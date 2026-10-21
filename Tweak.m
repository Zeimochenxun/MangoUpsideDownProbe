// 双层 Dock: a second row ("drawer") for SpringBoard's iPad-style floating
// dock on iOS 16, split out of Mango Suite 1.2.0~beta9.9.24
// (modules/orientation/DockDrawer.m, device-tested Beta9.9.15-9.9.24), plus
// the one hook Lynx 2.5.4 turns that dock on with.
// - The dock: +[SBFloatingDockController isFloatingDockSupported] answers YES
//   while FloatingDock is on (read at launch, so a respring applies it),
//   otherwise whatever SpringBoard, or Lynx, says.
// - With the dock fully presented, an upward drag on it pulls the platter
//   taller like a drawer that was always two rows long: its bottom edge stays
//   put, row 1 rides up with the finger and row 2 slides out from that edge.
//   Down closes it. The dock's own pan (root controller as delegate) is told
//   not to begin for the drags the drawer takes.
// - SpringBoard presents the dock frame by frame through the root
//   controller's _layoutFloatingDockPresentationProgress:, writing the dock
//   view's transform (ty 0 shown, 109 hidden, the progress overshooting to
//   ~1.27). The drawer leaves that translation alone and grows only the
//   platter, so a pull mid-spring stays smooth; when the dock heads out the
//   drawer closes with it.
// - The platter's icon lists are flexible-height subviews that autoresizing
//   re-centred in the taller platter, so while the drawer is out only the
//   full-bleed backgrounds follow it. Row 2 lives in a clipping strip at the
//   platter's bottom edge, re-laid out whenever row 1 changes metric set
//   (327x73 at 60pt pitch, 330x90 at 74pt), its icons scaled to row 1's.
// - SpringBoard's dock remembers only the 3 recents row 1 shows, so the
//   drawer keeps its own list of every app that comes to the front, newest
//   first. Pinned apps go first and count as dock apps for the recents
//   model's own filter (_displayItemContainedInUserDock:), so they never
//   move into row 1.
// - Past fully open the pull meets rubber-band resistance and narrows the
//   dock slightly (a horizontal scale folded into the dock transform); the
//   release springs back with a slight bounce carrying the finger's speed.
// - Lynx's running marks under row 1 are copied under row 2's running apps.
// - Mango Suite's own copy of the drawer wins: while its pan
//   ("MangoDockDrawer") is on the dock, this one steps aside.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <substrate.h>
#include <sys/stat.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <math.h>
#include "DrawerMath.h"
#import "Settings.h"

// Declared only so ARC sees an init-family call; SBIconView implements it.
@interface NSObject (DoubleDockIconView)
- (instancetype)initWithConfigurationOptions:(unsigned long long)options listLayoutProvider:(id)provider;
@end
typedef struct { CGSize size; CGFloat scale; CGFloat continuousCornerRadius; } DDIconImageInfo;

static CGFloat P,StartP,LastOffset,Extent=66.5,Margin=6.5,Pitch=60;
static CGSize IconSize={60,60};
static CGRect PlatBase,PlatWritten;
static __weak UIView *Dock;
static UIView *Strip;
static UIPanGestureRecognizer *DrawerPan;
static NSMutableDictionary<NSString *,UIView *> *Icons;
static NSString *Source=@"none",*InstallState=@"not-run",*IconFail=@"none",*PinFilter=@"not-run",*FloatingState=@"not-run",*ProgressState=@"not-run";
static NSUInteger Shown,Candidates,Pins;
static CGFloat IconScale=NAN;
static CGRect DividerFrame={{0,12},{1,49}};
static __weak UIView *DividerSource;
static UIView *Divider;
static NSString *DividerLook=@"none";
static BOOL Closing,RefreshQueued,Yield,FloatingWanted;
static NSString *RowKey=@"";
static CGFloat DrawnWidth;
// The dock view and its presentation, as SpringBoard writes them.
static Class DockViewClass,DockRootClass;
static __weak UIView *DockView;
static double LayoutProgress=NAN;
static SEL PresentedSel;
static CGAffineTransform Incoming,Final;
static CGFloat LastSqueeze=1;

