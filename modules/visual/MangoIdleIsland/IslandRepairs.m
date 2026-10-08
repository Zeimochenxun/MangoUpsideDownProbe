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
@property(nonatomic,weak) UIView *host;
@property(nonatomic) BOOL colorsValid;
@property(nonatomic,copy) NSArray<UIColor *> *colors, *targets;
@property(nonatomic,copy) NSString *sampleResult;
@end
@implementation MSIslandOpticalState
- (void)dealloc {
    [self.rim removeFromSuperlayer]; [self.halo removeFromSuperlayer];
}
@end
static char OpticalStateKey;
static NSMapTable<id,UIView *> *NotificationHosts;
static NSHashTable<UIView *> *OpticalHosts;
static BOOL Sampling;
static void Detach(MSIslandOpticalState *state);
static BOOL HostVisible(UIView *host) {
    if (!host.window) return NO;
    for (UIView *view=host;view;view=view.superview)
        if (view.hidden || view.layer.hidden || (view.layer.presentationLayer ?: view.layer).opacity<.01) return NO;
    return YES;
}

BOOL MSIslandUsesOwnedRim(void) {
    return MSRuntimeFlag(@"RimGeometryEnabled") || MSRuntimeFlag(@"GlassAnimationEnabled") || MSRuntimeFlag(@"EdgeColorEnabled");
}
BOOL MSIslandRepairsNeedFrames(void) {
    for (UIView *host in OpticalHosts.allObjects) {
        MSIslandOpticalState *state=objc_getAssociatedObject(host,&OpticalStateKey);
        if (!HostVisible(host)) { Detach(state); continue; }
        if (MSRuntimeFlag(@"EdgeColorEnabled")) return YES;
        if (!MSRuntimeFlag(@"GlassAnimationEnabled")) continue;
        if (host.layer.mask.animationKeys.count) return YES;
        for (UIView *view=state.glass;view;view=view.superview) {
            CALayer *layer=view.layer,*presentation=layer.presentationLayer;
            if (layer.animationKeys.count || (presentation &&
                (!CGRectEqualToRect(layer.bounds,presentation.bounds) ||
                 !CATransform3DEqualToTransform(layer.transform,presentation.transform) ||
                 !CGPointEqualToPoint(layer.position,presentation.position) ||
                 fabs(layer.opacity-presentation.opacity)>.001))) return YES;
        }
    }
    return NO;
}
void MSIslandNotificationState(id element,UIView *host,BOOL notification) {
    if (!element || !NSThread.isMainThread) return;
    if (!NotificationHosts) NotificationHosts=[NSMapTable weakToWeakObjectsMapTable];
    if (!notification || ![host isKindOfClass:UIView.class]) [NotificationHosts removeObjectForKey:element];
    else if (NotificationHosts.count<32 || [NotificationHosts objectForKey:element]) [NotificationHosts setObject:host forKey:element];
}
static BOOL VisibleNotification(UIView *host) {
    for (UIView *view in NotificationHosts.objectEnumerator.allObjects) {
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
static MSIslandOpticalState *State(UIView *glass) {
    MSIslandOpticalState *state=objc_getAssociatedObject(glass,&OpticalStateKey);
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
    state.glass=glass;
    objc_setAssociatedObject(glass,&OpticalStateKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!OpticalHosts) OpticalHosts=[NSHashTable weakObjectsHashTable];
    [OpticalHosts addObject:glass];
    return state;
}

// Keep the contour in the glass's own layer space. Ancestor transforms and
// spring scale/position animations are then inherited exactly once.
static UIBezierPath *Contour(CALayer *source,CALayer *mask,CGFloat thickness,BOOL *nativeOut) {
    CALayer *shown=mask.presentationLayer ?: mask;
    if ([shown isKindOfClass:CAShapeLayer.class] && ((CAShapeLayer *)shown).path && CATransform3DIsAffine(shown.transform)) {
        CGPathRef raw=((CAShapeLayer *)shown).path;
        CGRect box=CGPathGetBoundingBox(raw);
        if (!CGRectIsEmpty(box) && isfinite(box.size.width) && isfinite(box.size.height)) {
            UIBezierPath *path=[UIBezierPath bezierPathWithCGPath:raw];
            CGAffineTransform t=CATransform3DGetAffineTransform(shown.transform);
            CGPoint anchor=CGPointMake(shown.bounds.origin.x+shown.anchorPoint.x*shown.bounds.size.width,
                                       shown.bounds.origin.y+shown.anchorPoint.y*shown.bounds.size.height);
            CGAffineTransform map=CGAffineTransformConcat(CGAffineTransformMakeTranslation(-anchor.x,-anchor.y),t);
            map.tx+=shown.position.x; map.ty+=shown.position.y;
            [path applyTransform:map];
            CGRect mapped=path.bounds;
            // A stale mask from the previous layout must not clip a new contour.
            if (FiniteMap(map) && CGRectContainsRect(CGRectInset(source.bounds,-1,-1),mapped) &&
                mapped.size.width>=source.bounds.size.width*.8 && mapped.size.height>=source.bounds.size.height*.8) {
                *nativeOut=YES; return path;
            }
        }
    }
    CGFloat radius=source.cornerRadius;
    if (!isfinite(radius) || radius<=0) radius=fmin(source.bounds.size.width,source.bounds.size.height)*.5;
    if (!isfinite(radius) || radius<0) radius=0;
    radius=fmin(radius, fmin(source.bounds.size.width,source.bounds.size.height)*.5);
    CGRect inset=CGRectInset(source.bounds,thickness*.5,thickness*.5);
    return [UIBezierPath bezierPathWithRoundedRect:inset cornerRadius:fmax(0,radius-thickness*.5)];
}
static void Detach(MSIslandOpticalState *state) {
    [state.rim removeFromSuperlayer]; [state.halo removeFromSuperlayer];
}
static void UpdateGlass(UIView *host,UIView *glass,BOOL rim,BOOL halo,BOOL edgeOptIn) {
    MSIslandOpticalState *state=State(glass); state.host=host;
    BOOL color=MSRuntimeFlag(@"EdgeColorEnabled"), animated=MSRuntimeFlag(@"GlassAnimationEnabled");
    CALayer *source=(animated ? glass.layer.presentationLayer : nil) ?: glass.layer;
    CGRect bounds=source.bounds;
    if (!isfinite(bounds.size.width) || !isfinite(bounds.size.height) || bounds.size.width<1 || bounds.size.height<1) { Detach(state); return; }
    double thickness=fmin(MSRuntimeNumber(@"EdgeThickness",1.2,.5,4),fmin(bounds.size.width,bounds.size.height)*.4);
    BOOL native=NO;
    CALayer *originalMask=source.mask;
    UIBezierPath *path=Contour(source,originalMask,thickness,&native);
    CGRect rect=path.bounds;
    if (!isfinite(rect.origin.x) || !isfinite(rect.origin.y)) { Detach(state); return; }
    CFTimeInterval now=CACurrentMediaTime(); double elapsed=state.lastTick ? now-state.lastTick : 1.0/60; state.lastTick=now;
    double dynamics=MSRuntimeNumber(@"EdgeDynamics",.5,0,1);
    double sampleInterval=fmax(1.0/(4+4*dynamics),state.sampleCost>.02 ? .5 : 0);
    if (color && now-state.lastSample>=sampleInterval) {
        NSString *result=nil; NSArray *sample=SampleEdge(glass,bounds,&result);
        state.sampleCost=CACurrentMediaTime()-now; state.lastSample=now; state.sampleResult=result;
        state.colorsValid=sample!=nil; state.targets=sample;
        if (sample && !state.colors) state.colors=sample;
        if (!sample) state.colors=nil;
    }
    NSMutableArray *colors=[NSMutableArray new];
    if (color && state.colorsValid) {
        NSMutableArray *smoothed=[NSMutableArray new];
        for (unsigned side=0;side<4;side++) {
            CGFloat r,g,b,a,nr,ng,nb,na;
            [state.colors[side] getRed:&r green:&g blue:&b alpha:&a];
            [state.targets[side] getRed:&nr green:&ng blue:&nb alpha:&na];
            MSRGB c=MSColorSmooth((MSRGB){r,g,b},(MSRGB){nr,ng,nb},elapsed,dynamics);
            UIColor *value=[UIColor colorWithRed:c.r green:c.g blue:c.b alpha:.45+.25*dynamics];
            [smoothed addObject:value]; [colors addObject:(__bridge id)value.CGColor];
        }
        state.colors=smoothed; [colors addObject:colors.firstObject];
    } else {
        for (NSNumber *alpha in @[@.40,@.12,@.26,@.10,@.40]) [colors addObject:(__bridge id)[UIColor colorWithWhite:1 alpha:alpha.doubleValue].CGColor];
        if (!edgeOptIn) rim=NO;
    }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    state.rim.bounds=bounds; state.rim.position=CGPointMake(CGRectGetMidX(bounds),CGRectGetMidY(bounds));
    state.mask.bounds=bounds; state.mask.position=CGPointMake(CGRectGetMidX(bounds),CGRectGetMidY(bounds));
    state.mask.path=path.CGPath; state.mask.lineWidth=native ? thickness*2 : thickness;
    // The original glass mask belongs to Mango throughout dismissal.
    state.rim.colors=colors; state.rim.opacity=1; state.rim.masksToBounds=YES;
    double shimmer=(color && state.colorsValid) ? .12*dynamics*sin(now*.8) : 0;
    state.rim.startPoint=CGPointMake(.5,.5); state.rim.endPoint=CGPointMake(.5+sin(shimmer)*.5,.5-cos(shimmer)*.5);
    if (rim) { if (state.rim.superlayer!=glass.layer) [glass.layer addSublayer:state.rim]; }
    else [state.rim removeFromSuperlayer];
    // Host ancestors often clip. Put only the shadow in the aperture window;
    // the island remains its native view and retains normal hit testing.
    UIWindow *window=glass.window;
    CALayer *target=(animated ? window.layer.presentationLayer : nil) ?: window.layer;
    CALayer *haloSource=source;
    if ((source!=glass.layer)!=(target!=window.layer)) { target=window.layer; haloSource=glass.layer; }
    CGAffineTransform map=LayerMap(haloSource,target);
    UIBezierPath *haloPath=[path copy]; [haloPath applyTransform:map];
    CGRect canvas=target.bounds;
    state.halo.bounds=canvas; state.halo.position=CGPointMake(CGRectGetMidX(canvas),CGRectGetMidY(canvas));
    state.halo.path=haloPath.CGPath; state.halo.shadowPath=haloPath.CGPath;
    state.halo.shadowRadius=fmax(8,fmin(16,bounds.size.height*.16));
    state.halo.shadowOpacity=.32*VisibleOpacity(glass,window);
    UIView *branch=glass;
    while (branch.superview && branch.superview!=window) branch=branch.superview;
    if (halo && window && branch.superview==window && FiniteMap(map)) {
        if (state.halo.superlayer!=window.layer) [window.layer insertSublayer:state.halo below:branch.layer];
    } else [state.halo removeFromSuperlayer];
    [CATransaction commit];
    if (MSDiagnosticsActive() && now-state.lastLog>=1) {
        state.lastLog=now;
        MSDiagnosticsLog(@"Glass",[NSString stringWithFormat:@"glass=%p host=%p localContour=1 contour=%@ rim=%d geometry=%d presentation=%d clipOwned=0 nativeMask=%@ nativeRadius=%.2f halo=%d haloParent=window h=%.2f thickness=%.2f dynamics=%.2f color=%d valid=%d capture=%@ opacity=%.3f path=(%.1f,%.1f,%.1f,%.1f)",
            (__bridge void *)glass,(__bridge void *)host,native ? @"native-mask" : @"local-rounded",rim,MSRuntimeFlag(@"RimGeometryEnabled"),source!=glass.layer,NSStringFromClass(originalMask.class) ?: @"none",source.cornerRadius,halo,bounds.size.height,thickness,dynamics,color,state.colorsValid,state.sampleResult ?: @"off",VisibleOpacity(glass,host),rect.origin.x,rect.origin.y,rect.size.width,rect.size.height]);
    }
}
void MSIslandRepairUpdate(UIView *host,UIView *idle,BOOL edgeOptIn) {
    if (!NSThread.isMainThread || Sampling) return;
    BOOL rim=MSIslandUsesOwnedRim() && (edgeOptIn || MSRuntimeFlag(@"EdgeColorEnabled"));
    BOOL halo=MSRuntimeFlag(@"ShortHaloEnabled") && VisibleNotification(host);
    NSMutableArray<UIView *> *glasses=[NSMutableArray new],*todo=[host.subviews mutableCopy]; unsigned count=0;
    while (todo.count && count++<256) {
        UIView *view=todo.lastObject; [todo removeLastObject];
        if ((view==idle || IsGlass(view)) && view.window && !CGRectIsEmpty(view.bounds) && VisibleOpacity(view,host)>.001) [glasses addObject:view];
        [todo addObjectsFromArray:view.subviews];
    }
    if (todo.count || !HostVisible(host) || (!rim && !halo)) [glasses removeAllObjects];
    for (UIView *glass in OpticalHosts.allObjects) {
        MSIslandOpticalState *state=objc_getAssociatedObject(glass,&OpticalStateKey);
        if (state.host==host && ![glasses containsObject:glass]) Detach(state);
    }
    // Track every visible active/idle layer across overlap; never jump between
    // the maximum-opacity candidates. Each rim inherits its own native fade.
    for (UIView *glass in glasses) UpdateGlass(host,glass,rim,halo && glass!=idle,edgeOptIn);
}
