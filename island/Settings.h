// Shared by the SpringBoard tweak and the Settings pane. Like DoubleDock this is
// plain files in the jailbreak root, no CFPreferences daemon in between:
//   settings.plist  written by the pane, re-read by SpringBoard within 250ms
//   request.plist / result.plist  the pane asks SpringBoard to change the
//                   device model value (SpringBoard is where Mango does it from)
//   status.plist    what the tweak last saw, shown in the pane
//   state.plist, guard.plist, original.plist, MobileGestalt.original.plist
//                   the disguise bookkeeping (Disguise.m)
#pragma once
#import <Foundation/Foundation.h>
#import <roothide.h>
#include <math.h>
#include "IslandMath.h"

#ifndef DI_VERSION
#define DI_VERSION "dev"
#endif

static NSString *const DINotifySettings = @"com.chenxun.dynamicisland.settings";
static NSString *const DINotifyRequest = @"com.chenxun.dynamicisland.request";

// Real paths, not jbroot: files a user can create from Filza or ssh when the
// Settings pane is out of reach.
#define DI_DISABLED_PATH "/var/mobile/Library/Preferences/DynamicIsland.disabled"
#define DI_RESTORE_PATH "/var/mobile/Library/Preferences/DynamicIsland.restore"

static inline NSString *DIJB(const char *path) { return [NSString stringWithUTF8String:jbroot(path)]; }
static inline NSString *DIDirectory(void) { return DIJB("/var/mobile/Library/Application Support/DynamicIsland"); }
static inline NSString *DIFile(NSString *name) { return [DIDirectory() stringByAppendingPathComponent:name]; }

static inline NSDictionary *DIReadSettings(void) {
    NSDictionary *own = [NSDictionary dictionaryWithContentsOfFile:DIFile(@"settings.plist")];
    return own ?: @{};
}

static inline double DINumber(NSDictionary *settings, NSString *key, double fallback) {
    id value = settings[key];
    return [value isKindOfClass:NSNumber.class] ? [value doubleValue] : fallback;
}

static inline BOOL DIFlag(NSDictionary *settings, NSString *key, BOOL fallback) {
    id value = settings[key];
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : fallback;
}

// The size/position the user asked for, always inside the limits.
static inline IMAdjust DIAdjust(NSDictionary *settings) {
    return IMSanitize((IMAdjust){DINumber(settings, @"Scale", 1.0), DINumber(settings, @"OffsetX", 0.0),
                                 DINumber(settings, @"OffsetY", 0.0), DINumber(settings, @"AnchorY", IM_ANCHOR_Y_DEFAULT)});
}

static inline BOOL DIWriteSettings(NSDictionary *changes, NSError **error) {
    NSMutableDictionary *next = [DIReadSettings() mutableCopy];
    [next addEntriesFromDictionary:changes];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:next format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    return data && [NSFileManager.defaultManager createDirectoryAtPath:DIDirectory() withIntermediateDirectories:YES attributes:nil error:error] &&
           [data writeToFile:DIFile(@"settings.plist") options:NSDataWritingAtomic error:error];
}

static inline void DIPost(NSString *name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)name, NULL, NULL, YES);
}

// Pane side of the request protocol. Returns the request id to look for in
// result.plist, or nil with `error` set.
static inline NSString *DISubmitRequest(NSString *action, NSInteger mode, NSError **error) {
    NSString *identifier = NSUUID.UUID.UUIDString;
    NSDictionary *request = @{@"id": identifier, @"action": action, @"mode": @(mode),
                              @"time": @(NSDate.timeIntervalSinceReferenceDate)};
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:request format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!data || ![NSFileManager.defaultManager createDirectoryAtPath:DIDirectory() withIntermediateDirectories:YES attributes:nil error:error] ||
        ![data writeToFile:DIFile(@"request.plist") options:NSDataWritingAtomic error:error])
        return nil;
    DIPost(DINotifyRequest);
    return identifier;
}

static inline NSDictionary *DIResultFor(NSString *identifier) {
    NSDictionary *result = [NSDictionary dictionaryWithContentsOfFile:DIFile(@"result.plist")];
    return [result[@"id"] isEqual:identifier] ? result : nil;
}
