#import "../XiaoMangMutation.h"
#include <assert.h>
#include <stdio.h>

static void normalAndNested(void) {
    __block unsigned depth=0, restores=0, outerCalls=0, nestedCalls=0, finishes=0;
    __block NSInteger model=200; // Owned display geometry; baseline is 20.
    __block NSMutableString *sequence=[NSMutableString string];
    XMRunGeometryMutation(&depth, ^{
        ++restores; [sequence appendString:@"R"]; model=20;
    }, ^{
        ++outerCalls; [sequence appendString:@"O"]; assert(model==20 && depth==1);
        XMRunGeometryMutation(&depth, ^{
            ++restores; assert(0 && "nested restore must not run");
        }, ^{
            ++nestedCalls; [sequence appendString:@"N"]; assert(model==20 && depth==2);
            model=23; // Mango writes new logical geometry inside a nested setter.
        }, ^{
            ++finishes; assert(0 && "nested finish must not run");
        });
        assert(model==23 && depth==1);
    }, ^{
        ++finishes; [sequence appendString:@"F"]; assert(model==23);
        model=203; // Reconcile applies one turn to the new baseline.
    });
    assert(depth==0 && restores==1 && outerCalls==1 && nestedCalls==1 && finishes==1);
    assert(model==203 && [sequence isEqualToString:@"RONF"]);
}
static void exceptionRecovery(void) {
    // Actual helper must release nesting state for failures at every stage.
    // A failing restore must never run Mango's setter against owned geometry.
    for(unsigned failure=0;failure<3;++failure) {
        __block unsigned depth=0, restores=0, calls=0, finishes=0;
        __block BOOL caught=NO;
        @try {
            XMRunGeometryMutation(&depth, ^{
                ++restores;
                if(failure==0) [NSException raise:@"ExpectedFailure" format:@"restore"];
            }, ^{
                ++calls; assert(depth==1);
                if(failure==1) [NSException raise:@"ExpectedFailure" format:@"original"];
            }, ^{
                ++finishes;
                if(failure==2) [NSException raise:@"ExpectedFailure" format:@"finish"];
            });
        } @catch(NSException *exception) {
            caught=[exception.name isEqualToString:@"ExpectedFailure"];
        }
        assert(caught && depth==0 && restores==1 && finishes==1);
        assert(calls==(failure==0?0u:1u));
        // A subsequent independent mutation must still take the outer path.
        XMRunGeometryMutation(&depth, ^{++restores;}, ^{++calls;}, ^{++finishes;});
        assert(depth==0 && restores==2 && finishes==2);
        assert(calls==(failure==0?1u:2u));
    }
}
static void nestedExceptionRecovery(void) {
    __block unsigned depth=0, restores=0, calls=0, finishes=0;
    BOOL caught=NO;
    @try {
        XMRunGeometryMutation(&depth, ^{++restores;}, ^{
            ++calls;
            XMRunGeometryMutation(&depth, ^{++restores;}, ^{
                ++calls; assert(depth==2);
                [NSException raise:@"NestedFailure" format:@"expected"];
            }, ^{++finishes;});
        }, ^{++finishes;});
    } @catch(NSException *exception) { caught=[exception.name isEqualToString:@"NestedFailure"]; }
    assert(caught && depth==0 && restores==1 && calls==2 && finishes==1);
}
int main(void) {
    @autoreleasepool {
        normalAndNested();
        exceptionRecovery();
        nestedExceptionRecovery();
        puts("PASS: actual XiaoMang mutation helper; baseline visible to original, one original per setter, outer-only restore/reconcile, nested and all-stage exception guard recovery");
    }
    return 0;
}
