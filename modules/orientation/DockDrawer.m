// Dock second row ("drawer"), stage 1 (Beta9.9.14): read-only probe.
// While a diagnostics session runs, logs once per context (home/app x
// orientation, dock fully presented) the 16.5 names the drawer will be
// built on: the dock's subview tree, the controller/model graph behind the
// recents, how SpringBoard configures its dock icon views, launch selectors,
// and what the dock window hit-tests above the dock. A passive pan
// recognizer on the dock logs drags and the system recognizers active with
// them; it recognizes alongside everything and cancels no touches. Nothing
// here changes what the dock does.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>
#import "../../src/RuntimeDiagnostics.h"

void MSDockDrawerProbe(UIView *dock,double progress,BOOL inApp,long orientation);

static NSMutableArray<NSString *> *Pending;
// Split into diagnostics-sized parts; Flush() sends one per tick so the
// recorder's per-second cap never drops a part.
static void Queue(NSString *tag,NSArray<NSString *> *lines){
    if(!Pending)Pending=[NSMutableArray array];
    NSMutableArray<NSString *> *parts=[NSMutableArray array];
    NSMutableString *cur=[NSMutableString string];
    for(NSString *raw in lines){
        NSString *line=raw.length>1500?[raw substringToIndex:1500]:raw;
        if(cur.length&&cur.length+line.length>7000){[parts addObject:cur];cur=[NSMutableString string];}
        [cur appendFormat:@"\n%@",line];
    }
    if(cur.length)[parts addObject:cur];
    for(NSUInteger i=0;i<parts.count;i++)
        [Pending addObject:[NSString stringWithFormat:@"DOCKPROBE %@ %lu/%lu%@",tag,i+1,parts.count,parts[i]]];
}
static void Flush(void){
    if(!Pending.count)return;
    MSDiagnosticsLog(@"World",Pending.firstObject);
    [Pending removeObjectAtIndex:0];
}

