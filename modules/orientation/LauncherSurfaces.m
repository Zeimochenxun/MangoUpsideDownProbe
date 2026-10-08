#import "LauncherSurfaces.h"
#import "Beta9Identity.h"
#import "../../src/RuntimeSettings.h"
#import "../../src/RuntimeDiagnostics.h"
#import <QuartzCore/QuartzCore.h>
#import <substrate.h>
#include "SurfaceReconcile.h"
static NSHashTable<UIView *> *Surfaces;
static NSHashTable<UIViewController *> *Menus;
static void (^Changed)(void);
static BOOL Writing;
static unsigned InstalledHooks;
static char Key;
@interface MSSurfaceState : NSObject
@property(nonatomic) MSSurfaceOwnership owned;
@property(nonatomic,copy) NSString *role;
@property(nonatomic) double lastLog, session;
@end
@implementation MSSurfaceState
@end
static MWTransform Math(CGAffineTransform t) { return (MWTransform){t.a,t.b,t.c,t.d,t.tx,t.ty}; }
static BOOL Signature(Class cls,SEL sel,const char *type) {
    Method method=class_getInstanceMethod(cls,sel);
    return method && !strcmp(method_getTypeEncoding(method),type);
}
static BOOL AffineChain(UIView *view) {
    unsigned depth=0;
    for (;view;view=view.superview) {
        if (++depth>32 || !CATransform3DIsAffine(view.layer.transform) ||
            !CATransform3DIsIdentity(view.layer.sublayerTransform)) return NO;
    }
    return YES;
}
static MSSurfaceSnapshot Read(void *context) {
    UIView *view=(__bridge UIView *)context;
    UIView *parent=view.superview;
    UIWindow *window=view.window;
    MSSplitSnapshot s={.transform=Math(view.transform),.center={view.center.x,view.center.y}};
    if (!parent || !window || window.screen!=UIScreen.mainScreen || !AffineChain(view) ||
        CGRectIsEmpty(view.bounds) || !isfinite(view.center.x) || !isfinite(view.center.y)) return (MSSurfaceSnapshot){.local=s};
    // Measure in parent-local coordinates for the post-write mirror check.
    // Physical orientation is separately proven through the actual layer graph.
    CGPoint local[3]={CGPointZero,CGPointMake(1,0),CGPointMake(0,1)};
    CGPoint physical[3];
    for (unsigned i=0;i<3;i++) {
        CGPoint p=[view.layer convertPoint:local[i] toLayer:parent.layer];
        s.points[i]=(MWPoint){p.x,p.y};
        CGPoint w=[view.layer convertPoint:local[i] toLayer:window.layer];
        physical[i]=[window convertPoint:w toCoordinateSpace:window.screen.fixedCoordinateSpace];
    }
    CGRect screen=window.screen.fixedCoordinateSpace.bounds;
    CGPoint pivot=[window convertPoint:CGPointMake(CGRectGetMidX(screen),CGRectGetMidY(screen)) fromCoordinateSpace:window.screen.fixedCoordinateSpace];
    pivot=[parent.layer convertPoint:pivot fromLayer:window.layer];
    s.pivot=(MWPoint){pivot.x,pivot.y};
    for (UIView *ancestor=parent;ancestor;ancestor=ancestor.superview) {
        MSSurfaceState *owner=objc_getAssociatedObject(ancestor,&Key);
        if (owner.owned.turn.applied) { s.pivot=s.center; break; }
    }
    BOOL physicalInverted=MWInvertedBasis(physical[1].x-physical[0].x,physical[2].y-physical[0].y,
                                        physical[2].x-physical[0].x,physical[1].y-physical[0].y);
    BOOL physicalUpright=MWInvertedBasis(physical[0].x-physical[1].x,physical[0].y-physical[2].y,
                                       physical[2].x-physical[0].x,physical[1].y-physical[0].y);
    s.eligible=physicalUpright || physicalInverted;
    return (MSSurfaceSnapshot){.local=s,.physicalUpright=physicalUpright};
}
static void Write(void *context,MWTransform t) {
    UIView *view=(__bridge UIView *)context;
    Writing=YES;
    @try { [UIView performWithoutAnimation:^{ view.transform=CGAffineTransformMake(t.a,t.b,t.c,t.d,t.tx,t.ty); }]; }
    @finally { Writing=NO; }
}
static void Track(UIView *view,NSString *role) {
    if (![view isKindOfClass:UIView.class] || !view.window) return;
    if (!Surfaces) Surfaces=[NSHashTable weakObjectsHashTable];
    if (Surfaces.count>=32 && ![Surfaces containsObject:view]) return;
    [Surfaces addObject:view];
    MSSurfaceState *state=objc_getAssociatedObject(view,&Key);
    if (!state) { state=[MSSurfaceState new]; objc_setAssociatedObject(view,&Key,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    state.role=role;
}
static id Object(id object,const char *name) {
    SEL sel=sel_registerName(name);
    if (!B9ClassIsHello(object_getClass(object)) || !Signature(object_getClass(object),sel,"@16@0:8")) return nil;
    return ((id (*)(id,SEL))objc_msgSend)(object,sel);
}
static UIView *MenuSurface(UIViewController *controller) {
    UIView *body=controller.isViewLoaded ? controller.view : nil;
    UIWindow *window=body.window;
    if (!window) return nil;
    CGRect screen=window.screen.fixedCoordinateSpace.bounds;
    UIViewController *root=window.rootViewController;
    BOOL menuRoot=root==controller || ([root isKindOfClass:UINavigationController.class] && ((UINavigationController *)root).viewControllers.firstObject==controller);
    for (UIView *view=body;view && view!=window;view=view.superview) {
        if (view==root.view && !menuRoot) break;
        CGRect box=[view.layer convertRect:view.bounds toLayer:window.layer];
        box=[window convertRect:box toCoordinateSpace:window.screen.fixedCoordinateSpace];
        if (fabs(box.size.width-screen.size.width)<2 && fabs(box.size.height-screen.size.height)<2 &&
            fabs(CGRectGetMidX(box)-CGRectGetMidX(screen))<2 && fabs(CGRectGetMidY(box)-CGRectGetMidY(screen))<2) return view;
    }
    // Wait for the sheet's full-screen presentation container instead of
    // moving its content outside an ancestor that still clips to one detent.
    return nil;
}
void MSLauncherSurfacesUpdate(UIViewController *controller,BOOL active) {
    (void)active;
    if (!NSThread.isMainThread || !B9ClassIsHello(object_getClass(controller))) return;
    const char *names[]={"launcherContainerView","launcherContainerViewRight","appLibraryPickerLeft","appLibraryPickerRight"};
    for (unsigned i=0;i<4;i++) Track(Object(controller,names[i]),[NSString stringWithUTF8String:names[i]]);
}
void MSLauncherSurfacesFinish(BOOL active) {
    if (Writing || !NSThread.isMainThread) return;
    NSMutableSet *currentMenus=[NSMutableSet new];
    for (UIViewController *menu in Menus.allObjects) {
        UIView *surface=MenuSurface(menu);
        if (surface) { [currentMenus addObject:surface]; Track(surface,@"bottom-split-settings"); }
    }
    // A picker nested inside a launcher container inherits that one turn.
    // Reconcile parents before their descendants; a native double-turn is
    // handled by the picker's own measured basis on the following callback.
    NSArray<UIView *> *ordered=[Surfaces.allObjects sortedArrayUsingComparator:^NSComparisonResult(UIView *a,UIView *b) {
        unsigned ad=0,bd=0;
        for (UIView *v=a;v && ad<32;v=v.superview) ++ad;
        for (UIView *v=b;v && bd<32;v=v.superview) ++bd;
        return ad<bd ? NSOrderedAscending : (ad>bd ? NSOrderedDescending : NSOrderedSame);
    }];
    static double recordedSession;
    double currentSession=[MSRuntimeSettings()[@"DebugSessionToken"] doubleValue];
    if (MSDiagnosticsActive() && recordedSession!=currentSession) {
        recordedSession=currentSession;
        MSDiagnosticsLog(@"Split",[NSString stringWithFormat:@"SURFACE install hooks=%u menus=%lu currentMenuContainers=%lu targets=%lu",InstalledHooks,(unsigned long)Menus.count,(unsigned long)currentMenus.count,(unsigned long)Surfaces.count]);
    }
    for (UIView *view in ordered) {
        MSSurfaceState *state=objc_getAssociatedObject(view,&Key);
        MSSurfaceOwnership owned=state.owned;
        BOOL inherited=NO;
        for (UIView *parent=view.superview;parent;parent=parent.superview) {
            MSSurfaceState *ancestor=objc_getAssociatedObject(parent,&Key);
            if (ancestor.owned.turn.applied) { inherited=YES; break; }
        }
        BOOL targetActive=active && (![state.role isEqualToString:@"bottom-split-settings"] || [currentMenus containsObject:view]);
        unsigned result=MSSurfaceReconcile(&owned,targetActive,Read,Write,(__bridge void *)view);
        state.owned=owned;
        double now=CACurrentMediaTime(), session=[MSRuntimeSettings()[@"DebugSessionToken"] doubleValue];
        if (MSDiagnosticsActive() && (state.session!=session || result || now-state.lastLog>3)) {
            state.session=session; state.lastLog=now;
            CGPoint p=[view.layer convertPoint:CGPointZero toLayer:view.window.layer];
            CGPoint x=[view.layer convertPoint:CGPointMake(1,0) toLayer:view.window.layer];
            CGPoint y=[view.layer convertPoint:CGPointMake(0,1) toLayer:view.window.layer];
            MSDiagnosticsLog(@"Split",[NSString stringWithFormat:@"SURFACE role=%@ view=%p active=%d inherited=%d result=%u applied=%d center=(%.1f,%.1f) bounds=(%.1f,%.1f) layerBasis=(%.3f,%.3f) model=(%.3f,%.3f,%.1f,%.1f)",state.role,(__bridge void *)view,active,inherited,result,owned.turn.applied,view.center.x,view.center.y,view.bounds.size.width,view.bounds.size.height,x.x-p.x,y.y-p.y,view.transform.a,view.transform.d,view.transform.tx,view.transform.ty]);
        }
    }
}
static void (*MenuRotation)(id,SEL), (*MenuLayout)(id,SEL), (*PickerLayout)(id,SEL), (*PickerExpanded)(id,SEL);
static void MenuObserved(UIViewController *controller) {
    if (!NSThread.isMainThread || Writing) return;
    if (!Menus) Menus=[NSHashTable weakObjectsHashTable];
    if (Menus.count<8) [Menus addObject:controller];
    if (Changed) Changed();
}
static void HookMenuRotation(id self,SEL cmd) { MenuRotation(self,cmd); MenuObserved(self); }
static void HookMenuLayout(id self,SEL cmd) { MenuLayout(self,cmd); MenuObserved(self); }
static void HookPickerLayout(id self,SEL cmd) { PickerLayout(self,cmd); if (!Writing && NSThread.isMainThread && Changed) Changed(); }
static void HookPickerExpanded(id self,SEL cmd) { PickerExpanded(self,cmd); if (!Writing && NSThread.isMainThread && Changed) Changed(); }
void MSLauncherSurfacesInstall(void (^changed)(void)) {
    Changed=[changed copy];
    Class menu=objc_getClass("MangoMenuViewController"),picker=objc_getClass("MangoAppLibraryPickerView");
    struct { Class cls; const char *name; IMP hook; IMP *original; } entries[]={
        {menu,"mango_updateMenuRotation",(IMP)HookMenuRotation,(IMP *)&MenuRotation},
        {menu,"viewDidLayoutSubviews",(IMP)HookMenuLayout,(IMP *)&MenuLayout},
        {picker,"layoutSubviews",(IMP)HookPickerLayout,(IMP *)&PickerLayout},
        {picker,"updateExpandedFrame",(IMP)HookPickerExpanded,(IMP *)&PickerExpanded}};
    for (unsigned i=0;i<4;i++) {
        SEL sel=sel_registerName(entries[i].name);
        if (B9ClassIsHello(entries[i].cls) && Signature(entries[i].cls,sel,"v16@0:8") && B9IMPIsHello(class_getMethodImplementation(entries[i].cls,sel))) {
            MSHookMessageEx(entries[i].cls,sel,entries[i].hook,entries[i].original); InstalledHooks|=1u<<i;
        }
    }
}
