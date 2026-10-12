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
//   through the same SBHIconManager.
// Row 2's apps (Beta9.9.16): SpringBoard's dock remembers only the 3 recents
// row 1 already shows and drops the oldest for each new one, so the drawer
// keeps its own list of every app that comes to the front, newest first,
// and shows the ones row 1 does not.
// Pinned apps (Beta9.9.18): DockDrawerPinned, chosen in Settings, go first
// in their order; recents fill the rest, after a divider styled like row
// 1's when DockDrawerDivider is on.
// Beta9.9.20: running-app marks like Lynx's under row 2, and a pull that
// starts while SpringBoard is still animating the dock in waits for the
// dock to come to rest instead of pulling row 2 out from under it.
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
static NSString *Source=@"none",*InstallState=@"not-run",*IconFail=@"none";
static NSUInteger Shown,Candidates;
static CGFloat IconScale=NAN;
static CGRect DividerFrame={{0,12},{1,49}};
static __weak UIView *DividerSource;
static UIView *Divider;
static NSUInteger Pins;
static NSString *DividerLook=@"none";
static NSUInteger Springs;
static BOOL Waiting;
static CGFloat Origin;

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
    UIView *divider=Call(dock,@"dividerView");
    if([divider isKindOfClass:UIView.class]&&divider.superview){
        DividerSource=divider;
        CGRect r=[divider convertRect:divider.bounds toView:plat];
        if(r.size.width>0&&r.size.height>0)DividerFrame=r;
    }
    CGFloat d=fmax(0,fmin(LastOffset,Extent));
    CGRect out=PlatBase;out.size.height+=d;
    PlatWritten=out;
    // Row 1's icon lists are flexible-height subviews of the platter and,
    // autoresized, re-centred row 1 in the taller platter (Beta9.9.16 on
    // device). While the drawer is out only the full-bleed backgrounds
    // follow the platter; SpringBoard keeps placing the lists itself.
    plat.autoresizesSubviews=NO;
    if(!CGRectEqualToRect(f,out))plat.frame=out;
    UIViewAutoresizing fill=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    for(UIView *v in plat.subviews)
        if(v!=Strip&&(v.autoresizingMask&fill)==fill&&!CGRectEqualToRect(v.frame,plat.bounds))v.frame=plat.bounds;
    plat.autoresizesSubviews=d<=0;
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

