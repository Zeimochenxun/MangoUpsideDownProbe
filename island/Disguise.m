#import "Disguise.h"
#import "Settings.h"
#import "IslandPolicy.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
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

// The model value in the cache: IM_ENTRY_ABSENT when CacheExtra has no entry for
// it, IM_ENTRY_UNUSABLE when it has one that is not a positive whole number,
// else the value. A missing entry is a normal state (IslandPolicy.h).
static int64_t SubtypeIn(NSMutableDictionary *plist) {
    NSDictionary *extra = plist[@"CacheExtra"];
    id value = extra[SubtypeKey];
    if (!value) return IM_ENTRY_ABSENT;
    if (![value isKindOfClass:NSNumber.class]) return IM_ENTRY_UNUSABLE;
    int64_t number = [value longLongValue];
    return number > 0 ? number : IM_ENTRY_UNUSABLE;
}

// The entry in words, for the pane and the log.
static NSString *EntryText(NSMutableDictionary *plist) {
    NSDictionary *extra = plist[@"CacheExtra"];
    id value = extra[SubtypeKey];
    if (!value) return @"没有这一项";
    if ([value isKindOfClass:NSNumber.class]) return [NSString stringWithFormat:@"%@", value];
    return [NSString stringWithFormat:@"不是数字（%@）", NSStringFromClass([value class])];
}

// Mango writes the cache back as XML with an atomic replace, and no chmod; so
// does this. [read] Mango's modifyArtworkDeviceSubType: looks up CacheExtra once
// and sets the key, with no test of whether the key was there: a missing entry
// is added. Deleting the entry (`remove`) is the way back to "no entry". The
// entry is read back afterwards.
static BOOL WriteEntry(BOOL remove, int64_t value, NSString **why) {
    NSMutableDictionary *plist = LoadGestalt(NULL, why);
    if (!plist) return NO;
    NSMutableDictionary *extra = plist[@"CacheExtra"];
    if (remove) [extra removeObjectForKey:SubtypeKey];
    else extra[SubtypeKey] = @(value);
    NSError *error = nil;
    NSData *out = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    if (!out || ![out writeToFile:GestaltPath options:NSDataWritingAtomic error:&error]) {
        if (why) *why = [NSString stringWithFormat:@"写入失败（%@）", error.localizedDescription ?: @"未知原因"];
        return NO;
    }
    NSMutableDictionary *check = LoadGestalt(NULL, why);
    if (!check || SubtypeIn(check) != (remove ? IM_ENTRY_ABSENT : value)) {
        if (why) *why = @"写入后回读的机型值不对";
        return NO;
    }
    return YES;
}

// What the system itself answers for ArtworkDeviceSubType in this process
// (MGCopyAnswer), or -1 when it cannot be asked. This is what SpringBoard builds
// the island from, so it shows whether the cache entry is honoured; with no
// entry it is the phone's own value. SpringBoard reads the cache once at launch:
// a change written now shows here after the next respring.
int64_t DIEffectiveSubtype(void) {
    typedef CFTypeRef (*CopyAnswer)(CFStringRef);
    static CopyAnswer copy;
    if (!copy) copy = (CopyAnswer)dlsym(RTLD_DEFAULT, "MGCopyAnswer");
    if (!copy) return -1;
    CFTypeRef answer = copy(CFSTR("ArtworkDeviceSubType"));
    int64_t value = -1;
    if (answer && CFGetTypeID(answer) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)answer, kCFNumberSInt64Type, &value);
    if (answer) CFRelease(answer);
    return value;
}

// One line for the log: what the cache looks like and what the system answers,
// so a phone whose cache is unusual says so in the first export.
NSString *DIGestaltSummary(void) {
    NSString *why = nil;
    NSData *raw = nil;
    NSMutableDictionary *plist = LoadGestalt(&raw, &why);
    if (!plist) return [NSString stringWithFormat:@"GESTALT unreadable: %@ effective=%lld", why ?: @"?", DIEffectiveSubtype()];
    NSDictionary *extra = plist[@"CacheExtra"];
    NSArray *top = [plist.allKeys sortedArrayUsingSelector:@selector(compare:)];
    return [NSString stringWithFormat:@"GESTALT file=%luB top=[%@] extraEntries=%lu modelEntry=%@ effective=%lld", (unsigned long)raw.length,
            [top componentsJoinedByString:@","], (unsigned long)extra.count, EntryText(plist), DIEffectiveSubtype()];
}

