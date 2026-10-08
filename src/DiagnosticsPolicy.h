#pragma once
#include <math.h>
static inline int MSDiagnosticSessionActive(int enabled,double token,double now) {
    return enabled && isfinite(token) && isfinite(now) && token>0 && now>=token && now-token<1200;
}
