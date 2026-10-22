// Host test for IslandMath.h and IslandPolicy.h. The property that matters to
// the user is the first group: an adjustment written in window-local space
// gives the same visual result whether or not the window has been turned by
// 180 degrees (the phone held upside down), so changing size or position can
// never undo the inversion, and the inversion never moves the adjustment.
#include "../IslandMath.h"
#include "../IslandPolicy.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

static int near(double a, double b) { return fabs(a - b) < 1e-9; }
static double rnd(double lo, double hi) { return lo + (hi - lo) * (rand() / (double)RAND_MAX); }

// A window as the device log describes it: a uniform scale (25/24), a small
// origin, and, while the phone is upside down, a half-turn about the screen
// centre applied on top by World/Suite.
typedef struct { double unit, ox, oy; IMPoint centre; int turned; } Win;

static IMPoint WinToFixed(Win w, IMPoint u) {
    IMPoint p = {w.unit * u.x + w.ox, w.unit * u.y + w.oy};
    if (w.turned) { p.x = 2 * w.centre.x - p.x; p.y = 2 * w.centre.y - p.y; }
    return p;
}
// What the user sees: the fixed point seen through the half-turn, if any.
static IMPoint FixedToVisual(Win w, IMPoint p) {
    if (w.turned) { p.x = 2 * w.centre.x - p.x; p.y = 2 * w.centre.y - p.y; }
    return p;
}
static IMPoint Visual(Win w, IMPoint local) { return FixedToVisual(w, WinToFixed(w, local)); }

static void composition_is_orientation_independent(void) {
    srand(7);
    for (int i = 0; i < 20000; i++) {
        IMAdjust adj = IMSanitize((IMAdjust){rnd(0.5, 1.6), rnd(-90, 90), rnd(-90, 90), rnd(0, 60)});
        double unit = rnd(0.9, 1.1);
        Win up = {unit, rnd(-1, 1), rnd(-1, 1), {187.5, 406}, 0};
        Win down = up; down.turned = 1;
        // The window's own transform has the same magnitude turned or not.
        IMAffine wUp = {unit, 0, 0, unit, 0, 0}, wDown = {-unit, 0, 0, -unit, 12, 34};
        assert(near(IMWindowUnit(wUp), IMWindowUnit(wDown)));
        double u = IMWindowUnit(wUp);

        IMPoint pivot = {rnd(100, 260), rnd(0, 90)};       // anchor in local space
        IMPoint nodeAnchor = {rnd(100, 260), rnd(300, 500)}; // node centre in local space
        IMAffine t = IMNodeTransform(adj, u, pivot, nodeAnchor);
        for (int k = 0; k < 8; k++) {
            IMPoint p = {rnd(0, 360), rnd(0, 780)};          // a stock-layout point
            IMPoint moved = IMViewMap(t, nodeAnchor, p);
            // The mapping the user asked for, in local space.
            IMPoint want = IMAdjustMap(adj, u, pivot, p);
            assert(near(moved.x, want.x) && near(moved.y, want.y));
            // ...and in what the user sees, upright and upside down alike:
            // scale about the visual pivot, then offsets in screen points.
            for (int turned = 0; turned < 2; turned++) {
                Win w = turned ? down : up;
                IMPoint sv = Visual(w, p), pv = Visual(w, pivot), av = Visual(w, moved);
                assert(fabs(av.x - (pv.x + adj.scale * (sv.x - pv.x) + adj.offsetX)) < 1e-7);
                assert(fabs(av.y - (pv.y + adj.scale * (sv.y - pv.y) + adj.offsetY)) < 1e-7);
            }
        }
    }
}

