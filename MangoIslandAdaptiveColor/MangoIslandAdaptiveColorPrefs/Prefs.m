#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>

static CFStringRef const MangoDomain = CFSTR("com.go.mangoosprefs");
static CFStringRef const AdaptationKey = CFSTR("MangoIslandAdaptiveColor.Adaptation");
static CFStringRef const RenderReload = CFSTR("com.go.mangoosprefs/Reload");
static NSString * const PreviewNotification = @"MangoIslandAdaptiveColorPreviewChanged";
static dispatch_block_t PendingReload;

static double Clamp01(double value) {
    if (!isfinite(value)) return 1.0;
    return fmin(1.0, fmax(0.0, value));
}

static double CurrentStrength(void) {
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(AdaptationKey, MangoDomain));
    if (![value isKindOfClass:NSNumber.class]) return 1.0;
    return Clamp01([value doubleValue]);
}

static double SmoothStep(double edge0, double edge1, double x) {
    double t = Clamp01((x - edge0) / (edge1 - edge0));
    return t * t * (3.0 - 2.0 * t);
}

// CPU mirror of the exact 0.1.2 grayscale response used by the Metal patch.
// This is intentionally kept line-for-line equivalent in constants/order.
static double PreviewOutput(double luminance, double adaptation) {
    double bright = SmoothStep(0.08, 0.42, luminance);
    double target = 0.80 + (0.025 - 0.80) * bright;
    double opacity = 0.16 + (0.42 - 0.16) * bright;
    double adaptive = luminance + (target - luminance) * opacity;
    return luminance + (adaptive - luminance) * Clamp01(adaptation);
}

static void ScheduleRenderReload(void) {
    if (PendingReload) dispatch_block_cancel(PendingReload);
    PendingReload = dispatch_block_create(0, ^{
        CFPreferencesAppSynchronize(MangoDomain);
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             RenderReload, NULL, NULL, YES);
        PendingReload = nil;
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 140 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), PendingReload);
}

@interface MIAAdaptivePreviewView : UIView
@property (nonatomic) CGFloat adaptation;
@end

@implementation MIAAdaptivePreviewView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _adaptation = CurrentStrength();
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(previewChanged:)
                                                     name:PreviewNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)previewChanged:(NSNotification *)note {
    NSNumber *value = [note.object isKindOfClass:NSNumber.class] ? note.object : nil;
    if (!value) return;
    self.adaptation = Clamp01(value.doubleValue);
    [self setNeedsDisplay];
}

- (void)setAdaptation:(CGFloat)adaptation {
    _adaptation = Clamp01(adaptation);
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGRect bounds = CGRectInset(self.bounds, 12.0, 8.0);
    UIBezierPath *card = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:16.0];
    [UIColor.secondarySystemBackgroundColor setFill];
    [card fill];

    NSDictionary *titleAttrs = @{
        NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: UIColor.labelColor
    };
    NSString *title = [NSString stringWithFormat:@"自适应颜色预览   %.0f%%", self.adaptation * 100.0];
    [title drawAtPoint:CGPointMake(CGRectGetMinX(bounds) + 14.0, CGRectGetMinY(bounds) + 12.0)
        withAttributes:titleAttrs];

    CGRect stage = CGRectMake(CGRectGetMinX(bounds) + 14.0,
                              CGRectGetMinY(bounds) + 40.0,
                              CGRectGetWidth(bounds) - 28.0,
                              76.0);
    UIBezierPath *stagePath = [UIBezierPath bezierPathWithRoundedRect:stage cornerRadius:13.0];
    [stagePath addClip];

    const NSInteger steps = 160;
    CGFloat stepWidth = CGRectGetWidth(stage) / (CGFloat)steps + 0.6;
    for (NSInteger i = 0; i < steps; i++) {
        double t = (double)i / (double)(steps - 1);
        double l = 0.04 + 0.88 * t;
        [[UIColor colorWithWhite:l alpha:1.0] setFill];
        UIRectFill(CGRectMake(CGRectGetMinX(stage) + i * CGRectGetWidth(stage) / steps,
                              CGRectGetMinY(stage), stepWidth, CGRectGetHeight(stage)));
    }

    CGContextSaveGState(ctx);
    CGRect pill = CGRectMake(CGRectGetMinX(stage) + 22.0,
                             CGRectGetMidY(stage) - 19.0,
                             CGRectGetWidth(stage) - 44.0,
                             38.0);
    UIBezierPath *pillPath = [UIBezierPath bezierPathWithRoundedRect:pill cornerRadius:19.0];
    [pillPath addClip];
    for (NSInteger i = 0; i < steps; i++) {
        double t = (double)i / (double)(steps - 1);
        double l = 0.04 + 0.88 * t;
        double out = PreviewOutput(l, self.adaptation);
        [[UIColor colorWithWhite:Clamp01(out) alpha:1.0] setFill];
        UIRectFill(CGRectMake(CGRectGetMinX(stage) + i * CGRectGetWidth(stage) / steps,
                              CGRectGetMinY(pill), stepWidth, CGRectGetHeight(pill)));
    }
    CGContextRestoreGState(ctx);

    [[UIColor colorWithWhite:1.0 alpha:0.24] setStroke];
    pillPath.lineWidth = 1.0;
    [pillPath stroke];

    // Simple white active-content glyphs make contrast changes easier to judge.
    [[UIColor colorWithWhite:1.0 alpha:0.92] setFill];
    UIBezierPath *dot = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(CGRectGetMinX(pill) + 14.0,
                                                                          CGRectGetMidY(pill) - 4.0,
                                                                          8.0, 8.0)];
    [dot fill];
    UIBezierPath *line = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(CGRectGetMinX(pill) + 29.0,
                                                                             CGRectGetMidY(pill) - 2.0,
                                                                             42.0, 4.0)
                                                        cornerRadius:2.0];
    [line fill];

    NSDictionary *captionAttrs = @{
        NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightRegular],
        NSForegroundColorAttributeName: UIColor.secondaryLabelColor
    };
    NSString *caption = @"暗背景  ←  背景亮度  →  亮背景    ·    100% = 0.1.2 基线";
    [caption drawAtPoint:CGPointMake(CGRectGetMinX(bounds) + 14.0, CGRectGetMaxY(stage) + 10.0)
          withAttributes:captionAttrs];
}

