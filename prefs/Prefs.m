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

- (void)addSection:(NSString *)name footer:(NSString *)footer {
    PSSpecifier *group = name.length ? [PSSpecifier groupSpecifierWithName:name] : [PSSpecifier emptyGroupSpecifier];
    if (footer.length) [group setProperty:footer forKey:@"footerText"];
    [_specifiers addObject:group];
}

- (void)addSlider:(NSString *)name key:(NSString *)key min:(double)min max:(double)max {
    PSSpecifier *slider = [PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(writeValue:specifier:) get:@selector(readValue:) detail:nil cell:PSSliderCell edit:nil];
    [slider setProperty:key forKey:@"key"];
    [slider setProperty:@(min) forKey:@"min"];
    [slider setProperty:@(max) forKey:@"max"];
    [slider setProperty:@YES forKey:@"showValue"];
    [_specifiers addObject:slider];
}

- (void)addLink:(NSString *)name detail:(Class)detail {
    [_specifiers addObject:[PSSpecifier preferenceSpecifierNamed:name target:self set:nil get:nil detail:detail cell:PSLinkCell edit:nil]];
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

    [self addSection:nil footer:@"本插件为mango插件的自改补丁，仅自用"];

    [self addSection:@"总开关" footer:@"总开关，以及“静止灵动岛”“背景颜色自适应”“倒置方向与小芒”“分屏倒置”四个模块开关，更改后需在多巴胺中“重新启动用户空间”。其余开关和滑杆约 1 秒内生效。详见页尾“如何应用开关更改”。"];
    [self addSwitch:@"启用整合修复" key:@"Enabled"];

    [self addSection:@"灵动岛 · 静止态" footer:@"黑色光晕：顶部纯黑向下渐隐，同时把玻璃底渐隐成透明。浓度是黑色的深浅，渐隐位置是黑色在胶囊高度的多少处消失（越小越靠上）。下沿提亮是下边缘的柔光和一圈下沿更亮的细玻璃边。随背景明暗自动切换：背景偏亮（如白色页面）时，改用下半淡灰磨砂 + 全周细轮廓线，避免灰糊和下沿消失；约每秒取样一次岛周围的亮度。若自动切换没有生效（取样拿不到前台 App 画面），打开“始终使用磨砂样式”即可固定为磨砂。"];
    [self addSwitch:@"静止灵动岛与过渡修复" key:@"IdleEnabled"];
    [self addSwitch:@"黑色光晕（上黑下透）" key:@"IdleGlowEnabled"];
    [self addSlider:@"黑色浓度" key:@"IdleGlowDensity" min:0 max:1];
    [self addSlider:@"渐隐位置（越小黑色越靠上）" key:@"IdleGlowFade" min:.3 max:1];
    [self addSwitch:@"下沿提亮" key:@"IdleGlowShineEnabled"];
    [self addSwitch:@"随背景明暗自动切换" key:@"IdleGlowAdaptiveEnabled"];
    [self addSwitch:@"始终使用磨砂样式（不随背景变化）" key:@"IdleGlowFrostedEnabled"];

    [self addSection:@"灵动岛 · 玻璃与边缘" footer:@"边缘实时采色默认关闭；采色粗细与动态程度只在采色开启时起作用。"];
    [self addLink:@"玻璃与边缘光参数" detail:NSClassFromString(@"MangoSuiteGlassController")];
    [self addSwitch:@"椭圆轮廓与四角修复" key:@"RimGeometryEnabled"];
    [self addSwitch:@"液态玻璃过渡动画修复" key:@"GlassAnimationEnabled"];
    [self addSwitch:@"短通知黑色光晕修复" key:@"ShortHaloEnabled"];
    [self addSwitch:@"灵动岛边缘实时采色" key:@"EdgeColorEnabled"];
    [self addSlider:@"采色边缘粗细（点）" key:@"EdgeThickness" min:.5 max:4];
    [self addSlider:@"采色边缘动态程度" key:@"EdgeDynamics" min:0 max:1];

    [self addSection:@"背景颜色自适应" footer:@"模块开关，更改后需重新启动用户空间。"];
    [self addSwitch:@"背景颜色自适应" key:@"AdaptiveEnabled"];
    Class adaptiveClass = [self adaptiveControllerClass];
    PSSpecifier *adaptive = [PSSpecifier preferenceSpecifierNamed:@"自适应颜色参数" target:self set:nil get:nil detail:adaptiveClass cell:adaptiveClass ? PSLinkCell : PSButtonCell edit:nil];
    if (!adaptiveClass) [adaptive setButtonAction:@selector(showMissingAdaptive)];
    [_specifiers addObject:adaptive];

    NSError *nativeReadError = nil;
    (void)MSReadNativeUpsideDown(&nativeReadError);
    [self addSection:@"屏幕倒置" footer:nativeReadError ? nativeReadError.localizedDescription : @"“Mango 原生屏幕倒置”独立于总开关，保存后按页尾说明 Respring。“倒置方向与小芒”“分屏倒置”是模块开关（需重启用户空间）；启动器重开倒置恢复依赖分屏倒置，调整位置大小保持倒置、通知上下滑动方向修复、Dock 避开刘海依赖倒置方向与小芒。Dock 避开刘海：配合 Lynx 等开启的 iPad 样式 Dock，倒置时把完全抬起的 Dock 再抬 35 点露出刘海，并让刘海处也能从底边上划；正向不变。"];
    [self addSwitch:@"Mango 原生屏幕倒置" key:NativeUpsideDownKey];
    PSSpecifier *nativeItem = _specifiers.lastObject;
    [nativeItem setProperty:@(!nativeReadError) forKey:@"enabled"];
    [self addSwitch:@"倒置方向与小芒修复" key:@"WorldEnabled"];
    [self addSwitch:@"分屏倒置修复" key:@"SplitEnabled"];
    [self addSwitch:@"启动器重开倒置恢复" key:@"LauncherRecoveryEnabled"];
    [self addSwitch:@"调整位置大小保持倒置" key:@"IslandLayoutEnabled"];
    [self addSwitch:@"通知上下滑动方向修复" key:@"SwipeDirectionEnabled"];
    [self addSwitch:@"倒置时 Dock 避开刘海" key:@"DockNotchEnabled"];

    [self addSection:@"调试" footer:nil];
    [self addLink:@"调试日志与一键提取" detail:NSClassFromString(@"MangoSuiteDiagnosticsController")];

    [self addSection:@"使用" footer:nil];
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
    if ([key isEqualToString:@"IdleGlowDensity"]) return MSReadPreferences(NULL)[key] ?: @1.0;
    if ([key isEqualToString:@"IdleGlowFade"]) return MSReadPreferences(NULL)[key] ?: @.55;
    if ([key isEqualToString:NativeUpsideDownKey]) return MSReadNativeUpsideDown(NULL) ?: @NO;
    return key.length ? @(SuiteFlag(key)) : nil;
}

