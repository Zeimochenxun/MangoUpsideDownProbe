// Dock second row ("drawer"), Beta9.9.15. With the iPad-style dock fully
// presented, an upward drag on it pulls the platter taller like a drawer
// that was always two rows long: the platter's bottom edge stays put, row 1
// rides up with the finger and row 2 slides out from that edge. Gated live
// by DockDrawerEnabled (default off). Built on the Beta9.9.14 DOCKPROBE log:
// - presentation is SBFloatingDockView's own transform, already hooked in
//   World.m; the drawer adds its offset there (MSDockDrawerOffset), scaled
//   by the presentation progress so it folds away with the dock;
// - the platter (SBFloatingDockPlatterView, 327x73, icons 60pt at 6.5) is
//   lengthened downward by the same offset, so its bottom edge stays put on
//   screen; row 2 lives in a clipping strip that ends at that edge;
// - the dock's own pan (root controller as delegate) dismisses on downward
//   drags in apps and fails on the home screen; it is told not to begin for
//   the drags the drawer takes (up, or down while the drawer is open);
// - row 2 icons are real SBIconViews configured like row 1's and tapped
//   through the same SBHIconManager; their apps come from the app switcher's
//   recent layouts (SpringBoard keeps only 3 dock recents), minus row 1.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#include <math.h>
#import "../../src/RuntimeDiagnostics.h"

CGFloat MSDockDrawerOffset(UIView *dock,double progress);
void MSDockDrawerTick(UIView *dock,double progress);
void MSDockDrawerInstall(Class dockClass,Class rootClass);
void MSDockReapply(BOOL animated); // World.m

// Declared only so ARC sees an init-family call; SBIconView implements it.
@interface NSObject (MSDockDrawerIconView)
- (instancetype)initWithConfigurationOptions:(unsigned long long)options listLayoutProvider:(id)provider;
@end
typedef struct { CGSize size; CGFloat scale; CGFloat continuousCornerRadius; } MSIconImageInfo;

static CGFloat P,StartP,LastOffset,Extent=66.5,Margin=6.5,Pitch=60;
static CGSize IconSize={60,60};
static CGRect PlatBase,PlatWritten;
static __weak UIView *Dock;
static UIView *Strip;
static UIPanGestureRecognizer *DrawerPan;
static NSMutableDictionary<NSString *,UIView *> *Icons;
static NSString *Source=@"none",*InstallState=@"not-run";
static NSUInteger Shown;

static BOOL DrawerOn(void){return MSRuntimeFlag(@"DockDrawerEnabled");}
static id Call(id obj,NSString *name){
    SEL sel=NSSelectorFromString(name);
    if(!obj||![obj respondsToSelector:sel])return nil;
    NSMethodSignature *sig=[obj methodSignatureForSelector:sel];
    if(sig.numberOfArguments!=2||sig.methodReturnType[0]!='@')return nil;
    @try{return ((id(*)(id,SEL))objc_msgSend)(obj,sel);}@catch(__unused NSException *e){return nil;}
}
static NSArray *Items(id collection){
    if([collection isKindOfClass:NSArray.class])return collection;
    if([collection isKindOfClass:NSOrderedSet.class])return [collection array];
    if([collection isKindOfClass:NSSet.class])return [collection allObjects];
    return nil;
}
static NSString *Bundle(id item,NSString *getter){
    id b=Call(item,getter);
    return [b isKindOfClass:NSString.class]&&((NSString *)b).length?b:nil;
}
static double PresentedProgress(UIView *dock){
    UIViewController *root=dock.window.rootViewController;
    SEL sel=NSSelectorFromString(@"presentedProgress");
    return [root respondsToSelector:sel]?((double(*)(id,SEL))objc_msgSend)(root,sel):1;
}
static UIView *Platter(UIView *dock){
    id p=Call(dock,@"mainPlatterView");
    return [p isKindOfClass:UIView.class]?p:nil;
}
// Row 1's first icon view, and the next one in the same list for the pitch.
static UIView *RowOneIcon(UIView *dock,UIView **next){
    Class iconClass=objc_getClass("SBIconView");
    for(NSString *name in @[@"userIconListView",@"recentIconListView"]){
        UIView *list=Call(dock,name);
        NSMutableArray<UIView *> *found=[NSMutableArray array];
        for(UIView *v in list.subviews)if(iconClass&&[v isKindOfClass:iconClass]&&!v.hidden)[found addObject:v];
        [found sortUsingComparator:^NSComparisonResult(UIView *a,UIView *b){return a.frame.origin.x<b.frame.origin.x?NSOrderedAscending:NSOrderedDescending;}];
        if(found.count){if(next)*next=found.count>1?found[1]:nil;return found[0];}
    }
    return nil;
}

