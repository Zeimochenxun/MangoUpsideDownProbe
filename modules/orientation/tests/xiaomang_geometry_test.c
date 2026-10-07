#include "../XiaoMangGeometry.h"
#include <assert.h>
#include <stdio.h>

static void near(double a, double b) { assert(isfinite(a) && isfinite(b) && fabs(a-b) < 1e-8); }
static void samePoint(MWPoint a, MWPoint b) { near(a.x,b.x); near(a.y,b.y); }
static void sameTransform(MWTransform a, MWTransform b) {
    near(a.a,b.a); near(a.b,b.b); near(a.c,b.c);
    near(a.d,b.d); near(a.tx,b.tx); near(a.ty,b.ty);
}
static MWPoint add(MWPoint a, MWPoint b) { return (MWPoint){a.x+b.x,a.y+b.y}; }
static MWPoint subtract(MWPoint a, MWPoint b) { return (MWPoint){a.x-b.x,a.y-b.y}; }

// Independent UIKit geometry model: window coordinates are centered around
// its layer anchor, transformed into parent space and then into fixed space.
// This forward map never uses the inverse computed by the production planner.
typedef struct {
    MWTransform parent, baseline;
    MWPoint center, anchor;
} Fixture;
static MWPoint fixedPoint(Fixture f, MWTransform transform, MWPoint local) {
    MWPoint centered = subtract(local,f.anchor);
    return MWApply(f.parent,add(f.center,MWApply(transform,centered)));
}
static MWTransform mapping(Fixture f) {
    MWPoint o=fixedPoint(f,f.baseline,(MWPoint){0,0});
    MWPoint x=fixedPoint(f,f.baseline,(MWPoint){1,0});
    MWPoint y=fixedPoint(f,f.baseline,(MWPoint){0,1});
    return (MWTransform){x.x-o.x,x.y-o.y,y.x-o.x,y.y-o.y,o.x,o.y};
}
static MWTransform planned(Fixture f, MWPoint pivot) {
    MWTransform result={0};
    MWPoint anchor=fixedPoint(f,f.baseline,f.anchor);
    assert(XMPlanHalfTurn(f.baseline,mapping(f),anchor,pivot,&result)==XMPlanApply);
    return result;
}
static void reflectFixture(Fixture f, MWPoint pivot) {
    MWTransform after=planned(f,pivot);
    // Origin, independent basis axes, corners, off-center point and anchor.
    const MWPoint samples[]={{0,0},{1,0},{0,1},{260,260},{160,94},{37.5,-24.2},f.anchor};
    for(unsigned i=0;i<sizeof(samples)/sizeof(samples[0]);++i) {
        MWPoint before=fixedPoint(f,f.baseline,samples[i]);
        samePoint(fixedPoint(f,after,samples[i]),(MWPoint){2*pivot.x-before.x,2*pivot.y-before.y});
    }
    // A direct touch in the rotated window keeps its original local target.
    // A local drag's two-axis delta is mapped naturally by the turned basis.
    MWPoint start={18,33}, end={36,11};
    MWPoint beforeDelta=subtract(fixedPoint(f,f.baseline,end),fixedPoint(f,f.baseline,start));
    MWPoint afterDelta=subtract(fixedPoint(f,after,end),fixedPoint(f,after,start));
    samePoint(afterDelta,(MWPoint){-beforeDelta.x,-beforeDelta.y});
    // Extra gesture negation would invert that correct displacement again.
    MWPoint negatedEnd=add(start,subtract(start,end));
    MWPoint wrongDelta=subtract(fixedPoint(f,after,negatedEnd),fixedPoint(f,after,start));
    assert(fabs(wrongDelta.x-afterDelta.x)>1 || fabs(wrongDelta.y-afterDelta.y)>1);
}
static void layoutDoesNotAccumulate(void) {
    MWPoint pivot={187.5,406};
    Fixture f={{1,0,0,1,0,0},{1,0,0,1,0,0},{320,76},{130,130}};
    MWTransform initial=planned(f,pivot);
    // A layout transaction restores the exact owned baseline, changes center,
    // and plans again. The new point must reflect the new logical position.
    assert(MWOwns(initial,initial,1,0));
    f.center=(MWPoint){143,233};
    MWTransform next=planned(f,pivot);
    reflectFixture(f,pivot);
    assert(fabs(initial.tx-next.tx)>1 && fabs(initial.ty-next.ty)>1);
    // If the current transform is the original native value or an external
    // write, matching geometry alone cannot authorize baseline restoration.
    assert(!MWOwns(initial,initial,0,0));
    MWTransform external=initial; external.tx+=12;
    assert(!MWOwns(external,initial,1,0));
}
static void alreadyInvertedAndInvalid(void) {
    MWTransform upright={1,0,0,1,0,0}, sentinel={7,8,9,10,11,12};
    MWTransform result=sentinel;
    // Native scene can already invert the window with an identity transform.
    assert(XMPlanHalfTurn(upright,(MWTransform){-1,0,0,-1,375,812},
        (MWPoint){210,665},(MWPoint){187.5,406},&result)==XMPlanNativeInverted);
    sameTransform(result,sentinel);
    const MWTransform rejected[]={
        {0,0,0,1,0,0}, {1,0,0,-1,0,0},
        {1,.1,0,1,0,0}, {NAN,0,0,1,0,0}
    };
    for(unsigned i=0;i<sizeof(rejected)/sizeof(rejected[0]);++i) {
        result=sentinel;
        assert(XMPlanHalfTurn(upright,rejected[i],(MWPoint){1,2},
            (MWPoint){187.5,406},&result)==XMPlanInvalid);
        sameTransform(result,sentinel);
    }
    result=sentinel;
    assert(XMPlanHalfTurn((MWTransform){0,0,0,1,0,0},upright,
        (MWPoint){1,2},(MWPoint){187.5,406},&result)==XMPlanInvalid);
    assert(XMPlanHalfTurn(upright,upright,(MWPoint){NAN,2},
        (MWPoint){187.5,406},&result)==XMPlanInvalid);
    assert(XMPlanHalfTurn(upright,upright,(MWPoint){1,2},
        (MWPoint){187.5,INFINITY},&result)==XMPlanInvalid);
}
int main(void) {
    // iPhone 13 mini: 260x260 main panel, then a small notification window.
    reflectFixture((Fixture){{1,0,0,1,0,0},{1,0,0,1,0,0},
        {319,93},{130,130}},(MWPoint){187.5,406});
    reflectFixture((Fixture){{1,0,0,1,0,0},{1,0,0,1,0,0},
        {47,175},{160,36}},(MWPoint){187.5,406});
    // Parent scene has a different positive scale and translated origin.
    reflectFixture((Fixture){{.8,0,0,1.25,31,-17},{.9,0,0,1.1,13,-4},
        {82,195},{160,47}},(MWPoint){187.5,406});
    // A rotated parent compensated by the baseline still has an upright
    // actual fixed basis. The planner must respect both spaces independently.
    reflectFixture((Fixture){{0,1,-1,0,375,0},{0,-1,1,0,5,9},
        {76,223},{160,47}},(MWPoint){187.5,406});
    layoutDoesNotAccumulate();
    alreadyInvertedAndInvalid();
    puts("PASS: actual XiaoMang geometry planner; off-center main/notification windows, scaled scene space, physical reflection, no accumulated layout offsets, native-inverted and invalid guards, natural local drag mapping");
    return 0;
}
