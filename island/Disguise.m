#import "Disguise.h"
#import "Settings.h"
#import "IslandPolicy.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>

// Where iOS 16.5 keeps the cache, and the obfuscated key of ArtworkDeviceSubType
// inside its CacheExtra dictionary: both read from Mango (Beta9 and Beta12).
static NSString *const GestaltPath = @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist";
static NSString *const SubtypeKey = @"oPeik/9e8lQWMszEjbPzng";

static NSDictionary *Fail(NSString *message) { return @{@"ok": @NO, @"message": message ?: @"失败"}; }
static double Now(void) { return NSDate.date.timeIntervalSince1970; }

static void EnsureDirectory(void) {
    [NSFileManager.defaultManager createDirectoryAtPath:DIDirectory() withIntermediateDirectories:YES attributes:nil error:nil];
}
static NSDictionary *ReadPlist(NSString *name) { return [NSDictionary dictionaryWithContentsOfFile:DIFile(name)]; }
static BOOL WritePlist(NSDictionary *dictionary, NSString *name) {
    EnsureDirectory();
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:dictionary format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    return data && [data writeToFile:DIFile(name) options:NSDataWritingAtomic error:nil];
}
static int64_t NumberIn(NSDictionary *dictionary, NSString *key) {
    id value = dictionary[key];
    return [value isKindOfClass:NSNumber.class] ? [value longLongValue] : 0;
}

// ---- The MobileGestalt cache ----------------------------------------------

static NSMutableDictionary *LoadGestalt(NSData **raw, NSString **why) {
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:GestaltPath options:0 error:&error];
    if (!data) {
        if (why) *why = [NSString stringWithFormat:@"读不到 MobileGestalt 缓存（%@）", error.localizedDescription ?: @"未知原因"];
        return nil;
    }
    NSPropertyListFormat format = 0;
    id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:&format error:&error];
    if (![plist isKindOfClass:NSMutableDictionary.class]) {
        if (why) *why = @"MobileGestalt 缓存的格式不认识";
        return nil;
    }
    NSMutableDictionary *top = plist;
    if (![top[@"CacheExtra"] isKindOfClass:NSMutableDictionary.class]) {
        if (why) *why = @"MobileGestalt 缓存里没有 CacheExtra";
        return nil;
    }
    if (raw) *raw = data;
    return top;
}

static int64_t SubtypeIn(NSMutableDictionary *plist) {
    NSDictionary *extra = plist[@"CacheExtra"];
    return NumberIn(extra, SubtypeKey);
}

// Mango writes the cache back as XML with an atomic replace, and no chmod; so
// does this. The value is read back afterwards.
static BOOL WriteSubtype(int64_t value, NSString **why) {
    NSMutableDictionary *plist = LoadGestalt(NULL, why);
    if (!plist) return NO;
    NSMutableDictionary *extra = plist[@"CacheExtra"];
    if (![extra[SubtypeKey] isKindOfClass:NSNumber.class]) {
        if (why) *why = @"缓存里没有机型条目，没有改动";
        return NO;
    }
    extra[SubtypeKey] = @(value);
    NSError *error = nil;
    NSData *out = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    if (!out || ![out writeToFile:GestaltPath options:NSDataWritingAtomic error:&error]) {
        if (why) *why = [NSString stringWithFormat:@"写入失败（%@）", error.localizedDescription ?: @"未知原因"];
        return NO;
    }
    NSMutableDictionary *check = LoadGestalt(NULL, why);
    if (!check || SubtypeIn(check) != value) {
        if (why) *why = @"写入后回读的机型值不对";
        return NO;
    }
    return YES;
}

// ---- Guard ------------------------------------------------------------------

static IMGuardState Guard;
static BOOL GuardLoaded;

