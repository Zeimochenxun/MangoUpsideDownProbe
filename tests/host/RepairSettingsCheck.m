#import "../../src/SuitePreferences.h"
#include <assert.h>
int main(void) {
    @autoreleasepool {
        NSDictionary *defaults=MSReadPreferences(NULL);
        assert(defaults && MSRepairKeys().count==10);
        assert(!MSPreferenceFlag(defaults,@"EdgeColorEnabled") && !MSPreferenceFlag(defaults,@"DebugEnabled") && !MSPreferenceFlag(defaults,@"DockDrawerEnabled"));
        for (NSString *key in MSRepairKeys()) {
            assert(MSWritePreferenceFlag(key,NO,NULL));
            NSDictionary *before=MSReadPreferences(NULL);
            assert(!MSPreferenceFlag(before,key));
            assert(MSWritePreferenceFlag(key,YES,NULL));
            NSMutableDictionary *expected=[before mutableCopy]; expected[key]=@YES;
            assert([expected isEqualToDictionary:MSReadPreferences(NULL)]);
            assert(MSWritePreferenceFlag(key,NO,NULL));
        }
        assert(MSWritePreferenceValue(@"EdgeThickness",@.5,NULL));
        assert(MSWritePreferenceValue(@"EdgeThickness",@4,NULL));
        assert(!MSWritePreferenceValue(@"EdgeThickness",@4.1,NULL));
        assert(MSWritePreferenceValue(@"EdgeDynamics",@0,NULL));
        assert(MSWritePreferenceValue(@"EdgeDynamics",@1,NULL));
        assert(!MSWritePreferenceValue(@"EdgeDynamics",@(-.01),NULL));
        assert(!MSWritePreferenceValue(@"EdgeDynamics",@(NAN),NULL));
        assert(MSWritePreferenceValue(@"DockNotchLift",@0,NULL));
        assert(MSWritePreferenceValue(@"DockNotchLift",@50,NULL));
        assert(!MSWritePreferenceValue(@"DockNotchLift",@50.1,NULL));
        assert(MSWritePreferenceValue(@"DockDrawerPinned",(@[@"com.apple.Preferences",@"com.tencent.xin"]),NULL));
        assert([MSReadPreferences(NULL)[@"DockDrawerPinned"] isEqual:(@[@"com.apple.Preferences",@"com.tencent.xin"])]);
        assert(MSWritePreferenceValue(@"DockDrawerPinned",@[],NULL));
        assert(!MSWritePreferenceValue(@"DockDrawerPinned",(@[@"a",@"b",@"c",@"d",@"e",@"f"]),NULL));
        assert(!MSWritePreferenceValue(@"DockDrawerPinned",(@[@"a",@"a"]),NULL));
        assert(!MSWritePreferenceValue(@"DockDrawerPinned",@[@"bad id"],NULL));
        assert(!MSWritePreferenceValue(@"DockDrawerPinned",@[@1],NULL));
        assert(!MSWritePreferenceValue(@"DockDrawerPinned",@YES,NULL));
        assert(!MSWritePreferenceValue(@"DockNotchLift",@[@"a"],NULL));
        assert(!MSWritePreferenceValue(@"unrecognized",@YES,NULL));
        assert(MSWritePreferenceValue(@"DebugSessionToken",@1000,NULL));
        assert(MSWritePreferenceFlag(@"DebugEnabled",YES,NULL));
        NSDictionary *saved=MSReadPreferences(NULL);
        assert([saved[@"DebugSessionToken"] doubleValue]==1000 && [saved[@"DebugEnabled"] boolValue]);
        puts("PASS: eight repairs persist independently; color/debug opt in, bounded sliders, malformed values and session token persistence");
    }
    return 0;
}
