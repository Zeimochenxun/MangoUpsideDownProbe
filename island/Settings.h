// Shared by the SpringBoard tweak and the Settings pane. Like DoubleDock this is
// plain files in the jailbreak root, no CFPreferences daemon in between:
//   settings.plist  written by the pane, re-read by SpringBoard within 250ms
//   request.plist / result.plist  the pane asks SpringBoard to change the
//                   device model value or the screen canvas (SpringBoard is
//                   where Mango does both from)
//   status.plist    what the tweak last saw, shown in the pane
//   state.plist, guard.plist, original.plist, MobileGestalt.original.plist
//                   the model-change bookkeeping and the crash guard (Disguise.m)
//   canvas.plist, panel.plist, IOMobileGraphicsFamily.foreign.plist
//                   the screen-canvas bookkeeping and the panel's own pixel
//                   size as seen while no canvas was active (Canvas.m)
#pragma once
#import <Foundation/Foundation.h>
#import <roothide.h>
#include <math.h>
#include "IslandMath.h"
#include "IslandPolicy.h"

#ifndef DI_VERSION
#define DI_VERSION "dev"
#endif

static NSString *const DINotifySettings = @"com.chenxun.dynamicisland.settings";
static NSString *const DINotifyRequest = @"com.chenxun.dynamicisland.request";

// Real paths, not jbroot: files a user can create from Filza or ssh when the
// Settings pane is out of reach.
#define DI_DISABLED_PATH "/var/mobile/Library/Preferences/DynamicIsland.disabled"
#define DI_RESTORE_PATH "/var/mobile/Library/Preferences/DynamicIsland.restore"

// The screen canvas: the two real paths of Mango's applyResolutionWithWidth:
// height: (the plist in /var/tmp and the link to it in Preferences). [read]
#define DI_CANVAS_FILE "/var/tmp/com.apple.iokit.IOMobileGraphicsFamily.plist"
#define DI_CANVAS_LINK "/private/var/mobile/Library/Preferences/com.apple.iokit.IOMobileGraphicsFamily.plist"
// The same file spelled with the /private prefix: a link whose destination was
// resolved that way still points at the canvas file.
#define DI_CANVAS_FILE_ALT "/private/var/tmp/com.apple.iokit.IOMobileGraphicsFamily.plist"

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

// The simulation style the pane has selected: 0 = Pro (2556), 1 = Pro Max (2796)
// (Mango's MangoDynamicIslandSimulationMode), and the canvas preset it has
// selected (Mango's MangoResolutionPresetIndex). Always valid values.
static inline NSInteger DIMode(NSDictionary *settings) {
    return (NSInteger)DINumber(settings, @"Mode", 0) == 1 ? 1 : 0;
}
static inline NSInteger DIPreset(NSDictionary *settings) {
    NSInteger index = (NSInteger)DINumber(settings, @"ResolutionPreset", IM_PRESET_DEFAULT);
    return IMPresetAt((int)index) ? index : IM_PRESET_DEFAULT;
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

// Pane side of the request protocol. Actions: status, apply (mode), restore,
// canvas-apply (preset), canvas-restore. Returns the request id to look for in
// result.plist, or nil with `error` set.
static inline NSString *DISubmitRequest(NSString *action, NSInteger mode, NSInteger preset, NSError **error) {
    NSString *identifier = NSUUID.UUID.UUIDString;
    NSDictionary *request = @{@"id": identifier, @"action": action, @"mode": @(mode), @"preset": @(preset),
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
