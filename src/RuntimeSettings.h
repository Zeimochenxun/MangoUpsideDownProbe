#pragma once
#import "SuitePreferences.h"
#import <CoreFoundation/CoreFoundation.h>
#include <math.h>

static inline NSDictionary *MSRuntimeSettings(void) {
    static NSDictionary *snapshot;
    static NSTimeInterval last;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (!snapshot || now < last || now - last >= .25) {
        snapshot = MSReadPreferences(NULL);
        last = now;
    }
    return snapshot;
}
static inline BOOL MSRuntimeFlag(NSString *key) {
    NSDictionary *snapshot = MSRuntimeSettings();
    return MSPreferenceFlag(snapshot, @"Enabled") && MSPreferenceFlag(snapshot, key);
}
static inline double MSRuntimeNumber(NSString *key, double fallback, double low, double high) {
    id value = MSRuntimeSettings()[key];
    double number = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : fallback;
    return isfinite(number) ? fmax(low, fmin(high, number)) : fallback;
}
static inline BOOL MSNativeInversionRequested(void) {
    static NSTimeInterval last;
    static BOOL requested;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (!last || now < last || now-last >= .5) {
        last = now;
        CFStringRef domain = CFSTR("com.go.mangoosprefs");
        if (!CFPreferencesAppSynchronize(domain)) { requested = NO; return NO; }
        id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("LeXiang.UpsideDown.Enabled"), domain));
        requested = [value isKindOfClass:NSNumber.class] && [value boolValue];
    }
    return requested;
}
