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
#include <string.h>

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
    // The original value of a phone is its panel's pixel height (Mango's
    // defaultDeviceSubType = nativeBounds.height): 13 mini 1080x2340, X 1125x2436.
    assert(IMNativeSubtype(2340) == 2340 && IMNativeSubtype(2339.6) == 2340 && IMNativeSubtype(2436) == 2436);
    assert(IMNativeSubtype(NAN) == 0 && IMNativeSubtype(INFINITY) == 0 && IMNativeSubtype(-5) == 0 && IMNativeSubtype(0) == 0);
    assert(!IMHardwareHasIsland(2340) && !IMHardwareHasIsland(2436) && IMHardwareHasIsland(2556) && IMHardwareHasIsland(2796) &&
           !IMHardwareHasIsland(NAN));
    // What original.plist holds becomes an original; a disguise never does.
    IMOriginal none = IMStoredOriginal(0, false), val = IMStoredOriginal(2340, false), absent = IMStoredOriginal(0, true);
    assert(none.kind == IMOriginalNone && val.kind == IMOriginalValue && val.value == 2340 && absent.kind == IMOriginalAbsent);
    assert(IMStoredOriginal(2556, false).kind == IMOriginalNone && IMStoredOriginal(2796, false).kind == IMOriginalNone);
    assert(IMStoredOriginal(2556, true).kind == IMOriginalAbsent);   // an island value beside "absent": absent wins
    assert(IMStoredOriginal(-3, false).kind == IMOriginalNone);
    // Back-up decisions never overwrite an original and never store a disguise.
    assert(IMBackupDecide(val, 2556) == IMBackupKeep && IMBackupDecide(val, 2436) == IMBackupKeep && IMBackupDecide(absent, 2556) == IMBackupKeep);
    assert(IMBackupDecide(absent, IM_ENTRY_ABSENT) == IMBackupKeep);
    assert(IMBackupDecide(none, 2436) == IMBackupStore && IMBackupDecide(none, 2340) == IMBackupStore);
    assert(IMBackupDecide(none, 2556) == IMBackupUnknown && IMBackupDecide(none, 2796) == IMBackupUnknown);
    // A phone whose cache has no entry (the first device run of 0.2.0): the original is "no entry".
    assert(IMBackupDecide(none, IM_ENTRY_ABSENT) == IMBackupStoreAbsent);
    // An entry that is not a number is the only thing that is refused.
    assert(IMBackupDecide(none, IM_ENTRY_UNUSABLE) == IMBackupUnreadable && IMBackupDecide(none, -7) == IMBackupUnreadable);
    // Restore: "no entry" deletes; the stored original wins; otherwise Mango's nativeBounds rule.
    IMRestorePlan plan = IMRestorePlanFor(absent, 2340);
    assert(plan.remove && plan.value == 0);
    plan = IMRestorePlanFor(absent, NAN);
    assert(plan.remove);                                // deleting needs no screen size
    plan = IMRestorePlanFor(IMStoredOriginal(2436, false), 2436);
    assert(!plan.remove && plan.value == 2436);
    plan = IMRestorePlanFor(IMStoredOriginal(2340, false), 2436);
    assert(!plan.remove && plan.value == 2340);         // the stored original beats the screen
    plan = IMRestorePlanFor((IMOriginal){IMOriginalValue, 2556}, 2436);
    assert(!plan.remove && plan.value == 2436);         // a stored disguise is not an original
    plan = IMRestorePlanFor(none, 2436);
    assert(!plan.remove && plan.value == 2436);
    plan = IMRestorePlanFor(none, 2340);
    assert(!plan.remove && plan.value == 2340);
    plan = IMRestorePlanFor(none, NAN);
    assert(!plan.remove && plan.value == 0);            // nothing computable: the caller refuses
    // Nothing stored and no entry in the cache: nothing to put back, and no entry is invented.
    plan = IMRestorePlanNow(none, IM_ENTRY_ABSENT, 2340);
    assert(plan.remove && IMPlanAlreadyHolds(plan, IM_ENTRY_ABSENT));
    plan = IMRestorePlanNow(none, IM_ENTRY_ABSENT, NAN);
    assert(plan.remove);
    // Otherwise it is the plan of the stored original / the screen rule.
    plan = IMRestorePlanNow(none, 2556, 2340);
    assert(!plan.remove && plan.value == 2340);         // simulated by something else: Mango's rule
    plan = IMRestorePlanNow(absent, 2556, 2340);
    assert(plan.remove);
    plan = IMRestorePlanNow(val, IM_ENTRY_ABSENT, 2436);
    assert(!plan.remove && plan.value == 2340);
    plan = IMRestorePlanNow(none, IM_ENTRY_UNUSABLE, 2340);
    assert(!plan.remove && plan.value == 2340);
    // "Already there": a delete holds when there is no entry; a write when the entry equals it.
    assert(IMPlanAlreadyHolds(IMRestorePlanFor(absent, 2340), IM_ENTRY_ABSENT));
    assert(!IMPlanAlreadyHolds(IMRestorePlanFor(absent, 2340), 2556) && !IMPlanAlreadyHolds(IMRestorePlanFor(absent, 2340), IM_ENTRY_UNUSABLE));
    assert(IMPlanAlreadyHolds(IMRestorePlanFor(val, 2436), 2340) && !IMPlanAlreadyHolds(IMRestorePlanFor(val, 2436), 2556));
    assert(!IMPlanAlreadyHolds(IMRestorePlanFor(none, NAN), 0) && !IMPlanAlreadyHolds(IMRestorePlanFor(none, NAN), 2340));
    // Apply refuses an unusable entry and phones that already have an island; a missing entry is fine.
    assert(IMApplyDecide(2436, 2556, 2436) == IMApplyOK);
    assert(IMApplyDecide(2556, 2556, 2436) == IMApplyAlreadyIsland);
    assert(IMApplyDecide(2556, 2796, 2436) == IMApplyOK);   // switching style
    assert(IMApplyDecide(2556, 2796, 2556) == IMApplyHardwareIsland);
    assert(IMApplyDecide(IM_ENTRY_ABSENT, 2556, 2340) == IMApplyOK && IMApplyDecide(IM_ENTRY_ABSENT, 2796, 2340) == IMApplyOK);
    assert(IMApplyDecide(IM_ENTRY_ABSENT, 2556, 2556) == IMApplyHardwareIsland);
    assert(IMApplyDecide(IM_ENTRY_UNUSABLE, 2556, 2436) == IMApplyUnreadable && IMApplyDecide(2436, 0, 2436) == IMApplyUnreadable);
    assert(IMApplyDecide(2340, 2556, 2340) == IMApplyOK && IMApplyDecide(2340, 2796, 2340) == IMApplyOK);  // 13 mini
}

