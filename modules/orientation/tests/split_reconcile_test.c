#include "../SplitReconcile.h"
#include <assert.h>
#include <stdio.h>

static const MWTransform Identity = {1,0,0,1,0,0};
static const MWTransform NativeTurn = {-1,0,0,-1,375,812};

typedef struct {
    MWTransform model, native, launcherChild;
    int target, safe, badBasis, wrongAfterWrite, foreignAfterWrite;
    unsigned reads, writes;
} Fixture;

// Independent forward model of UIKit's centered window coordinates followed
// by the scene-to-fixed-screen transform; this does not call MWTurn/MWApply.
static MWPoint affine(MWTransform t, MWPoint p) {
    return (MWPoint){p.x*t.a+p.y*t.c+t.tx,p.x*t.b+p.y*t.d+t.ty};
}
static MWPoint screenPoint(Fixture *fixture, MWPoint local) {
    MWPoint relative = {local.x-187.5,local.y-406};
    MWPoint parent = affine(fixture->model, relative);
    parent.x += 187.5; parent.y += 406;
    return affine(fixture->native, parent);
}
static MSSplitSnapshot readSnapshot(void *context) {
    Fixture *fixture = context;
    ++fixture->reads;
    MSSplitSnapshot sample = {.transform=fixture->model,.center={187.5,406},
        .pivot={187.5,406},.eligible=fixture->target&&fixture->safe};
    const MWPoint local[] = {{0,0},{1,0},{0,1}};
    for (unsigned i=0; i<3; ++i) sample.points[i]=screenPoint(fixture,local[i]);
    if (fixture->badBasis) sample.points[1].y += .02;
    if (fixture->wrongAfterWrite && fixture->writes)
        for (unsigned i=0; i<3; ++i) sample.points[i].x += 3;
    return sample;
}
static void writeTransform(void *context, MWTransform value) {
    Fixture *fixture = context;
    ++fixture->writes;
    fixture->model = value;
    if (fixture->foreignAfterWrite) fixture->model.tx += 17;
}
static Fixture upright(void) {
    return (Fixture){.model={1,0,0,1,0,0},.native={1,0,0,1,0,0},
        .launcherChild={1,0,0,1,0,0},.target=1,.safe=1};
}
static unsigned reconcile(Fixture *fixture, MSSplitOwnership *state, int active) {
    return MSSplitReconcile(state,active,readSnapshot,writeTransform,fixture);
}
static void nearPoint(MWPoint a, MWPoint b) {
    assert(fabs(a.x-b.x)<1e-8 && fabs(a.y-b.y)<1e-8);
}
static void mirroredScreen(Fixture *fixture) {
    const MWPoint points[]={{0,0},{1,0},{0,1},{375,812},{83.5,217.25}};
    for (unsigned i=0; i<sizeof(points)/sizeof(points[0]); ++i)
        nearPoint(screenPoint(fixture,points[i]),(MWPoint){375-points[i].x,812-points[i].y});
}
static void launcherInverted(Fixture *fixture) {
    // Beta8's portrait launcher animation resets its local child transform to
    // identity. Verify its physical basis through the corrected outer window.
    MWPoint p0=screenPoint(fixture,affine(fixture->launcherChild,(MWPoint){28,60}));
    MWPoint px=screenPoint(fixture,affine(fixture->launcherChild,(MWPoint){29,60}));
    MWPoint py=screenPoint(fixture,affine(fixture->launcherChild,(MWPoint){28,61}));
    nearPoint((MWPoint){px.x-p0.x,px.y-p0.y},(MWPoint){-1,0});
    nearPoint((MWPoint){py.x-p0.x,py.y-p0.y},(MWPoint){0,-1});
}

