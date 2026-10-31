// Settings → 灵动岛. The same four things as Mango's menu section, in the same
// order and with Mango's wording where it has any (read from its Beta9 and Beta12
// binaries): 模拟灵动岛模式 + 应用模拟灵动岛 / 取消模拟, 预设 + 应用分辨率 /
// 恢复默认分辨率, then size and position. Sliders and the switch write
// settings.plist (Settings.h) and SpringBoard picks them up within a fraction of
// a second. The model and canvas buttons do not touch the system themselves: they
// ask SpringBoard, where Mango does the same, through request.plist, and show what
// it answered.
#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <objc/message.h>
#import "../Settings.h"
#import "../IslandPolicy.h"

@interface DynamicIslandRootController : PSListController {
    NSDictionary *_status;  // SpringBoard's answer to "status": model value and canvas
}
@end

static void Alert(UIViewController *controller, NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

static PSSpecifier *Group(NSString *name, NSString *footer) {
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:name ?: @""];
    if (footer) [group setProperty:footer forKey:@"footerText"];
    return group;
}

// Writes land at once; the Darwin notification is coalesced so a slider drag
// does not post once per touch.
static void NotifyLater(void) {
    static BOOL pending;
    if (pending) return;
    pending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        pending = NO;
        DIPost(DINotifySettings);
    });
}

static NSString *ShowInt(id value) {
    return [value isKindOfClass:NSNumber.class] ? [NSString stringWithFormat:@"%lld", [value longLongValue]] : @"未知";
}

// Mango's two mode button titles. [read]
static NSString *ModeName(NSInteger mode) {
    return mode == 1 ? @"Pro Max (1290×2796)" : @"Pro (1179×2556)";
}

static NSString *PresetName(const IMPreset *preset) {
    return preset ? ([NSString stringWithUTF8String:preset->name] ?: @"") : @"";
}

// The picker line of Mango's preset menu: "%@ — %ld×%ld". [read]
static NSString *PresetLine(NSInteger index) {
    const IMPreset *preset = IMPresetAt((int)index);
    return preset ? [NSString stringWithFormat:@"%@ — %d×%d", PresetName(preset), preset->width, preset->height] : @"";
}

// Mango's gate: both changes need iOS 16.1 or later. [read]
static BOOL OSSupported(void) {
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    return IMOSSupportsSimulation((long)os.majorVersion, (long)os.minorVersion);
}

static NSString *AdjustText(NSString *state) {
    if (!state) return @"未知";
    NSDictionary *names = @{
        @"applied": @"已生效",
        @"default": @"在默认值，没有改动系统",
        @"off": @"已关闭",
        @"kill-switch": @"应急开关文件存在，已停用（DynamicIsland.disabled）",
        @"no-window": @"还没有找到灵动岛窗口：先让灵动岛出现一次（放首歌或开个计时器）",
        @"verify-failed": @"校验没通过，已撤回改动（日志里有详情）",
        @"conflict": @"别的插件在用那一层，已避让",
        @"waiting": @"等待中",
    };
    if (names[state]) return names[state];
    if ([state hasPrefix:@"ineligible:"]) return [NSString stringWithFormat:@"层级结构和预期不符（%@），没有改动", [state substringFromIndex:11]];
    return state;
}

static NSString *TurnText(NSString *name) {
    if ([name isEqualToString:@"upright"]) return @"正向";
    if ([name isEqualToString:@"turned"]) return @"已转 180°（倒置）";
    if ([name isEqualToString:@"other"]) return @"其它角度";
    return @"没有窗口";
}

@implementation DynamicIslandRootController

- (PSSpecifier *)toggle:(NSString *)name key:(NSString *)key {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(setFlag:specifier:) get:@selector(flag:) detail:nil cell:PSSwitchCell edit:nil];
    [item setProperty:key forKey:@"key"];
    return item;
}

- (PSSpecifier *)button:(NSString *)name action:(SEL)action {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:name target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [item setButtonAction:action];
    return item;
}

- (PSSpecifier *)slider:(NSString *)key min:(double)min max:(double)max {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:key target:self set:@selector(setNumber:specifier:) get:@selector(number:) detail:nil cell:PSSliderCell edit:nil];
    [item setProperty:key forKey:@"key"];
    [item setProperty:@(min) forKey:@"min"];
    [item setProperty:@(max) forKey:@"max"];
    [item setProperty:@YES forKey:@"showValue"];
    return item;
}

// ---- Footers ----------------------------------------------------------------