// Mango's isCurrentlyEnabled, probed on its real control flow with current and
// default (nativeBounds) values fed in through the two selectors it calls; every
// row below is a result read from that run, plus the rule's own corners.
static void mango_is_currently_enabled(void) {
    static const struct { int64_t current; double native; bool enabled; bool read; } rows[] = {
        {2340, 2340, false, true},  {2340, 2556, false, true}, {2556, 2340, true, true},  {2556, 2556, false, true},
        {2796, 2340, true, true},   {2796, 2556, true, true},  {0, 2340, false, true},    {0, 2556, false, true},
        {2796, 2796, false, false}, {2436, 2340, false, false}, {2556, NAN, true, false},
    };
    for (size_t i = 0; i < sizeof rows / sizeof rows[0]; i++)
        assert(IMIsSimulated(rows[i].current, rows[i].native) == rows[i].enabled);
}

static void os_gate(void) {
    assert(!IMOSSupportsSimulation(15, 7) && !IMOSSupportsSimulation(15, 99) && !IMOSSupportsSimulation(16, 0));
    assert(!IMOSSupportsSimulation(0, 0) && !IMOSSupportsSimulation(-1, 5));
    assert(IMOSSupportsSimulation(16, 1) && IMOSSupportsSimulation(16, 5) && IMOSSupportsSimulation(17, 0) && IMOSSupportsSimulation(26, 0));
}

