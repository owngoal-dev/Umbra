#import "RHServicePorts.h"
#import "roothide.h"
#include <arpa/inet.h>
#include <errno.h>
#include <sys/socket.h>
#include <unistd.h>

extern int spawnRoot(NSString *path, NSArray *args, NSString **stdOut, NSString **stdErr);

static BOOL PortError(NSError **error, NSString *message) {
    if (error) {
        *error = [NSError errorWithDomain:@"wiki.qaq.umbra.serviceports"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey : message}];
    }
    return NO;
}

static NSString *ServiceLabel(NSString *service) {
    return @{
        @"openssh" : @"com.openssh.sshd",
        @"dropbear" : @"com.mkj.dropbear",
        @"frida" : @"re.frida.server"
    }[service];
}

static NSString *ServicePath(NSString *service) {
    NSString *label = ServiceLabel(service);
    return label ? jbroot([@"/Library/LaunchDaemons/" stringByAppendingFormat:@"%@.plist", label])
                 : nil;
}

static NSNumber *PortNumber(id value) {
    NSString *text = [value isKindOfClass:NSNumber.class] ? [value stringValue] : value;
    if (![text isKindOfClass:NSString.class] || !text.length || text.length > 5 ||
        [text rangeOfCharacterFromSet:[NSCharacterSet
                                          characterSetWithCharactersInString:@"0123456789"]
                                          .invertedSet]
                .location != NSNotFound) {
        return nil;
    }
    NSInteger port = text.integerValue;
    return port >= 1 && port <= 65535 ? @(port) : nil;
}

static NSNumber *EndpointPort(NSString *endpoint) {
    return PortNumber([endpoint componentsSeparatedByString:@":"].lastObject);
}

static NSString *ChangedEndpoint(NSString *endpoint, NSNumber *port) {
    NSRange colon = [endpoint rangeOfString:@":" options:NSBackwardsSearch];
    NSString *prefix =
        colon.location == NSNotFound ? @"" : [endpoint substringToIndex:colon.location + 1];
    return [prefix stringByAppendingString:port.stringValue];
}

// Only the port-bearing fields are changed; launch arguments and binding addresses stay intact.
static NSArray<NSNumber *> *ConfigPorts(NSMutableDictionary *config, NSString *service,
                                        NSArray<NSNumber *> *replacement) {
    NSArray *args = config[@"ProgramArguments"];
    if (![args isKindOfClass:NSArray.class]) {
        return nil;
    }
    for (id argument in args) {
        if (![argument isKindOfClass:NSString.class]) {
            return nil;
        }
    }
    NSMutableArray<NSNumber *> *ports = [NSMutableArray new];
    if ([service isEqualToString:@"openssh"]) {
        NSDictionary *sockets = config[@"Sockets"];
        if (![args containsObject:@"-i"] || ![sockets isKindOfClass:NSDictionary.class] ||
            !sockets.count) {
            return nil;
        }
        if (!sockets[@"SSHListener"] || sockets.count > 2 ||
            (sockets.count == 2 && !sockets[@"SSHListener2"]) ||
            (replacement && (replacement.count < 1 || replacement.count > 2))) {
            return nil;
        }
        NSArray *keys =
            sockets[@"SSHListener2"] ? @[ @"SSHListener", @"SSHListener2" ] : @[ @"SSHListener" ];
        NSMutableDictionary *changed = sockets.mutableCopy;
        for (NSString *key in keys) {
            NSDictionary *socket = sockets[key];
            if (![socket isKindOfClass:NSDictionary.class]) {
                return nil;
            }
            id value = socket[@"SockServiceName"];
            NSNumber *port = [value isEqual:@"ssh"] ? @22 : PortNumber(value);
            if (!port) {
                return nil;
            }
            if (replacement) {
                if (ports.count < replacement.count) {
                    NSMutableDictionary *updated = socket.mutableCopy;
                    updated[@"SockServiceName"] = replacement[ports.count].stringValue;
                    changed[key] = updated;
                } else {
                    [changed removeObjectForKey:key];
                }
            }
            [ports addObject:port];
        }
        if (replacement) {
            config[@"Sockets"] = changed;
        }
    } else if ([service isEqualToString:@"dropbear"]) {
        NSUInteger wrapper =
            [args indexOfObjectPassingTest:^BOOL(NSString *arg, NSUInteger index, BOOL *stop) {
                return [arg.lastPathComponent isEqualToString:@"dropbear-wrapper"];
            }];
        if (wrapper == NSNotFound || args.count != wrapper + 2 ||
            (replacement && replacement.count != 1)) {
            return nil;
        }
        NSNumber *port = EndpointPort(args.lastObject);
        if (!port) {
            return nil;
        }
        [ports addObject:port];
        if (replacement) {
            NSMutableArray *updated = args.mutableCopy;
            updated[wrapper + 1] = ChangedEndpoint(args.lastObject, replacement[0]);
            config[@"ProgramArguments"] = updated;
        }
    } else if ([service isEqualToString:@"frida"]) {
        if (replacement && replacement.count != 1) {
            return nil;
        }
        BOOL knownProgram = NO;
        NSString *endpoint = @"127.0.0.1:27042";
        NSUInteger option = NSNotFound;
        BOOL joined = NO;
        for (NSUInteger index = 0; index < args.count; index++) {
            NSString *arg = args[index];
            if ([arg.lastPathComponent isEqualToString:@"frida-server-wrapper"] ||
                [arg.lastPathComponent isEqualToString:@"frida-server"]) {
                knownProgram = YES;
            }
            if ([arg isEqualToString:@"-l"] || [arg isEqualToString:@"--listen"] ||
                [arg hasPrefix:@"--listen="]) {
                if (option != NSNotFound) {
                    return nil;
                }
                option = index;
                joined = [arg hasPrefix:@"--listen="];
                if (joined) {
                    endpoint = [arg substringFromIndex:9];
                } else if (++index < args.count) {
                    endpoint = args[index];
                } else {
                    return nil;
                }
            }
        }
        if (!knownProgram || [endpoint rangeOfString:@":"].location == NSNotFound) {
            return nil;
        }
        NSNumber *port = EndpointPort(endpoint);
        if (!port) {
            return nil;
        }
        [ports addObject:port];
        if (replacement) {
            NSMutableArray *updated = args.mutableCopy;
            NSString *address = ChangedEndpoint(endpoint, replacement[0]);
            if (option == NSNotFound) {
                [updated addObjectsFromArray:@[ @"--listen", address ]];
            } else if (joined) {
                updated[option] = [@"--listen=" stringByAppendingString:address];
            } else {
                updated[option + 1] = address;
            }
            config[@"ProgramArguments"] = updated;
        }
    } else {
        return nil;
    }
    return ports;
}