static BOOL Framework(Class c){
    const char *n=class_getName(c);
    return !strncmp(n,"UI",2)||!strncmp(n,"NS",2)||!strncmp(n,"_UI",3)||!strncmp(n,"CA",2);
}
static NSString *Brief(id v){
    if(!v)return @"nil";
    @try{
        NSString *c=NSStringFromClass(object_getClass(v));
        if([v isKindOfClass:NSString.class]){NSString *s=v;return [NSString stringWithFormat:@"\"%@\"",s.length>60?[s substringToIndex:60]:s];}
        if([v isKindOfClass:NSNumber.class])return [v description];
        if([v isKindOfClass:NSArray.class]||[v isKindOfClass:NSOrderedSet.class]||[v isKindOfClass:NSSet.class]||[v isKindOfClass:NSDictionary.class]){
            id first=[v isKindOfClass:NSDictionary.class]?[[v allValues] firstObject]:[v isKindOfClass:NSSet.class]?[v anyObject]:[v firstObject];
            return [NSString stringWithFormat:@"%@[%lu]%@",c,(unsigned long)[v count],first?NSStringFromClass([first class]):@""];
        }
        return c;
    }@catch(__unused NSException *e){return @"?";}
}
// A zero-argument getter's value, only when the object really has one.
static NSString *Get(id obj,NSString *name){
    SEL sel=NSSelectorFromString(name);
    if(!obj||![obj respondsToSelector:sel])return @"-";
    NSMethodSignature *sig=[obj methodSignatureForSelector:sel];
    if(sig.numberOfArguments!=2)return @"args";
    const char *r=sig.methodReturnType;
    @try{
        switch(r[0]){
            case '@':return Brief(((id(*)(id,SEL))objc_msgSend)(obj,sel));
            case 'd':return [NSString stringWithFormat:@"%.2f",((double(*)(id,SEL))objc_msgSend)(obj,sel)];
            case 'f':return [NSString stringWithFormat:@"%.2f",((float(*)(id,SEL))objc_msgSend)(obj,sel)];
            case 'B':case 'c':case 'C':return [NSString stringWithFormat:@"%d",((BOOL(*)(id,SEL))objc_msgSend)(obj,sel)];
            case 'q':case 'l':return [NSString stringWithFormat:@"%lld",((long long(*)(id,SEL))objc_msgSend)(obj,sel)];
            case 'Q':case 'L':return [NSString stringWithFormat:@"%llu",((unsigned long long(*)(id,SEL))objc_msgSend)(obj,sel)];
            case 'i':return [NSString stringWithFormat:@"%d",((int(*)(id,SEL))objc_msgSend)(obj,sel)];
            case 'I':return [NSString stringWithFormat:@"%u",((unsigned(*)(id,SEL))objc_msgSend)(obj,sel)];
            case '{':{
                // Geometry-style structs: print as the doubles they hold.
                NSUInteger len=sig.methodReturnLength;
                if(len>64||len%8)return [NSString stringWithFormat:@"type:%.60s",r];
                double buf[8]={0};
                NSInvocation *inv=[NSInvocation invocationWithMethodSignature:sig];
                inv.target=obj;inv.selector=sel;[inv invoke];[inv getReturnValue:buf];
                NSMutableArray<NSString *> *vals=[NSMutableArray array];
                for(NSUInteger i=0;i<len/8;i++)[vals addObject:[NSString stringWithFormat:@"%.1f",buf[i]]];
                return [NSString stringWithFormat:@"{%@}",[vals componentsJoinedByString:@","]];
            }
        }
    }@catch(__unused NSException *e){return @"threw";}
    return [NSString stringWithFormat:@"type:%.40s",r];
}
static NSString *Gets(id obj,NSArray<NSString *> *names){
    NSMutableArray<NSString *> *out=[NSMutableArray array];
    for(NSString *n in names)[out addObject:[NSString stringWithFormat:@"%@=%@",n,Get(obj,n)]];
    return [out componentsJoinedByString:@" "];
}
static id Call(id obj,NSString *name){
    SEL sel=NSSelectorFromString(name);
    if(!obj||![obj respondsToSelector:sel])return nil;
    NSMethodSignature *sig=[obj methodSignatureForSelector:sel];
    if(sig.numberOfArguments!=2||sig.methodReturnType[0]!='@')return nil;
    @try{return ((id(*)(id,SEL))objc_msgSend)(obj,sel);}@catch(__unused NSException *e){return nil;}
}
// Own (non-UIKit) selectors along the class chain, optionally filtered.
static NSString *Methods(Class start,NSArray<NSString *> *keys,NSUInteger cap){
    NSMutableArray<NSString *> *out=[NSMutableArray array];
    NSUInteger n=0;
    for(Class c=start;c&&!Framework(c)&&n<cap;c=class_getSuperclass(c)){
        unsigned count=0;Method *m=class_copyMethodList(c,&count);
        NSMutableArray<NSString *> *own=[NSMutableArray array];
        for(unsigned i=0;i<count&&n<cap;i++){
            NSString *sel=NSStringFromSelector(method_getName(m[i]));
            BOOL hit=!keys;
            for(NSString *k in keys)if([sel rangeOfString:k options:NSCaseInsensitiveSearch].location!=NSNotFound){hit=YES;break;}
            if(hit){[own addObject:sel];n++;}
        }
        free(m);
        if(own.count)[out addObject:[NSString stringWithFormat:@"%s{%@}",class_getName(c),[own componentsJoinedByString:@","]]];
    }
    return out.count?[out componentsJoinedByString:@" "]:@"none";
}
static NSString *Has(const char *cls,NSArray<NSString *> *sels,BOOL meta){
    Class c=objc_getClass(cls);
    if(!c)return [NSString stringWithFormat:@"%s=missing",cls];
    NSMutableArray<NSString *> *out=[NSMutableArray array];
    for(NSString *s in sels){
        Method m=meta?class_getClassMethod(c,NSSelectorFromString(s)):class_getInstanceMethod(c,NSSelectorFromString(s));
        [out addObject:[NSString stringWithFormat:@"%@%@=%s",meta?@"+":@"",s,m?method_getTypeEncoding(m):"no"]];
    }
    return [NSString stringWithFormat:@"%s %@",cls,[out componentsJoinedByString:@" "]];
}
static BOOL Follow(id v){
    if([v isKindOfClass:UIView.class])return NO;
    NSString *c=NSStringFromClass([v class]);
    if(![c hasPrefix:@"SB"]&&![c hasPrefix:@"_SB"])return NO;
    for(NSString *k in @[@"Dock",@"Suggest",@"Recent",@"IconManager",@"IconModel",@"ListModel",@"ViewProvider",@"IconController"])
        if([c containsString:k])return YES;
    return NO;
}
static NSString *Ivars(id obj,NSMutableArray *follow){
    NSMutableArray<NSString *> *out=[NSMutableArray array];
    for(Class c=object_getClass(obj);c&&!Framework(c);c=class_getSuperclass(c)){
        unsigned count=0;Ivar *iv=class_copyIvarList(c,&count);
        for(unsigned i=0;i<count;i++){
            const char *type=ivar_getTypeEncoding(iv[i]),*name=ivar_getName(iv[i]);
            if(!type||!name)continue;
            NSString *val=nil;
            if(type[0]=='@'&&type[1]!='?'){
                id v=object_getIvar(obj,iv[i]);
                val=Brief(v);
                if(v&&follow&&Follow(v))[follow addObject:v];
            }else{
                const uint8_t *p=(const uint8_t *)(__bridge void *)obj+ivar_getOffset(iv[i]);
                switch(type[0]){
                    case 'd':val=[NSString stringWithFormat:@"%.2f",*(const double *)p];break;
                    case 'q':val=[NSString stringWithFormat:@"%lld",*(const long long *)p];break;
                    case 'Q':val=[NSString stringWithFormat:@"%llu",*(const unsigned long long *)p];break;
                    case 'B':case 'c':val=[NSString stringWithFormat:@"%d",*(const char *)p];break;
                    default:if(!strncmp(type,"{CGRect",7))val=NSStringFromCGRect(*(const CGRect *)p);
                }
            }
            if(val)[out addObject:[NSString stringWithFormat:@"%s=%@",name,val]];
        }
        free(iv);
    }
    return [out componentsJoinedByString:@" "];
}
static NSString *Owner(Class c,SEL s){
    IMP imp=class_getMethodImplementation(c,s);
    Class o=c;
    while(class_getSuperclass(o)&&class_getMethodImplementation(class_getSuperclass(o),s)==imp)o=class_getSuperclass(o);
    return NSStringFromClass(o);
}
static NSString *Geometry(UIView *v){
    if(CGAffineTransformIsIdentity(v.transform))return NSStringFromCGRect(v.frame);
    return [NSString stringWithFormat:@"c=%@ b=%@ ty=%.1f",NSStringFromCGPoint(v.center),NSStringFromCGSize(v.bounds.size),v.transform.ty];
}
static void Tree(UIView *v,NSUInteger depth,NSMutableArray<NSString *> *lines){
    if(lines.count>=90)return;
    BOOL icon=[NSStringFromClass(v.class) hasSuffix:@"IconView"]&&[v respondsToSelector:NSSelectorFromString(@"icon")];
    NSString *extra=icon?[@" " stringByAppendingString:Gets(v,@[@"location",@"icon"])]:@"";
    [lines addObject:[NSString stringWithFormat:@"%*s%@ %@%@ a=%.2f clip=%d mask=%lu cr=%.1f gr=%lu sub=%lu%@",(int)(depth*2),"",
        NSStringFromClass(v.class),Geometry(v),v.hidden?@" hidden":@"",v.alpha,v.clipsToBounds,(unsigned long)v.autoresizingMask,
        v.layer.cornerRadius,(unsigned long)v.gestureRecognizers.count,(unsigned long)v.subviews.count,extra]];
    if(!icon&&depth<6)for(UIView *s in v.subviews)Tree(s,depth+1,lines);
}
static UIView *FirstIconView(UIView *root){
    Class c=objc_getClass("SBIconView");
    NSMutableArray<UIView *> *queue=[NSMutableArray arrayWithObject:root];
    for(NSUInteger i=0;i<queue.count&&i<512;i++){
        if(c&&[queue[i] isKindOfClass:c])return queue[i];
        [queue addObjectsFromArray:queue[i].subviews];
    }
    return nil;
}

