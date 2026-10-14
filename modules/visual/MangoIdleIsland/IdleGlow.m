#import "IdleGlow.h"
#import "IslandRepairs.h"
#import "../../../src/RuntimeSettings.h"
#import "../../../src/RuntimeDiagnostics.h"
#import <QuartzCore/QuartzCore.h>

static NSString * const MaskName = @"MangoSuiteIdleGlowMask";

typedef struct { double density, fade; BOOL shine, adaptive, frosted; } GlowParams;

// Suite settings (Settings > Mango Suite > Island, idle): black density 0...1 (default 1), the fraction
// of the pill height at which the black has faded out (0.3...1, default 0.55), IdleGlowShineEnabled for
// the lower-edge light and thin rim, IdleGlowAdaptiveEnabled for the light-background style and
// IdleGlowFrostedEnabled (default off) to force that style whatever the background is.
static GlowParams ReadParams(void) {
    return (GlowParams){ MSRuntimeNumber(@"IdleGlowDensity", 1, 0, 1), MSRuntimeNumber(@"IdleGlowFade", .55, .3, 1),
                         MSRuntimeFlag(@"IdleGlowShineEnabled"), MSRuntimeFlag(@"IdleGlowAdaptiveEnabled"), MSRuntimeFlag(@"IdleGlowFrostedEnabled") };
}

static id Black(double alpha) { return (__bridge id)[UIColor colorWithWhite:0 alpha:alpha].CGColor; }
static id White(double alpha) { return (__bridge id)[UIColor colorWithWhite:1 alpha:alpha].CGColor; }
static id Frost(double alpha) { return (__bridge id)[UIColor colorWithRed:150/255.0 green:156/255.0 blue:160/255.0 alpha:alpha].CGColor; }

static CAGradientLayer *Vertical(NSArray *colors, NSArray<NSNumber *> *locations) {
    CAGradientLayer *layer = [CAGradientLayer layer];
    layer.colors = colors;
    layer.locations = locations;
    layer.startPoint = CGPointMake(.5, 0);
    layer.endPoint = CGPointMake(.5, 1);
    return layer;
}

@interface MSIdleGlowView : UIView
- (void)refresh;
- (void)adaptToLuminance:(double)luminance;
@end

// Top-black glow on the idle pill: pure black at the top feathering to clear, plus one of two finishes.
// Clear (dark or colorful backgrounds): a soft light along the lower edge and a thin rim brighter at the
// bottom. Frosted (light backgrounds, where white light would vanish and the clear lower half would leave
// the pill open): a pale grey frost over the lower half and a full thin outline. The glass backing is faded
// the same way by MSIdleGlowSync, so the lower half is never a murky grey.
@implementation MSIdleGlowView {
    CAGradientLayer *_dark, *_shine, *_rim, *_frost;
    CAShapeLayer *_ring, *_outline;
    GlowParams _applied;
    CGSize _appliedSize;
    BOOL _hasApplied, _light, _styled;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.isAccessibilityElement = NO;
    self.accessibilityElementsHidden = YES;
    self.clipsToBounds = YES;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.name = @"MangoSuiteIdleGlow";
    _dark = Vertical(@[], @[]);
    _frost = Vertical(@[Frost(0), Frost(0), Frost(.22)], @[@0, @.3, @1]);
    _shine = Vertical(@[White(0), White(0), White(.16), White(.34)], @[@0, @.6, @.88, @1]);
    _rim = Vertical(@[White(.07), White(.15), White(.40)], @[@0, @.5, @1]);
    _ring = [CAShapeLayer layer];
    _ring.fillColor = nil;
    _ring.strokeColor = UIColor.whiteColor.CGColor;
    _ring.lineWidth = 1;
    _rim.mask = _ring;
    _outline = [CAShapeLayer layer];
    _outline.fillColor = nil;
    _outline.strokeColor = [UIColor colorWithWhite:0 alpha:.26].CGColor;
    _outline.lineWidth = .8;
    for (CALayer *l in @[_dark, _frost, _shine, _rim, _outline]) [self.layer addSublayer:l];
    return self;
}

