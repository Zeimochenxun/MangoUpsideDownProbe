// Settings → 双层 Dock. Switches write Application Support/DoubleDock/
// settings.plist (Settings.h); SpringBoard picks them up within 250ms,
// except FloatingDock, which applies at the next respring.
#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <objc/message.h>
#import "../Settings.h"

@interface DoubleDockRootController : PSListController
@end
@interface DoubleDockPinnedController : PSListController
@end

static void Alert(UIViewController *controller, NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

static PSSpecifier *Group(NSString *name, NSString *footer) {
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:name];
    if (footer) [group setProperty:footer forKey:@"footerText"];
    return group;
}

@implementation DoubleDockRootController

- (PSSpecifier *)toggle:(NSString *)name key:(NSString *)key {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(setFlag:specifier:) get:@selector(flag:) detail:nil cell:PSSwitchCell edit:nil];
    [item setProperty:key forKey:@"key"];
    return item;
}

- (NSMutableArray *)specifiers {
    if (_specifiers) return _specifiers;
    self.title = @"双层 Dock";
    NSMutableArray *list = [NSMutableArray array];
    id suiteDrawer = [NSDictionary dictionaryWithContentsOfFile:DDSuiteFile(@"settings.plist")][@"DockDrawerEnabled"];
    if ([suiteDrawer isKindOfClass:NSNumber.class] && [suiteDrawer boolValue])
        [list addObject:Group(@"Mango Suite 的双层 Dock 还开着", @"两个只能用一个：Mango Suite 里的开着时，这里会自动让开。请到 Mango Suite 的设置里关掉它，然后注销一次。")];
    [list addObject:Group(@"第二排", @"Dock 完全出现后，在 Dock 上往上滑拉出第二排，往下滑收起。第二排先放固定的 App，再放最近用过、第一排没有的 App。")];
    [list addObject:[self toggle:@"启用双层 Dock" key:@"Enabled"]];
    [list addObject:[self toggle:@"固定 App 后加分隔线" key:@"Divider"]];
    [list addObject:[PSSpecifier preferenceSpecifierNamed:@"第二排固定 App" target:self set:nil get:nil detail:DoubleDockPinnedController.class cell:PSLinkCell edit:nil]];
    [list addObject:Group(@"iPad 样式 Dock", @"让 iPhone 用上 iPad 那样悬浮的 Dock，双层 Dock 要靠它。已经在 Lynx 里打开浮动 Dock 的话，这里开不开都一样。改动后注销一次才生效。")];
    [list addObject:[self toggle:@"启用 iPad 样式 Dock" key:@"FloatingDock"]];
    [list addObject:Group(@"倒置时避开刘海", @"屏幕倒过来时，Dock 的底边正好在刘海下面。打开后，完全出来的 Dock 会再往上抬一些，滑动距离不变；正着用时不受影响。装着 Mango Suite 且它的“倒置时 Dock 避开刘海”开着时，由 Suite 负责抬升（它还管刘海处防误触），这里的设置先不起作用。")];
    [list addObject:[self toggle:@"倒置时 Dock 避开刘海" key:@"NotchLift"]];
    PSSpecifier *height = [PSSpecifier preferenceSpecifierNamed:@"Dock 抬升高度（点，默认 35）" target:self set:@selector(setHeight:specifier:) get:@selector(height:) detail:nil cell:PSSliderCell edit:nil];
    [height setProperty:@0 forKey:@"min"];
    [height setProperty:@(DDLiftMax) forKey:@"max"];
    [height setProperty:@YES forKey:@"showValue"];
    [list addObject:height];
    [list addObject:Group(@"诊断", [NSString stringWithFormat:@"双层 Dock %@。遇到问题时导出日志发给开发者。", @DD_VERSION])];
    PSSpecifier *share = [PSSpecifier preferenceSpecifierNamed:@"导出诊断日志" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [share setButtonAction:@selector(shareLog)];
    [list addObject:share];
    _specifiers = list;
    return _specifiers;
}

- (id)flag:(PSSpecifier *)specifier {
    return @(DDFlag(DDReadSettings(), [specifier propertyForKey:@"key"]));
}

- (void)setFlag:(id)value specifier:(PSSpecifier *)specifier {
    NSError *error = nil;
    if (![value isKindOfClass:NSNumber.class] || !DDWriteSetting([specifier propertyForKey:@"key"], @([value boolValue]), &error))
        Alert(self, @"保存失败", error.localizedDescription ?: @"无效的值。");
}

- (id)height:(__unused PSSpecifier *)specifier {
    return @(DDLiftHeight(DDReadSettings()));
}

- (void)setHeight:(id)value specifier:(__unused PSSpecifier *)specifier {
    NSError *error = nil;
    if (![value isKindOfClass:NSNumber.class] || !DDWriteSetting(@"LiftHeight", @(round(fmin(DDLiftMax, fmax(0, [value doubleValue])))), &error))
        Alert(self, @"保存失败", error.localizedDescription ?: @"无效的值。");
}

- (void)shareLog {
    NSMutableString *report = [NSMutableString stringWithFormat:@"双层 Dock %@ / iOS %@\n导出时间：%@\n\n", @DD_VERSION, UIDevice.currentDevice.systemVersion, NSDate.date];
    for (NSString *name in @[@"DoubleDock.log.old", @"DoubleDock.log"]) {
        NSString *text = [NSString stringWithContentsOfFile:DDFile(name) encoding:NSUTF8StringEncoding error:nil];
        if (text) [report appendString:text];
    }
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"DoubleDockExports"];
    NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"DoubleDock-%@.txt", [NSUUID.UUID.UUIDString substringToIndex:8]]];
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