static NSMutableDictionary *ReadConfig(NSString *service, NSData **original, NSError **error) {
    NSString *path = ServicePath(service);
    if (!path || ![[RHServicePorts installedServices] containsObject:service]) {
        PortError(error, NSLocalizedString(@"Service is not installed.", nil));
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data) {
        return nil;
    }
    id config = [NSPropertyListSerialization propertyListWithData:data
                                                          options:NSPropertyListMutableContainers
                                                           format:nil
                                                            error:error];
    if (![config isKindOfClass:NSMutableDictionary.class] ||
        ![config[@"Label"] isEqual:ServiceLabel(service)]) {
        PortError(error, NSLocalizedString(@"Unsupported service configuration.", nil));
        return nil;
    }
    if (original) {
        *original = data;
    }
    return config;
}

static BOOL WriteConfig(NSData *data, NSString *path, NSDictionary *attributes, NSError **error) {
    NSString *temporary = [path stringByAppendingFormat:@".%@.tmp", NSUUID.UUID.UUIDString];
    NSFileManager *manager = NSFileManager.defaultManager;
    NSDictionary *permissions = @{
        NSFilePosixPermissions : attributes[NSFilePosixPermissions] ?: @0644,
        NSFileOwnerAccountID : attributes[NSFileOwnerAccountID] ?: @0,
        NSFileGroupOwnerAccountID : attributes[NSFileGroupOwnerAccountID] ?: @0
    };
    if (![manager createFileAtPath:temporary contents:data attributes:permissions]) {
        return PortError(error, NSLocalizedString(@"Could not save service ports.", nil));
    }
    if (rename(temporary.fileSystemRepresentation, path.fileSystemRepresentation) != 0) {
        int code = errno;
        [manager removeItemAtPath:temporary error:nil];
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil];
        }
        return NO;
    }
    return YES;
}

