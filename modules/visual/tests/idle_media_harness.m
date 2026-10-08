// Runner inserts production Eligibility, Update, Layout and helpers.
// Property stubs verify decisions and setter use, not UIKit/device rendering.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#include <math.h>
#include <stdio.h>
static int Failures;
#undef assert
#define assert(condition) do { if (!(condition)) { Failures++; fprintf(stderr, "line %d: %s\n", __LINE__, #condition); } } while (0)

@interface CALayer : NSObject
@property (nonatomic) CGFloat cornerRadius;
@property (nonatomic) CGFloat opacity;
@property (nonatomic) BOOL hidden;
@property (nonatomic) CGRect bounds;
@property (nonatomic, retain) CALayer *presentationLayer;
@end
@implementation CALayer @end
@interface CATransaction : NSObject
+ (void)begin;
+ (void)setDisableActions:(BOOL)value;
+ (void)commit;
@end
@implementation CATransaction
+ (void)begin {}
+ (void)setDisableActions:(BOOL)value { (void)value; }
+ (void)commit {}
@end
@class UIWindow;
@interface UIView : NSObject
@property (nonatomic) CGFloat alpha;
@property (nonatomic) BOOL hidden;
@property (nonatomic) BOOL userInteractionEnabled;
@property (nonatomic) CGRect frame;
@property (nonatomic) CGRect bounds;
@property (nonatomic, retain) CALayer *layer;
@property (nonatomic, assign) UIWindow *window;
@property (nonatomic, assign) UIView *superview;
@property (nonatomic, retain) NSMutableArray<UIView *> *subviews;
@property (nonatomic) NSUInteger frameWrites;
@property (nonatomic) NSUInteger alphaWrites;
@property (nonatomic) NSUInteger hiddenWrites;
@property (nonatomic) NSUInteger insertions;
@property (nonatomic) NSUInteger removals;
- (void)insertSubview:(UIView *)view atIndex:(NSUInteger)index;
- (void)removeFromSuperview;
- (void)layoutSubviews;
+ (void)performWithoutAnimation:(void (^)(void))actions;
@end
@implementation UIView
@synthesize frame = _frame, alpha = _alpha, hidden = _hidden;
- (void)setFrame:(CGRect)frame { _frame = frame; self.frameWrites++; }
- (void)setAlpha:(CGFloat)alpha { _alpha = alpha; self.layer.opacity = alpha; self.alphaWrites++; }
- (void)setHidden:(BOOL)hidden { _hidden = hidden; self.hiddenWrites++; }
- (void)insertSubview:(UIView *)view atIndex:(NSUInteger)index {
    self.insertions++;
    [view removeFromSuperview];
    [self.subviews insertObject:view atIndex:index];
    view.superview = self;
    view.window = self.window;
}
- (void)removeFromSuperview {
    if (!self.superview) return;
    self.removals++;
    [self.superview.subviews removeObject:self];
    self.superview = nil;
    self.window = nil;
}
- (void)layoutSubviews {}
+ (void)performWithoutAnimation:(void (^)(void))actions { actions(); }
@end
@interface UIWindow : UIView @end
@implementation UIWindow @end
@interface MRUActivityNowPlayingView : UIView @end
@implementation MRUActivityNowPlayingView @end
@interface MRUSessionNowPlayingView : UIView @end
@implementation MRUSessionNowPlayingView @end
@interface SAUIElementView : UIView @end
@implementation SAUIElementView @end
@interface TestIslandGlass : UIView @end
@implementation TestIslandGlass @end