static id Get(id object, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    return [object respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(object, sel) : nil;
}

// @[name, bundle id] for user apps and non-hidden system apps, by name.
static NSArray<NSArray<NSString *> *> *InstalledApps(void) {
    NSMutableArray<NSArray<NSString *> *> *apps = [NSMutableArray array];
    id workspace = Get(NSClassFromString(@"LSApplicationWorkspace"), @"defaultWorkspace");
    for (id proxy in Get(workspace, @"allInstalledApplications")) {
        NSString *bundle = Get(proxy, @"applicationIdentifier"), *name = Get(proxy, @"localizedName"), *type = Get(proxy, @"applicationType");
        NSArray *tags = Get(proxy, @"appTags");
        if (![bundle isKindOfClass:NSString.class] || ![name isKindOfClass:NSString.class] || !bundle.length || !name.length) continue;
        if (![type isEqual:@"User"] && ![type isEqual:@"System"]) continue;
        if (([tags isKindOfClass:NSArray.class] && [tags containsObject:@"hidden"]) || [bundle hasPrefix:@"com.apple.webapp"]) continue;
        [apps addObject:@[name, bundle]];
    }
    [apps sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [a[0] localizedStandardCompare:b[0]]; }];
    return apps;
}

static UIImage *AppIcon(NSString *bundle) {
    SEL sel = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if (![UIImage respondsToSelector:sel]) return nil;
    return ((UIImage *(*)(id, SEL, NSString *, int, double))objc_msgSend)(UIImage.class, sel, bundle, 0, UIScreen.mainScreen.scale);
}

// 第二排固定 App: one switch per visible installed app; the order they are
// switched on is the order row 2 shows them in, left of the recents.
@implementation DoubleDockPinnedController

- (PSSpecifier *)appItem:(NSArray<NSString *> *)app {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:app[0] target:self set:@selector(writeValue:specifier:) get:@selector(readValue:) detail:nil cell:PSSwitchCell edit:nil];
    [item setProperty:app[1] forKey:@"bundle"];
    UIImage *icon = AppIcon(app[1]);
    if (icon) [item setProperty:icon forKey:@"iconImage"];
    return item;
}

- (NSMutableArray *)specifiers {
    if (_specifiers) return _specifiers;
    self.title = @"第二排固定 App";
    NSMutableArray *list = [NSMutableArray array];
    NSArray<NSArray<NSString *> *> *apps = InstalledApps();
    NSArray<NSString *> *pinned = DDPinned(DDReadSettings());
    [list addObject:Group(@"已固定（按打开顺序从左往右）", [NSString stringWithFormat:@"最多 %lu 个，排在第二排最左边，右边放最近使用。固定的 App 不会出现在第一排的最近使用里；已放在第一排固定栏里的 App 不会重复显示。", (unsigned long)DDPinnedMax])];
    for (NSString *bundle in pinned)
        for (NSArray<NSString *> *app in apps)
            if ([app[1] isEqualToString:bundle]) [list addObject:[self appItem:app]];
    [list addObject:Group(@"全部 App", nil)];
    for (NSArray<NSString *> *app in apps)
        if (![pinned containsObject:app[1]]) [list addObject:[self appItem:app]];
    _specifiers = list;
    return _specifiers;
}

- (id)readValue:(PSSpecifier *)specifier {
    return @([DDPinned(DDReadSettings()) containsObject:[specifier propertyForKey:@"bundle"]]);
}

- (void)writeValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *bundle = [specifier propertyForKey:@"bundle"];
    if (![bundle isKindOfClass:NSString.class] || ![value isKindOfClass:NSNumber.class]) return;
    NSMutableArray<NSString *> *list = [DDPinned(DDReadSettings()) mutableCopy];
    if ([value boolValue] && ![list containsObject:bundle]) {
        if (list.count >= DDPinnedMax) {
            Alert(self, @"已满", [NSString stringWithFormat:@"第二排最多固定 %lu 个 App，请先关掉一个。", (unsigned long)DDPinnedMax]);
            [self reloadSpecifiers];
            return;
        }
        [list addObject:bundle];
    } else if (![value boolValue]) {
        [list removeObject:bundle];
    }
    NSError *error = nil;
    if (!DDWriteSetting(@"Pinned", list, &error)) Alert(self, @"保存失败", error.localizedDescription);
    _specifiers = nil;
    [self reloadSpecifiers];
}

@end