// ---- Guard ------------------------------------------------------------------

static IMGuardState Guard;
static int GuardTargets;  // IM_GUARD_* bits the armed guard undoes if it trips
static int TripTargets;   // what this launch has to undo; valid after DIGuardStartup returned YES
static BOOL GuardLoaded;

static void GuardSave(void) {
    WritePlist(@{@"Armed": @(Guard.armed), @"ShortRuns": @(Guard.shortRuns), @"ArmedAt": @(Guard.armedAt),
                 @"LastStart": @(Guard.lastStart), @"LastAlive": @(Guard.lastAlive), @"Targets": @(GuardTargets)}, @"guard.plist");
}
static void GuardLoad(void) {
    memset(&Guard, 0, sizeof Guard);
    GuardTargets = 0;
    NSDictionary *saved = ReadPlist(@"guard.plist");
    if ([saved[@"Armed"] isKindOfClass:NSNumber.class]) {
        Guard.armed = [saved[@"Armed"] boolValue];
        Guard.shortRuns = (int)NumberIn(saved, @"ShortRuns");
        Guard.armedAt = [saved[@"ArmedAt"] doubleValue];
        Guard.lastStart = [saved[@"LastStart"] doubleValue];
        Guard.lastAlive = [saved[@"LastAlive"] doubleValue];
        // A guard file from 0.1.0 has no list: only the model change existed then.
        GuardTargets = saved[@"Targets"] ? (int)NumberIn(saved, @"Targets") & IM_GUARD_ALL : IM_GUARD_DISGUISE;
        if (!Guard.armed) GuardTargets = 0;
        else if (!GuardTargets) IMGuardDisarm(&Guard);  // armed with nothing to undo
    }
    GuardLoaded = YES;
}

void DIGuardArmFor(int target) {
    if (!GuardLoaded) GuardLoad();
    GuardTargets = IMGuardTargetsOnArm(Guard.armed, GuardTargets, target);
    IMGuardArm(&Guard, Now());
    GuardSave();
}
void DIGuardDoneFor(int target) {
    if (!GuardLoaded) GuardLoad();
    GuardTargets = IMGuardTargetsOnDone(GuardTargets, target);
    if (!GuardTargets) IMGuardDisarm(&Guard);
    GuardSave();
}

BOOL DIGuardStartup(void) {
    GuardLoad();
    BOOL trip = IMGuardLaunch(&Guard, Now());
    TripTargets = trip ? GuardTargets : 0;
    GuardSave();
    return trip;
}
int DIGuardTargets(void) { return TripTargets; }
void DIGuardTick(void) {
    if (!GuardLoaded || !Guard.armed) return;
    IMGuardAlive(&Guard, Now());
    if (!Guard.armed) GuardTargets = 0;  // lived long enough: nothing left to undo
    GuardSave();
}
BOOL DIGuardArmed(void) { return GuardLoaded && Guard.armed; }

// ---- Operations -------------------------------------------------------------

// What original.plist says the first original was (IslandPolicy.h).
static IMOriginal StoredOriginal(void) {
    NSDictionary *saved = ReadPlist(@"original.plist");
    return IMStoredOriginal(NumberIn(saved, @"Subtype"), [saved[@"Absent"] boolValue]);
}