// Lengthens the platter downward by the current offset from SpringBoard's
// own frame, and keeps row 2's strip on the platter's fixed bottom edge.
static void ApplyExtension(UIView *dock){
    UIView *plat=Platter(dock);
    if(!plat)return;
    CGRect f=plat.frame;
    if(!CGRectEqualToRect(f,PlatWritten))PlatBase=f;
    UIView *second=nil,*first=RowOneIcon(dock,&second);
    if(first){
        CGRect r=[first convertRect:first.bounds toView:plat];
        if(r.size.width>0&&r.origin.y>=0&&r.origin.y<PlatBase.size.height){
            Margin=r.origin.y;IconSize=r.size;Extent=PlatBase.size.height-Margin;
            Pitch=second?second.frame.origin.x-first.frame.origin.x:IconSize.width;
            if(Pitch<IconSize.width)Pitch=IconSize.width;
        }
    }
    CGFloat d=fmax(0,fmin(LastOffset,Extent));
    CGRect out=PlatBase;out.size.height+=d;
    PlatWritten=out;
    if(!CGRectEqualToRect(f,out))plat.frame=out;
    if(!Strip){Strip=[UIView new];Strip.clipsToBounds=YES;}
    if(Strip.superview!=plat)[plat addSubview:Strip];
    Strip.frame=CGRectMake(0,PlatBase.size.height-Margin,PlatBase.size.width,Margin+d);
    Strip.hidden=d<=0;
}
static void Settle(UIView *dock,BOOL animated){
    MSDockReapply(animated);
    [dock setNeedsLayout];
    [dock layoutIfNeeded];
}

