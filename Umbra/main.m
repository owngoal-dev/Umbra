#import <dlfcn.h>
#import <spawn.h>
#import <objc/message.h>
#import <UIKit/UIKit.h>
#import "AppInfo.h"
#import "RHServicePorts.h"

extern const char **environ;

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t *__restrict, uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t *__restrict, uid_t);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t *__restrict, uid_t);

int spawn(const char *path, const char **argv, const char **envp, void (^std_out)(char *, int),
          void (^std_err)(char *, int)) {

    __block pid_t pid = 0;
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);

    posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);

    posix_spawn_file_actions_t action;
    posix_spawn_file_actions_init(&action);

    int outPipe[2];
    pipe(outPipe);
    posix_spawn_file_actions_addclose(&action, outPipe[0]);
    posix_spawn_file_actions_adddup2(&action, outPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&action, outPipe[1]);

    int errPipe[2];
    pipe(errPipe);
    posix_spawn_file_actions_addclose(&action, errPipe[0]);
    posix_spawn_file_actions_adddup2(&action, errPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&action, errPipe[1]);

    dispatch_semaphore_t lock = dispatch_semaphore_create(0);

    dispatch_queue_t queue = dispatch_queue_create("spawnPipeQueue", DISPATCH_QUEUE_CONCURRENT);

    dispatch_source_t stdOutSource =
        dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, outPipe[0], 0, queue);
    dispatch_source_t stdErrSource =
        dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, errPipe[0], 0, queue);

    int outFD = outPipe[0];
    int errFD = errPipe[0];

    dispatch_source_set_cancel_handler(stdOutSource, ^{
        close(outFD);
        dispatch_semaphore_signal(lock);
    });
    dispatch_source_set_cancel_handler(stdErrSource, ^{
        close(errFD);
        dispatch_semaphore_signal(lock);
    });

    dispatch_source_set_event_handler(stdOutSource, ^{
        char buffer[BUFSIZ] = {0};
        ssize_t bytes = read(outFD, buffer, sizeof(buffer) - 1);
        if (bytes <= 0) {
            dispatch_source_cancel(stdOutSource);
            return;
        }
        if (std_out)
            std_out(buffer, bytes);
    });
    dispatch_source_set_event_handler(stdErrSource, ^{
        char buffer[BUFSIZ] = {0};
        ssize_t bytes = read(errFD, buffer, sizeof(buffer) - 1);
        if (bytes <= 0) {
            dispatch_source_cancel(stdErrSource);
            return;
        }
        if (std_err)
            std_err(buffer, bytes);
    });

    dispatch_resume(stdOutSource);
    dispatch_resume(stdErrSource);

    int spawnError = posix_spawn(&pid, path, &action, &attr, argv, envp);

    posix_spawnattr_destroy(&attr);
    posix_spawn_file_actions_destroy(&action);

    close(outPipe[1]);
    close(errPipe[1]);

    if (spawnError != 0) {
        dispatch_source_cancel(stdOutSource);
        dispatch_source_cancel(stdErrSource);
        return spawnError;
    }

    dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
    dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);

    int status = 0;
    while (waitpid(pid, &status, 0) != -1) {
        if (WIFSIGNALED(status)) {
            return 128 + WTERMSIG(status);
        } else if (WIFEXITED(status)) {
            return WEXITSTATUS(status);
        }
    };
    return -1;
}

int spawnRoot(NSString *path, NSArray *args, NSString **stdOut, NSString **stdErr) {

    NSMutableArray *argsM = args.mutableCopy ?: [NSMutableArray new];
    [argsM insertObject:path atIndex:0];

    NSUInteger argCount = [argsM count];
    char **argsC = (char **)malloc((argCount + 1) * sizeof(char *));

    for (NSUInteger i = 0; i < argCount; i++) {
        argsC[i] = strdup([[argsM objectAtIndex:i] UTF8String]);
    }
    argsC[argCount] = NULL;

    NSMutableData *outData = stdOut ? [NSMutableData new] : nil;
    NSMutableData *errData = stdErr ? [NSMutableData new] : nil;
    int retval = spawn(
        path.fileSystemRepresentation, argsC, environ,
        ^(char *bytes, int length) {
            [outData appendBytes:bytes length:length];
        },
        ^(char *bytes, int length) {
            [errData appendBytes:bytes length:length];
        });

    if (stdOut)
        *stdOut = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding] ?: @"";
    if (stdErr)
        *stdErr = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] ?: @"";

    for (NSUInteger i = 0; i < argCount; i++) {
        free(argsC[i]);
    }
    free(argsC);

    return retval;
}

BOOL isUUIDPathOf(NSString *path, NSString *parent) {
    if (!path || !parent)
        return NO;

    const char *_path = path.UTF8String;
    const char *_parent = parent.UTF8String;

    char rp[PATH_MAX];
    if (!realpath(_path, rp))
        return NO;

    char rpp[PATH_MAX + 1];
    if (!realpath(_parent, rpp))
        return NO;

    size_t rpplen = strlen(rpp);

    if (rpp[rpplen] != '/') {
        strcat(rpp, "/");
        rpplen++;
    }

    if (strncmp(rp, rpp, rpplen) != 0)
        return NO;

    char *p1 = rp + rpplen;
    char *p2 = strchr(p1, '/');
    if (!p2)
        p2 = rp + strlen(rp);

    if ((p2 - p1) != (sizeof("xxxxxxxx-xxxx-xxxx-yxxx-xxxxxxxxxxxx") - 1))
        return NO;

    return YES;
}

