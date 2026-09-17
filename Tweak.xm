// MangoUpsideDownWorld 0.13.0-alpha13. Experimental; see EVIDENCE.md.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <substrate.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <string.h>
#include "WorldMath.h"

static const char *Disabled="/var/mobile/Library/Preferences/MangoUpsideDownWorld.disabled";
static const char *TracePath="/var/mobile/Library/Preferences/MangoUpsideDownWorld.trace";
static Class WindowClass, PassClass, ContentClass, ContainerClass;
static NSHashTable<UIWindow *> *Windows;
static NSHashTable<UIView *> *Roots;
static BOOL Enabled, Installed, Busy, Tracing;
static unsigned Depth, Attempts, HitDepth;
static dispatch_source_t Timer;
static char StateKey;
// Forward declarations: the floating debug overlay is defined near the
// gesture-trace code below, but Log() (defined first, and the single choke
// point every call site in this file already goes through) mirrors every
// line into its history, and Reconcile() toggles its visibility and turn
// state, and the other-window probe checks window identity against it, all
// ahead of that definition.
static void DebugRecord(NSString *line);
static void DebugSetVisible(BOOL visible);
static void DebugSetTurned(BOOL turned);
static UIWindow *DebugWindow;

// Patch-owned state classes, NOT names extracted from Mango.
@interface MWOwnedTransform : NSObject
@property(nonatomic) CGAffineTransform before, after;
@property(nonatomic) BOOL applied;
@end
@implementation MWOwnedTransform
@end
@interface MWWorldState : NSObject
@property(nonatomic,strong) MWOwnedTransform *outer;
@property(nonatomic,strong) NSMapTable<UIView *,MWOwnedTransform *> *inner;
@property(nonatomic,weak) UIView *parent;
@property(nonatomic) BOOL suspended;
@property(nonatomic) double lastLog, lastSkipLog;
@property(nonatomic,copy) NSString *lastSkip;
@end
@implementation MWWorldState
@end