// Recent apps, newest first, from the app switcher; SpringBoard's dock
// recents (only 3) when no switcher list is reachable. Row 1's apps and the
// app in front are skipped.
static NSArray<NSString *> *RecentBundles(UIView *dock){
    id vc=Call(dock.window.rootViewController,@"floatingDockViewController");
    id model=Call(Call(vc,@"suggestionsViewController"),@"suggestionsModel");
    NSMutableSet<NSString *> *skip=[NSMutableSet set];
    for(id icon in Items(Call(Call(vc,@"dockListModel"),@"icons"))){NSString *b=Bundle(icon,@"applicationBundleID");if(b)[skip addObject:b];}
    for(id item in Items(Call(model,@"currentDisplayItems"))){NSString *b=Bundle(item,@"bundleIdentifier");if(b)[skip addObject:b];}
    NSString *front=Bundle(Call(UIApplication.sharedApplication,@"_accessibilityFrontMostApplication"),@"bundleIdentifier");
    if(front)[skip addObject:front];
    NSArray *layouts=nil;
    for(UIWindow *w in dock.window.windowScene.windows){
        if(![NSStringFromClass(w.class) isEqualToString:@"SBMainSwitcherWindow"])continue;
        NSMutableArray *vcs=[NSMutableArray array];
        if(w.rootViewController)[vcs addObject:w.rootViewController];
        for(NSUInteger i=0;i<vcs.count&&i<16;i++)[vcs addObjectsFromArray:((UIViewController *)vcs[i]).childViewControllers];
        for(id c in vcs)if((layouts=Items(Call(c,@"recentAppLayouts")))){Source=NSStringFromClass([c class]);break;}
        if(layouts)break;
    }
    if(!layouts){
        layouts=Items(Call(Call(objc_getClass("SBMainSwitcherViewController"),@"sharedInstanceIfExists"),@"recentAppLayouts"));
        if(layouts)Source=@"SBMainSwitcherViewController.shared";
    }
    NSMutableArray<NSString *> *out=[NSMutableArray array];
    for(id layout in layouts)
        for(id item in Items(Call(layout,@"allItems"))){NSString *b=Bundle(item,@"bundleIdentifier");if(b&&![out containsObject:b])[out addObject:b];}
    if(!out.count){
        Source=@"dock-recents";
        for(id item in Items(Call(model,@"currentRecentDisplayItemsSortedByRecency"))){NSString *b=Bundle(item,@"bundleIdentifier");if(b&&![out containsObject:b])[out addObject:b];}
    }
    [out filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *b,__unused NSDictionary *bindings){return ![skip containsObject:b];}]];
    return out;
}
// A real icon view set up the way SpringBoard set up row 1's `model`.
static UIView *IconView(NSString *bundle,UIView *model,id iconModel){
    UIView *view=Icons[bundle];
    if(view)return view;
    SEL lookup=NSSelectorFromString(@"applicationIconForBundleIdentifier:");
    id icon=[iconModel respondsToSelector:lookup]?((id(*)(id,SEL,id))objc_msgSend)(iconModel,lookup,bundle):nil;
    Class iconClass=objc_getClass("SBIconView");
    SEL options=NSSelectorFromString(@"configurationOptions"),info=NSSelectorFromString(@"iconImageInfo"),scale=NSSelectorFromString(@"iconContentScale");
    if(!icon||!iconClass||![iconClass instancesRespondToSelector:@selector(initWithConfigurationOptions:listLayoutProvider:)]||
       ![model respondsToSelector:options]||![model respondsToSelector:info]||![model respondsToSelector:scale])return nil;
    view=[[iconClass alloc] initWithConfigurationOptions:((unsigned long long(*)(id,SEL))objc_msgSend)(model,options)
                                      listLayoutProvider:Call(model,@"listLayoutProvider")];
    if(![view isKindOfClass:UIView.class])return nil;
    for(NSString *name in @[@"location",@"delegate"]){
        SEL setter=NSSelectorFromString([NSString stringWithFormat:@"set%@%@:",[[name substringToIndex:1] uppercaseString],[name substringFromIndex:1]]);
        if([view respondsToSelector:setter])((void(*)(id,SEL,id))objc_msgSend)(view,setter,Call(model,name));
    }
    ((void(*)(id,SEL,double))objc_msgSend)(view,NSSelectorFromString(@"setIconContentScale:"),((double(*)(id,SEL))objc_msgSend)(model,scale));
    ((void(*)(id,SEL,MSIconImageInfo))objc_msgSend)(view,NSSelectorFromString(@"setIconImageInfo:"),((MSIconImageInfo(*)(id,SEL))objc_msgSend)(model,info));
    for(NSString *name in @[@"setAllowsLabelArea:",@"setLabelHidden:"]){
        SEL setter=NSSelectorFromString(name);
        if([view respondsToSelector:setter])((void(*)(id,SEL,BOOL))objc_msgSend)(view,setter,[name isEqualToString:@"setLabelHidden:"]);
    }
    ((void(*)(id,SEL,id))objc_msgSend)(view,NSSelectorFromString(@"setIcon:"),icon);
    if(!Icons)Icons=[NSMutableDictionary dictionary];
    Icons[bundle]=view;
    return view;
}
// Fills row 2 as the drawer starts opening; as many icons as row 1 fits.
static void Refresh(UIView *dock){
    UIView *model=RowOneIcon(dock,NULL);
    if(!model||!Strip)return;
    id vc=Call(dock.window.rootViewController,@"floatingDockViewController");
    id iconModel=Call(Call(Call(vc,@"suggestionsViewController"),@"suggestionsModel"),@"iconModel")?:Call(Call(vc,@"iconManager"),@"iconModel");
    NSUInteger cap=(NSUInteger)fmax(1,floor((PlatBase.size.width-2*Margin+(Pitch-IconSize.width))/Pitch));
    NSMutableArray<UIView *> *views=[NSMutableArray array];
    NSMutableSet<NSString *> *used=[NSMutableSet set];
    for(NSString *bundle in RecentBundles(dock)){
        if(views.count>=cap)break;
        UIView *v=IconView(bundle,model,iconModel);
        if(v){[views addObject:v];[used addObject:bundle];}
    }
    for(NSString *bundle in Icons.allKeys)if(![used containsObject:bundle]){[Icons[bundle] removeFromSuperview];[Icons removeObjectForKey:bundle];}
    CGFloat total=views.count?views.count*Pitch-(Pitch-IconSize.width):0;
    CGFloat x=(PlatBase.size.width-total)/2;
    for(NSUInteger i=0;i<views.count;i++){
        views[i].frame=CGRectMake(x+i*Pitch,Margin,IconSize.width,IconSize.height);
        if(views[i].superview!=Strip)[Strip addSubview:views[i]];
    }
    Shown=views.count;
}

