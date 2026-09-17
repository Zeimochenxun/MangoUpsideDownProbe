// MangoUpsideDownWorld placement hotfix.
//
// This module intentionally NEVER hooks SBSystemApertureContainerView's
// setTransform:. The first integrated version did, which could race the
// aperture/Mango rotation transform and leave the island visually stuck.
//
// Placement now owns only container.center. It tracks Mango-confirmed hosts,
// mirrors a container to the opposite physical edge when needed, and restores
// only the center value it wrote. Rotation/scale remain entirely owned by
// Mango/SystemAperture/World.

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
#include <errno.h>
#include "Geometry.h"

static const char *WPDisabled = "/var/mobile/Library/Preferences/MangoUpsideDownWorld.disabled";
static const char *WPLogPath = "/var/mobile/Library/Logs/MangoUpsideDownWorld.log";
static const NSUInteger WPPendingCap = 64;
static const double WPPendingTTL = 30.0;

static Class WPContainerClass, WPWindowClass;
static NSHashTable<UIView *> *WPContainers;
static NSMutableArray *WPPending;
static dispatch_source_t WPTimer;
static BOOL WPInstalled, WPEnabled, WPResolving;
static unsigned WPAttempts, WPPendingSeen, WPPendingExpired;
static double WPPendingLog, WPExpiryLog;
static char WPStateKey;

@interface MWPState : NSObject
@property(nonatomic,strong) NSHashTable<UIView *> *hosts;
@property(nonatomic) CGPoint baselineCenter;
@property(nonatomic) CGPoint appliedCenter;
@property(nonatomic) BOOL applied;
@property(nonatomic) double lastLog;
@end
@implementation MWPState
@end

@interface MWPPendingHost : NSObject
@property(nonatomic,weak) UIView *host;
@property(nonatomic) double firstSeen;
@end
@implementation MWPPendingHost
@end

