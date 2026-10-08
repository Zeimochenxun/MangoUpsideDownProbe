#ifndef MANGO_SUITE_POLICY_H
#define MANGO_SUITE_POLICY_H

enum { MS_IDLE = 1, MS_ADAPTIVE = 2, MS_WORLD = 4, MS_SPLIT = 8 };
enum { MS_OTHER, MS_SPRINGBOARD, MS_BACKBOARD };
typedef struct {
    int enabled, idle, adaptive, world, split;
    int idleEmergency, worldEmergency, splitEmergency, legacyOrientation;
} MSState;

static inline unsigned MSModulesForProcess(MSState state, int process) {
    if (!state.enabled) return 0;
    if (process == MS_BACKBOARD) return state.adaptive ? MS_ADAPTIVE : 0;
    if (process != MS_SPRINGBOARD) return 0;
    unsigned mask = 0;
    if (state.idle && !state.idleEmergency) mask |= MS_IDLE;
    if (state.world && !state.worldEmergency && !state.legacyOrientation) mask |= MS_WORLD;
    if (state.split && !state.splitEmergency && !state.legacyOrientation) mask |= MS_SPLIT;
    return mask;
}
static inline unsigned MSModulesWithOptics(MSState state,int process,int optical) {
    unsigned mask=MSModulesForProcess(state,process);
    if (process==MS_SPRINGBOARD && state.enabled && optical && !state.idleEmergency) mask|=MS_IDLE;
    return mask;
}
#endif
