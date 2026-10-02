#import "../XiaoMangAnimation.h"
#include <assert.h>
#include <stdio.h>

static CABasicAnimation *property(NSString *path) {
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:path];
    animation.duration = 30;
    return animation;
}
int main(void) {
    @autoreleasepool {
        for (NSString *path in @[@"position", @"position.x", @"bounds.size", @"transform", @"transform.rotation.z"])
            assert(XMGeometryAnimation(property(path)));
        for (NSString *path in @[@"opacity", @"backgroundColor", @"positioning", @"transformer", @""])
            assert(!XMGeometryAnimation(property(path)));
        CAAnimationGroup *geometry = [CAAnimationGroup animation];
        geometry.duration = 30;
        geometry.animations = @[property(@"position"),property(@"transform.scale")];
        assert(XMGeometryAnimation(geometry));
        CAAnimationGroup *nested = [CAAnimationGroup animation];
        nested.animations = @[geometry,property(@"bounds")];
        assert(XMGeometryAnimation(nested));
        CAAnimationGroup *mixed = [CAAnimationGroup animation];
        mixed.duration = 30;
        mixed.animations = @[geometry,property(@"opacity")];
        assert(!XMGeometryAnimation(mixed));
        assert(!XMGeometryAnimation([CAAnimationGroup animation]));
        assert(!XMGeometryAnimation([CATransition animation]));
        CALayer *outer = [CALayer layer], *child = [CALayer layer];
        [outer addSublayer:child];
        [outer addAnimation:property(@"position") forKey:@"nativeMovement"];
        [outer addAnimation:geometry forKey:@"geometryGroup"];
        [outer addAnimation:property(@"opacity") forKey:@"fade"];
        [outer addAnimation:mixed forKey:@"mixedGroup"];
        [child addAnimation:property(@"position") forKey:@"flyIn"];
        XMClearGeometryAnimations(outer);
        assert(![outer animationForKey:@"nativeMovement"] && ![outer animationForKey:@"geometryGroup"]);
        assert([outer animationForKey:@"fade"] && [outer animationForKey:@"mixedGroup"]);
        assert([child animationForKey:@"flyIn"]);
        puts("PASS: actual XiaoMang animation cleanup; outer geometry and geometry-only groups removed, opacity/mixed groups and child fly-in preserved");
    }
    return 0;
}
