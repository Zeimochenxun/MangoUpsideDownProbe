#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "../src/SuitePreferences.h"
#import "../src/NativePreferences.h"
#import "Prefs.h"

static NSString * const NativeUpsideDownKey = @"LeXiang.UpsideDown.Enabled";

static BOOL SuiteFlag(NSString *key) {
    if (MSHasEmergencyMarker(key)) return NO;
    return MSPreferenceFlag(MSReadPreferences(NULL), key);
}

@implementation MangoSuitePrefsController

- (void)showMessage:(NSString *)message title:(NSString *)title {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)addSection:(NSString *)name {
    PSSpecifier *group = name.length ? [PSSpecifier groupSpecifierWithName:name] : [PSSpecifier emptyGroupSpecifier];
    [_specifiers addObject:group];
}

- (void)addSwitch:(NSString *)name key:(NSString *)key {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(writeValue:specifier:) get:@selector(readValue:) detail:nil cell:PSSwitchCell edit:nil];
    [item setProperty:key forKey:@"key"];
    [_specifiers addObject:item];
}

- (Class)adaptiveControllerClass {
    Class controller = NSClassFromString(@"MangoIslandAdaptiveColorPrefsController");
    if (!controller) {
        // Resolve from this installed bundle so RootHide's randomized root is
        // preserved; do not hard-code the rootful /Library location.
        NSString *parent = [[NSBundle bundleForClass:self.class].bundlePath stringByDeletingLastPathComponent];
        NSString *path = [parent stringByAppendingPathComponent:@"MangoIslandAdaptiveColorPrefs.bundle"];
        NSBundle *bundle = [NSBundle bundleWithPath:path];
        if (bundle) [bundle loadAndReturnError:NULL];
        controller = NSClassFromString(@"MangoIslandAdaptiveColorPrefsController");
    }
    return [controller isSubclassOfClass:PSListController.class] ? controller : Nil;
}