// Sizes and positions change while the phone is turned and turned back. The
// node transform depends only on the adjustment, never on the turn, and the
// final picture is always the adjusted stock picture; back at the defaults the
// package owns nothing and the picture is exactly stock.
static void adjusting_while_turning_never_loses_either(void) {
    Win w = {25.0 / 24.0, 0, 0.097, {187.5, 406}, 0};
    IMPoint pivot = {180, 28.3}, nodeAnchor = {180, 389.67}, p = {171, 33.3};
    IMAffine owned = IMIdentity();
    const int turned[] = {0, 1, 1, 0, 0, 1};
    const double scales[] = {1.0, 1.12, 0.85, 0.85, 1.0, 1.2};
    const double ys[] = {0, 6, -4, -4, 0, 10};
    for (int i = 0; i < 6; i++) {
        w.turned = turned[i];
        IMAdjust adj = IMSanitize((IMAdjust){scales[i], 0, ys[i], IM_ANCHOR_Y_DEFAULT});
        double sign = w.turned ? -1 : 1;
        double unit = IMWindowUnit((IMAffine){sign * w.unit, 0, 0, sign * w.unit, 0, 0});
        IMAffine desired = IMNodeTransform(adj, unit, pivot, nodeAnchor);
        bool isOwned = !IMAffineNear(owned, IMIdentity());
        IMOwnAction action = IMOwnDecide(!IMIsIdentity(adj), isOwned, owned, owned, desired);
        if (action == IMOwnWrite) owned = desired;
        if (action == IMOwnRelease) owned = IMIdentity();
        IMPoint stock = Visual(w, p), got = Visual(w, IMViewMap(owned, nodeAnchor, p));
        if (IMIsIdentity(adj)) {
            assert(IMAffineNear(owned, IMIdentity()));
            assert(near(got.x, stock.x) && near(got.y, stock.y));
        } else {
            IMPoint pv = Visual(w, pivot);
            assert(fabs(got.x - (pv.x + adj.scale * (stock.x - pv.x))) < 1e-7);
            assert(fabs(got.y - (pv.y + adj.scale * (stock.y - pv.y) + adj.offsetY)) < 1e-7);
        }
    }
}

static void window_unit_is_sane(void) {
    assert(near(IMWindowUnit((IMAffine){25.0 / 24, 0, 0, 25.0 / 24, 0, 0}), 25.0 / 24));
    assert(near(IMWindowUnit((IMAffine){-25.0 / 24, 0, 0, -25.0 / 24, 3, 4}), 25.0 / 24));
    assert(near(IMWindowUnit((IMAffine){0, 1, -1, 0, 0, 0}), 1.0));  // a quarter turn keeps its scale
    assert(IMWindowUnit((IMAffine){0, 0, 0, 0, 0, 0}) == 1.0);       // degenerate
    assert(IMWindowUnit((IMAffine){NAN, 0, 0, 1, 0, 0}) == 1.0);
    assert(IMWindowUnit((IMAffine){9, 0, 0, 9, 0, 0}) == 1.0);       // implausible
}

static void sanitize_and_identity(void) {
    IMAdjust bad = IMSanitize((IMAdjust){NAN, INFINITY, -INFINITY, NAN});
    assert(bad.scale == 1.0 && bad.offsetX == 0 && bad.offsetY == 0 && bad.anchorY == IM_ANCHOR_Y_DEFAULT);
    IMAdjust big = IMSanitize((IMAdjust){9, 500, -500, 900});
    assert(big.scale == IM_SCALE_MAX && big.offsetX == IM_OFFSET_MAX && big.offsetY == -IM_OFFSET_MAX && big.anchorY == 200);
    IMAdjust small = IMSanitize((IMAdjust){0.01, 0, 0, -3});
    assert(small.scale == IM_SCALE_MIN && small.anchorY == 0);
    assert(IMIsIdentity((IMAdjust){1, 0, 0, 29.5}));
    assert(IMIsIdentity((IMAdjust){1.0002, 0.001, -0.001, 29.5}));
    assert(!IMIsIdentity((IMAdjust){1.01, 0, 0, 29.5}));
    assert(!IMIsIdentity((IMAdjust){1, 0.5, 0, 29.5}));
    assert(!IMIsIdentity((IMAdjust){1, 0, -0.5, 29.5}));
    // The identity adjustment produces the identity transform (nothing to write).
    IMAffine t = IMNodeTransform((IMAdjust){1, 0, 0, 29.5}, 25.0 / 24, (IMPoint){180, 28}, (IMPoint){180, 389});
    assert(IMAffineNear(t, IMIdentity()));
}

