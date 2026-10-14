#pragma once
#import <QuartzCore/QuartzCore.h>

// Existing outer-window animations can have presentation endpoints that no
// longer match a reflected model frame. Never remove opacity or child-layer
// animations. A mixed group is not exclusively ours to discard.
static inline BOOL XMGeometryAnimation(CAAnimation *animation) {
    if ([animation isKindOfClass:CAPropertyAnimation.class]) {
        NSString *path = ((CAPropertyAnimation *)animation).keyPath;
        for (NSString *property in @[@"position", @"bounds", @"transform"])
            if ([path isEqualToString:property] || [path hasPrefix:[property stringByAppendingString:@"."]]) return YES;
        return NO;
    }
    if ([animation isKindOfClass:CAAnimationGroup.class]) {
        NSArray<CAAnimation *> *children = ((CAAnimationGroup *)animation).animations;
        if (!children.count) return NO;
        for (CAAnimation *child in children) if (!XMGeometryAnimation(child)) return NO;
        return YES;
    }
    return NO;
}

static inline void XMClearGeometryAnimations(CALayer *layer) {
    for (NSString *key in layer.animationKeys)
        if (XMGeometryAnimation([layer animationForKey:key])) [layer removeAnimationForKey:key];
}