// Up opens, down closes only an open drawer; mostly-sideways drags and a
// dock that is not fully presented are left to SpringBoard.
static BOOL Wants(UIPanGestureRecognizer *g){
    UIView *dock=g.view;
    if(!DrawerOn()||!dock||dock!=Dock||PresentedProgress(dock)<.99)return NO;
    CGPoint v=[g velocityInView:dock.superview];
    if(fabs(v.y)<=fabs(v.x))return NO;
    return v.y<0?P<1:P>0;
}
@interface MSDockDrawerPan : NSObject <UIGestureRecognizerDelegate>
@end
@implementation MSDockDrawerPan
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    return [g isKindOfClass:UIPanGestureRecognizer.class]&&Wants((UIPanGestureRecognizer *)g);
}
- (void)pan:(UIPanGestureRecognizer *)g {
    UIView *dock=g.view;
    CGFloat e=fmax(Extent,1);
    switch(g.state){
        case UIGestureRecognizerStateBegan:
            StartP=P;
            if(P<=0)Refresh(dock);
            __attribute__((fallthrough));
        case UIGestureRecognizerStateChanged:
            P=fmax(0,fmin(1,StartP-[g translationInView:dock.superview].y/e));
            Settle(dock,NO);
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:{
            // Where the flick would coast to decides open or closed.
            CGFloat v=[g velocityInView:dock.superview].y;
            CGFloat target=g.state==UIGestureRecognizerStateEnded?(P-v*.15/e>.5?1:0):(StartP>.5?1:0);
            [UIView animateWithDuration:.45 delay:0 usingSpringWithDamping:.86 initialSpringVelocity:0
                                options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction
                             animations:^{P=target;Settle(dock,YES);} completion:nil];
            break;
        }
        default:break;
    }
}
@end
static MSDockDrawerPan *PanTarget;

CGFloat MSDockDrawerOffset(UIView *dock,double progress){
    CGFloat k=isfinite(progress)?fmax(0,fmin(1,progress)):1;
    CGFloat d=dock&&dock==Dock&&DrawerOn()?P*Extent*k:0;
    if(d!=LastOffset){LastOffset=d;[dock setNeedsLayout];}
    return d;
}

