#import "UMBInstalledAppInfo.h"

#import <Foundation/Foundation.h>

BOOL UMBIsUUIDPathOf(NSString *path, NSString *parent);

NSString *UMBClearAppData(UMBInstalledAppInfo *app) {
    NSError *error = nil;

    if (app.containerURL && UMBIsUUIDPathOf(app.containerURL.path, @"/private/var/mobile/Containers/Data/Application/")
        && [NSFileManager.defaultManager fileExistsAtPath:app.containerURL.path]) {
        if (![NSFileManager.defaultManager removeItemAtURL:app.containerURL error:&error]) {
            return [NSString stringWithFormat:NSLocalizedString(@"Failed to remove app data container:\n%@", nil),
                                              error.localizedDescription];
        }
    }
    return nil;
}
