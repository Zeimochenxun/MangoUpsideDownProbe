#pragma once
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <roothide.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <math.h>
#import "RuntimeSettings.h"
#include "DiagnosticsPolicy.h"

#import "RuntimeRecording.h"

// Model fixed coordinates plus local presentation state, not a pixel test.
// Deliberately excludes description/text/accessibility/media-model properties.
static inline NSString *MSDiagnosticsViewLine(UIView *view) {
    if (!view) return @"view=nil";
    @try {
        CALayer *layer = view.layer, *presentation = layer.presentationLayer;
        CGRect bounds = layer.bounds, pb = presentation ? presentation.bounds : CGRectNull;
        CGPoint position = layer.position, anchor = layer.anchorPoint;
        CGPoint pp = presentation ? presentation.position : CGPointMake(NAN,NAN);
        CGPoint pa = presentation ? presentation.anchorPoint : CGPointMake(NAN,NAN);
        CATransform3D t = layer.transform, p = presentation ? presentation.transform : CATransform3DIdentity;
        CGPoint o=CGPointMake(NAN,NAN), x=o, y=o, corners[4]={o,o,o,o};
        UIWindow *window = view.window;
        id<UICoordinateSpace> fixed = window.screen.fixedCoordinateSpace;
        if ([view isKindOfClass:UIWindow.class]) fixed = ((UIWindow *)view).screen.fixedCoordinateSpace;
        if (fixed) {
            o=[view convertPoint:CGPointZero toCoordinateSpace:fixed];
            x=[view convertPoint:CGPointMake(1,0) toCoordinateSpace:fixed];
            y=[view convertPoint:CGPointMake(0,1) toCoordinateSpace:fixed];
            const CGPoint local[4]={{CGRectGetMinX(bounds),CGRectGetMinY(bounds)},
                {CGRectGetMaxX(bounds),CGRectGetMinY(bounds)}, {CGRectGetMaxX(bounds),CGRectGetMaxY(bounds)},
                {CGRectGetMinX(bounds),CGRectGetMaxY(bounds)}};
            for (unsigned i=0;i<4;i++) corners[i]=[view convertPoint:local[i] toCoordinateSpace:fixed];
        }
        return [NSString stringWithFormat:
            @"v=%p k=%@ up=%p w=%p hidden=%d alpha=%.3f b=(%.1f,%.1f,%.1f,%.1f) pos=(%.1f,%.1f) anchor=(%.2f,%.2f) T=(%.3f,%.3f,%.3f,%.3f,%.1f,%.1f) affine=%d persp=%.3f clip=%d/%d mask=%d layerHidden=%d opacity=%.3f p=%d pb=(%.1f,%.1f,%.1f,%.1f) pp=(%.1f,%.1f) pa=(%.2f,%.2f) pT=(%.3f,%.3f,%.3f,%.3f,%.1f,%.1f) pAffine=%d pHidden=%d pOpacity=%.3f fixed=(%.1f,%.1f;%.3f,%.3f;%.3f,%.3f) corners=(%.1f,%.1f;%.1f,%.1f;%.1f,%.1f;%.1f,%.1f)",
            (__bridge void *)view,NSStringFromClass(view.class),(__bridge void *)view.superview,(__bridge void *)window,view.hidden,view.alpha,
            bounds.origin.x,bounds.origin.y,bounds.size.width,bounds.size.height,position.x,position.y,anchor.x,anchor.y,
            t.m11,t.m12,t.m21,t.m22,t.m41,t.m42,CATransform3DIsAffine(t),t.m34,
            view.clipsToBounds,layer.masksToBounds,layer.mask!=nil,layer.hidden,layer.opacity,presentation!=nil,
            pb.origin.x,pb.origin.y,pb.size.width,pb.size.height,pp.x,pp.y,pa.x,pa.y,
            p.m11,p.m12,p.m21,p.m22,p.m41,p.m42,CATransform3DIsAffine(p),presentation ? presentation.hidden : NO,
            presentation ? presentation.opacity : NAN,o.x,o.y,x.x-o.x,x.y-o.y,y.x-o.x,y.y-o.y,
            corners[0].x,corners[0].y,corners[1].x,corners[1].y,corners[2].x,corners[2].y,corners[3].x,corners[3].y];
    } @catch (__unused NSException *exception) {
        return @"geometry-sample-error";
    }
}