static void GuardSave(void) {
    WritePlist(@{@"Armed": @(Guard.armed), @"ShortRuns": @(Guard.shortRuns), @"ArmedAt": @(Guard.armedAt),
                 @"LastStart": @(Guard.lastStart), @"LastAlive": @(Guard.lastAlive)}, @"guard.plist");
}
static void GuardLoad(void) {
    memset(&Guard, 0, sizeof Guard);
    NSDictionary *saved = ReadPlist(@"guard.plist");
    if ([saved[@"Armed"] isKindOfClass:NSNumber.class]) {
        Guard.armed = [saved[@"Armed"] boolValue];
        Guard.shortRuns = (int)NumberIn(saved, @"ShortRuns");
        Guard.armedAt = [saved[@"ArmedAt"] doubleValue];
        Guard.lastStart = [saved[@"LastStart"] doubleValue];
        Guard.lastAlive = [saved[@"LastAlive"] doubleValue];
    }
    GuardLoaded = YES;
}
static void GuardArm(void) {
    if (!GuardLoaded) GuardLoad();
    IMGuardArm(&Guard, Now());
    GuardSave();
}
static void GuardDisarm(void) {
    if (!GuardLoaded) GuardLoad();
    IMGuardDisarm(&Guard);
    GuardSave();
}

BOOL DIGuardStartup(void) {
    GuardLoad();
    BOOL trip = IMGuardLaunch(&Guard, Now());
    GuardSave();
    return trip;
}
void DIGuardTick(void) {
    if (!GuardLoaded || !Guard.armed) return;
    IMGuardAlive(&Guard, Now());
    GuardSave();
}
BOOL DIGuardArmed(void) { return GuardLoaded && Guard.armed; }

// ---- Operations -------------------------------------------------------------

NSDictionary *DIDisguiseStatus(double nativeHeight) {
    NSString *why = nil;
    NSMutableDictionary *plist = LoadGestalt(NULL, &why);
    int64_t original = NumberIn(ReadPlist(@"original.plist"), @"Subtype");
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    out[@"ok"] = @(plist != nil);
    out[@"message"] = plist ? @"" : (why ?: @"");
    if (plist) out[@"subtype"] = @(SubtypeIn(plist));
    if (original > 0) out[@"original"] = @(original);
    out[@"nativeHeight"] = @(nativeHeight);
    out[@"hardwareIsland"] = @(IMHardwareHasIsland(nativeHeight));
    out[@"restore"] = @(IMRestoreValue(original > 0, original, nativeHeight));
    out[@"applied"] = @([ReadPlist(@"state.plist")[@"Applied"] boolValue]);
    out[@"guardArmed"] = @(DIGuardArmed());
    return out;
}

NSDictionary *DIDisguiseApply(NSInteger mode, double nativeHeight) {
    NSString *why = nil;
    NSData *raw = nil;
    NSMutableDictionary *plist = LoadGestalt(&raw, &why);
    if (!plist) return Fail(why);
    int64_t current = SubtypeIn(plist), target = IMSubtypeForMode((int)mode);

    switch (IMApplyDecide(current, target, nativeHeight)) {
        case IMApplyUnreadable:
            return Fail(@"读不到当前的机型值，什么都没改。");
        case IMApplyHardwareIsland:
            return Fail(@"这台手机自带灵动岛，不需要伪装，什么都没改。");
        case IMApplyAlreadyIsland:
            return @{@"ok": @YES, @"message": @"机型值已经是这个样式，没有改动。", @"subtype": @(current), @"respring": @NO};
        case IMApplyOK:
            break;
    }

    // Keep the first original forever; never store a disguise as the original.
    int64_t original = NumberIn(ReadPlist(@"original.plist"), @"Subtype");
    BOOL have = original > 0;
    NSString *note = @"";
    switch (IMBackupDecide(have, current)) {
        case IMBackupKeep:
            break;
        case IMBackupUnreadable:
            return Fail(@"读不到当前的机型值，什么都没改。");
        case IMBackupUnknown:
            note = @"原机型值之前已被改过又没有备份，还原时会按屏幕推算。";
            break;
        case IMBackupStore: {
            EnsureDirectory();
            NSError *error = nil;
            if (![raw writeToFile:DIFile(@"MobileGestalt.original.plist") options:NSDataWritingAtomic error:&error])
                return Fail([NSString stringWithFormat:@"备份原缓存失败，什么都没改（%@）", error.localizedDescription ?: @"未知原因"]);
            if (!WritePlist(@{@"Subtype": @(current), @"SavedAt": @(Now()), @"System": NSProcessInfo.processInfo.operatingSystemVersionString},
                            @"original.plist"))
                return Fail(@"备份原机型值失败，什么都没改。");
            original = current;
            have = YES;
            break;
        }
    }

    int64_t restore = IMRestoreValue(have, original, nativeHeight);
    if (restore <= 0) return Fail(@"算不出还原用的值，什么都没改。");

    if (!WriteSubtype(target, &why)) return Fail(why);
    if (!WritePlist(@{@"Applied": @YES, @"Mode": @(mode), @"Target": @(target), @"Previous": @(current),
                      @"RestoreValue": @(restore), @"AppliedAt": @(Now())}, @"state.plist")) {
        WriteSubtype(current, NULL);  // no record to restore from: take the change back
        return Fail(@"保存还原记录失败，已把机型值写回原样。");
    }
    GuardArm();

    NSMutableDictionary *out = [@{@"ok": @YES, @"subtype": @(target), @"restore": @(restore), @"respring": @YES,
                                  @"message": [NSString stringWithFormat:@"已把机型值从 %lld 改成 %lld。%@", current, target, note]} mutableCopy];
    if (have) out[@"original"] = @(original);
    return out;
}

