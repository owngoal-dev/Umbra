#import "RHBackend.h"
#import "RHServicePorts.h"
#import "NSJSONSerialization+Comments.h"
#import "VarCleanRules.h"
#import "roothide.h"
#import <CFNetwork/CFNetwork.h>
#import <IOKit/IOKitLib.h>
#include <arpa/inet.h>
#include <spawn.h>
#include <sys/mount.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>
#include <zlib.h>

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
@end

BOOL isUUIDPathOf(NSString *path, NSString *parent);
void killAllForBundle(const char *bundlePath);
NSString *clearAppData(AppInfo *app);
NSString *RootUserClearAppData(AppInfo *app);

static BOOL RHFail(NSError **error, NSString *message) {
    if (error) {
        *error = [NSError errorWithDomain:@"com.umbra.manager"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey : message}];
    }
    return NO;
}

static BOOL RHWriteDictionary(NSDictionary *dictionary, NSString *path, NSError **error) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:dictionary
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0
                                                               error:error];
    return data && [data writeToFile:path options:NSDataWritingAtomic error:error];
}

static BOOL RHPortIsOpen(uint16_t port) {
    int descriptor = socket(AF_INET, SOCK_STREAM, 0);
    if (descriptor < 0) {
        return NO;
    }
    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = inet_addr("127.0.0.1");
    address.sin_port = htons(port);
    BOOL connected = connect(descriptor, (struct sockaddr *)&address, sizeof(address)) == 0;
    close(descriptor);
    return connected;
}

@implementation RHBackend

+ (BOOL)prepareWithError:(NSError **)error {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSString *directory = jbroot(@"/var/mobile/Library/RootHide");
    if (![manager fileExistsAtPath:directory]) {
        NSDictionary *attributes = @{
            NSFilePosixPermissions : @0755,
            NSFileOwnerAccountID : @501,
            NSFileGroupOwnerAccountID : @501
        };
        if (![manager createDirectoryAtPath:directory
                withIntermediateDirectories:YES
                                 attributes:attributes
                                      error:error]) {
            return NO;
        }
    }

    NSString *path = [NSBundle.mainBundle pathForResource:@"VarCleanRules" ofType:@"json"];
    if (!path) {
        return RHFail(error,
                      NSLocalizedString(@"The bundled cleaning rules could not be found.", nil));
    }
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data) {
        return NO;
    }
    if (crc32(0, data.bytes, (uInt)data.length) != VARCLEANRULESHASH) {
        return RHFail(error,
                      NSLocalizedString(@"The bundled cleaning rules failed verification.", nil));
    }
    id rules = [NSJSONSerialization JSONObjectWithCommentedData:data options:0 error:error];
    if (!rules) {
        return NO;
    }
    if (![rules isKindOfClass:NSDictionary.class]) {
        return RHFail(error,
                      NSLocalizedString(@"The cleaning rules are not a valid dictionary.", nil));
    }
    if (!RHWriteDictionary(rules, [directory stringByAppendingPathComponent:@"varCleanRules.plist"],
                           error)) {
        return NO;
    }
    NSString *customPath = self.customRulesPath;
    if (![manager fileExistsAtPath:customPath] && !RHWriteDictionary(@{}, customPath, error)) {
        return NO;
    }
    if (![self configurationForKey:@"urlSchemeReplacements"]) {
        return [self setConfiguration:@{@"filza" : @{@"target" : @"fila", @"enabled" : @NO}}
                               forKey:@"urlSchemeReplacements"
                                error:error];
    }
    return YES;
}

+ (id)configurationForKey:(NSString *)key {
    @synchronized(self) {
        NSDictionary *configuration = [NSDictionary
            dictionaryWithContentsOfFile:jbroot(
                                             @"/var/mobile/Library/RootHide/RootHideConfig.plist")];
        return configuration[key];
    }
}

