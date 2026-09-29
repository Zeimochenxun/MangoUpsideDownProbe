#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>

static CFStringRef const MangoDomain = CFSTR("com.go.mangoosprefs");
static CFStringRef const RenderReload = CFSTR("com.go.mangoosprefs/Reload");
static NSString * const AdaptationKey = @"MangoIslandAdaptiveColor.Adaptation";
static NSString * const LumaStartKey = @"MangoIslandAdaptiveColor.LumaStart";
static NSString * const LumaEndKey = @"MangoIslandAdaptiveColor.LumaEnd";
static NSString * const DarkTargetKey = @"MangoIslandAdaptiveColor.DarkTarget";
static NSString * const BrightTargetKey = @"MangoIslandAdaptiveColor.BrightTarget";
static NSString * const DarkOpacityKey = @"MangoIslandAdaptiveColor.DarkOpacity";
static NSString * const BrightOpacityKey = @"MangoIslandAdaptiveColor.BrightOpacity";
static dispatch_block_t PendingReload;

static const double DefaultMaster = 0.90;
static const double DefaultLumaStart = 0.08;
static const double DefaultLumaEnd = 0.52;
static const double DefaultDarkTarget = 0.80;
static const double DefaultBrightTarget = 0.08;
static const double DefaultDarkOpacity = 0.16;
static const double DefaultBrightOpacity = 0.20;

@interface MangoIslandAdaptiveColorPrefsController : PSListController
- (id)readValue:(PSSpecifier *)specifier;
- (void)writeValue:(id)value specifier:(PSSpecifier *)specifier;
- (void)resetDefaults:(PSSpecifier *)specifier;
@end

static id CopyValue(NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, MangoDomain));
}

static NSNumber *DefaultValueForKey(NSString *key) {
    if ([key isEqualToString:AdaptationKey]) return @(DefaultMaster);
    if ([key isEqualToString:LumaStartKey]) return @(DefaultLumaStart);
    if ([key isEqualToString:LumaEndKey]) return @(DefaultLumaEnd);
    if ([key isEqualToString:DarkTargetKey]) return @(DefaultDarkTarget);
    if ([key isEqualToString:BrightTargetKey]) return @(DefaultBrightTarget);
    if ([key isEqualToString:DarkOpacityKey]) return @(DefaultDarkOpacity);
    if ([key isEqualToString:BrightOpacityKey]) return @(DefaultBrightOpacity);
    return nil;
}

static NSArray<NSString *> *AllKeys(void) {
    return @[AdaptationKey, LumaStartKey, LumaEndKey, DarkTargetKey,
             BrightTargetKey, DarkOpacityKey, BrightOpacityKey];
}

static void ScheduleRenderReload(void) {
    if (PendingReload) dispatch_block_cancel(PendingReload);
    PendingReload = dispatch_block_create(0, ^{
        CFPreferencesAppSynchronize(MangoDomain);
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             RenderReload,
                                             NULL,
                                             NULL,
                                             YES);
        PendingReload = nil;
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 140 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), PendingReload);
}

@implementation MangoIslandAdaptiveColorPrefsController

- (PSSpecifier *)slider:(NSString *)name
                    key:(NSString *)key
                    min:(double)minimum
                    max:(double)maximum {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:name
                                                        target:self
                                                           set:@selector(writeValue:specifier:)
                                                           get:@selector(readValue:)
                                                        detail:nil
                                                          cell:PSSliderCell
                                                          edit:nil];
    [item setProperty:key forKey:@"key"];
    [item setProperty:@(minimum) forKey:@"min"];
    [item setProperty:@(maximum) forKey:@"max"];
    [item setProperty:@YES forKey:@"showValue"];
    [item setProperty:@YES forKey:@"isContinuous"];
    return item;
}

- (void)addSection:(NSString *)title
            footer:(NSString *)footer
           sliders:(NSArray<PSSpecifier *> *)sliders {
    PSSpecifier *group = title.length ? [PSSpecifier groupSpecifierWithName:title] : [PSSpecifier emptyGroupSpecifier];
    if (footer.length) [group setProperty:footer forKey:@"footerText"];
    [_specifiers addObject:group];
    [_specifiers addObjectsFromArray:sliders];
}