int main(void) {
    MSSplitOwnership state={0};
    Fixture fixture=upright();
    fixture.native=NativeTurn;
    assert(reconcile(&fixture,&state,1)==0);
    assert(fixture.writes==0 && !state.applied);
    assert(MWNear(fixture.model,Identity));
    mirroredScreen(&fixture); launcherInverted(&fixture);

    fixture=upright(); fixture.model=(MWTransform){-1,0,0,-1,0,0};
    assert(reconcile(&fixture,&state,1)==0);
    assert(fixture.writes==0 && !state.applied); // unowned native window turn

    fixture=upright();
    assert(reconcile(&fixture,&state,1)==MSSplitApplied);
    assert(state.applied && fixture.writes==1);
    mirroredScreen(&fixture); launcherInverted(&fixture);
    for (unsigned i=0; i<10000; ++i) assert(reconcile(&fixture,&state,1)==0);
    assert(fixture.writes==1); // repeated callbacks never accumulate rotation
    mirroredScreen(&fixture);

    // The scene later adds its native half-turn while our model matrix stays
    // unchanged: the old Split applied+Near branch returned with double pi.
    fixture.native=NativeTurn;
    fixture.launcherChild=Identity;
    assert(!MSSplitInverted(readSnapshot(&fixture)));
    assert(reconcile(&fixture,&state,1)==MSSplitRestored);
    assert(fixture.writes==2 && !state.applied);
    assert(MWNear(fixture.model,Identity) && MWNear(fixture.native,NativeTurn));
    mirroredScreen(&fixture); launcherInverted(&fixture);

    fixture.native=Identity;
    assert(reconcile(&fixture,&state,1)==MSSplitApplied);
    assert(state.applied && fixture.writes==3);
    fixture.model=Identity; // an external native layout reset
    assert(reconcile(&fixture,&state,1)==(MSSplitReleased|MSSplitApplied));
    assert(state.applied && fixture.writes==4); // repairs during this same call
    mirroredScreen(&fixture); launcherInverted(&fixture);

    assert(reconcile(&fixture,&state,0)==MSSplitRestored);
    assert(!state.applied && fixture.writes==5 && MWNear(fixture.model,Identity));
    assert(reconcile(&fixture,&state,0)==0);
    assert(reconcile(&fixture,&state,1)==MSSplitApplied);
    fixture.target=0;
    assert(reconcile(&fixture,&state,1)==MSSplitRestored);
    assert(!state.applied && MWNear(fixture.model,Identity));

    fixture=upright(); state=(MSSplitOwnership){0};
    assert(reconcile(&fixture,&state,1)==MSSplitApplied);
    fixture.model=(MWTransform){.8,0,0,.8,7,9}; fixture.safe=0;
    MWTransform foreign=fixture.model;
    assert(reconcile(&fixture,&state,1)==MSSplitReleased);
    assert(fixture.writes==1 && !state.applied && MWNear(fixture.model,foreign));
    assert(reconcile(&fixture,&state,0)==0 && MWNear(fixture.model,foreign));

    fixture=upright(); state=(MSSplitOwnership){0}; fixture.badBasis=1;
    assert(reconcile(&fixture,&state,1)==0 && fixture.writes==0);
    fixture.badBasis=0; fixture.native.a=NAN;
    assert(reconcile(&fixture,&state,1)==0 && fixture.writes==0);

    fixture=upright(); state=(MSSplitOwnership){0}; fixture.wrongAfterWrite=1;
    assert(reconcile(&fixture,&state,1)==(MSSplitRestored|MSSplitRejected));
    assert(fixture.writes==2 && !state.applied && state.suspended && MWNear(fixture.model,Identity));
    assert(reconcile(&fixture,&state,1)==0 && fixture.writes==2);
    fixture.wrongAfterWrite=0; // a later stable native scene/layout update
    assert(reconcile(&fixture,&state,1)==MSSplitApplied);
    assert(fixture.writes==3 && state.applied && !state.suspended);
    mirroredScreen(&fixture);

    // A different writer wins during our attempted turn. Failed verification
    // releases ownership without restoring its new transform to our baseline.
    fixture=upright(); state=(MSSplitOwnership){0}; fixture.foreignAfterWrite=1;
    assert(reconcile(&fixture,&state,1)==(MSSplitReleased|MSSplitRejected));
    assert(fixture.writes==1 && !state.applied && state.suspended);
    assert(fixture.model.tx==17);

    fixture=upright(); state=(MSSplitOwnership){0};
    assert(reconcile(&fixture,&state,1)==MSSplitApplied);
    fixture.safe=0;
    assert(reconcile(&fixture,&state,1)==MSSplitRestored);
    assert(!state.applied && MWNear(fixture.model,Identity));

    puts("PASS: actual fixed-screen rechecks, native scene double-turn removal, same-call reset repair, portrait launcher child basis, foreign-transform ownership, unsafe/invalid guards and 10000 stable updates");
    return 0;
}