static void ContextLines(UIView *dock,NSMutableArray<NSString *> *lines){
    UIWindow *w=dock.window;
    UIViewController *root=w.rootViewController;
    [lines addObject:[NSString stringWithFormat:@"window %@ frame=%@ level=%.0f clip=%d hitTest=%@ pointInside=%@ rootVC=%@ rootView=%@ %@ rootHit=%@",
        NSStringFromClass(w.class),NSStringFromCGRect(w.frame),w.windowLevel,w.clipsToBounds,
        Owner(w.class,@selector(hitTest:withEvent:)),Owner(w.class,@selector(pointInside:withEvent:)),
        NSStringFromClass(root.class),NSStringFromClass(root.view.class),NSStringFromCGRect(root.view.frame),
        root.view?Owner(root.view.class,@selector(hitTest:withEvent:)):@"-"]];
    [lines addObject:[NSString stringWithFormat:@"dockHit hitTest=%@ pointInside=%@",
        Owner(dock.class,@selector(hitTest:withEvent:)),Owner(dock.class,@selector(pointInside:withEvent:))]];
    for(UIView *v=dock.superview;v&&v!=w;v=v.superview)
        [lines addObject:[NSString stringWithFormat:@"ancestor %@ %@ clip=%d",NSStringFromClass(v.class),Geometry(v),v.clipsToBounds]];
    // What the dock window returns at and above the platter: whether a row
    // drawn there would get its touches.
    UIView *plat=Call(dock,@"mainPlatterView");
    if(![plat isKindOfClass:UIView.class])plat=dock;
    CGRect pf=[plat convertRect:plat.bounds toView:w];
    NSMutableArray<NSString *> *hits=[NSMutableArray array];
    for(NSNumber *above in @[@-1,@0,@20,@60,@100]){
        CGFloat a=above.doubleValue;
        CGPoint pt=a<0?CGPointMake(CGRectGetMidX(pf),CGRectGetMidY(pf)):CGPointMake(CGRectGetMidX(pf),CGRectGetMinY(pf)-a);
        UIView *hit=nil;
        @try{hit=[w hitTest:pt withEvent:nil];}@catch(__unused NSException *e){}
        [hits addObject:[NSString stringWithFormat:@"%@:%@",a<0?@"center":above.stringValue,hit?NSStringFromClass(hit.class):@"nil"]];
    }
    [lines addObject:[NSString stringWithFormat:@"platterInWindow=%@ hits %@",NSStringFromCGRect(pf),[hits componentsJoinedByString:@" "]]];
    for(UIView *v=dock;v;v=v.superview)
        for(UIGestureRecognizer *g in v.gestureRecognizers)
            [lines addObject:[NSString stringWithFormat:@"gesture on=%@ %@ enabled=%d cancels=%d delegate=%@ name=%@",
                NSStringFromClass(v.class),NSStringFromClass(g.class),g.enabled,g.cancelsTouchesInView,
                g.delegate?NSStringFromClass([g.delegate class]):@"nil",g.name?:@"-"]];
    [lines addObject:[@"dock " stringByAppendingString:Gets(dock,@[@"mainPlatterView",@"userIconListView",@"recentIconListView",@"dividerView",
        @"paddingEdgeInsets",@"platterVerticalMargin",@"maximumIconSize",@"interIconSpacing",@"contentHeight",@"iconSize"])]];
    [lines addObject:[@"root " stringByAppendingString:Gets(root,@[@"presentedProgress",@"floatingDockHeight",@"maximumFloatingDockHeight",
        @"preferredVerticalMargin",@"floatingDockScreenFrame",@"floatingDockScreenPresentationFrame",@"translationFromFullyPresentedFrame",@"floatingDockViewTopMargin"])]];
    Tree(dock,0,lines);
}
static void GraphLines(UIView *dock,NSMutableArray<NSString *> *lines){
    UIViewController *root=dock.window.rootViewController;
    NSMutableArray<NSString *> *children=[NSMutableArray array];
    for(UIViewController *c in root.childViewControllers)[children addObject:NSStringFromClass(c.class)];
    [lines addObject:[NSString stringWithFormat:@"rootChildren %@",[children componentsJoinedByString:@","]]];
    id vc=Call(root,@"floatingDockViewController");
    [lines addObject:[@"dockVC " stringByAppendingString:Gets(vc,@[@"dockListModel",@"suggestionsViewController",@"iconViewProvider",
        @"iconManager",@"dockView",@"suggestionsModel",@"dockOffscreenProgress"])]];
    id svc=Call(vc,@"suggestionsViewController");
    [lines addObject:[@"suggestionsVC " stringByAppendingString:Gets(svc,@[@"suggestionsModel",@"suggestionsIconListModel",
        @"numberOfRecents",@"model",@"dataSource",@"iconListView"])]];
    id list=Call(Call(vc,@"dockListModel"),@"icons");
    if([list isKindOfClass:NSArray.class])
        for(id icon in [list subarrayWithRange:NSMakeRange(0,MIN([list count],(NSUInteger)10))])
            [lines addObject:[@"userDockIcon " stringByAppendingString:Gets(icon,@[@"applicationBundleID",@"leafIdentifier",@"displayName"])]];
    Class iconController=objc_getClass("SBIconController");
    id shared=iconController?Call(iconController,@"sharedInstance"):nil;
    // Walk ivars from the dock controllers outward, following only dock,
    // suggestion, recents and icon-model objects.
    NSMutableArray *queue=[NSMutableArray array];
    id starts[]={root,vc,svc,dock,shared};
    for(size_t i=0;i<sizeof starts/sizeof *starts;i++)if(starts[i])[queue addObject:starts[i]];
    NSHashTable *seen=[NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory|NSPointerFunctionsObjectPointerPersonality];
    NSMutableSet<Class> *dumped=[NSMutableSet set];
    NSArray<NSString *> *keys=@[@"icon",@"recent",@"suggest",@"model",@"launch",@"tap",@"displayitem",@"metric",@"platter",@"present",@"gesture",@"row",@"height"];
    NSUInteger described=0;
    for(NSUInteger i=0;i<queue.count&&described<24;i++){
        id o=queue[i];
        if([seen containsObject:o])continue;
        [seen addObject:o];described++;
        BOOL heavy=o==shared||[o isKindOfClass:UIView.class];
        [lines addObject:[NSString stringWithFormat:@"obj %@ %p ivars %@",Brief(o),(__bridge void *)o,Ivars(o,queue)]];
        if(![dumped containsObject:[o class]]){[dumped addObject:[o class]];
            [lines addObject:[NSString stringWithFormat:@"  methods %@",Methods([o class],keys,heavy?40:60)]];}
        NSString *c=NSStringFromClass([o class]);
        if([c containsString:@"SuggestionsModel"]){
            [lines addObject:[@"  model " stringByAppendingString:Gets(o,@[@"currentDisplayItems",@"recentsController",@"userDockListModel",
                @"maxSuggestions",@"recentsEnabled",@"suggestionsEnabled"])]];
            id items=Call(o,@"currentDisplayItems");
            if([items isKindOfClass:NSArray.class])
                for(id item in [items subarrayWithRange:NSMakeRange(0,MIN([items count],(NSUInteger)12))])
                    [lines addObject:[@"  item " stringByAppendingString:Gets(item,@[@"bundleIdentifier",@"type",@"uniqueIdentifier"])]];
        }
        if([c containsString:@"Recent"])
            [lines addObject:[@"  recents " stringByAppendingString:Gets(o,@[@"recentDisplayItems",@"recents",@"displayItems",@"recentDisplayItemsCount"])]];
    }
}
static void ApiLines(UIView *dock,NSMutableArray<NSString *> *lines){
    UIView *iconView=FirstIconView(dock);
    [lines addObject:[@"dockIconView " stringByAppendingString:Gets(iconView,@[@"location",@"delegate",@"listLayoutProvider",@"configurationOptions",
        @"icon",@"iconContentScale",@"iconImageInfo",@"allowsLabelArea",@"isLabelHidden",@"labelHidden",@"iconImageFrame",@"iconViewProvider"])]];
    if(iconView)[lines addObject:[NSString stringWithFormat:@"dockIconView frame=%@ delegateMethods %@",NSStringFromCGRect(iconView.frame),
        Methods([Call(iconView,@"delegate") class],@[@"tapped",@"launch",@"activate",@"shouldActivate"],40)]];
    [lines addObject:Has("SBIconView",@[@"initWithConfigurationOptions:",@"initWithConfigurationOptions:listLayoutProvider:",@"setIcon:",
        @"setLocation:",@"setDelegate:",@"setListLayoutProvider:",@"setIconContentScale:",@"setAllowsLabelArea:",@"setLabelHidden:",
        @"setIconImageInfo:",@"setIconViewProvider:"],NO)];
    [lines addObject:[@"SBIconView methods " stringByAppendingString:Methods(objc_getClass("SBIconView"),
        @[@"init",@"location",@"label",@"tap",@"imageinfo",@"contentscale",@"configuration"],60)]];
    [lines addObject:Has("SBIconController",@[@"sharedInstance"],YES)];
    [lines addObject:[@"SBIconController launch " stringByAppendingString:Methods(objc_getClass("SBIconController"),@[@"launch",@"tapped",@"activate",@"floatingdock"],40)]];
    [lines addObject:[@"SBHIconManager launch " stringByAppendingString:Methods(objc_getClass("SBHIconManager"),@[@"launch",@"tapped",@"activate",@"iconViewFor",@"dequeue",@"recycle"],50)]];
    [lines addObject:Has("SBIconModel",@[@"expectedIconForDisplayIdentifier:",@"applicationIconForBundleIdentifier:",@"leafIconForIdentifier:"],NO)];
    [lines addObject:Has("SpringBoard",@[@"launchApplicationWithIdentifier:suspended:",@"_accessibilityFrontMostApplication"],NO)];
    [lines addObject:Has("SBUIController",@[@"sharedInstance"],YES)];
    [lines addObject:[@"SBUIController activate " stringByAppendingString:Methods(objc_getClass("SBUIController"),@[@"activateApplication"],20)]];
    [lines addObject:Has("UIImage",@[@"_applicationIconImageForBundleIdentifier:format:scale:"],YES)];
    [lines addObject:[@"SBFloatingDockView " stringByAppendingString:Methods(objc_getClass("SBFloatingDockView"),
        @[@"metric",@"platter",@"icon",@"divider",@"height",@"padding",@"margin",@"layout",@"point",@"hit"],70)]];
    [lines addObject:[@"SBFloatingDockPlatterView " stringByAppendingString:Methods(objc_getClass("SBFloatingDockPlatterView"),nil,50)]];
    [lines addObject:[@"SBFloatingDockSuggestionsModel " stringByAppendingString:Methods(objc_getClass("SBFloatingDockSuggestionsModel"),nil,70)]];
    [lines addObject:[@"SBFloatingDockController " stringByAppendingString:Methods(objc_getClass("SBFloatingDockController"),
        @[@"suggest",@"recent",@"present",@"model",@"viewController",@"gesture"],50)]];
}