#include <sys/sysctl.h>

int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

void killAllForBundle(const char *bundlePath) {

    char realBundlePath[PATH_MAX + 1];
    if (!realpath(bundlePath, realBundlePath))
        return;

    size_t realBundlePathLen = strlen(realBundlePath);
    if (realBundlePath[realBundlePathLen] != '/') {
        strcat(realBundlePath, "/");
        realBundlePathLen++;
    }

    int mib[3] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL};
    struct kinfo_proc *info;
    size_t length;
    size_t count;

    if (sysctl(mib, 3, NULL, &length, NULL, 0) < 0)
        return;
    if (!(info = malloc(length)))
        return;
    if (sysctl(mib, 3, info, &length, NULL, 0) < 0) {
        free(info);
        return;
    }
    count = length / sizeof(struct kinfo_proc);
    for (int i = 0; i < count; i++) {
        pid_t pid = info[i].kp_proc.p_pid;
        if (pid == 0) {
            continue;
        }

        char executablePath[PATH_MAX];
        if (proc_pidpath(pid, executablePath, sizeof(executablePath)) > 0) {
            char realExecutablePath[PATH_MAX];
            if (realpath(executablePath, realExecutablePath) &&
                strncmp(realExecutablePath, realBundlePath, realBundlePathLen) == 0) {
                kill(pid, SIGKILL);
            }
        }
    }
    free(info);
}

NSString *RootUserClearAppData(AppInfo *app) {
    NSString *error = nil;
    NSString *result = nil;
    int ret = spawnRoot(NSBundle.mainBundle.executablePath,
                        @[ @"clearAppData", app.bundleIdentifier ], &result, &error);
    if (ret != 0) {
        return error;
    }
    return nil;
}

BOOL RootUserRemoveItemAtPath(NSString *path) {
    NSString *error = nil;
    NSString *result = nil;
    int ret = spawnRoot(NSBundle.mainBundle.executablePath, @[ @"removeItemAtPath", path ], &result,
                        &error);
    if (ret != 0) {
        return NO;
    }
    return YES;
}

BOOL RootUserGetDirectoryContents(NSString *path, NSString *cacheFile) {
    NSString *error = nil;
    NSString *result = nil;
    int ret = spawnRoot(NSBundle.mainBundle.executablePath,
                        @[ @"getDirectoryContents", path, cacheFile ], &result, &error);
    if (ret != 0) {
        return NO;
    }
    return YES;
}

int main(int argc, char *argv[]) {

    if (argc >= 2 &&
        (strcmp(argv[1], "servicePorts") == 0 || strcmp(argv[1], "setServicePorts") == 0)) {
        @autoreleasepool {
            NSError *error = nil;
            if (argc == 3 && strcmp(argv[1], "servicePorts") == 0) {
                NSArray *ports = [RHServicePorts portsForService:@(argv[2]) error:&error];
                if (ports) {
                    NSData *data = [NSJSONSerialization dataWithJSONObject:ports
                                                                   options:0
                                                                     error:&error];
                    if (data) {
                        fwrite(data.bytes, 1, data.length, stdout);
                        fputc('\n', stdout);
                        return 0;
                    }
                }
            } else if (argc == 4 && strcmp(argv[1], "setServicePorts") == 0) {
                NSArray *ports = [@(argv[3]) componentsSeparatedByString:@","];
                if ([RHServicePorts setPorts:ports forService:@(argv[2]) error:&error]) {
                    return 0;
                }
            }
            fprintf(stderr, "%s\n",
                    (error.localizedDescription ?: @"Invalid service port request").UTF8String);
            return 1;
        }
    }

    if (argc >= 2) {
        if (argc == 3 && strcmp(argv[1], "removeItemAtPath") == 0) {
            NSError *err;
            if (![NSFileManager.defaultManager removeItemAtPath:@(argv[2]) error:&err]) {
                fprintf(stderr, "%s", err.description.UTF8String);
                return -1;
            }
            return 0;
        }
        if (argc == 4 && strcmp(argv[1], "getDirectoryContents") == 0) {
            NSArray *GetDirectoryContents(NSString * path);
            NSArray *contents = GetDirectoryContents(@(argv[2]));
            if (!contents) {
                return -1;
            }
            if (![contents writeToFile:@(argv[3]) atomically:YES]) {
                return -2;
            }
            return 0;
        }
        if (argc == 3 && strcmp(argv[1], "clearAppData") == 0) {
            AppInfo *app = [AppInfo appWithBundleIdentifier:@(argv[2])];
            NSString *clearAppData(AppInfo * app);
            NSString *error = clearAppData(app);
            if (error) {
                fprintf(stderr, "%s", error.UTF8String);
                return -1;
            }
            return 0;
        }
    }

    NSString *appDelegateClassName;
    @autoreleasepool {
        appDelegateClassName = @"AppDelegate";
    }
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}
