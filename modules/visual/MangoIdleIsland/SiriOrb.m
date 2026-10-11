#import "SiriOrb.h"
#import <QuartzCore/QuartzCore.h>

// Stock layers only: no private API, no per-frame code (the render server runs
// the two slow loops). Numbers are unit fractions of the orb diameter, tuned
// against the reference screenshot.
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

@interface MSSiriOrbView : UIView
@end

@implementation MSSiriOrbView {
    CALayer *_clip, *_streak;
    CAGradientLayer *_body, *_glow, *_halo, *_fringeTop, *_fringeBottom, *_core, *_line, *_rim;
    CAShapeLayer *_ring;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.isAccessibilityElement = NO;
    self.accessibilityElementsHidden = YES;
    self.layer.name = @"MangoSuiteSiriOrb";
    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = .30; self.layer.shadowRadius = 4; self.layer.shadowOffset = CGSizeMake(0, 1.5);

    _clip = [CALayer layer]; _clip.masksToBounds = YES;
    [self.layer addSublayer:_clip];

    // Dark glass above, frosted light below.
    _body = Gradient(kCAGradientLayerAxial, @[C(13,13,15,1), C(18,18,20,1), C(51,54,59,.96), C(128,131,142,.92)], @[@0, @.46, @.60, @1]);
    _body.startPoint = CGPointMake(.5, 0); _body.endPoint = CGPointMake(.5, 1);
    _glow = Gradient(kCAGradientLayerRadial, @[C(255,255,255,.30), C(255,255,255,0)], @[@0, @1]);
    _glow.startPoint = CGPointMake(.5, 1.05); _glow.endPoint = CGPointMake(1.05, .35);
    [_clip addSublayer:_body]; [_clip addSublayer:_glow];

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

    // Thin glass edge, brighter along the bottom.
    _rim = Gradient(kCAGradientLayerAxial, @[C(255,255,255,.10), C(255,255,255,.20), C(255,255,255,.55)], @[@0, @.5, @1]);
    _rim.startPoint = CGPointMake(.5, 0); _rim.endPoint = CGPointMake(.5, 1);
    _ring = [CAShapeLayer layer]; _ring.fillColor = nil; _ring.strokeColor = UIColor.whiteColor.CGColor;
    _rim.mask = _ring;
    [_clip addSublayer:_rim];
    return self;
}

static void Place(CALayer *l, CGFloat d, double x, double y, double w, double h) {
    l.bounds = CGRectMake(0, 0, w * d, h * d);
    l.position = CGPointMake((x + w / 2) * d, (y + h / 2) * d);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat d = MIN(self.bounds.size.width, self.bounds.size.height);
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    CGRect b = CGRectMake(0, 0, d, d);
    self.layer.shadowPath = [UIBezierPath bezierPathWithOvalInRect:b].CGPath;
    _clip.frame = b; _clip.cornerRadius = d / 2;
    for (CALayer *l in @[_body, _glow, _streak, _rim]) Place(l, d, 0, 0, 1, 1);
    Place(_halo, d, 0, .32, 1, .30);
    Place(_fringeTop, d, .10, .36, .80, .13);
    Place(_fringeBottom, d, .125, .455, .75, .13);
    Place(_core, d, .14, .419, .72, .092);
    Place(_line, d, 0, .466, 1, .008);
    CGFloat w = .013 * d;
    _ring.frame = b; _ring.lineWidth = w;
    _ring.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(b, w / 2, w / 2)].CGPath;
    [CATransaction commit];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window || [_streak animationForKey:@"orb-breathe"] || UIAccessibilityIsReduceMotionEnabled()) return;
    CGFloat d = MAX(self.bounds.size.width, 1);
    [_streak addAnimation:Loop(@"transform.scale.x", .88, 1, 3.4) forKey:@"orb-breathe"];
    [_streak addAnimation:Loop(@"opacity", .80, 1, 3.4) forKey:@"orb-pulse"];
    [_streak addAnimation:Loop(@"transform.translation.y", -.014 * d, .014 * d, 4.6) forKey:@"orb-bob"];
}
@end

UIView *MSSiriOrbCreate(void) { return [MSSiriOrbView new]; }

void MSSiriOrbSync(UIView *orb, UIView *host, CGFloat opacity) {
    if (orb.superview != host) [host insertSubview:orb atIndex:0];
    // Settled geometry must stay quiet: host hooks re-run on every setter.
    CGRect b = host.bounds;
    CGFloat d = MIN(b.size.width, b.size.height);
    CGRect frame = CGRectMake(CGRectGetMidX(b) - d / 2, CGRectGetMidY(b) - d / 2, d, d);
    if (!CGRectEqualToRect(orb.frame, frame)) orb.frame = frame;
    if (orb.alpha != opacity) orb.alpha = opacity;
    if (orb.hidden) orb.hidden = NO;
}
