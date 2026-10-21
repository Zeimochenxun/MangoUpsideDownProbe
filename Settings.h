// Shared by the SpringBoard tweak and the Settings pane: one plist outside
// CFPreferences (as Mango Suite does), so both read the same file with no
// daemon cache in between. SpringBoard re-reads it every 250ms.
#pragma once
#import <Foundation/Foundation.h>
#import <roothide.h>
#include <math.h>

static const NSUInteger DDPinnedMax = 5;
// Lift while inverted: the iPhone 13 mini's 5.35mm housing at 0.1537mm/pt.
static const double DDLiftDefault = 35, DDLiftMax = 50;

static inline NSString *DDJB(const char *path) { return [NSString stringWithUTF8String:jbroot(path)]; }
static inline NSString *DDDirectory(void) { return DDJB("/var/mobile/Library/Application Support/DoubleDock"); }
static inline NSString *DDFile(NSString *name) { return [DDDirectory() stringByAppendingPathComponent:name]; }
// Mango Suite 1.2.0~beta9.9.x had this drawer built in; its choices seed a first run.
static inline NSString *DDSuiteFile(NSString *name) {
    return [DDJB("/var/mobile/Library/Application Support/MangoSuite") stringByAppendingPathComponent:name];
}

static inline NSDictionary *DDReadSettings(void) {
    NSDictionary *own = [NSDictionary dictionaryWithContentsOfFile:DDFile(@"settings.plist")];
    if (own) return own;
    NSDictionary *suite = [NSDictionary dictionaryWithContentsOfFile:DDSuiteFile(@"settings.plist")];
    NSMutableDictionary *seed = [NSMutableDictionary dictionary];
    if ([suite[@"DockDrawerPinned"] isKindOfClass:NSArray.class]) seed[@"Pinned"] = suite[@"DockDrawerPinned"];
    if ([suite[@"DockDrawerDivider"] isKindOfClass:NSNumber.class]) seed[@"Divider"] = suite[@"DockDrawerDivider"];
    if ([suite[@"DockNotchEnabled"] isKindOfClass:NSNumber.class]) seed[@"NotchLift"] = suite[@"DockNotchEnabled"];
    if ([suite[@"DockNotchLift"] isKindOfClass:NSNumber.class]) seed[@"LiftHeight"] = suite[@"DockNotchLift"];
    return seed;
}

static inline double DDLiftHeight(NSDictionary *settings) {
    id value = settings[@"LiftHeight"];
    double height = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : DDLiftDefault;
    return isfinite(height) ? fmin(DDLiftMax, fmax(0, height)) : DDLiftDefault;
}

// Every switch (Enabled, Divider, FloatingDock, NotchLift) defaults on.
static inline BOOL DDFlag(NSDictionary *settings, NSString *key) {
    id value = settings[key];
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : YES;
}

// Row 2's pinned apps, in the order they were switched on.
static inline NSArray<NSString *> *DDPinned(NSDictionary *settings) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    id list = settings[@"Pinned"];
    if ([list isKindOfClass:NSArray.class])
        for (id bundle in list)
            if ([bundle isKindOfClass:NSString.class] && [bundle length] && ![out containsObject:bundle] && out.count < DDPinnedMax)
                [out addObject:bundle];
    return out;
}

static inline BOOL DDWriteSetting(NSString *key, id value, NSError **error) {
    NSMutableDictionary *next = [DDReadSettings() mutableCopy];
    next[key] = value;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:next format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    return data && [NSFileManager.defaultManager createDirectoryAtPath:DDDirectory() withIntermediateDirectories:YES attributes:nil error:error] &&
        [data writeToFile:DDFile(@"settings.plist") options:NSDataWritingAtomic error:error];
}
