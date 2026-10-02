// The runner inserts production helper and Layout bodies. Property stubs only:
// these check ownership/order/setter quietness, not UIKit or device behavior.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#include <stdio.h>

static int Failures;
#undef assert
#define assert(condition) do { if (!(condition)) { Failures++; } } while (0)

@interface CALayer : NSObject
@property (nonatomic) CGFloat cornerRadius;
@end
@implementation CALayer
@end

@interface UIView : NSObject
@property (nonatomic) CGFloat alpha;
@property (nonatomic) BOOL hidden;
@property (nonatomic) CGRect frame;
@property (nonatomic) CGRect bounds;
@property (nonatomic, retain) CALayer *layer;
@property (nonatomic, assign) UIView *window;
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
@end
@implementation UIView
@synthesize frame = _frame, alpha = _alpha, hidden = _hidden;
- (void)setFrame:(CGRect)frame { _frame = frame; self.frameWrites++; }
- (void)setAlpha:(CGFloat)alpha { _alpha = alpha; self.alphaWrites++; }
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
@end

@interface MRUActivityNowPlayingView : UIView @end
@implementation MRUActivityNowPlayingView @end
@interface MRUSessionNowPlayingView : UIView @end
@implementation MRUSessionNowPlayingView @end

static Class ActivityMediaClass, SessionMediaClass;
static BOOL MediaPlaying;
static char BackgroundKey;
static NSHashTable<UIView *> *Hosts;
static void (*OriginalLayout)(id, SEL);
static NSUInteger NativeLayouts, Pulses, Updates;
static BOOL ExpectDetached;
static void Pulse(void) { Pulses++; }
static void Update(UIView *host) { (void)host; Updates++; }

/* ACTUAL_MEDIA_HELPERS */

static UIView *View(Class cls, UIView *window) {
    UIView *view = [cls new];
    view.layer = [CALayer new];
    view.subviews = [NSMutableArray array];
    view.window = window;
    view.frame = view.bounds = CGRectMake(0, 0, 125, 36.67);
    return view;
}

static void NativeLayout(id self, SEL cmd) {
    (void)cmd;
    NativeLayouts++;
    UIView *background = objc_getAssociatedObject(self, &BackgroundKey);
    assert((background.superview == nil) == ExpectDetached);
}

int main(void) {
    ActivityMediaClass = MRUActivityNowPlayingView.class;
    SessionMediaClass = MRUSessionNowPlayingView.class;
    Hosts = [NSHashTable weakObjectsHashTable];
    OriginalLayout = NativeLayout;
    UIView *window = View(UIView.class, nil);
    window.window = window;
    UIView *host = View(UIView.class, window);
    UIView *background = View(UIView.class, nil);
    objc_setAssociatedObject(host, &BackgroundKey, background, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SynchronizeBackground(host, background, 1);
    assert(background.superview == host && !background.hidden);
    NSUInteger frame = background.frameWrites, alpha = background.alphaWrites;
    NSUInteger hidden = background.hiddenWrites, insertions = host.insertions;
    for (NSUInteger i = 0; i < 120; i++) SynchronizeBackground(host, background, 1);
    assert(background.frameWrites == frame && background.alphaWrites == alpha);
    assert(background.hiddenWrites == hidden && host.insertions == insertions);
    Layout(host, @selector(layoutSubviews));
    assert(NativeLayouts == 1 && Pulses == 1 && Updates == 1);
    assert(background.superview == host);

    // Actual playing state releases the owned copy before original layout.
    MediaPlaying = YES;
    ExpectDetached = YES;
    Layout(host, @selector(layoutSubviews));
    assert(background.hidden && background.superview == nil);
    assert(background.frameWrites == frame);
    NSUInteger removals = background.removals;
    for (NSUInteger i = 0; i < 120; i++) PrepareForNativeLayout(host);
    assert(background.removals == removals && background.frameWrites == frame);
    assert(!NeedsIdleBacking(YES, NO, 0, YES));
    assert(!NeedsIdleBacking(NO, YES, 0.2, YES));
    assert(NeedsIdleBacking(YES, NO, 0, NO));
    assert(NeedsIdleBacking(NO, YES, 0.2, NO));
    assert(!NeedsIdleBacking(NO, YES, 1, NO));
    MediaPlaying = NO;
    SynchronizeBackground(host, background, 1);
    UIView *media = View(MRUActivityNowPlayingView.class, window);
    media.alpha = 0;
    media.hidden = YES;
    media.bounds = CGRectZero;
    [host insertSubview:media atIndex:host.subviews.count];
    assert(NativeMediaPresent(host));
    Layout(host, @selector(layoutSubviews));
    assert(background.superview == nil);
    assert(media.superview == host && media.alpha == 0 && media.hidden);
    [media removeFromSuperview];
    media = View(MRUSessionNowPlayingView.class, window);
    [host insertSubview:media atIndex:0];
    assert(NativeMediaPresent(host));
    [media removeFromSuperview];
    assert(!NativeMediaPresent(host));
    SynchronizeBackground(host, background, 1);
    assert(background.superview == host);
    if (Failures) { fprintf(stderr, "FAIL: %d production media-helper expectations\n", Failures); return 1; }
    puts("PASS: production media ownership, native callback order, and settled setter quietness (property stubs)");
    return 0;
}
