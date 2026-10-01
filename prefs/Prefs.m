#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "../src/SuitePreferences.h"

static BOOL SuiteFlag(NSString *key) {
    NSString *marker = MSMarkerForKey(key);
    if (marker && [NSFileManager.defaultManager fileExistsAtPath:marker]) return NO;
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
    [self addSwitch:@"启用 Mango 整合补丁" key:@"Enabled"];

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
    [self addSwitch:@"倒置方向修复" key:@"WorldEnabled"];
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
    return key.length ? @(SuiteFlag(key)) : nil;
}

- (void)writeValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    NSArray *known = @[@"Enabled", @"IdleEnabled", @"AdaptiveEnabled", @"WorldEnabled", @"SplitEnabled"];
    if (![known containsObject:key] || ![value isKindOfClass:NSNumber.class]) return;
    BOOL enabled = [value boolValue];
    NSError *saveError = nil;
    if (!MSReadPreferences(&saveError)) {
        [self reloadSpecifiers];
        [self showMessage:[NSString stringWithFormat:@"%@\n%@", saveError.localizedDescription, saveError.userInfo[NSFilePathErrorKey]] title:@"保存失败"];
        return;
    }
    NSString *marker = MSMarkerForKey(key);
    NSFileManager *files = NSFileManager.defaultManager;
    BOOL hadMarker = enabled && marker && [files fileExistsAtPath:marker];
    NSData *markerContents = nil;
    if (hadMarker) {
        NSError *error = nil;
        markerContents = [NSData dataWithContentsOfFile:marker options:0 error:&error];
        if (!markerContents || ![files removeItemAtPath:marker error:&error]) {
            [self reloadSpecifiers];
            [self showMessage:[NSString stringWithFormat:@"无法清除该模块的旧停用标记，开关未保存。\n%@\n%@", marker, error.localizedDescription ?: @"请检查文件权限。"] title:@"未能开启"];
            return;
        }
    }
    if (!MSWritePreferenceFlag(key, enabled, &saveError)) {
        BOOL markerRestored = !hadMarker || [markerContents writeToFile:marker options:NSDataWritingAtomic error:NULL];
        [self reloadSpecifiers];
        NSError *cause = saveError.userInfo[NSUnderlyingErrorKey];
        NSString *message = [NSString stringWithFormat:@"%@\n%@\n%@%@", saveError.localizedDescription, saveError.userInfo[NSFilePathErrorKey], cause.localizedDescription ?: @"", markerRestored ? @"" : @"\n旧停用标记未能恢复；重启前请确认模块状态。"];
        [self showMessage:message title:@"保存失败"];
        return;
    }
    [self reloadSpecifiers];
}

- (void)showRestartHelp {
    [self showMessage:@"1. 保存所需模块开关。\n2. 打开越狱工具，选择“重新启动用户空间”。\n3. 完成后验证灵动岛和倒置、分屏效果。\n\n仅重新加载桌面（Respring）不能重新加载 backboardd 中的颜色自适应模块。本页开关会保留原参数；玻璃与自适应参数页沿用原插件的参数刷新方式。" title:@"应用开关更改"];
}

- (void)showMissingAdaptive {
    [self showMessage:@"无法加载 AdaptiveColor 参数页面。请重新安装完整的 Mango 整合包。" title:@"参数页不可用"];
}

@end