// Passive drag logger: where an up/down drag on the dock starts, how far it
// goes, and which recognizers along the dock's chain were active with it.
@interface MSDockProbePan : NSObject <UIGestureRecognizerDelegate>
@end
@implementation MSDockProbePan
- (BOOL)gestureRecognizer:(__unused UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(__unused UIGestureRecognizer *)o {
    return YES;
}
- (void)pan:(UIPanGestureRecognizer *)g {
    UIGestureRecognizerState s=g.state;
    if((s!=UIGestureRecognizerStateBegan&&s!=UIGestureRecognizerStateEnded&&s!=UIGestureRecognizerStateCancelled)||!MSDiagnosticsActive())return;
    UIView *dock=g.view,*host=dock.superview;
    CGPoint p=[g locationInView:dock],t=[g translationInView:host],v=[g velocityInView:host];
    NSMutableArray<NSString *> *active=[NSMutableArray array];
    for(UIView *x=dock;x;x=x.superview)
        for(UIGestureRecognizer *o in x.gestureRecognizers)
            if(o!=g&&o.state!=UIGestureRecognizerStatePossible)
                [active addObject:[NSString stringWithFormat:@"%@:%ld",NSStringFromClass(o.class),(long)o.state]];
    NSString *under=@"";
    if(s==UIGestureRecognizerStateBegan){UIView *hit=[dock hitTest:p withEvent:nil];under=[@" under=" stringByAppendingString:hit?NSStringFromClass(hit.class):@"nil"];}
    MSDiagnosticsLog(@"World",[NSString stringWithFormat:@"DOCKPROBE pan state=%ld point=%@ translation=%@ velocity=%@ dockTy=%.1f%@ active=%@",
        (long)s,NSStringFromCGPoint(p),NSStringFromCGPoint(t),NSStringFromCGPoint(v),dock.transform.ty,under,[active componentsJoinedByString:@","]]);
}
@end

static MSDockProbePan *PanTarget;
static __weak UIPanGestureRecognizer *Pan;
void MSDockDrawerProbe(UIView *dock,double progress,BOOL inApp,long orientation){
    BOOL active=MSDiagnosticsActive();
    if(!active||Pan.view!=dock){if(Pan)[Pan.view removeGestureRecognizer:Pan];}
    if(!active||!dock)return;
    Flush();
    if(!Pan){
        if(!PanTarget)PanTarget=[MSDockProbePan new];
        UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:PanTarget action:@selector(pan:)];
        pan.delegate=PanTarget;pan.cancelsTouchesInView=NO;pan.delaysTouchesEnded=NO;pan.name=@"MangoDockProbe";
        [dock addGestureRecognizer:pan];Pan=pan;
    }
    if(!dock.window||!(progress>=.99))return;
    static NSMutableSet<NSString *> *done;
    if(!done)done=[NSMutableSet set];
    NSString *key=[NSString stringWithFormat:@"%@-%ld",inApp?@"app":@"home",orientation];
    if([done containsObject:key])return;
    [done addObject:key];
    @try{
        NSMutableArray<NSString *> *lines=[NSMutableArray array];
        ContextLines(dock,lines);
        Queue(key,lines);
        if(done.count==1){
            [lines removeAllObjects];GraphLines(dock,lines);Queue(@"graph",lines);
            [lines removeAllObjects];ApiLines(dock,lines);Queue(@"api",lines);
        }
    }@catch(NSException *e){Queue(key,@[[@"threw " stringByAppendingString:e.reason?:@"?"]]);}
}
