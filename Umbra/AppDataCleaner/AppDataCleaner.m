#include <Foundation/Foundation.h>

#import "AppInfo.h"

BOOL isUUIDPathOf(NSString *path, NSString *parent);

NSString *clearAppData(AppInfo *app) {
    NSError *error = nil;

    if (app.containerURL &&
        isUUIDPathOf(app.containerURL.path, @"/private/var/mobile/Containers/Data/Application/") &&
        [NSFileManager.defaultManager fileExistsAtPath:app.containerURL.path]) {
        if (![NSFileManager.defaultManager removeItemAtURL:app.containerURL error:&error]) {
            return [NSString stringWithFormat:NSLocalizedString(
                                                  @"Failed to remove app data container:\n%@", nil),
                                              error.localizedDescription];
        }
    }
    return nil;
}