- (NSMutableArray *)specifiers {
    if (_specifiers) return _specifiers;
    self.title = @"Mango 整合设置";
    _specifiers = [NSMutableArray new];

    PSSpecifier *notice = [PSSpecifier emptyGroupSpecifier];
    [notice setProperty:@"本插件为mango插件的自改补丁，仅自用。Beta9.6 为崩溃隔离诊断版，默认停用整合补丁；此前问题和通知上滑崩溃尚未确认解决。" forKey:@"footerText"];
    [_specifiers addObject:notice];

    [self addSection:@"总开关"];
    [self addSwitch:@"启用整合修复" key:@"Enabled"];
    [self addSection:@"通知崩溃隔离"];
    PSSpecifier *isolationHelp=_specifiers.lastObject;
    [isolationHelp setProperty:@"默认开启。重新启动用户空间后，全部整合补丁停止加载，Mango 原版继续运行；各项原有选择保留。此模式用于定位，原有问题可能继续存在。关闭隔离后会恢复补丁，当前通知上滑崩溃仍未定位。更改后务必在多巴胺中重新启动用户空间。" forKey:@"footerText"];
    [self addSwitch:@"完全隔离整合补丁（需重启用户空间）" key:@"CrashIsolationEnabled"];

    [self addSection:@"灵动岛外观"];
    [self addSwitch:@"静止灵动岛与过渡修复" key:@"IdleEnabled"];
    PSSpecifier *glass = [PSSpecifier preferenceSpecifierNamed:@"玻璃与边缘光参数" target:self set:nil get:nil detail:NSClassFromString(@"MangoSuiteGlassController") cell:PSLinkCell edit:nil];
    [_specifiers addObject:glass];

    [self addSection:nil];
    [self addSwitch:@"背景颜色自适应" key:@"AdaptiveEnabled"];
    Class adaptiveClass = [self adaptiveControllerClass];
    PSSpecifier *adaptive = [PSSpecifier preferenceSpecifierNamed:@"自适应颜色参数" target:self set:nil get:nil detail:adaptiveClass cell:adaptiveClass ? PSLinkCell : PSButtonCell edit:nil];
    if (!adaptiveClass) [adaptive setButtonAction:@selector(showMissingAdaptive)];
    [_specifiers addObject:adaptive];

    [self addSection:@"旋转与布局"];
    NSError *nativeReadError = nil;
    (void)MSReadNativeUpsideDown(&nativeReadError);
    PSSpecifier *orientationGroup = _specifiers.lastObject;
    if (nativeReadError) [orientationGroup setProperty:nativeReadError.localizedDescription forKey:@"footerText"];
    [self addSwitch:@"Mango 原生屏幕倒置" key:NativeUpsideDownKey];
    PSSpecifier *nativeItem = _specifiers.lastObject;
    [nativeItem setProperty:@(!nativeReadError) forKey:@"enabled"];
    [self addSwitch:@"倒置方向与小芒修复" key:@"WorldEnabled"];
    [self addSection:nil];
    [self addSwitch:@"分屏倒置修复" key:@"SplitEnabled"];

    [self addSection:@"本版问题修复（可分别关闭）"];
    [self addSwitch:@"1 椭圆轮廓与四角修复" key:@"RimGeometryEnabled"];
    [self addSwitch:@"2 启动器重开倒置恢复" key:@"LauncherRecoveryEnabled"];
    [self addSwitch:@"3 液态玻璃过渡动画修复" key:@"GlassAnimationEnabled"];
    [self addSwitch:@"4 调整位置大小保持倒置" key:@"IslandLayoutEnabled"];
    [self addSwitch:@"5 短通知黑色光晕修复" key:@"ShortHaloEnabled"];
    [self addSwitch:@"6 灵动岛边缘实时采色" key:@"EdgeColorEnabled"];
    for (NSDictionary *row in @[@{@"name":@"灵动岛边缘粗细（点）", @"key":@"EdgeThickness", @"min":@.5, @"max":@4.0},
                                @{@"name":@"采色边缘动态程度", @"key":@"EdgeDynamics", @"min":@0.0, @"max":@1.0}]) {
        PSSpecifier *slider = [PSSpecifier preferenceSpecifierNamed:row[@"name"] target:self set:@selector(writeValue:specifier:) get:@selector(readValue:) detail:nil cell:PSSliderCell edit:nil];
        [slider setProperty:row[@"key"] forKey:@"key"];
        [slider setProperty:row[@"min"] forKey:@"min"];
        [slider setProperty:row[@"max"] forKey:@"max"];
        [slider setProperty:@YES forKey:@"showValue"];
        [_specifiers addObject:slider];
    }
    [self addSwitch:@"7 通知上下滑动方向修复（暂停）" key:@"SwipeDirectionEnabled"];
    PSSpecifier *pausedSwipe=_specifiers.lastObject;
    [pausedSwipe setProperty:@NO forKey:@"enabled"];
    [self addSection:nil];
    PSSpecifier *pauseHelp=_specifiers.lastObject;
    [pauseHelp setProperty:@"上一版通知上滑后进入安全模式，本版已停用方向改写并保留原有选择。通知动作暂由 Mango 原版处理；保留的开关值不会启用这项改写。" forKey:@"footerText"];
    [self addSection:@"调试"];
    PSSpecifier *diagnostics = [PSSpecifier preferenceSpecifierNamed:@"调试日志与一键提取" target:self set:nil get:nil detail:NSClassFromString(@"MangoSuiteDiagnosticsController") cell:PSLinkCell edit:nil];
    [_specifiers addObject:diagnostics];

    [self addSection:@"使用"];
    PSSpecifier *help = [PSSpecifier preferenceSpecifierNamed:@"如何应用开关更改" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [help setButtonAction:@selector(showRestartHelp)];
    [_specifiers addObject:help];
    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}

- (id)readValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if ([key isEqualToString:@"EdgeThickness"]) return MSReadPreferences(NULL)[key] ?: @1.2;
    if ([key isEqualToString:@"EdgeDynamics"]) return MSReadPreferences(NULL)[key] ?: @.5;
    if ([key isEqualToString:NativeUpsideDownKey]) return MSReadNativeUpsideDown(NULL) ?: @NO;
    return key.length ? @(SuiteFlag(key)) : nil;
}