// Status lines for 导出诊断日志 in Settings; one rollover at 512KB.
static void Log(NSString *line){
    NSString *path=DDFile(@"DoubleDock.log");
    struct stat info;
    if(!stat(path.fileSystemRepresentation,&info)&&info.st_size>512*1024)
        rename(path.fileSystemRepresentation,[path stringByAppendingString:@".old"].fileSystemRepresentation);
    FILE *file=fopen(path.fileSystemRepresentation,"a");
    if(!file)return;
    char stamp[32];time_t now=time(NULL);struct tm local;
    localtime_r(&now,&local);
    strftime(stamp,sizeof stamp,"%m-%d %H:%M:%S",&local);
    fprintf(file,"%s %s\n",stamp,line.UTF8String);
    fclose(file);
}
static NSDictionary *S(void){
    static NSDictionary *snapshot;static CFTimeInterval last;
    CFTimeInterval now=CACurrentMediaTime();
    if(!snapshot||now-last>=.25){snapshot=DDReadSettings();last=now;}
    return snapshot;
}
static BOOL DrawerOn(void){return !Yield&&DDFlag(S(),@"Enabled");}
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
// The root controller's presented progress, NAN if it has none.
static double Presented(UIView *dock){
    UIViewController *root=dock.window.rootViewController;
    return PresentedSel&&[root isKindOfClass:DockRootClass]?((double(*)(id,SEL))objc_msgSend)(root,PresentedSel):NAN;
}
// The progress a transform write is for: the layout call it happens inside,
// else the presented progress.
static double DockProgress(UIView *dock){
    return isfinite(LayoutProgress)?LayoutProgress:Presented(dock);
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

static UIView *ImageView(UIView *iconView);
static void Refresh(UIView *dock);
static NSString *MetricKey(void);
static CGFloat Squeeze(UIView *dock);
// Grows the platter upward from SpringBoard's own frame by the drawer's
// pull, keeping its bottom edge and row 2's strip on that edge.
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
        UIView *image=ImageView(first);
        if(image)DrawnWidth=[image convertRect:image.bounds toView:first].size.width;
    }
    UIView *divider=Call(dock,@"dividerView");
    if([divider isKindOfClass:UIView.class]&&divider.superview){
        DividerSource=divider;
        CGRect r=[divider convertRect:divider.bounds toView:plat];
        if(r.size.width>0&&r.size.height>0)DividerFrame=r;
    }
    CGFloat d=DrawerOn()?fmax(0,fmin(1+DDStretch,P))*Extent:0;
    LastOffset=d;
    CGRect out=PlatBase;out.origin.y-=d;out.size.height+=d;
    PlatWritten=out;
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
    // Lynx's running marks for row 1 live outside the platter and the dock
    // view: keep them under their icons as row 1 rides up and squeezes.
    for(NSString *name in @[@"userIconListView",@"recentIconListView"])
        for(UIView *icon in ((UIView *)Call(dock,name)).subviews){
            UIView *mark=Call(icon,@"indicator");
            if(![mark isKindOfClass:UIView.class]||[mark isDescendantOfView:plat])continue;
            CGPoint middle=[dock.superview convertPoint:dock.center toView:mark.superview];
            mark.transform=CGAffineTransformMakeTranslation((mark.center.x-middle.x)*(Squeeze(dock)-1),-d);
        }
    // Row 1 changed metric set under an open row 2: lay row 2 out again.
    NSString *key=MetricKey();
    if(d>0&&Shown&&!RefreshQueued&&![key isEqualToString:RowKey]){
        RefreshQueued=YES;
        dispatch_async(dispatch_get_main_queue(),^{RefreshQueued=NO;if(Dock&&P>0)Refresh(Dock);});
    }
}
static NSString *MetricKey(void){
    return [NSString stringWithFormat:@"%.1f %.1f %@ %.1f %.1f",Margin,Pitch,NSStringFromCGSize(PlatBase.size),DrawnWidth,DividerFrame.size.height];
}
static CGFloat Squeeze(UIView *dock){
    return dock&&dock==Dock&&DrawerOn()?DDSqueeze(P):1;
}
static void (*OrigSetTransform)(UIView *,SEL,CGAffineTransform);
// Replays SpringBoard's last write with the current squeeze through the
// hooks below this one (Mango Suite's notch lift among them), and only while
// nothing else has written since. Inside an animation block it animates.
static void Reapply(UIView *dock){
    CGFloat squeeze=Squeeze(dock);
    if(!dock||dock!=DockView||squeeze==LastSqueeze||!CGAffineTransformEqualToTransform(dock.transform,Final))return;
    CGAffineTransform t=Incoming;t.a*=squeeze;
    LastSqueeze=squeeze;
    OrigSetTransform(dock,@selector(setTransform:),t);
    Final=dock.transform;
}
static void Settle(UIView *dock){
    Reapply(dock);
    [dock setNeedsLayout];
    [dock layoutIfNeeded];
}

