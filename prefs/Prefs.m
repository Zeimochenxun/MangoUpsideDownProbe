#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "../src/SuitePreferences.h"
#import "../src/NativePreferences.h"

static NSString * const NativeUpsideDownKey = @"LeXiang.UpsideDown.Enabled";

static BOOL SuiteFlag(NSString *key) {
    if (MSHasEmergencyMarker(key)) return NO;
    return MSPreferenceFlag(MSReadPreferences(NULL), key);
}

@interface MangoSuitePrefsController : PSListController
- (id)readValue:(PSSpecifier *)specifier;
- (void)writeValue:(id)value specifier:(PSSpecifier *)specifier;
- (void)showRestartHelp;
- (void)showMissingAdaptive;
@end

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
    [notice setProperty:@"本插件为mango插件的自改补丁，仅自用" forKey:@"footerText"];
    [_specifiers addObject:notice];

    [self addSection:@"总开关"];
    [self addSwitch:@"启用整合修复" key:@"Enabled"];

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
    if ([key isEqualToString:NativeUpsideDownKey]) return MSReadNativeUpsideDown(NULL) ?: @NO;
    return key.length ? @(SuiteFlag(key)) : nil;
}

- (void)writeValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if ([key isEqualToString:NativeUpsideDownKey]) {
        if (![value isKindOfClass:NSNumber.class]) return;
        NSError *error = nil;
        BOOL saved = MSWriteNativeUpsideDown([value boolValue], &error);
        [self reloadSpecifiers];
        if (!saved) [self showMessage:error.localizedDescription ?: @"请重新打开设置后检查当前倒置开关。" title:@"保存失败"];
        return;
    }
    NSArray *known = @[@"Enabled", @"IdleEnabled", @"AdaptiveEnabled", @"WorldEnabled", @"SplitEnabled"];
    if (![known containsObject:key] || ![value isKindOfClass:NSNumber.class]) return;
    BOOL enabled = [value boolValue];
    NSError *saveError = nil;
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