static void ownership_never_fights(void) {
    IMAffine id = IMIdentity();
    IMAffine ours = {1.1, 0, 0, 1.1, 2, -3}, other = {0.5, 0, 0, 0.5, 0, 0}, want = {1.2, 0, 0, 1.2, 1, 1};
    // Not owned yet: write over identity, never over a foreign value.
    assert(IMOwnDecide(true, false, id, id, want) == IMOwnWrite);
    assert(IMOwnDecide(true, false, other, id, want) == IMOwnConflict);
    assert(IMOwnDecide(false, false, other, id, want) == IMOwnKeep);
    assert(IMOwnDecide(false, false, id, id, want) == IMOwnKeep);
    // Owned: keep, rewrite or release only while the value is still ours.
    assert(IMOwnDecide(true, true, ours, ours, ours) == IMOwnKeep);
    assert(IMOwnDecide(true, true, ours, ours, want) == IMOwnWrite);
    assert(IMOwnDecide(false, true, ours, ours, want) == IMOwnRelease);
    // Someone replaced it: identity is a harmless reset, anything else is theirs.
    assert(IMOwnDecide(true, true, id, ours, want) == IMOwnWrite);
    assert(IMOwnDecide(false, true, id, ours, want) == IMOwnRelease);
    assert(IMOwnDecide(true, true, other, ours, want) == IMOwnConflict);
    assert(IMOwnDecide(false, true, other, ours, want) == IMOwnConflict);
}

static void probes_and_classification(void) {
    assert(IMBasisIsTranslation((IMPoint){5, 7}, (IMPoint){6, 7}, (IMPoint){5, 8}));
    assert(!IMBasisIsTranslation((IMPoint){0, 0}, (IMPoint){1.04, 0}, (IMPoint){0, 1.04}));
    assert(!IMBasisIsTranslation((IMPoint){0, 0}, (IMPoint){-1, 0}, (IMPoint){0, -1}));
    assert(!IMBasisIsTranslation((IMPoint){NAN, 0}, (IMPoint){1, 0}, (IMPoint){0, 1}));
    assert(IMClassifyWindowBasis((IMPoint){0, 0}, (IMPoint){1.04, 0}, (IMPoint){0, 1.04}) == IMWindowUpright);
    assert(IMClassifyWindowBasis((IMPoint){0, 0}, (IMPoint){-1.04, 0}, (IMPoint){0, -1.04}) == IMWindowTurned);
    assert(IMClassifyWindowBasis((IMPoint){0, 0}, (IMPoint){0, 1}, (IMPoint){-1, 0}) == IMWindowOther);
    assert(IMClassifyWindowBasis((IMPoint){0, 0}, (IMPoint){-1, 0}, (IMPoint){0, 1}) == IMWindowOther);
    assert(IMClassifyWindowBasis((IMPoint){0, 0}, (IMPoint){NAN, 0}, (IMPoint){0, 1}) == IMWindowOther);
}