static Class WindowClass, ElementClass;
static BOOL InUpdate, Disabled, OriginalIslandGlassSeen, GlassConstructorVerified, GlassConstructionFailed;
// External playback enters production only in the deliberate negative control.
static BOOL PlaybackIsPlaying;
static char BackgroundKey, StateKey, GlassModeKey;
static NSHashTable<UIView *> *Hosts;
static void (*OriginalLayout)(id, SEL);
static NSUInteger NativeLayouts, Pulses;
static BOOL ExpectBackingAtNativeLayout;
static UIView *ChangeAtNativeLayout;
static BOOL HideAtNativeLayout;
static UIView *View(Class cls, UIWindow *window);
static void Pulse(void) { Pulses++; }
static void Log(NSString *event) { (void)event; }
static BOOL IsIslandGlass(UIView *view) { return [view isKindOfClass:TestIslandGlass.class]; }
static void EnsureActiveEdge(UIView *view) { (void)view; }
static BOOL MangoGlassSetting(void) { return YES; }
static UIView *CreateBackground(BOOL mango, CGRect rect) {
    UIView *view = View(UIView.class, nil);
    view.frame = view.bounds = rect;
    objc_setAssociatedObject(view, &GlassModeKey, @(mango), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return view;
}
static BOOL MSRuntimeFlag(NSString *key) { return [key isEqualToString:@"IdleEnabled"]; }
static BOOL IslandEdgeOptIn(void) { return YES; }
static void MSIslandRepairUpdate(UIView *host,UIView *idle,BOOL edge) { (void)host; (void)idle; (void)edge; }
/* ACTUAL_MEDIA_HELPERS */
static UIView *View(Class cls, UIWindow *window) {
    UIView *view = [cls new];
    view.layer = [CALayer new];
    view.subviews = [NSMutableArray array];
    view.window = window;
    view.frame = view.bounds = CGRectMake(0, 0, 125, 36.67);
    view.layer.bounds = view.bounds;
    view.alpha = 1;
    view.userInteractionEnabled = YES;
    return view;
}
static void Presented(UIView *view, CGFloat opacity, CGRect bounds) {
    view.layer.presentationLayer = [CALayer new];
    view.layer.presentationLayer.opacity = opacity;
    view.layer.presentationLayer.bounds = bounds;
}
static void Near(CGFloat actual, CGFloat expected) { assert(fabs(actual - expected) < 0.000001); }
static void Backing(UIView *host, CGFloat expected) {
    UIView *background = objc_getAssociatedObject(host, &BackgroundKey);
    if (expected == 0) { assert(background.superview == nil && background.hidden); }
    else { assert(background.superview == host && !background.hidden); Near(background.alpha, expected); }
}
static void NativeLayout(id self, SEL cmd) {
    (void)cmd;
    NativeLayouts++;
    UIView *background = objc_getAssociatedObject(self, &BackgroundKey);
    assert((background.superview == self) == ExpectBackingAtNativeLayout);
    if (ChangeAtNativeLayout) { ChangeAtNativeLayout.hidden = HideAtNativeLayout; ChangeAtNativeLayout.alpha = 1; }
}
int main(void) {
    WindowClass = UIWindow.class;
    ElementClass = SAUIElementView.class;
    GlassConstructorVerified = YES;
    OriginalIslandGlassSeen = YES;
    Hosts = [NSHashTable weakObjectsHashTable];
    OriginalLayout = NativeLayout;
    UIWindow *window = (UIWindow *)View(UIWindow.class, nil);
    window.window = window;
    UIView *host = View(UIView.class, window);
    UIView *background = View(UIView.class, nil);
    objc_setAssociatedObject(background, &GlassModeKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(host, &BackgroundKey, background, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SynchronizeBackground(host, background, 1);
    ExpectBackingAtNativeLayout = YES;
    // Playing without any activity must retain the only visible glass.
    PlaybackIsPlaying = YES;
    assert(PlaybackIsPlaying);
    Layout(host, @selector(layoutSubviews));
    Backing(host, 1);
    assert(NativeLayouts == 1 && Pulses > 0);
    NSUInteger frame = background.frameWrites, alpha = background.alphaWrites;
    NSUInteger hidden = background.hiddenWrites, insertions = host.insertions;
    for (NSUInteger i = 0; i < 120; i++) Layout(host, @selector(layoutSubviews));
    Backing(host, 1);
    assert(background.frameWrites == frame && background.alphaWrites == alpha);
    assert(background.hiddenWrites == hidden && host.insertions == insertions && background.removals == 0);
    // Media roots are containers: hidden, alpha-zero, zero-size AND opaque empty
    // roots do not establish rendered native activity. Test both real class names.
    Class roots[] = {MRUActivityNowPlayingView.class, MRUSessionNowPlayingView.class};
    for (NSUInteger i = 0; i < sizeof(roots) / sizeof(roots[0]); i++) {
        UIView *media = View(roots[i], window);
        [host insertSubview:media atIndex:host.subviews.count];
        media.hidden = YES;
        Layout(host, @selector(layoutSubviews)); Backing(host, 1);
        assert(media.superview == host && media.hidden);
        media.hidden = NO; media.alpha = 0;
        Layout(host, @selector(layoutSubviews)); Backing(host, 1);
        media.alpha = 1; media.bounds = CGRectZero;
        Layout(host, @selector(layoutSubviews)); Backing(host, 1);
        media.bounds = host.bounds;
        Layout(host, @selector(layoutSubviews)); Backing(host, 1);
        // Only the existing native element/glass layer inside the container
        // provides evidence. The full Update uses its presentation fade.
        Class nativeClasses[] = {SAUIElementView.class, TestIslandGlass.class};
        for (NSUInteger j = 0; j < sizeof(nativeClasses) / sizeof(nativeClasses[0]); j++) {
            UIView *native = View(nativeClasses[j], window);
            [media insertSubview:native atIndex:0];
            native.alpha = 0;
            Presented(native, 0.25, host.bounds);
            Update(host); Backing(host, 0.75);
            native.layer.presentationLayer.opacity = 0.75;
            Update(host); Backing(host, 0.25);
            native.layer.presentationLayer.opacity = 1;
            Update(host); Backing(host, 0);
            // Dismiss destination is zero; presentation still has visible pixels.
            CGFloat fades[] = {0.75, 0.25, 0};
            for (NSUInteger k = 0; k < sizeof(fades) / sizeof(fades[0]); k++) {
                native.layer.presentationLayer.opacity = fades[k];
                Update(host); Backing(host, 1 - fades[k]);
            }
            native.alpha = 1;
            Presented(native, 1, host.bounds);
            media.hidden = YES;
            Update(host); Backing(host, 1);
            media.hidden = NO; media.layer.hidden = YES;
            Update(host); Backing(host, 1);
            media.layer.hidden = NO;
            Presented(media, 0, host.bounds);
            Update(host); Backing(host, 1);
            media.layer.presentationLayer.opacity = 0.4;
            Update(host); Backing(host, 0.6);
            media.layer.presentationLayer = nil;
            // Native layout reveals/hides actual activity; inspect afterwards.
            native.layer.presentationLayer = nil; native.hidden = YES;
            Update(host); Backing(host, 1);
            ChangeAtNativeLayout = native; HideAtNativeLayout = NO;
            ExpectBackingAtNativeLayout = YES;
            Layout(host, @selector(layoutSubviews)); Backing(host, 0);
            ExpectBackingAtNativeLayout = NO; HideAtNativeLayout = YES;
            Layout(host, @selector(layoutSubviews)); Backing(host, 1);
            assert(native.superview == media && native.hidden);
            ChangeAtNativeLayout = nil; ExpectBackingAtNativeLayout = YES;
            [native removeFromSuperview];
        }
        [media removeFromSuperview];
        Update(host); Backing(host, 1);
    }
    // Existing compact-return/expanded-geometry rules remain intact.
    Presented(host, 1, CGRectMake(0, 0, 150, 44));
    Update(host); Backing(host, 0);
    Presented(host, 1, CGRectMake(0, 0, 143, 40));
    Update(host); Backing(host, 1);
    host.layer.presentationLayer = nil;
    PlaybackIsPlaying = NO;
    if (Failures) { fprintf(stderr, "FAIL: %d production media/update expectations\n", Failures); return 1; }
    puts("PASS: production Eligibility/Update/Layout: playback and containers retain glass, visible native activity blends, layout observed, settled setters quiet (property stubs)");
    return 0;
}
