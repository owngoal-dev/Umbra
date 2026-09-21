#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RHServicePorts : NSObject
+ (NSArray<NSString *> *)installedServices;
+ (NSNumber *)opensshBackupPort;
+ (nullable NSArray<NSNumber *> *)portsForService:(NSString *)service
                                            error:(NSError **)error NS_SWIFT_NAME(ports(for:));
+ (BOOL)setPorts:(NSArray<NSNumber *> *)ports
      forService:(NSString *)service
           error:(NSError **)error NS_SWIFT_NAME(setPorts(_:for:));
@end

NS_ASSUME_NONNULL_END
