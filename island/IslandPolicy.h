#pragma once
// Decisions around the Dynamic Island simulation, as plain C so they can be
// tested on a host. The Foundation code that reads and writes the files lives
// in Disguise.m and Canvas.m and only carries these decisions out.
//
// Labels: [read] taken from Mango's MangoDynamicIslandSimulation class and the
// menu code that drives it (MangoHello, Beta9; Beta12 is identical); [inferred]
// follows from something read; [missing] not seen on a device yet.
//
// ArtworkDeviceSubType, as the original value of a phone, is the panel's pixel
// height: [read] Mango's `defaultDeviceSubType` is exactly
// (NSInteger)UIScreen.mainScreen.nativeBounds.size.height, no table. The two
// island values are the ones Mango writes: [read] mode 0 -> 2556 (14 Pro), any
// other mode -> 2796 (14 Pro Max).
#include <math.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define IM_SUBTYPE_14PRO 2556
#define IM_SUBTYPE_14PROMAX 2796

// Mode 0 is Mango's default (14 Pro); anything else is the Pro Max. [read]
static inline int64_t IMSubtypeForMode(int mode) {
    return mode == 1 ? IM_SUBTYPE_14PROMAX : IM_SUBTYPE_14PRO;
}

static inline bool IMIsIslandSubtype(int64_t value) {
    return value == IM_SUBTYPE_14PRO || value == IM_SUBTYPE_14PROMAX;
}

// The value Mango's `defaultDeviceSubType` returns for a panel of this pixel
// height. [read] fcvtzs truncates; pixel heights are whole numbers, so rounding
// gives the same value and tolerates a stray fraction.
static inline int64_t IMNativeSubtype(double nativeHeightPx) {
    return isfinite(nativeHeightPx) && nativeHeightPx > 0 ? (int64_t)llround(nativeHeightPx) : 0;
}

// A phone whose own screen already is a 14 Pro/Pro Max size has a real island;
// writing the same value would change nothing and a later restore could not
// tell it from a simulation.
static inline bool IMHardwareHasIsland(double nativeHeightPx) {
    return IMIsIslandSubtype(IMNativeSubtype(nativeHeightPx));
}

// Mango's `isCurrentlyEnabled`: the cache holds an island value that is not the
// panel's own height. [read] probed on the real control flow with every
// combination of current 0/2340/2556/2796 and default 2340/2556.
static inline bool IMIsSimulated(int64_t current, double nativeHeightPx) {
    return IMIsIslandSubtype(current) && current != IMNativeSubtype(nativeHeightPx);
}

