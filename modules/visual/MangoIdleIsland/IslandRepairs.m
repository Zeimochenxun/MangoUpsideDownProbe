#import "IslandRepairs.h"
#import "OpticalMath.h"
#import "../../../src/RuntimeSettings.h"
#import "../../../src/RuntimeDiagnostics.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

@interface MSIslandOpticalState : NSObject
@property(nonatomic,strong) CAGradientLayer *rim;
@property(nonatomic,strong) CAShapeLayer *mask, *halo;
@property(nonatomic) double lastSample,lastTick,lastLog;
@property(nonatomic) double sampleCost;
@property(nonatomic,weak) UIView *glass;
@property(nonatomic) BOOL colorsValid;
@property(nonatomic,copy) NSArray<UIColor *> *colors, *targets;
@property(nonatomic,copy) NSString *sampleResult;
@end
@implementation MSIslandOpticalState
- (void)dealloc { [self.rim removeFromSuperlayer]; [self.halo removeFromSuperlayer]; }
@end
static char OpticalStateKey;
static NSHashTable<UIView *> *NotificationViews;
static NSHashTable<UIView *> *OpticalHosts;
static BOOL Sampling;

BOOL MSIslandUsesOwnedRim(void) {
    return MSRuntimeFlag(@"RimGeometryEnabled") || MSRuntimeFlag(@"GlassAnimationEnabled") || MSRuntimeFlag(@"EdgeColorEnabled");
}
BOOL MSIslandRepairsNeedFrames(void) {
    for (UIView *host in OpticalHosts.allObjects) {
        if (!host.window || host.hidden || host.alpha<.01) continue;
        MSIslandOpticalState *state=objc_getAssociatedObject(host,&OpticalStateKey);
        if (MSRuntimeFlag(@"EdgeColorEnabled") && state.glass.window) return YES;
        if (!MSRuntimeFlag(@"GlassAnimationEnabled")) continue;
        for (UIView *view=state.glass;view;view=view.superview) {
            CALayer *layer=view.layer,*presentation=layer.presentationLayer;
            if (layer.animationKeys.count || (presentation &&
                (!CGRectEqualToRect(layer.bounds,presentation.bounds) ||
                 !CATransform3DEqualToTransform(layer.transform,presentation.transform) ||
                 fabs(layer.opacity-presentation.opacity)>.001))) return YES;
        }
    }
    return NO;
}
void MSIslandNotificationLayout(UIView *view) {
    if (![view isKindOfClass:UIView.class] || !NSThread.isMainThread) return;
    if (!NotificationViews) NotificationViews=[NSHashTable weakObjectsHashTable];
    if (NotificationViews.count<32) [NotificationViews addObject:view];
}
static BOOL VisibleNotification(UIView *host) {
    for (UIView *view in NotificationViews.allObjects) {
        if (!view.window || view.window!=host.window || view.hidden) continue;
        if (view!=host && ![view isDescendantOfView:host] && ![host isDescendantOfView:view]) continue;
        double opacity=1;
        for (UIView *v=view;v && v!=host;v=v.superview) {
            if (v.hidden) { opacity=0; break; }
            opacity*=(v.layer.presentationLayer ?: v.layer).opacity;
        }
        if (opacity>.01) return YES;
    }
    return NO;
}
static CGFloat VisibleOpacity(UIView *view,UIView *host) {
    CGFloat opacity=1;
    for (UIView *v=view;v && v!=host;v=v.superview) {
        if (v.hidden || v.layer.hidden) return 0;
        opacity*=(v.layer.presentationLayer ?: v.layer).opacity;
    }
    return fmax(0,fmin(1,opacity));
}
static BOOL IsGlass(UIView *view) {
    Class cls=object_getClass(view);
    if (![NSStringFromClass(cls) isEqualToString:@"MGLiveBackdropView"]) return NO;
    const char *image=class_getImageName(cls);
    NSString *name=image ? [[NSString stringWithUTF8String:image] lastPathComponent] : nil;
    if (![name isEqualToString:@"MangoHello.dylib"] && ![name isEqualToString:@"MangoPanda.dylib"]) return NO;
    SEL selector=sel_registerName("lgFilterType"); Method method=class_getInstanceMethod(cls,selector);
    if (!method || strcmp(method_getTypeEncoding(method),"@16@0:8")) return NO;
    return [((id (*)(id,SEL))objc_msgSend)(view,selector) isEqualToString:@"go.mangoos.island"];
}
static CGAffineTransform LayerMap(CALayer *from,CALayer *to) {
    CGPoint o=[from convertPoint:CGPointZero toLayer:to],x=[from convertPoint:CGPointMake(1,0) toLayer:to],y=[from convertPoint:CGPointMake(0,1) toLayer:to];
    return CGAffineTransformMake(x.x-o.x,x.y-o.y,y.x-o.x,y.y-o.y,o.x,o.y);
}
static BOOL FiniteMap(CGAffineTransform t) {
    return isfinite(t.a) && isfinite(t.b) && isfinite(t.c) && isfinite(t.d) && isfinite(t.tx) && isfinite(t.ty) && fabs(t.a*t.d-t.b*t.c)>1e-6;
}
static NSArray<UIWindow *> *BackgroundWindows(UIWindow *aperture) {
    NSMutableOrderedSet *windows=[NSMutableOrderedSet new];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop
    NSMutableArray *result=[NSMutableArray new];
    for (UIWindow *window in windows)
        if (window!=aperture && window.screen==aperture.screen && !window.hidden && window.alpha>.01 && window.windowLevel<aperture.windowLevel)
            [result addObject:window];
    [result sortUsingComparator:^NSComparisonResult(UIWindow *a,UIWindow *b) {
        return a.windowLevel<b.windowLevel ? NSOrderedAscending : (a.windowLevel>b.windowLevel ? NSOrderedDescending : NSOrderedSame);
    }];
    return result;
}
static NSArray<UIColor *> *SampleEdge(UIView *glass,CGRect local,NSString **result) {
    if (Sampling) return nil;
    UIWindow *aperture=glass.window;
    CALayer *source=glass.layer.presentationLayer ?: glass.layer;
    CALayer *window=aperture.layer.presentationLayer ?: aperture.layer;
    CGAffineTransform toWindow=LayerMap(source,window);
    CGPoint o=[aperture convertPoint:CGPointZero toCoordinateSpace:aperture.screen.fixedCoordinateSpace];
    CGPoint x=[aperture convertPoint:CGPointMake(1,0) toCoordinateSpace:aperture.screen.fixedCoordinateSpace];
    CGPoint y=[aperture convertPoint:CGPointMake(0,1) toCoordinateSpace:aperture.screen.fixedCoordinateSpace];
    CGAffineTransform toFixed=CGAffineTransformConcat(toWindow,CGAffineTransformMake(x.x-o.x,x.y-o.y,y.x-o.x,y.y-o.y,o.x,o.y));
    if (!FiniteMap(toFixed)) { *result=@"invalid-coordinate-map"; return nil; }
    CGRect island=CGRectApplyAffineTransform(local,toFixed);
    CGRect crop=CGRectIntersection(CGRectInset(island,-14,-14),aperture.screen.fixedCoordinateSpace.bounds);
    if (CGRectIsEmpty(crop) || CGRectIsNull(crop)) { *result=@"offscreen"; return nil; }
    const size_t width=96,height=48;
    uint8_t pixels[96*48*4]={0};
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(pixels,width,height,8,width*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) { *result=@"bitmap-unavailable"; return nil; }
    BOOL drew=NO,failed=NO; Sampling=YES;
    @try {
        UIGraphicsPushContext(context);
        CGContextTranslateCTM(context,0,height); CGContextScaleCTM(context,width/crop.size.width,-(double)height/crop.size.height);
        CGContextTranslateCTM(context,-crop.origin.x,-crop.origin.y);
        // Prefer the actual display so a foreground app's pixels can be
        // sampled too. Optional private export: never call a missing symbol.
        // No image leaves this stack frame or enters a log/export file.
        typedef CGImageRef (*ScreenCapture)(void);
        static ScreenCapture capture;
        static BOOL resolvedCapture;
        if (!resolvedCapture) { capture=(ScreenCapture)dlsym(RTLD_DEFAULT,"UIGetScreenImage"); resolvedCapture=YES; }
        CGImageRef screenImage=capture ? capture() : NULL;
        if (screenImage) {
            CGRect screenBounds=aperture.screen.fixedCoordinateSpace.bounds;
            double imageRatio=(double)CGImageGetWidth(screenImage)/CGImageGetHeight(screenImage);
            double screenRatio=screenBounds.size.width/screenBounds.size.height;
            if (isfinite(imageRatio) && fabs(imageRatio-screenRatio)<.005) {
                CGContextSaveGState(context);
                CGContextTranslateCTM(context,screenBounds.origin.x,CGRectGetMaxY(screenBounds));
                CGContextScaleCTM(context,1,-1);
                CGContextDrawImage(context,(CGRect){CGPointZero,screenBounds.size},screenImage);
                CGContextRestoreGState(context); drew=YES;
                *result=@"display-pixels";
            }
            CGImageRelease(screenImage);
        }
        unsigned count=0;
        for (UIWindow *background in (drew ? @[] : BackgroundWindows(aperture))) {
            if (++count>12) { failed=YES; break; }
            CGPoint bo=[background convertPoint:CGPointZero toCoordinateSpace:aperture.screen.fixedCoordinateSpace];
            CGPoint bx=[background convertPoint:CGPointMake(1,0) toCoordinateSpace:aperture.screen.fixedCoordinateSpace];
            CGPoint by=[background convertPoint:CGPointMake(0,1) toCoordinateSpace:aperture.screen.fixedCoordinateSpace];
            CGAffineTransform map=CGAffineTransformMake(bx.x-bo.x,bx.y-bo.y,by.x-bo.x,by.y-bo.y,bo.x,bo.y);
            if (!FiniteMap(map)) { failed=YES; continue; }
            CGContextSaveGState(context); CGContextConcatCTM(context,map);
            BOOL ok=[background drawViewHierarchyInRect:background.bounds afterScreenUpdates:NO];
            CGContextRestoreGState(context); drew|=ok; failed|=!ok;
        }
    } @catch (__unused NSException *exception) { failed=YES; }
    @finally { UIGraphicsPopContext(); Sampling=NO; CGContextRelease(context); }
    if (!drew || failed) { *result=@"background-capture-unavailable"; return nil; }
    MSColorBin bins[4][13]={0};
    CGAffineTransform inverse=CGAffineTransformInvert(toFixed);
    unsigned samples=0;
    for (size_t py=0;py<height;py++) for (size_t px=0;px<width;px++) {
        CGPoint fixed=CGPointMake(crop.origin.x+(px+.5)*crop.size.width/width,crop.origin.y+(py+.5)*crop.size.height/height);
        CGPoint p=CGPointApplyAffineTransform(fixed,inverse);
        // Sample only outside the island's rectangular footprint; exclude all
        // glass, content and our ring even if backdrop compositing includes it.
        if (CGRectContainsPoint(CGRectInset(local,-5,-5),p)) continue;
        double dx=(p.x-CGRectGetMidX(local))/(local.size.width*.5+14);
        double dy=(p.y-CGRectGetMidY(local))/(local.size.height*.5+14);
        unsigned sector=fabs(dx)>fabs(dy) ? (dx>0 ? 1 : 3) : (dy>0 ? 2 : 0);
        size_t index=(py*width+px)*4;
        if (pixels[index+3]<200) continue;
        double alpha=pixels[index+3]/255.0;
        MSRGB c={fmin(1,pixels[index]/255.0/alpha),fmin(1,pixels[index+1]/255.0/alpha),fmin(1,pixels[index+2]/255.0/alpha)};
        MSColorAccumulate(bins[sector],c); ++samples;
    }
    NSMutableArray *colors=[NSMutableArray new];
    for (unsigned side=0;side<4;side++) {
        MSRGB c;
        if (!MSColorDominant(bins[side],&c)) { *result=@"edge-partially-offscreen"; return nil; }
        [colors addObject:[UIColor colorWithRed:c.r green:c.g blue:c.b alpha:1]];
    }
    *result=[NSString stringWithFormat:@"%@ sampled=%u sectors=4 screenshot-retained=0",*result ?: @"springboard-window-pixels",samples];
    return colors;
}
static MSIslandOpticalState *State(UIView *host) {
    MSIslandOpticalState *state=objc_getAssociatedObject(host,&OpticalStateKey);
    if (state) return state;
    state=[MSIslandOpticalState new];
    state.rim=[CAGradientLayer layer]; state.rim.type=kCAGradientLayerConic;
    state.rim.startPoint=CGPointMake(.5,.5); state.rim.endPoint=CGPointMake(.5,0);
    state.mask=[CAShapeLayer layer]; state.mask.fillColor=UIColor.clearColor.CGColor; state.mask.strokeColor=UIColor.whiteColor.CGColor;
    state.mask.lineCap=kCALineCapRound; state.mask.lineJoin=kCALineJoinRound;
    state.rim.mask=state.mask;
    state.halo=[CAShapeLayer layer]; state.halo.fillColor=[UIColor colorWithWhite:0 alpha:.001].CGColor;
    state.halo.shadowColor=UIColor.blackColor.CGColor; state.halo.shadowOffset=CGSizeZero;
    state.rim.name=@"MangoSuiteOwnedOpticalRim"; state.halo.name=@"MangoSuiteOwnedNotificationHalo";
    objc_setAssociatedObject(host,&OpticalStateKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!OpticalHosts) OpticalHosts=[NSHashTable weakObjectsHashTable];
    [OpticalHosts addObject:host];
    return state;
}
void MSIslandRepairUpdate(UIView *host,UIView *idle,BOOL edgeOptIn) {
    if (!NSThread.isMainThread || Sampling) return;
    BOOL color=MSRuntimeFlag(@"EdgeColorEnabled"), rim=MSIslandUsesOwnedRim() && (edgeOptIn || color);
    BOOL halo=MSRuntimeFlag(@"ShortHaloEnabled") && VisibleNotification(host);
    MSIslandOpticalState *state=objc_getAssociatedObject(host,&OpticalStateKey);
    if ((!rim && !halo) || !host.window || host.hidden || host.alpha<.01) {
        [state.rim removeFromSuperlayer]; [state.halo removeFromSuperlayer]; return;
    }
    UIView *best=nil; CGFloat opacity=0;
    NSMutableArray *todo=[host.subviews mutableCopy]; unsigned count=0;
    while (todo.count && count++<256) {
        UIView *view=todo.lastObject; [todo removeLastObject];
        if ((view==idle || IsGlass(view)) && view.window && !CGRectIsEmpty(view.bounds)) {
            CGFloat visible=VisibleOpacity(view,host);
            if (visible>opacity) { best=view; opacity=visible; }
        }
        [todo addObjectsFromArray:view.subviews];
    }
    if (!best || opacity<.01 || todo.count) { [state.rim removeFromSuperlayer]; [state.halo removeFromSuperlayer]; return; }
    BOOL animated=MSRuntimeFlag(@"GlassAnimationEnabled");
    BOOL hasPair=animated && best.layer.presentationLayer && host.layer.presentationLayer;
    CALayer *source=hasPair ? best.layer.presentationLayer : best.layer;
    CALayer *target=hasPair ? host.layer.presentationLayer : host.layer;
    CGRect bounds=source.bounds;
    CGAffineTransform map=LayerMap(source,target);
    if (!FiniteMap(map) || !isfinite(bounds.size.width) || !isfinite(bounds.size.height) || bounds.size.width<1 || bounds.size.height<1) {
        [state.rim removeFromSuperlayer]; [state.halo removeFromSuperlayer]; return;
    }
    // Geometry is projected as a path, not by scaling separate left/right
    // caps. A single contour drives specular, color and halo every frame.
    double thickness=color ? MSRuntimeNumber(@"EdgeThickness",1.2,.5,4) : .7;
    CGRect projected=CGRectApplyAffineTransform(bounds,map);
    thickness=fmin(thickness,fmin(projected.size.width,projected.size.height)*.4);
    double radius=MSOpticalRadius(projected.size.width,projected.size.height,thickness);
    double nativeRadius=source.cornerRadius;
    if (nativeRadius>0 && isfinite(nativeRadius)) radius=fmin(radius,nativeRadius*fmin(hypot(map.a,map.b),hypot(map.c,map.d)));
    else if (projected.size.height>50) radius=fmin(radius,28);
    UIBezierPath *path=[UIBezierPath bezierPathWithRoundedRect:CGRectInset(projected,thickness*.5,thickness*.5) cornerRadius:radius];
    CGRect rect=CGPathGetBoundingBox(path.CGPath);
    if (!isfinite(rect.origin.x) || !isfinite(rect.origin.y) || !isfinite(rect.size.width) || !isfinite(rect.size.height)) return;
    state=State(host);
    state.glass=best;
    CFTimeInterval now=CACurrentMediaTime(); double elapsed=state.lastTick ? now-state.lastTick : 1.0/30; state.lastTick=now;
    double dynamics=MSRuntimeNumber(@"EdgeDynamics",.5,0,1);
    double sampleInterval=fmax(1.0/(4+4*dynamics),state.sampleCost>.02 ? .5 : 0);
    if (color && now-state.lastSample >= sampleInterval) {
        NSString *result=nil;
        NSArray *sample=SampleEdge(best,bounds,&result);
        state.sampleCost=CACurrentMediaTime()-now;
        state.lastSample=now; state.sampleResult=result;
        if (sample) { state.targets=sample; if (!state.colorsValid) state.colors=sample; state.colorsValid=YES; }
        else { state.colorsValid=NO; state.targets=nil; state.colors=nil; }
    }
    NSMutableArray *colors=[NSMutableArray new];
    if (color && state.colorsValid) {
        NSMutableArray *smoothed=[NSMutableArray new];
        for (unsigned side=0;side<4;side++) {
            CGFloat r,g,b,a,nr,ng,nb,na;
            [state.colors[side] getRed:&r green:&g blue:&b alpha:&a];
            // Explicit RGB channels keep interpolation in one color space.
            [state.targets[side] getRed:&nr green:&ng blue:&nb alpha:&na];
            MSRGB c=MSColorSmooth((MSRGB){r,g,b},(MSRGB){nr,ng,nb},elapsed,dynamics);
            UIColor *value=[UIColor colorWithRed:c.r green:c.g blue:c.b alpha:.45+.25*dynamics];
            [smoothed addObject:value]; [colors addObject:(__bridge id)value.CGColor];
        }
        state.colors=smoothed;
        [colors addObject:colors.firstObject];
    } else {
        for (NSNumber *alpha in @[@.40,@.12,@.26,@.10,@.40]) [colors addObject:(__bridge id)[UIColor colorWithWhite:1 alpha:alpha.doubleValue].CGColor];
        if (!edgeOptIn) rim=NO; // Capture failure does not invent background colors.
    }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    CGRect canvas=host.bounds;
    if (canvas.size.width>0 && canvas.size.height>0) {
        CGPoint center=CGPointMake((CGRectGetMidX(rect)-canvas.origin.x)/canvas.size.width,(CGRectGetMidY(rect)-canvas.origin.y)/canvas.size.height);
        double shimmer=(color && state.colorsValid) ? .12*dynamics*sin(now*.8) : 0;
        state.rim.startPoint=center;
        state.rim.endPoint=CGPointMake(center.x+sin(shimmer)*.5,center.y-cos(shimmer)*.5);
    }
    state.rim.bounds=canvas; state.rim.position=CGPointMake(CGRectGetMidX(canvas),CGRectGetMidY(canvas));
    state.mask.bounds=canvas; state.mask.position=CGPointMake(CGRectGetMidX(canvas),CGRectGetMidY(canvas));
    state.mask.path=path.CGPath; state.mask.lineWidth=thickness;
    state.rim.colors=colors;
    state.rim.opacity=opacity;
    if (rim) { if (state.rim.superlayer!=host.layer) [host.layer addSublayer:state.rim]; }
    else [state.rim removeFromSuperlayer];
    // Explicit shadowPath and minimum blur remove dependence on content height.
    UIView *haloParent=host.superview;
    CALayer *haloTarget=hasPair ? haloParent.layer.presentationLayer : haloParent.layer;
    CALayer *haloSource=source;
    if (!haloTarget) { haloTarget=haloParent.layer; haloSource=best.layer; }
    CGAffineTransform haloMap=haloTarget ? LayerMap(haloSource,haloTarget) : CGAffineTransformIdentity;
    CGRect haloRect=CGRectApplyAffineTransform(bounds,haloMap);
    double haloRadius=fmin(radius,MSOpticalRadius(haloRect.size.width,haloRect.size.height,0));
    UIBezierPath *haloPath=[UIBezierPath bezierPathWithRoundedRect:haloRect cornerRadius:haloRadius];
    CGRect haloCanvas=haloParent.bounds;
    state.halo.bounds=haloCanvas; state.halo.position=CGPointMake(CGRectGetMidX(haloCanvas),CGRectGetMidY(haloCanvas));
    state.halo.path=haloPath.CGPath; state.halo.shadowPath=haloPath.CGPath;
    state.halo.shadowRadius=fmax(8,fmin(16,bounds.size.height*.16));
    state.halo.shadowOpacity=halo ? .32*opacity*(host.layer.presentationLayer ?: host.layer).opacity : 0;
    if (halo && haloParent && FiniteMap(haloMap)) { if (state.halo.superlayer!=haloParent.layer) [haloParent.layer insertSublayer:state.halo below:host.layer]; }
    else [state.halo removeFromSuperlayer];
    [CATransaction commit];
    if (MSDiagnosticsActive() && now-state.lastLog >= 1) {
        state.lastLog=now;
        MSDiagnosticsLog(@"Glass",[NSString stringWithFormat:@"rim=%d geometry=%d presentation=%d halo=%d h=%.2f radius=%.2f thickness=%.2f dynamics=%.2f color=%d valid=%d capture=%@ sampleMs=%.1f intervalMs=%.1f opacity=%.3f path=(%.1f,%.1f,%.1f,%.1f)",rim,MSRuntimeFlag(@"RimGeometryEnabled"),hasPair,halo,bounds.size.height,radius,thickness,dynamics,color,state.colorsValid,state.sampleResult ?: @"off",state.sampleCost*1000,sampleInterval*1000,opacity,rect.origin.x,rect.origin.y,rect.size.width,rect.size.height]);
    }
}