// The drawer's own recency list, fed every 250ms with the app in front and
// kept across resprings. A first run starts from Mango Suite's list.
static const NSUInteger MRUCap=24;
static NSMutableArray<NSString *> *MRU;
static void RecordFront(void){
    if(!MRU){
        MRU=[NSMutableArray array];
        NSArray *saved=[NSArray arrayWithContentsOfFile:DDFile(@"recents.plist")]?:[NSArray arrayWithContentsOfFile:DDSuiteFile(@"dock-recents.plist")];
        for(id b in saved)if([b isKindOfClass:NSString.class]&&MRU.count<MRUCap)[MRU addObject:b];
    }
    NSString *front=Bundle(Call(UIApplication.sharedApplication,@"_accessibilityFrontMostApplication"),@"bundleIdentifier");
    if(!front||[MRU.firstObject isEqualToString:front])return;
    [MRU removeObject:front];
    [MRU insertObject:front atIndex:0];
    while(MRU.count>MRUCap)[MRU removeLastObject];
    [MRU writeToFile:DDFile(@"recents.plist") atomically:YES];
}
static NSSet<NSString *> *UserDock(id vc){
    NSMutableSet<NSString *> *out=[NSMutableSet set];
    for(id icon in Items(Call(Call(vc,@"dockListModel"),@"icons"))){NSString *b=Bundle(icon,@"applicationBundleID");if(b)[out addObject:b];}
    return out;
}
// Everything row 1 shows: its fixed apps and its recents.
static NSSet<NSString *> *RowOne(id vc){
    NSMutableSet<NSString *> *out=[UserDock(vc) mutableCopy];
    id model=Call(Call(vc,@"suggestionsViewController"),@"suggestionsModel");
    for(id item in Items(Call(model,@"currentDisplayItems"))){NSString *b=Bundle(item,@"bundleIdentifier");if(b)[out addObject:b];}
    return out;
}
// Recent apps, newest first: the drawer's own list, then the app
// switcher's if reachable, then SpringBoard's 3 dock recents. Row 1's apps
// and the app in front are skipped.
static NSArray<NSString *> *RecentBundles(UIView *dock){
    id vc=Call(dock.window.rootViewController,@"floatingDockViewController");
    id model=Call(Call(vc,@"suggestionsViewController"),@"suggestionsModel");
    NSMutableSet<NSString *> *skip=[RowOne(vc) mutableCopy];
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
    if(!iconView)return nil;
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
    ((void(*)(id,SEL,DDIconImageInfo))objc_msgSend)(view,NSSelectorFromString(@"setIconImageInfo:"),((DDIconImageInfo(*)(id,SEL))objc_msgSend)(model,info));
    for(NSString *name in @[@"setAllowsLabelArea:",@"setLabelHidden:"]){
        SEL setter=NSSelectorFromString(name);
        if([view respondsToSelector:setter])((void(*)(id,SEL,BOOL))objc_msgSend)(view,setter,[name isEqualToString:@"setLabelHidden:"]);
    }
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
            // Measured without the lift ApplyExtension may have given it.
            CGAffineTransform lift=mark.transform;
            mark.transform=CGAffineTransformIdentity;
            IndicatorBox=[mark convertRect:mark.bounds toView:icon];
            mark.transform=lift;
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
    NSMutableArray<UIView *> *views=[NSMutableArray array];
    NSMutableSet<NSString *> *used=[NSMutableSet set];
    NSSet<NSString *> *userDock=UserDock(vc);
    for(NSString *bundle in DDPinned(S())){
        if(views.count>=DDCapacity(PlatBase.size.width,Margin,0,Pitch,IconSize.width))break;
        if([userDock containsObject:bundle]||[used containsObject:bundle])continue;
        UIView *v=IconView(bundle,model,iconModel);
        if(v){[views addObject:v];[used addObject:bundle];}
    }
    Pins=views.count;
    BOOL divide=Pins&&DDFlag(S(),@"Divider");
    NSUInteger cap=DDCapacity(PlatBase.size.width,Margin,divide?gap:0,Pitch,IconSize.width);
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
    // Row 1 draws its 60pt icon boxes at SpringBoard's content scale (0.78
    // or 0.96 by metric set) and ours do not pick that up, so scale each to
    // row 1's drawn image size, again on every layout.
    UIView *theirs=ImageView(model);
    CGFloat want=theirs?[theirs convertRect:theirs.bounds toView:model].size.width:0;
    for(NSUInteger i=0;i<views.count;i++){
        views[i].transform=CGAffineTransformIdentity;
        views[i].bounds=CGRectMake(0,0,IconSize.width,IconSize.height);
        [views[i] layoutIfNeeded];
        UIView *mine=ImageView(views[i]);
        CGFloat have=mine?[mine convertRect:mine.bounds toView:views[i]].size.width:0;
        IconScale=want>0&&have>0?want/have:NAN;
        if(want>0&&have>0&&fabs(want/have-1)>.02)views[i].transform=CGAffineTransformMakeScale(want/have,want/have);
        views[i].center=CGPointMake(x+i*Pitch+(i>=Pins?g:0)+IconSize.width/2,Margin+IconSize.height/2);
        if(views[i].superview!=Strip)[Strip addSubview:views[i]];
    }
    if(!Divider)Divider=[UIView new];
    UIView *source=DividerSource;
    // Row 1's divider gets its grey from SpringBoard's visual styling: a
    // colour blended through layer filters, so copy the layer's whole look.
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
    RowKey=MetricKey();
}