static void disguise_policy(void) {
    assert(IMSubtypeForMode(0) == 2556 && IMSubtypeForMode(1) == 2796);
    assert(IMSubtypeForMode(-5) == 2556 && IMSubtypeForMode(7) == 2556);
    assert(IMIsIslandSubtype(2556) && IMIsIslandSubtype(2796) && !IMIsIslandSubtype(2436) && !IMIsIslandSubtype(0));
    // 13 mini: nativeBounds 1125x2436.
    assert(!IMHardwareHasIsland(2436) && IMHardwareHasIsland(2556) && IMHardwareHasIsland(2796) && !IMHardwareHasIsland(NAN));
    // Back-up decisions never overwrite an original and never store a disguise.
    assert(IMBackupDecide(true, 2556) == IMBackupKeep && IMBackupDecide(true, 2436) == IMBackupKeep);
    assert(IMBackupDecide(false, 2436) == IMBackupStore);
    assert(IMBackupDecide(false, 2556) == IMBackupUnknown && IMBackupDecide(false, 2796) == IMBackupUnknown);
    assert(IMBackupDecide(false, 0) == IMBackupUnreadable && IMBackupDecide(false, -1) == IMBackupUnreadable);
    // Restore: the stored original wins; otherwise Mango's nativeBounds rule.
    assert(IMRestoreValue(true, 2436, 2436) == 2436);
    assert(IMRestoreValue(true, 2340, 2436) == 2340);
    assert(IMRestoreValue(true, 2556, 2436) == 2436);   // a stored disguise is not an original
    assert(IMRestoreValue(false, 0, 2436) == 2436);
    assert(IMRestoreValue(false, 0, NAN) == 0);
    // Apply refuses unreadable input and phones that already have an island.
    assert(IMApplyDecide(2436, 2556, 2436) == IMApplyOK);
    assert(IMApplyDecide(2556, 2556, 2436) == IMApplyAlreadyIsland);
    assert(IMApplyDecide(2556, 2796, 2436) == IMApplyOK);   // switching style
    assert(IMApplyDecide(2556, 2796, 2556) == IMApplyHardwareIsland);
    assert(IMApplyDecide(0, 2556, 2436) == IMApplyUnreadable && IMApplyDecide(2436, 0, 2436) == IMApplyUnreadable);
}

static void crash_guard(void) {
    // Applied from a long-lived SpringBoard (started at 100), then the first new
    // SpringBoard crashes within seconds: the next launch must undo the disguise.
    IMGuardState g = {0};
    assert(!IMGuardLaunch(&g, 100));
    for (double t = 105; t <= 1000; t += 5) IMGuardAlive(&g, t);
    IMGuardArm(&g, 1000);
    assert(!IMGuardLaunch(&g, 1005));      // the run that armed us is not evidence
    IMGuardAlive(&g, 1010);                // lived ~5s, then crashed
    assert(IMGuardLaunch(&g, 1012));       // trips on the first short run
    IMGuardDisarm(&g);
    assert(!g.armed && g.shortRuns == 0);

    // Same, but the first new SpringBoard is healthy: it disarms after a minute
    // and later quick resprings never trip it.
    IMGuardState h = {0};
    assert(!IMGuardLaunch(&h, 100));
    IMGuardArm(&h, 400);
    assert(!IMGuardLaunch(&h, 405));
    for (double t = 410; t <= 480; t += 5) IMGuardAlive(&h, t);
    assert(!h.armed);
    assert(!IMGuardLaunch(&h, 483));
    IMGuardAlive(&h, 486);
    assert(!IMGuardLaunch(&h, 489));       // two quick resprings, not armed: nothing happens

    // The run that armed the guard may itself be short-lived (apply right after a
    // respring); that alone must not trip it.
    IMGuardState k = {0};
    assert(!IMGuardLaunch(&k, 50));
    IMGuardAlive(&k, 52);
    IMGuardArm(&k, 53);
    assert(!IMGuardLaunch(&k, 56));
    for (double t = 60; t <= 130; t += 5) IMGuardAlive(&k, t);
    assert(!k.armed);

    // A run that survives past the minimum life before dying does not count.
    IMGuardState m = {0};
    assert(!IMGuardLaunch(&m, 0));
    IMGuardArm(&m, 10);
    assert(!IMGuardLaunch(&m, 12));
    IMGuardAlive(&m, 40);                  // 28s alive (< stable, > minimum)
    assert(!IMGuardLaunch(&m, 44));
    assert(m.armed && m.shortRuns == 0);
}

int main(void) {
    composition_is_orientation_independent();
    adjusting_while_turning_never_loses_either();
    window_unit_is_sane();
    sanitize_and_identity();
    ownership_never_fights();
    probes_and_classification();
    disguise_policy();
    crash_guard();
    puts("island_test: ok");
    return 0;
}