- (void)writeValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if ([key isEqualToString:@"EdgeThickness"] || [key isEqualToString:@"EdgeDynamics"] || [key isEqualToString:@"IdleGlowDensity"] || [key isEqualToString:@"IdleGlowFade"]) {
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
    NSArray *known = [@[@"Enabled", @"IdleEnabled", @"AdaptiveEnabled", @"WorldEnabled", @"SplitEnabled", @"DebugEnabled", @"IdleGlowEnabled", @"IdleGlowShineEnabled", @"IdleGlowAdaptiveEnabled", @"IdleGlowFrostedEnabled"] arrayByAddingObjectsFromArray:MSRepairKeys()];
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
    [self showMessage:[NSString stringWithFormat:@"Mango 原生倒置：%@\n\n原生倒置开关独立于“启用整合修复”。更改原生倒置后，完整关闭设置再打开本页检查保存，然后 Respring。测试期间不要进入 Mango 原版的倒置设置页，它会清回关闭。\n\n总开关和四个模块开关（静止灵动岛、背景颜色自适应、倒置方向与小芒、分屏倒置）更改后，请在多巴胺中“重新启动用户空间”；Respring 不能重载颜色自适应模块。其余开关和滑杆约 1 秒内即时生效。\n\n玻璃与自适应参数按原有方式即时刷新。关闭总开关会保留你的各项选择及原生倒置偏好。", state] title:@"应用开关更改"];
}

- (void)showMissingAdaptive {
    [self showMessage:@"无法加载 AdaptiveColor 参数页面。请重新安装完整的 Mango 整合包。" title:@"参数页不可用"];
}

@end