// Up opens (or stretches), down closes only an open drawer; mostly-sideways
// drags, and a dock less than half way in or on its way out, are left to
// SpringBoard.
static BOOL Wants(UIPanGestureRecognizer *g){
    UIView *dock=g.view;
    double shown=Presented(dock);
    if(!DrawerOn()||!dock||dock!=Dock||Closing||(isfinite(shown)&&shown<.5))return NO;
    CGPoint v=[g velocityInView:dock.superview];
    if(fabs(v.y)<=fabs(v.x))return NO;
    return v.y<0||P>0;
}
// speed: the finger's speed toward target in points per second.
static void Animate(UIView *dock,CGFloat target,CGFloat speed,void (^done)(void)){
    CGFloat distance=fabs(target-P)*fmax(Extent,1);
    CGFloat initial=distance>1?fmax(0,fmin(20,speed/distance)):0;
    [UIView animateWithDuration:target>0?.55:.3 delay:0 usingSpringWithDamping:target>0?.78:1 initialSpringVelocity:initial
                        options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction
                     animations:^{P=target;Settle(dock);} completion:^(__unused BOOL finished){if(done)done();}];
}
@interface DoubleDockPan : NSObject <UIGestureRecognizerDelegate>
@end
@implementation DoubleDockPan
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
        case UIGestureRecognizerStateChanged:{
            P=DDPull(StartP-[g translationInView:dock.superview].y/e);
            [UIView performWithoutAnimation:^{Settle(dock);}];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:{
            CGFloat v=[g velocityInView:dock.superview].y;
            CGFloat target=DDReleaseOpen(g.state==UIGestureRecognizerStateEnded,P,StartP,v,e)?1:0;
            Animate(dock,target,target>0?-v:v,nil);
            break;
        }
        default:break;
    }
}
@end
static DoubleDockPan *PanTarget;

