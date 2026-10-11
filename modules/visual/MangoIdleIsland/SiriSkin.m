#import "SiriSkin.h"
#import <QuartzCore/QuartzCore.h>

// Stock layers only: no private API, no per-frame code (the render server runs
// the slow loops). Numbers are fractions of the pill width/height, tuned against
// the iOS 27 Siri reference.
static UIColor *C(int r, int g, int b, double a) { return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:a]; }

static CAGradientLayer *Gradient(CAGradientLayerType type, NSArray<UIColor *> *colors, NSArray<NSNumber *> *locations) {
    CAGradientLayer *layer = [CAGradientLayer layer];
    layer.type = type;
    NSMutableArray *cg = [NSMutableArray arrayWithCapacity:colors.count];
    for (UIColor *c in colors) [cg addObject:(__bridge id)c.CGColor];
    layer.colors = cg;
    layer.locations = locations;
    return layer;
}

// A radial gradient inscribed in its frame is an ellipse.
static CAGradientLayer *Ellipse(NSArray<UIColor *> *colors, NSArray<NSNumber *> *locations) {
    CAGradientLayer *layer = Gradient(kCAGradientLayerRadial, colors, locations);
    layer.startPoint = CGPointMake(.5, .5);
    layer.endPoint = CGPointMake(1, 1);
    return layer;
}

static CABasicAnimation *Loop(NSString *keyPath, double from, double to, CFTimeInterval duration) {
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:keyPath];
    a.fromValue = @(from); a.toValue = @(to); a.duration = duration;
    a.autoreverses = YES; a.repeatCount = HUGE_VALF; a.removedOnCompletion = NO;
    a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    return a;
}

@interface MSSiriSkinView : UIView
@end

@implementation MSSiriSkinView {
    CALayer *_clip, *_streak;
    CAGradientLayer *_dark, *_frost, *_halo, *_fringeTop, *_fringeBottom, *_core, *_line;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.isAccessibilityElement = NO;
    self.accessibilityElementsHidden = YES;
    self.layer.name = @"MangoSuiteSiriSkin";

    _clip = [CALayer layer];
    _clip.masksToBounds = YES;
    _clip.cornerCurve = kCACornerCurveContinuous;
    [self.layer addSublayer:_clip];

    // Black glass on top fading to clear by the lower third, then a faint frost at the bottom.
    _dark = Gradient(kCAGradientLayerAxial, @[C(0,0,0,.94), C(0,0,0,.80), C(0,0,0,.34), C(0,0,0,0), C(0,0,0,0)], @[@0, @.30, @.47, @.64, @1]);
    _frost = Gradient(kCAGradientLayerAxial, @[C(255,255,255,0), C(255,255,255,0), C(255,255,255,.10), C(255,255,255,.24)], @[@0, @.55, @.80, @1]);
    for (CAGradientLayer *g in @[_dark, _frost]) { g.startPoint = CGPointMake(.5, 0); g.endPoint = CGPointMake(.5, 1); [_clip addSublayer:g]; }

    // The lens-shaped light streak and its chromatic fringes; this group breathes.
    _streak = [CALayer layer];
    _halo = Ellipse(@[C(255,255,255,.55), C(205,205,255,.26), C(255,255,255,0)], @[@0, @.45, @1]);
    _fringeTop = Ellipse(@[C(255,150,200,.50), C(255,150,200,0)], @[@0, @1]);
    _fringeBottom = Ellipse(@[C(120,255,215,.45), C(120,255,215,0)], @[@0, @1]);
    _core = Ellipse(@[C(255,255,255,1), C(255,255,255,.9), C(255,255,255,0)], @[@0, @.35, @1]);
    _line = Gradient(kCAGradientLayerAxial, @[C(255,255,255,0), C(255,255,255,.106), C(255,255,255,.30), C(255,255,255,.106), C(255,255,255,0)], @[@0, @.25, @.5, @.75, @1]);
    _line.startPoint = CGPointMake(0, .5); _line.endPoint = CGPointMake(1, .5);
    for (CALayer *l in @[_halo, _fringeTop, _fringeBottom, _line, _core]) [_streak addSublayer:l];
    [_clip addSublayer:_streak];
    return self;
}

static void Place(CALayer *l, CGSize s, double x, double y, double w, double h) {
    l.bounds = CGRectMake(0, 0, w * s.width, h * s.height);
    l.position = CGPointMake((x + w / 2) * s.width, (y + h / 2) * s.height);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize s = self.bounds.size;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _clip.frame = self.bounds; _clip.cornerRadius = s.height / 2;
    for (CALayer *l in @[_dark, _frost, _streak]) Place(l, s, 0, 0, 1, 1);
    Place(_halo, s, .02, .16, .96, .62);
    Place(_fringeTop, s, .13, .205, .74, .36);
    Place(_fringeBottom, s, .15, .38, .70, .36);
    Place(_core, s, .21, .365, .58, .20);
    Place(_line, s, 0, .46, 1, .02);
    [CATransaction commit];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window || [_streak animationForKey:@"skin-breathe"] || UIAccessibilityIsReduceMotionEnabled()) return;
    CGFloat h = MAX(self.bounds.size.height, 1);
    [_streak addAnimation:Loop(@"transform.scale.x", .90, 1, 3.4) forKey:@"skin-breathe"];
    [_streak addAnimation:Loop(@"opacity", .80, 1, 3.4) forKey:@"skin-pulse"];
    [_streak addAnimation:Loop(@"transform.translation.y", -.03 * h, .03 * h, 4.6) forKey:@"skin-bob"];
}
@end

UIView *MSSiriSkinCreate(void) { return [MSSiriSkinView new]; }

void MSSiriSkinSync(UIView *skin, UIView *host, UIView *backing, CGFloat opacity) {
    // Settled geometry must stay quiet: host hooks re-run on every setter.
    NSArray<UIView *> *subs = host.subviews;
    NSUInteger i = [subs indexOfObject:backing];
    if (skin.superview != host || (i != NSNotFound && [subs indexOfObject:skin] != i + 1)) [host insertSubview:skin aboveSubview:backing];
    if (!CGRectEqualToRect(skin.frame, host.bounds)) skin.frame = host.bounds;
    if (skin.alpha != opacity) skin.alpha = opacity;
    if (skin.hidden) skin.hidden = NO;
}
