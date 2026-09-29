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

@interface MangoIslandAdaptiveColorPrefsController : PSListController
- (id)readValue:(PSSpecifier *)specifier;
- (void)writeValue:(id)value specifier:(PSSpecifier *)specifier;
@end

static id CopyValue(NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, MangoDomain));
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
              footer:@"已移除预览与所有自定义 Settings Cell。当前页面只使用系统原生 Preferences 控件。默认值严格对应 MangoIslandAdaptiveColor 0.1.2。参数通过 Island marker 实时传给 MangoOSRendering；每项内部量化为 8 个稳定档位，以换取无需重编译 shader 的实时调节。"
             sliders:@[
        [self slider:@"总自适应强度" key:AdaptationKey min:0.0 max:1.0]
    ]];

    [self addSection:@"亮度响应区间"
              footer:@"响应起点决定从多暗的背景开始发生明显变化；响应终点决定到多亮时完成过渡。0.1.2 默认：起点 0.08，终点 0.42。若终点低于起点，渲染器会自动保留最小过渡区间以避免异常。"
             sliders:@[
        [self slider:@"响应起点" key:LumaStartKey min:0.0 max:0.42],
        [self slider:@"响应终点" key:LumaEndKey min:0.18 max:0.92]
    ]];

    [self addSection:@"目标亮度"
              footer:@"暗背景目标亮度越高，灵动岛在暗背景上越偏亮；亮背景目标亮度越低，灵动岛在亮背景上越偏黑。0.1.2 默认：暗背景 0.80，亮背景 0.025。"
             sliders:@[
        [self slider:@"暗背景目标亮度" key:DarkTargetKey min:0.20 max:1.0],
        [self slider:@"亮背景目标亮度" key:BrightTargetKey min:0.0 max:0.36]
    ]];

    [self addSection:@"混合强度"
              footer:@"分别控制暗背景端与亮背景端向目标亮度靠拢的程度。总自适应强度会再乘在这两个值之上。0.1.2 默认：暗区 0.16，亮区 0.42。"
             sliders:@[
        [self slider:@"暗区混合强度" key:DarkOpacityKey min:0.0 max:0.80],
        [self slider:@"亮区混合强度" key:BrightOpacityKey min:0.0 max:0.85]
    ]];

    return _specifiers;
}

static NSNumber *DefaultValueForKey(NSString *key) {
    if ([key isEqualToString:AdaptationKey]) return @1.0;
    if ([key isEqualToString:LumaStartKey]) return @0.08;
    if ([key isEqualToString:LumaEndKey]) return @0.42;
    if ([key isEqualToString:DarkTargetKey]) return @0.80;
    if ([key isEqualToString:BrightTargetKey]) return @0.025;
    if ([key isEqualToString:DarkOpacityKey]) return @0.16;
    if ([key isEqualToString:BrightOpacityKey]) return @0.42;
    return nil;
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

@end