// Every presentation progress SpringBoard writes the dock at: once it heads
// out, the drawer closes along with it.
static void DrawerProgress(UIView *dock,double progress){
    static double last=1;
    BOOL leaving=DDLeaving(progress,last);
    if(isfinite(progress))last=progress;
    if(!leaving||dock!=Dock||P<=0||Closing)return;
    UIGestureRecognizerState s=DrawerPan.state;
    if(s==UIGestureRecognizerStateBegan||s==UIGestureRecognizerStateChanged)return;
    Closing=YES;
    dispatch_async(dispatch_get_main_queue(),^{Animate(dock,0,0,^{Closing=NO;});});
}

static void (*OrigLayoutProgress)(id,SEL,double);
static void HookLayoutProgress(id self,SEL cmd,double progress){
    double outer=LayoutProgress;
    LayoutProgress=progress;
    @try{OrigLayoutProgress(self,cmd,progress);}@finally{LayoutProgress=outer;}
}
static void HookSetTransform(UIView *self,SEL cmd,CGAffineTransform t){
    // isKindOfClass: as well, in case the hook landed on UIView's own method.
    if(!NSThread.isMainThread||![self isKindOfClass:DockViewClass]||![self.window.rootViewController isKindOfClass:DockRootClass]){OrigSetTransform(self,cmd,t);return;}
    DockView=self;
    DrawerProgress(self,DockProgress(self));
    Incoming=t;
    LastSqueeze=Squeeze(self);
    t.a*=LastSqueeze;
    OrigSetTransform(self,cmd,t);
    Final=self.transform;
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
// SpringBoard keeps a dock app out of the dock's recents; pinned row 2
// apps are kept out the same way.
static BOOL (*OrigContained)(id,SEL,id);
static BOOL HookContained(id self,SEL cmd,id item){
    if(OrigContained(self,cmd,item))return YES;
    NSString *bundle=DrawerOn()?Bundle(item,@"bundleIdentifier"):nil;
    return bundle&&[DDPinned(S()) containsObject:bundle];
}
static BOOL (*OrigSupported)(id,SEL);
static BOOL HookSupported(id self,SEL cmd){
    return FloatingWanted||OrigSupported(self,cmd);
}
// After the switch or the pinned list changes, have the recents re-filter.
static void ReloadRecentsIfPinsChanged(UIView *dock){
    static NSString *last;
    NSString *now=[NSString stringWithFormat:@"%d %@",DrawerOn(),[DDPinned(S()) componentsJoinedByString:@","]];
    if(!dock||[now isEqualToString:last])return;
    BOOL first=!last;
    last=now;
    id model=Call(Call(Call(dock.window.rootViewController,@"floatingDockViewController"),@"suggestionsViewController"),@"suggestionsModel");
    SEL reload=NSSelectorFromString(@"_reloadRecentsAndSuggestions");
    if((!first||DrawerOn())&&[model respondsToSelector:reload])((void(*)(id,SEL))objc_msgSend)(model,reload);
}

static BOOL ImageLoaded(const char *suffix){
    size_t n=strlen(suffix);
    for(uint32_t i=0;i<_dyld_image_count();i++){
        const char *name=_dyld_get_image_name(i);
        size_t l=name?strlen(name):0;
        if(l>=n&&!strcmp(name+l-n,suffix))return YES;
    }
    return NO;
}
// Once, when the dock first shows: what else decides the dock here.
static void Environment(void){
    static BOOL done;
    if(done)return;
    done=YES;
    Class controller=objc_getClass("SBFloatingDockController");
    int others=OrigSupported&&controller?OrigSupported(controller,sel_registerName("isFloatingDockSupported")):-1;
    id defaults=Call(Call(objc_getClass("SBDefaults"),@"localDefaults"),@"floatingDockDefaults");
    SEL recents=NSSelectorFromString(@"recentsEnabled");
    int recentsOn=[defaults respondsToSelector:recents]?((BOOL(*)(id,SEL))objc_msgSend)(defaults,recents):-1;
    Log([NSString stringWithFormat:@"environment floating=%@ wanted=%d withoutUs=%d lynx=%d mangoSuiteWorld=%d recentsEnabled=%d drawer=%@ progressHook=%@ pinFilter=%@",
        FloatingState,FloatingWanted,others,ImageLoaded("/Lynx.dylib"),ImageLoaded("/MangoUpsideDownWorld.dylib"),recentsOn,InstallState,ProgressState,PinFilter]);
}
static void Status(double progress){
    static double last;static NSString *lastBody;
    double now=CACurrentMediaTime();
    if(now-last<2)return;
    last=now;
    NSString *body=[NSString stringWithFormat:@"status on=%d yield=%d pan=%d p=%.2f progress=%.2f extent=%.1f offset=%.1f margin=%.1f icon=%@ pitch=%.1f platter=%@ source=%@ candidates=%lu pins=%lu shown=%lu divider=%d iconScale=%.3f iconFail=%@ dividerLook={%@} indicator={%@} recentFront=%@",
        DrawerOn(),Yield,DrawerPan!=nil,P,progress,Extent,LastOffset,Margin,NSStringFromCGSize(IconSize),Pitch,NSStringFromCGRect(PlatBase),Source,
        (unsigned long)Candidates,(unsigned long)Pins,(unsigned long)Shown,Divider&&!Divider.hidden,IconScale,IconFail,DividerLook,IndicatorLook,
        [[MRU subarrayWithRange:NSMakeRange(0,MIN(MRU.count,(NSUInteger)6))] componentsJoinedByString:@","]];
    if([body isEqualToString:lastBody])return;
    lastBody=body;
    Log(body);
}
// Every 250ms: attaches or removes the drawer's pan, records the app in
// front, and closes the drawer once the dock has gone away.
static void Tick(void){
    UIView *dock=DockView;
    double progress=dock?DockProgress(dock):NAN;
    if(dock)Environment();
    BOOL suite=NO;
    for(UIGestureRecognizer *g in dock.gestureRecognizers)if(g!=DrawerPan&&[g.name isEqualToString:@"MangoDockDrawer"])suite=YES;
    Yield=suite;
    if(DrawerOn())RecordFront();
    if([PinFilter isEqualToString:@"hooked"])ReloadRecentsIfPinsChanged(dock);
    BOOL on=dock&&DrawerOn();
    if(DrawerPan&&(!on||DrawerPan.view!=dock)){[DrawerPan.view removeGestureRecognizer:DrawerPan];DrawerPan=nil;}
    if(!on){
        // Put the platter back, then stay out of the dock's layout.
        if(Dock){P=0;Settle(Dock);Dock=nil;}
        Status(progress);
        return;
    }
    if(Dock!=dock){Dock=dock;[dock setNeedsLayout];}
    if(!DrawerPan){
        if(!PanTarget)PanTarget=[DoubleDockPan new];
        DrawerPan=[[UIPanGestureRecognizer alloc] initWithTarget:PanTarget action:@selector(pan:)];
        DrawerPan.delegate=PanTarget;DrawerPan.name=@"DoubleDockDrawer";
        [dock addGestureRecognizer:DrawerPan];
    }
    if(P>0&&isfinite(progress)&&progress<.01&&DrawerPan.state==UIGestureRecognizerStatePossible){P=0;Settle(dock);}
    Status(progress);
}

static BOOL ReturnsBool(Method m,unsigned args){
    char type[8]={0};
    if(!m||method_getNumberOfArguments(m)!=args)return NO;
    method_getReturnType(m,type,sizeof type);
    return type[0]=='B'||type[0]=='c';
}
static void InstallFloatingDock(void){
    Class controller=objc_getClass("SBFloatingDockController");
    SEL sel=sel_registerName("isFloatingDockSupported");
    Method m=controller?class_getClassMethod(controller,sel):NULL;
    if(!ReturnsBool(m,2)){FloatingState=m?@"signature":@"missing";return;}
    MSHookMessageEx(object_getClass(controller),sel,(IMP)HookSupported,(IMP *)&OrigSupported);
    FloatingState=@"hooked";
}
static void InstallDrawer(void){
    DockRootClass=objc_getClass("SBFloatingDockRootViewController");
    DockViewClass=objc_getClass("SBFloatingDockView");
    SEL begin=@selector(gestureRecognizerShouldBegin:),layout=sel_registerName("_layoutFloatingDockPresentationProgress:"),presented=sel_registerName("presentedProgress");
    if(!DockRootClass||!DockViewClass||![DockViewClass isSubclassOfClass:UIView.class]||!class_getInstanceMethod(DockRootClass,begin)){
        InstallState=@"missing-classes";return;}
    char type[8]={0};
    Method m=class_getInstanceMethod(DockRootClass,presented);
    if(m&&method_getNumberOfArguments(m)==2){method_getReturnType(m,type,sizeof type);if(type[0]=='d')PresentedSel=presented;}
    m=class_getInstanceMethod(DockRootClass,layout);
    if(m&&method_getNumberOfArguments(m)==3){
        method_getArgumentType(m,2,type,sizeof type);
        if(type[0]=='d'){MSHookMessageEx(DockRootClass,layout,(IMP)HookLayoutProgress,(IMP *)&OrigLayoutProgress);ProgressState=@"hooked";}
    }
    if(!OrigLayoutProgress)ProgressState=PresentedSel?@"presented-only":@"missing";
    MSHookMessageEx(DockViewClass,@selector(setTransform:),(IMP)HookSetTransform,(IMP *)&OrigSetTransform);
    MSHookMessageEx(DockViewClass,@selector(layoutSubviews),(IMP)HookLayout,(IMP *)&OrigLayout);
    MSHookMessageEx(DockViewClass,@selector(pointInside:withEvent:),(IMP)HookPointInside,(IMP *)&OrigPointInside);
    MSHookMessageEx(DockRootClass,begin,(IMP)HookRootShouldBegin,(IMP *)&OrigRootShouldBegin);
    InstallState=@"hooked";
    Class model=objc_getClass("SBFloatingDockSuggestionsModel");
    SEL contained=NSSelectorFromString(@"_displayItemContainedInUserDock:");
    m=model?class_getInstanceMethod(model,contained):NULL;
    if(ReturnsBool(m,3)){
        MSHookMessageEx(model,contained,(IMP)HookContained,(IMP *)&OrigContained);
        PinFilter=@"hooked";
    }else PinFilter=m?[NSString stringWithFormat:@"signature:%s",method_getTypeEncoding(m)]:@"missing";
    [NSNotificationCenter.defaultCenter addObserverForName:@"SBApplicationProcessStateDidChange" object:nil queue:NSOperationQueue.mainQueue
                                                usingBlock:^(__unused NSNotification *note){if(Strip&&!Strip.hidden)UpdateIndicators();}];
}

__attribute__((constructor)) static void DoubleDockInit(void){
    @autoreleasepool{
        if(![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"])return;
        [NSFileManager.defaultManager createDirectoryAtPath:DDDirectory() withIntermediateDirectories:YES attributes:nil error:nil];
        FloatingWanted=DDFlag(DDReadSettings(),@"FloatingDock");
        InstallFloatingDock();
        InstallDrawer();
        Log([NSString stringWithFormat:@"DoubleDock %@ loaded floating=%@ wanted=%d drawer=%@ progressHook=%@ pinFilter=%@",
            @DD_VERSION,FloatingState,FloatingWanted,InstallState,ProgressState,PinFilter]);
        if(![InstallState isEqualToString:@"hooked"])return;
        NSTimer *timer=[NSTimer timerWithTimeInterval:.25 repeats:YES block:^(__unused NSTimer *t){Tick();}];
        [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    }
}
