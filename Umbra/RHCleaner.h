#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RHCleanItem : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *path;
@property (nonatomic) BOOL folder;
@property (nonatomic) BOOL checked;
@property (nonatomic) BOOL ignored;
@end

@interface RHCleanGroup : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSArray<RHCleanItem *> *items;
@property (nonatomic, copy, nullable) NSString *errorMessage;
@end

@interface RHCleaner : NSObject
+ (nullable NSArray<RHCleanGroup *> *)scanKeepingSelection:
                                          (NSDictionary<NSString *, NSNumber *> *)selection
                                                     error:(NSError **)error
    NS_SWIFT_NAME(scan(selection:));
+ (NSDictionary<NSString *, NSString *> *)removePaths:(NSArray<NSString *> *)paths
    NS_SWIFT_NAME(remove(paths:));
@end

FOUNDATION_EXPORT NSArray<NSDictionary *> *_Nullable GetDirectoryContents(NSString *path);

NS_ASSUME_NONNULL_END
