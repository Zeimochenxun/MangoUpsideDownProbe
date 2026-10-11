#import "IdleGlow.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>

static NSString * const MangoDomain = @"com.go.mangoosprefs";

typedef struct { BOOL rect; double opacity, spread; } GlowParams;

static double Number(id value, double fallback, double low, double high) {
    double n = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
    return isfinite(n) ? fmax(low, fmin(high, n)) : fallback;
}

// Mango's own settings (MangoOSPrefs): PillGlass.Glow.Style "0" circle (default) / "1" rect,
// .Opacity 0...1 (default 1), .Spread 0.5...2 (default 1). Read about once a second.
static GlowParams ReadParams(void) {
    static GlowParams cached = {NO, 1, 1};
    static CFTimeInterval last;
    CFTimeInterval now = CACurrentMediaTime();
    if (last && now - last < 1) return cached;
    last = now;
    CFStringRef domain = (__bridge CFStringRef)MangoDomain;
    CFPreferencesAppSynchronize(domain);
    id style = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("PillGlass.Glow.Style"), domain));
    id opacity = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("PillGlass.Glow.Opacity"), domain));
    id spread = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("PillGlass.Glow.Spread"), domain));
    cached.rect = [style respondsToSelector:@selector(integerValue)] && [style integerValue] == 1;
    cached.opacity = Number(opacity, 1, 0, 1);
    cached.spread = Number(spread, 1, .5, 2);
    return cached;
}

@interface MSIdleGlowView : UIView
- (void)refresh;
@end

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
    [self.layer addSublayer:_glow];
    return self;
}

- (void)refresh {
    GlowParams p = ReadParams();
    CGSize s = self.bounds.size;
    if (_hasApplied && p.rect == _applied.rect && p.opacity == _applied.opacity && p.spread == _applied.spread && CGSizeEqualToSize(s, _appliedSize)) return;
    _applied = p; _appliedSize = s; _hasApplied = YES;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    self.layer.cornerRadius = s.height / 2;
    _glow.frame = self.bounds;
    _glow.colors = @[(__bridge id)[UIColor colorWithWhite:0 alpha:p.opacity].CGColor, (__bridge id)[UIColor colorWithWhite:0 alpha:0].CGColor];
    _glow.locations = @[@0, @1];
    if (p.rect) {
        // Pure black at the top, feathering to clear; spread > 1 pushes the fade past the bottom edge.
        _glow.type = kCAGradientLayerAxial;
        _glow.startPoint = CGPointMake(.5, 0);
        _glow.endPoint = CGPointMake(.5, p.spread);
    } else {
        // Radial black ball on the sensor-hole position (mid-height), radius 1.2 pill heights x spread.
        _glow.type = kCAGradientLayerRadial;
        _glow.startPoint = CGPointMake(.5, .5);
        _glow.endPoint = CGPointMake(.5 + 1.2 * p.spread * s.height / MAX(s.width, 1), .5 + 1.2 * p.spread);
    }
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
