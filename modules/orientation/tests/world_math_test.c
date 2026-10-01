#include "../WorldMath.h"
#include <assert.h>
#include <stdio.h>

static void near(double a, double b) { assert(fabs(a-b) < 1e-8); }
static void halfTurn(double width, double height, MWTransform before, MWPoint center) {
    MWPoint pivot = {width/2,height/2};
    MWTransform after = MWTurn(before, center, pivot);
    const MWPoint points[] = {{0,0},{1,0},{0,1},{37.5,-24.2}};
    for (unsigned i=0; i<sizeof(points)/sizeof(points[0]); ++i) {
        MWPoint old = MWApply(before, points[i]), now = MWApply(after, points[i]);
        near(now.x + center.x, width - (old.x + center.x));
        near(now.y + center.y, height - (old.y + center.y));
    }
    assert(MWNear(MWTurn(after,center,pivot),before));
}
int main(void) {
    // iPhone 13 mini physical-point screen, normal and displaced/scaled roots.
    halfTurn(375,812,(MWTransform){1,0,0,1,0,0},(MWPoint){187.5,406});
    halfTurn(375,812,(MWTransform){.8,.2,-.1,1.1,13,27},(MWPoint){150,385});
    halfTurn(390,844,(MWTransform){1,0,0,1,7,-4},(MWPoint){192,410});
    assert(MWInvertedBasis(-1,-1,0,0));
    assert(!MWInvertedBasis(1,1,0,0));
    assert(!MWInvertedBasis(-1,1,0,0));
    assert(!MWInvertedBasis(-1,-1,.02,0));
    assert(!MWInvertedBasis(NAN,-1,0,0));
    MWTransform content = {-.9,0,0,-.9,23,17};
    MWTransform upright = MWCancelTurn(content);
    near(upright.a,.9); near(upright.d,.9);
    near(upright.tx,23); near(upright.ty,17);
    assert(MWNear(MWCancelTurn(upright),content));
    assert(!MWFinite((MWTransform){1,0,0,1,NAN,0}));
    MWTransform turn = {-1,0,0,-1,0,0};
    assert(MWOwns(turn,turn,1,0));
    assert(!MWOwns(turn,turn,0,0));   // pre-existing native half-turn
    assert(!MWOwns(turn,turn,1,1));   // suspended instance
    assert(!MWOwns((MWTransform){-1,0,0,-1,2,0},turn,1,0)); // foreign write
    assert(!MWOwns((MWTransform){1,0,0,1,0,0},turn,1,0));
    assert(!MWOwns((MWTransform){-1,0,0,-1,NAN,0},turn,1,0));
    puts("PASS: window half-turn around screen center, non-centered/scaled geometry, content normalization, double-turn and invalid basis guards");
    return 0;
}
