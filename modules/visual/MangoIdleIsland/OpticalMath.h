#pragma once
#include <math.h>
#include <stddef.h>
typedef struct { double r,g,b; } MSRGB;
typedef struct { double weight; MSRGB sum; unsigned count; } MSColorBin;
static inline double MSOpticalRadius(double width,double height,double stroke) {
    if (!isfinite(width) || !isfinite(height) || !isfinite(stroke) || width<=0 || height<=0) return 0;
    return fmax(0,(fmin(width,height)-fmax(0,stroke))*.5);
}
static inline double MSColorSaturation(MSRGB c) {
    double hi=fmax(c.r,fmax(c.g,c.b)),lo=fmin(c.r,fmin(c.g,c.b));
    return hi>1e-6 ? (hi-lo)/hi : 0;
}
static inline unsigned MSColorHueBin(MSRGB c) {
    double hi=fmax(c.r,fmax(c.g,c.b)),lo=fmin(c.r,fmin(c.g,c.b)),d=hi-lo,h=0;
    if (d<.02) return 12;
    if (hi==c.r) h=fmod((c.g-c.b)/d+6,6);
    else if (hi==c.g) h=(c.b-c.r)/d+2;
    else h=(c.r-c.g)/d+4;
    return (unsigned)fmin(11,floor(h*2));
}
static inline void MSColorAccumulate(MSColorBin bins[13],MSRGB color) {
    unsigned index=MSColorHueBin(color);
    // Both area and saturation contribute; a large moderate region can beat
    // a tiny saturated pixel. Neutral backgrounds remain neutral.
    double weight=.25+MSColorSaturation(color)*.75;
    bins[index].weight+=weight; ++bins[index].count;
    bins[index].sum.r+=color.r*weight; bins[index].sum.g+=color.g*weight; bins[index].sum.b+=color.b*weight;
}
static inline int MSColorDominant(MSColorBin bins[13],MSRGB *result) {
    unsigned best=0; double weight=0;
    for (unsigned i=0;i<13;i++) if (bins[i].weight>weight) { best=i; weight=bins[i].weight; }
    if (weight<=0) return 0;
    *result=(MSRGB){bins[best].sum.r/weight,bins[best].sum.g/weight,bins[best].sum.b/weight}; return 1;
}
static inline MSRGB MSColorSmooth(MSRGB previous,MSRGB next,double elapsed,double dynamics) {
    double rate=2+fmax(0,fmin(1,dynamics))*8;
    double alpha=1-exp(-fmax(0,fmin(.5,elapsed))*rate);
    return (MSRGB){previous.r+(next.r-previous.r)*alpha,previous.g+(next.g-previous.g)*alpha,previous.b+(next.b-previous.b)*alpha};
}
