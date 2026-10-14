// Reproduce the supplied device log's window conversion behavior. This is a
// model-coordinate regression, not a claim about phone pixels or UIKit timing.
#include "../SplitReconcile.h"
#include <assert.h>
#include <stdio.h>

typedef struct {
    MWTransform window, root, scene;
    int useRoot, eligible, brokenLayerRead;
    unsigned writes;
} Launcher;

static const MWTransform identity={1,0,0,1,0,0};
static const MWTransform nativeTurn={-1,0,0,-1,375,812};
static MWPoint point(Launcher *f,MWPoint p) {
    // In the trace, UIWindow's fixed-coordinate conversion stays identity
    // despite the window's model becoming [-1,0,0,-1,0,0]. A child layer's
    // relative conversion still contains its own local centered transform.
    if (f->useRoot && !f->brokenLayerRead) {
        p.x-=187.5; p.y-=406;
        MWTransform t=f->root;
        p=(MWPoint){t.a*p.x+t.c*p.y+t.tx+187.5,t.b*p.x+t.d*p.y+t.ty+406};
    }
    MWTransform s=f->scene;
    return (MWPoint){s.a*p.x+s.c*p.y+s.tx,s.b*p.x+s.d*p.y+s.ty};
}
static MSSplitSnapshot readLauncher(void *context) {
    Launcher *f=context;
    MSSplitSnapshot s={.transform=f->useRoot ? f->root : f->window,
        .eligible=f->eligible,.center={187.5,406},.pivot={187.5,406}};
    s.points[0]=point(f,(MWPoint){0,0});
    s.points[1]=point(f,(MWPoint){1,0});
    s.points[2]=point(f,(MWPoint){0,1});
    return s;
}
static void writeLauncher(void *context,MWTransform t) {
    Launcher *f=context; ++f->writes;
    if (f->useRoot) f->root=t; else f->window=t;
}
static unsigned recover(Launcher *f,MSSplitOwnership *s,int active) {
    return MSSplitReconcileRecovery(s,active,1,readLauncher,writeLauncher,f);
}
static Launcher normal(void) {
    return (Launcher){.window={1,0,0,1,0,0},.root={1,0,0,1,0,0},
        .scene={1,0,0,1,0,0},.eligible=1};
}
static void inverted(Launcher *f) {
    assert(MSSplitInverted(readLauncher(f)));
    const MWPoint points[]={{0,0},{375,812},{83,217},{28,60}};
    for (unsigned i=0;i<4;++i) {
        MWPoint actual=point(f,points[i]);
        assert(fabs(actual.x-(375-points[i].x))<1e-8);
        assert(fabs(actual.y-(812-points[i].y))<1e-8);
    }
}
int main(void) {
    Launcher f=normal(); MSSplitOwnership s={0};
    // Negative control: the previous target reproduces result=9, suspended=1.
    assert(recover(&f,&s,1)==(MSSplitRestored|MSSplitRejected));
    assert(s.suspended && !s.applied && f.writes==2 && MWNear(f.window,identity));
    for (unsigned i=0;i<100;++i) assert(recover(&f,&s,1)==0);
    assert(f.writes==2); // A repeat callback cannot rescue this old target.

    // The new target gets distinct ownership, independent of that suspension.
    f.useRoot=1; MSSplitOwnership root={0};
    assert(recover(&f,&root,1)==MSSplitApplied);
    assert(root.applied && !root.suspended && MWNear(f.window,identity)); inverted(&f);
    for (unsigned i=0;i<10000;++i) assert(recover(&f,&root,1)==0);
    assert(f.writes==3); inverted(&f);

    // Minimize then Dock/library reopen resets the child transform. Repair in
    // the same callback, keeping the window untouched and no accumulated turn.
    f.root=identity;
    assert(recover(&f,&root,1)==(MSSplitReleased|MSSplitApplied)); inverted(&f);
    f.scene=nativeTurn;
    assert(recover(&f,&root,1)==MSSplitRestored); inverted(&f);
    f.scene=identity;
    assert(recover(&f,&root,1)==MSSplitApplied); inverted(&f);
    assert(recover(&f,&root,0)==MSSplitRestored);
    assert(MWNear(f.root,identity) && MWNear(f.window,identity));

    f=normal(); f.useRoot=1; root=(MSSplitOwnership){0}; f.scene=nativeTurn;
    assert(recover(&f,&root,1)==0 && f.writes==0); inverted(&f);
    f.scene=identity; f.root=(MWTransform){.8,0,0,.8,7,9};
    assert(recover(&f,&root,1)==0 && f.writes==0); // Foreign/native scaling.
    f=normal(); f.useRoot=1; root=(MSSplitOwnership){0}; f.eligible=0;
    assert(recover(&f,&root,1)==0 && f.writes==0);
    f.eligible=1;
    assert(recover(&f,&root,1)==MSSplitApplied);
    f.root.tx=17;
    assert(recover(&f,&root,0)==MSSplitReleased && f.root.tx==17);
    f=normal(); f.useRoot=1; root=(MSSplitOwnership){0};
    f.brokenLayerRead=1;
    assert(recover(&f,&root,1)==(MSSplitRestored|MSSplitRejected));
    assert(root.suspended && MWNear(f.root,identity)); // Still enforce verification.
    puts("PASS: device window-conversion negative control suspends; separate launcher root recovers, Dock/library resets, native remap, 10000 stable updates, disable/foreign/unsafe ownership and failed child verification");
}
