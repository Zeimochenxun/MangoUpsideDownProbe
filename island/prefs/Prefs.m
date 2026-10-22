// Settings → 灵动岛. Sliders and the switch write settings.plist (Settings.h) and
// SpringBoard picks them up within a fraction of a second. The three model
// buttons do not touch the device model themselves: they ask SpringBoard, where
// Mango does the same, through request.plist, and show what it answered.
#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <objc/message.h>
#import "../Settings.h"
#import "../IslandPolicy.h"

@interface DynamicIslandRootController : PSListController {
    NSDictionary *_disguise;
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

- (NSString *)disguiseFooter {
    NSDictionary *d = _disguise;
    if (!d) return @"正在向 SpringBoard 询问当前的机型值……（需要灵动岛插件已启用）";
    if (![d[@"ok"] boolValue]) return [NSString stringWithFormat:@"读不到机型值：%@", d[@"message"] ?: @"没有回应"];
    NSMutableString *text = [NSMutableString stringWithFormat:@"当前机型值 %@，原值 %@（%@），还原时写回 %@。",
                             ShowInt(d[@"subtype"]), d[@"original"] ? ShowInt(d[@"original"]) : @"未备份", d[@"original"] ? @"已备份" : @"点伪装时会先备份", ShowInt(d[@"restore"])];
    BOOL islandValue = IMIsIslandSubtype([d[@"subtype"] longLongValue]);
    if ([d[@"hardwareIsland"] boolValue]) [text appendString:@"\n这台手机自带灵动岛，不需要伪装。"];
    else if ([d[@"applied"] boolValue]) [text appendString:@"\n已伪装。"];
    else if (islandValue) [text appendFormat:@"\n机型值已经是灵动岛的值，但不是本插件改的（可能是 Mango 的灵动岛模拟）。点“还原机型”会按屏幕推算写回 %@。", ShowInt(d[@"restore"])];
    else [text appendString:@"\n未伪装。"];
    if ([d[@"guardArmed"] boolValue]) [text appendString:@"\n崩溃保护已启用：新的 SpringBoard 一启动就崩，会自动还原。"];
    [text appendString:@"\n\n伪装和 Mango 的灵动岛模拟是同一个办法：改系统缓存里的机型值（2556 是 14 Pro，2796 是 14 Pro Max），再注销。两者只开一个。点按钮后会立刻注销。\n万一桌面异常：在 Filza 或 ssh 里到 /var/mobile/Library/Preferences/ 新建一个空文件 DynamicIsland.restore，插件下次启动（或 5 秒内）会自动还原。"];
    return text;
}

- (NSString *)statusFooter {
    NSDictionary *s = [NSDictionary dictionaryWithContentsOfFile:DIFile(@"status.plist")];
    if (!s) return @"SpringBoard 里还没有状态记录：确认插件已启用，并注销一次。";
    return [NSString stringWithFormat:@"调节：%@\n灵动岛窗口方向：%@\n插件 %@，iOS %@，%@。", AdjustText(s[@"adjust"]), TurnText(s[@"turnFixed"]),
            s[@"version"] ?: @"?", s[@"ios"] ?: @"?", s[@"machine"] ?: @"?"];
}

- (NSMutableArray *)specifiers {
    if (_specifiers) return _specifiers;
    self.title = @"灵动岛";
    NSMutableArray *list = [NSMutableArray array];
    [list addObject:Group(@"机型伪装", [self disguiseFooter])];
    [list addObject:[self button:@"伪装为 iPhone 14 Pro 的灵动岛" action:@selector(applyPro)]];
    [list addObject:[self button:@"伪装为 iPhone 14 Pro Max 的灵动岛" action:@selector(applyProMax)]];
    [list addObject:[self button:@"还原机型" action:@selector(restoreModel)]];

    [list addObject:Group(@"大小与位置", @"按你看到的方向算：向右、向下为正，正着拿和倒置时都一样，倒置时不需要另外设置。大小以灵动岛静止时的中心为准。调节只改灵动岛中间一层透传视图，不碰倒置用到的窗口、根视图和内容层，所以调节不会让倒置失效，倒置也不会让调节错位。\n用了本页的调节，请把 Mango 自己的灵动岛位置、大小调节关掉（归零），不然会叠加或互相避让。")];
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
    [self refreshDisguise];
}

// Ask SpringBoard for the current model value and rebuild the footers.
- (void)refreshDisguise {
    __weak DynamicIslandRootController *weakSelf = self;
    [self request:@"status" mode:0 completion:^(NSDictionary *result, NSString *error) {
        DynamicIslandRootController *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_disguise = result ?: @{@"ok": @NO, @"message": error ?: @""};
        strongSelf->_specifiers = nil;
        [strongSelf reloadSpecifiers];
    }];
}

- (void)request:(NSString *)action mode:(NSInteger)mode completion:(void (^)(NSDictionary *result, NSString *error))completion {
    NSError *error = nil;
    NSString *identifier = DISubmitRequest(action, mode, &error);
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

- (void)confirmApply:(NSInteger)mode name:(NSString *)name value:(int)value {
    NSString *message = [NSString stringWithFormat:@"会先把原来的机型值备份，然后写入 %d，并立刻注销。\n如果注销后桌面不正常：新建 /var/mobile/Library/Preferences/DynamicIsland.restore（空文件）即可还原。", value];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"伪装为 %@？", name] message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"伪装并注销" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [self request:@"apply" mode:mode completion:^(NSDictionary *result, NSString *error) {
            if (!result) { Alert(self, @"没有完成", error); return; }
            Alert(self, [result[@"ok"] boolValue] ? @"已写入" : @"没有完成", result[@"message"] ?: @"");
            [self refreshDisguise];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)applyPro { [self confirmApply:0 name:@"iPhone 14 Pro" value:IM_SUBTYPE_14PRO]; }
- (void)applyProMax { [self confirmApply:1 name:@"iPhone 14 Pro Max" value:IM_SUBTYPE_14PROMAX]; }

- (void)restoreModel {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"还原机型？" message:@"把机型值写回备份的原值，并立刻注销。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"还原并注销" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [self request:@"restore" mode:0 completion:^(NSDictionary *result, NSString *error) {
            if (!result) { Alert(self, @"没有完成", error); return; }
            Alert(self, [result[@"ok"] boolValue] ? @"已还原" : @"没有完成", result[@"message"] ?: @"");
            [self refreshDisguise];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

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

- (void)shareLog {
    NSMutableString *report = [NSMutableString stringWithFormat:@"灵动岛 %@ / iOS %@\n导出时间：%@\n", @DI_VERSION, UIDevice.currentDevice.systemVersion, NSDate.date];
    for (NSString *name in @[@"settings.plist", @"status.plist", @"state.plist", @"original.plist", @"guard.plist", @"result.plist"]) {
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
