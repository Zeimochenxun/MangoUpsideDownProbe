// Host check (macOS, CI): the drawer math and the settings file with its
// Mango Suite seed. Run with DD_TEST_ROOT set to an empty directory.
#import <Foundation/Foundation.h>
#include <assert.h>
#include "../DrawerMath.h"
#import "../Settings.h"

static void Write(NSString *path, NSDictionary *plist) {
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    assert([plist writeToURL:[NSURL fileURLWithPath:path] error:nil]);
}

int main(void) {
    @autoreleasepool {
        // Pull: linear up to open, then a rubber band that never passes DDStretch.
        assert(DDPull(-.3) == 0 && DDPull(.4) == .4 && DDPull(1) == 1);
        assert(DDPull(1.001) > 1 && DDPull(1.001) < 1.001);
        assert(DDPull(1.5) < DDPull(3) && DDPull(1e6) < 1 + DDStretch);
        // Squeeze: none until stretched, DDNarrow at full stretch and beyond.
        assert(DDSqueeze(.5) == 1 && DDSqueeze(1) == 1);
        assert(DDSqueeze(1 + DDStretch) == 1 - DDNarrow && DDSqueeze(2) == DDSqueeze(1 + DDStretch));
        // Capacity of the device's 327pt platter (6.5 margins, 60pt icons at 60pt pitch).
        assert(DDCapacity(327, 6.5, 0, 60, 60) == 5 && DDCapacity(327, 6.5, 14, 60, 60) == 5 && DDCapacity(100, 6.5, 0, 60, 60) == 1);
        // Release: a flick decides, a slow release keeps the nearer state, a cancel goes back.
        assert(DDReleaseOpen(1, .2, 0, -2000, 66.5) && !DDReleaseOpen(1, .4, 0, 0, 66.5) && DDReleaseOpen(1, .6, 0, 0, 66.5));
        assert(!DDReleaseOpen(1, .9, 1, 2000, 66.5) && DDReleaseOpen(0, .1, 1, 0, 66.5));
        // Leaving: a fall below .8, not the presentation spring settling from its overshoot.
        assert(DDLeaving(.7, .75) && !DDLeaving(1, 1.27) && !DDLeaving(.75, .7) && !DDLeaving(NAN, 1));

        // Settings: no files means every switch on and nothing pinned.
        NSDictionary *settings = DDReadSettings();
        assert(settings.count == 0 && DDFlag(settings, @"Enabled") && DDFlag(settings, @"FloatingDock") && DDPinned(settings).count == 0);
        // A first run takes Mango Suite's drawer choices, cleaned to 5 distinct apps.
        Write(DDSuiteFile(@"settings.plist"), @{@"DockDrawerPinned": @[@"a", @"b", @"a", @"c", @7, @"d", @"e", @"f"],
                                                @"DockDrawerDivider": @NO, @"DockDrawerEnabled": @YES});
        settings = DDReadSettings();
        assert([DDPinned(settings) isEqualToArray:(@[@"a", @"b", @"c", @"d", @"e"])] && !DDFlag(settings, @"Divider") && DDFlag(settings, @"Enabled"));
        // The first write keeps that seed in our own file; Mango Suite is not read again.
        NSError *error = nil;
        assert(DDWriteSetting(@"Enabled", @NO, &error));
        Write(DDSuiteFile(@"settings.plist"), @{@"DockDrawerDivider": @YES});
        settings = DDReadSettings();
        assert(!DDFlag(settings, @"Enabled") && !DDFlag(settings, @"Divider") && DDPinned(settings).count == 5);
        puts("DoubleDock checks passed");
    }
    return 0;
}
