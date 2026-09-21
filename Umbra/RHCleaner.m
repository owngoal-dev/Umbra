#import "RHCleaner.h"
#import "roothide.h"
#include <unistd.h>

extern BOOL RootUserGetDirectoryContents(NSString *path, NSString *cacheFile);
extern BOOL RootUserRemoveItemAtPath(NSString *path);

@implementation RHCleanItem
@end

@implementation RHCleanGroup
@end

static BOOL Matches(NSString *name, NSArray *list) {
    for (id entry in list) {
        if ([entry isKindOfClass:NSString.class]) {
            if ([name isEqualToString:entry])
                return YES;
        } else if ([entry isKindOfClass:NSDictionary.class] &&
                   [entry[@"name"] isKindOfClass:NSString.class]) {
            NSString *pattern = entry[@"name"];
            if ([entry[@"match"] isEqual:@"include"] && [name containsString:pattern])
                return YES;
            if ([entry[@"match"] isEqual:@"regexp"]) {
                NSRegularExpression *expression =
                    [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
                if ([expression numberOfMatchesInString:name
                                                options:0
                                                  range:NSMakeRange(0, name.length)])
                    return YES;
            }
        }
    }
    return NO;
}

NSArray<RHCleanItem *> *
RHCleanerItemsForDirectory(NSString *path, NSArray<NSDictionary *> *contents, NSDictionary *rule,
                           NSDictionary *custom, NSDictionary<NSString *, NSNumber *> *selection) {
    NSMutableArray<RHCleanItem *> *items = [NSMutableArray new];
    for (id entry in contents) {
        if (![entry isKindOfClass:NSDictionary.class])
            continue;
        NSString *name = entry[@"name"];
        if (![name isKindOfClass:NSString.class] || name.length == 0 ||
            [name containsString:@"/"] || [name isEqualToString:@"."] ||
            [name isEqualToString:@".."])
            continue;

        BOOL checked = NO;
        BOOL ignored = NO;
        if (Matches(name, rule[@"blacklist"])) {
            ignored = Matches(name, custom[@"whitelist"]);
            checked = !ignored;
        } else if (Matches(name, custom[@"blacklist"])) {
            checked = YES;
        } else if (Matches(name, rule[@"whitelist"])) {
            continue;
        } else if ([rule[@"default"] isEqual:@"blacklist"]) {
            ignored =
                Matches(name, custom[@"whitelist"]) || [custom[@"default"] isEqual:@"whitelist"];
            checked = !ignored;
        } else if ([rule[@"default"] isEqual:@"whitelist"]) {
            if ([custom[@"default"] isEqual:@"blacklist"])
                checked = YES;
            else
                continue;
        } else {
            ignored =
                Matches(name, custom[@"whitelist"]) || [custom[@"default"] isEqual:@"whitelist"];
            checked = !ignored && [custom[@"default"] isEqual:@"blacklist"];
        }

        RHCleanItem *item = [RHCleanItem new];
        item.name = name;
        item.path = [path stringByAppendingPathComponent:name];
        item.folder = [entry[@"isDirectory"] boolValue];
        item.checked = !ignored && selection[item.path] ? selection[item.path].boolValue : checked;
        item.ignored = ignored;
        [items addObject:item];
    }
    [items sortUsingComparator:^NSComparisonResult(RHCleanItem *a, RHCleanItem *b) {
        if (a.folder != b.folder)
            return a.folder ? NSOrderedAscending : NSOrderedDescending;
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    return items;
}

NSArray<NSDictionary *> *GetDirectoryContents(NSString *path) {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSArray<NSString *> *contents = [manager contentsOfDirectoryAtPath:path error:nil];
    if (!contents)
        return nil;
    NSMutableArray *result = [NSMutableArray new];
    for (NSString *name in contents) {
        BOOL directory = NO;
        BOOL exists = [manager fileExistsAtPath:[path stringByAppendingPathComponent:name]
                                    isDirectory:&directory];
        [result addObject:@{@"name" : name, @"isDirectory" : @(exists && directory)}];
    }
    return result;
}

static NSDictionary *ReadRules(NSString *path, NSError **error) {
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data)
        return nil;
    id rules = [NSPropertyListSerialization propertyListWithData:data
                                                         options:NSPropertyListImmutable
                                                          format:nil
                                                           error:error];
    if (!rules)
        return nil;
    BOOL valid = [rules isKindOfClass:NSDictionary.class];
    if (valid) {
        for (NSString *directory in rules) {
            NSDictionary *rule = rules[directory];
            if (![directory isKindOfClass:NSString.class] || !directory.isAbsolutePath ||
                ![rule isKindOfClass:NSDictionary.class] ||
                (rule[@"whitelist"] && ![rule[@"whitelist"] isKindOfClass:NSArray.class]) ||
                (rule[@"blacklist"] && ![rule[@"blacklist"] isKindOfClass:NSArray.class])) {
                valid = NO;
                break;
            }
        }
    }
    if (!valid) {
        if (error)
            *error = [NSError
                errorWithDomain:NSCocoaErrorDomain
                           code:NSPropertyListReadCorruptError
                       userInfo:@{
                           NSLocalizedDescriptionKey :
                               NSLocalizedString(@"The cleaning rules file is invalid.", nil),
                           NSFilePathErrorKey : path
                       }];
        return nil;
    }
    return rules;
}

@implementation RHCleaner

+ (NSArray<RHCleanGroup *> *)scanKeepingSelection:(NSDictionary<NSString *, NSNumber *> *)selection
                                            error:(NSError **)error {
    NSDictionary *rules =
        ReadRules(jbroot(@"/var/mobile/Library/RootHide/varCleanRules.plist"), error);
    if (!rules)
        return nil;
    NSDictionary *customRules =
        ReadRules(jbroot(@"/var/mobile/Library/RootHide/varCleanRules-custom.plist"), error);
    if (!customRules)
        return nil;

    NSMutableSet<NSString *> *paths = [NSMutableSet setWithArray:rules.allKeys];
    [paths addObjectsFromArray:customRules.allKeys];
    NSMutableArray<RHCleanGroup *> *groups = [NSMutableArray new];
    NSFileManager *manager = NSFileManager.defaultManager;
    for (NSString *path in paths) {
        NSArray *contents = GetDirectoryContents(path);
        if (!contents && [manager fileExistsAtPath:path] && (geteuid() != 0 || getegid() != 0)) {
            NSString *cacheFile = jbroot(@"/tmp/.dircontentscache");
            if (RootUserGetDirectoryContents(path, cacheFile)) {
                contents = [NSArray arrayWithContentsOfFile:cacheFile];
                [manager removeItemAtPath:cacheFile error:nil];
            }
        }

        RHCleanGroup *group = [RHCleanGroup new];
        group.path = path;
        group.items = RHCleanerItemsForDirectory(path, contents, rules[path] ?: customRules[path],
                                                 rules[path] ? customRules[path] : nil, selection);
        if (!contents && [manager fileExistsAtPath:path]) {
            group.errorMessage = NSLocalizedString(@"The folder could not be read.", nil);
        }
        [groups addObject:group];
    }
    [groups sortUsingComparator:^NSComparisonResult(RHCleanGroup *a, RHCleanGroup *b) {
        if ((a.items.count > 0) != (b.items.count > 0))
            return a.items.count > 0 ? NSOrderedAscending : NSOrderedDescending;
        return [a.path compare:b.path];
    }];
    return groups;
}

+ (NSDictionary<NSString *, NSString *> *)removePaths:(NSArray<NSString *> *)paths {
    NSMutableDictionary *failures = [NSMutableDictionary new];
    for (NSString *path in paths) {
        NSError *error = nil;
        if ([NSFileManager.defaultManager removeItemAtPath:path error:&error])
            continue;
        if ([error.domain isEqualToString:NSCocoaErrorDomain] &&
            error.code == NSFileNoSuchFileError)
            continue;
        if ((geteuid() != 0 || getegid() != 0) && RootUserRemoveItemAtPath(path))
            continue;
        failures[path] =
            error.localizedDescription ?: NSLocalizedString(@"The file could not be removed.", nil);
    }
    return failures;
}

@end
