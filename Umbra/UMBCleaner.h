#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UMBCleanItem : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *path;
@property (nonatomic) BOOL folder;
@property (nonatomic) BOOL checked;
@property (nonatomic) BOOL ignored;
@end

@interface UMBCleanGroup : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSArray<UMBCleanItem *> *items;
@property (nonatomic, copy, nullable) NSString *errorMessage;
@end

@interface UMBCleaner : NSObject
+ (nullable NSArray<UMBCleanGroup *> *)scanKeepingSelection:
                                           (NSDictionary<NSString *, NSNumber *> *)selection
                                                      error:(NSError **)error
    NS_SWIFT_NAME(scan(selection:));
+ (NSDictionary<NSString *, NSString *> *)removePaths:(NSArray<NSString *> *)paths
    NS_SWIFT_NAME(remove(paths:));
@end

FOUNDATION_EXPORT NSArray<NSDictionary *> *_Nullable UMBGetDirectoryContents(NSString *path);

NS_ASSUME_NONNULL_END
