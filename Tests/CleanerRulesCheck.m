#import "UMBCleaner.h"
#include <assert.h>

extern NSArray<UMBCleanItem *> *UMBCleanerItemsForDirectory(NSString *, NSArray<NSDictionary *> *,
                                                            NSDictionary *, NSDictionary *,
                                                            NSDictionary<NSString *, NSNumber *> *);

BOOL UMBRootUserGetDirectoryContents(NSString *path, NSString *cacheFile) {
    abort();
}

BOOL UMBRootUserRemoveItemAtPath(NSString *path) {
    abort();
}

static UMBCleanItem *Item(NSDictionary *rule, NSDictionary *custom, NSNumber *previous) {
    return UMBCleanerItemsForDirectory(@"/test", @[ @{
                                           @"name" : @"sample",
                                           @"isDirectory" : @NO
                                       } ],
                                       rule, custom, previous ? @{@"/test/sample" : previous} : @{})
        .firstObject;
}

int main(void) {
    @autoreleasepool {
        NSDictionary *black = @{@"blacklist" : @[ @"sample" ]};
        NSDictionary *white = @{@"whitelist" : @[ @"sample" ]};
        assert(Item(black, nil, nil).checked);
        assert(!Item(black, white, nil).checked && Item(black, white, nil).ignored);
        assert(Item(white, black, nil).checked);
        assert(Item(white, nil, nil) == nil);
        assert(Item(
                   @{@"blacklist" : @[ @"sample" ],
                     @"whitelist" : @[ @"sample" ]},
                   nil, nil)
                   .checked);
        assert(!Item(
                    black, @{
                        @"default" : @"whitelist",
                        @"whitelist" : @[ @"sample" ],
                        @"blacklist" : @[ @"sample" ]
                    },
                    nil)
                    .checked);
        assert(Item(@{@"default" : @"blacklist"}, nil, nil).checked);
        assert(Item(@{@"default" : @"blacklist"}, @{@"default" : @"whitelist"}, nil).ignored);
        assert(Item(@{@"default" : @"whitelist"}, nil, nil) == nil);
        assert(Item(@{@"default" : @"whitelist"}, @{@"default" : @"blacklist"}, nil).checked);
        assert(!Item(@{}, nil, nil).checked);
        assert(Item(@{}, @{@"default" : @"blacklist"}, nil).checked);
        assert(Item(@{}, white, nil).ignored);
        assert(Item(
                   @{@"blacklist" : @[ @{@"match" : @"include", @"name" : @"amp"} ]}, nil, nil)
                   .checked);
        assert(Item(
                   @{@"blacklist" : @[ @{@"match" : @"regexp", @"name" : @"^sam.*e$"} ]}, nil, nil)
                   .checked);
        assert(!Item(
                    @{@"blacklist" : @[ @{@"match" : @"regexp", @"name" : @"["} ]}, nil, nil)
                    .checked);
        assert(!Item(black, nil, @NO).checked);
        assert(Item(@{}, nil, @YES).checked);
        assert(!Item(black, white, @YES).checked);
        assert(Item(black, nil, nil).checked);

        NSArray<UMBCleanItem *> *items = UMBCleanerItemsForDirectory(@"/test", @[
            @{@"name" : @"a-file",
              @"isDirectory" : @NO},
            @{@"name" : @"z-folder",
              @"isDirectory" : @YES},
            @{@"name" : @"b-folder",
              @"isDirectory" : @YES},
            @{@"name" : @"..",
              @"isDirectory" : @YES},
            @{@"name" : @"outside/file",
              @"isDirectory" : @NO}
        ],
                                                                     @{}, nil, @{});
        assert(items.count == 3);
        assert([items[0].name isEqualToString:@"b-folder"]);
        assert([items[1].name isEqualToString:@"z-folder"]);
        assert([items[2].name isEqualToString:@"a-file"]);
        puts("Cleaner rules: priority, matching, preserved selection, and ordering passed.");
    }
    return 0;
}
