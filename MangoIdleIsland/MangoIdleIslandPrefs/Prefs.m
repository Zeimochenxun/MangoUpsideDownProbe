#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>

static CFStringRef const Domain = CFSTR("com.go.mangoosprefs");
static CFStringRef const Reload = CFSTR("go.mangoos/ParametersReloaded");
static NSString * const TintUIKey = @"MangoIdleIsland.TintAlpha";

@interface MangoIdlePrefsController : PSListController
- (id)readValue:(PSSpecifier *)specifier;
- (void)writeValue:(id)value specifier:(PSSpecifier *)specifier;
@end

static id CopyValue(NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, Domain));
}

static BOOL ParseRGBAHex(id value, NSString **rgbOut, unsigned *alphaOut) {
    if (![value isKindOfClass:NSString.class]) return NO;
    NSString *color = (NSString *)value;
    if (color.length != 9 || ![color hasPrefix:@"#"]) return NO;

    NSString *hex = [color substringFromIndex:1];
    NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFabcdef"] invertedSet];
    if ([hex rangeOfCharacterFromSet:bad].location != NSNotFound) return NO;

    unsigned alpha = 0;
    NSScanner *scanner = [NSScanner scannerWithString:[hex substringFromIndex:6]];
    if (![scanner scanHexInt:&alpha] || !scanner.isAtEnd || alpha > 255) return NO;

    if (rgbOut) *rgbOut = [hex substringToIndex:6];
    if (alphaOut) *alphaOut = alpha;
    return YES;
}

static NSNumber *CurrentTintAlpha(void) {
    unsigned alpha = 0;
    if (ParseRGBAHex(CopyValue(@"Island.LightTintColor"), NULL, &alpha) ||
        ParseRGBAHex(CopyValue(@"Island.DarkTintColor"), NULL, &alpha)) {
        return @((double)alpha / 255.0);
    }

    // MangoOSRendering Beta7's built-in Island record initializes the final
    // tint RGBA vector to 0,0,0,0.  Do not invent the old 0.10 fallback.
    return @0.0;
}

static NSString *ColorWithAlpha(id existing, NSString *fallbackRGB, unsigned alpha) {
    NSString *rgb = nil;
    if (!ParseRGBAHex(existing, &rgb, NULL)) rgb = fallbackRGB;
    return [NSString stringWithFormat:@"#%@%02X", rgb, alpha];
}

static void PostReload(void) {
    if (CFPreferencesAppSynchronize(Domain)) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             Reload,
                                             NULL,
                                             NULL,
                                             YES);
    }
}

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
    if (description.length) [group setProperty:description forKey:@"footerText"];
    [_specifiers addObject:group];
    [_specifiers addObject:item];
}

- (NSMutableArray *)specifiers {
    if (_specifiers) return _specifiers;
    _specifiers = [NSMutableArray new];

    [self addSectionNamed:@"灵动岛玻璃 · Mango 原版参数"
              description:@"全局调整灵动岛玻璃：同一套 Island 参数同时作用于静止态和 Mango 活动态；不叠加第二层玻璃。首次拖动或切换后才保存参数。\n\n色调通透：控制 Mango 的 Island.Blur 参数（0–3）；Mango Beta7 的 Island 内置默认值为 1.7。"
                     item:[self item:@"色调通透" key:@"Island.Blur" cell:PSSliderCell low:@0 high:@3]];

    [self addSectionNamed:nil
              description:@"色调强度：调整 Mango 最终使用的浅色/深色色调 RGBA 透明度（0–1），并保留两套颜色原有 RGB。0 为不叠加色调；数值接近 1 时色调会明显遮盖玻璃内容。此实现不会再单独写入 Island.TintStrength。"
                     item:[self item:@"色调强度" key:TintUIKey cell:PSSliderCell low:@0 high:@1]];

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

static id DefaultValueForKey(NSString *key) {
    if ([key isEqualToString:@"Island.Blur"]) return @1.7;
    if ([key isEqualToString:@"Island.SpecularOpacity"]) return @0.1;
    if ([key isEqualToString:@"Island.SpecularEnabled"]) return @NO;
    if ([key isEqualToString:@"Island.DispersionEnabled"]) return @YES;
    if ([key isEqualToString:@"Global.DispersionStrength"]) return @5;
    return nil;
}

- (id)readValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return nil;
    if ([key isEqualToString:TintUIKey]) return CurrentTintAlpha();

    id actual = CopyValue(key);
    if ([actual isKindOfClass:NSNumber.class]) return actual;
    return DefaultValueForKey(key);
}

- (void)writeValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length || ![value isKindOfClass:NSNumber.class]) return;

    NSNumber *minimum = [specifier propertyForKey:@"min"];
    NSNumber *maximum = [specifier propertyForKey:@"max"];
    double numeric = [value doubleValue];
    if (!isfinite(numeric)) return;
    if (minimum && maximum) numeric = fmin(maximum.doubleValue, fmax(minimum.doubleValue, numeric));

    if ([key isEqualToString:TintUIKey]) {
        unsigned alpha = (unsigned)lround(numeric * 255.0);
        NSString *light = ColorWithAlpha(CopyValue(@"Island.LightTintColor"), @"FFFFFF", alpha);
        NSString *dark = ColorWithAlpha(CopyValue(@"Island.DarkTintColor"), @"000000", alpha);

        CFPreferencesSetAppValue(CFSTR("Island.LightTintColor"), (__bridge CFStringRef)light, Domain);
        CFPreferencesSetAppValue(CFSTR("Island.DarkTintColor"), (__bridge CFStringRef)dark, Domain);

        // In Beta7 LightTintColor is parsed after the scalar TintStrength and
        // overwrites the complete light RGBA vector.  Keep one source of truth.
        CFPreferencesSetAppValue(CFSTR("Island.TintStrength"), NULL, Domain);
    } else {
        value = @(numeric);
        CFPreferencesSetAppValue((__bridge CFStringRef)key,
                                 (__bridge CFPropertyListRef)value,
                                 Domain);
    }

    PostReload();
}

@end
