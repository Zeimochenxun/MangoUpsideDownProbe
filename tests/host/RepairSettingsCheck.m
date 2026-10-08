#import "../../src/SuitePreferences.h"
#include <assert.h>
int main(void) {
    @autoreleasepool {
        NSDictionary *defaults=MSReadPreferences(NULL);
        assert(defaults && MSRepairKeys().count==7);
        assert(!MSPreferenceFlag(defaults,@"EdgeColorEnabled") && !MSPreferenceFlag(defaults,@"DebugEnabled"));
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
        assert(!MSWritePreferenceValue(@"unrecognized",@YES,NULL));
        assert(MSWritePreferenceValue(@"DebugSessionToken",@1000,NULL));
        assert(MSWritePreferenceFlag(@"DebugEnabled",YES,NULL));
        NSDictionary *saved=MSReadPreferences(NULL);
        assert([saved[@"DebugSessionToken"] doubleValue]==1000 && [saved[@"DebugEnabled"] boolValue]);
        puts("PASS: seven repairs persist independently; color/debug opt in, bounded sliders, malformed values and session token persistence");
    }
    return 0;
}