+ (BOOL)setConfiguration:(id)value forKey:(NSString *)key error:(NSError **)error {
    @synchronized(self) {
        NSString *path = jbroot(@"/var/mobile/Library/RootHide/RootHideConfig.plist");
        NSMutableDictionary *configuration =
            [NSMutableDictionary dictionaryWithContentsOfFile:path];
        if (!configuration && [NSFileManager.defaultManager fileExistsAtPath:path]) {
            return RHFail(error, NSLocalizedString(
                                     @"The saved configuration is not a valid dictionary.", nil));
        }
        configuration = configuration ?: [NSMutableDictionary new];
        configuration[key] = value;
        return RHWriteDictionary(configuration, path, error);
    }
}

+ (NSArray<AppInfo *> *)installedApps {
    NSMutableArray<AppInfo *> *applications = [NSMutableArray new];
    for (id proxy in LSApplicationWorkspace.defaultWorkspace.allInstalledApplications) {
        AppInfo *app = [AppInfo appWithPrivateProxy:proxy];
        if (!app.isHiddenApp && ![app.bundleIdentifier hasPrefix:@"com.apple."] &&
            isUUIDPathOf(app.bundleURL.path, @"/private/var/containers/Bundle/Application/")) {
            [applications addObject:app];
        }
    }
    return applications;
}

+ (NSString *)relaxinMarketingVersion {
    NSString *identifier = [NSString stringWithContentsOfFile:jbroot(@"/basebin/.AppIdentifier")
                                                     encoding:NSUTF8StringEncoding
                                                        error:nil];
    identifier = [identifier
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!identifier.length) {
        return nil;
    }
    NSURL *bundleURL = [AppInfo appWithBundleIdentifier:identifier].bundleURL;
    if (!bundleURL) {
        return nil;
    }
    NSDictionary *info = [NSDictionary
        dictionaryWithContentsOfURL:[bundleURL URLByAppendingPathComponent:@"Info.plist"]];
    NSString *executable = info[@"CFBundleExecutable"];
    if (![@"Relaxin" isEqual:executable] && ![@"RelaxinLite" isEqual:executable]) {
        return nil;
    }
    id version = info[@"CFBundleShortVersionString"];
    return [version isKindOfClass:NSString.class] ? version : nil;
}

+ (NSString *)blacklistUnavailableReason {
    if (![[self configurationForKey:@"blacklistDisabled"] boolValue]) {
        return nil;
    }
    NSFileManager *manager = NSFileManager.defaultManager;
    if ([manager fileExistsAtPath:jbroot(@"/.bootstrapped")] ||
        [manager fileExistsAtPath:jbroot(@"/.thebootstrapped")]) {
        return NSLocalizedString(@"Apps are blacklisted by default in current environment, just "
                                 @"disable tweaks for this app in the AppList of Bootstrap.",
                                 nil);
    }
    return NSLocalizedString(@"Blacklist is not supported in current environment.", nil);
}

+ (NSString *)blacklistRejectionForApp:(AppInfo *)app {
    NSFileManager *manager = NSFileManager.defaultManager;
    if ([manager fileExistsAtPath:jbroot(@"/.thebootstrapped")] &&
        ([manager
             fileExistsAtPath:[app.bundleURL.path stringByAppendingString:@"/../.appbackup"]] ||
         [manager
             fileExistsAtPath:[app.bundleURL.path stringByAppendingPathExtension:@"appbackup"]] ||
         [manager
             fileExistsAtPath:[app.bundleURL.path stringByAppendingPathComponent:@".jbroot"]])) {
        return NSLocalizedString(@"This app is tweaked by Bootstrap, please disable tweak for it "
                                 @"in the AppList of Bootstrap first.",
                                 nil);
    }
    return nil;
}

+ (BOOL)requiresCompatibilityWarning {
#ifdef __arm64e__
    return [[self configurationForKey:@"spinlockFixApplied"] boolValue] &&
           NSProcessInfo.processInfo.operatingSystemVersion.majorVersion == 15;
#else
    return NO;
#endif
}

