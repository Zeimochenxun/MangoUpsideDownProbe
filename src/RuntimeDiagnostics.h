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

// This recorder observes existing decisions; it never sets a view or preference.
// Each translation unit has a finite session. All callers are on the main queue.
static inline BOOL MSDiagnosticsActive(void) {
    if (!NSThread.isMainThread) return NO;
    if (!MSRuntimeFlag(@"DebugEnabled")) return NO;
    id token = MSRuntimeSettings()[@"DebugSessionToken"];
    double began = [token isKindOfClass:NSNumber.class] ? [token doubleValue] : 0;
    double now = NSDate.date.timeIntervalSince1970;
    return MSDiagnosticSessionActive(1,began,now);
}

static inline void MSDiagnosticsLog(NSString *module, NSString *message) {
    if (!MSDiagnosticsActive() || !message.length ||
        !([module isEqualToString:@"Idle"] || [module isEqualToString:@"World"] || [module isEqualToString:@"Split"] || [module isEqualToString:@"Glass"])) return;
    int fd = -1;
    @try {
        static NSTimeInterval rateSecond;
        static unsigned count;
        NSTimeInterval timestamp = NSDate.date.timeIntervalSince1970;
        NSTimeInterval second = floor(timestamp);
        if (rateSecond != second) { rateSecond = second; count = 0; }
        if (count++ >= 8) return;
        const char *mapped = jbroot("/var/mobile/Library/Logs/MangoSuiteDiagnostics");
        if (!mapped) return;
        struct stat info;
        if (mkdir(mapped, 0700) && errno != EEXIST) return;
        if (lstat(mapped, &info) || !S_ISDIR(info.st_mode) || info.st_uid != getuid()) return;
        NSString *path = [[NSString stringWithUTF8String:mapped] stringByAppendingPathComponent:[module stringByAppendingString:@".log"]];
        fd = open(path.fileSystemRepresentation, O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW|O_NONBLOCK, 0600);
        if (fd < 0) return;
        if (fstat(fd, &info) || !S_ISREG(info.st_mode) || info.st_uid != getuid() || info.st_nlink != 1) return;
        if (message.length > 8192) message = [[message substringToIndex:8100] stringByAppendingString:@"\n[message-truncated]"];
        NSData *line = [[NSString stringWithFormat:@"%.3f version=1.2.0~beta9.4 session=%.3f pid=%d module=%@ %@\n", timestamp, [MSRuntimeSettings()[@"DebugSessionToken"] doubleValue], getpid(), module, message] dataUsingEncoding:NSUTF8StringEncoding];
        if (info.st_size + (off_t)line.length > 256 * 1024 && ftruncate(fd, 0)) return;
        const uint8_t *bytes = line.bytes;
        size_t remaining = line.length;
        while (remaining) {
            ssize_t written = write(fd, bytes, remaining);
            if (written < 0 && errno == EINTR) continue;
            if (written <= 0) break;
            bytes += written; remaining -= (size_t)written;
        }
    } @catch (__unused NSException *exception) {
        // A diagnostic failure cannot change a native callback's outcome.
    } @finally {
        if (fd >= 0) close(fd);
    }
}

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
