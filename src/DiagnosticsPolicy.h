#pragma once
#include <math.h>
#include <stdio.h>
#include <string.h>
static inline int MSDiagnosticSessionActive(int enabled,double token,double now) {
    return enabled && isfinite(token) && isfinite(now) && token>0 && now>=token && now-token<1200;
}
static inline int MSDiagnosticRecordHeader(const char *line) {
    double time;
    return line && sscanf(line,"%lf version=",&time)==1 && strstr(line," version=")!=NULL;
}
static inline int MSDiagnosticRecordCurrent(const char *line,double token) {
    if (!MSDiagnosticRecordHeader(line) || !isfinite(token) || token<=0) return 0;
    const char *tag=strstr(line," session=");
    double logged;
    return tag && sscanf(tag," session=%lf",&logged)==1 && isfinite(logged) && fabs(logged-token)<=.001;
}
