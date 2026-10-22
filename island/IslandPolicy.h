#pragma once
// Decisions around the Dynamic Island disguise, as plain C so they can be
// tested on a host. The Foundation code that reads and writes the plist lives
// in Disguise.m and only carries these decisions out.
//
// ArtworkDeviceSubType is the logical screen height times the native scale, i.e.
// UIScreen.nativeBounds.height: 2436 for 375x812pt phones (X/XS/11 Pro/12 mini/
// 13 mini), 2532 for 390x844, 2778 for 428x926, 2556 for the 14 Pro (393x852) and
// 2796 for the 14 Pro Max (430x932). The two island values are the ones Mango
// writes (read from its Beta9 and Beta12 binaries); the rule for the original is
// Mango's own "default derived from nativeBounds" plus the pattern above.
#include <math.h>
#include <stdbool.h>
#include <stdint.h>

#define IM_SUBTYPE_14PRO 2556
#define IM_SUBTYPE_14PROMAX 2796

// Mode 0 is Mango's default (14 Pro); anything else is the Pro Max.
static inline int64_t IMSubtypeForMode(int mode) {
    return mode == 1 ? IM_SUBTYPE_14PROMAX : IM_SUBTYPE_14PRO;
}

static inline bool IMIsIslandSubtype(int64_t value) {
    return value == IM_SUBTYPE_14PRO || value == IM_SUBTYPE_14PROMAX;
}

// A phone whose own screen already is a 14 Pro/Pro Max size has a real island;
// writing the same value would change nothing and a later restore could not
// tell it from a disguise.
static inline bool IMHardwareHasIsland(double nativeHeightPx) {
    return isfinite(nativeHeightPx) && IMIsIslandSubtype((int64_t)llround(nativeHeightPx));
}

typedef enum {
    IMBackupKeep,     // an original is already stored: never overwrite it
    IMBackupStore,    // the current value is plausibly original: store it now
    IMBackupUnknown,  // already an island value and nothing stored: the original is lost
    IMBackupUnreadable
} IMBackupAction;

static inline IMBackupAction IMBackupDecide(bool haveBackup, int64_t current) {
    if (haveBackup) return IMBackupKeep;
    if (current <= 0) return IMBackupUnreadable;
    return IMIsIslandSubtype(current) ? IMBackupUnknown : IMBackupStore;
}

// What a restore writes: the stored original, else the value derived from the
// screen (Mango's rule). An island value is never accepted as an "original".
static inline int64_t IMRestoreValue(bool haveBackup, int64_t backup, double nativeHeightPx) {
    if (haveBackup && backup > 0 && !IMIsIslandSubtype(backup)) return backup;
    return isfinite(nativeHeightPx) ? (int64_t)llround(nativeHeightPx) : 0;
}

typedef enum { IMApplyOK, IMApplyAlreadyIsland, IMApplyHardwareIsland, IMApplyUnreadable } IMApplyCheck;

static inline IMApplyCheck IMApplyDecide(int64_t current, int64_t target, double nativeHeightPx) {
    if (current <= 0 || target <= 0) return IMApplyUnreadable;
    if (IMHardwareHasIsland(nativeHeightPx)) return IMApplyHardwareIsland;
    return current == target ? IMApplyAlreadyIsland : IMApplyOK;
}

// ---- Crash-loop guard -----------------------------------------------------
// After the disguise is applied SpringBoard restarts and re-reads the value. If
// the new value makes SpringBoard crash on launch, tweaks may stop loading
// (safe mode) before anyone could undo it, so the package undoes it itself:
// armed at apply time, it counts SpringBoard runs that began after arming and
// died within IM_GUARD_MIN_LIFE seconds, and trips on the IM_GUARD_TRIP-th.
// One is enough: safe mode can start right after the first crash, and a
// SpringBoard that dies within seconds of the first launch with a new device
// value is reason enough to take the value back. A run that lives
// IM_GUARD_STABLE seconds disarms it.
#define IM_GUARD_MIN_LIFE 15.0
#define IM_GUARD_STABLE 60.0
#define IM_GUARD_TRIP 1

typedef struct {
    bool armed;
    int shortRuns;
    double armedAt, lastStart, lastAlive;  // seconds on any monotone-enough clock
} IMGuardState;

static inline void IMGuardArm(IMGuardState *g, double now) {
    g->armed = true;
    g->shortRuns = 0;
    g->armedAt = now;
}

static inline void IMGuardDisarm(IMGuardState *g) {
    g->armed = false;
    g->shortRuns = 0;
}

// Call once per SpringBoard launch. Returns true when this launch must undo the
// disguise.
static inline bool IMGuardLaunch(IMGuardState *g, double now) {
    // The run that ends here is evidence only if it began after arming; the run
    // that armed the guard (and may itself have been short) is not.
    bool counts = g->lastStart > g->armedAt;
    double life = g->lastStart > 0 ? g->lastAlive - g->lastStart : 1e9;
    if (g->armed && counts && life < IM_GUARD_MIN_LIFE) g->shortRuns++;
    else if (!g->armed || life >= IM_GUARD_MIN_LIFE) g->shortRuns = 0;
    g->lastStart = now;
    g->lastAlive = now;
    return g->armed && g->shortRuns >= IM_GUARD_TRIP;
}

// Call every few seconds while SpringBoard runs.
static inline void IMGuardAlive(IMGuardState *g, double now) {
    g->lastAlive = now;
    if (g->armed && g->lastStart > g->armedAt && now - g->lastStart >= IM_GUARD_STABLE)
        IMGuardDisarm(g);
}
