// https://github.com/wujianguo/iOSAppsInfo
// modified by Shadow-

#import "AppInfo.h"
#import <TargetConditionals.h>

@interface UIImage ()
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)identifier
                                               format:(int)format
                                                scale:(double)scale;
@end

@interface PrivateApi_LSApplicationProxy : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
@property (nonatomic, readonly) NSString *localizedShortName;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSArray *appTags;
@property (nonatomic, readonly) NSURL *bundleURL;
@property (nonatomic, readonly) NSURL *containerURL;
@end

@implementation UMBInstalledAppInfo {
    PrivateApi_LSApplicationProxy *_applicationProxy;
    UIImage *_icon;
}

- (NSString *)name {
    return _applicationProxy.localizedName ?: _applicationProxy.localizedShortName;
}

- (NSString *)bundleIdentifier {
    return [_applicationProxy bundleIdentifier];
}

- (UIImage *)icon {
#if TARGET_OS_IOS
    if (nil == _icon) {
#else
    if (nil == _icon &&
        [UIImage
            respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
#endif
        _icon = [UIImage _applicationIconImageForBundleIdentifier:self.bundleIdentifier
                                                           format:10
                                                            scale:UIScreen.mainScreen.scale];
    }

    return _icon;
}

- (NSURL *)bundleURL {
    return _applicationProxy.bundleURL;
}
- (NSURL *)containerURL {
    return _applicationProxy.containerURL;
}

- (BOOL)isHiddenApp {
    return [[_applicationProxy appTags] indexOfObject:@"hidden"] != NSNotFound;
}

- (id)initWithPrivateProxy:(id)privateProxy {
    self = [super init];
    if (self != nil) {
        _applicationProxy = (PrivateApi_LSApplicationProxy *)privateProxy;
    }

    return self;
}

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier {
    self = [super init];
    if (self != nil) {
        _applicationProxy = [NSClassFromString(@"LSApplicationProxy")
            applicationProxyForIdentifier:bundleIdentifier];
    }

    return self;
}

+ (instancetype)appWithPrivateProxy:(id)privateProxy {
    return [[self alloc] initWithPrivateProxy:privateProxy];
}

+ (instancetype)appWithBundleIdentifier:(NSString *)bundleIdentifier {
    return [[self alloc] initWithBundleIdentifier:bundleIdentifier];
}

@end
