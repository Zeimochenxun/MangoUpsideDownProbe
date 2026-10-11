#import "../PanCorrection.h"
#include <assert.h>
#include <stdio.h>

static BOOL Same(CGPoint a, CGPoint b) { return a.x == b.x && a.y == b.y; }
static void normalAndOriginalException(void) {
    for (unsigned throwOriginal = 0; throwOriginal <= 1; ++throwOriginal) {
        CGPoint before = CGPointMake(17,51);
        __block CGPoint current = before;
        __block unsigned setters = 0, calls = 0;
        __block unsigned depth = 0;
        __block BOOL caught = NO;
        @try {
            MSB8RunPanCorrection(before, ^(CGPoint value) {
                ++setters; current = value;
            }, ^{
                ++calls;
                assert(Same(current,CGPointMake(17,-51)));
                assert(depth == 1);
                if (throwOriginal) [NSException raise:@"OriginalCallback" format:@"expected"];
            }, &depth);
        } @catch (NSException *exception) {
            caught = [exception.name isEqualToString:@"OriginalCallback"];
        }
        assert(caught == (BOOL)throwOriginal);
        assert(calls == 1 && setters == 2 && depth == 0);
        assert(Same(current,before));
    }
}
static void restoreExceptionReleasesRecursionGuard(void) {
    CGPoint before = CGPointMake(-24,-73);
    __block unsigned setters = 0, calls = 0;
    unsigned depth = 0;
    BOOL caught = NO;
    @try {
        MSB8RunPanCorrection(before, ^(CGPoint value) {
            ++setters;
            if (setters == 1) assert(Same(value,CGPointMake(-24,73)));
            else {
                assert(Same(value,before));
                [NSException raise:@"RestoreSetter" format:@"expected"];
            }
        }, ^{ ++calls; }, &depth);
    } @catch (NSException *exception) { caught = [exception.name isEqualToString:@"RestoreSetter"]; }
    assert(caught && setters == 2 && calls == 1 && depth == 0);
}
int main(void) {
    @autoreleasepool {
        normalAndOriginalException();
        restoreExceptionReleasesRecursionGuard();
        id gesture=[NSObject new], other=[NSObject new];
        __block __weak id scope=nil;
        __block unsigned depth=0, calls=0;
        CGPoint translation=CGPointMake(15,40),velocity=CGPointMake(12,-80);
        assert(Same(MSB9PanQueryValue(translation,gesture,scope,depth,YES),translation));
        for (unsigned throws=0;throws<=1;throws++) {
            BOOL caught=NO;
            @try {
                MSB9RunPanQueries(gesture,^{
                    ++calls;
                    assert(scope==gesture && depth==1);
                    assert(Same(MSB9PanQueryValue(translation,gesture,scope,depth,YES),CGPointMake(15,-40)));
                    assert(Same(MSB9PanQueryValue(velocity,gesture,scope,depth,YES),CGPointMake(12,80)));
                    assert(Same(MSB9PanQueryValue(translation,other,scope,depth,YES),translation));
                    assert(Same(MSB9PanQueryValue(translation,gesture,scope,depth,NO),translation));
                    MSB9RunPanQueries(other,^{ assert(scope==other && depth==2); },&scope,&depth);
                    assert(scope==gesture && depth==1);
                    if (throws) [NSException raise:@"QueryCallback" format:@"expected"];
                },&scope,&depth);
            } @catch (NSException *exception) { caught=[exception.name isEqualToString:@"QueryCallback"]; }
            assert(caught==(BOOL)throws && !scope && depth==0);
        }
        assert(calls==2);
        puts("PASS: production Beta9 pan query scope covers translation/velocity, other gesture and thread passthrough, nested calls and exception cleanup without recognizer mutation");
        puts("PASS: actual production pan helper, temporary y only, one original call, normal/exception restoration, recursion guard recovery");
    }
    return 0;
}
