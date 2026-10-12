// MangoSuite Beta9 aperture orientation module; see ADAPTATION.md.
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
#include "WorldPersistence.h"
#include "RecoveryPolicy.h"
#import "../../src/RuntimeDiagnostics.h"
#import "../../src/RuntimeSettings.h"

static const char *Disabled="/var/mobile/Library/Preferences/MangoUpsideDownWorld.disabled";
static Class WindowClass, PassClass, ContentClass, ContainerClass;
static NSHashTable<UIWindow *> *Windows;
static NSHashTable<UIView *> *Roots;
static BOOL Enabled, Installed, Busy;
static unsigned Depth, Attempts, HitDepth;
static dispatch_source_t Timer;
static char StateKey;
#import "Beta9Identity.h"
#import "PanCorrection.h"
#import "PillProxy.h"
#include <errno.h>
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
@property(nonatomic) CGRect suspendedBounds;
@property(nonatomic) double lastLog, lastSkipLog;
@property(nonatomic,copy) NSString *lastSkip;
@property(nonatomic,copy) NSString *diagnosticSignature, *diagnosticRestoreReason;
@property(nonatomic) double diagnosticSampleTime, diagnosticLogTime, diagnosticRestoreTime;
@end
@implementation MWWorldState
@end


static void Log(NSString *s) {
    NSLog(@"[MangoSuiteWorld] %@", s);
    MSDiagnosticsLog(@"World",s);
    if (!MSDiagnosticsActive()) return;
    const char *mappedPath = jbroot("/var/mobile/Library/Logs/MangoUpsideDownWorld.log");
    if (!mappedPath) return;
    NSString *path = [NSString stringWithUTF8String:mappedPath];
    const char *directory = jbroot("/var/mobile/Library/Logs");
    if (!path || !directory) return;
    mkdir(directory, 0755);
    int fd = open(path.fileSystemRepresentation, O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW, 0600);
    if (fd < 0) return;
    struct stat st;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode)) { close(fd); return; }
    if (st.st_size > 512*1024) ftruncate(fd, 0);
    NSData *data = [[NSString stringWithFormat:@"%.3f %@\n", NSDate.timeIntervalSinceReferenceDate, s]
                   dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *cursor = data.bytes; size_t left = data.length;
    while (left) {
        ssize_t count = write(fd, cursor, left);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        cursor += count; left -= (size_t)count;
    }
    close(fd);
}
static MWTransform Math(CGAffineTransform t){return (MWTransform){t.a,t.b,t.c,t.d,t.tx,t.ty};}
static CGAffineTransform CG(MWTransform t){return CGAffineTransformMake(t.a,t.b,t.c,t.d,t.tx,t.ty);}
static MWWorldState *State(UIView *v){return objc_getAssociatedObject(v,&StateKey);}
static MWTransform FixedMap(UIView *view);
static BOOL KeepsWorld(UIView *root, MWWorldState *state, UIWindow *window);
// The cancellation record for this content view, created on demand. Returns it
// only while the window above this view's root is actually turned (s.outer is
// the window's owned transform; see ApplyWorld): that turn is what makes an
// inverted content value render upside-down, so it is also the exact
// condition under which normalizing an incoming value is correct.
static MWOwnedTransform *OwnedContent(UIView *v){
    for(UIView *p=v.superview;p;p=p.superview){
        MWWorldState *s=State(p);
        if(!s)continue;
        if(!KeepsWorld(p,s,v.window))return nil;
        MWOwnedTransform *owned=[s.inner objectForKey:v];
        if(!owned){owned=[MWOwnedTransform new];[s.inner setObject:owned forKey:v];}
        return owned;
    }
    return nil;
}
static NSInteger Orientation(void) {
    static double lastInverted=-INFINITY;
    NSInteger value = B9Orientation();
    if (MSRuntimeFlag(@"IslandLayoutEnabled")) return MSRecoverOrientation(value,MSNativeInversionRequested(),CACurrentMediaTime(),&lastInverted);
    return value;
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
    // An external owner is allowed to replace its value. Relinquish our record
    // without writing the stale baseline; future application still has to pass
    // every physical-shape and basis guard. A routine layout reset must not
    // permanently disable the island and its gesture compensation.
    if(!ok)Log(@"RELEASE external transform preserved; waiting for valid world geometry");
}
static NSString *DiagnosticTransform(CGAffineTransform t) {
    return [NSString stringWithFormat:@"(%.3f,%.3f,%.3f,%.3f,%.1f,%.1f)",t.a,t.b,t.c,t.d,t.tx,t.ty];
}
static void RestoreWorldReason(UIView *root, NSString *reason) {
    // Observe the existing restore; neither its guard nor its writes change.
    NSString *before=nil;
    MWWorldState *state=State(root);
    @try {
        double now=CACurrentMediaTime();
        if(MSDiagnosticsActive() && state.outer.applied &&
           (![state.diagnosticRestoreReason isEqualToString:reason] || now-state.diagnosticRestoreTime>=1.0)) {
            state.diagnosticRestoreReason=reason;state.diagnosticRestoreTime=now;
            before=[NSString stringWithFormat:@"RESTORE reason=%@ root=%p parent=%p ownedBefore=%@ ownedAfter=%@ modelBefore=%@ matchedBefore=%d",
                reason,(__bridge void *)root,(__bridge void *)state.parent,DiagnosticTransform(state.outer.before),
                DiagnosticTransform(state.outer.after),state.parent ? DiagnosticTransform(state.parent.transform) : @"nil",
                state.parent && MWNear(Math(state.parent.transform),Math(state.outer.after))];
        }
    } @catch (__unused NSException *exception) {}
    RestoreWorld(root);
    if(before) @try {
        MSDiagnosticsLog(@"World",[before stringByAppendingFormat:@" appliedAfter=%d modelAfter=%@",state.outer.applied,state.parent ? DiagnosticTransform(state.parent.transform) : @"nil"]);
    } @catch (__unused NSException *exception) {}
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
    Log([NSString stringWithFormat:@"SKIP reason=%@ mangoOrientation=%ld systemOrientation=%ld resolvedOrientation=%ld",
         reason,(long)B9MangoOrientation(),(long)B9SystemOrientation(),(long)Orientation()]);
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
    if(s.parent!=w){RestoreWorldReason(root,@"parent-changed");s.parent=w;}
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
    // Turn the aperture window around the physical screen center, so its
    // contents and normal UIKit hit testing share one transformed space.
    // This does not by itself repair Mango's Ended up/down action semantics;
    // that correction is separately scoped to this owned window below.
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
        RestoreWorldReason(root,@"post-transform-verification");s.suspended=YES;s.suspendedBounds=root.bounds;Log(@"SUSPEND post-transform verification failed");return;
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
static MWTransform FixedMap(UIView *view) {
    id<UICoordinateSpace> fixed=view.window.screen.fixedCoordinateSpace;
    if([view isKindOfClass:UIWindow.class])fixed=((UIWindow *)view).screen.fixedCoordinateSpace;
    if(!fixed)return (MWTransform){NAN,NAN,NAN,NAN,NAN,NAN};
    CGPoint o=[view convertPoint:CGPointZero toCoordinateSpace:fixed];
    CGPoint x=[view convertPoint:CGPointMake(1,0) toCoordinateSpace:fixed];
    CGPoint y=[view convertPoint:CGPointMake(0,1) toCoordinateSpace:fixed];
    return (MWTransform){x.x-o.x,x.y-o.y,y.x-o.x,y.y-o.y,o.x,o.y};
}
static BOOL KeepsWorld(UIView *root, MWWorldState *state, UIWindow *window) {
    return window && state && root.superview==window && state.parent==window &&
        MWKeepWorld(Math(window.transform),Math(state.outer.after),state.outer.applied,
                    state.suspended,FixedMap(window),FixedMap(root));
}
static void PillStatus(void);
static void DockStatus(void);
static void DockSync(void);
static void ShieldUpdate(void);
static BOOL ShieldVisible(void);
static void ReconcileRoot(UIView *root) {
    MWWorldState *state=State(root);UIWindow *window=root.window;
    if (state.suspended && MSRuntimeFlag(@"IslandLayoutEnabled") &&
        (!CGRectEqualToRect(root.bounds,state.suspendedBounds) || state.parent!=window)) state.suspended=NO;
    if(KeepsWorld(root,state,window)){
        // Leave stable native media/notification layouts in their corrected
        // coordinate space. Only newly attached native inverted contents need
        // normalization; the setters already handle later animation targets.
        NSArray<UIView *> *contents=Contents(root);
        if(!contents){Skip(state,@"content-hierarchy-transition");return;}
        for(UIView *view in contents)
            for(UIView *parent=view.superview;parent && parent!=root;parent=parent.superview)
                if([parent isKindOfClass:ContentClass]){
                    RestoreWorldReason(root,@"nested-content");Skip(state,@"nested-content");return;
                }
        for(UIView *view in contents){
            MWTransform map=FixedMap(view),value=Math(view.transform);
            if(MWInvertedBasis(-map.a,-map.d,map.c,map.b) && MWFinite(value) &&
               MWInvertedBasis(value.a,value.d,value.c,value.b)){
                MWOwnedTransform *owned=[state.inner objectForKey:view];
                if(!owned){owned=[MWOwnedTransform new];[state.inner setObject:owned forKey:view];}
                SetOwned(view,owned,CG(MWCancelTurn(value)));
                MWTransform actual=FixedMap(view);
                if(!MWInvertedBasis(actual.a,actual.d,actual.c,actual.b)){
                    RestoreOne(view,owned);
                    Skip(state,@"new-content-normalization");
                }
            }
        }
        return;
    }
    RestoreWorldReason(root,@"world-ownership-or-basis-lost");
    ApplyWorld(root);
}
static void DiagnosticWorldScan(BOOL read, NSInteger decision) {
    if(!MSDiagnosticsActive())return;
    @try {
        double now=CACurrentMediaTime();unsigned sampled=0;
        for(UIView *root in Roots.allObjects) {
            if(sampled++>=8)break;
            MWWorldState *state=State(root);
            if(!state || now-state.diagnosticSampleTime<1.0)continue;
            state.diagnosticSampleTime=now;
            NSMutableString *body=[NSMutableString stringWithFormat:
                @"STATE enabled=%d decisionRead=%d decisionResolved=%ld sampleMango=%ld sampleSystem=%ld roots=%lu rootsCap=8 depth=%u busy=%d applied=%d suspended=%d keepsWorldSample=%d parent=%p ownedBefore=%@ ownedAfter=%@ innerCount=%lu lastSkip=%@ pixels-visible=unknown\nroot %@\nwindow %@",
                Enabled,read,(long)decision,(long)B9MangoOrientation(),(long)B9SystemOrientation(),(unsigned long)Roots.count,
                Depth,Busy,state.outer.applied,state.suspended,KeepsWorld(root,state,root.window),(__bridge void *)state.parent,
                DiagnosticTransform(state.outer.before),DiagnosticTransform(state.outer.after),(unsigned long)state.inner.count,
                state.lastSkip ?: @"none",MSDiagnosticsViewLine(root),MSDiagnosticsViewLine(root.window)];
            unsigned contents=0;
            for(UIView *view in state.inner.keyEnumerator) {
                if(contents++>=4)break;
                MWOwnedTransform *owned=[state.inner objectForKey:view];
                NSString *line=[NSString stringWithFormat:@"\ncontent applied=%d matched=%d before=%@ after=%@ %@",
                    owned.applied,MWNear(Math(view.transform),Math(owned.after)),DiagnosticTransform(owned.before),
                    DiagnosticTransform(owned.after),MSDiagnosticsViewLine(view)];
                if(body.length+line.length>7500){[body appendString:@"\n[content-budget-truncated]"];break;}
                [body appendString:line];
            }
            [body appendFormat:@"\ncontentCap=4 contentTotal=%lu",(unsigned long)state.inner.count];
            if([state.diagnosticSignature isEqualToString:body] && now-state.diagnosticLogTime<10.0)continue;
            state.diagnosticSignature=body;state.diagnosticLogTime=now;
            MSDiagnosticsLog(@"World",body);
        }
    } @catch (__unused NSException *exception) {}
}
static void Reconcile(void) {
    if (Busy || Depth || !NSThread.isMainThread) return;
    Busy = YES;
    __block BOOL decisionRead=NO;
    __block NSInteger decision=0;
    @try {
        [UIView performWithoutAnimation:^{
            if (Enabled && B9Disabled(Disabled)) { Enabled = NO; Log(@"DISABLED restored owned transforms"); }
            if (!Enabled || (decisionRead=YES, decision=Orientation()) != UIInterfaceOrientationPortraitUpsideDown) {
                for (UIView *root in Roots.allObjects) RestoreWorldReason(root,!Enabled ? @"disabled" : @"resolved-orientation-not-2");
                return;
            }
            for (UIWindow *w in ExistingWindows()) Discover(w);
            for (UIWindow *w in Windows.allObjects) Discover(w);
            for (UIView *root in Roots.allObjects) ReconcileRoot(root);
        }];
    } @finally { Busy = NO; DiagnosticWorldScan(decisionRead,decision); PillStatus(); DockSync(); ShieldUpdate(); DockStatus(); }
}
static BOOL Relevant(UIView *v){
    if([v isKindOfClass:WindowClass])return YES;
    if(State(v))return YES;
    return [v isKindOfClass:ContentClass]&&[v.window isKindOfClass:WindowClass];
}
static BOOL Begin(UIView *v){
    if(Busy||![NSThread isMainThread]||!Relevant(v))return NO;
    if(Depth++==0){
        // Root/content geometry is expressed inside the already turned window.
        // Keep that space stable while Mango's position/size slider writes it.
        if (MSRuntimeFlag(@"IslandLayoutEnabled") && ![v isKindOfClass:WindowClass]) {
            for (UIView *root in Roots.allObjects)
                if (root.window == v.window && KeepsWorld(root, State(root), root.window)) return YES;
        }
        Busy=YES;
        @try{[UIView performWithoutAnimation:^{for(UIView *root in Roots.allObjects)RestoreWorldReason(root,@"geometry-setter");}];}
        @finally{Busy=NO;}}
    return YES;
}
static BOOL BeginLayout(UIView *view){
    if(Busy || !NSThread.isMainThread || !Relevant(view))return NO;
    // A pure layout pass must keep the animation's corrected model endpoint.
    // Nested geometry setters share this transaction and defer reconciliation,
    // rather than briefly committing the native inverted target to the model.
    ++Depth;
    return YES;
}
static void End(BOOL begun){if(begun&&--Depth==0)Reconcile();}

// Public UIView methods hooked only on the three evidenced private subclasses.
// Separate originals avoid cross-class recursion when a method is inherited.
#define DEFINE_HOOKS(P) \
static void (*P##Layout)(id,SEL); \
static void P##HookLayout(id s,SEL c){BOOL b=BeginLayout(s);@try{P##Layout(s,c);if(!Busy&&[NSThread isMainThread]&&[s isKindOfClass:WindowClass])Discover(s);}@finally{End(b);}} \
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
    if(!Enabled||Busy||Depth||![NSThread isMainThread]||HitDepth||B9Disabled(Disabled))return nil;
    ++HitDepth;
    @try {
    for(UIView *root in w.subviews.reverseObjectEnumerator){
        MWWorldState *s=State(root);
        if(!KeepsWorld(root,s,w)||!VisibleChain(root,w))continue;
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
static BOOL VerifiedMango(void) { return !B9LegacyOrientationLoaded() && B9VerifiedMango(); }

// Beta9 Hello still treats orientations 1/2 as the same portrait branch and
// consumes uncorrected Ended translation.y. Preserve World 1.2.0's narrow
// correction only for a view beneath a window World actually turned itself.
static BOOL OwnsGestureWindow(UIView *view) {
    UIWindow *window = view.window;
    if (![window isKindOfClass:WindowClass]) return NO;
    for (UIView *root in Roots.allObjects) {
        MWWorldState *state = State(root);
        if (root.superview == window && state.parent == window &&
            KeepsWorld(root,state,window) &&
            (view == window || view == root || [view isDescendantOfView:root])) return YES;
    }
    return NO;
}
static void (*OriginalMangoPan)(id, SEL, id);
static void (*OriginalPillPan)(id, SEL, id);
static CGPoint (*OriginalTranslation)(id,SEL,UIView *), (*OriginalVelocity)(id,SEL,UIView *);
static __weak id ScopedPan;
static unsigned PanDepth;
static BOOL PanInstalled;
static unsigned PanAttempts;
static CGPoint HookTranslation(id gesture,SEL selector,UIView *view) {
    CGPoint value=OriginalTranslation(gesture,selector,view);
    return MSB9PanQueryValue(value,gesture,ScopedPan,PanDepth,NSThread.isMainThread);
}
static CGPoint HookVelocity(id gesture,SEL selector,UIView *view) {
    CGPoint value=OriginalVelocity(gesture,selector,view);
    return MSB9PanQueryValue(value,gesture,ScopedPan,PanDepth,NSThread.isMainThread);
}
static void RunMangoPan(id controller, SEL selector, UIPanGestureRecognizer *gesture, void (*original)(id,SEL,id)) {
    if (!MSRuntimeFlag(@"SwipeDirectionEnabled") || !NSThread.isMainThread || PanDepth || !Enabled || Busy || Depth || B9Disabled(Disabled) ||
        ![gesture isKindOfClass:UIPanGestureRecognizer.class] ||
        gesture.state != UIGestureRecognizerStateEnded) {
        original(controller, selector, gesture); return;
    }
    UIView *view = gesture.view;
    MWTransform map=FixedMap(view);
    NSInteger raw=0;BOOL owned=NO,inverted=NO,upright=NO;
    owned=OwnsGestureWindow(view);
    BOOL target=[view.window isKindOfClass:WindowClass] && !view.window.hidden;
    inverted=MWInvertedBasis(map.a,map.d,map.c,map.b);
    upright=MWUprightBasis(map.a,map.d,map.c,map.b);
    BOOL correction=MSB10PanNeedsFlip(raw=Orientation(),upright);
    if(MSDiagnosticsActive()) @try {
        MSDiagnosticsLog(@"World",[NSString stringWithFormat:@"PAN ended entry=%@ view=%p window=%p windowClass=%@ resolvedDirection=%ld apertureTarget=%d actualOwned=%d actualViewInverted=%d actualViewUpright=%d correction=%d",NSStringFromSelector(selector),(__bridge void *)view,(__bridge void *)view.window,NSStringFromClass(view.window.class),(long)raw,target,owned,inverted,upright,correction]);
    } @catch (__unused NSException *exception) {}
    if(!correction){
        original(controller,selector,gesture);return;
    }
    CGPoint before = [gesture translationInView:view];
    if (!isfinite(before.x) || !isfinite(before.y)) {
        original(controller, selector, gesture); return;
    }
    // Correct both Ended queries without changing recognizer state. Native
    // callbacks may consume velocity as well as translation. Other gestures,
    // horizontal movement and Began/Changed drag behavior pass through.
    MSB9RunPanQueries(gesture,^{ original(controller,selector,gesture); },&ScopedPan,&PanDepth);
}
static void HookMangoPan(id controller,SEL selector,UIPanGestureRecognizer *gesture) { RunMangoPan(controller,selector,gesture,OriginalMangoPan); }
// The pill's handler reads one Ended translation.y. It was previously installed
// only after the resize-pan entry matched, so a missing resize entry left it
// unfixed. Install it independently and substitute the gesture argument instead
// of mutating the recognizer or hooking UIPanGestureRecognizer.
static BOOL PillPanInstalled;
static unsigned PillPanAttempts;
static void HookPillPan(id controller,SEL selector,UIPanGestureRecognizer *gesture) {
    id argument=gesture;
    @try {
        BOOL isPan=[gesture isKindOfClass:UIPanGestureRecognizer.class];
        BOOL ended=isPan && gesture.state==UIGestureRecognizerStateEnded;
        if (ended && NSThread.isMainThread) {
            BOOL flag=MSRuntimeFlag(@"SwipeDirectionEnabled"), disabled=B9Disabled(Disabled);
            BOOL gates=flag && !PanDepth && Enabled && !Busy && !Depth && !disabled;
            UIView *view=gesture.view;
            MWTransform map=FixedMap(view);
            NSInteger raw=Orientation();
            BOOL target=[view.window isKindOfClass:WindowClass] && !view.window.hidden;
            BOOL inverted=MWInvertedBasis(map.a,map.d,map.c,map.b);
            BOOL upright=MWUprightBasis(map.a,map.d,map.c,map.b);
            BOOL correction=gates && MSB10PanNeedsFlip(raw,upright);
            CGPoint local=correction ? [gesture translationInView:view] : CGPointZero;
            BOOL usable=correction && isfinite(local.x) && isfinite(local.y);
            if(MSDiagnosticsActive()) MSDiagnosticsLog(@"World",[NSString stringWithFormat:@"PAN pill-ended gates=%d flag=%d panDepth=%u enabled=%d busy=%d depth=%u disabled=%d direction=%ld window=%@ apertureTarget=%d viewInverted=%d viewUpright=%d map=(%.3f,%.3f,%.3f,%.3f) used=%d localY=%.2f handlerY=%.2f",gates,flag,PanDepth,Enabled,Busy,Depth,disabled,(long)raw,NSStringFromClass(view.window.class),target,inverted,upright,map.a,map.b,map.c,map.d,usable,usable ? local.y : 0,usable ? -local.y : 0]);
            if (usable) argument=MWPillProxy(gesture,CGPointMake(local.x,-local.y));
        }
    } @catch (__unused NSException *exception) { argument=gesture; }
    OriginalPillPan(controller,selector,argument);
}
// Written once per diagnostic session: without it a missing hook and a hook
// that never fires look identical in the log.
static void PillStatus(void) {
    static double session;
    double current=[MSRuntimeSettings()[@"DebugSessionToken"] doubleValue];
    if (!MSDiagnosticsActive() || session==current) return;
    session=current;
    MSDiagnosticsLog(@"World",[NSString stringWithFormat:@"PAN status pillInstalled=%d pillAttempts=%u resizeInstalled=%d resizeAttempts=%u worldEnabled=%d",PillPanInstalled,PillPanAttempts,PanInstalled,PanAttempts,Enabled]);
}
static void InstallPillPan(void) {
    if(PillPanInstalled || !Enabled || B9Disabled(Disabled))return;
    Class pill=objc_getClass("MangoPillElement");
    SEL pillPan=sel_registerName("handlePanGesture:");
    if (B9ClassIsHello(pill) && Signature(pill,pillPan,"v",@[@"@"]) && B9IMPIsHello(class_getMethodImplementation(pill,pillPan))) {
        MSHookMessageEx(pill,pillPan,(IMP)HookPillPan,(IMP *)&OriginalPillPan);
        PillPanInstalled=YES;
        Log([NSString stringWithFormat:@"Pill ended-pan proxy installed attempt=%u",PillPanAttempts]);
        return;
    }
    if(++PillPanAttempts<40)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{InstallPillPan();});
    else Log(@"Pill pan unavailable after 20s: MangoHello MangoPillElement handler absent or wrapped");
}
static void InstallMangoPan(void) {
    if(PanInstalled || !Enabled || B9Disabled(Disabled))return;
    Class controller = objc_getClass("SBSystemApertureViewController");
    SEL selector = sel_registerName("_handleResizePan:");
    if (!controller || !Signature(controller, selector, "v", @[@"@"]) ||
        !B9IMPIsHello(class_getMethodImplementation(controller, selector))) {
        if(++PanAttempts<40)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{InstallMangoPan();});
        else Log(@"Pan correction unavailable after 20s: MangoHello resize-pan hook absent or wrapped");
        return;
    }
    if (!Signature(UIPanGestureRecognizer.class,@selector(translationInView:),@encode(CGPoint),@[@"@"]) ||
        !Signature(UIPanGestureRecognizer.class,@selector(velocityInView:),@encode(CGPoint),@[@"@"])) {
        Log(@"Pan query ABI mismatch; correction skipped"); return;
    }
    MSHookMessageEx(UIPanGestureRecognizer.class,@selector(translationInView:),(IMP)HookTranslation,(IMP *)&OriginalTranslation);
    MSHookMessageEx(UIPanGestureRecognizer.class,@selector(velocityInView:),(IMP)HookVelocity,(IMP *)&OriginalVelocity);
    MSHookMessageEx(controller, selector, (IMP)HookMangoPan, (IMP *)&OriginalMangoPan);
    PanInstalled=YES;
    Log(@"Owned-window ended-pan correction installed (vertical translation only)");
}
static Class OrientationLockClass;
static BOOL OrientationLockFixOK=YES;
static SEL LockWithArgSel;
static void (*OrigLockNoArg)(id,SEL);
static void (*OrigLockWithArg)(id,SEL,long long);
// Preserve the viewed upside-down orientation when the user enables the
// normal orientation lock. Other orientations and background callers pass
// through to the original no-argument implementation unchanged.
static void HookLockNoArg(id self,SEL cmd){
    if(!NSThread.isMainThread || !OrientationLockFixOK || !Enabled || B9Disabled(Disabled)){OrigLockNoArg(self,cmd);return;}
    if(Orientation()==UIInterfaceOrientationPortraitUpsideDown){
        Log(@"ORIENTATIONLOCK forced-to-upsidedown");
        OrigLockWithArg(self,LockWithArgSel,(long long)UIInterfaceOrientationPortraitUpsideDown);
        return;
    }
    OrigLockNoArg(self,cmd);
}
static void InstallOrientationLockFix(void){
    OrientationLockClass=objc_getClass("SBOrientationLockManager");
    SEL lockSel=sel_registerName("lock");
    LockWithArgSel=sel_registerName("lock:");
    NSArray *longArg=@[@(@encode(long long))];
    if(!OrientationLockClass||
       !Signature(OrientationLockClass,lockSel,"v",@[])||
       !Signature(OrientationLockClass,LockWithArgSel,"v",longArg)){
        OrientationLockFixOK=NO;Log(@"NO ORIENTATION LOCK FIX: signature mismatch");return;}
    OrigLockWithArg=(void (*)(id,SEL,long long))class_getMethodImplementation(OrientationLockClass,LockWithArgSel);
    MSHookMessageEx(OrientationLockClass,lockSel,(IMP)HookLockNoArg,(IMP *)&OrigLockNoArg);
}

// iPad-style floating dock (Lynx 2 "useFloatingDock", i.e. SpringBoard's own
// SBFloatingDock*) versus the notch while SpringBoard is inverted: the dock's
// bottom edge is then the physical top edge, under the iPhone 13 mini's
// sensor housing. Gated live by the DockNotchEnabled repair switch.
//
// Dock (Beta9.9.12, from the Beta9.9.11 device DOCK status): on 16.5 the root
// controller lays out with -_layoutFloatingDockPresentationProgress: (the 14.5
// name -_layoutFloatingDockViewWithProgress: does not exist), and presentation
// is a pure translation on SBFloatingDockView itself -- ty 0 presented, 109
// hidden, 60.3 part-way -- while its position never moves. So the lift goes
// into that same transform: every write SpringBoard makes gets
// NotchHeight*progress more upward translation, inside whatever animation
// block the write is in. Proportional to progress, so the finger travel that
// reaches progress 1 is unchanged and the same swipe lifts further; hidden
// (progress 0), upright, or switched off adds nothing. DockSync() re-writes
// the last SpringBoard value when orientation or the switch changes while
// the dock sits still, so upright is never left lifted.
//
// Notch swipes (Beta9.9.12, from the same log): holding the home gesture's
// bottom-edge region at NotchBand made both SpringBoard edge recognizers stay
// possible for notch-rim touches (stateAfter=0), yet the app under the notch
// still acted first. The app process gates its own gestures only for touches
// that begin at the screen edge, and a touch landing on the notch's lower rim
// is not one; SpringBoard cannot change that gate. Instead a SpringBoard-owned
// strip covers the notch's span down to NotchShieldDepth while inverted with
// an app in front, so touches starting there are routed to SpringBoard and
// reach only the system gestures, never the app. Taps inside that strip are
// therefore not delivered to the app either; the strip is kept as shallow as
// the device log's notch-rim touch-downs (38-47pt) allow.
// Default dock lift: 13 mini housing, 5.35mm at 0.1537mm/pt. User-adjustable
// 0-50pt through the DockNotchLift slider (Beta9.9.13).
static const CGFloat NotchHeight=35;
static const CGFloat NotchBand=50;        // home-edge region while inverted: the 13 mini's notch-side safe-area band
static const CGFloat NotchHalfWidth=95;   // ~26mm (169pt) housing plus finger slack
static const CGFloat NotchShieldDepth=48; // notch-rim touch-downs logged at 38-47pt from the edge
static SEL TouchOrientationSel,EdgeRegionSel,SetEdgeRegionSel,PresentedProgressSel,FrontAppSel;
static Class HomeGestureClass,DockViewClass,DockRootClass;
static NSString *DockInstall=@"not-run",*EdgeInstall=@"not-run";
static unsigned long DockCalls,DockWrites;
static double DockLastProgress=NAN,DockLayoutProgress=NAN;
static char EdgeRegionKey,EdgeNotchKey;
static BOOL DockFixOn(void){return Enabled&&!B9Disabled(Disabled)&&MSRuntimeFlag(@"DockNotchEnabled");}
// Whether v's +y points at the physical top edge, i.e. v's bottom is the notch.
static BOOL DownIsNotch(UIView *v){
    id<UICoordinateSpace> fixed=v.window.screen.fixedCoordinateSpace;
    if(!fixed)return NO;
    CGPoint o=[v convertPoint:CGPointZero toCoordinateSpace:fixed];
    CGPoint d=[v convertPoint:CGPointMake(0,1) toCoordinateSpace:fixed];
    return d.y-o.y<-.5;
}
static void (*OrigDockLayout)(id,SEL,double);
static void HookDockLayout(id self,SEL cmd,double progress){
    double outer=DockLayoutProgress;
    DockLayoutProgress=progress;DockCalls++;DockLastProgress=progress;
    @try{OrigDockLayout(self,cmd,progress);}@finally{DockLayoutProgress=outer;}
}
// The progress a transform write is for: the layout call it happens inside,
// else the root controller's current presented progress.
static double DockProgress(UIView *dock){
    if(isfinite(DockLayoutProgress))return DockLayoutProgress;
    UIViewController *root=dock.window.rootViewController;
    if(PresentedProgressSel&&[root isKindOfClass:DockRootClass])return ((double(*)(id,SEL))objc_msgSend)(root,PresentedProgressSel);
    return NAN;
}
static CGFloat DockLiftFor(UIView *dock){
    if(!DockFixOn()||!DownIsNotch(dock.superview))return 0;
    return MWDockLift(DockProgress(dock),MSRuntimeNumber(@"DockNotchLift",NotchHeight,0,50));
}
static __weak UIView *DockViewRef;
static CGAffineTransform DockIncoming,DockWritten;
static CGFloat DockLastLift;
static void (*OrigDockTransform)(id,SEL,CGAffineTransform);
static void HookDockTransform(UIView *self,SEL cmd,CGAffineTransform t){
    // isKindOfClass: as well, in case the hook landed on an inherited superclass method.
    if(![NSThread isMainThread]||![self isKindOfClass:DockViewClass]||![self.window.rootViewController isKindOfClass:DockRootClass]){OrigDockTransform(self,cmd,t);return;}
    CGFloat lift=DockLiftFor(self);
    CGAffineTransform out=t;out.ty-=lift;
    DockViewRef=self;DockIncoming=t;DockWritten=out;DockLastLift=lift;DockWrites++;
    OrigDockTransform(self,cmd,out);
    static double last;double now=CACurrentMediaTime();
    if(lift>0&&now-last>1){last=now;
        Log([NSString stringWithFormat:@"DOCKLIFT progress=%.2f lift=%.1f ty=%.1f->%.1f",DockProgress(self),lift,t.ty,out.ty]);}
}
static void DockSync(void){
    UIView *dock=DockViewRef;
    if(!dock||!OrigDockTransform)return;
    CGFloat lift=DockLiftFor(dock);
    // Only rewrite our own last value; anything else belongs to SpringBoard.
    if(lift==DockLastLift||!CGAffineTransformEqualToTransform(dock.transform,DockWritten))return;
    CGAffineTransform out=DockIncoming;out.ty-=lift;
    DockWritten=out;DockLastLift=lift;
    [UIView performWithoutAnimation:^{OrigDockTransform(dock,@selector(setTransform:),out);}];
}
static void (*OrigEdgeTouchesBegan)(id,SEL,NSSet *,UIEvent *);
static void HookEdgeTouchesBegan(UIGestureRecognizer *self,SEL cmd,NSSet<UITouch *> *touches,UIEvent *event){
    if(![NSThread isMainThread]||![self isKindOfClass:HomeGestureClass]){OrigEdgeTouchesBegan(self,cmd,touches,event);return;}
    BOOL inverted=((long long(*)(id,SEL))objc_msgSend)(self,TouchOrientationSel)==UIInterfaceOrientationPortraitUpsideDown;
    double current=((double(*)(id,SEL))objc_msgSend)(self,EdgeRegionSel);
    // Only our own last write may be treated as ours; any other value is
    // SpringBoard's fresh base and is what gets handed back when upright.
    NSArray<NSNumber *> *owned=objc_getAssociatedObject(self,&EdgeRegionKey);
    double base=owned&&current==owned[1].doubleValue?owned[0].doubleValue:current;
    double region=inverted&&DockFixOn()?fmax(base,NotchBand):base;
    if(isfinite(region)&&region!=current)((void(*)(id,SEL,double))objc_msgSend)(self,SetEdgeRegionSel,region);
    objc_setAssociatedObject(self,&EdgeRegionKey,@[@(base),@(region)],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UITouch *t=touches.anyObject;CGPoint p=[t locationInView:nil];
    if(t.window)p=[t.window convertPoint:p toCoordinateSpace:UIScreen.mainScreen.fixedCoordinateSpace];
    // A half-turn mirrors x about the center, so the span test holds in fixed
    // and in upside-down screen coordinates alike.
    BOOL notch=inverted&&isfinite(p.x)&&fabs(p.x-CGRectGetMidX(UIScreen.mainScreen.fixedCoordinateSpace.bounds))<=NotchHalfWidth&&p.y<=NotchBand+10;
    objc_setAssociatedObject(self,&EdgeNotchKey,notch?@YES:nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    OrigEdgeTouchesBegan(self,cmd,touches,event);
    if(!notch||!MSDiagnosticsActive())return;
    Log([NSString stringWithFormat:@"HOMEEDGE begin class=%@ point={%.1f,%.1f} region=%.1f->%.1f stateAfter=%ld shield=%d",
        NSStringFromClass(self.class),p.x,p.y,base,region,(long)self.state,ShieldVisible()]);
}
// Read-only outcome of a notch-rim touch: did the home gesture recognize or
// fail, and if it failed, which of UIKit's edge features said so.
static void (*OrigHomeSetState)(id,SEL,UIGestureRecognizerState);
static void HookHomeSetState(UIGestureRecognizer *self,SEL cmd,UIGestureRecognizerState state){
    OrigHomeSetState(self,cmd,state);
    if(![NSThread isMainThread]||(state!=UIGestureRecognizerStateBegan&&state!=UIGestureRecognizerStateFailed)||
       !objc_getAssociatedObject(self,&EdgeNotchKey))return;
    objc_setAssociatedObject(self,&EdgeNotchKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(!MSDiagnosticsActive())return;
    NSString *debug=@"";
    SEL debugSel=NSSelectorFromString(@"debugDictionary");
    if(state==UIGestureRecognizerStateFailed&&[self respondsToSelector:debugSel]){
        id dict=((id(*)(id,SEL))objc_msgSend)(self,debugSel);
        debug=[[dict description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        if(debug.length>1500)debug=[debug substringToIndex:1500];
    }
    Log([NSString stringWithFormat:@"HOMEEDGE result class=%@ state=%@ %@",NSStringFromClass(self.class),
        state==UIGestureRecognizerStateBegan?@"began":@"failed",debug]);
}
// The notch strip: a SpringBoard window whose only hit-testable content is
// the strip, so the render server routes touches there to SpringBoard (and
// its system gestures) instead of to the app; everywhere else stays clear and
// falls through as before.
@interface MSNotchShieldWindow : UIWindow
@end
@implementation MSNotchShieldWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit=[super hitTest:point withEvent:event];
    return hit==self?nil:hit;
}
@end
static MSNotchShieldWindow *ShieldWindow;
static UIView *ShieldStrip;
static NSString *ShieldReason=@"not-run";
static BOOL ShieldVisible(void){return ShieldWindow&&!ShieldWindow.hidden;}
static UIWindowScene *MainWindowScene(void){
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if([scene isKindOfClass:UIWindowScene.class]&&((UIWindowScene *)scene).screen==UIScreen.mainScreen)
            return (UIWindowScene *)scene;
    return nil;
}
static void ShieldUpdate(void){
    NSString *reason=nil;
    if(!DockFixOn())reason=@"switch-off";
    else if(Orientation()!=UIInterfaceOrientationPortraitUpsideDown)reason=@"not-inverted";
    else if(FrontAppSel&&!((id(*)(id,SEL))objc_msgSend)(UIApplication.sharedApplication,FrontAppSel))reason=@"no-front-app";
    ShieldReason=reason?:@"active";
    if(reason){if(ShieldVisible())ShieldWindow.hidden=YES;return;}
    if(!ShieldWindow){
        UIWindowScene *scene=MainWindowScene();
        ShieldWindow=scene?[[MSNotchShieldWindow alloc] initWithWindowScene:scene]:[[MSNotchShieldWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        ShieldWindow.windowLevel=UIWindowLevelStatusBar-1;
        ShieldWindow.backgroundColor=UIColor.clearColor;
        ShieldStrip=[UIView new];
        // Nearly invisible, but real content, which is what the render
        // server's hit test needs; hitTestsAsOpaque says the same where it exists.
        ShieldStrip.backgroundColor=[UIColor colorWithWhite:0 alpha:.011];
        if([ShieldStrip.layer respondsToSelector:NSSelectorFromString(@"setHitTestsAsOpaque:")])
            [ShieldStrip.layer setValue:@YES forKey:@"hitTestsAsOpaque"];
        [ShieldWindow addSubview:ShieldStrip];
    }
    id<UICoordinateSpace> fixed=UIScreen.mainScreen.fixedCoordinateSpace;
    ShieldWindow.frame=UIScreen.mainScreen.bounds;
    CGRect strip=CGRectMake(CGRectGetMidX(fixed.bounds)-NotchHalfWidth,0,2*NotchHalfWidth,NotchShieldDepth);
    CGRect local=[ShieldWindow convertRect:strip fromCoordinateSpace:fixed];
    if(!CGRectEqualToRect(ShieldStrip.frame,local))ShieldStrip.frame=local;
    if(ShieldWindow.hidden)ShieldWindow.hidden=NO;
}
static void DockStatus(void){
    static double lastScan,lastLog;static NSString *lastBody;
    if(!MSDiagnosticsActive())return;
    double now=CACurrentMediaTime();
    if(now-lastScan<2)return;
    lastScan=now;
    @try{
        UIView *dock=DockViewRef;
        NSMutableString *body=[NSMutableString stringWithFormat:@"DOCK status install=%@ edgeInstall=%@ switch=%d layoutCalls=%lu lastProgress=%.2f writes=%lu incomingTy=%.1f writtenTy=%.1f lift=%.1f shield=%@ shieldVisible=%d orientation=%ld",
            DockInstall,EdgeInstall,MSRuntimeFlag(@"DockNotchEnabled"),DockCalls,DockLastProgress,DockWrites,DockIncoming.ty,DockWritten.ty,DockLastLift,ShieldReason,ShieldVisible(),(long)Orientation()];
        if(dock)[body appendFormat:@"\ndockView progress=%.2f superviewInverted=%d %@",DockProgress(dock),DownIsNotch(dock.superview),MSDiagnosticsViewLine(dock)];
        if(ShieldVisible())[body appendFormat:@"\nshieldStrip %@",MSDiagnosticsViewLine(ShieldStrip)];
        if(FrontAppSel){id app=((id(*)(id,SEL))objc_msgSend)(UIApplication.sharedApplication,FrontAppSel);
            [body appendFormat:@"\nfrontApp=%@",app?NSStringFromClass([app class]):@"nil"];}
        NSMutableArray<NSString *> *levels=[NSMutableArray array];
        for(UIWindow *w in ExistingWindows())
            if(!w.hidden&&levels.count<24)[levels addObject:[NSString stringWithFormat:@"%@@%.0f",NSStringFromClass(w.class),w.windowLevel]];
        [body appendFormat:@"\nwindows %@",[levels componentsJoinedByString:@","]];
        if(body.length>7500)[body setString:[body substringToIndex:7500]];
        if([body isEqualToString:lastBody]&&now-lastLog<30)return;
        lastBody=body;lastLog=now;
        MSDiagnosticsLog(@"World",body);
    }@catch(__unused NSException *exception){}
}
static void InstallDockNotchFix(void){
    DockRootClass=objc_getClass("SBFloatingDockRootViewController");
    DockViewClass=objc_getClass("SBFloatingDockView");
    SEL layout=sel_registerName("_layoutFloatingDockPresentationProgress:");
    SEL presented=sel_registerName("presentedProgress");
    FrontAppSel=sel_registerName("_accessibilityFrontMostApplication");
    if(![UIApplication.sharedApplication respondsToSelector:FrontAppSel])FrontAppSel=NULL;
    BOOL hasLayout=DockRootClass&&Signature(DockRootClass,layout,"v",@[@(@encode(double))]);
    if(DockRootClass&&Signature(DockRootClass,presented,@encode(double),@[]))PresentedProgressSel=presented;
    if(!DockRootClass)DockInstall=@"no-root-class";
    else if(!DockViewClass||!ValidClass(DockViewClass,UIView.class)||
            !Signature(DockViewClass,@selector(setTransform:),"v",@[@(@encode(CGAffineTransform))]))DockInstall=@"no-dock-view";
    else if(!hasLayout&&!PresentedProgressSel)DockInstall=@"no-progress-source";
    else{
        if(hasLayout)MSHookMessageEx(DockRootClass,layout,(IMP)HookDockLayout,(IMP *)&OrigDockLayout);
        MSHookMessageEx(DockViewClass,@selector(setTransform:),(IMP)HookDockTransform,(IMP *)&OrigDockTransform);
        DockInstall=hasLayout?@"hooked":@"hooked-presented-only";
    }
    if(![DockInstall hasPrefix:@"hooked"])Log([@"NO DOCK LIFT: " stringByAppendingString:DockInstall]);
    // Hooked on the UIKit base class, where the edge-region test lives, so a
    // home-gesture subclass that overrides touchesBegan: and calls super is
    // still covered; HomeGestureClass scopes it back to home gestures only.
    Class edge=objc_getClass("UIScreenEdgePanGestureRecognizer");
    HomeGestureClass=objc_getClass("SBHomeGesturePanGestureRecognizer");
    TouchOrientationSel=sel_registerName("_touchInterfaceOrientation");
    EdgeRegionSel=sel_registerName("_bottomEdgeRegionSize");
    SetEdgeRegionSel=sel_registerName("_setBottomEdgeRegionSize:");
    if(edge&&HomeGestureClass&&ValidClass(HomeGestureClass,edge)&&
       Signature(edge,@selector(touchesBegan:withEvent:),"v",@[@"@",@"@"])&&
       Signature(HomeGestureClass,TouchOrientationSel,@encode(long long),@[])&&
       Signature(edge,EdgeRegionSel,@encode(double),@[])&&
       Signature(edge,SetEdgeRegionSel,"v",@[@(@encode(double))])){
        MSHookMessageEx(edge,@selector(touchesBegan:withEvent:),(IMP)HookEdgeTouchesBegan,(IMP *)&OrigEdgeTouchesBegan);
        EdgeInstall=@"hooked";
        if(Signature(HomeGestureClass,@selector(setState:),"v",@[@(@encode(UIGestureRecognizerState))]))
            MSHookMessageEx(HomeGestureClass,@selector(setState:),(IMP)HookHomeSetState,(IMP *)&OrigHomeSetState);
    }else{EdgeInstall=@"signature-mismatch";Log(@"NO HOME EDGE FIX: signature mismatch");}
}

#define INSTALL_HOOKS(C,P) \
MSHookMessageEx(C,@selector(layoutSubviews),(IMP)P##HookLayout,(IMP *)&P##Layout); \
MSHookMessageEx(C,@selector(setFrame:),(IMP)P##HookFrame,(IMP *)&P##Frame); \
MSHookMessageEx(C,@selector(setBounds:),(IMP)P##HookBounds,(IMP *)&P##Bounds); \
MSHookMessageEx(C,@selector(setCenter:),(IMP)P##HookCenter,(IMP *)&P##Center)
#define INSTALL_TRANSFORM_HOOK(C,P) \
MSHookMessageEx(C,@selector(setTransform:),(IMP)P##HookTransform,(IMP *)&P##Transform)
static void Install(void){
    if(Installed||B9Disabled(Disabled))return;
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
    Roots=[NSHashTable weakObjectsHashTable];Windows=[NSHashTable weakObjectsHashTable];Enabled=YES;Installed=YES;
    INSTALL_HOOKS(PassClass,Pass);INSTALL_HOOKS(ContentClass,Content);INSTALL_HOOKS(WindowClass,Window);
    INSTALL_TRANSFORM_HOOK(PassClass,Pass);INSTALL_TRANSFORM_HOOK(WindowClass,Window);
    MSHookMessageEx(ContentClass,@selector(setTransform:),(IMP)ContentHookTransform,(IMP *)&ContentTransform);
    MSHookMessageEx(WindowClass,@selector(hitTest:withEvent:),(IMP)HookHit,(IMP *)&OrigHit);
    MSHookMessageEx(WindowClass,@selector(pointInside:withEvent:),(IMP)HookInside,(IMP *)&OrigInside);
    [NSNotificationCenter.defaultCenter addObserverForName:@"MangoInterfaceOrientationDidChange" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note){Reconcile();dispatch_async(dispatch_get_main_queue(),^{Reconcile();});}];
    Timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(Timer,dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),250*NSEC_PER_MSEC,50*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(Timer,^{Reconcile();if(!Enabled)dispatch_source_cancel(Timer);});dispatch_resume(Timer);
    InstallMangoPan();
    InstallPillPan();
    InstallOrientationLockFix();
    InstallDockNotchFix();
    Log(@"INSTALLED Beta9.1: persistent verified world, recoverable ownership, physical ended-pan, orientation lock and floating-dock notch lift");
    Reconcile();
}
__attribute__((constructor)) static void StartWorld(void){@autoreleasepool{dispatch_async(dispatch_get_main_queue(),^{Install();});}}