- (NSString *)modelFooter {
    NSDictionary *d = _status;
    if (!d) return @"正在向 SpringBoard 询问当前的机型值……（需要灵动岛插件已启用）";
    if (![d[@"ok"] boolValue]) return [NSString stringWithFormat:@"读不到机型值：%@", d[@"message"] ?: @"没有回应"];
    NSMutableString *text = [NSMutableString stringWithFormat:@"当前机型值 %@，原值 %@（%@），取消模拟时写回 %@。",
                             ShowInt(d[@"subtype"]), d[@"original"] ? ShowInt(d[@"original"]) : @"未备份", d[@"original"] ? @"已备份" : @"应用时会先备份", ShowInt(d[@"restore"])];
    if ([d[@"hardwareIsland"] boolValue]) {
        [text appendString:@"\n这台手机自带灵动岛，不需要模拟。"];
    } else if ([d[@"simulated"] boolValue]) {
        [text appendFormat:@"\n已模拟：机型值是灵动岛的 %@。", ShowInt(d[@"subtype"])];
        if (![d[@"applied"] boolValue])
            [text appendFormat:@"这个值不是本插件改的（可能来自 Mango 的灵动岛模拟）；点“取消模拟”会按屏幕写回 %@。", ShowInt(d[@"restore"])];
    } else {
        [text appendString:@"\n未模拟。"];
    }
    if ([d[@"guardArmed"] boolValue]) [text appendString:@"\n崩溃保护已启用：新的 SpringBoard 一启动就崩，会自动还原。"];
    [text appendString:@"\n\n模拟灵动岛只适用于 iOS 16.1 及以上、没有实体灵动岛的设备，不满足就别强行使用。开启或关闭都要重启用户空间才生效，点按钮并确认后会立刻注销。\n做法和 Mango 的灵动岛模拟是同一个：改系统缓存里的机型值（2556 是 14 Pro，2796 是 14 Pro Max），再注销。两者只开一个。\n万一桌面异常：在 Filza 或 ssh 里到 /var/mobile/Library/Preferences/ 新建一个空文件 DynamicIsland.restore，插件下次启动（或 5 秒内）会自动还原。"];
    return text;
}

// The panel's own size as SpringBoard reports it: under a canvas the live
// nativeBounds may be the canvas [missing], so SpringBoard keeps the size it saw
// before. The live size when SpringBoard has not answered.
- (CGSize)panelSize {
    id width = _status[@"panelWidth"], height = _status[@"panelHeight"];
    if ([width isKindOfClass:NSNumber.class] && [height isKindOfClass:NSNumber.class])
        return CGSizeMake([width doubleValue], [height doubleValue]);
    return UIScreen.mainScreen.nativeBounds.size;
}

- (NSString *)canvasFooter {
    CGSize native = [self panelSize];
    NSMutableString *text = [NSMutableString stringWithFormat:@"当前原生分辨率 %.0f×%.0f。", native.width, native.height];
    NSDictionary *d = _status;
    id liveWidth = d[@"liveWidth"], liveHeight = d[@"liveHeight"];
    if ([liveWidth isKindOfClass:NSNumber.class] && [liveHeight isKindOfClass:NSNumber.class] &&
        (fabs([liveWidth doubleValue] - native.width) > 0.5 || fabs([liveHeight doubleValue] - native.height) > 0.5))
        [text appendFormat:@"系统现在报告的屏幕是 %.0f×%.0f（画布的尺寸）。", [liveWidth doubleValue], [liveHeight doubleValue]];
    if (!d) {
        [text appendString:@"\n正在向 SpringBoard 询问当前的画布……"];
    } else if ([d[@"canvasActive"] boolValue]) {
        if ([d[@"canvasWidth"] isKindOfClass:NSNumber.class] && [d[@"canvasHeight"] isKindOfClass:NSNumber.class]) {
            const IMPreset *preset = IMPresetAt([d[@"canvasPreset"] intValue]);
            [text appendFormat:@"\n画布已设为 %@×%@%@。", ShowInt(d[@"canvasWidth"]), ShowInt(d[@"canvasHeight"]),
                               preset ? [NSString stringWithFormat:@"（%@）", PresetName(preset)] : @""];
        } else {
            [text appendString:@"\n画布的链接在，但读不到里面的尺寸。"];
        }
        if (![d[@"canvasByUs"] boolValue])
            [text appendString:@"这个设置不是本插件做的（可能来自 Mango 的“应用分辨率”）；点“恢复默认分辨率”会一并清除。"];
    } else {
        [text appendString:@"\n画布：默认。"];
    }
    if ([d[@"canvasForeign"] boolValue])
        [text appendString:@"\nPreferences 里 com.apple.iokit.IOMobileGraphicsFamily.plist 的位置上有别的文件或链接：应用时会先留一份备份，恢复时放回去。"];
    [text appendString:@"\n\n做法和 Mango 一样：把 canvas_width 和 canvas_height 写进 /var/tmp/com.apple.iokit.IOMobileGraphicsFamily.plist，再在 Preferences 里放一个指向它的链接，然后注销。如果出现黑屏/花屏等异常，请重新注销恢复；还不行就新建 DynamicIsland.restore（同上）。系统在 iOS 16.5 上认不认这两个键，上机才知道。"];
    return text;
}

