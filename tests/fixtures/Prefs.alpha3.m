#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <CoreFoundation/CoreFoundation.h>

static CFStringRef const SuiteDomain = CFSTR("com.chenxun.mangosuite");
static NSString * const SuiteFile = @"/var/mobile/Library/Preferences/com.chenxun.mangosuite.plist";

static NSString *MarkerForKey(NSString *key) {
    if ([key isEqualToString:@"IdleEnabled"]) return @"/var/mobile/Library/Logs/MangoIdleIsland/DISABLED";
    if ([key isEqualToString:@"WorldEnabled"]) return @"/var/mobile/Library/Preferences/MangoUpsideDownWorld.disabled";
    if ([key isEqualToString:@"SplitEnabled"]) return @"/var/mobile/Library/Preferences/MangoSplitUpsideDownFix.disabled";
    return nil;
}

static id StoredValue(NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, SuiteDomain));
}

static BOOL SuiteFlag(NSString *key) {
    NSString *marker = MarkerForKey(key);
    if (marker && [NSFileManager.defaultManager fileExistsAtPath:marker]) return NO;
    NSDictionary *snapshot = [NSDictionary dictionaryWithContentsOfFile:SuiteFile];
    if (!snapshot && [NSFileManager.defaultManager fileExistsAtPath:SuiteFile]) return NO;
    id value = snapshot[key];
    return value == nil ? YES : ([value isKindOfClass:NSNumber.class] && [value boolValue]);
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

- (void)addSection:(NSString *)name footer:(NSString *)footer {
    PSSpecifier *group = name.length ? [PSSpecifier groupSpecifierWithName:name] : [PSSpecifier emptyGroupSpecifier];
    if (footer.length) [group setProperty:footer forKey:@"footerText"];
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
    CFPreferencesAppSynchronize(SuiteDomain);

    [self addSection:@"总开关" footer:@"修改本页任何开关后，请在越狱工具中重新启动用户空间。仅重新加载桌面不足以应用全部模块。关闭总开关会保留各模块的选择。"];
    [self addSwitch:@"启用 Mango 整合补丁" key:@"Enabled"];

    [self addSection:@"灵动岛外观" footer:@"在静止状态补充玻璃，并协调通知、音乐和展开收拢时的过渡。参数页中的玻璃参数属于 Mango 全局灵动岛设置。"];
    [self addSwitch:@"静止灵动岛与过渡修复" key:@"IdleEnabled"];
    PSSpecifier *glass = [PSSpecifier preferenceSpecifierNamed:@"玻璃与边缘光参数" target:self set:nil get:nil detail:NSClassFromString(@"MangoSuiteGlassController") cell:PSLinkCell edit:nil];
    [_specifiers addObject:glass];

    [self addSection:nil footer:@"按背景明暗调整岛体颜色。开启时，色调强度由自适应参数中的明暗不透明度控制；基础色调强度在关闭自适应并重启用户空间后生效。"];
    [self addSwitch:@"背景颜色自适应" key:@"AdaptiveEnabled"];
    Class adaptiveClass = [self adaptiveControllerClass];
    PSSpecifier *adaptive = [PSSpecifier preferenceSpecifierNamed:@"自适应颜色参数" target:self set:nil get:nil detail:adaptiveClass cell:adaptiveClass ? PSLinkCell : PSButtonCell edit:nil];
    if (!adaptiveClass) [adaptive setButtonAction:@selector(showMissingAdaptive)];
    [_specifiers addObject:adaptive];

    [self addSection:@"旋转与布局" footer:@"控制整体倒置方向修复。可与分屏倒置修复分别开关；修改后重启用户空间。"];
    [self addSwitch:@"倒置方向修复" key:@"WorldEnabled"];
    [self addSection:nil footer:@"修复倒置时的分屏布局。只影响此模块，关闭不会更改上方的方向修复选择。"];
    [self addSwitch:@"分屏倒置修复" key:@"SplitEnabled"];

    [self addSection:@"版本与使用" footer:@"IdleIsland 1.1.9.2 alpha2\nAdaptiveColor 0.1.3\nMangoUpsideDownWorld 1.2.0\nMangoSplitUpsideDownFix 0.1.1 alpha2\n\n适用于 Mango Beta7-1、iOS 16.5、RootHide arm64e。整合包需要原版 Mango。旧版独立补丁应由安装器替换，避免重复注入。"];
    PSSpecifier *help = [PSSpecifier preferenceSpecifierNamed:@"如何应用开关更改" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [help setButtonAction:@selector(showRestartHelp)];
    [_specifiers addObject:help];
    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    CFPreferencesAppSynchronize(SuiteDomain);
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
    id previous = StoredValue(key);
    NSString *marker = MarkerForKey(key);
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
    CFPreferencesSetAppValue((__bridge CFStringRef)key, enabled ? kCFBooleanTrue : kCFBooleanFalse, SuiteDomain);
    BOOL synchronized = CFPreferencesAppSynchronize(SuiteDomain);
    id saved = [NSDictionary dictionaryWithContentsOfFile:SuiteFile][key];
    if (!synchronized || ![saved isKindOfClass:NSNumber.class] || [saved boolValue] != enabled) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)previous, SuiteDomain);
        CFPreferencesAppSynchronize(SuiteDomain);
        BOOL markerRestored = !hadMarker || [markerContents writeToFile:marker options:NSDataWritingAtomic error:NULL];
        [self reloadSpecifiers];
        NSString *message = markerRestored ? @"设置未能写入，请检查偏好文件权限后重试。" : @"设置未能写入，且旧停用标记未能恢复。请检查文件权限；重启用户空间前先确认该模块的状态。";
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
