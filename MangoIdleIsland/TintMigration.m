#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>

static CFStringRef const MangoPrefsDomain = CFSTR("com.go.mangoosprefs");
static CFStringRef const MangoRenderReloadName = CFSTR("com.go.mangoosprefs/Reload");
static CFStringRef const RepairDomain = CFSTR("com.chenxun.mangoidleisland");
static CFStringRef const RepairDoneKey = CFSTR("TintRGBARepair101Done");

static void PostMangoReload(void) {
    // Beta7-1 MangoOSRendering reloads its cached parameter table on this
    // notification and then emits go.mangoos/ParametersReloaded to live views.
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         MangoRenderReloadName,
                                         NULL,
                                         NULL,
                                         YES);
}

__attribute__((constructor)) static void RepairTintState101(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;

        CFPreferencesAppSynchronize(RepairDomain);
        id done = CFBridgingRelease(CFPreferencesCopyAppValue(RepairDoneKey, RepairDomain));
        if ([done respondsToSelector:@selector(boolValue)] && [done boolValue]) return;

        BOOL repaired = NO;
        CFPreferencesAppSynchronize(MangoPrefsDomain);
        id standalone = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Island.TintStrength"), MangoPrefsDomain));

        // MangoIdleIsland 1.0.0 was the only released build of this tweak that
        // wrote the standalone scalar, and it clamped that value to 0...1.
        // Beta7 starts Island tint RGBA at 0,0,0,0, so that legacy scalar can
        // produce a black tint unless a complete color value overrides it.
        if ([standalone isKindOfClass:NSNumber.class]) {
            double value = [standalone doubleValue];
            if (isfinite(value) && value >= 0.0 && value <= 1.0) {
                CFPreferencesSetAppValue(CFSTR("Island.TintStrength"), NULL, MangoPrefsDomain);
                repaired = CFPreferencesAppSynchronize(MangoPrefsDomain);
            }
        }

        CFPreferencesSetAppValue(RepairDoneKey, kCFBooleanTrue, RepairDomain);
        CFPreferencesAppSynchronize(RepairDomain);

        if (repaired) {
            PostMangoReload();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{ PostMangoReload(); });
        }
    }
}