- (NSString *)statusFooter {
    NSDictionary *s = [NSDictionary dictionaryWithContentsOfFile:DIFile(@"status.plist")];
    if (!s) return @"SpringBoard 里还没有状态记录：确认插件已启用，并注销一次。";
    return [NSString stringWithFormat:@"调节：%@\n灵动岛窗口方向：%@\n插件 %@，iOS %@，%@，原生像素高 %@。", AdjustText(s[@"adjust"]), TurnText(s[@"turnFixed"]),
            s[@"version"] ?: @"?", s[@"ios"] ?: @"?", s[@"machine"] ?: @"?", ShowInt(s[@"nativeHeight"])];
}

// ---- The list -----------------------------------------------------------------

- (NSMutableArray *)specifiers {
    if (_specifiers) return _specifiers;
    self.title = @"灵动岛";
    NSDictionary *settings = DIReadSettings();
    NSMutableArray *list = [NSMutableArray array];

    [list addObject:Group(@"灵动岛模拟", [self modelFooter])];
    [list addObject:[self button:[NSString stringWithFormat:@"模式：%@", ModeName(DIMode(settings))] action:@selector(chooseMode)]];
    [list addObject:[self button:@"应用模拟灵动岛" action:@selector(applyTapped)]];
    [list addObject:[self button:@"取消模拟" action:@selector(cancelTapped)]];

    [list addObject:Group(@"分辨率", [self canvasFooter])];
    [list addObject:[self button:[NSString stringWithFormat:@"预设：%@", PresetLine(DIPreset(settings))] action:@selector(choosePreset)]];
    [list addObject:[self button:@"应用分辨率" action:@selector(resolutionApplyTapped)]];
    [list addObject:[self button:@"恢复默认分辨率" action:@selector(resolutionRestoreTapped)]];

    [list addObject:Group(@"大小与位置", @"按你看到的方向算：向右、向下为正，正着拿和倒置时都一样，倒置时不需要另外设置。缩放绕 Mango 同款的点：灵动岛所在那一层顶端往下 42 点、水平居中。调节只改灵动岛中间一层透传视图，不碰倒置用到的窗口、根视图和内容层，所以调节不会让倒置失效，倒置也不会让调节错位。\n用了本页的调节，请把 Mango 自己的灵动岛位置、大小调节关掉（归零），不然会叠加或互相避让。")];
    [list addObject:[self toggle:@"启用大小与位置调节" key:@"AdjustEnabled"]];
    [list addObject:Group(@"大小（默认 1.00）", nil)];
    [list addObject:[self slider:@"Scale" min:IM_SCALE_MIN max:IM_SCALE_MAX]];
    [list addObject:Group(@"左右（点，向右为正，默认 0）", nil)];
    [list addObject:[self slider:@"OffsetX" min:-IM_OFFSET_MAX max:IM_OFFSET_MAX]];
    [list addObject:Group(@"上下（点，向下为正，默认 0）", nil)];
    [list addObject:[self slider:@"OffsetY" min:-IM_OFFSET_MAX max:IM_OFFSET_MAX]];
    [list addObject:Group(nil, nil)];
    [list addObject:[self button:@"恢复默认大小和位置" action:@selector(resetAdjust)]];

    [list addObject:Group(@"状态", [self statusFooter])];
    [list addObject:Group(@"诊断", [NSString stringWithFormat:@"灵动岛 %@。遇到问题时导出日志发给开发者。", @DI_VERSION])];
    [list addObject:[self button:@"导出诊断日志" action:@selector(shareLog)]];
    _specifiers = list;
    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshStatus];
}

// Ask SpringBoard for the current model value and canvas and rebuild the list.
- (void)refreshStatus {
    __weak DynamicIslandRootController *weakSelf = self;
    [self request:@"status" mode:0 preset:0 completion:^(NSDictionary *result, NSString *error) {
        DynamicIslandRootController *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_status = result ?: @{@"ok": @NO, @"message": error ?: @""};
        strongSelf->_specifiers = nil;
        [strongSelf reloadSpecifiers];
    }];
}

