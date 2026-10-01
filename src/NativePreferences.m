#import "NativePreferences.h"
#import <CoreFoundation/CoreFoundation.h>

#ifndef MS_NATIVE_DOMAIN
#define MS_NATIVE_DOMAIN "com.go.mangoosprefs"
#endif
static CFStringRef const Domain = CFSTR(MS_NATIVE_DOMAIN);
static CFStringRef const Key = CFSTR("LeXiang.UpsideDown.Enabled");

#ifdef MS_NATIVE_TEST_SYNC_HOOK
extern Boolean MSNativeTestSynchronize(CFStringRef domain);
#define NativeSynchronize MSNativeTestSynchronize
#else
#define NativeSynchronize CFPreferencesAppSynchronize
#endif

static NSError *NativeError(NSString *message) {
    return [NSError errorWithDomain:@"com.chenxun.mangosuite.native-preference" code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static id CopyValue(void) {
    return CFBridgingRelease(CFPreferencesCopyAppValue(Key, Domain));
}

NSNumber *MSReadNativeUpsideDown(NSError **error) {
    if (error) *error = nil;
    if (!NativeSynchronize(Domain)) {
        if (error) *error = NativeError(@"无法同步 Mango 倒置偏好。请重新打开设置后检查。");
        return nil;
    }
    id value = CopyValue();
    if (value && ![value isKindOfClass:NSNumber.class]) {
        if (error) *error = NativeError(@"Mango 倒置偏好格式无效，原值已保留。");
        return nil;
    }
    return @([value boolValue]);
}

BOOL MSWriteNativeUpsideDown(BOOL enabled, NSError **error) {
    if (error) *error = nil;
    if (!MSReadNativeUpsideDown(error)) return NO;
    id previous = CopyValue();
    CFPreferencesSetAppValue(Key, enabled ? kCFBooleanTrue : kCFBooleanFalse, Domain);
    BOOL synchronized = NativeSynchronize(Domain);
    id saved = CopyValue();
    if (synchronized && [saved isKindOfClass:NSNumber.class] && [saved boolValue] == enabled) return YES;

    // Restore only this preference, never replace the complete Mango domain.
    CFPreferencesSetAppValue(Key, (__bridge CFPropertyListRef)previous, Domain);
    BOOL restored = NativeSynchronize(Domain);
    id readback = CopyValue();
    restored = restored && (previous ? [readback isEqual:previous] : !readback);
    if (error) *error = NativeError(restored ? @"倒置偏好保存校验失败，原值已恢复。"
                                            : @"倒置偏好保存校验失败。请重新打开本页确认当前开关。");
    return NO;
}