@end

@interface MIAAdaptivePreviewCell : PSTableCell
@property (nonatomic, strong) MIAAdaptivePreviewView *previewView;
@end

@implementation MIAAdaptivePreviewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = UIColor.clearColor;
        _previewView = [[MIAAdaptivePreviewView alloc] initWithFrame:CGRectZero];
        [self.contentView addSubview:_previewView];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.previewView.frame = self.contentView.bounds;
}

@end

@interface MangoIslandAdaptiveColorPrefsController : PSListController
- (id)readValue:(PSSpecifier *)specifier;
- (void)writeValue:(id)value specifier:(PSSpecifier *)specifier;
@end

@implementation MangoIslandAdaptiveColorPrefsController

- (NSMutableArray *)specifiers {
    if (_specifiers) return _specifiers;
    _specifiers = [NSMutableArray new];

    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"颜色自适应 · 0.1.2 基线"];
    [group setProperty:@"滑块只改变 0.1.2 自适应颜色的贡献量。100% 完整保留 0.1.2 的亮度曲线、目标色和 16%–42% 混合；0% 不施加自适应色。下方预览使用与 Metal shader 相同的公式实时计算，仅模拟颜色响应，不模拟 Mango 的模糊、折射和边缘光。" forKey:@"footerText"];
    [_specifiers addObject:group];

    PSSpecifier *slider = [PSSpecifier preferenceSpecifierNamed:@"颜色自适应强度"
                                                          target:self
                                                             set:@selector(writeValue:specifier:)
                                                             get:@selector(readValue:)
                                                          detail:nil
                                                            cell:PSSliderCell
                                                            edit:nil];
    [slider setProperty:(__bridge NSString *)AdaptationKey forKey:@"key"];
    [slider setProperty:@0.0 forKey:@"min"];
    [slider setProperty:@1.0 forKey:@"max"];
    [slider setProperty:@1.0 forKey:@"default"];
    [slider setProperty:@YES forKey:@"showValue"];
    [slider setProperty:@YES forKey:@"isContinuous"];
    [_specifiers addObject:slider];

    PSSpecifier *preview = [PSSpecifier preferenceSpecifierNamed:@""
                                                           target:nil
                                                              set:nil
                                                              get:nil
                                                           detail:nil
                                                             cell:PSStaticTextCell
                                                             edit:nil];
    [preview setProperty:MIAAdaptivePreviewCell.class forKey:@"cellClass"];
    [preview setProperty:@156 forKey:@"height"];
    [_specifiers addObject:preview];

    return _specifiers;
}

- (id)readValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (![key isEqualToString:(__bridge NSString *)AdaptationKey]) return nil;
    return @(CurrentStrength());
}

- (void)writeValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (![key isEqualToString:(__bridge NSString *)AdaptationKey] || ![value isKindOfClass:NSNumber.class]) return;
    double amount = Clamp01([value doubleValue]);
    NSNumber *stored = @(amount);
    CFPreferencesSetAppValue(AdaptationKey, (__bridge CFPropertyListRef)stored, MangoDomain);
    CFPreferencesAppSynchronize(MangoDomain);

    // Preview follows the finger immediately. The renderer reload is coalesced
    // so continuous slider motion does not flood backboardd with reloads.
    [[NSNotificationCenter defaultCenter] postNotificationName:PreviewNotification object:stored];
    ScheduleRenderReload();
}

@end
