// https://github.com/wujianguo/iOSAppsInfo
// modified by Shadow-

#import "AppInfo.h"

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

@implementation AppInfo {
    PrivateApi_LSApplicationProxy *_applicationProxy;
    UIImage *_icon;
    NSString *_name;
}

- (NSString *)name {
    if (_name) {
        return _name;
    }
    NSString *languageCode = [[NSLocale preferredLanguages] firstObject];
    NSRange range = [languageCode rangeOfString:@"-" options:NSBackwardsSearch];
    if (range.location != NSNotFound) {
        languageCode = [languageCode substringToIndex:range.location];
    }

    NSString *infoPlistPath = [_applicationProxy.bundleURL.path
        stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.lproj/InfoPlist.strings",
                                                                  languageCode]];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:infoPlistPath]) {
        NSDictionary *plistDict = [[NSDictionary alloc] initWithContentsOfFile:infoPlistPath];
        NSString *displayName = [plistDict objectForKey:@"CFBundleDisplayName"];
        if (displayName) {
            _name = displayName;
            return _name;
        }
    }

    _name = _applicationProxy.localizedName ?: _applicationProxy.localizedShortName;
    return _name;
}

- (NSString *)bundleIdentifier {
    return [_applicationProxy bundleIdentifier];
}

- (UIImage *)icon {
    if (nil == _icon) {
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
