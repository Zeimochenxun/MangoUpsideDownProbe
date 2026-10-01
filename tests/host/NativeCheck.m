#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import "../../src/NativePreferences.h"

static int Synchronizes = 0, FailAt = -1;
Boolean MSNativeTestSynchronize(CFStringRef domain) {
    if (++Synchronizes == FailAt) return false;
    return CFPreferencesAppSynchronize(domain);
}
static CFStringRef const Domain = CFSTR(MS_NATIVE_DOMAIN);
static CFStringRef const Key = CFSTR("LeXiang.UpsideDown.Enabled");
static void Require(BOOL condition, NSString *reason) {
    if (!condition) { NSLog(@"FAIL: %@", reason); exit(1); }
}
static id Copy(CFStringRef key) { return CFBridgingRelease(CFPreferencesCopyAppValue(key, Domain)); }
static void Clear(void) {
    CFPreferencesSetAppValue(Key, NULL, Domain);
    CFPreferencesSetAppValue(CFSTR("SiblingMustSurvive"), NULL, Domain);
    Require(CFPreferencesAppSynchronize(Domain), @"test domain cleanup");
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 2;
        NSString *mode = [NSString stringWithUTF8String:argv[1]];
        NSError *error = nil;
        if ([mode isEqualToString:@"exercise"]) {
            Clear();
            Require(![MSReadNativeUpsideDown(&error) boolValue] && !error && !Copy(Key), @"missing value reads false without creating it");
            CFPreferencesSetAppValue(CFSTR("SiblingMustSurvive"), CFSTR("preserve"), Domain);
            Require(CFPreferencesAppSynchronize(Domain), @"sibling seed");
            Require(MSWriteNativeUpsideDown(YES, &error) && !error, @"native enable");
            Require([MSReadNativeUpsideDown(&error) boolValue], @"native readback on");
            Require([Copy(CFSTR("SiblingMustSurvive")) isEqual:@"preserve"], @"other Mango preferences preserved");
            FailAt = Synchronizes + 2; // preflight succeeds, actual write synchronize fails.
            Require(!MSWriteNativeUpsideDown(NO, &error) && error, @"failed sync rejected");
            Require([MSReadNativeUpsideDown(NULL) boolValue], @"prior true restored after failed write");
            FailAt = Synchronizes + 1;
            Require(!MSWriteNativeUpsideDown(NO, &error) && error, @"failed preflight rejected without mutation");
            Require([MSReadNativeUpsideDown(NULL) boolValue], @"preflight failure preserves prior true");
            CFPreferencesSetAppValue(Key, CFSTR("invalid-must-survive"), Domain);
            Require(CFPreferencesAppSynchronize(Domain), @"invalid seed");
            Require(!MSWriteNativeUpsideDown(NO, &error) && error, @"invalid original type rejected");
            Require([Copy(Key) isEqual:@"invalid-must-survive"], @"invalid original retained");
            CFPreferencesSetAppValue(Key, NULL, Domain);
            Require(CFPreferencesAppSynchronize(Domain), @"clear malformed value");
            Require(MSWriteNativeUpsideDown(NO, &error) && ![MSReadNativeUpsideDown(NULL) boolValue], @"native disable");
            Require(MSWriteNativeUpsideDown(YES, &error), @"leave true for independent reader process");
            puts("PASS: actual native setter sync/readback, sibling preservation, preflight/write failures and rollback");
        } else if ([mode isEqualToString:@"read"]) {
            Require([MSReadNativeUpsideDown(&error) boolValue] && !error, @"separate process reads persisted native value");
            Require([Copy(CFSTR("SiblingMustSurvive")) isEqual:@"preserve"], @"separate process reads sibling value");
            puts("PASS: independent CFPreferences process reads native true and untouched sibling");
        } else if ([mode isEqualToString:@"clear"]) Clear();
        else return 2;
        return 0;
    }
}