// The ten presets of Mango's picker, exactly as read from resolutionPresets.
static void resolution_presets(void) {
    static const struct { const char *name; int w, h; } want[IM_PRESET_COUNT] = {
        {"iPhone 16 Pro Max", 1320, 2868}, {"iPhone 16 Pro", 1206, 2622},        {"15ProMax / 14ProMax", 1290, 2796},
        {"15Pro / 14Pro (灵动岛)", 1179, 2556}, {"13ProMax / 12ProMax", 1284, 2778}, {"13Pro / 12Pro", 1170, 2532},
        {"13mini / 12mini", 1080, 2340},   {"XS / X", 1125, 2436},                {"iPad Pro 12.9\"", 2048, 2732},
        {"iPad Pro 11\"", 1668, 2388},
    };
    for (int i = 0; i < IM_PRESET_COUNT; i++) {
        const IMPreset *p = IMPresetAt(i);
        assert(p && strcmp(p->name, want[i].name) == 0 && p->width == want[i].w && p->height == want[i].h);
        assert(IMCanvasValid(p->width, p->height));
        assert(IMPresetFind(p->width, p->height) == i);
    }
    assert(IMPresetAt(-1) == NULL && IMPresetAt(IM_PRESET_COUNT) == NULL && IMPresetAt(1 << 20) == NULL);
    assert(IMPresetFind(1, 1) == -1 && IMPresetFind(1080, 2339) == -1);
    assert(IMPresetAt(IM_PRESET_DEFAULT)->width == 1179 && IMPresetAt(IM_PRESET_DEFAULT)->height == 2556);
    // The 14 Pro and Pro Max presets are the canvases of the two island modes.
    assert(IMPresetAt(3)->height == IMSubtypeForMode(0) && IMPresetAt(2)->height == IMSubtypeForMode(1));
    // Sane-size check: both sides inside the bounds, edges included.
    assert(IMCanvasValid(640, 640) && IMCanvasValid(4096, 4096) && IMCanvasValid(1080, 2340));
    assert(!IMCanvasValid(639, 2000) && !IMCanvasValid(2000, 639) && !IMCanvasValid(4097, 2000) && !IMCanvasValid(2000, 4097));
    assert(!IMCanvasValid(0, 0) && !IMCanvasValid(-1080, 2340) && !IMCanvasValid(1080, -2340));
}

// The link at the Preferences path: never delete what is not ours without
// keeping a copy, never touch what is not a file or a link, never put a kept
// copy over something that has appeared since.
static void canvas_path_decisions(void) {
    assert(IMLinkDecide(IMPathMissing) == IMLinkCreate);
    assert(IMLinkDecide(IMPathOurLink) == IMLinkReplace);
    assert(IMLinkDecide(IMPathOtherLink) == IMLinkKeepThenReplace);
    assert(IMLinkDecide(IMPathFile) == IMLinkKeepThenReplace);
    assert(IMLinkDecide(IMPathOther) == IMLinkRefuse);
    assert(IMUnlinkIsOurs(IMPathOurLink));
    assert(!IMUnlinkIsOurs(IMPathMissing) && !IMUnlinkIsOurs(IMPathOtherLink) && !IMUnlinkIsOurs(IMPathFile) && !IMUnlinkIsOurs(IMPathOther));
    assert(IMMayPutBack(IMPathMissing));
    assert(!IMMayPutBack(IMPathOurLink) && !IMMayPutBack(IMPathOtherLink) && !IMMayPutBack(IMPathFile) && !IMMayPutBack(IMPathOther));
}

