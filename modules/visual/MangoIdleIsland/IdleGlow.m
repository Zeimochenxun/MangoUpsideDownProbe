#import "IdleGlow.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>

static NSString * const MangoDomain = @"com.go.mangoosprefs";

typedef struct { double opacity, spread; } GlowParams;

static double Number(id value, double fallback, double low, double high) {
    double n = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
    return isfinite(n) ? fmax(low, fmin(high, n)) : fallback;
}

// Mango's own settings (Island Liquid Glass > Glow Opacity / Glow Spread): PillGlass.Glow.Opacity
// 0...1 and .Spread (Mango clamps to 0.3...3), both default 1. Read about once a second.
static GlowParams ReadParams(void) {
    static GlowParams cached = {1, 1};
    static CFTimeInterval last;
    CFTimeInterval now = CACurrentMediaTime();
    if (last && now - last < 1) return cached;
    last = now;
    CFStringRef domain = (__bridge CFStringRef)MangoDomain;
    CFPreferencesAppSynchronize(domain);
    id opacity = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("PillGlass.Glow.Opacity"), domain));
    id spread = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("PillGlass.Glow.Spread"), domain));
    cached.opacity = Number(opacity, 1, 0, 1);
    cached.spread = Number(spread, 1, .3, 3);
    return cached;
}

@interface MSIdleGlowView : UIView
- (void)refresh;
@end

// Mango's circle black glow, copied from the Beta7 island layout pass (mangoos.dylib): one radial
// CAGradientLayer, black at alpha 1 / 1 / .55 / 0 at 0 / .42 / .78 / 1, from (.5,.3) to (1,1),
// framed 1.2 W x 0.7 H (both times spread), centred, with its top 0.12 H above the island.
// Mango shows it only when the island is taller than 90pt; the idle pill is shown here on purpose.
@implementation MSIdleGlowView {
    CAGradientLayer *_glow;
    GlowParams _applied;
    CGSize _appliedSize;
    BOOL _hasApplied;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.isAccessibilityElement = NO;
    self.accessibilityElementsHidden = YES;
    self.clipsToBounds = YES;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.name = @"MangoSuiteIdleGlow";
    _glow = [CAGradientLayer layer];
    _glow.type = kCAGradientLayerRadial;
    _glow.colors = @[(__bridge id)[UIColor colorWithWhite:0 alpha:1].CGColor,
                     (__bridge id)[UIColor colorWithWhite:0 alpha:1].CGColor,
                     (__bridge id)[UIColor colorWithWhite:0 alpha:.55].CGColor,
                     (__bridge id)[UIColor colorWithWhite:0 alpha:0].CGColor];
    _glow.locations = @[@0, @.42, @.78, @1];
    _glow.startPoint = CGPointMake(.5, .3);
    _glow.endPoint = CGPointMake(1, 1);
    [self.layer addSublayer:_glow];
    return self;
}

- (void)refresh {
    GlowParams p = ReadParams();
    CGSize s = self.bounds.size;
    if (_hasApplied && p.opacity == _applied.opacity && p.spread == _applied.spread && CGSizeEqualToSize(s, _appliedSize)) return;
    _applied = p; _appliedSize = s; _hasApplied = YES;
    double w = 1.2 * s.width * p.spread, h = .7 * s.height * p.spread;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    self.layer.cornerRadius = s.height / 2;
    _glow.frame = CGRectMake((s.width - w) / 2, -.12 * s.height, w, h);
    _glow.opacity = (float)p.opacity;
    [CATransaction commit];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self refresh];
}
@end

UIView *MSIdleGlowCreate(void) { return [MSIdleGlowView new]; }

void MSIdleGlowSync(UIView *glow, UIView *host, UIView *backing, CGFloat opacity) {
    // Settled geometry must stay quiet: host hooks re-run on every setter.
    NSArray<UIView *> *subs = host.subviews;
    NSUInteger i = [subs indexOfObject:backing];
    if (glow.superview != host || (i != NSNotFound && [subs indexOfObject:glow] != i + 1)) [host insertSubview:glow aboveSubview:backing];
    if (!CGRectEqualToRect(glow.frame, host.bounds)) glow.frame = host.bounds;
    if (glow.alpha != opacity) glow.alpha = opacity;
    if (glow.hidden) glow.hidden = NO;
    if ([glow isKindOfClass:MSIdleGlowView.class]) [(MSIdleGlowView *)glow refresh];
}