static BOOL PortIsFree(NSNumber *port) {
    for (NSNumber *family in @[ @(AF_INET), @(AF_INET6) ]) {
        int descriptor = socket(family.intValue, SOCK_STREAM, 0);
        if (descriptor < 0) {
            return NO;
        }
        int one = 1;
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
        int result;
        if (family.intValue == AF_INET) {
            struct sockaddr_in address = {.sin_family = AF_INET,
                                          .sin_port = htons(port.unsignedShortValue),
                                          .sin_addr.s_addr = INADDR_ANY};
            result = bind(descriptor, (struct sockaddr *)&address, sizeof(address));
        } else {
            setsockopt(descriptor, IPPROTO_IPV6, IPV6_V6ONLY, &one, sizeof(one));
            struct sockaddr_in6 address = {.sin6_family = AF_INET6,
                                           .sin6_port = htons(port.unsignedShortValue),
                                           .sin6_addr = IN6ADDR_ANY_INIT};
            result = bind(descriptor, (struct sockaddr *)&address, sizeof(address));
        }
        close(descriptor);
        if (result != 0) {
            return NO;
        }
    }
    return YES;
}

static int LaunchControl(NSArray<NSString *> *arguments) {
    return spawnRoot(jbroot(@"/usr/bin/launchctl"), arguments, nil, nil);
}