// Under a canvas the live screen size may be the canvas; the model-value
// decisions use the panel size noted while no canvas was active.
static void panel_size_under_a_canvas(void) {
    // No canvas: trust what the screen says.
    assert(near(IMPanelSize(false, 2340, 2556), 2556) && near(IMPanelSize(false, 0, 2340), 2340));
    // A canvas is active: the noted panel wins, so a 14 Pro canvas on a 13 mini does
    // not make it look like a phone with a real island.
    assert(near(IMPanelSize(true, 2340, 2556), 2340));
    assert(!IMHardwareHasIsland(IMPanelSize(true, 2340, 2556)) && IMHardwareHasIsland(2556));
    assert(IMRestorePlanFor(IMStoredOriginal(0, false), IMPanelSize(true, 2340, 2556)).value == 2340);
    // Nothing noted (a canvas that was there before this package): all we have is live.
    assert(near(IMPanelSize(true, 0, 2556), 2556) && near(IMPanelSize(true, NAN, 2556), 2556) && near(IMPanelSize(true, -1, 2556), 2556));
    // Noting: only without a canvas, only a plausible size, only when it changed.
    assert(IMShouldNotePanel(false, 2340, 0) && IMShouldNotePanel(false, 2340, NAN) && IMShouldNotePanel(false, 2340, 2436));
    assert(!IMShouldNotePanel(false, 2340, 2340));
    assert(!IMShouldNotePanel(true, 2556, 2340) && !IMShouldNotePanel(true, 2340, 0));
    assert(!IMShouldNotePanel(false, NAN, 0) && !IMShouldNotePanel(false, 0, 0) && !IMShouldNotePanel(false, -3, 0) && !IMShouldNotePanel(false, INFINITY, 0));
}

// The guard undoes only what it was armed for.
static void guard_targets(void) {
    assert(IMGuardTargetsOnArm(false, 0, IM_GUARD_DISGUISE) == IM_GUARD_DISGUISE);
    assert(IMGuardTargetsOnArm(false, 0, IM_GUARD_CANVAS) == IM_GUARD_CANVAS);
    // A stale list from a guard that is no longer armed is not carried over.
    assert(IMGuardTargetsOnArm(false, IM_GUARD_DISGUISE, IM_GUARD_CANVAS) == IM_GUARD_CANVAS);
    // Armed twice inside the window: both are undone if it trips.
    assert(IMGuardTargetsOnArm(true, IM_GUARD_DISGUISE, IM_GUARD_CANVAS) == IM_GUARD_ALL);
    assert(IMGuardTargetsOnArm(true, IM_GUARD_ALL, IM_GUARD_CANVAS) == IM_GUARD_ALL);
    // Junk bits never leak in.
    assert(IMGuardTargetsOnArm(true, 0xff, 0x10) == IM_GUARD_ALL);
    assert(IMGuardTargetsOnArm(false, 0, 0xff) == IM_GUARD_ALL);
    // Undoing one leaves the other armed; undoing both leaves nothing.
    assert(IMGuardTargetsOnDone(IM_GUARD_ALL, IM_GUARD_DISGUISE) == IM_GUARD_CANVAS);
    assert(IMGuardTargetsOnDone(IM_GUARD_ALL, IM_GUARD_CANVAS) == IM_GUARD_DISGUISE);
    assert(IMGuardTargetsOnDone(IM_GUARD_CANVAS, IM_GUARD_CANVAS) == 0);
    assert(IMGuardTargetsOnDone(IM_GUARD_CANVAS, IM_GUARD_DISGUISE) == IM_GUARD_CANVAS);
    assert(IMGuardTargetsOnDone(0, IM_GUARD_ALL) == 0);
}

// Mango's pivot, 42pt below the top of the adjusted view, is the default; the
// adjustment keeps that point fixed while it scales.
static void anchor_is_mangos(void) {
    assert(near(IM_ANCHOR_Y_DEFAULT, 42.0));
    IMAdjust adj = IMSanitize((IMAdjust){1.25, 0, 0, IM_ANCHOR_Y_DEFAULT});
    IMPoint node = {187.5, 406}, pivot = {187.5, 0 + adj.anchorY};  // node's top at 0 in its parent
    IMAffine t = IMNodeTransform(adj, 25.0 / 24, pivot, node);
    IMPoint fixed = IMViewMap(t, node, pivot);
    assert(near(fixed.x, pivot.x) && near(fixed.y, pivot.y));
    // A point 10 below the pivot ends up 12.5 below it.
    IMPoint below = IMViewMap(t, node, (IMPoint){pivot.x, pivot.y + 10});
    assert(near(below.y - pivot.y, 12.5));
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
    mango_is_currently_enabled();
    os_gate();
    resolution_presets();
    canvas_path_decisions();
    panel_size_under_a_canvas();
    guard_targets();
    anchor_is_mangos();
    crash_guard();
    puts("island_test: ok");
    return 0;
}
