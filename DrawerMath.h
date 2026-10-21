// The drawer's pure math, shared by Tweak.m and tests/check.m. Units: drawer
// progress P, 0 closed, 1 open, above 1 stretched (in rows).
#pragma once
#include <math.h>

static const double DDStretch = .25; // how far past open the rubber band reaches
static const double DDNarrow = .04;  // horizontal squeeze at full stretch

// UIScrollView-style resistance past fully open, approaching DDStretch.
static inline double DDRubber(double over) { return DDStretch * (1 - 1 / (over * .55 / DDStretch + 1)); }
// Progress for a raw pull: linear up to open, rubber band beyond.
static inline double DDPull(double raw) { return raw > 1 ? 1 + DDRubber(raw - 1) : fmax(0, raw); }
// The dock's horizontal scale: below 1 only while stretched.
static inline double DDSqueeze(double p) { return p <= 1 ? 1 : 1 - DDNarrow * fmin(1, (p - 1) / DDStretch); }
// Icons a row of the platter fits, less both margins and any divider gap.
static inline unsigned long DDCapacity(double width, double margin, double gap, double pitch, double icon) {
    return (unsigned long)fmax(1, floor((width - 2 * margin - gap + (pitch - icon)) / pitch));
}
// Open or closed after a release: where the flick would coast to; a
// cancelled pan goes back to where it started.
static inline int DDReleaseOpen(int ended, double p, double startP, double velocityY, double extent) {
    return ended ? p - velocityY * .15 / extent > .5 : startP > .5;
}
// The dock heading out: presentation progress falling and below .8 (its
// spring only undershoots a few percent after a ~1.27 overshoot).
static inline int DDLeaving(double progress, double last) {
    return isfinite(progress) && progress < last - .001 && progress < .8;
}