NSDictionary *DIDisguiseStatus(double nativeHeight) {
    NSString *why = nil;
    NSMutableDictionary *plist = LoadGestalt(NULL, &why);
    IMOriginal original = StoredOriginal();
    IMRestorePlan plan = IMRestorePlanNow(original, plist ? SubtypeIn(plist) : IM_ENTRY_UNUSABLE, nativeHeight);
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    out[@"ok"] = @(plist != nil);
    out[@"message"] = plist ? @"" : (why ?: @"");
    if (plist) {
        int64_t current = SubtypeIn(plist);
        out[@"subtype"] = @(current > 0 ? current : 0);
        out[@"entry"] = current > 0 ? @"value" : (current == IM_ENTRY_ABSENT ? @"absent" : @"unusable");
        out[@"entryText"] = EntryText(plist);
        out[@"simulated"] = @(IMIsSimulated(current, nativeHeight));
    }
    if (original.kind == IMOriginalValue) out[@"original"] = @(original.value);
    out[@"originalAbsent"] = @(original.kind == IMOriginalAbsent);
    out[@"effective"] = @(DIEffectiveSubtype());
    out[@"nativeHeight"] = @(nativeHeight);
    out[@"hardwareIsland"] = @(IMHardwareHasIsland(nativeHeight));
    out[@"restore"] = @(plan.value);
    out[@"restoreRemoves"] = @(plan.remove);
    out[@"applied"] = @([ReadPlist(@"state.plist")[@"Applied"] boolValue]);
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    out[@"osSupported"] = @(IMOSSupportsSimulation((long)os.majorVersion, (long)os.minorVersion));
    out[@"guardArmed"] = @(DIGuardArmed());
    return out;
}

NSDictionary *DIDisguiseApply(NSInteger mode, double nativeHeight) {
    // Mango's own gate, before anything is read or written.
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    if (!IMOSSupportsSimulation((long)os.majorVersion, (long)os.minorVersion))
        return Fail(@"灵动岛模拟需要 iOS 16.1 及以上系统，当前系统版本过低，什么都没改。");
    NSString *why = nil;
    NSData *raw = nil;
    NSMutableDictionary *plist = LoadGestalt(&raw, &why);
    if (!plist) return Fail(why);
    int64_t current = SubtypeIn(plist), target = IMSubtypeForMode((int)mode);

    // An entry that exists but is not a number is the only unreadable case: a
    // missing entry is simply added (what Mango does).
    switch (IMApplyDecide(current, target, nativeHeight)) {
        case IMApplyUnreadable:
            return Fail([NSString stringWithFormat:@"缓存里机型值那一项%@，不敢改，什么都没改。", EntryText(plist)]);
        case IMApplyHardwareIsland:
            return Fail(@"这台手机自带灵动岛，不需要伪装，什么都没改。");
        case IMApplyAlreadyIsland:
            return @{@"ok": @YES, @"message": @"机型值已经是这个样式，没有改动。", @"subtype": @(current), @"respring": @NO};
        case IMApplyOK:
            break;
    }

    // Keep the first original forever; never store a disguise as the original.
    IMOriginal original = StoredOriginal();
    NSString *note = @"";
    switch (IMBackupDecide(original, current)) {
        case IMBackupKeep:
            break;
        case IMBackupUnreadable:
            return Fail([NSString stringWithFormat:@"缓存里机型值那一项%@，不敢改，什么都没改。", EntryText(plist)]);
        case IMBackupUnknown:
            note = @"原机型值之前已被改过又没有备份，还原时会按屏幕推算。";
            break;
        case IMBackupStore:
        case IMBackupStoreAbsent: {
            BOOL absent = current == IM_ENTRY_ABSENT;
            EnsureDirectory();
            NSError *error = nil;
            if (![raw writeToFile:DIFile(@"MobileGestalt.original.plist") options:NSDataWritingAtomic error:&error])
                return Fail([NSString stringWithFormat:@"备份原缓存失败，什么都没改（%@）", error.localizedDescription ?: @"未知原因"]);
            NSMutableDictionary *record = [@{@"SavedAt": @(Now()), @"System": NSProcessInfo.processInfo.operatingSystemVersionString} mutableCopy];
            if (absent) record[@"Absent"] = @YES;
            else record[@"Subtype"] = @(current);
            if (!WritePlist(record, @"original.plist")) return Fail(@"备份原机型值失败，什么都没改。");
            original = IMStoredOriginal(absent ? 0 : current, absent);
            if (absent) note = @"缓存里原来没有机型值这一项，已记下；取消模拟时会把它删掉。";
            break;
        }
    }

    IMRestorePlan plan = IMRestorePlanFor(original, nativeHeight);
    if (!plan.remove && plan.value <= 0) return Fail(@"算不出还原用的值，什么都没改。");

    if (!WriteEntry(NO, target, &why)) return Fail(why);
    if (!WritePlist(@{@"Applied": @YES, @"Mode": @(mode), @"Target": @(target), @"Previous": @(current > 0 ? current : 0),
                      @"RestoreValue": @(plan.value), @"RestoreRemove": @(plan.remove), @"AppliedAt": @(Now())}, @"state.plist")) {
        WriteEntry(current == IM_ENTRY_ABSENT, current > 0 ? current : 0, NULL);  // no record to restore from: take the change back
        return Fail(@"保存还原记录失败，已把机型值写回原样。");
    }
    DIGuardArmFor(IM_GUARD_DISGUISE);

    NSString *before = current > 0 ? [NSString stringWithFormat:@"%lld", current] : @"（没有这一项）";
    NSMutableDictionary *out = [@{@"ok": @YES, @"subtype": @(target), @"restore": @(plan.value), @"restoreRemoves": @(plan.remove), @"respring": @YES,
                                  @"message": [NSString stringWithFormat:@"已把机型值从 %@ 改成 %lld。%@", before, target, note]} mutableCopy];
    if (original.kind == IMOriginalValue) out[@"original"] = @(original.value);
    return out;
}

