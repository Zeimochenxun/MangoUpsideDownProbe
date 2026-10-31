#import "Canvas.h"
#import "Disguise.h"
#import "Settings.h"
#import "IslandPolicy.h"
#include <errno.h>
#include <limits.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static NSString *const CanvasFile = @DI_CANVAS_FILE;
static NSString *const CanvasLink = @DI_CANVAS_LINK;
static NSString *const StateName = @"canvas.plist";
static NSString *const ForeignName = @"IOMobileGraphicsFamily.foreign.plist";

static NSDictionary *Fail(NSString *message) { return @{@"ok": @NO, @"message": message ?: @"失败"}; }
static double Now(void) { return NSDate.date.timeIntervalSince1970; }

static NSDictionary *ReadState(void) { return [NSDictionary dictionaryWithContentsOfFile:DIFile(StateName)]; }
static BOOL WriteState(NSDictionary *dictionary) {
    [NSFileManager.defaultManager createDirectoryAtPath:DIDirectory() withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:dictionary format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    return data && [data writeToFile:DIFile(StateName) options:NSDataWritingAtomic error:nil];
}

// What is at `path`, without following a link. For a link, `target` gets where
// it points. Anything that cannot be examined counts as "other": never touched.
static IMPathKind KindOf(const char *path, NSString **target) {
    struct stat info;
    if (lstat(path, &info) != 0) return errno == ENOENT ? IMPathMissing : IMPathOther;
    if (S_ISLNK(info.st_mode)) {
        char buffer[PATH_MAX + 1];
        ssize_t length = readlink(path, buffer, PATH_MAX);
        if (length < 0) return IMPathOtherLink;
        buffer[length] = 0;
        if (target) *target = [NSString stringWithUTF8String:buffer];
        return strcmp(buffer, DI_CANVAS_FILE) == 0 || strcmp(buffer, DI_CANVAS_FILE_ALT) == 0 ? IMPathOurLink : IMPathOtherLink;
    }
    return S_ISREG(info.st_mode) ? IMPathFile : IMPathOther;
}

// Takes the canvas away: our link (only if the path still holds our link), the
// canvas file, then whatever the link replaced, into an empty slot only.
// Returns how many things it changed. File operations only.
static int Teardown(int foreignKind, NSString *foreignTarget) {
    NSFileManager *fm = NSFileManager.defaultManager;
    int changed = 0;
    if (IMUnlinkIsOurs(KindOf(DI_CANVAS_LINK, NULL)) && unlink(DI_CANVAS_LINK) == 0) changed++;
    if (unlink(DI_CANVAS_FILE) == 0) changed++;
    if (IMMayPutBack(KindOf(DI_CANVAS_LINK, NULL))) {
        if (foreignKind == 1 && [fm fileExistsAtPath:DIFile(ForeignName)]) {
            if ([fm copyItemAtPath:DIFile(ForeignName) toPath:CanvasLink error:nil]) {
                changed++;
                [fm removeItemAtPath:DIFile(ForeignName) error:nil];
            }
        } else if (foreignKind == 2 && foreignTarget.length) {
            if (symlink(foreignTarget.fileSystemRepresentation, DI_CANVAS_LINK) == 0) changed++;
        }
    }
    return changed;
}

// ---- The panel's own size ---------------------------------------------------------

static NSString *const PanelName = @"panel.plist";

static BOOL CanvasLinkActive(void) { return KindOf(DI_CANVAS_LINK, NULL) == IMPathOurLink; }

void DICanvasNotePanel(double width, double height) {
    double saved = [[NSDictionary dictionaryWithContentsOfFile:DIFile(PanelName)][@"Height"] doubleValue];
    if (!IMShouldNotePanel(CanvasLinkActive(), height, saved) || !(isfinite(width) && width > 0)) return;
    [NSFileManager.defaultManager createDirectoryAtPath:DIDirectory() withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:@{@"Width": @(width), @"Height": @(height), @"NotedAt": @(Now())}
                                                              format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    [data writeToFile:DIFile(PanelName) options:NSDataWritingAtomic error:nil];
}

double DICanvasPanelWidth(double live) {
    double saved = [[NSDictionary dictionaryWithContentsOfFile:DIFile(PanelName)][@"Width"] doubleValue];
    return IMPanelSize(CanvasLinkActive(), saved, live);
}

double DICanvasPanelHeight(double live) {
    double saved = [[NSDictionary dictionaryWithContentsOfFile:DIFile(PanelName)][@"Height"] doubleValue];
    return IMPanelSize(CanvasLinkActive(), saved, live);
}

NSDictionary *DICanvasStatus(double liveWidth, double liveHeight) {
    NSDictionary *state = ReadState();
    IMPathKind kind = KindOf(DI_CANVAS_LINK, NULL);
    BOOL ours = kind == IMPathOurLink;
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    out[@"canvasActive"] = @(ours);
    out[@"canvasByUs"] = @(ours && [state[@"Applied"] boolValue]);
    out[@"canvasForeign"] = @(kind == IMPathFile || kind == IMPathOtherLink);
    out[@"liveWidth"] = @(liveWidth);
    out[@"liveHeight"] = @(liveHeight);
    out[@"panelWidth"] = @(DICanvasPanelWidth(liveWidth));
    out[@"panelHeight"] = @(DICanvasPanelHeight(liveHeight));
    if (ours) {
        NSDictionary *live = [NSDictionary dictionaryWithContentsOfFile:CanvasLink];  // read through the link
        id width = live[@"canvas_width"], height = live[@"canvas_height"];
        if ([width isKindOfClass:NSNumber.class] && [height isKindOfClass:NSNumber.class]) {
            out[@"canvasWidth"] = width;
            out[@"canvasHeight"] = height;
            out[@"canvasPreset"] = @(IMPresetFind([width longValue], [height longValue]));
        }
    }
    return out;
}

NSDictionary *DICanvasApply(NSInteger preset, double liveWidth, double liveHeight) {
    // Mango's own gate, before anything is read or written.
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    if (!IMOSSupportsSimulation((long)os.majorVersion, (long)os.minorVersion))
        return Fail(@"修改分辨率需要 iOS 16.1 及以上系统，当前系统版本过低，什么都没改。");
    const IMPreset *p = IMPresetAt((int)preset);
    if (!p || !IMCanvasValid(p->width, p->height)) return Fail(@"没有这个分辨率预设，什么都没改。");
    DICanvasNotePanel(liveWidth, liveHeight);  // before the canvas exists, so it is still the panel

    NSFileManager *fm = NSFileManager.defaultManager;
    NSDictionary *old = ReadState();
    int foreignKind = [old[@"ForeignKind"] intValue];
    NSString *foreignTarget = [old[@"ForeignTarget"] isKindOfClass:NSString.class] ? old[@"ForeignTarget"] : nil;

    // What is at the Preferences path decides how the link gets there.
    NSString *target = nil;
    IMPathKind kind = KindOf(DI_CANVAS_LINK, &target);
    IMLinkAction action = IMLinkDecide(kind);
    if (action == IMLinkRefuse) return Fail(@"Preferences 里那个位置上不是文件也不是链接，什么都没改。");
    if (action == IMLinkKeepThenReplace) {
        // One kept copy at a time: never overwrite an earlier one.
        if (foreignKind != 0)
            return Fail(@"那个位置上有别的文件或链接，而且之前已经备份过一份。为了不覆盖备份，什么都没改；先点“恢复默认分辨率”。");
        if (kind == IMPathFile) {
            [fm createDirectoryAtPath:DIDirectory() withIntermediateDirectories:YES attributes:nil error:nil];
            [fm removeItemAtPath:DIFile(ForeignName) error:nil];
            NSError *copyError = nil;
            if (![fm copyItemAtPath:CanvasLink toPath:DIFile(ForeignName) error:&copyError])
                return Fail([NSString stringWithFormat:@"备份原来的文件失败，什么都没改（%@）", copyError.localizedDescription ?: @"未知原因"]);
            foreignKind = 1;
        } else {
            if (!target.length) return Fail(@"读不到原来那个链接指向哪里，什么都没改。");
            foreignKind = 2;
            foreignTarget = target;
        }
    }

    // The canvas file, as Mango writes it: {canvas_height, canvas_width}, XML,
    // atomic replace.
    NSError *error = nil;
    NSData *xml = [NSPropertyListSerialization dataWithPropertyList:@{@"canvas_height": @(p->height), @"canvas_width": @(p->width)}
                                                             format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    if (!xml || ![xml writeToFile:CanvasFile options:NSDataWritingAtomic error:&error])
        return Fail([NSString stringWithFormat:@"写不进 %@（%@），什么都没改。", CanvasFile, error.localizedDescription ?: @"未知原因"]);

    // The link in Preferences. An existing link of ours already points at the
    // file just rewritten and stays as it is.
    if (action != IMLinkReplace) {
        if (action == IMLinkKeepThenReplace && unlink(DI_CANVAS_LINK) != 0) {
            int code = errno;
            unlink(DI_CANVAS_FILE);
            return Fail([NSString stringWithFormat:@"移不开原来的文件或链接（错误 %d），什么都没改。", code]);
        }
        if (symlink(DI_CANVAS_FILE, DI_CANVAS_LINK) != 0) {
            int code = errno;
            Teardown(foreignKind, foreignTarget);
            return Fail([NSString stringWithFormat:@"建链接失败（错误 %d），已撤回。", code]);
        }
    }

    // Read it back the way the system will: through the link.
    NSDictionary *check = [NSDictionary dictionaryWithContentsOfFile:CanvasLink];
    id width = check[@"canvas_width"], height = check[@"canvas_height"];
    if (![width isKindOfClass:NSNumber.class] || ![height isKindOfClass:NSNumber.class] ||
        [width integerValue] != p->width || [height integerValue] != p->height) {
        Teardown(foreignKind, foreignTarget);
        return Fail(@"写完回读到的画布尺寸不对，已撤回。");
    }

    NSMutableDictionary *state = [@{@"Applied": @YES, @"Preset": @(preset), @"Width": @(p->width), @"Height": @(p->height),
                                    @"AppliedAt": @(Now()), @"ForeignKind": @(foreignKind)} mutableCopy];
    if (foreignTarget) state[@"ForeignTarget"] = foreignTarget;
    if (!WriteState(state)) {
        Teardown(foreignKind, foreignTarget);
        return Fail(@"保存还原记录失败，已撤回。");
    }
    DIGuardArmFor(IM_GUARD_CANVAS);

    NSString *name = [NSString stringWithUTF8String:p->name] ?: @"";
    return @{@"ok": @YES, @"respring": @YES, @"preset": @(preset), @"width": @(p->width), @"height": @(p->height),
             @"message": [NSString stringWithFormat:@"已把画布设成 %d×%d（%@）。", p->width, p->height, name]};
}

NSDictionary *DICanvasRestore(void) {
    NSDictionary *state = ReadState();
    int foreignKind = [state[@"ForeignKind"] intValue];
    NSString *foreignTarget = [state[@"ForeignTarget"] isKindOfClass:NSString.class] ? state[@"ForeignTarget"] : nil;
    IMPathKind kind = KindOf(DI_CANVAS_LINK, NULL);
    BOOL foreignThere = kind != IMPathMissing && !IMUnlinkIsOurs(kind);

    int changed = Teardown(foreignKind, foreignTarget);
    WriteState(@{@"Applied": @NO, @"RestoredAt": @(Now())});
    DIGuardDoneFor(IM_GUARD_CANVAS);

    NSString *note = foreignThere ? @"Preferences 里那个位置上现在是别的文件或链接，没有动它。" : @"";
    if (!changed)
        return @{@"ok": @YES, @"respring": @NO, @"message": [@"画布本来就是默认的，没有改动。" stringByAppendingString:note]};
    return @{@"ok": @YES, @"respring": @YES, @"message": [@"已恢复默认分辨率。" stringByAppendingString:note]};
}