NSDictionary *DIDisguiseRestore(double nativeHeight) {
    NSString *why = nil;
    NSMutableDictionary *plist = LoadGestalt(NULL, &why);
    if (!plist) return Fail(why);
    int64_t current = SubtypeIn(plist);
    int64_t original = NumberIn(ReadPlist(@"original.plist"), @"Subtype");
    int64_t value = IMRestoreValue(original > 0, original, nativeHeight);
    if (value <= 0) return Fail(@"算不出要还原成的值，什么都没改。");
    BOOL applied = [ReadPlist(@"state.plist")[@"Applied"] boolValue];

    if (current == value && !applied)
        return @{@"ok": @YES, @"message": @"机型值本来就是原值，没有改动。", @"subtype": @(current), @"respring": @NO};
    if (current != value && !WriteSubtype(value, &why)) return Fail(why);
    WritePlist(@{@"Applied": @NO, @"RestoredAt": @(Now()), @"Value": @(value)}, @"state.plist");
    GuardDisarm();
    return @{@"ok": @YES, @"subtype": @(value), @"restore": @(value), @"respring": @YES,
             @"message": [NSString stringWithFormat:@"已把机型值从 %lld 还原成 %lld。", current, value]};
}

BOOL DIDisguiseRestoreFromState(NSString **note) {
    NSDictionary *state = ReadPlist(@"state.plist");
    int64_t value = NumberIn(state, @"RestoreValue");
    if (![state[@"Applied"] boolValue] || value <= 0 || IMIsIslandSubtype(value)) {
        if (note) *note = @"没有可用的还原记录";
        return NO;
    }
    NSString *why = nil;
    if (!WriteSubtype(value, &why)) {
        if (note) *note = why;
        return NO;
    }
    WritePlist(@{@"Applied": @NO, @"RestoredAt": @(Now()), @"Value": @(value), @"By": @"launch"}, @"state.plist");
    GuardDisarm();
    if (note) *note = [NSString stringWithFormat:@"已写回 %lld", value];
    return YES;
}

BOOL DIRespring(void) {
    Class service = objc_getClass("FBSystemService");
    SEL shared = sel_registerName("sharedInstance"), relaunch = sel_registerName("exitAndRelaunch:");
    if (!service || ![service respondsToSelector:shared]) return NO;
    id instance = ((id (*)(id, SEL))objc_msgSend)((id)service, shared);
    if (!instance || ![instance respondsToSelector:relaunch]) return NO;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(instance, relaunch, YES);
    return YES;
}
