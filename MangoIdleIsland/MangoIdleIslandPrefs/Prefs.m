#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>

static CFStringRef const Domain = CFSTR("com.go.mangoosprefs");
static CFStringRef const Reload = CFSTR("go.mangoos/ParametersReloaded");

@interface MangoIdlePrefsController : PSListController
- (id)readValue:(PSSpecifier *)specifier;
- (void)writeValue:(id)value specifier:(PSSpecifier *)specifier;
@end

@implementation MangoIdlePrefsController

- (PSSpecifier *)item:(NSString *)name key:(NSString *)key cell:(PSCellType)cell low:(NSNumber *)low high:(NSNumber *)high {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:name
                                                        target:self
                                                           set:@selector(writeValue:specifier:)
                                                           get:@selector(readValue:)
                                                        detail:nil
                                                          cell:cell
                                                          edit:nil];
    [item setProperty:key forKey:@"key"];
    if (low && high) {
        [item setProperty:low forKey:@"min"];
        [item setProperty:high forKey:@"max"];
        [item setProperty:@YES forKey:@"showValue"];
        [item setProperty:@NO forKey:@"isContinuous"];
    }
    return item;
}

- (void)addSectionNamed:(NSString *)sectionName
            description:(NSString *)description
                   item:(PSSpecifier *)item {
    PSSpecifier *group = sectionName.length
        ? [PSSpecifier groupSpecifierWithName:sectionName]
        : [PSSpecifier emptyGroupSpecifier];
    if (description.length) {
        [group setProperty:description forKey:@"footerText"];
    }
    [_specifiers addObject:group];
    [_specifiers addObject:item];
}

- (NSMutableArray *)specifiers {
    if (_specifiers) return _specifiers;
    _specifiers = [NSMutableArray new];

    [self addSectionNamed:@"灵动岛玻璃 · Mango 原版参数"
              description:@"仅调整 Island 表面；其他 Mango 玻璃维持原样。首次拖动或切换后才保存参数。\n\n色调通透：控制 Mango 的 Island.Blur 参数（0–3），用于改变灵动岛玻璃的模糊与通透表现；尚未写入时按 Mango 默认值约 1.7 显示。"
                     item:[self item:@"色调通透" key:@"Island.Blur" cell:PSSliderCell low:@0 high:@3]];

    [self addSectionNamed:nil
              description:@"色调强度：直接控制 Mango 渲染器的 Island.TintStrength 参数（0–1）。数值越大，色调作用越明显；本项不再修改浅色/深色色值或颜色透明度。尚未写入时按约 0.10 显示。"
                     item:[self item:@"色调强度" key:@"Island.TintStrength" cell:PSSliderCell low:@0 high:@1]];

    [self addSectionNamed:nil
              description:@"边缘光：开启或关闭灵动岛的边缘高光效果。此开关只控制 Island，本效果仍受 Mango 原版边缘光总开关约束。"
                     item:[self item:@"边缘光" key:@"Island.SpecularEnabled" cell:PSSwitchCell low:nil high:nil]];

    [self addSectionNamed:nil
              description:@"边缘光调整：控制灵动岛边缘光的透明度/强度（0–1）。仅在 Island 边缘光开启且 Mango 原版总开关允许时可见。"
                     item:[self item:@"边缘光调整" key:@"Island.SpecularOpacity" cell:PSSliderCell low:@0 high:@1]];

    [self addSectionNamed:nil
              description:@"光斑：开启或关闭灵动岛玻璃的光斑/色散效果。"
                     item:[self item:@"光斑" key:@"Island.DispersionEnabled" cell:PSSwitchCell low:nil high:nil]];

    [self addSectionNamed:nil
              description:@"光斑强度（全局）：控制 Mango 的全局光斑强度（0–20）。该值不是 Island 独占参数，也会影响其他已启用光斑的 Mango 玻璃。"
                     item:[self item:@"光斑强度（全局）" key:@"Global.DispersionStrength" cell:PSSliderCell low:@0 high:@20]];

    return _specifiers;
}

static id CopyValue(NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, Domain));
}

static id DefaultValueForKey(NSString *key) {
    if ([key isEqualToString:@"Island.Blur"]) return @1.7;
    if ([key isEqualToString:@"Island.TintStrength"]) return @0.10;
    if ([key isEqualToString:@"Island.SpecularOpacity"]) return @0.1;
    if ([key isEqualToString:@"Island.SpecularEnabled"]) return @NO;
    if ([key isEqualToString:@"Island.DispersionEnabled"]) return @YES;
    if ([key isEqualToString:@"Global.DispersionStrength"]) return @5;
    return nil;
}

- (id)readValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return nil;

    id actual = CopyValue(key);
    if ([actual isKindOfClass:NSNumber.class]) return actual;
    return DefaultValueForKey(key);
}

- (void)writeValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length || ![value isKindOfClass:NSNumber.class]) return;

    NSNumber *minimum = [specifier propertyForKey:@"min"];
    NSNumber *maximum = [specifier propertyForKey:@"max"];
    if (minimum && maximum) {
        double numeric = [value doubleValue];
        if (!isfinite(numeric)) return;
        numeric = fmin(maximum.doubleValue, fmax(minimum.doubleValue, numeric));
        value = @(numeric);
    }

    // Mango Beta7 exposes TintStrength as its own per-surface parameter.
    // Keep every preference mapped one-to-one to its real Mango key.
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             Domain);

    if (CFPreferencesAppSynchronize(Domain)) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             Reload,
                                             NULL,
                                             NULL,
                                             YES);
    }
}

@end
