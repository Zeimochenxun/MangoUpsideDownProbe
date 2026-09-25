#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>

static CFStringRef const MangoPrefsDomain = CFSTR("com.go.mangoosprefs");
static CFStringRef const RepairDomain = CFSTR("com.chenxun.mangoidleisland");
static CFStringRef const RepairDoneKey = CFSTR("TintRGBARepair101Done");

static BOOL ValidRGBAString(id value) {
    if (![value isKindOfClass:NSString.class]) return NO;
    NSString *s = (NSString *)value;
    if (s.length != 9 || ![s hasPrefix:@"#"]) return NO;
    NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFabcdef"] invertedSet];
    return [[s substringFromIndex:1] rangeOfCharacterFromSet:bad].location == NSNotFound;
}

__attribute__((constructor)) static void RepairTintState101(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;

        CFPreferencesAppSynchronize(RepairDomain);
        id done = CFBridgingRelease(CFPreferencesCopyAppValue(RepairDoneKey, RepairDomain));
        if ([done respondsToSelector:@selector(boolValue)] && [done boolValue]) return;

        CFPreferencesAppSynchronize(MangoPrefsDomain);
        id standalone = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Island.TintStrength"), MangoPrefsDomain));
        id light = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Island.LightTintColor"), MangoPrefsDomain));
        id dark = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Island.DarkTintColor"), MangoPrefsDomain));

        // 1.0.0 could leave a scalar tint alpha while Mango's built-in Island
        // RGB defaults are all zero.  That turns the tint into a black overlay.
        // LightTintColor is parsed later and replaces the whole light RGBA
        // vector, so the standalone scalar is also redundant once colors exist.
        if ([standalone isKindOfClass:NSNumber.class]) {
            double value = [standalone doubleValue];
            if (isfinite(value) && value >= 0.0 && value <= 1.0) {
                CFPreferencesSetAppValue(CFSTR("Island.TintStrength"), NULL, MangoPrefsDomain);
                CFPreferencesAppSynchronize(MangoPrefsDomain);

                // Do not synthesize tint colors during migration.  With no
                // existing color values this restores Mango's native 0 alpha;
                // with valid colors their original RGBA remains untouched.
                (void)ValidRGBAString(light);
                (void)ValidRGBAString(dark);
            }
        }

        CFPreferencesSetAppValue(RepairDoneKey, kCFBooleanTrue, RepairDomain);
        CFPreferencesAppSynchronize(RepairDomain);
    }
}