static void (*OrigLayout)(UIView *,SEL);
static void HookLayout(UIView *self,SEL cmd){
    OrigLayout(self,cmd);
    if(self==Dock&&NSThread.isMainThread)ApplyExtension(self);
}
// Row 2 hangs below the dock view's own bounds once the drawer is out.
static BOOL (*OrigPointInside)(UIView *,SEL,CGPoint,UIEvent *);
static BOOL HookPointInside(UIView *self,SEL cmd,CGPoint p,UIEvent *event){
    if(OrigPointInside(self,cmd,p,event))return YES;
    if(self!=Dock||LastOffset<=0)return NO;
    UIView *plat=Platter(self);
    return plat&&CGRectContainsPoint(plat.frame,p);
}
static BOOL (*OrigRootShouldBegin)(id,SEL,UIGestureRecognizer *);
static BOOL HookRootShouldBegin(id self,SEL cmd,UIGestureRecognizer *g){
    if(g!=DrawerPan&&[g isKindOfClass:UIPanGestureRecognizer.class]&&Wants((UIPanGestureRecognizer *)g))return NO;
    return OrigRootShouldBegin(self,cmd,g);
}
void MSDockDrawerInstall(Class dockClass,Class rootClass){
    SEL begin=@selector(gestureRecognizerShouldBegin:);
    if(!dockClass||!rootClass||!class_getInstanceMethod(dockClass,@selector(layoutSubviews))||
       !class_getInstanceMethod(dockClass,@selector(pointInside:withEvent:))||!class_getInstanceMethod(rootClass,begin)){
        InstallState=@"missing-methods";return;}
    MSHookMessageEx(dockClass,@selector(layoutSubviews),(IMP)HookLayout,(IMP *)&OrigLayout);
    MSHookMessageEx(dockClass,@selector(pointInside:withEvent:),(IMP)HookPointInside,(IMP *)&OrigPointInside);
    MSHookMessageEx(rootClass,begin,(IMP)HookRootShouldBegin,(IMP *)&OrigRootShouldBegin);
    InstallState=@"hooked";
}

static void Status(double progress){
    static double last;static NSString *lastBody;
    if(!MSDiagnosticsActive())return;
    double now=CACurrentMediaTime();
    if(now-last<2)return;
    last=now;
    NSString *body=[NSString stringWithFormat:@"DRAWER status install=%@ on=%d pan=%d p=%.2f progress=%.2f extent=%.1f offset=%.1f margin=%.1f icon=%@ pitch=%.1f platter=%@ source=%@ shown=%lu",
        InstallState,DrawerOn(),DrawerPan!=nil,P,progress,Extent,LastOffset,Margin,NSStringFromCGSize(IconSize),Pitch,NSStringFromCGRect(PlatBase),Source,(unsigned long)Shown];
    if([body isEqualToString:lastBody])return;
    lastBody=body;
    MSDiagnosticsLog(@"World",body);
}
// World.m's 250ms reconcile: attaches or removes the drawer's pan, and
// closes the drawer once the dock has gone away.
void MSDockDrawerTick(UIView *dock,double progress){
    BOOL on=dock&&DrawerOn()&&[InstallState isEqualToString:@"hooked"];
    if(DrawerPan&&(!on||DrawerPan.view!=dock)){[DrawerPan.view removeGestureRecognizer:DrawerPan];DrawerPan=nil;}
    if(!on){
        if(P>0&&Dock){P=0;Settle(Dock,NO);}
        Status(progress);
        return;
    }
    if(Dock!=dock){Dock=dock;[dock setNeedsLayout];}
    if(!DrawerPan){
        if(!PanTarget)PanTarget=[MSDockDrawerPan new];
        DrawerPan=[[UIPanGestureRecognizer alloc] initWithTarget:PanTarget action:@selector(pan:)];
        DrawerPan.delegate=PanTarget;DrawerPan.name=@"MangoDockDrawer";
        [dock addGestureRecognizer:DrawerPan];
    }
    if(P>0&&isfinite(progress)&&progress<.01&&DrawerPan.state==UIGestureRecognizerStatePossible){P=0;Settle(dock,NO);}
    Status(progress);
}