- (NSMutableArray *)specifiers {
    if (_specifiers) return _specifiers;
    _specifiers = [NSMutableArray new];

    [self addSection:@"灵动岛颜色自适应"
              footer:@"0.1.3 仅对通过 Island marker 校验的 go.mangoos.island 渲染生效。高亮背景会自动进入 Highlight Glass：减少灰膜感、保留更多背景颜色与细节，并增强亮背景下的边缘对比和色散可见度。页面不包含任何自定义预览 Cell。"
             sliders:@[
        [self slider:@"总自适应强度" key:AdaptationKey min:0.0 max:1.0]
    ]];

    [self addSection:@"亮度响应区间"
              footer:@"响应起点决定从多暗开始变化；响应终点决定普通亮度响应何时完成。新的默认终点提高到 0.52，让普通背景到高亮背景之间过渡更柔和。"
             sliders:@[
        [self slider:@"响应起点" key:LumaStartKey min:0.0 max:0.42],
        [self slider:@"响应终点" key:LumaEndKey min:0.18 max:0.92]
    ]];

    [self addSection:@"目标亮度"
              footer:@"暗背景目标亮度越高，暗处越偏亮；亮背景目标亮度越低，亮处越偏暗。高亮模式会优先以保留色彩比例的方式压低亮度，不再简单把整块玻璃混成灰色。"
             sliders:@[
        [self slider:@"暗背景目标亮度" key:DarkTargetKey min:0.20 max:1.0],
        [self slider:@"亮背景目标亮度" key:BrightTargetKey min:0.0 max:0.36]
    ]];

    [self addSection:@"混合强度"
              footer:@"暗区和亮区分别控制向目标亮度靠拢的程度。新的亮区默认从 0.42 降到 0.20，优先保留玻璃下方的真实背景细节；高亮背景还会自动进一步降低灰色覆盖，并增强边缘暗轮廓与色散。"
             sliders:@[
        [self slider:@"暗区混合强度" key:DarkOpacityKey min:0.0 max:0.80],
        [self slider:@"亮区混合强度" key:BrightOpacityKey min:0.0 max:0.85]
    ]];

    PSSpecifier *resetGroup = [PSSpecifier groupSpecifierWithName:@"恢复"];
    [resetGroup setProperty:@"恢复为 0.1.3 推荐参数：总强度 0.90、响应 0.08→0.52、目标亮度 0.80→0.08、混合强度 0.16→0.20。" forKey:@"footerText"];
    [_specifiers addObject:resetGroup];

    PSSpecifier *reset = [PSSpecifier preferenceSpecifierNamed:@"恢复默认参数"
                                                         target:self
                                                            set:nil
                                                            get:nil
                                                         detail:nil
                                                           cell:PSButtonCell
                                                           edit:nil];
    [reset setButtonAction:@selector(resetDefaults:)];
    [_specifiers addObject:reset];

    return _specifiers;
}

- (id)readValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return nil;
    id actual = CopyValue(key);
    if ([actual isKindOfClass:NSNumber.class] && isfinite([actual doubleValue])) return actual;
    return DefaultValueForKey(key);
}

- (void)writeValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length || ![value isKindOfClass:NSNumber.class]) return;

    double numeric = [value doubleValue];
    if (!isfinite(numeric)) return;
    NSNumber *minimum = [specifier propertyForKey:@"min"];
    NSNumber *maximum = [specifier propertyForKey:@"max"];
    if (minimum) numeric = fmax(minimum.doubleValue, numeric);
    if (maximum) numeric = fmin(maximum.doubleValue, numeric);

    NSNumber *stored = @(numeric);
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)stored,
                             MangoDomain);
    ScheduleRenderReload();
}

- (void)resetDefaults:(PSSpecifier *)specifier {
    (void)specifier;
    for (NSString *key in AllKeys()) {
        NSNumber *value = DefaultValueForKey(key);
        if (!value) continue;
        CFPreferencesSetAppValue((__bridge CFStringRef)key,
                                 (__bridge CFPropertyListRef)value,
                                 MangoDomain);
    }
    CFPreferencesAppSynchronize(MangoDomain);
    [self reloadSpecifiers];
    ScheduleRenderReload();
}

@end
