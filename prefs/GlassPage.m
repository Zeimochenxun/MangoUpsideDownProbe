#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>
#import "../src/SuitePreferences.h"

static CFStringRef const Domain = CFSTR("com.go.mangoosprefs");
// Beta9 MangoOSRendering listens here, reloads its parameter cache, then
// publishes go.mangoos/ParametersReloaded to existing live filter instances.
static CFStringRef const RenderReload = CFSTR("com.go.mangoosprefs/Reload");
static NSString * const TintUIKey = @"MangoIdleIsland.TintAlpha";

static BOOL SuiteAdaptiveEnabled(void) {
    NSDictionary *snapshot = MSReadPreferences(NULL);
    return MSPreferenceFlag(snapshot, @"Enabled") && MSPreferenceFlag(snapshot, @"AdaptiveEnabled");
}

@interface MangoSuiteGlassController : PSListController
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
    return @0.0;
}

static NSString *ColorWithAlpha(id existing, NSString *fallbackRGB, unsigned alpha) {
    NSString *rgb = nil;
    if (!ParseRGBAHex(existing, &rgb, NULL)) rgb = fallbackRGB;
    return [NSString stringWithFormat:@"#%@%02X", rgb, alpha];
}

static void PostReload(void) {
    if (!CFPreferencesAppSynchronize(Domain)) return;

    // Do not jump straight to ParametersReloaded: the verified Beta9
    // Rendering callback on com.go.mangoosprefs/Reload performs the important
    // cache re-read first and then publishes ParametersReloaded itself.
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         RenderReload,
                                         NULL,
                                         NULL,
                                         YES);
}

@implementation MangoSuiteGlassController

- (PSSpecifier *)item:(NSString *)name key:(NSString *)key cell:(PSCellType)cell low:(NSNumber *)low high:(NSNumber *)high {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:name
                                                        target:self
                                                           set:@selector(writeValue:specifier:)
                                                           get:@selector(readValue:)
                                                        detail:nil
                                                          cell:cell
                                                          edit:nil];
    [item setProperty:key forKey:@"key"];
    if ([key isEqualToString:TintUIKey]) [item setProperty:@(!SuiteAdaptiveEnabled()) forKey:@"enabled"];
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
    self.title = @"玻璃与边缘光参数";
    _specifiers = [NSMutableArray new];

    [self addSectionNamed:@"玻璃外观"
              description:@"调整 Mango 灵动岛的全局玻璃参数，同时影响静止与活动状态。色调通透范围 0–3，Mango Beta9 默认约 0.1。"
                     item:[self item:@"色调通透" key:@"Island.Blur" cell:PSSliderCell low:@0 high:@3]];

    [self addSectionNamed:nil
              description:@"自适应开启时，请在“自适应颜色参数”中调整明暗不透明度，本项暂不可调。关闭自适应并重新启动用户空间后，本项控制基础色调强度（0–1），分别保留浅色和深色的原有 RGB。"
                     item:[self item:@"基础色调强度" key:TintUIKey cell:PSSliderCell low:@0 high:@1]];

    [self addSectionNamed:@"边缘光"
              description:@"开启灵动岛边缘高光；显示效果仍受 Mango 原版全局边缘光条件影响。"
                     item:[self item:@"边缘光" key:@"Island.SpecularEnabled" cell:PSSwitchCell low:nil high:nil]];

    [self addSectionNamed:nil
              description:@"边缘光强度范围 0–1，开启边缘光后生效。"
                     item:[self item:@"边缘光强度" key:@"Island.SpecularOpacity" cell:PSSliderCell low:@0 high:@1]];

    [self addSectionNamed:@"光斑"
              description:@"开启或关闭灵动岛光斑。"
                     item:[self item:@"光斑" key:@"Island.DispersionEnabled" cell:PSSwitchCell low:nil high:nil]];

    [self addSectionNamed:nil
              description:@"范围 0–20。这是 Mango 全局光斑强度，也会影响其他已开启光斑的玻璃区域。"
                     item:[self item:@"光斑强度（全局）" key:@"Global.DispersionStrength" cell:PSSliderCell low:@0 high:@20]];

    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _specifiers = nil;
    [self reloadSpecifiers];
}

static id DefaultValueForKey(NSString *key) {
    if ([key isEqualToString:@"Island.Blur"]) return @0.1;
    if ([key isEqualToString:@"Island.SpecularOpacity"]) return @0.6;
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
    if ([key isEqualToString:TintUIKey] && SuiteAdaptiveEnabled()) return;

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

        // Beta9's scalar tint can override the full Light/Dark RGBA values.
        // Keep one source of truth and preserve the two RGB variants separately.
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
