#import "IdleGlow.h"
#import "../../../src/RuntimeSettings.h"
#import <QuartzCore/QuartzCore.h>

static NSString * const MaskName = @"MangoSuiteIdleGlowMask";

typedef struct { double density, fade; } GlowParams;

// Suite settings (Settings > Mango Suite > Island appearance): black density 0...1 (default 1) and the
// fraction of the pill height at which the black has faded out (0.3...1, default 0.55 = a little
// higher than the first preview's 0.65).
static GlowParams ReadParams(void) {
    return (GlowParams){ MSRuntimeNumber(@"IdleGlowDensity", 1, 0, 1), MSRuntimeNumber(@"IdleGlowFade", .55, .3, 1) };
}

static id Black(double alpha) { return (__bridge id)[UIColor colorWithWhite:0 alpha:alpha].CGColor; }
static id White(double alpha) { return (__bridge id)[UIColor colorWithWhite:1 alpha:alpha].CGColor; }

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
@end

// Straight top-black glow on the idle pill: pure black at the top feathering to clear, a soft light along
// the lower edge and a thin glass rim that is brighter at the bottom. The glass backing is faded the same
// way by MSIdleGlowSync, so the lower half is really clear instead of a murky grey.
@implementation MSIdleGlowView {
    CAGradientLayer *_dark, *_shine, *_rim;
    CAShapeLayer *_ring;
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
    _dark = Vertical(@[], @[]);
    _shine = Vertical(@[White(0), White(0), White(.16), White(.34)], @[@0, @.6, @.88, @1]);
    _rim = Vertical(@[White(.07), White(.15), White(.40)], @[@0, @.5, @1]);
    _ring = [CAShapeLayer layer];
    _ring.fillColor = nil;
    _ring.strokeColor = UIColor.whiteColor.CGColor;
    _ring.lineWidth = 1;
    _rim.mask = _ring;
    for (CALayer *l in @[_dark, _shine, _rim]) [self.layer addSublayer:l];
    return self;
}

- (void)refresh {
    GlowParams p = ReadParams();
    CGSize s = self.bounds.size;
    if (_hasApplied && p.density == _applied.density && p.fade == _applied.fade && CGSizeEqualToSize(s, _appliedSize)) return;
    _applied = p; _appliedSize = s; _hasApplied = YES;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    CGRect b = self.bounds;
    self.layer.cornerRadius = s.height / 2;
    for (CALayer *l in @[_dark, _shine, _rim, _ring]) l.frame = b;
    _dark.colors = @[Black(p.density), Black(.55 * p.density), Black(0), Black(0)];
    _dark.locations = @[@0, @(.538 * p.fade), @(p.fade), @1];
    _ring.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(b, .5, .5) cornerRadius:MAX(s.height / 2 - .5, 0)].CGPath;
    [CATransaction commit];
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
    if ([glow isKindOfClass:MSIdleGlowView.class]) [(MSIdleGlowView *)glow refresh];
    MaskBacking(backing);
}