- (void)applyStyleAnimated:(BOOL)animated {
    [CATransaction begin];
    if (animated) [CATransaction setAnimationDuration:.4]; else [CATransaction setDisableActions:YES];
    _shine.opacity = _rim.opacity = (_applied.shine && !_light) ? 1 : 0;
    _frost.opacity = _outline.opacity = _light ? 1 : 0;
    [CATransaction commit];
}

- (void)refresh {
    GlowParams p = ReadParams();
    CGSize s = self.bounds.size;
    if (_hasApplied && p.density == _applied.density && p.fade == _applied.fade && p.shine == _applied.shine && p.adaptive == _applied.adaptive && p.frosted == _applied.frosted && CGSizeEqualToSize(s, _appliedSize)) return;
    _applied = p; _appliedSize = s; _hasApplied = YES;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    CGRect b = self.bounds;
    self.layer.cornerRadius = s.height / 2;
    for (CALayer *l in @[_dark, _frost, _shine, _rim, _ring, _outline]) l.frame = b;
    _dark.colors = @[Black(p.density), Black(.55 * p.density), Black(0), Black(0)];
    _dark.locations = @[@0, @(.538 * p.fade), @(p.fade), @1];
    _ring.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(b, .5, .5) cornerRadius:MAX(s.height / 2 - .5, 0)].CGPath;
    _outline.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(b, .4, .4) cornerRadius:MAX(s.height / 2 - .4, 0)].CGPath;
    [CATransaction commit];
    [self applyStyleAnimated:NO];
}

// luminance < 0 means unknown: keep the current finish. Hysteresis keeps a mid-tone background from flickering.
- (void)adaptToLuminance:(double)luminance {
    BOOL light = _light;
    if (_applied.frosted) light = YES;
    else if (!_applied.adaptive) light = NO;
    else if (luminance > .66) light = YES;
    else if (luminance >= 0 && luminance < .55) light = NO;
    if (_styled && light == _light) return;
    BOOL first = !_styled;
    _styled = YES; _light = light;
    [self applyStyleAnimated:!first];
    MSDiagnosticsLog(@"Idle", [NSString stringWithFormat:@"[GLOW] finish=%@ luminance=%.2f adaptive=%d forced=%d", light ? @"frosted" : @"clear", luminance, _applied.adaptive, _applied.frosted]);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self refresh];
}
@end

UIView *MSIdleGlowCreate(void) { return [MSIdleGlowView new]; }

// Fade the glass backing toward clear at the bottom. Only ever installs or updates its own mask;
// a mask someone else put there is left alone.
static void MaskBacking(UIView *backing) {
    CALayer *mask = backing.layer.mask;
    if (!mask) {
        CAGradientLayer *g = Vertical(@[White(1), White(.55), White(.15), White(.10)], @[@0, @.4, @.8, @1]);
        g.name = MaskName;
        backing.layer.mask = g;
        mask = g;
    }
    if ([mask.name isEqualToString:MaskName] && !CGRectEqualToRect(mask.frame, backing.bounds)) mask.frame = backing.bounds;
}

void MSIdleGlowRelease(UIView *backing) {
    if ([backing.layer.mask.name isEqualToString:MaskName]) backing.layer.mask = nil;
}

void MSIdleGlowSync(UIView *glow, UIView *host, UIView *backing, CGFloat opacity) {
    // Settled geometry must stay quiet: host hooks re-run on every setter.
    NSArray<UIView *> *subs = host.subviews;
    NSUInteger i = [subs indexOfObject:backing];
    if (glow.superview != host || (i != NSNotFound && [subs indexOfObject:glow] != i + 1)) [host insertSubview:glow aboveSubview:backing];
    if (!CGRectEqualToRect(glow.frame, host.bounds)) glow.frame = host.bounds;
    if (glow.alpha != opacity) glow.alpha = opacity;
    if (glow.hidden) glow.hidden = NO;
    if ([glow isKindOfClass:MSIdleGlowView.class]) {
        MSIdleGlowView *view = (MSIdleGlowView *)glow;
        [view refresh];
        GlowParams p = ReadParams();
        [view adaptToLuminance:(p.adaptive && !p.frosted) ? MSIslandBackgroundLuminance(host, backing) : -1];
    }
    MaskBacking(backing);
}