// Mango refuses both the model change and the resolution change below iOS 16.1
// ("灵动岛模拟需要 iOS 16.1 及以上系统…"). [read] Taking a change back is never
// refused here.
static inline bool IMOSSupportsSimulation(long major, long minor) {
    return major > 16 || (major == 16 && minor >= 1);
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
    return IMNativeSubtype(nativeHeightPx);
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

// What the guard undoes when it trips: only the change that was armed for it.
// Applying the screen canvas must not take back a model change that has been
// stable for days, and the other way round. Arming again while still armed
// (both changes within the one-minute window) adds to the list.
#define IM_GUARD_DISGUISE 1
#define IM_GUARD_CANVAS 2
#define IM_GUARD_ALL (IM_GUARD_DISGUISE | IM_GUARD_CANVAS)

static inline int IMGuardTargetsOnArm(bool alreadyArmed, int current, int add) {
    return ((alreadyArmed ? current : 0) | add) & IM_GUARD_ALL;
}

static inline int IMGuardTargetsOnDone(int current, int done) {
    return current & ~done & IM_GUARD_ALL;
}

// ---- Screen canvas (Mango: applyResolutionWithWidth:height:) -----------------
// Mango's "应用分辨率" writes {canvas_height, canvas_width} into
// /var/tmp/com.apple.iokit.IOMobileGraphicsFamily.plist, replaces
// /private/var/mobile/Library/Preferences/com.apple.iokit.IOMobileGraphicsFamily.plist
// by a symbolic link to it, and restarts user space half a second later;
// "恢复默认分辨率" deletes both. [read] Whether the system honours these keys on
// iOS 16.5 is [missing] (a device run will show it); the keys are the ones the
// iOS 15/16 resolution tricks use [inferred].

typedef struct { const char *name; int width, height; } IMPreset;
#define IM_PRESET_COUNT 10

// The ten presets of Mango's picker, in its order, with its labels. [read] The
// label of the fourth entry was the only one missing from the first analysis.
static inline const IMPreset *IMPresetAt(int index) {
    static const IMPreset table[IM_PRESET_COUNT] = {
        {"iPhone 16 Pro Max", 1320, 2868},
        {"iPhone 16 Pro", 1206, 2622},
        {"15ProMax / 14ProMax", 1290, 2796},
        {"15Pro / 14Pro (灵动岛)", 1179, 2556},
        {"13ProMax / 12ProMax", 1284, 2778},
        {"13Pro / 12Pro", 1170, 2532},
        {"13mini / 12mini", 1080, 2340},
        {"XS / X", 1125, 2436},
        {"iPad Pro 12.9\"", 2048, 2732},
        {"iPad Pro 11\"", 1668, 2388},
    };
    return index >= 0 && index < IM_PRESET_COUNT ? &table[index] : NULL;
}

// Mango never validates (its picker only offers the table above). This package
// takes only a preset index from the pane and checks the size anyway.
#define IM_CANVAS_MIN 640
#define IM_CANVAS_MAX 4096
static inline bool IMCanvasValid(long width, long height) {
    return width >= IM_CANVAS_MIN && width <= IM_CANVAS_MAX && height >= IM_CANVAS_MIN && height <= IM_CANVAS_MAX;
}

// The preset the picker starts on until the user chooses: the 14 Pro size, the
// canvas that goes with the 14 Pro island. Mango starts on its first entry.
#define IM_PRESET_DEFAULT 3

// Index of the preset with exactly this size, or -1.
static inline int IMPresetFind(long width, long height) {
    for (int i = 0; i < IM_PRESET_COUNT; i++) {
        const IMPreset *p = IMPresetAt(i);
        if (p->width == width && p->height == height) return i;
    }
    return -1;
}

// What sits at the Preferences path before the link is made. Mango deletes
// whatever is there; this package keeps a copy of a file or a foreign link and
// puts it back on restore, and never touches anything that is not a file or a
// link.
typedef enum {
    IMPathMissing,
    IMPathOurLink,    // symbolic link to the canvas file in /var/tmp (ours, or Mango's: same paths)
    IMPathOtherLink,  // symbolic link to somewhere else
    IMPathFile,       // regular file
    IMPathOther       // directory, socket, ...
} IMPathKind;

typedef enum {
    IMLinkCreate,           // nothing there: make the link
    IMLinkReplace,          // our own link: replace it
    IMLinkKeepThenReplace,  // somebody else's file or link: keep a copy, then replace
    IMLinkRefuse            // not a file or a link: leave alone and say so
} IMLinkAction;

static inline IMLinkAction IMLinkDecide(IMPathKind kind) {
    switch (kind) {
        case IMPathMissing: return IMLinkCreate;
        case IMPathOurLink: return IMLinkReplace;
        case IMPathOtherLink:
        case IMPathFile: return IMLinkKeepThenReplace;
        default: return IMLinkRefuse;
    }
}

// On restore only a link to the canvas file is removed; anything else at the
// path has been put there by someone else since and stays.
static inline bool IMUnlinkIsOurs(IMPathKind kind) { return kind == IMPathOurLink; }

// A kept copy may be put back only into an empty slot.
static inline bool IMMayPutBack(IMPathKind kindNow) { return kindNow == IMPathMissing; }

// The panel's own pixel size while a canvas is active. UIScreen.nativeBounds may
// then report the canvas instead of the panel [missing: not seen on a device], and
// Mango's `defaultDeviceSubType` reads it live: after a 14 Pro sized canvas it
// would see "a phone that already has an island" and a restore would write 2556.
// This package keeps the size it saw while no canvas was active and uses that for
// every decision about the model value.
static inline double IMPanelSize(bool canvasActive, double saved, double live) {
    return canvasActive && isfinite(saved) && saved > 0 ? saved : live;
}

// Note the live size as the panel's only while no canvas is active, when it is a
// plausible size, and when it differs from what is already noted.
static inline bool IMShouldNotePanel(bool canvasActive, double live, double saved) {
    return !canvasActive && isfinite(live) && live > 0 && !(isfinite(saved) && saved == live);
}
