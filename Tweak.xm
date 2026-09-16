// MangoUpsideDownWorld 0.1.0-alpha1. Experimental; see EVIDENCE.md.
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
static Class WindowClass, PassClass, ContentClass, ContainerClass;
static NSHashTable<UIWindow *> *Windows;
static NSHashTable<UIView *> *Roots;
static BOOL Enabled, Installed, Busy;
static unsigned Depth, Attempts, HitDepth;
static dispatch_source_t Timer;
static char StateKey;

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
@property(nonatomic) double lastLog;
@end
@implementation MWWorldState
@end

static void Log(NSString *s) {
    NSLog(@"[MangoUDWorld] %@",s);
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
    BOOL ok=RestoreOne(root,s.outer);
    for(UIView *v in s.inner.keyEnumerator.allObjects)
        if(!RestoreOne(v,[s.inner objectForKey:v]))ok=NO;
    if(!ok&&!s.suspended){s.suspended=YES;Log(@"CONFLICT: unknown transform; world suspended until respring");}
}
static void SetOwned(UIView *v,MWOwnedTransform *s,CGAffineTransform t){
    s.before=v.transform;s.after=t;s.applied=YES;v.transform=t;
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
    NSArray<UIView *> *contents=Contents(root);if(!contents.count)return;
    if(!CATransform3DIsAffine(w.layer.transform)||!CATransform3DIsIdentity(w.layer.sublayerTransform))return;
    id<UICoordinateSpace> fixed=w.screen.fixedCoordinateSpace;
    CGRect screen=fixed.bounds;
    CGRect r=[root convertRect:root.bounds toCoordinateSpace:fixed];
    // Only the full-screen root shape evidenced in the device log is accepted.
    if(!isfinite(r.origin.x)||!isfinite(r.origin.y)||!isfinite(r.size.width)||!isfinite(r.size.height)||
       fabs(CGRectGetWidth(r)-CGRectGetWidth(screen))>2||fabs(CGRectGetHeight(r)-CGRectGetHeight(screen))>2||
       fabs(CGRectGetMidX(r)-CGRectGetMidX(screen))>2||fabs(CGRectGetMidY(r)-CGRectGetMidY(screen))>2)return;
    // Require an upright unmodified root before making the world upside-down.
    CGPoint o=[root convertPoint:CGPointZero toCoordinateSpace:fixed];
    CGPoint x=[root convertPoint:CGPointMake(1,0) toCoordinateSpace:fixed];
    CGPoint y=[root convertPoint:CGPointMake(0,1) toCoordinateSpace:fixed];
    if(x.x-o.x<=0||y.y-o.y<=0||fabs(x.y-o.y)>1e-4||fabs(y.x-o.x)>1e-4)return;
    // Validate every content basis first, so unsupported geometry causes no
    // partial correction. Hidden contents are retained for subsequent reveals.
    NSMutableArray<UIView *> *cancel=[NSMutableArray array];
    for(UIView *v in contents){
        CGPoint a=[v convertPoint:CGPointZero toCoordinateSpace:fixed];
        CGPoint b=[v convertPoint:CGPointMake(1,0) toCoordinateSpace:fixed];
        CGPoint c=[v convertPoint:CGPointMake(0,1) toCoordinateSpace:fixed];
        double dx=b.x-a.x,dy=c.y-a.y;
        if(!isfinite(dx)||!isfinite(dy)||fabs(dx)<1e-5||fabs(dy)<1e-5||
           fabs(b.y-a.y)>fabs(dx)*.001||fabs(c.x-a.x)>fabs(dy)*.001||dx*dy<=0)return;
        // Nested content instances would be normalized twice. Fail closed.
        for(UIView *p=v.superview;p&&p!=root;p=p.superview)if([p isKindOfClass:ContentClass])return;
        if(dx<0&&dy<0)[cancel addObject:v];
    }
    CGPoint pivot=[w convertPoint:CGPointMake(CGRectGetMidX(screen),CGRectGetMidY(screen)) fromCoordinateSpace:fixed];
    MWTransform rotated=MWTurn(Math(root.transform),(MWPoint){root.center.x,root.center.y},(MWPoint){pivot.x,pivot.y});
    if(!MWFinite(rotated))return;
    for(UIView *v in cancel){
        MWOwnedTransform *owned=[s.inner objectForKey:v];
        if(!owned){owned=[MWOwnedTransform new];[s.inner setObject:owned forKey:v];}
        CGAffineTransform t=v.transform;t.a=-t.a;t.b=-t.b;t.c=-t.c;t.d=-t.d;
        SetOwned(v,owned,t);
    }
    SetOwned(root,s.outer,CG(rotated));
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
    if(CACurrentMediaTime()-s.lastLog>5){s.lastLog=CACurrentMediaTime();
        Log([NSString stringWithFormat:@"WORLD orientation=2 root=%p contents=%lu canceled=%lu windowBounds=%@",(__bridge void *)root,(unsigned long)contents.count,(unsigned long)cancel.count,NSStringFromCGRect(w.bounds)]);}
}
static void Reconcile(void){
    if(Busy||Depth||![NSThread isMainThread])return;
    Busy=YES;
    @try{
        [UIView performWithoutAnimation:^{
            for(UIView *root in Roots.allObjects)RestoreWorld(root);
            if(access(Disabled,F_OK)==0&&Enabled){Enabled=NO;Log(@"DISABLED: restored owned transforms");}
            if(!Enabled||Orientation()!=UIInterfaceOrientationPortraitUpsideDown)return;
            for(UIWindow *w in UIApplication.sharedApplication.windows)Discover(w);
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
static void P##HookCenter(id s,SEL c,CGPoint v){BOOL b=Begin(s);@try{P##Center(s,c,v);}@finally{End(b);}} \
static void (*P##Transform)(id,SEL,CGAffineTransform); \
static void P##HookTransform(id s,SEL c,CGAffineTransform v){BOOL b=Begin(s);@try{P##Transform(s,c,v);}@finally{End(b);}}
DEFINE_HOOKS(Pass)
DEFINE_HOOKS(Content)
DEFINE_HOOKS(Window)

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
#define INSTALL_HOOKS(C,P) \
MSHookMessageEx(C,@selector(layoutSubviews),(IMP)P##HookLayout,(IMP *)&P##Layout); \
MSHookMessageEx(C,@selector(setFrame:),(IMP)P##HookFrame,(IMP *)&P##Frame); \
MSHookMessageEx(C,@selector(setBounds:),(IMP)P##HookBounds,(IMP *)&P##Bounds); \
MSHookMessageEx(C,@selector(setCenter:),(IMP)P##HookCenter,(IMP *)&P##Center); \
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
    Roots=[NSHashTable weakObjectsHashTable];Windows=[NSHashTable weakObjectsHashTable];Enabled=YES;Installed=YES;
    INSTALL_HOOKS(PassClass,Pass);INSTALL_HOOKS(ContentClass,Content);INSTALL_HOOKS(WindowClass,Window);
    MSHookMessageEx(WindowClass,@selector(hitTest:withEvent:),(IMP)HookHit,(IMP *)&OrigHit);
    MSHookMessageEx(WindowClass,@selector(pointInside:withEvent:),(IMP)HookInside,(IMP *)&OrigInside);
    [NSNotificationCenter.defaultCenter addObserverForName:@"MangoInterfaceOrientationDidChange" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){Reconcile();dispatch_async(dispatch_get_main_queue(),^{Reconcile();});}];
    Timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(Timer,dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),250*NSEC_PER_MSEC,50*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(Timer,^{Reconcile();if(!Enabled)dispatch_source_cancel(Timer);});dispatch_resume(Timer);
    Log(@"INSTALLED World 0.1.0-alpha1: whole aperture root turn + internal rotation normalization + window hit fallback");Reconcile();
}
__attribute__((constructor)) static void StartWorld(void){@autoreleasepool{dispatch_async(dispatch_get_main_queue(),^{Install();});}}
