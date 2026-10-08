#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "../ObservedPan.h"
#include <assert.h>
#include <stdio.h>

@interface Recognizer : NSObject
@property(nonatomic) CGPoint translation, velocity;
@property(nonatomic) NSInteger state, action;
@property(nonatomic) unsigned calls;
@property(nonatomic,weak) id controller;
@property(nonatomic) SEL selector;
@property(nonatomic) BOOL fail, nest;
@end
@implementation Recognizer
@end
static void Native(id controller,SEL selector,id gesture) {
    Recognizer *g=gesture;
    assert(g.controller==controller && g.selector==selector);
    g.calls++;
    if (g.fail) [NSException raise:@"NativeFailure" format:@"preserve this exception"];
    if (g.nest) {
        g.nest=NO;
        MSRunObservedPan(controller,selector,g,Native,nil);
    }
    if (g.state==3) g.action=g.translation.y>30 ? 1 : (g.translation.y< -30 ? -1 : 0);
}
int main(void) { @autoreleasepool {
    NSObject *controller=[NSObject new]; SEL selector=@selector(description);
    // Native final +/-30 threshold and velocity must survive both preference
    // values, all states, horizontal movement, cancelled and nested callbacks.
    for (int requested=0;requested<2;requested++) for (int state=0;state<6;state++)
        for (int direction=-1;direction<=1;direction++) {
            Recognizer *g=[Recognizer new]; g.controller=controller;g.selector=selector;
            g.translation=CGPointMake(17,31*direction);g.velocity=CGPointMake(28,900*direction);g.state=state;
            __block unsigned before=0,after=0;
            MSRunObservedPan(controller,selector,g,Native,^(BOOL returned) {
                if (returned) after++; else before++;
                if (requested) [NSException raise:@"LoggerFailure" format:@"must not affect native outcome"];
            });
            assert(before==1 && after==1 && g.calls==1);
            assert(g.translation.x==17 && g.translation.y==31*direction);
            assert(g.velocity.x==28 && g.velocity.y==900*direction);
            assert(g.action==(state==3 ? direction : 0));
        }
    Recognizer *g=[Recognizer new];g.controller=controller;g.selector=selector;g.nest=YES;
    MSRunObservedPan(controller,selector,g,Native,nil);assert(g.calls==2);
    g.fail=YES; __block unsigned returned=0;BOOL escaped=NO;
    @try { MSRunObservedPan(controller,selector,g,Native,^(BOOL after) { returned+=after; }); }
    @catch (NSException *e) { escaped=[e.name isEqualToString:@"NativeFailure"]; }
    assert(escaped && returned==0 && g.calls==3);
    // Negative control: the removed final-y rewrite changes native selection.
    g.fail=NO;g.state=3;g.translation=CGPointMake(0,31);Native(controller,selector,g);assert(g.action==1);
    g.translation=CGPointMake(0,-31);Native(controller,selector,g);assert(g.action==-1);
    puts("PASS: production pan observer preserves native action thresholds, recognizer, callback count, nested calls and exceptions despite logger failure");
} return 0; }