// The drawer's own recency list, fed from World.m's 250ms tick by whichever
// app is in front, persisted so a respring keeps it.
static const NSUInteger MRUCap=24;
static NSMutableArray<NSString *> *MRU;
static NSURL *MRUFile(void){
    return [NSURL fileURLWithPath:[NSString stringWithUTF8String:jbroot("/var/mobile/Library/Application Support/MangoSuite/dock-recents.plist")]];
}
static void RecordFront(void){
    if(!MRU){
        MRU=[NSMutableArray array];
        for(id b in [NSArray arrayWithContentsOfURL:MRUFile() error:nil])
            if([b isKindOfClass:NSString.class]&&MRU.count<MRUCap)[MRU addObject:b];
    }
    NSString *front=Bundle(Call(UIApplication.sharedApplication,@"_accessibilityFrontMostApplication"),@"bundleIdentifier");
    if(!front||[MRU.firstObject isEqualToString:front])return;
    [MRU removeObject:front];
    [MRU insertObject:front atIndex:0];
    while(MRU.count>MRUCap)[MRU removeLastObject];
    [MRU writeToURL:MRUFile() error:nil];
}
static NSSet<NSString *> *UserDock(id vc){
    NSMutableSet<NSString *> *out=[NSMutableSet set];
    for(id icon in Items(Call(Call(vc,@"dockListModel"),@"icons"))){NSString *b=Bundle(icon,@"applicationBundleID");if(b)[out addObject:b];}
    return out;
}
// Recent apps, newest first: the drawer's own list, then the app
// switcher's if reachable, then SpringBoard's 3 dock recents. Row 1's apps
// and the app in front are skipped.
static NSArray<NSString *> *RecentBundles(UIView *dock){
    id vc=Call(dock.window.rootViewController,@"floatingDockViewController");
    id model=Call(Call(vc,@"suggestionsViewController"),@"suggestionsModel");
    NSMutableSet<NSString *> *skip=[UserDock(vc) mutableCopy];
    for(id item in Items(Call(model,@"currentDisplayItems"))){NSString *b=Bundle(item,@"bundleIdentifier");if(b)[skip addObject:b];}
    NSString *front=Bundle(Call(UIApplication.sharedApplication,@"_accessibilityFrontMostApplication"),@"bundleIdentifier");
    if(front)[skip addObject:front];
    NSMutableArray<NSString *> *out=[NSMutableArray array];
    void (^add)(NSString *)=^(NSString *b){if(b&&![skip containsObject:b]&&![out containsObject:b])[out addObject:b];};
    for(NSString *b in MRU)add(b);
    NSUInteger own=out.count;
    NSString *switcher=@"none";
    NSArray *layouts=nil;
    for(UIWindow *w in dock.window.windowScene.windows){
        if(![NSStringFromClass(w.class) isEqualToString:@"SBMainSwitcherWindow"])continue;
        NSMutableArray *vcs=[NSMutableArray array];
        if(w.rootViewController)[vcs addObject:w.rootViewController];
        for(NSUInteger i=0;i<vcs.count&&i<16;i++)[vcs addObjectsFromArray:((UIViewController *)vcs[i]).childViewControllers];
        for(id c in vcs)if((layouts=Items(Call(c,@"recentAppLayouts")))){switcher=NSStringFromClass([c class]);break;}
        if(layouts)break;
    }
    if(!layouts){
        layouts=Items(Call(Call(objc_getClass("SBMainSwitcherViewController"),@"sharedInstanceIfExists"),@"recentAppLayouts"));
        if(layouts)switcher=@"SBMainSwitcherViewController.shared";
    }
    NSUInteger fromSwitcher=out.count;
    for(id layout in layouts)
        for(id item in Items(Call(layout,@"allItems")))add(Bundle(item,@"bundleIdentifier"));
    fromSwitcher=out.count-fromSwitcher;
    for(id item in Items(Call(model,@"currentRecentDisplayItemsSortedByRecency")))add(Bundle(item,@"bundleIdentifier"));
    Source=[NSString stringWithFormat:@"own:%lu/%lu switcher:%@:%lu dock:%lu skip:%lu",(unsigned long)own,(unsigned long)MRU.count,
        switcher,(unsigned long)fromSwitcher,(unsigned long)(out.count-own-fromSwitcher),(unsigned long)skip.count];
    return out;
}
static UIView *ImageView(UIView *iconView){
    NSMutableArray<UIView *> *queue=[NSMutableArray arrayWithArray:iconView.subviews];
    for(NSUInteger i=0;i<queue.count&&i<64;i++){
        if([NSStringFromClass(queue[i].class) containsString:@"IconImageView"])return queue[i];
        [queue addObjectsFromArray:queue[i].subviews];
    }
    return nil;
}
// A real icon view set up the way SpringBoard set up row 1's `model`.
static UIView *IconView(NSString *bundle,UIView *model,id iconModel){
    UIView *view=Icons[bundle];
    if(view)return view;
    SEL lookup=NSSelectorFromString(@"applicationIconForBundleIdentifier:");
    id icon=[iconModel respondsToSelector:lookup]?((id(*)(id,SEL,id))objc_msgSend)(iconModel,lookup,bundle):nil;
    Class iconClass=objc_getClass("SBIconView");
    SEL options=NSSelectorFromString(@"configurationOptions"),info=NSSelectorFromString(@"iconImageInfo"),scale=NSSelectorFromString(@"iconContentScale");
    if(!icon){IconFail=[NSString stringWithFormat:@"no-icon:%@ model=%@",bundle,iconModel?NSStringFromClass([iconModel class]):@"nil"];return nil;}
    if(!iconClass||![iconClass instancesRespondToSelector:@selector(initWithConfigurationOptions:listLayoutProvider:)]||
       ![model respondsToSelector:options]||![model respondsToSelector:info]||![model respondsToSelector:scale]){IconFail=@"no-icon-view-api";return nil;}
    view=[[iconClass alloc] initWithConfigurationOptions:((unsigned long long(*)(id,SEL))objc_msgSend)(model,options)
                                      listLayoutProvider:Call(model,@"listLayoutProvider")];
    if(![view isKindOfClass:UIView.class]){IconFail=@"init-failed";return nil;}
    ((void(*)(id,SEL,id))objc_msgSend)(view,NSSelectorFromString(@"setIcon:"),icon);
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
    // Row 1 draws its 60pt icons at SpringBoard's content scale (0.78 on
    // device) and ours did not pick that up, so match the drawn image size.
    view.bounds=CGRectMake(0,0,IconSize.width,IconSize.height);
    [view layoutIfNeeded];
    UIView *mine=ImageView(view),*theirs=ImageView(model);
    CGFloat want=theirs?[theirs convertRect:theirs.bounds toView:model].size.width:0;
    CGFloat have=mine?[mine convertRect:mine.bounds toView:view].size.width:0;
    if(want>0&&have>0&&fabs(want/have-1)>.02)view.transform=CGAffineTransformMakeScale(want/have,want/have);
    IconScale=want>0&&have>0?want/have:NAN;
    if(!Icons)Icons=[NSMutableDictionary dictionary];
    Icons[bundle]=view;
    return view;
}
// Lynx's running-app marks (showDockIndicators) hang on row 1's icon views
// as `indicator`. Row 2 copies the look of one that is showing (none when
// Lynx's marks are off or no row 1 app runs) and puts it under each row 2
// app that is still running.
static char IndicatorKey;
static CGRect IndicatorBox;
static UIView *IndicatorSource;
static NSString *IndicatorLook=@"none";
static void LearnIndicator(UIView *dock){
    IndicatorBox=CGRectNull;IndicatorSource=nil;IndicatorLook=@"none";
    Class iconClass=objc_getClass("SBIconView");
    for(NSString *name in @[@"userIconListView",@"recentIconListView"])
        for(UIView *icon in ((UIView *)Call(dock,name)).subviews){
            if(!iconClass||![icon isKindOfClass:iconClass])continue;
            UIView *mark=Call(icon,@"indicator");
            if(![mark isKindOfClass:UIView.class]||mark.hidden||mark.alpha<.01||!mark.window)continue;
            IndicatorBox=[mark convertRect:mark.bounds toView:icon];
            IndicatorSource=mark;
            IndicatorLook=[NSString stringWithFormat:@"%@ box=%@ bg=%@ radius=%.1f alpha=%.2f in=%@",NSStringFromClass(mark.class),
                NSStringFromCGRect(IndicatorBox),mark.backgroundColor,mark.layer.cornerRadius,mark.alpha,NSStringFromClass(mark.superview.class)];
            return;
        }
}
static BOOL Running(NSString *bundle){
    id apps=Call(objc_getClass("SBApplicationController"),@"sharedInstance");
    SEL lookup=NSSelectorFromString(@"applicationWithBundleIdentifier:"),running=NSSelectorFromString(@"isRunning");
    id app=[apps respondsToSelector:lookup]?((id(*)(id,SEL,id))objc_msgSend)(apps,lookup,bundle):nil;
    if(app&&![app respondsToSelector:running])app=Call(app,@"processState");
    return [app respondsToSelector:running]&&((BOOL(*)(id,SEL))objc_msgSend)(app,running);
}
static void UpdateIndicators(void){
    UIView *source=IndicatorSource;
    for(NSString *bundle in Icons){
        UIView *icon=Icons[bundle];
        UIImageView *mark=objc_getAssociatedObject(icon,&IndicatorKey);
        if(!source||CGRectIsNull(IndicatorBox)||icon.superview!=Strip||!Running(bundle)){mark.hidden=YES;continue;}
        if(!mark){
            mark=[UIImageView new];mark.userInteractionEnabled=NO;
            objc_setAssociatedObject(icon,&IndicatorKey,mark,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        mark.backgroundColor=source.backgroundColor;
        mark.alpha=source.alpha;
        mark.layer.cornerRadius=source.layer.cornerRadius;
        mark.layer.compositingFilter=source.layer.compositingFilter;
        if([source isKindOfClass:UIImageView.class]){mark.image=((UIImageView *)source).image;mark.tintColor=source.tintColor;}
        // IndicatorBox is in a row 1 icon view's own (unscaled) box; row 2's
        // icon views have that same box around their centre.
        CGRect box=IndicatorBox;
        box.origin.x+=icon.center.x-IconSize.width/2;
        box.origin.y+=icon.center.y-IconSize.height/2;
        mark.frame=box;
        if(mark.superview!=Strip)[Strip addSubview:mark];
        mark.hidden=NO;
    }
}
// Fills row 2 as the drawer starts opening; as many icons as row 1 fits.
static void Refresh(UIView *dock){
    UIView *model=RowOneIcon(dock,NULL);
    if(!model||!Strip)return;
    id vc=Call(dock.window.rootViewController,@"floatingDockViewController");
    id iconModel=Call(Call(Call(vc,@"suggestionsViewController"),@"suggestionsModel"),@"iconModel")?:Call(Call(vc,@"iconManager"),@"iconModel");
    LearnIndicator(dock);
    // Row 1 spaces its two lists by a margin, the divider and a margin.
    CGFloat gap=2*Margin+DividerFrame.size.width;
    NSUInteger (^capacity)(CGFloat)=^NSUInteger(CGFloat g){
        return (NSUInteger)fmax(1,floor((PlatBase.size.width-2*Margin-g+(Pitch-IconSize.width))/Pitch));
    };
    NSMutableArray<UIView *> *views=[NSMutableArray array];
    NSMutableSet<NSString *> *used=[NSMutableSet set];
    NSSet<NSString *> *userDock=UserDock(vc);
    for(id bundle in Items(MSRuntimeSettings()[@"DockDrawerPinned"])){
        if(views.count>=capacity(0))break;
        if(![bundle isKindOfClass:NSString.class]||[userDock containsObject:bundle]||[used containsObject:bundle])continue;
        UIView *v=IconView(bundle,model,iconModel);
        if(v){[views addObject:v];[used addObject:bundle];}
    }
    Pins=views.count;
    BOOL divide=Pins&&MSRuntimeFlag(@"DockDrawerDivider");
    NSUInteger cap=capacity(divide?gap:0);
    NSArray<NSString *> *bundles=RecentBundles(dock);
    Candidates=bundles.count;
    for(NSString *bundle in bundles){
        if(views.count>=cap)break;
        if([used containsObject:bundle])continue;
        UIView *v=IconView(bundle,model,iconModel);
        if(v){[views addObject:v];[used addObject:bundle];}
    }
    divide=divide&&views.count>Pins;
    for(NSString *bundle in Icons.allKeys)if(![used containsObject:bundle]){
        [objc_getAssociatedObject(Icons[bundle],&IndicatorKey) removeFromSuperview];
        [Icons[bundle] removeFromSuperview];[Icons removeObjectForKey:bundle];
    }
    CGFloat g=divide?gap:0;
    CGFloat total=views.count?views.count*Pitch-(Pitch-IconSize.width)+g:0;
    CGFloat x=(PlatBase.size.width-total)/2;
    for(NSUInteger i=0;i<views.count;i++){
        views[i].center=CGPointMake(x+i*Pitch+(i>=Pins?g:0)+IconSize.width/2,Margin+IconSize.height/2);
        if(views[i].superview!=Strip)[Strip addSubview:views[i]];
    }
    if(!Divider)Divider=[UIView new];
    UIView *source=DividerSource;
    // Row 1's divider gets its grey from SpringBoard's visual styling: a
    // colour blended through layer filters (Beta9.9.18 drew it plain white
    // without them), so copy the layer's whole look, not just the colour.
    Divider.backgroundColor=source.backgroundColor?:[UIColor colorWithWhite:1 alpha:.3];
    Divider.alpha=source?source.alpha:1;
    Divider.layer.backgroundColor=source?source.layer.backgroundColor:Divider.layer.backgroundColor;
    Divider.layer.compositingFilter=source.layer.compositingFilter;
    Divider.layer.filters=source.layer.filters;
    Divider.layer.opacity=source?source.layer.opacity:1;
    DividerLook=source?[NSString stringWithFormat:@"bg=%@ compositing=%@ filters=%@ opacity=%.2f alpha=%.2f sublayers=%lu subviews=%lu",
        source.backgroundColor,source.layer.compositingFilter,[source.layer.filters valueForKey:@"name"],source.layer.opacity,source.alpha,
        (unsigned long)source.layer.sublayers.count,(unsigned long)source.subviews.count]:@"no-source";
    CGFloat end=x+Pins*Pitch-(Pitch-IconSize.width);
    Divider.frame=CGRectMake(end+g/2-DividerFrame.size.width/2,DividerFrame.origin.y,DividerFrame.size.width,DividerFrame.size.height);
    Divider.hidden=!divide;
    if(Divider.superview!=Strip)[Strip addSubview:Divider];
    UpdateIndicators();
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
// SpringBoard is still animating the dock (its own animation, not our spring).
static BOOL Settling(UIView *dock){return !Springs&&dock.layer.animationKeys.count>0;}
static void Finish(UIView *dock,CGFloat target,NSUInteger tries){
    if(Settling(dock)&&tries<20){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC),dispatch_get_main_queue(),^{Finish(dock,target,tries+1);});
        return;
    }
    Springs++;
    [UIView animateWithDuration:.45 delay:0 usingSpringWithDamping:.86 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction
                     animations:^{P=target;Settle(dock,YES);} completion:^(__unused BOOL finished){Springs--;}];
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
            StartP=P;Origin=0;Waiting=Settling(dock);
            if(P<=0)Refresh(dock);
            __attribute__((fallthrough));
        case UIGestureRecognizerStateChanged:{
            // Pulled while SpringBoard still brings the dock in: hold the
            // drawer shut and measure the pull from where the dock settles.
            CGFloat t=[g translationInView:dock.superview].y;
            if(Waiting&&Settling(dock)){Origin=t;break;}
            Waiting=NO;
            P=fmax(0,fmin(1,StartP-(t-Origin)/e));
            Settle(dock,NO);
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:{
            // Where the flick would coast to decides open or closed.
            CGFloat v=[g velocityInView:dock.superview].y;
            CGFloat target=g.state==UIGestureRecognizerStateEnded?(P-v*.15/e>.5?1:0):(StartP>.5?1:0);
            Finish(dock,target,0);
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
    [NSNotificationCenter.defaultCenter addObserverForName:@"SBApplicationProcessStateDidChange" object:nil queue:NSOperationQueue.mainQueue
                                                usingBlock:^(__unused NSNotification *note){if(Strip&&!Strip.hidden)UpdateIndicators();}];
}

static void Status(double progress){
    static double last;static NSString *lastBody;
    if(!MSDiagnosticsActive())return;
    double now=CACurrentMediaTime();
    if(now-last<2)return;
    last=now;
    NSString *body=[NSString stringWithFormat:@"DRAWER status install=%@ on=%d pan=%d p=%.2f progress=%.2f extent=%.1f offset=%.1f margin=%.1f icon=%@ pitch=%.1f platter=%@ source=%@ candidates=%lu pins=%lu shown=%lu divider=%d iconScale=%.3f iconFail=%@ dividerLook={%@} indicator={%@} recentFront=%@",
        InstallState,DrawerOn(),DrawerPan!=nil,P,progress,Extent,LastOffset,Margin,NSStringFromCGSize(IconSize),Pitch,NSStringFromCGRect(PlatBase),Source,
        (unsigned long)Candidates,(unsigned long)Pins,(unsigned long)Shown,Divider&&!Divider.hidden,IconScale,IconFail,DividerLook,IndicatorLook,[[MRU subarrayWithRange:NSMakeRange(0,MIN(MRU.count,(NSUInteger)6))] componentsJoinedByString:@","]];
    if([body isEqualToString:lastBody])return;
    lastBody=body;
    MSDiagnosticsLog(@"World",body);
}
// World.m's 250ms reconcile: attaches or removes the drawer's pan, and
// closes the drawer once the dock has gone away.
void MSDockDrawerTick(UIView *dock,double progress){
    if(DrawerOn())RecordFront();
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
