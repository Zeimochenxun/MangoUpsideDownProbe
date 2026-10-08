#import "SuitePreferences.h"
#import <roothide.h>
#include <math.h>

static NSString * const ErrorDomain = @"com.chenxun.mangosuite.storage";

NSString *MSPreferencesPath(void) {
    // One mobile-user file for Settings, SpringBoard and backboardd. Keep it
    // outside CFPreferences so an older daemon cache cannot overwrite it.
    return [NSString stringWithUTF8String:jbroot("/var/mobile/Library/Application Support/MangoSuite/settings.plist")];
}

static NSError *StorageError(NSString *description, NSString *path, NSError *cause) {
    NSMutableDictionary *details = [@{NSLocalizedDescriptionKey: description, NSFilePathErrorKey: path} mutableCopy];
    if (cause) details[NSUnderlyingErrorKey] = cause;
    return [NSError errorWithDomain:ErrorDomain code:1 userInfo:details];
}

static NSDictionary *ReadFile(NSString *path, BOOL *missing, NSError **error) {
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&readError];
    *missing = !data && [readError.domain isEqualToString:NSCocoaErrorDomain] && readError.code == NSFileReadNoSuchFileError;
    if (*missing) return nil;
    if (!data) {
        if (error) *error = StorageError(@"无法读取整合开关。", path, readError);
        return nil;
    }
    id snapshot = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&readError];
    if (![snapshot isKindOfClass:NSDictionary.class]) {
        if (error) *error = StorageError(@"整合开关文件格式无效，原文件已保留。", path, readError);
        return nil;
    }
    return snapshot;
}

NSDictionary *MSReadPreferences(NSError **error) {
    if (error) *error = nil;
    BOOL missing = NO;
    NSDictionary *snapshot = ReadFile(MSPreferencesPath(), &missing, error);
    if (!missing) return snapshot;

    // Preserve valid alpha1–alpha3 settings, including RootHide's redirected
    // CFPreferences file. First successful edit copies the whole dictionary.
    NSString *legacy = @"/var/mobile/Library/Preferences/com.chenxun.mangosuite.plist";
    NSString *redirected = [NSString stringWithUTF8String:jbroot(legacy.fileSystemRepresentation)];
    snapshot = ReadFile(redirected, &missing, error);
    if (!missing) return snapshot;
    if (![redirected isEqualToString:legacy]) {
        snapshot = ReadFile(legacy, &missing, error);
        if (!missing) return snapshot;
    }
    return @{};
}

BOOL MSPreferenceFlag(NSDictionary *snapshot, NSString *key) {
    if ([key isEqualToString:@"CrashIsolationEnabled"]) {
        id value=snapshot[key];
        // Missing or malformed isolation settings cannot re-enable hooks.
        return !([value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]) && [value doubleValue]==0);
    }
    if (!snapshot) return NO;
    id value = snapshot[key];
    BOOL defaultValue = ![@[@"EdgeColorEnabled", @"DebugEnabled"] containsObject:key];
    return value == nil ? defaultValue : ([value isKindOfClass:NSNumber.class] && [value boolValue]);
}

BOOL MSWritePreferenceFlag(NSString *key, BOOL enabled, NSError **error) {
    return MSWritePreferenceValue(key, @(enabled), error);
}

NSArray<NSString *> *MSRepairKeys(void) {
    return @[@"RimGeometryEnabled", @"LauncherRecoveryEnabled", @"GlassAnimationEnabled",
             @"IslandLayoutEnabled", @"ShortHaloEnabled", @"EdgeColorEnabled", @"SwipeDirectionEnabled"];
}

BOOL MSWritePreferenceValue(NSString *key, id value, NSError **error) {
    if (error) *error = nil;
    NSString *path = MSPreferencesPath();
    NSArray *known = [@[@"Enabled", @"IdleEnabled", @"AdaptiveEnabled", @"WorldEnabled", @"SplitEnabled",
        @"DebugEnabled", @"DebugSessionToken", @"EdgeThickness", @"EdgeDynamics", @"CrashIsolationEnabled"] arrayByAddingObjectsFromArray:MSRepairKeys()];
    BOOL valid = [known containsObject:key] && [value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]);
    if ([key isEqualToString:@"EdgeThickness"]) valid = valid && [value doubleValue] >= .5 && [value doubleValue] <= 4;
    if ([key isEqualToString:@"EdgeDynamics"]) valid = valid && [value doubleValue] >= 0 && [value doubleValue] <= 1;
    if (!valid) {
        if (error) *error = StorageError(@"未知的整合开关。", path, nil);
        return NO;
    }
    NSDictionary *current = MSReadPreferences(error);
    if (!current) return NO;
    NSMutableDictionary *next = [current mutableCopy];
    next[key] = value;
    NSError *writeError = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:next format:NSPropertyListBinaryFormat_v1_0 options:0 error:&writeError];
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *parent = path.stringByDeletingLastPathComponent;
    if (!data || ![files createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0755} error:&writeError]) {
        if (error) *error = StorageError(@"无法创建整合开关文件。", path, writeError);
        return NO;
    }
    NSData *previous = [NSData dataWithContentsOfFile:path];
    if (![data writeToFile:path options:NSDataWritingAtomic error:&writeError]) {
        if (error) *error = StorageError(@"无法保存整合开关，原设置已保留。", path, writeError);
        return NO;
    }
    BOOL missing = NO;
    NSDictionary *saved = ReadFile(path, &missing, &writeError);
    if (![saved isEqualToDictionary:next]) {
        NSError *rollbackError = nil;
        BOOL restored = previous ? [previous writeToFile:path options:NSDataWritingAtomic error:&rollbackError]
                                 : [files removeItemAtPath:path error:&rollbackError];
        if (error) *error = StorageError(restored ? @"保存校验失败，原设置已恢复。" : @"保存校验失败，原设置未能恢复。", path, rollbackError ?: writeError);
        return NO;
    }
    return YES;
}

NSString *MSMarkerForKey(NSString *key) {
    // These are the original binaries' emergency paths, not CF preference domains.
    if ([key isEqualToString:@"IdleEnabled"]) return @"/var/mobile/Library/Logs/MangoIdleIsland/DISABLED";
    if ([key isEqualToString:@"WorldEnabled"]) return @"/var/mobile/Library/Preferences/MangoUpsideDownWorld.disabled";
    if ([key isEqualToString:@"SplitEnabled"]) return @"/var/mobile/Library/Preferences/MangoSplitUpsideDownFix.disabled";
    return nil;
}

NSArray<NSString *> *MSMarkerPathsForKey(NSString *key) {
    NSString *legacy = MSMarkerForKey(key);
    if (!legacy) return @[];
    NSString *redirected = [NSString stringWithUTF8String:jbroot(legacy.fileSystemRepresentation)];
    return [redirected isEqualToString:legacy] ? @[legacy] : @[legacy, redirected];
}

BOOL MSHasEmergencyMarker(NSString *key) {
    for (NSString *path in MSMarkerPathsForKey(key))
        if ([NSFileManager.defaultManager fileExistsAtPath:path]) return YES;
    return NO;
}
