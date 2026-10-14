// Settings → 屏幕倒置 → 第二排固定 App. One switch per visible installed app;
// the order apps are switched on is the order the dock drawer's row 2 shows
// them in, left of the recents. Stored as DockDrawerPinned (bundle ids).
#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <objc/message.h>
#import "../src/SuitePreferences.h"

static const NSUInteger PinnedMax = 5;

@interface MangoSuiteDockPinnedController : PSListController
@end

static NSArray<NSString *> *Pinned(void) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    id list = MSReadPreferences(NULL)[@"DockDrawerPinned"];
    if ([list isKindOfClass:NSArray.class])
        for (id bundle in list) if ([bundle isKindOfClass:NSString.class]) [out addObject:bundle];
    return out;
}

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

@implementation MangoSuiteDockPinnedController

- (void)showMessage:(NSString *)message title:(NSString *)title {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

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
    _specifiers = [NSMutableArray new];
    NSArray<NSArray<NSString *> *> *apps = InstalledApps();
    NSArray<NSString *> *pinned = Pinned();
    PSSpecifier *chosen = [PSSpecifier groupSpecifierWithName:@"已固定（按打开顺序从左往右）"];
    [chosen setProperty:[NSString stringWithFormat:@"最多 %lu 个，排在第二排最左边，右边放最近使用。固定的 App 不会出现在第一排的最近使用里；已放在第一排固定栏里的 App 不会重复显示。", (unsigned long)PinnedMax] forKey:@"footerText"];
    [_specifiers addObject:chosen];
    for (NSString *bundle in pinned)
        for (NSArray<NSString *> *app in apps)
            if ([app[1] isEqualToString:bundle]) [_specifiers addObject:[self appItem:app]];
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"全部 App"]];
    for (NSArray<NSString *> *app in apps)
        if (![pinned containsObject:app[1]]) [_specifiers addObject:[self appItem:app]];
    return _specifiers;
}

- (id)readValue:(PSSpecifier *)specifier {
    return @([Pinned() containsObject:[specifier propertyForKey:@"bundle"]]);
}

- (void)writeValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *bundle = [specifier propertyForKey:@"bundle"];
    if (![bundle isKindOfClass:NSString.class] || ![value isKindOfClass:NSNumber.class]) return;
    NSMutableArray<NSString *> *list = [Pinned() mutableCopy];
    if ([value boolValue] && ![list containsObject:bundle]) {
        if (list.count >= PinnedMax) {
            [self showMessage:[NSString stringWithFormat:@"第二排最多固定 %lu 个 App，请先关掉一个。", (unsigned long)PinnedMax] title:@"已满"];
            [self reloadSpecifiers];
            return;
        }
        [list addObject:bundle];
    } else if (![value boolValue]) {
        [list removeObject:bundle];
    }
    NSError *error = nil;
    if (!MSWritePreferenceValue(@"DockDrawerPinned", list, &error)) [self showMessage:error.localizedDescription title:@"保存失败"];
    _specifiers = nil;
    [self reloadSpecifiers];
}

@end
