#import "LauncherSurfaces.h"
#import "Beta9Identity.h"
#import "../../src/RuntimeDiagnostics.h"
#import <QuartzCore/QuartzCore.h>

static char SampleKey;
@interface MSSurfaceSample : NSObject
@property(nonatomic) double session, last;
@end
@implementation MSSurfaceSample
@end

static id Object(id object,const char *name) {
    Class cls=object_getClass(object);
    SEL sel=sel_registerName(name);
    Method method=class_getInstanceMethod(cls,sel);
    if (!B9ClassIsHello(cls) || !method ||
        strcmp(method_getTypeEncoding(method),"@16@0:8") ||
        !B9IMPIsHello(method_getImplementation(method))) return nil;
    return ((id (*)(id,SEL))objc_msgSend)(object,sel);
}
static void Sample(UIView *view,NSString *role) {
    if (![view isKindOfClass:UIView.class] || !view.window) return;
    MSSurfaceSample *sample=objc_getAssociatedObject(view,&SampleKey);
    if (!sample) {
        sample=[MSSurfaceSample new];
        objc_setAssociatedObject(view,&SampleKey,sample,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    double session=[MSRuntimeSettings()[@"DebugSessionToken"] doubleValue],now=CACurrentMediaTime();
    CALayer *layer=view.layer,*present=layer.presentationLayer;
    BOOL moving=present && (fabs(present.position.x-layer.position.x)>.2 ||
        fabs(present.position.y-layer.position.y)>.2 ||
        fabs(present.transform.m11-layer.transform.m11)>.002 ||
        fabs(present.transform.m22-layer.transform.m22)>.002);
    if (sample.session==session && now-sample.last<(moving ? .25 : 3)) return;
    sample.session=session; sample.last=now;
    UIWindow *window=view.window;
    CGPoint p=[layer convertPoint:CGPointZero toLayer:window.layer];
    CGPoint x=[layer convertPoint:CGPointMake(1,0) toLayer:window.layer];
    CGPoint y=[layer convertPoint:CGPointMake(0,1) toLayer:window.layer];
    CGPoint pp=present ? present.position : CGPointMake(NAN,NAN);
    MSDiagnosticsLog(@"Split",[NSString stringWithFormat:
        @"SURFACE observer=1 writes=0 hooks=0 role=%@ class=%@ view=%p parent=%p hidden=%d center=(%.1f,%.1f) bounds=(%.1f,%.1f) T=(%.3f,%.3f,%.3f,%.3f,%.1f,%.1f) layerBasis=(%.3f,%.3f,%.3f,%.3f) presentation=%d moving=%d pp=(%.1f,%.1f) pT=(%.3f,%.3f,%.1f,%.1f) clip=%d/%d",
        role,NSStringFromClass(view.class),(__bridge void *)view,(__bridge void *)view.superview,view.hidden,
        view.center.x,view.center.y,view.bounds.size.width,view.bounds.size.height,
        view.transform.a,view.transform.b,view.transform.c,view.transform.d,view.transform.tx,view.transform.ty,
        x.x-p.x,x.y-p.y,y.x-p.x,y.y-p.y,present!=nil,moving,pp.x,pp.y,
        present ? present.transform.m11 : NAN,present ? present.transform.m22 : NAN,
        present ? present.transform.m41 : NAN,present ? present.transform.m42 : NAN,
        view.clipsToBounds,layer.masksToBounds]);
}
void MSLauncherSurfacesObserve(UIViewController *controller) {
    if (!MSDiagnosticsActive() || !controller) return;
    @try {
        if (B9ClassIsHello(object_getClass(controller))) {
            const char *names[]={"launcherContainerView","launcherContainerViewRight",
                "appLibraryPickerLeft","appLibraryPickerRight","watchPickerView","watchPickerViewRight"};
            for (unsigned i=0;i<6;i++) Sample(Object(controller,names[i]),[NSString stringWithUTF8String:names[i]]);
        }
        // Observe an already presented menu without entering its layout stack.
        for (unsigned depth=0;controller && depth<8;depth++,controller=controller.presentedViewController) {
            UIViewController *menu=controller;
            if ([menu isKindOfClass:UINavigationController.class]) menu=((UINavigationController *)menu).viewControllers.firstObject;
            if ([NSStringFromClass(menu.class) isEqualToString:@"MangoMenuViewController"] &&
                B9ClassIsHello(object_getClass(menu)) && menu.isViewLoaded) Sample(menu.view,@"bottom-split-settings");
        }
    } @catch (__unused NSException *exception) {}
}