static void WPLog(NSString *message) {
    if (![NSThread isMainThread]) return;
    NSString *line=[NSString stringWithFormat:@"PLACEMENT %@",message];
    NSLog(@"[MangoUDWorld] %@",line);
    mkdir("/var/mobile/Library/Logs",0755);
    int fd=open(WPLogPath,O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW,0600);
    if(fd<0)return;
    struct stat st;
    if(fstat(fd,&st)!=0||!S_ISREG(st.st_mode)){close(fd);return;}
    if(st.st_size>512*1024)ftruncate(fd,0);
    NSData *bytes=[[NSString stringWithFormat:@"%.3f %@\n",NSDate.timeIntervalSinceReferenceDate,line] dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *p=(const uint8_t *)bytes.bytes;size_t left=bytes.length;
    while(left){ssize_t n=write(fd,p,left);if(n<0&&errno==EINTR)continue;if(n<=0)break;p+=n;left-=(size_t)n;}
    close(fd);
}

static void WPRateLog(double *slot,double interval,NSString *message){
    double now=CACurrentMediaTime();if(now-*slot<interval)return;*slot=now;WPLog(message);
}

static MWPState *WPState(UIView *v){return objc_getAssociatedObject(v,&WPStateKey);}
static MUDFRect WPRect(CGRect r){return (MUDFRect){r.origin.x,r.origin.y,r.size.width,r.size.height};}
static BOOL WPCenterNear(CGPoint a,CGPoint b){return fabs(a.x-b.x)<0.01&&fabs(a.y-b.y)<0.01;}

static NSInteger WPOrientation(void){
    Class c=objc_getClass("DecoratedAppSceneView");
    SEL sel=sel_registerName("mango_currentInterfaceOrientation");
    Method m=c?class_getClassMethod(c,sel):NULL;
    if(!m||method_getNumberOfArguments(m)!=2)return -1;
    char type[64]={0};method_getReturnType(m,type,sizeof(type));
    if(strcmp(type,@encode(NSInteger))!=0)return -1;
    return ((NSInteger(*)(id,SEL))objc_msgSend)((id)c,sel);
}

static UIView *WPFindAncestor(UIView *host,Class cls){
    for(UIView *v=host;v;v=v.superview)if([v isKindOfClass:cls])return v;
    return nil;
}

static UIView *WPCurrentHost(UIView *container,MWPState *s){
    for(UIView *host in s.hosts.allObjects)if(WPFindAncestor(host,WPContainerClass)==container)return host;
    return nil;
}

static BOOL WPWindowIsWorldTurned(UIWindow *window){
    if(!window||window.screen!=UIScreen.mainScreen)return NO;
    id<UICoordinateSpace> fixed=window.screen.fixedCoordinateSpace;
    CGPoint o=[window convertPoint:CGPointZero toCoordinateSpace:fixed];
    CGPoint x=[window convertPoint:CGPointMake(1,0) toCoordinateSpace:fixed];
    CGPoint y=[window convertPoint:CGPointMake(0,1) toCoordinateSpace:fixed];
    double dx=x.x-o.x,dy=y.y-o.y,skewX=y.x-o.x,skewY=x.y-o.y;
    return isfinite(dx)&&isfinite(dy)&&isfinite(skewX)&&isfinite(skewY)&&
           dx<-1e-5&&dy<-1e-5&&fabs(skewY)<=fabs(dx)*1e-3&&fabs(skewX)<=fabs(dy)*1e-3;
}

static void WPRestore(UIView *v,MWPState *s,NSString *reason){
    if(!s.applied)return;
    if(WPCenterNear(v.center,s.appliedCenter)){
        [UIView performWithoutAnimation:^{v.center=s.baselineCenter;}];
        if(reason)WPLog([NSString stringWithFormat:@"RESTORE %@ container=%p",reason,(__bridge void *)v]);
    }else if(reason){
        WPLog([NSString stringWithFormat:@"CLEAR %@ container=%p external-center-change",reason,(__bridge void *)v]);
    }
    s.applied=NO;
}

static void WPUpdate(UIView *v){
    if(!v||![NSThread isMainThread])return;
    MWPState *s=WPState(v);if(!s)return;
    if(s.applied&&!WPCenterNear(v.center,s.appliedCenter))s.applied=NO;

    if(!WPEnabled||access(WPDisabled,F_OK)==0||WPOrientation()!=UIInterfaceOrientationPortraitUpsideDown){
        WPRestore(v,s,@"orientation-or-disabled");return;
    }

    UIView *host=WPCurrentHost(v,s);
    UIView *parent=v.superview;
    UIWindow *window=v.window;
    if(!host||!parent||![window isKindOfClass:WPWindowClass]||window.screen!=UIScreen.mainScreen){
        WPRestore(v,s,@"detached");return;
    }

    if(!WPWindowIsWorldTurned(window)){
        WPRestore(v,s,@"waiting-for-world-turn");return;
    }

    id<UICoordinateSpace> fixed=window.screen.fixedCoordinateSpace;
    CGPoint o=[parent convertPoint:CGPointZero toCoordinateSpace:fixed];
    CGPoint x=[parent convertPoint:CGPointMake(1,0) toCoordinateSpace:fixed];
    CGPoint y=[parent convertPoint:CGPointMake(0,1) toCoordinateSpace:fixed];
    MUDFAffine map={x.x-o.x,x.y-o.y,y.x-o.x,y.y-o.y,o.x,o.y};

    MUDFRect current=WPRect([v convertRect:v.bounds toCoordinateSpace:fixed]);
    MUDFRect baseline=current;
    CGPoint baseCenter=s.applied?s.baselineCenter:v.center;

    if(s.applied){
        MUDFPoint own={s.appliedCenter.x-s.baselineCenter.x,s.appliedCenter.y-s.baselineCenter.y};
        baseline=MUDFBaselineRect(current,map,own);
    }

    MUDFPoint delta;MUDFRect target;
    MUDFPlanResult result=MUDFPlan(WPRect(fixed.bounds),baseline,map,&delta,&target);

    if(result==MUDFPlanAlreadyAtOtherEdge){
        WPRestore(v,s,@"world-already-placed");
        double now=CACurrentMediaTime();if(now-s.lastLog>2){s.lastLog=now;WPLog(@"SKIP already at physical lower edge");}
        return;
    }
    if(result!=MUDFPlanOK){
        WPRestore(v,s,@"geometry-guard");return;
    }

    CGPoint desired=CGPointMake(baseCenter.x+delta.x,baseCenter.y+delta.y);
    s.baselineCenter=baseCenter;s.appliedCenter=desired;s.applied=YES;
    if(!WPCenterNear(v.center,desired))[UIView performWithoutAnimation:^{v.center=desired;}];

    CGRect after=[v convertRect:v.bounds toCoordinateSpace:fixed];
    if(!MUDFFiniteRect(WPRect(after))||fabs(CGRectGetMinY(after)-target.y)>1.0||fabs(CGRectGetMinX(after)-target.x)>1.0){
        WPRestore(v,s,@"post-write-mismatch");
        WPLog(@"SKIP center-only placement verification failed");
        return;
    }

    double now=CACurrentMediaTime();
    if(now-s.lastLog>2){
        s.lastLog=now;
        WPLog([NSString stringWithFormat:@"APPLY center-only container=%p baseline=%@ actual=%@ deltaParent={%.3f,%.3f}",
               (__bridge void *)v,NSStringFromCGRect(CGRectMake(baseline.x,baseline.y,baseline.width,baseline.height)),NSStringFromCGRect(after),delta.x,delta.y]);
    }
}

static void WPUpdateAll(void){for(UIView *v in WPContainers.allObjects)WPUpdate(v);}

static BOOL WPTrackHost(UIView *host){
    UIView *container=WPFindAncestor(host,WPContainerClass);
    if(!container||![container.window isKindOfClass:WPWindowClass])return NO;
    MWPState *s=WPState(container);
    if(!s){
        s=[MWPState new];s.hosts=[NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(container,&WPStateKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [WPContainers addObject:container];
        WPLog([NSString stringWithFormat:@"TRACK host=%p container=%p",(__bridge void *)host,(__bridge void *)container]);
    }
    [s.hosts addObject:host];
    WPUpdate(container);
    return YES;
}

static void WPAddPending(UIView *host){
    for(MWPPendingHost *p in WPPending)if(p.host==host)return;
    if(WPPending.count>=WPPendingCap){WPRateLog(&WPPendingLog,5,@"PENDING cap reached");return;}
    MWPPendingHost *p=[MWPPendingHost new];p.host=host;p.firstSeen=CACurrentMediaTime();[WPPending addObject:p];++WPPendingSeen;
    WPRateLog(&WPPendingLog,1,[NSString stringWithFormat:@"PENDING host=%p queued count=%lu seen=%u",(__bridge void *)host,(unsigned long)WPPending.count,WPPendingSeen]);
}

static void WPResolvePending(void){
    if(!WPPending.count||WPResolving||![NSThread isMainThread])return;
    WPResolving=YES;
    @try{
        double now=CACurrentMediaTime();
        for(MWPPendingHost *p in [WPPending copy]){
            UIView *host=p.host;if(!host){[WPPending removeObject:p];continue;}
            if(WPEnabled&&WPTrackHost(host)){
                [WPPending removeObject:p];WPLog([NSString stringWithFormat:@"PENDING host=%p resolved after %.2fs",(__bridge void *)host,now-p.firstSeen]);continue;
            }
            if(now-p.firstSeen>WPPendingTTL){[WPPending removeObject:p];++WPPendingExpired;WPRateLog(&WPExpiryLog,5,[NSString stringWithFormat:@"PENDING expired=%u",WPPendingExpired]);}
        }
    }@finally{WPResolving=NO;}
}

static void (*WPOrigHostLayout)(id,SEL,id);
static void WPHookHostLayout(id self,SEL cmd,id object){
    WPOrigHostLayout(self,cmd,object);
    if(!WPEnabled||![NSThread isMainThread]||![object isKindOfClass:UIView.class])return;
    UIView *host=(UIView *)object;
    if(WPTrackHost(host))return;
    WPAddPending(host);
    dispatch_async(dispatch_get_main_queue(),^{WPResolvePending();});
}

static BOOL WPSignature(Class cls,SEL sel,const char *ret,NSArray<NSString *> *args){
    Method m=cls?class_getInstanceMethod(cls,sel):NULL;if(!m||method_getNumberOfArguments(m)!=args.count+2)return NO;
    char t[512]={0};method_getReturnType(m,t,sizeof(t));if(strcmp(t,ret))return NO;
    for(NSUInteger i=0;i<args.count;i++){memset(t,0,sizeof(t));method_getArgumentType(m,(unsigned)i+2,t,sizeof(t));if(strcmp(t,args[i].UTF8String))return NO;}
    return YES;
}

static BOOL WPVerifiedMango(void){
    const uint8_t uuid[16]={0x67,0xc0,0xd7,0xc2,0x44,0x87,0x3f,0xd2,0x95,0x35,0x06,0x77,0x45,0xae,0x4b,0x8f};
    for(uint32_t i=0;i<_dyld_image_count();i++){
        const char *name=_dyld_get_image_name(i);if(!name)continue;
        const char *base=strrchr(name,'/');base=base?base+1:name;
        if(!strcmp(base,"MangoUpsideDownFix.dylib")){WPLog(@"NO HOOKS legacy standalone Fix still loaded");return NO;}
        if(strcmp(base,"mango.dylib"))continue;
        const struct mach_header_64 *h=(const struct mach_header_64 *)_dyld_get_image_header(i);if(!h||h->magic!=MH_MAGIC_64)return NO;
        const uint8_t *p=(const uint8_t *)(h+1),*end=p+h->sizeofcmds;
        for(uint32_t n=0;n<h->ncmds;n++){
            if((size_t)(end-p)<sizeof(struct load_command))return NO;
            const struct load_command *lc=(const struct load_command *)p;if(lc->cmdsize<sizeof(*lc)||lc->cmdsize>(size_t)(end-p))return NO;
            if(lc->cmd==LC_UUID&&lc->cmdsize>=sizeof(struct uuid_command))return !memcmp(((const struct uuid_command *)p)->uuid,uuid,16);
            p+=lc->cmdsize;
        }
        return NO;
    }
    return NO;
}

static void WPInstall(void){
    if(WPInstalled||access(WPDisabled,F_OK)==0)return;
    NSOperatingSystemVersion os=NSProcessInfo.processInfo.operatingSystemVersion;
    if(os.majorVersion!=16||os.minorVersion!=5||os.patchVersion!=0){WPLog(@"NO HOOKS restricted to iOS 16.5");return;}

    Class element=objc_getClass("MangoPillElement");
    WPContainerClass=objc_getClass("SBSystemApertureContainerView");
    WPWindowClass=objc_getClass("SBSystemApertureWindow");
    if(!WPVerifiedMango()||!element||!WPContainerClass||!WPWindowClass){
        if(++WPAttempts<40)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{WPInstall();});
        else WPLog(@"NO HOOKS matching Mango/classes unavailable within 20 seconds");
        return;
    }

    SEL host=sel_registerName("layoutHostContainerViewDidLayoutSubviews:");
    if(!WPSignature(element,host,"v",@[@"@"])) {WPLog(@"NO HOOKS host callback signature mismatch");return;}

    WPContainers=[NSHashTable weakObjectsHashTable];WPPending=[NSMutableArray array];WPEnabled=YES;WPInstalled=YES;
    MSHookMessageEx(element,host,(IMP)WPHookHostLayout,(IMP *)&WPOrigHostLayout);

    [NSNotificationCenter.defaultCenter addObserverForName:@"MangoInterfaceOrientationDidChange" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){
        WPResolvePending();WPUpdateAll();
        dispatch_async(dispatch_get_main_queue(),^{WPResolvePending();WPUpdateAll();});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),dispatch_get_main_queue(),^{WPResolvePending();WPUpdateAll();});
    }];

    WPTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(WPTimer,dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),250*NSEC_PER_MSEC,50*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(WPTimer,^{
        if(access(WPDisabled,F_OK)==0&&WPEnabled){WPEnabled=NO;[WPPending removeAllObjects];WPUpdateAll();WPLog(@"DISABLED restored center-only placement");}
        else{WPResolvePending();WPUpdateAll();}
        if(!WPEnabled)dispatch_source_cancel(WPTimer);
    });
    dispatch_resume(WPTimer);
    WPLog(@"INSTALLED center-only placement hotfix; no container transform hooks");
}

__attribute__((constructor)) static void StartWorldPlacement(void){@autoreleasepool{dispatch_async(dispatch_get_main_queue(),^{WPInstall();});}}