static BOOL PortsAreListening(NSArray<NSNumber *> *ports) {
    for (NSNumber *port in ports) {
        int descriptor = socket(AF_INET, SOCK_STREAM, 0);
        if (descriptor < 0) {
            return NO;
        }
        struct sockaddr_in address = {.sin_family = AF_INET,
                                      .sin_port = htons(port.unsignedShortValue),
                                      .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
        BOOL connected = connect(descriptor, (struct sockaddr *)&address, sizeof(address)) == 0;
        close(descriptor);
        if (!connected) {
            return NO;
        }
    }
    return YES;
}

@implementation RHServicePorts

+ (NSArray<NSString *> *)installedServices {
    NSString *status = [NSString stringWithContentsOfFile:jbroot(@"/var/lib/dpkg/status")
                                                 encoding:NSUTF8StringEncoding
                                                    error:nil];
    NSMutableSet *packages = [NSMutableSet new];
    for (NSString *paragraph in [status componentsSeparatedByString:@"\n\n"]) {
        NSString *package = nil;
        BOOL installed = NO;
        for (NSString *line in [paragraph componentsSeparatedByString:@"\n"]) {
            if ([line hasPrefix:@"Package: "]) {
                package = [line substringFromIndex:9];
            }
            if ([line hasPrefix:@"Status: "] && [line hasSuffix:@" ok installed"]) {
                installed = YES;
            }
        }
        if (package && installed) {
            [packages addObject:package];
        }
    }
    NSMutableArray *services = [NSMutableArray new];
    if ([packages containsObject:@"openssh-server"] ||
        ([packages containsObject:@"openssh"] &&
         [NSFileManager.defaultManager fileExistsAtPath:ServicePath(@"openssh")])) {
        [services addObject:@"openssh"];
    }
    if ([packages containsObject:@"dropbear"]) {
        [services addObject:@"dropbear"];
    }
    if ([packages containsObject:@"re.frida.server"] ||
        [packages containsObject:@"re.frida.server64"]) {
        [services addObject:@"frida"];
    }
    return services;
}

+ (NSNumber *)opensshBackupPort {
    NSDictionary *socket =
        [NSDictionary dictionaryWithContentsOfFile:[ServicePath(@"openssh")
                                                       stringByAppendingString:@".backup-socket"]];
    return [socket isKindOfClass:NSDictionary.class]
               ? (PortNumber(socket[@"SockServiceName"]) ?: @2222)
               : @2222;
}

+ (NSArray<NSNumber *> *)portsForService:(NSString *)service error:(NSError **)error {
    NSMutableDictionary *config = ReadConfig(service, nil, error);
    if (!config) {
        return nil;
    }
    NSArray *ports = ConfigPorts(config, service, nil);
    if (!ports) {
        PortError(error, NSLocalizedString(@"Unsupported service configuration.", nil));
    }
    return ports;
}

+ (BOOL)setPorts:(NSArray<NSNumber *> *)ports
      forService:(NSString *)service
           error:(NSError **)error {
    @synchronized(self) {
        NSMutableSet *unique = [NSMutableSet new];
        NSMutableArray *validated = [NSMutableArray new];
        for (id port in ports) {
            NSNumber *number = PortNumber(port);
            if (!number) {
                return PortError(error, NSLocalizedString(@"Enter a port from 1 to 65535.", nil));
            }
            if ([unique containsObject:number]) {
                return PortError(error, NSLocalizedString(@"Each port must be different.", nil));
            }
            [unique addObject:number];
            [validated addObject:number];
        }
        ports = validated;
        if (!ports.count) {
            return PortError(error, NSLocalizedString(@"Enter a port from 1 to 65535.", nil));
        }
        if (geteuid() != 0 || getegid() != 0) {
            NSString *message = nil;
            NSString *values = [[ports valueForKey:@"stringValue"] componentsJoinedByString:@","];
            int result = spawnRoot(NSBundle.mainBundle.executablePath,
                                   @[ @"setServicePorts", service, values ], nil, &message);
            return result == 0 ||
                   PortError(error, message.length
                                        ? message
                                        : NSLocalizedString(@"Could not save service ports.", nil));
        }
        NSData *original = nil;
        NSMutableDictionary *config = ReadConfig(service, &original, error);
        if (!config) {
            return NO;
        }
        NSArray *oldPorts = ConfigPorts(config, service, nil);
        if (!oldPorts) {
            return PortError(error, NSLocalizedString(@"Unsupported service configuration.", nil));
        }
        if ([oldPorts isEqualToArray:ports]) {
            return YES;
        }
        if ([service isEqualToString:@"openssh"]) {
            NSMutableDictionary *sockets = [config[@"Sockets"] mutableCopy];
            NSDictionary *secondary = sockets[@"SSHListener2"];
            if (ports.count == 2 && !secondary) {
                id saved = [NSDictionary
                    dictionaryWithContentsOfFile:[ServicePath(@"openssh")
                                                     stringByAppendingString:@".backup-socket"]];
                sockets[@"SSHListener2"] =
                    [saved isKindOfClass:NSDictionary.class] ? saved : sockets[@"SSHListener"];
                config[@"Sockets"] = sockets;
            }
        }
        if (!ConfigPorts(config, service, ports)) {
            return PortError(error, NSLocalizedString(@"Unsupported service configuration.", nil));
        }
        for (NSNumber *port in ports) {
            if (![oldPorts containsObject:port] && !PortIsFree(port)) {
                return PortError(error,
                                 [NSString stringWithFormat:NSLocalizedString(
                                                                @"Port %@ is already in use.", nil),
                                                            port]);
            }
        }
        NSString *path = ServicePath(service);
        NSString *backup = [path stringByAppendingString:@".umbra-backup"];
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path
                                                                                  error:error];
        if (!attributes) {
            return NO;
        }
        NSData *data =
            [NSPropertyListSerialization dataWithPropertyList:config
                                                       format:NSPropertyListXMLFormat_v1_0
                                                      options:0
                                                        error:error];
        if (!data || !WriteConfig(original, backup, attributes, error)) {
            return NO;
        }
        if ([service isEqualToString:@"openssh"] && oldPorts.count == 2 && ports.count == 1) {
            NSDictionary *previous = [NSPropertyListSerialization propertyListWithData:original
                                                                               options:0
                                                                                format:nil
                                                                                 error:error];
            NSData *socket = [NSPropertyListSerialization
                dataWithPropertyList:previous[@"Sockets"][@"SSHListener2"]
                              format:NSPropertyListXMLFormat_v1_0
                             options:0
                               error:error];
            if (!socket || !WriteConfig(socket, [path stringByAppendingString:@".backup-socket"],
                                        attributes, error)) {
                return NO;
            }
        }
        BOOL loaded =
            LaunchControl(
                @[ @"print", [@"system/" stringByAppendingString:ServiceLabel(service)] ]) == 0;
        if (!WriteConfig(data, path, attributes, error)) {
            return NO;
        }
        if (!loaded) {
            return YES;
        }
        BOOL restarted =
            LaunchControl(@[ @"unload", path ]) == 0 && LaunchControl(@[ @"load", path ]) == 0;
        for (NSUInteger attempt = 0; restarted && attempt < 80; attempt++) {
            if (PortsAreListening(ports)) {
                return YES;
            }
            [NSThread sleepForTimeInterval:0.1];
        }
        if (!WriteConfig(original, path, attributes, error)) {
            return PortError(
                error, NSLocalizedString(@"Could not restore the original configuration.", nil));
        }
        LaunchControl(@[ @"unload", path ]);
        if (LaunchControl(@[ @"load", path ]) != 0) {
            return PortError(
                error, NSLocalizedString(
                           @"Could not restore the service. Restart it in your terminal.", nil));
        }
        return PortError(
            error,
            NSLocalizedString(
                @"Could not restart the service. The original configuration was restored.", nil));
    }
}
@end