- (void)request:(NSString *)action mode:(NSInteger)mode preset:(NSInteger)preset completion:(void (^)(NSDictionary *result, NSString *error))completion {
    NSError *error = nil;
    NSString *identifier = DISubmitRequest(action, mode, preset, &error);
    if (!identifier) {
        completion(nil, error.localizedDescription ?: @"无法发出请求");
        return;
    }
    __block int tries = 0;
    [NSTimer scheduledTimerWithTimeInterval:.15 repeats:YES block:^(NSTimer *timer) {
        NSDictionary *result = DIResultFor(identifier);
        if (result) {
            [timer invalidate];
            completion(result, nil);
        } else if (++tries > 60) {
            [timer invalidate];
            completion(nil, @"SpringBoard 没有回应。确认灵动岛插件已启用，并注销一次。");
        }
    }];
}

// Sends the request and shows SpringBoard's answer. A change that has to respring
// does so about a second after the answer is written; the alert may not be seen.
- (void)run:(NSString *)action mode:(NSInteger)mode preset:(NSInteger)preset doneTitle:(NSString *)doneTitle {
    [self request:action mode:mode preset:preset completion:^(NSDictionary *result, NSString *error) {
        if (!result) { Alert(self, @"没有完成", error); return; }
        Alert(self, [result[@"ok"] boolValue] ? doneTitle : @"没有完成", result[@"message"] ?: @"");
        [self refreshStatus];
    }];
}

- (void)confirm:(NSString *)title message:(NSString *)message button:(NSString *)button action:(NSString *)action mode:(NSInteger)mode preset:(NSInteger)preset doneTitle:(NSString *)doneTitle {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:button style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
        [self run:action mode:mode preset:preset doneTitle:doneTitle];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentSheet:(UIAlertController *)sheet {
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)saveSetting:(NSString *)key value:(id)value {
    NSError *error = nil;
    if (!DIWriteSettings(@{key: value}, &error)) {
        Alert(self, @"保存失败", error.localizedDescription ?: @"无效的值。");
        return;
    }
    _specifiers = nil;
    [self reloadSpecifiers];
}

// ---- 灵动岛模拟 ---------------------------------------------------------------

- (void)chooseMode {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"模拟灵动岛模式" message:@"只是选好样式，点“应用模拟灵动岛”才会改。" preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSInteger mode = 0; mode < 2; mode++)
        [sheet addAction:[UIAlertAction actionWithTitle:ModeName(mode) style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            [self saveSetting:@"Mode" value:@(mode)];
        }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentSheet:sheet];
}

- (void)applyTapped {
    if (!OSSupported()) {
        Alert(self, @"系统版本不支持", @"灵动岛模拟需要 iOS 16.1 及以上系统。当前系统版本过低，强行使用可能导致设备异常。");
        return;
    }
    NSInteger mode = DIMode(DIReadSettings());
    NSString *message = [NSString stringWithFormat:@"即将切换至 %@ 模式\n\n会先把原来的机型值备份，再写入 %lld。修改后设备将自动注销重启，请耐心等待。\n\n此操作会修改系统配置文件，请在充分了解风险后使用。\n如果注销后桌面不正常：新建 /var/mobile/Library/Preferences/DynamicIsland.restore（空文件）即可还原。",
                         ModeName(mode), (long long)IMSubtypeForMode((int)mode)];
    [self confirm:@"⚠️ 模拟灵动岛" message:message button:@"确定应用" action:@"apply" mode:mode preset:0 doneTitle:@"已写入"];
}

- (void)cancelTapped {
    NSString *restore = _status[@"restore"] ? ShowInt(_status[@"restore"]) : @"原值";
    NSString *message = [NSString stringWithFormat:@"即将恢复为原始设备子类型 (%@)\n\n修改后设备将自动注销重启，请耐心等待。", restore];
    [self confirm:@"⚠️ 取消模拟灵动岛" message:message button:@"确定恢复" action:@"restore" mode:0 preset:0 doneTitle:@"已还原"];
}

// ---- 分辨率 ---------------------------------------------------------------------

- (void)choosePreset {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"预设" message:@"只是选好尺寸，点“应用分辨率”才会改。" preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSInteger index = 0; index < IM_PRESET_COUNT; index++)
        [sheet addAction:[UIAlertAction actionWithTitle:PresetLine(index) style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            [self saveSetting:@"ResolutionPreset" value:@(index)];
        }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentSheet:sheet];
}