static void Log(NSString *s) {
    NSLog(@"[MangoUDWorld] %@",s);
    // Every call site funnels through here, so mirroring into the debug
    // overlay's history at this single point (rather than at each of this
    // file's Log() call sites) is what keeps the floating panel and the log
    // file in parity by construction, including at call sites added later.
    DebugRecord(s);
    mkdir("/var/mobile/Library/Logs",0755);
    int fd=open("/var/mobile/Library/Logs/MangoUpsideDownWorld.log",O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW,0600);
    if(fd<0)return;
    struct stat st;
    if(fstat(fd,&st)||!S_ISREG(st.st_mode)){close(fd);return;}
    if(st.st_size>512*1024)ftruncate(fd,0);
    NSData *b=[[NSString stringWithFormat:@"%.3f %@\n",NSDate.timeIntervalSinceReferenceDate,s] dataUsingEncoding:NSUTF8StringEncoding];
    (void)write(fd,b.bytes,b.length);close(fd);
}
static MWTransform Math(CGAffineTransform t){return (MWTransform){t.a,t.b,t.c,t.d,t.tx,t.ty};}
static CGAffineTransform CG(MWTransform t){return CGAffineTransformMake(t.a,t.b,t.c,t.d,t.tx,t.ty);}
static MWWorldState *State(UIView *v){return objc_getAssociatedObject(v,&StateKey);}
// The cancellation record for this content view, created on demand. Returns it
// only while the window above this view's root is actually turned (s.outer is
// the window's owned transform; see ApplyWorld): that turn is what makes an
// inverted content value render upside-down, so it is also the exact
// condition under which normalizing an incoming value is correct.
static MWOwnedTransform *OwnedContent(UIView *v){
    for(UIView *p=v.superview;p;p=p.superview){
        MWWorldState *s=State(p);
        if(!s)continue;
        if(s.suspended||!s.outer.applied)return nil;
        MWOwnedTransform *owned=[s.inner objectForKey:v];
        if(!owned){owned=[MWOwnedTransform new];[s.inner setObject:owned forKey:v];}
        return owned;
    }
    return nil;
}
static NSInteger Orientation(void){
    Class c=objc_getClass("DecoratedAppSceneView");
    SEL sel=sel_registerName("mango_currentInterfaceOrientation");
    Method m=c?class_getClassMethod(c,sel):NULL;char ret[32]={0};
    if(!m||method_getNumberOfArguments(m)!=2)return -1;
    method_getReturnType(m,ret,sizeof(ret));
    if(strcmp(ret,@encode(NSInteger)))return -1;
    return ((NSInteger(*)(id,SEL))objc_msgSend)((id)c,sel);
}
static BOOL RestoreOne(UIView *v,MWOwnedTransform *s){
    if(!s.applied)return YES;
    s.applied=NO;
    if(!MWNear(Math(v.transform),Math(s.after)))return NO;
    v.transform=s.before;return YES;
}
static void RestoreWorld(UIView *root){
    MWWorldState *s=State(root);if(!s)return;
    // s.outer now belongs to the window (see ApplyWorld), not to root itself.
    // s.parent is weak; treat it going nil while still marked applied as the
    // same kind of conflict an unrecognized value would be, rather than
    // message a nil view for the CGAffineTransform-returning accessor below.
    BOOL ok=YES;
    if(s.outer.applied){
        if(s.parent)ok=RestoreOne(s.parent,s.outer);
        else{s.outer.applied=NO;ok=NO;}
    }
    for(UIView *v in s.inner.keyEnumerator.allObjects)
        if(!RestoreOne(v,[s.inner objectForKey:v]))ok=NO;
    if(!ok&&!s.suspended){s.suspended=YES;Log(@"CONFLICT: unknown transform; world suspended until respring");}
}
static void SetOwned(UIView *v,MWOwnedTransform *s,CGAffineTransform t){
    s.before=v.transform;s.after=t;s.applied=YES;v.transform=t;
}
// Report why a correction was skipped. Rate limited per root, and repeated only
// when the reason changes, so a steady skip cannot flood the log.
static void Skip(MWWorldState *s,NSString *reason){
    if(!s)return;
    double now=CACurrentMediaTime();
    if([s.lastSkip isEqualToString:reason]&&now-s.lastSkipLog<=5)return;
    s.lastSkip=reason;s.lastSkipLog=now;
    Log([NSString stringWithFormat:@"SKIP reason=%@ mangoOrientation=%ld",reason,(long)Orientation()]);
}
static BOOL VisibleChain(UIView *v,UIView *stop){
    unsigned n=0;
    for(;v&&n++<32;v=v.superview){
        if(v.hidden||v.alpha<=.01||!v.userInteractionEnabled)return NO;
        if(v==stop)return YES;
    }
    return NO;
}
static NSArray<UIView *> *Contents(UIView *root){
    NSMutableArray *queue=[NSMutableArray arrayWithObject:root],*result=[NSMutableArray array];
    for(NSUInteger i=0;i<queue.count;i++){
        if(queue.count>2048)return nil;
        UIView *v=queue[i];
        if(!CATransform3DIsAffine(v.layer.transform)||!CATransform3DIsIdentity(v.layer.sublayerTransform))return nil;
        if([v isKindOfClass:ContentClass])[result addObject:v];
        [queue addObjectsFromArray:v.subviews];
    }
    return result;
}
static void Discover(UIWindow *window){
    if(![window isKindOfClass:WindowClass]||window.screen!=UIScreen.mainScreen)return;
    [Windows addObject:window];
    for(UIView *root in window.subviews){
        if(![root isKindOfClass:PassClass]||State(root))continue;
        NSArray *contents=Contents(root);if(!contents.count)continue;
        MWWorldState *s=[MWWorldState new];s.outer=[MWOwnedTransform new];
        s.inner=[NSMapTable weakToStrongObjectsMapTable];s.parent=window;
        objc_setAssociatedObject(root,&StateKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [Roots addObject:root];Log([NSString stringWithFormat:@"TRACK window=%p root=%p contents=%lu",(__bridge void *)window,(__bridge void *)root,(unsigned long)contents.count]);
    }
}
static void ApplyWorld(UIView *root){
    MWWorldState *s=State(root);UIWindow *w=root.window;
    if(s.suspended||root.superview!=w||![w isKindOfClass:WindowClass]||w.screen!=UIScreen.mainScreen)return;
    if(s.parent!=w){s.suspended=YES;return;}
    NSArray<UIView *> *contents=Contents(root);if(!contents.count){Skip(s,@"contents");return;}
    if(!CATransform3DIsAffine(w.layer.transform)||!CATransform3DIsIdentity(w.layer.sublayerTransform)){Skip(s,@"window-layer");return;}
    id<UICoordinateSpace> fixed=w.screen.fixedCoordinateSpace;
    CGRect screen=fixed.bounds;
    CGRect r=[root convertRect:root.bounds toCoordinateSpace:fixed];
    // Only the full-screen root shape evidenced in the device log is accepted.
    if(!isfinite(r.origin.x)||!isfinite(r.origin.y)||!isfinite(r.size.width)||!isfinite(r.size.height)||
       fabs(CGRectGetWidth(r)-CGRectGetWidth(screen))>2||fabs(CGRectGetHeight(r)-CGRectGetHeight(screen))>2||
       fabs(CGRectGetMidX(r)-CGRectGetMidX(screen))>2||fabs(CGRectGetMidY(r)-CGRectGetMidY(screen))>2){
        Skip(s,[NSString stringWithFormat:@"root-shape rect=%@ screen=%@",NSStringFromCGRect(r),NSStringFromCGRect(screen)]);return;}
    // Require an upright unmodified root before making the world upside-down.
    CGPoint o=[root convertPoint:CGPointZero toCoordinateSpace:fixed];
    CGPoint x=[root convertPoint:CGPointMake(1,0) toCoordinateSpace:fixed];
    CGPoint y=[root convertPoint:CGPointMake(0,1) toCoordinateSpace:fixed];
    if(x.x-o.x<=0||y.y-o.y<=0||fabs(x.y-o.y)>1e-4||fabs(y.x-o.x)>1e-4){
        Skip(s,[NSString stringWithFormat:@"root-basis dx=%g dy=%g skewX=%g skewY=%g",x.x-o.x,y.y-o.y,y.x-o.x,x.y-o.y]);return;}
    // Require an upright unmodified window too: the turn below is applied to
    // the window itself now (see the comment further down for why), so this is
    // the same kind of precondition on the thing about to be rotated.
    CGPoint wo=[w convertPoint:CGPointZero toCoordinateSpace:fixed];
    CGPoint wx=[w convertPoint:CGPointMake(1,0) toCoordinateSpace:fixed];
    CGPoint wy=[w convertPoint:CGPointMake(0,1) toCoordinateSpace:fixed];
    if(wx.x-wo.x<=0||wy.y-wo.y<=0||fabs(wx.y-wo.y)>1e-4||fabs(wy.x-wo.x)>1e-4){
        Skip(s,[NSString stringWithFormat:@"window-basis dx=%g dy=%g skewX=%g skewY=%g",wx.x-wo.x,wy.y-wo.y,wy.x-wo.x,wx.y-wo.y]);return;}
    // Validate every content basis first, so unsupported geometry causes no
    // partial correction. Hidden contents are retained for subsequent reveals.
    NSMutableArray<UIView *> *cancel=[NSMutableArray array];
    for(UIView *v in contents){
        CGPoint a=[v convertPoint:CGPointZero toCoordinateSpace:fixed];
        CGPoint b=[v convertPoint:CGPointMake(1,0) toCoordinateSpace:fixed];
        CGPoint c=[v convertPoint:CGPointMake(0,1) toCoordinateSpace:fixed];
        double dx=b.x-a.x,dy=c.y-a.y;
        if(!isfinite(dx)||!isfinite(dy)||fabs(dx)<1e-5||fabs(dy)<1e-5||
           fabs(b.y-a.y)>fabs(dx)*.001||fabs(c.x-a.x)>fabs(dy)*.001||dx*dy<=0){
            Skip(s,[NSString stringWithFormat:@"content-basis dx=%g dy=%g skewX=%g skewY=%g",dx,dy,c.x-a.x,b.y-a.y]);return;}
        // Nested content instances would be normalized twice. Fail closed.
        for(UIView *p=v.superview;p&&p!=root;p=p.superview)if([p isKindOfClass:ContentClass]){Skip(s,@"nested-content");return;}
        if(MWInvertedBasis(dx,dy,c.x-a.x,b.y-a.y))[cancel addObject:v];
    }
    // Turn the WINDOW, not root. Turning only root's own transform (the
    // current approach) leaves root and content agreeing with each other --
    // both end up turned relative to fixed space, root directly and content
    // because its own cancellation is relative to root, not to fixed -- which
    // is exactly why position and content orientation already came out
    // right. But the window itself was never touched, so it stays upright
    // relative to fixed space, disagreeing in SIGN with root and content. A
    // gesture whose translation is read relative to the window (or via any
    // API that hands back raw/fixed-space deltas, which is equivalent) reads
    // the opposite direction from one read relative to root or content --
    // which is what turned a downward swipe into an upward one. Turning the
    // window instead makes it agree with root and content too, so every
    // gesture in the subtree reads the same direction regardless of which
    // view it is anchored to. A window has no superview; its own center and
    // frame are already expressed directly in the fixed/screen space, so
    // unlike root's pivot (which needs converting into root's parent, the
    // window, first) no conversion is needed here.
    CGPoint pivot=CGPointMake(CGRectGetMidX(screen),CGRectGetMidY(screen));
    MWTransform rotated=MWTurn(Math(w.transform),(MWPoint){w.center.x,w.center.y},(MWPoint){pivot.x,pivot.y});
    if(!MWFinite(rotated)){Skip(s,@"nonfinite-turn");return;}
    // The sweep creates ownership directly: it runs before the window is
    // turned, which is the condition OwnedContent deliberately refuses.
    for(UIView *v in cancel){
        MWOwnedTransform *owned=[s.inner objectForKey:v];
        if(!owned){owned=[MWOwnedTransform new];[s.inner setObject:owned forKey:v];}
        SetOwned(v,owned,CG(MWCancelTurn(Math(v.transform))));
    }
    SetOwned(w,s.outer,CG(rotated));
    // Verify model-space half-turn on three independent points.
    CGPoint actual[3]={[root convertPoint:CGPointZero toCoordinateSpace:fixed],
        [root convertPoint:CGPointMake(1,0) toCoordinateSpace:fixed],
        [root convertPoint:CGPointMake(0,1) toCoordinateSpace:fixed]};
    CGPoint old[3]={o,x,y};
    for(int i=0;i<3;i++)if(!isfinite(actual[i].x)||!isfinite(actual[i].y)||
        fabs(actual[i].x-(2*CGRectGetMidX(screen)-old[i].x))>.1||
        fabs(actual[i].y-(2*CGRectGetMidY(screen)-old[i].y))>.1){
        RestoreWorld(root);s.suspended=YES;Log(@"SUSPEND post-transform verification failed");return;
    }
    s.lastSkip=nil;
    if(CACurrentMediaTime()-s.lastLog>5){s.lastLog=CACurrentMediaTime();
        Log([NSString stringWithFormat:@"WORLD orientation=2 root=%p contents=%lu canceled=%lu windowBounds=%@",(__bridge void *)root,(unsigned long)contents.count,(unsigned long)cancel.count,NSStringFromCGRect(w.bounds)]);}
}
static NSArray<UIWindow *> *ExistingWindows(void){
    NSMutableOrderedSet<UIWindow *> *result=[NSMutableOrderedSet orderedSet];
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if([scene isKindOfClass:UIWindowScene.class])
            [result addObjectsFromArray:((UIWindowScene *)scene).windows];
    // SpringBoard's legacy system aperture window may have no UIWindowScene
    // (sceneOrientation=0 in the supplied log). Keep this targeted fallback.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [result addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop
    return result.array;
}
// 0.13.0-alpha13, diagnostic-only (gated by Tracing, same as TraceTouches):
// the pill is not the only thing that fails to follow the world -- Mango's
// split-screen UI and any other plugin are separate windows/view trees this
// file has never looked at, and their real class names are unknown. Rather
// than guess one and hook it -- the exact mistake alpha1-8 spent this whole
// file avoiding on the pill -- this sweeps every window on the main screen
// for the same tell already used to find inverted content inside the pill
// (MWInvertedBasis: a clean, already-applied half-turn), and logs the real
// class name of whatever it finds. A hit here is what turns "some other
// plugin doesn't follow" into a concrete class to target next, the same way
// alpha11's CLASSDUMP turned a guess into SBSystemApertureLongPressGesture-
// Recognizer. Never modifies anything it finds; walks are bounded like
// Contents(), and each window class is logged only once per boot so a
// steady hit cannot flood the log.
static NSMutableSet<NSString *> *SeenInvertedWindowClasses;
static void ProbeInverted(UIView *v,id<UICoordinateSpace> fixed,unsigned depth,NSMutableArray<NSString *> *hits){
    if(depth>32||hits.count>=8||!CATransform3DIsAffine(v.layer.transform))return;
    CGPoint a=[v convertPoint:CGPointZero toCoordinateSpace:fixed];
    CGPoint b=[v convertPoint:CGPointMake(1,0) toCoordinateSpace:fixed];
    CGPoint c=[v convertPoint:CGPointMake(0,1) toCoordinateSpace:fixed];
    double dx=b.x-a.x,dy=c.y-a.y;
    if(MWInvertedBasis(dx,dy,c.x-a.x,b.y-a.y))[hits addObject:NSStringFromClass(v.class)];
    for(UIView *sub in v.subviews)ProbeInverted(sub,fixed,depth+1,hits);
}
static void ProbeOtherWindows(void){
    if(!SeenInvertedWindowClasses)SeenInvertedWindowClasses=[NSMutableSet set];
    for(UIWindow *w in ExistingWindows()){
        if(w.screen!=UIScreen.mainScreen||w==DebugWindow||(WindowClass&&[w isKindOfClass:WindowClass]))continue;
        NSString *wcls=NSStringFromClass(w.class);
        if([SeenInvertedWindowClasses containsObject:wcls])continue;
        NSMutableArray<NSString *> *hits=[NSMutableArray array];
        ProbeInverted(w,w.screen.fixedCoordinateSpace,0,hits);
        if(!hits.count)continue;
        [SeenInvertedWindowClasses addObject:wcls];
        Log([NSString stringWithFormat:@"SPLITPROBE window=%@ inverted=%@",wcls,[hits componentsJoinedByString:@","]]);
    }
}
static void Reconcile(void){
    if(Busy||Depth||![NSThread isMainThread])return;
    Busy=YES;
    @try{
        [UIView performWithoutAnimation:^{
            for(UIView *root in Roots.allObjects)RestoreWorld(root);
            if(access(Disabled,F_OK)==0&&Enabled){Enabled=NO;Log(@"DISABLED: restored owned transforms");}
            // Tracing is independent of Enabled/orientation: it is a read-only
            // diagnostic, useful for comparing turned vs. untouched behavior.
            BOOL tracing=access(TracePath,F_OK)==0;
            if(tracing!=Tracing){Tracing=tracing;Log(Tracing?@"TRACE: touch/gesture tracing enabled":@"TRACE: touch/gesture tracing disabled");DebugSetVisible(Tracing);}
            BOOL active=Enabled&&Orientation()==UIInterfaceOrientationPortraitUpsideDown;
            DebugSetTurned(active);
            if(Tracing)ProbeOtherWindows();
            if(!active)return;
            for(UIWindow *w in ExistingWindows())Discover(w);
            for(UIWindow *w in Windows.allObjects)Discover(w);
            for(UIView *root in Roots.allObjects)ApplyWorld(root);
        }];
    }@finally{Busy=NO;}
}
static BOOL Relevant(UIView *v){
    if([v isKindOfClass:WindowClass])return YES;
    if(State(v))return YES;
    return [v isKindOfClass:ContentClass]&&[v.window isKindOfClass:WindowClass];
}
static BOOL Begin(UIView *v){
    if(Busy||![NSThread isMainThread]||!Relevant(v))return NO;
    if(Depth++==0){Busy=YES;
        @try{[UIView performWithoutAnimation:^{for(UIView *root in Roots.allObjects)RestoreWorld(root);}];}
        @finally{Busy=NO;}}
    return YES;
}
static void End(BOOL begun){if(begun&&--Depth==0)Reconcile();}

// Public UIView methods hooked only on the three evidenced private subclasses.
// Separate originals avoid cross-class recursion when a method is inherited.
#define DEFINE_HOOKS(P) \
static void (*P##Layout)(id,SEL); \
static void P##HookLayout(id s,SEL c){BOOL b=Begin(s);@try{P##Layout(s,c);if(!Busy&&[NSThread isMainThread]&&[s isKindOfClass:WindowClass])Discover(s);}@finally{End(b);}} \
static void (*P##Frame)(id,SEL,CGRect); \
static void P##HookFrame(id s,SEL c,CGRect v){BOOL b=Begin(s);@try{P##Frame(s,c,v);}@finally{End(b);}} \
static void (*P##Bounds)(id,SEL,CGRect); \
static void P##HookBounds(id s,SEL c,CGRect v){BOOL b=Begin(s);@try{P##Bounds(s,c,v);}@finally{End(b);}} \
static void (*P##Center)(id,SEL,CGPoint); \
static void P##HookCenter(id s,SEL c,CGPoint v){BOOL b=Begin(s);@try{P##Center(s,c,v);}@finally{End(b);}}
#define DEFINE_TRANSFORM_HOOK(P) \
static void (*P##Transform)(id,SEL,CGAffineTransform); \
static void P##HookTransform(id s,SEL c,CGAffineTransform v){BOOL b=Begin(s);@try{P##Transform(s,c,v);}@finally{End(b);}}
DEFINE_HOOKS(Pass)
DEFINE_HOOKS(Content)
DEFINE_HOOKS(Window)
DEFINE_TRANSFORM_HOOK(Pass)
DEFINE_TRANSFORM_HOOK(Window)

// Content transforms are the one value Mango animates. Correcting one after
// the original setter cannot retarget an animation UIKit has already built
// toward Mango's inverted value, so this hook substitutes an upright target
// before calling through instead. It deliberately does not use Begin()/End():
// Begin's restore silently commits Mango's raw last value to the model right
// before this call runs, and Core Animation captures whatever the model held
// at that instant as the start of any animation this call is part of. That
// silent detour is what turned Mango's own reveal and dismiss animations into
// a visible spin through the sign boundary this cancellation exists to hide --
// a brief one on every activation, a slow one on dismissal. Handling the
// value directly, with no write in between, keeps every animation Core
// Animation builds for this call between two upright endpoints. World's own
// writes (SetOwned, RestoreOne) reach this same hook re-entrantly while Busy
// is set; they are passed through untouched since their bookkeeping is
// already done by the caller.
static void (*ContentTransform)(id,SEL,CGAffineTransform);
static void ContentHookTransform(UIView *s,SEL c,CGAffineTransform v){
    if(Busy||![NSThread isMainThread]){ContentTransform(s,c,v);return;}
    MWOwnedTransform *owned=OwnedContent(s);
    MWTransform upright=MWCancelTurn(Math(v));
    if(owned&&MWInvertedBasis(v.a,v.d,v.c,v.b)&&MWFinite(upright)){
        ContentTransform(s,c,CG(upright));
        owned.before=v;owned.after=CG(upright);owned.applied=YES;
    }else{
        // Not a value this hook can reconstruct from (transitional, already
        // upright, or nonfinite): pass it through untouched and let the
        // periodic sweep re-examine and re-cancel it if it settles inverted.
        if(owned)owned.applied=NO;
        ContentTransform(s,c,v);
    }
}

static UIView *WorldHit(UIWindow *w,CGPoint point,UIEvent *event){
    if(!Enabled||Busy||Depth||![NSThread isMainThread]||HitDepth||Orientation()!=2)return nil;
    ++HitDepth;
    @try {
    for(UIView *root in w.subviews.reverseObjectEnumerator){
        MWWorldState *s=State(root);
        if(!s.outer.applied||s.suspended||!VisibleChain(root,w))continue;
        CGPoint local=[root convertPoint:point fromView:w];
        if(!isfinite(local.x)||!isfinite(local.y))continue;
        UIView *hit=[root hitTest:local withEvent:event];
        if(hit&&hit!=root&&[hit isDescendantOfView:root]&&VisibleChain(hit,w))return hit;
    }
    return nil;
    } @finally {--HitDepth;}
}
static UIView *(*OrigHit)(id,SEL,CGPoint,UIEvent *);
static UIView *HookHit(UIWindow *w,SEL cmd,CGPoint p,UIEvent *event){
    UIView *original=OrigHit(w,cmd,p,event);
    if(original&&original!=w)return original;
    UIView *hit=WorldHit(w,p,event);
    if(hit){static double last;double now=CACurrentMediaTime();if(now-last>1){last=now;Log([NSString stringWithFormat:@"HIT fallback point=%@ target=%@",NSStringFromCGPoint(p),NSStringFromClass(hit.class)]);}return hit;}
    return original;
}
static BOOL (*OrigInside)(id,SEL,CGPoint,UIEvent *);
static BOOL HookInside(UIWindow *w,SEL cmd,CGPoint p,UIEvent *e){
    if(OrigInside(w,cmd,p,e))return YES;
    return WorldHit(w,p,e)!=nil;
}
static BOOL Signature(Class c,SEL sel,const char *ret,NSArray<NSString *> *args){
    Method m=class_getInstanceMethod(c,sel);char buf[512]={0};
    if(!m||method_getNumberOfArguments(m)!=args.count+2)return NO;
    method_getReturnType(m,buf,sizeof(buf));if(strcmp(buf,ret))return NO;
    for(NSUInteger i=0;i<args.count;i++){method_getArgumentType(m,(unsigned)i+2,buf,sizeof(buf));if(strcmp(buf,args[i].UTF8String))return NO;}
    return YES;
}
static BOOL ValidClass(Class c,Class base){for(;c;c=class_getSuperclass(c))if(c==base)return YES;return NO;}
static BOOL VerifiedMango(void){
    const uint8_t uuid[16]={0x67,0xc0,0xd7,0xc2,0x44,0x87,0x3f,0xd2,0x95,0x35,0x06,0x77,0x45,0xae,0x4b,0x8f};
    BOOL found=NO;
    for(uint32_t i=0;i<_dyld_image_count();i++){
        const char *name=_dyld_get_image_name(i);if(!name)continue;
        const char *base=strrchr(name,'/');base=base?base+1:name;
        if(!strcmp(base,"MangoUpsideDownFix.dylib")){Log(@"NO HOOKS: uninstall MangoUpsideDownFix before using World");return NO;}
        if(strcmp(base,"mango.dylib"))continue;
        const struct mach_header_64 *h=(const struct mach_header_64 *)_dyld_get_image_header(i);
        if(!h||h->magic!=MH_MAGIC_64)continue;
        const uint8_t *p=(const uint8_t *)(h+1),*end=p+h->sizeofcmds;
        for(uint32_t n=0;n<h->ncmds;n++){
            if((size_t)(end-p)<sizeof(struct load_command))break;
            const struct load_command *lc=(const struct load_command *)p;
            if(lc->cmdsize<sizeof(*lc)||lc->cmdsize>(size_t)(end-p))break;
            if(lc->cmd==LC_UUID&&lc->cmdsize>=sizeof(struct uuid_command))found=!memcmp(((const struct uuid_command *)p)->uuid,uuid,16);
            p+=lc->cmdsize;
        }
    }
    return found;
}
// Why the direction stayed backwards through four attempts at turning
// geometry, and what this version does instead.
//
// A view's rendering matrix and its touch-coordinate matrix are the same
// matrix (touches run it inverted). So no transform can flip what is drawn
// without equally flipping the coordinates anything in that same subtree
// reads -- alpha1-3 turned root, alpha4 turned the window, which is the
// topmost view World can reach, and the swipe direction was reported wrong
// after both. That rules out the whole "some view in the chain still
// disagrees in sign" family of explanations, including the one alpha4 was
// built on.
//
// What is left is a reader that does not sit in the subtree at all: it asks
// the screen's fixedCoordinateSpace, i.e. physical screen position. A
// window's transform only places the window INSIDE that space; it cannot
// redefine the space itself. Such a reader therefore always sees where the
// finger physically is, correctly and unaffected by anything World does --
// and that is the bug. World moves the island from the physical top of the
// screen to the physical bottom; the reader keeps deciding up-versus-down
// against the layout it was written for. Every swipe comes out inverted, and
// would keep coming out inverted no matter how much more geometry is turned.
//
// This is also consistent with the two facts that looked contradictory: live
// drag tracking follows the finger (it re-reads position continuously and
// renders through the turned subtree, so both halves are in the same turned
// space and cancel), while the discrete up/down verdict does not (it is one
// sign taken in fixed space and never passed through the turn).
//
// So the fix is not more geometry. It is one negation applied at the single
// place where a fixed-space vertical delta enters the island's gesture
// handling: UIPanGestureRecognizer's translationInView:/velocityInView:,
// public documented UIKit API, when the recognizer's own view is inside a
// root World is actively turning. Inside that subtree the turn has already
// inverted the visual meaning of "down", so returning the negated vector is
// what makes the reader's verdict match the finger. Restricted that tightly,
// this cannot reach any pan gesture elsewhere in SpringBoard, and it reverts
// to the untouched value the moment the world is not turned.
//
// Horizontal is negated too, for the same reason and by the same half-turn:
// a half-turn inverts both axes, so left/right on the turned island is
// mirrored exactly as up/down is. Negating only y would fix the reported
// symptom and leave the horizontal half of the same bug in place.
//
// Confidence and how this gets falsified: the reasoning above is sound but
// the specific reader has not been observed -- alpha7's read-only probe on
// these same two methods logged nothing during testing, which means either
// no swipe was performed in that window, or the real recognizer is a private
// subclass that overrides these two methods and so bypasses a base-class
// hook. If it is that subclass, this fix changes nothing observable and the
// direction stays wrong; that outcome is informative, not a regression, and
// it is the reason GESTURE logging is kept in place here. If instead the
// reader takes its delta from raw UITouch locations rather than from a pan
// recognizer, the same thing happens. Either way the next step is to log the
// recognizer's real class rather than guess again.
static BOOL InvertGestureAxes=YES;
// Device result of the probe above: pillSwipeDownAction/pillSwipeUpAction and
// A gesture belongs to the turned world only while its own view is root or a
// descendant of a root that is currently turned. The turn is what inverts the
// visual meaning of a fixed-space delta, so it is also the exact condition
// under which negating one is correct -- the same reasoning, and the same
// s.outer.applied test, that OwnedContent uses for content transforms. A
// suspended root is deliberately excluded: after SUSPEND or CONFLICT the
// world is no longer turned, so its deltas must be passed through untouched.
static BOOL InsideTurnedRoot(UIView *v){
    if(!Roots.count)return NO;
    for(unsigned n=0;v&&n++<64;v=v.superview){
        MWWorldState *s=State(v);
        if(s)return !s.suspended&&s.outer.applied;
    }
    return NO;
}
// Floating debug overlay, added in 0.10.0-alpha10. The file-based trace
// toggle answers "did anything fire" only after the fact, through Filza or
// SSH; this answers it live, on the screen being tested, with no separate
// retrieval step. It is a plain UIWindow the World never registers as a
// Root, so none of the world/content/gesture hooks above ever apply to it --
// it always renders upright, and its own drag/tap gestures are unaffected by
// TurnDelta (InsideTurnedRoot walks superviews looking for a tracked Root;
// this window's view tree is never one).
static UIWindowScene *MainWindowScene(void){
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if([scene isKindOfClass:UIWindowScene.class]&&((UIWindowScene *)scene).screen==UIScreen.mainScreen)
            return (UIWindowScene *)scene;
    return nil;
}
@interface MWDebugWindow : UIWindow
@end
@implementation MWDebugWindow
// Only the bubble/panel subviews should ever receive a touch; every other
// point in this full-screen window must fall through to whatever is behind
// it -- the same click-through requirement SBFTouchPassThroughView names.
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *hit=[super hitTest:p withEvent:e];
    return hit==self?nil:hit;
}
@end
@interface MWDebugController : NSObject
- (void)onTap:(UITapGestureRecognizer *)g;
- (void)onPan:(UIPanGestureRecognizer *)g;
- (void)onLongPress:(UILongPressGestureRecognizer *)g;
@end
static UIView *DebugBubble;
static UILabel *DebugCount;
static UITextView *DebugPanel;
static NSMutableArray<NSString *> *DebugHistory;
static BOOL DebugExpanded;
static void DebugLayout(void){
    if(!DebugWindow)return;
    DebugPanel.hidden=!DebugExpanded;
    if(!DebugExpanded)return;
    CGRect screen=UIScreen.mainScreen.bounds;
    CGRect b=DebugBubble.frame;
    CGFloat w=MIN((CGFloat)300,screen.size.width-16),h=MIN((CGFloat)360,screen.size.height-16);
    CGFloat x=MAX((CGFloat)8,MIN(b.origin.x,screen.size.width-w-8));
    CGFloat y=b.origin.y-h-8;
    if(y<8)y=CGRectGetMaxY(b)+8;
    DebugPanel.frame=CGRectMake(x,y,w,h);
    DebugPanel.text=[DebugHistory componentsJoinedByString:@"\n"];
    [DebugPanel scrollRangeToVisible:NSMakeRange(DebugPanel.text.length,0)];
}
@implementation MWDebugController
- (void)onTap:(UITapGestureRecognizer *)g {
    if(g.state!=UIGestureRecognizerStateEnded)return;
    DebugExpanded=!DebugExpanded;
    DebugLayout();
}
- (void)onPan:(UIPanGestureRecognizer *)g {
    CGPoint t=[g translationInView:DebugWindow];
    CGRect f=DebugBubble.frame;
    f.origin.x+=t.x;f.origin.y+=t.y;
    DebugBubble.frame=f;
    [g setTranslation:CGPointZero inView:DebugWindow];
    if(g.state==UIGestureRecognizerStateEnded||g.state==UIGestureRecognizerStateCancelled)DebugLayout();
}
- (void)onLongPress:(UILongPressGestureRecognizer *)g {
    if(g.state!=UIGestureRecognizerStateBegan)return;
    UIPasteboard.generalPasteboard.string=DebugPanel.text?:@"";
    UIColor *was=DebugPanel.backgroundColor;
    DebugPanel.backgroundColor=[UIColor colorWithWhite:1 alpha:.4];
    [UIView animateWithDuration:.3 animations:^{DebugPanel.backgroundColor=was;}];
}
@end
static MWDebugController *DebugController;
static void DebugCreate(void){
    if(DebugWindow)return;
    CGRect screen=UIScreen.mainScreen.bounds;
    UIWindowScene *scene=MainWindowScene();
    DebugWindow=scene?[[MWDebugWindow alloc] initWithWindowScene:scene]:[[MWDebugWindow alloc] initWithFrame:screen];
    DebugWindow.frame=screen;
    DebugWindow.windowLevel=UIWindowLevelAlert+100000;
    DebugWindow.backgroundColor=UIColor.clearColor;
    DebugWindow.hidden=YES;
    DebugBubble=[[UIView alloc] initWithFrame:CGRectMake(screen.size.width-60,screen.size.height-140,44,44)];
    DebugBubble.backgroundColor=[UIColor colorWithWhite:0 alpha:.55];
    DebugBubble.layer.cornerRadius=22;DebugBubble.clipsToBounds=YES;
    DebugCount=[[UILabel alloc] initWithFrame:DebugBubble.bounds];
    DebugCount.textAlignment=NSTextAlignmentCenter;
    DebugCount.textColor=UIColor.whiteColor;
    DebugCount.font=[UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
    DebugCount.text=@"0";DebugCount.userInteractionEnabled=NO;
    [DebugBubble addSubview:DebugCount];
    [DebugWindow addSubview:DebugBubble];
    DebugPanel=[[UITextView alloc] initWithFrame:CGRectZero];
    DebugPanel.backgroundColor=[UIColor colorWithWhite:0 alpha:.85];
    DebugPanel.textColor=UIColor.greenColor;
    DebugPanel.font=[UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    // Not selectable: long-press below copies everything at once, so
    // per-character selection (and the loupe UI that would otherwise
    // contend with our own long-press recognizer for the same gesture)
    // is unneeded. Scrolling is UIScrollView's own pan recognizer and is
    // unaffected by selectable.
    DebugPanel.editable=NO;DebugPanel.selectable=NO;
    DebugPanel.layer.cornerRadius=8;DebugPanel.clipsToBounds=YES;
    DebugPanel.hidden=YES;
    [DebugWindow addSubview:DebugPanel];
    DebugController=[MWDebugController new];
    [DebugBubble addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:DebugController action:@selector(onTap:)]];
    [DebugBubble addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:DebugController action:@selector(onPan:)]];
    [DebugPanel addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:DebugController action:@selector(onLongPress:)]];
}
// Called from Reconcile() on every Tracing transition. Lazily creates the
// overlay once, then only toggles hidden -- history and bubble position
// survive being hidden, so re-enabling tracing does not reset either.
static void DebugSetVisible(BOOL visible){
    if(visible)DebugCreate();
    if(!DebugWindow)return;
    DebugWindow.hidden=!visible;
    if(!visible){DebugExpanded=NO;DebugPanel.hidden=YES;}
}
// 0.13.0-alpha13: make the overlay itself follow the same inversion it
// reports on. Unlike SBSystemApertureWindow, this is a plain UIWindow we
// wrote ourselves -- no private gesture class underneath it reading a fixed
// coordinate space -- so a bare half-turn is the whole fix: UIKit's own
// hit-testing and every gesture recognizer's translationInView:/
// locationInView: already compose correctly with a window transform, which
// is exactly why the pill above needs the rest of this file and this does
// not. Runs every Reconcile tick regardless of Tracing, so the transform is
// already correct by the time DebugCreate() lazily makes the window visible.
static void DebugSetTurned(BOOL turned){
    if(!DebugWindow)return;
    DebugWindow.transform=turned?CGAffineTransformMakeRotation((CGFloat)M_PI):CGAffineTransformIdentity;
}
static void DebugRecord(NSString *line){
    if(!DebugHistory)DebugHistory=[NSMutableArray array];
    [DebugHistory addObject:line];
    if(DebugHistory.count>300)[DebugHistory removeObjectAtIndex:0];
    if(!DebugCount)return;
    DebugCount.text=[NSString stringWithFormat:@"%lu",(unsigned long)DebugHistory.count];
    if(DebugExpanded){
        DebugPanel.text=[DebugHistory componentsJoinedByString:@"\n"];
        [DebugPanel scrollRangeToVisible:NSMakeRange(DebugPanel.text.length,0)];
    }
}

// in/out/inout are Objective-C context-sensitive keywords; name the parameters
// so they cannot be read as parameter qualifiers.
static void LogGestureFix(NSString *api,NSString *cls,CGPoint raw,CGPoint flipped){
    static double last;double now=CACurrentMediaTime();
    if(now-last<=0.05)return;    // a drag calls this many times per frame
    last=now;
    Log([NSString stringWithFormat:@"GESTURE api=%@ class=%@ raw={%.2f,%.2f} turned={%.2f,%.2f}",api,cls,raw.x,raw.y,flipped.x,flipped.y]);
}
static void LogGestureSkip(NSString *api,NSString *cls,UIView *view){
    static double last;double now=CACurrentMediaTime();
    if(now-last<=1)return;
    last=now;
    Log([NSString stringWithFormat:@"GESTURE SKIP api=%@ class=%@ view=%@ reason=outside-turned-root",api,cls,NSStringFromClass(view.class)]);
}
// Negate both axes of a fixed-space delta read inside the turned world. Guard
// non-finite values rather than propagate them, matching how every geometry
// path here fails closed.
static CGPoint TurnDelta(NSString *api,UIGestureRecognizer *self,CGPoint v){
    if(!InvertGestureAxes||!isfinite(v.x)||!isfinite(v.y))return v;
    if(![NSThread isMainThread])return v;
    UIView *view=self.view;
    // The runtime class of self, not just the hooked base class: if a private
    // UIPanGestureRecognizer subclass overrides translationInView:/
    // velocityInView: this hook is bypassed and never logs at all, but when a
    // subclass instance reaches here without overriding, self.class already
    // names it -- no need to guess.
    NSString *cls=NSStringFromClass(self.class);
    if(!InsideTurnedRoot(view)){
        // A recognizer anchored at or above root (on the aperture window
        // itself, say) is out of scope above and corrected nothing -- which
        // on its own is indistinguishable from this hook never being called
        // at all. Say which one happened, so a run where the direction is
        // still wrong points at the right next step instead of at both.
        if(view.window&&[Windows containsObject:view.window])
            LogGestureSkip(api,cls,view);
        return v;
    }
    CGPoint out=CGPointMake(-v.x,-v.y);
    LogGestureFix(api,cls,v,out);
    return out;
}
static CGPoint (*OrigTranslation)(id,SEL,UIView *);
static CGPoint HookTranslation(UIGestureRecognizer *self,SEL cmd,UIView *view){
    return TurnDelta(@"translationInView:",self,OrigTranslation(self,cmd,view));
}
static CGPoint (*OrigVelocity)(id,SEL,UIView *);
static CGPoint HookVelocity(UIGestureRecognizer *self,SEL cmd,UIView *view){
    return TurnDelta(@"velocityInView:",self,OrigVelocity(self,cmd,view));
}
static void InstallGestureFix(void){
    Class pan=objc_getClass("UIPanGestureRecognizer");
    NSArray *args=@[@"@"];
    if(!pan||!Signature(pan,@selector(translationInView:),@encode(CGPoint),args)||
       !Signature(pan,@selector(velocityInView:),@encode(CGPoint),args)){
        InvertGestureAxes=NO;Log(@"NO GESTURE FIX: signature mismatch");return;}
    MSHookMessageEx(pan,@selector(translationInView:),(IMP)HookTranslation,(IMP *)&OrigTranslation);
    MSHookMessageEx(pan,@selector(velocityInView:),(IMP)HookVelocity,(IMP *)&OrigVelocity);
}

// Diagnostic-only touch/gesture trace, added in 0.9.0-alpha9. Off by default;
// toggled at runtime by TracePath, same mechanism as Disabled (see
// Reconcile). It answers directly, rather than by inference, which class is
// actually receiving and interpreting a drag on the island: unlike the
// translationInView:/velocityInView: hooks above, which only ever see calls
// that reach UIPanGestureRecognizer's own implementation, this dumps every
// gesture recognizer attached along a touched view's superview chain --
// including a private subclass that overrides those two methods and so is
// otherwise invisible here.
static NSString *StateName(UIGestureRecognizerState st){
    switch(st){
        case UIGestureRecognizerStatePossible:return @"Possible";
        case UIGestureRecognizerStateBegan:return @"Began";
        case UIGestureRecognizerStateChanged:return @"Changed";
        case UIGestureRecognizerStateEnded:return @"Ended";
        case UIGestureRecognizerStateCancelled:return @"Cancelled";
        case UIGestureRecognizerStateFailed:return @"Failed";
        default:return @"?";
    }
}
static NSString *PhaseName(UITouchPhase ph){
    switch(ph){
        case UITouchPhaseBegan:return @"Began";
        case UITouchPhaseMoved:return @"Moved";
        case UITouchPhaseStationary:return @"Stationary";
        case UITouchPhaseEnded:return @"Ended";
        case UITouchPhaseCancelled:return @"Cancelled";
        default:return @"?";
    }
}
static NSString *RecognizerDump(UIView *v){
    NSMutableArray<NSString *> *out=[NSMutableArray array];
    NSMutableSet *seen=[NSMutableSet set];
    for(unsigned n=0;v&&n++<32;v=v.superview){
        for(UIGestureRecognizer *gr in v.gestureRecognizers){
            if([seen containsObject:gr])continue;
            [seen addObject:gr];
            [out addObject:[NSString stringWithFormat:@"%@(state=%@,touches=%lu)",
                NSStringFromClass(gr.class),StateName(gr.state),(unsigned long)gr.numberOfTouches]];
        }
    }
    return out.count?[out componentsJoinedByString:@","]:@"none";
}
static void TraceTouches(UIWindow *w,UIEvent *e){
    if(!e.allTouches.count)return;
    static double last;double now=CACurrentMediaTime();
    if(now-last<=0.05)return;    // a drag reports many touch batches per frame
    last=now;
    id<UICoordinateSpace> fixed=w.screen.fixedCoordinateSpace;
    for(UITouch *t in e.allTouches){
        CGPoint win=[t locationInView:w];
        CGPoint fx=isfinite(win.x)&&isfinite(win.y)?[w convertPoint:win toCoordinateSpace:fixed]:win;
        Log([NSString stringWithFormat:@"TOUCH phase=%@ window={%.1f,%.1f} fixed={%.1f,%.1f} view=%@ recognizers=%@",
            PhaseName(t.phase),win.x,win.y,fx.x,fx.y,NSStringFromClass(t.view.class),RecognizerDump(t.view)]);
    }
}
// Strictly read-only: calls through to the original sendEvent: FIRST and
// inspects the touches only afterward. UIKit performs its hit test and
// assigns UITouch.view as part of the original implementation's own work, so
// reading before calling through would see a touch's view before it exists.
// Nothing here can change dispatch order, hit-testing, or any return value.
static void (*WindowSendEvent)(id,SEL,UIEvent *);
static void WindowHookSendEvent(UIWindow *s,SEL c,UIEvent *e){
    WindowSendEvent(s,c,e);
    if(Tracing)TraceTouches(s,e);
}

// 0.11.0-alpha11: the TOUCH trace above named the real class handling pill
// drags -- SBSystemApertureLongPressGestureRecognizer, not any
// UIPanGestureRecognizer subclass. That single fact already explains why
// alpha7's read-only probe on UIPanGestureRecognizer's translationInView:/
// velocityInView: logged nothing, and it means alpha8's negation of those
// same two methods was hooking the wrong class -- it cannot have touched
// the real swipe-direction bug. This does for the newly-named classes what
// alpha5/6 did for MangoPillManager: list what each one actually defines,
// so the next step is reading real method names instead of guessing again.
static void LogOwnMethods(Class start,NSString *label){
    if(!start){Log([NSString stringWithFormat:@"CLASSDUMP %@ not-loaded",label]);return;}
    NSMutableArray<NSString *> *lines=[NSMutableArray array];
    Class c=start;
    for(unsigned n=0;c&&n++<8;c=class_getSuperclass(c)){
        const char *name=class_getName(c);
        if(!strncmp(name,"NS",2)||!strncmp(name,"UI",2)||!strncmp(name,"OS_",3))break;
        unsigned count=0;
        Method *methods=class_copyMethodList(c,&count);
        for(unsigned i=0;i<count;i++)
            [lines addObject:[NSString stringWithFormat:@"%s.%s",name,sel_getName(method_getName(methods[i]))]];
        free(methods);
    }
    Log([NSString stringWithFormat:@"CLASSDUMP %@ methods=%@",label,lines.count?[lines componentsJoinedByString:@","]:@"none"]);
}
// Read-only probe of the one position API every UIGestureRecognizer
// subclass responds to regardless of its own class -- locationInView:/
// locationOfTouch:inView:, both defined on the UIGestureRecognizer base
// class, unlike translationInView:/velocityInView: which only
// UIPanGestureRecognizer has. Hooked specifically on
// SBSystemApertureLongPressGestureRecognizer (MSHookMessageEx scopes the
// override to this one class even though the real implementation is
// inherited, the same technique already used elsewhere in this file for
// setFrame:/setBounds:/setCenter:/setTransform: on PassClass/ContentClass/
// WindowClass). Calls through unmodified and only logs -- unlike TurnDelta,
// this makes no claim yet about what a fix here would even mean.
static void LogLongPressProbe(NSString *api,CGPoint p,NSString *state){
    // Unlike TurnDelta's own callers, nothing upstream of this one already
    // checked the thread -- and Log() now unconditionally touches the debug
    // overlay's UILabel/UITextView, which is not thread-safe.
    if(![NSThread isMainThread])return;
    static double last;double now=CACurrentMediaTime();
    if(now-last<=0.05)return;    // a drag calls this many times per frame
    last=now;
    Log([NSString stringWithFormat:@"LPROBE api=%@ point={%.2f,%.2f} state=%@",api,p.x,p.y,state]);
}
static CGPoint (*OrigLongPressLocation)(id,SEL,UIView *);
static CGPoint HookLongPressLocation(UIGestureRecognizer *self,SEL cmd,UIView *view){
    CGPoint p=OrigLongPressLocation(self,cmd,view);
    LogLongPressProbe(@"locationInView:",p,StateName(self.state));
    return p;
}
static CGPoint (*OrigLongPressTouchLocation)(id,SEL,NSUInteger,UIView *);
static CGPoint HookLongPressTouchLocation(UIGestureRecognizer *self,SEL cmd,NSUInteger idx,UIView *view){
    CGPoint p=OrigLongPressTouchLocation(self,cmd,idx,view);
    LogLongPressProbe(@"locationOfTouch:inView:",p,StateName(self.state));
    return p;
}
static void InstallLongPressProbe(void){
    Class cls=objc_getClass("SBSystemApertureLongPressGestureRecognizer");
    LogOwnMethods(cls,@"SBSystemApertureLongPressGestureRecognizer");
    LogOwnMethods(objc_getClass("_SAUIPortalView"),@"_SAUIPortalView");
    if(!cls)return;
    NSArray *viewArg=@[@"@"];
    if(Signature(cls,@selector(locationInView:),@encode(CGPoint),viewArg))
        MSHookMessageEx(cls,@selector(locationInView:),(IMP)HookLongPressLocation,(IMP *)&OrigLongPressLocation);
    else Log(@"NO LPROBE: locationInView: signature mismatch");
    NSArray *touchArgs=@[@(@encode(NSUInteger)),@"@"];
    if(Signature(cls,@selector(locationOfTouch:inView:),@encode(CGPoint),touchArgs))
        MSHookMessageEx(cls,@selector(locationOfTouch:inView:),(IMP)HookLongPressTouchLocation,(IMP *)&OrigLongPressTouchLocation);
    else Log(@"NO LPROBE: locationOfTouch:inView: signature mismatch");
}
#define INSTALL_HOOKS(C,P) \
MSHookMessageEx(C,@selector(layoutSubviews),(IMP)P##HookLayout,(IMP *)&P##Layout); \
MSHookMessageEx(C,@selector(setFrame:),(IMP)P##HookFrame,(IMP *)&P##Frame); \
MSHookMessageEx(C,@selector(setBounds:),(IMP)P##HookBounds,(IMP *)&P##Bounds); \
MSHookMessageEx(C,@selector(setCenter:),(IMP)P##HookCenter,(IMP *)&P##Center)
#define INSTALL_TRANSFORM_HOOK(C,P) \
MSHookMessageEx(C,@selector(setTransform:),(IMP)P##HookTransform,(IMP *)&P##Transform)
static void Install(void){
    if(Installed||access(Disabled,F_OK)==0)return;
    NSOperatingSystemVersion os=NSProcessInfo.processInfo.operatingSystemVersion;
    if(os.majorVersion!=16||os.minorVersion!=5||os.patchVersion!=0){Log(@"NO HOOKS: restricted to iOS 16.5");return;}
    WindowClass=objc_getClass("SBSystemApertureWindow");PassClass=objc_getClass("SBFTouchPassThroughView");
    ContentClass=objc_getClass("_SBSystemApertureContainerViewContentView");ContainerClass=objc_getClass("SBSystemApertureContainerView");
    if(!WindowClass||!PassClass||!ContentClass||!ContainerClass||!VerifiedMango()){
        if(++Attempts<40)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{Install();});
        else Log(@"NO HOOKS: matching Mango UUID/classes unavailable or conflicting Fix loaded");return;}
    if(!ValidClass(WindowClass,UIWindow.class)||!ValidClass(PassClass,UIView.class)||!ValidClass(ContentClass,UIView.class))return;
    for(Class c in @[WindowClass,PassClass,ContentClass]){
        if(!Signature(c,@selector(layoutSubviews),"v",@[])||
           !Signature(c,@selector(setFrame:),"v",@[@(@encode(CGRect))])||
           !Signature(c,@selector(setBounds:),"v",@[@(@encode(CGRect))])||
           !Signature(c,@selector(setCenter:),"v",@[@(@encode(CGPoint))])||
           !Signature(c,@selector(setTransform:),"v",@[@(@encode(CGAffineTransform))])){Log(@"NO HOOKS: geometry signature mismatch");return;}}
    NSArray *hitArgs=@[@(@encode(CGPoint)),@"@"];
    if(!Signature(WindowClass,@selector(hitTest:withEvent:),"@",hitArgs)||!Signature(WindowClass,@selector(pointInside:withEvent:),@encode(BOOL),hitArgs)){Log(@"NO HOOKS: touch signature mismatch");return;}
    if(!Signature(WindowClass,@selector(sendEvent:),"v",@[@"@"])){Log(@"NO HOOKS: sendEvent signature mismatch");return;}
    Roots=[NSHashTable weakObjectsHashTable];Windows=[NSHashTable weakObjectsHashTable];Enabled=YES;Installed=YES;
    INSTALL_HOOKS(PassClass,Pass);INSTALL_HOOKS(ContentClass,Content);INSTALL_HOOKS(WindowClass,Window);
    INSTALL_TRANSFORM_HOOK(PassClass,Pass);INSTALL_TRANSFORM_HOOK(WindowClass,Window);
    MSHookMessageEx(ContentClass,@selector(setTransform:),(IMP)ContentHookTransform,(IMP *)&ContentTransform);
    MSHookMessageEx(WindowClass,@selector(hitTest:withEvent:),(IMP)HookHit,(IMP *)&OrigHit);
    MSHookMessageEx(WindowClass,@selector(pointInside:withEvent:),(IMP)HookInside,(IMP *)&OrigInside);
    MSHookMessageEx(WindowClass,@selector(sendEvent:),(IMP)WindowHookSendEvent,(IMP *)&WindowSendEvent);
    [NSNotificationCenter.defaultCenter addObserverForName:@"MangoInterfaceOrientationDidChange" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){Reconcile();dispatch_async(dispatch_get_main_queue(),^{Reconcile();});}];
    Timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(Timer,dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),250*NSEC_PER_MSEC,50*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(Timer,^{Reconcile();if(!Enabled)dispatch_source_cancel(Timer);});dispatch_resume(Timer);
    InstallGestureFix();
    InstallLongPressProbe();
    Log(@"INSTALLED World 0.13.0-alpha13: window turn + content normalization + skip reasons + gesture delta turn + window hit fallback + touch/gesture trace + floating trace overlay (all log lines, now itself turned) + long-press class probe + other-window inversion probe");Reconcile();
}
__attribute__((constructor)) static void StartWorld(void){@autoreleasepool{dispatch_async(dispatch_get_main_queue(),^{Install();});}}
