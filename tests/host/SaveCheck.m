#import <Preferences/PSListController.h>
#import <CoreFoundation/CoreFoundation.h>
#import "../../src/SuitePreferences.h"
#import "../../src/NativePreferences.h"

@interface PSListController (ActualSuiteMethods)
- (id)readValue:(PSSpecifier *)specifier;
- (void)writeValue:(id)value specifier:(PSSpecifier *)specifier;
@end

static NSArray *Keys(void) {
    return @[@"Enabled", @"IdleEnabled", @"AdaptiveEnabled", @"WorldEnabled", @"SplitEnabled"];
}
static void Require(BOOL condition, NSString *reason) {
    if (!condition) { NSLog(@"FAIL: %@", reason); exit(1); }
}
static PSSpecifier *Item(PSListController *controller, NSString *key) {
    for (PSSpecifier *item in [controller specifiers]) {
        if ([[item propertyForKey:@"key"] isEqual:key]) return item;
    }
    Require(NO, key); return nil;
}
static unsigned ReadMask(PSListController *controller) {
    unsigned mask = 0;
    for (unsigned i = 0; i < Keys().count; i++) {
        PSSpecifier *item = Item(controller, Keys()[i]);
        Require(item.target == controller && item.setter == @selector(writeValue:specifier:) && item.getter == @selector(readValue:), @"switch getter/setter wiring");
        if ([[controller readValue:item] boolValue]) mask |= 1u << i;
    }
    return mask;
}
static void Write(PSListController *controller, NSString *key, BOOL enabled) {
    controller.presentedViewController = nil;
    [controller writeValue:@(enabled) specifier:Item(controller, key)];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) return 2;
        NSBundle *bundle = [NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];
        Class root = bundle.principalClass;
        Require([NSStringFromClass(root) isEqual:@"MangoSuitePrefsController"], @"root controller");
        PSListController *controller = [root new];
        NSString *mode = [NSString stringWithUTF8String:argv[2]];
        if ([mode isEqual:@"reproduce-save"]) {
            CFStringRef domain = CFSTR("com.chenxun.mangosuite");
            CFPreferencesSetAppValue(CFSTR("Enabled"), kCFBooleanTrue, domain);
            Require(CFPreferencesAppSynchronize(domain), @"legacy CF save succeeded");
            Require(![NSFileManager.defaultManager fileExistsAtPath:@"/var/mobile/Library/Preferences/com.chenxun.mangosuite.plist"], @"unredirected file missing");
            Write(controller, @"Enabled", NO);
            UIAlertController *alert = controller.presentedViewController;
            Require([alert.title isEqual:@"保存失败"], @"legacy mixed-store false failure reproduced");
            id saved = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Enabled"), domain));
            Require([saved boolValue], @"legacy setter rolled the successfully saved switch back");
            CFPreferencesSetAppValue(CFSTR("Enabled"), NULL, domain);
            CFPreferencesAppSynchronize(domain);
            puts("REPRODUCED: CFPreferences save succeeds but the fixed raw-path check reports failure and rolls it back");
        } else if ([mode isEqual:@"combinations"]) {
            Require(ReadMask(controller) == 31, @"first-install defaults");
            unsigned current = 31;
            for (unsigned mask = 0; mask < 32; mask++) {
                for (unsigned i = 0; i < Keys().count; i++) {
                    BOOL on = !!(mask & (1u << i));
                    Write(controller, Keys()[i], on);
                    Require(!controller.presentedViewController, @"valid switch save has no alert");
                    current = (current & ~(1u << i)) | (on ? 1u << i : 0);
                    Require(ReadMask(controller) == current, @"only the selected switch changes");
                    Require(ReadMask([root new]) == current, @"new settings controller reads persisted values");
                }
                Require(ReadMask(controller) == mask, @"all 32 combinations persist");
                PSListController *glass = [NSClassFromString(@"MangoSuiteGlassController") new];
                BOOL tintAvailable = [[Item(glass, @"MangoIdleIsland.TintAlpha") propertyForKey:@"enabled"] boolValue];
                Require(tintAvailable == !((mask & 1) && (mask & 4)), @"glass page uses the same master/adaptive state");
            }
            // Leave a nontrivial selection for a separate reader process.
            for (unsigned i = 0; i < Keys().count; i++) Write(controller, Keys()[i], !!(21 & (1u << i)));
            Require(ReadMask(controller) == 21, @"persist independent selection");
            puts("PASS: all 32 selections save through actual UI setters, preserve other switches and reload in new controllers; glass gating agrees");
        } else if ([mode isEqual:@"migrate"]) {
            Require(ReadMask(controller) == 21, @"redirected legacy settings read");
            Write(controller, @"IdleEnabled", YES);
            Require(!controller.presentedViewController && ReadMask([root new]) == 23, @"legacy selection migrated without resetting other switches");
            puts("PASS: redirected alpha3 settings migrate on edit and preserve sibling selections");
        } else if ([mode isEqual:@"emergency-marker"]) {
            NSString *testRoot = [NSProcessInfo.processInfo.environment objectForKey:@"MANGOSUITE_HOST_ROOT"];
            NSString *marker = nil;
            for (NSString *path in MSMarkerPathsForKey(@"IdleEnabled"))
                if ([path hasPrefix:[testRoot stringByAppendingString:@"/"]]) marker = path;
            Require(marker != nil, @"RootHide mapped emergency marker available");
            NSFileManager *files = NSFileManager.defaultManager;
            Require([files createDirectoryAtPath:marker.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL], @"isolated marker parent");
            NSData *contents = [@"original marker must survive failure" dataUsingEncoding:NSUTF8StringEncoding];
            Require([contents writeToFile:marker atomically:YES], @"mapped marker seed");
            Require(MSHasEmergencyMarker(@"IdleEnabled") && ![[controller readValue:Item(controller,@"IdleEnabled")] boolValue], @"UI reflects mapped emergency stop");
            Write(controller,@"IdleEnabled",YES);
            Require(!controller.presentedViewController && !MSHasEmergencyMarker(@"IdleEnabled") && [[controller readValue:Item(controller,@"IdleEnabled")] boolValue], @"successful enable clears mapped marker");
            Write(controller,@"IdleEnabled",NO);
            Require([contents writeToFile:marker atomically:YES], @"rollback marker seed");
            NSString *storeParent = MSPreferencesPath().stringByDeletingLastPathComponent;
            Require([files setAttributes:@{NSFilePosixPermissions:@0555} ofItemAtPath:storeParent error:NULL], @"force real storage write failure");
            @try {
                Write(controller,@"IdleEnabled",YES);
                UIAlertController *alert = controller.presentedViewController;
                Require([alert.title isEqual:@"保存失败"], @"marker removal followed by storage failure reports failure");
                Require([[NSData dataWithContentsOfFile:marker] isEqual:contents], @"original marker contents restored after failed save");
                Require(!MSPreferenceFlag(MSReadPreferences(NULL),@"IdleEnabled"), @"failed enable retains stored off state");
            } @finally {
                Require([files setAttributes:@{NSFilePosixPermissions:@0755} ofItemAtPath:storeParent error:NULL], @"restore isolated store permissions");
                [files removeItemAtPath:marker error:NULL];
            }
            puts("PASS: actual UI clears RootHide mapped stop marker; failed persistence restores its exact contents");
        } else if ([mode isEqual:@"native-ui"]) {
            CFStringRef domain = CFSTR(MS_NATIVE_DOMAIN);
            CFStringRef key = CFSTR("LeXiang.UpsideDown.Enabled");
            CFPreferencesSetAppValue(key, NULL, domain);
            Require(CFPreferencesAppSynchronize(domain), @"native UI clean seed");
            Write(controller, @"LeXiang.UpsideDown.Enabled", YES);
            Require(!controller.presentedViewController && [MSReadNativeUpsideDown(NULL) boolValue], @"actual UI enables native preference");
            Write(controller, @"Enabled", NO);
            Require(!controller.presentedViewController && [MSReadNativeUpsideDown(NULL) boolValue], @"master off leaves native choice intact");
            NSDictionary *suite = MSReadPreferences(NULL);
            Write(controller, @"LeXiang.UpsideDown.Enabled", NO);
            Require(!controller.presentedViewController && ![MSReadNativeUpsideDown(NULL) boolValue], @"actual UI disables native preference");
            Require([MSReadPreferences(NULL) isEqualToDictionary:suite], @"native UI leaves all Suite preferences intact");
            CFPreferencesSetAppValue(key, CFSTR("invalid-ui-must-survive"), domain);
            Require(CFPreferencesAppSynchronize(domain), @"malformed native seed");
            PSListController *reopened = [root new];
            PSSpecifier *nativeItem = Item(reopened, @"LeXiang.UpsideDown.Enabled");
            Require(![[nativeItem propertyForKey:@"enabled"] boolValue], @"invalid native value disables the switch instead of pretending it is off");
            Write(reopened, @"LeXiang.UpsideDown.Enabled", YES);
            UIAlertController *alert = reopened.presentedViewController;
            Require([alert.title isEqual:@"保存失败"], @"actual native UI reports save failure");
            id previous = CFBridgingRelease(CFPreferencesCopyAppValue(key, domain));
            Require([previous isEqual:@"invalid-ui-must-survive"], @"invalid native UI value retained");
            CFPreferencesSetAppValue(key, NULL, domain);
            Require(CFPreferencesAppSynchronize(domain), @"native UI cleanup");
            puts("PASS: actual native UI setter, master independence, sibling Suite preservation and visible malformed-value failure");
        } else if ([mode isEqual:@"failure"]) {
            unsigned before = ReadMask(controller);
            Write(controller, @"Enabled", !(before & 1));
            UIAlertController *alert = controller.presentedViewController;
            Require([alert.title isEqual:@"保存失败"] && [alert.message containsString:@"settings.plist"], @"failed save reports the real store path");
            Require(ReadMask([root new]) == before, @"failed save retains previous state");
            puts("PASS: failed save reports an error and leaves prior state unchanged");
        } else return 2;
        return 0;
    }
}