NSDictionary *DIDisguiseRestore(double nativeHeight) {
    NSString *why = nil;
    NSMutableDictionary *plist = LoadGestalt(NULL, &why);
    if (!plist) return Fail(why);
    int64_t current = SubtypeIn(plist);
    IMRestorePlan plan = IMRestorePlanNow(StoredOriginal(), current, nativeHeight);
    if (!plan.remove && plan.value <= 0) return Fail(@"算不出要还原成的值，什么都没改。");
    BOOL applied = [ReadPlist(@"state.plist")[@"Applied"] boolValue];
    BOOL holds = IMPlanAlreadyHolds(plan, current);

    if (holds && !applied)
        return @{@"ok": @YES, @"message": @"机型值本来就是原值，没有改动。", @"subtype": @(current > 0 ? current : 0), @"respring": @NO};
    if (!holds && !WriteEntry(plan.remove, plan.value, &why)) return Fail(why);
    WritePlist(@{@"Applied": @NO, @"RestoredAt": @(Now()), @"Value": @(plan.value), @"Removed": @(plan.remove)}, @"state.plist");
    DIGuardDoneFor(IM_GUARD_DISGUISE);
    NSString *before = current > 0 ? [NSString stringWithFormat:@"%lld", current] : @"（没有这一项）";
    NSString *message = plan.remove ? [NSString stringWithFormat:@"已把机型值从 %@ 还原：删掉了这一项（原来就没有）。", before]
                                    : [NSString stringWithFormat:@"已把机型值从 %@ 还原成 %lld。", before, plan.value];
    return @{@"ok": @YES, @"subtype": @(plan.remove ? 0 : plan.value), @"restore": @(plan.value), @"restoreRemoves": @(plan.remove),
             @"respring": @YES, @"message": message};
}

BOOL DIDisguiseRestoreFromState(NSString **note) {
    NSDictionary *state = ReadPlist(@"state.plist");
    BOOL remove = [state[@"RestoreRemove"] boolValue];
    int64_t value = NumberIn(state, @"RestoreValue");
    if (![state[@"Applied"] boolValue] || (!remove && (value <= 0 || IMIsIslandSubtype(value)))) {
        if (note) *note = @"没有可用的还原记录";
        return NO;
    }
    NSString *why = nil;
    if (!WriteEntry(remove, value, &why)) {
        if (note) *note = why;
        return NO;
    }
    WritePlist(@{@"Applied": @NO, @"RestoredAt": @(Now()), @"Value": @(value), @"Removed": @(remove), @"By": @"launch"}, @"state.plist");
    DIGuardDoneFor(IM_GUARD_DISGUISE);
    if (note) *note = remove ? @"已删掉机型值那一项" : [NSString stringWithFormat:@"已写回 %lld", value];
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
