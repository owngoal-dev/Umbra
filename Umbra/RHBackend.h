#import <Foundation/Foundation.h>
#import "AppInfo.h"

NS_ASSUME_NONNULL_BEGIN

@interface RHBackend : NSObject

+ (BOOL)prepareWithError:(NSError **)error NS_SWIFT_NAME(prepare());
+ (nullable id)configurationForKey:(NSString *)key NS_SWIFT_NAME(configuration(forKey:));
+ (BOOL)setConfiguration:(id)value
                  forKey:(NSString *)key
                   error:(NSError **)error NS_SWIFT_NAME(setConfiguration(_:forKey:));
+ (NSArray<AppInfo *> *)installedApps NS_SWIFT_NAME(installedApps());
+ (nullable NSString *)relaxinMarketingVersion NS_SWIFT_NAME(relaxinMarketingVersion());
+ (nullable NSString *)blacklistUnavailableReason NS_SWIFT_NAME(blacklistUnavailableReason());
+ (nullable NSString *)blacklistRejectionForApp:(AppInfo *)app
    NS_SWIFT_NAME(blacklistRejection(for:));
+ (BOOL)requiresCompatibilityWarning NS_SWIFT_NAME(requiresCompatibilityWarning());
+ (BOOL)setBlacklisted:(BOOL)blacklisted
                forApp:(AppInfo *)app
                 error:(NSError **)error NS_SWIFT_NAME(setBlacklisted(_:for:));
+ (nullable NSString *)clearDataForApp:(AppInfo *)app NS_SWIFT_NAME(clearData(for:));
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)
    startupWarnings NS_SWIFT_NAME(startupWarnings());
+ (NSString *)customRulesPath NS_SWIFT_NAME(customRulesPath());
+ (void)cleanOwnApplicationFiles NS_SWIFT_NAME(cleanOwnApplicationFiles());

@end

NS_ASSUME_NONNULL_END
