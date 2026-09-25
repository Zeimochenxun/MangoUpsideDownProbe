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
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(writeValue:specifier:) get:@selector(readValue:) detail:nil cell:cell edit:nil];
    [item setProperty:key forKey:@"key"];
    if (low && high) {
        [item setProperty:low forKey:@"min"];
        [item setProperty:high forKey:@"max"];
        [item setProperty:@YES forKey:@"showValue"];
        [item setProperty:@NO forKey:@"isContinuous"];
    }
    return item;
}

- (NSMutableArray *)specifiers {
    if (_specifiers) return _specifiers;
    _specifiers = [NSMutableArray new];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"灵动岛玻璃 · Mango 原版参数"];
    [group setProperty:@"仅调整 Island 表面；其他 Mango 玻璃维持原样。首次拖动或切换后才保存参数。" forKey:@"footerText"];
    [_specifiers addObject:group];
    [_specifiers addObject:[self item:@"色调通透" key:@"Island.Blur" cell:PSSliderCell low:@0 high:@3]];
    [_specifiers addObject:[self item:@"色调强度" key:@"Island.TintStrength" cell:PSSliderCell low:@0 high:@1]];
    [_specifiers addObject:[self item:@"边缘光" key:@"Island.SpecularEnabled" cell:PSSwitchCell low:nil high:nil]];
    [_specifiers addObject:[self item:@"边缘光调整" key:@"Island.SpecularOpacity" cell:PSSliderCell low:@0 high:@1]];
    [_specifiers addObject:[self item:@"光斑" key:@"Island.DispersionEnabled" cell:PSSwitchCell low:nil high:nil]];
    [_specifiers addObject:[self item:@"光斑强度（全局）" key:@"Global.DispersionStrength" cell:PSSliderCell low:@0 high:@20]];
    PSSpecifier *note = [PSSpecifier emptyGroupSpecifier];
    [note setProperty:@"光斑强度为 Mango 原版全局参数，也会影响其他启用光斑的玻璃。边缘光仍受 Mango 原版总开关控制。" forKey:@"footerText"];
    [_specifiers addObject:note];
    return _specifiers;
}

static id CopyValue(NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, Domain));
}

// Beta7's tint control stores RGB plus a 00..FF alpha byte, not a second blur.
static NSNumber *CurrentTintStrength(void) {
    NSString *color = CopyValue(@"Island.LightTintColor");
    if (![color isKindOfClass:NSString.class] || color.length != 9 || ![color hasPrefix:@"#"]) return @(26.0 / 255.0);
    unsigned value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:[color substringFromIndex:7]];
    if (![scanner scanHexInt:&value] || !scanner.isAtEnd || value > 255) return @(26.0 / 255.0);
    return @((double)value / 255.0);
}

- (id)readValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if ([key isEqualToString:@"Island.TintStrength"]) return CurrentTintStrength();
    id actual = CopyValue(key);
    if ([actual isKindOfClass:NSNumber.class]) return actual;
    if ([key isEqualToString:@"Island.Blur"]) return @1.7;
    if ([key isEqualToString:@"Island.SpecularOpacity"]) return @0.1;
    if ([key isEqualToString:@"Island.SpecularEnabled"]) return @NO;
    if ([key isEqualToString:@"Island.DispersionEnabled"]) return @YES;
    if ([key isEqualToString:@"Global.DispersionStrength"]) return @5;
    return nil;
}

static NSString *ColorWithAlpha(id existing, NSString *fallback, unsigned alpha) {
    NSString *rgb = fallback;
    if ([existing isKindOfClass:NSString.class] && [existing length] == 9 && [existing hasPrefix:@"#"]) {
        NSString *candidate = [existing substringWithRange:NSMakeRange(1, 6)];
        NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFabcdef"] invertedSet];
        if ([candidate rangeOfCharacterFromSet:bad].location == NSNotFound) rgb = candidate;
    }
    return [NSString stringWithFormat:@"#%@%02X", rgb, alpha];
}

- (void)writeValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key || ![value isKindOfClass:NSNumber.class]) return;
    if ([key isEqualToString:@"Island.TintStrength"]) {
        double val = [value doubleValue];
        if (!isfinite(val)) return;
        unsigned alpha = (unsigned)lround(fmin(1.0, fmax(0.0, val)) * 255.0);
        NSString *light = ColorWithAlpha(CopyValue(@"Island.LightTintColor"), @"FFFFFF", alpha);
        NSString *dark = ColorWithAlpha(CopyValue(@"Island.DarkTintColor"), @"000000", alpha);
        CFPreferencesSetAppValue(CFSTR("Island.LightTintColor"), (__bridge CFStringRef)light, Domain);
        CFPreferencesSetAppValue(CFSTR("Island.DarkTintColor"), (__bridge CFStringRef)dark, Domain);
    } else {
        NSNumber *minimum = [specifier propertyForKey:@"min"];
        NSNumber *maximum = [specifier propertyForKey:@"max"];
        if (minimum && maximum) {
            double val = [value doubleValue];
            if (!isfinite(val)) return;
            value = @(fmin(maximum.doubleValue, fmax(minimum.doubleValue, val)));
        }
        CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, Domain);
    }
    if (CFPreferencesAppSynchronize(Domain)) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), Reload, NULL, NULL, YES);
    }
}
@end