+ (BOOL)setBlacklisted:(BOOL)blacklisted forApp:(AppInfo *)app error:(NSError **)error {
    if (!app.bundleIdentifier.length || !app.bundleURL.path.length) {
        return RHFail(error, NSLocalizedString(@"The selected app is no longer available.", nil));
    }
    NSString *reason = self.blacklistUnavailableReason ?: [self blacklistRejectionForApp:app];
    if (reason) {
        return RHFail(error, reason);
    }
    @synchronized(self) {
        id stored = [self configurationForKey:@"appconfig"];
        if (stored && ![stored isKindOfClass:NSDictionary.class]) {
            return RHFail(error, NSLocalizedString(
                                     @"The saved configuration is not a valid dictionary.", nil));
        }
        NSMutableDictionary *configuration = [stored mutableCopy] ?: [NSMutableDictionary new];
        configuration[app.bundleIdentifier] = @(blacklisted);
        if (![self setConfiguration:configuration forKey:@"appconfig" error:error]) {
            return NO;
        }
    }
    killAllForBundle(app.bundleURL.path.UTF8String);
    return YES;
}

+ (NSString *)clearDataForApp:(AppInfo *)app {
    if (!app.bundleIdentifier.length || !app.bundleURL.path.length) {
        return NSLocalizedString(@"The selected app is no longer available.", nil);
    }
    killAllForBundle(app.bundleURL.path.UTF8String);
    return geteuid() == 0 && getegid() == 0 ? clearAppData(app) : RootUserClearAppData(app);
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)startupWarnings {
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *warnings = [NSMutableArray new];
    NSFileManager *manager = NSFileManager.defaultManager;
    NSMutableString *bootHash = [NSMutableString new];
    io_registry_entry_t entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/chosen");
    if (entry) {
        CFTypeRef hash =
            IORegistryEntryCreateCFProperty(entry, CFSTR("boot-manifest-hash"), NULL, 0);
        if (hash && CFGetTypeID(hash) == CFDataGetTypeID()) {
            const UInt8 *bytes = CFDataGetBytePtr(hash);
            for (CFIndex index = 0; index < CFDataGetLength(hash); index++) {
                [bootHash appendFormat:@"%02X", bytes[index]];
            }
        }
        if (hash) {
            CFRelease(hash);
        }
        IOObjectRelease(entry);
    }
    NSString *bootPath =
        bootHash.length ? [@"/private/preboot" stringByAppendingPathComponent:bootHash] : nil;
    if (bootPath && [manager fileExistsAtPath:bootPath]) {
        NSMutableSet *prebootContents = [NSMutableSet
            setWithArray:[manager contentsOfDirectoryAtPath:@"/private/preboot" error:nil] ?: @[]];
        [prebootContents minusSet:[NSSet setWithArray:@[
                             @".fseventsd", @"active", @"cryptex1", @"Cryptexes", bootHash
                         ]]];
        NSMutableSet *bootContents = [NSMutableSet
            setWithArray:[manager contentsOfDirectoryAtPath:bootPath error:nil] ?: @[]];
        [bootContents
            minusSet:[NSSet setWithArray:@[
                @"AppleInternal", @"private", @"System", @"usr", @"LocalPolicy.cryptex1.img4"
            ]]];
        NSArray *unknownContents =
            [[prebootContents.allObjects arrayByAddingObjectsFromArray:bootContents.allObjects]
                sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
        if (unknownContents.count) {
            [warnings addObject:@{
                @"title" : NSLocalizedString(@"Legacy rootless jailbreak(s)", nil),
                @"message" : [NSString
                    stringWithFormat:@"%@\n\n%@", [unknownContents componentsJoinedByString:@"\n"],
                                     NSLocalizedString(
                                         @"*WARNING*: Don't touch any other files in "
                                         @"/private/preboot/, otherwise it will cause bootloop",
                                         nil)]
            }];
            pid_t pid = 0;
            char *arguments[] = {"/sbin/mount", "-u", "-w", "/private/preboot", NULL};
            posix_spawn(&pid, arguments[0], NULL, NULL, arguments, NULL);
            if (pid > 0) {
                int status = 0;
                waitpid(pid, &status, 0);
            }
        }
    } else {
        [warnings addObject:@{
            @"title" : NSLocalizedString(@"Unknown preboot system", nil),
            @"message" : bootHash
        }];
    }

    NSArray *defaultMounts = @[
        @"/usr/standalone/firmware", @"/System/Library/Pearl/ReferenceFrames",
        @"/System/Library/Caches/com.apple.factorydata"
    ];
    NSMutableArray<NSString *> *unknownMounts = [NSMutableArray new];
    struct statfs *mounts = NULL;
    int count = getmntinfo(&mounts, 0);
    for (int index = 0; index < count; index++) {
        if (strcmp(mounts[index].f_fstypename, "bindfs") == 0 &&
            ![defaultMounts containsObject:@(mounts[index].f_mntonname)]) {
            [unknownMounts addObject:@(mounts[index].f_mntonname)];
        }
    }
    if (unknownMounts.count) {
        [warnings addObject:@{
            @"title" : NSLocalizedString(@"Unknown Bindfs Mount(s)", nil),
            @"message" : [unknownMounts componentsJoinedByString:@"\n"]
        }];
    }
    NSArray *installedServices = RHServicePorts.installedServices;
    NSArray *serviceIDs = @[ @"openssh", @"dropbear", @"frida" ];
    NSArray *titles = @[
        NSLocalizedString(@"SSH Server", nil), NSLocalizedString(@"Dropbear", nil),
        NSLocalizedString(@"Frida Server", nil)
    ];
    NSArray *messages = @[
        NSLocalizedString(@"SSH Server has been installed, you can uninstall it via Sileo/Zebra.",
                          nil),
        NSLocalizedString(@"Dropbear has been installed, you can uninstall it via Sileo/Zebra.",
                          nil),
        NSLocalizedString(@"Frida Server has been installed, you can uninstall it via Sileo/Zebra.",
                          nil)
    ];
    NSArray *checkPorts = @[ @[ @22, @2222 ], @[ @44 ], @[ @27042 ] ];
    for (NSUInteger index = 0; index < serviceIDs.count; index++) {
        NSString *service = serviceIDs[index];
        BOOL active = NO;
        for (NSNumber *port in checkPorts[index]) {
            if (RHPortIsOpen(port.unsignedShortValue)) {
                active = YES;
                break;
            }
        }
        if (active) {
            NSMutableDictionary *finding =
                [@{@"title" : titles[index], @"message" : messages[index]} mutableCopy];
            if ([installedServices containsObject:service]) {
                finding[@"service"] = service;
            }
            [warnings addObject:finding];
        }
    }
    NSDictionary *proxySettings = CFBridgingRelease(CFNetworkCopySystemProxySettings());
    if ([proxySettings[(__bridge NSString *)kCFNetworkProxiesHTTPEnable] boolValue]) {
        [warnings addObject:@{
            @"title" : NSLocalizedString(@"VPN or Proxy", nil),
            @"message" : NSLocalizedString(
                @"Some apps may refuse to run because a VPN/Proxy is enabled.", nil)
        }];
    }
    return warnings;
}

+ (NSString *)customRulesPath {
    return jbroot(@"/var/mobile/Library/RootHide/varCleanRules-custom.plist");
}

+ (void)cleanOwnApplicationFiles {
    NSString *identifier = NSBundle.mainBundle.bundleIdentifier;
    if (!identifier.length) {
        return;
    }
    NSArray<NSArray<NSString *> *> *paths = @[
        @[ @"Library/Preferences", @".plist" ], @[ @"Library/Application Support/Containers", @"" ],
        @[ @"Library/SplashBoard/Snapshots", @"" ], @[ @"Library/Caches", @"" ],
        @[ @"Library/Saved Application State", @".savedState" ], @[ @"Library/WebKit", @"" ],
        @[ @"Library/Cookies", @".binarycookies" ], @[ @"Library/HTTPStorages", @"" ]
    ];
    for (NSArray<NSString *> *path in paths) {
        NSString *file = [[@"/var/mobile" stringByAppendingPathComponent:path[0]]
            stringByAppendingPathComponent:[identifier stringByAppendingString:path[1]]];
        [NSFileManager.defaultManager removeItemAtPath:file error:nil];
    }
}

@end