- (void)writeValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if ([key isEqualToString:@"SwipeDirectionEnabled"]) return;
    if ([key isEqualToString:@"EdgeThickness"] || [key isEqualToString:@"EdgeDynamics"]) {
        NSError *error = nil;
        if (!MSWritePreferenceValue(key, value, &error)) [self showMessage:error.localizedDescription title:@"保存失败"];
        return;
    }
    if ([key isEqualToString:NativeUpsideDownKey]) {
        if (![value isKindOfClass:NSNumber.class]) return;
        NSError *error = nil;
        BOOL saved = MSWriteNativeUpsideDown([value boolValue], &error);
        [self reloadSpecifiers];
        if (!saved) [self showMessage:error.localizedDescription ?: @"请重新打开设置后检查当前倒置开关。" title:@"保存失败"];
        return;
    }
    NSArray *known = [@[@"Enabled", @"IdleEnabled", @"AdaptiveEnabled", @"WorldEnabled", @"SplitEnabled", @"DebugEnabled", @"CrashIsolationEnabled"] arrayByAddingObjectsFromArray:MSRepairKeys()];
    if (![known containsObject:key] || ![value isKindOfClass:NSNumber.class]) return;
    BOOL enabled = [value boolValue];
    NSError *saveError = nil;
    if ([key isEqualToString:@"DebugEnabled"] && enabled && !MSWritePreferenceValue(@"DebugSessionToken", @(NSDate.date.timeIntervalSince1970), &saveError)) {
        [self showMessage:saveError.localizedDescription title:@"记录未能开始"]; return;
    }
    if (!MSReadPreferences(&saveError)) {
        [self reloadSpecifiers];
        [self showMessage:[NSString stringWithFormat:@"%@\n%@", saveError.localizedDescription, saveError.userInfo[NSFilePathErrorKey]] title:@"保存失败"];
        return;
    }
    NSFileManager *files = NSFileManager.defaultManager;
    NSMutableDictionary<NSString *, NSData *> *removedMarkers = [NSMutableDictionary new];
    for (NSString *marker in (enabled ? MSMarkerPathsForKey(key) : @[])) {
        if (![files fileExistsAtPath:marker]) continue;
        NSError *error = nil;
        NSData *markerContents = [NSData dataWithContentsOfFile:marker options:0 error:&error];
        if (!markerContents || ![files removeItemAtPath:marker error:&error]) {
            BOOL restored = YES;
            for (NSString *path in removedMarkers) restored = [removedMarkers[path] writeToFile:path options:NSDataWritingAtomic error:NULL] && restored;
            [self reloadSpecifiers];
            [self showMessage:[NSString stringWithFormat:@"无法清除该模块的旧停用标记，开关未保存。\n%@\n%@%@", marker, error.localizedDescription ?: @"请检查文件权限。", restored ? @"" : @"\n先前移除的停用标记未能恢复，请在重启前检查模块状态。"] title:@"未能开启"];
            return;
        }
        removedMarkers[marker] = markerContents;
    }
    if (!MSWritePreferenceFlag(key, enabled, &saveError)) {
        BOOL markerRestored = YES;
        for (NSString *path in removedMarkers) markerRestored = [removedMarkers[path] writeToFile:path options:NSDataWritingAtomic error:NULL] && markerRestored;
        [self reloadSpecifiers];
        NSError *cause = saveError.userInfo[NSUnderlyingErrorKey];
        NSString *message = [NSString stringWithFormat:@"%@\n%@\n%@%@", saveError.localizedDescription, saveError.userInfo[NSFilePathErrorKey], cause.localizedDescription ?: @"", markerRestored ? @"" : @"\n旧停用标记未能恢复；重启前请确认模块状态。"];
        [self showMessage:message title:@"保存失败"];
        return;
    }
    [self reloadSpecifiers];
}

- (void)showRestartHelp {
    NSError *readError = nil;
    NSNumber *native = MSReadNativeUpsideDown(&readError);
    NSString *state = native ? ([native boolValue] ? @"已开启" : @"已关闭") : (readError.localizedDescription ?: @"无法读取");
    [self showMessage:[NSString stringWithFormat:@"Mango 原生倒置：%@\n\n原生倒置开关独立于“启用整合修复”。更改原生倒置后，完整关闭设置再打开本页检查保存，然后 Respring。测试期间不要进入 Mango 原版的倒置设置页，它会清回关闭。\n\n总开关和四个修复开关更改后，请在多巴胺中“重新启动用户空间”；Respring 不能重载颜色自适应模块。\n\n玻璃与自适应参数按原有方式即时刷新。关闭总开关会保留你的各项选择及原生倒置偏好。", state] title:@"应用开关更改"];
}

- (void)showMissingAdaptive {
    [self showMessage:@"无法加载 AdaptiveColor 参数页面。请重新安装完整的 Mango 整合包。" title:@"参数页不可用"];
}

@end