- (void)resolutionApplyTapped {
    if (!OSSupported()) {
        Alert(self, @"系统版本不支持", @"修改分辨率需要 iOS 16.1 及以上系统。当前系统版本过低，强行使用可能导致设备异常。");
        return;
    }
    NSInteger index = DIPreset(DIReadSettings());
    const IMPreset *preset = IMPresetAt((int)index);
    if (!preset) return;
    CGSize native = [self panelSize];
    NSString *message = [NSString stringWithFormat:@"预设：%@ (%d×%d)\n当前原生：%.0f×%.0f\n\n修改后设备将自动注销重启，请耐心等待。\n\n如果出现黑屏/花屏等异常，请重新注销恢复；还不行就新建 /var/mobile/Library/Preferences/DynamicIsland.restore（空文件）。",
                         PresetName(preset), preset->width, preset->height, native.width, native.height];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"⚠️ 应用分辨率" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复默认分辨率" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        [self run:@"canvas-restore" mode:0 preset:0 doneTitle:@"已恢复"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定应用" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
        [self run:@"canvas-apply" mode:0 preset:index doneTitle:@"已写入"];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resolutionRestoreTapped {
    [self confirm:@"恢复默认分辨率？" message:@"删除画布设置，把被它顶替的文件放回原处，然后立刻注销。" button:@"恢复并注销" action:@"canvas-restore" mode:0 preset:0 doneTitle:@"已恢复"];
}

// ---- 大小与位置 -----------------------------------------------------------------

- (id)flag:(PSSpecifier *)specifier {
    return @(DIFlag(DIReadSettings(), [specifier propertyForKey:@"key"], YES));
}

- (void)setFlag:(id)value specifier:(PSSpecifier *)specifier {
    NSError *error = nil;
    if (![value isKindOfClass:NSNumber.class] || !DIWriteSettings(@{[specifier propertyForKey:@"key"]: @([value boolValue])}, &error))
        Alert(self, @"保存失败", error.localizedDescription ?: @"无效的值。");
    else
        NotifyLater();
}

- (id)number:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    IMAdjust adjust = DIAdjust(DIReadSettings());
    if ([key isEqualToString:@"Scale"]) return @(adjust.scale);
    if ([key isEqualToString:@"OffsetX"]) return @(adjust.offsetX);
    return @(adjust.offsetY);
}

- (void)setNumber:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (![value isKindOfClass:NSNumber.class]) return;
    double raw = [value doubleValue];
    double rounded = [key isEqualToString:@"Scale"] ? round(raw * 100) / 100 : round(raw * 2) / 2;
    NSError *error = nil;
    if (!DIWriteSettings(@{key: @(rounded)}, &error)) Alert(self, @"保存失败", error.localizedDescription ?: @"无效的值。");
    else NotifyLater();
}

- (void)resetAdjust {
    NSError *error = nil;
    if (!DIWriteSettings(@{@"Scale": @1, @"OffsetX": @0, @"OffsetY": @0}, &error)) {
        Alert(self, @"保存失败", error.localizedDescription);
        return;
    }
    NotifyLater();
    _specifiers = nil;
    [self reloadSpecifiers];
}

// ---- 诊断 -----------------------------------------------------------------------

- (void)shareLog {
    NSMutableString *report = [NSMutableString stringWithFormat:@"灵动岛 %@ / iOS %@\n导出时间：%@\n", @DI_VERSION, UIDevice.currentDevice.systemVersion, NSDate.date];
    for (NSString *name in @[@"settings.plist", @"status.plist", @"state.plist", @"original.plist", @"canvas.plist", @"panel.plist", @"guard.plist", @"result.plist"]) {
        NSDictionary *dictionary = [NSDictionary dictionaryWithContentsOfFile:DIFile(name)];
        [report appendFormat:@"\n[%@]\n%@\n", name, dictionary ?: @"(没有)"];
    }
    [report appendString:@"\n[日志]\n"];
    for (NSString *name in @[@"DynamicIsland.log.old", @"DynamicIsland.log"]) {
        NSString *text = [NSString stringWithContentsOfFile:DIFile(name) encoding:NSUTF8StringEncoding error:nil];
        if (text) [report appendString:text];
    }
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"DynamicIslandExports"];
    NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"DynamicIsland-%@.txt", [NSUUID.UUID.UUIDString substringToIndex:8]]];
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error] ||
        ![report writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        Alert(self, @"导出失败", error.localizedDescription);
        return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
    share.popoverPresentationController.sourceView = self.view;
    share.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:share animated:YES completion:nil];
}

@end
