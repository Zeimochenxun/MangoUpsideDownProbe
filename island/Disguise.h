// The device-model half of the Dynamic Island: SpringBoard decides whether to
// build the island from MobileGestalt's ArtworkDeviceSubType, so a notch phone
// gets one by answering 2556 (14 Pro) or 2796 (14 Pro Max) there. Mango does
// exactly this from inside SpringBoard (read from its Beta9 and Beta12
// binaries); so does this, only with a stored original, an explicit restore and
// a crash-loop guard. Everything here is called from SpringBoard (Tweak.m).
//
// Result dictionaries go straight into result.plist: ok (BOOL), message
// (text for the user), and where it applies subtype, original, restore
// (NSNumber) and respring (BOOL). Status adds simulated (Mango's
// isCurrentlyEnabled: an island value that is not the panel's own height) and
// osSupported (Mango's iOS 16.1 gate, applied to apply only).
#pragma once
#import <Foundation/Foundation.h>

NSDictionary *DIDisguiseStatus(double nativeHeight);
NSDictionary *DIDisguiseApply(NSInteger mode, double nativeHeight);
NSDictionary *DIDisguiseRestore(double nativeHeight);

// At SpringBoard launch, before UIKit is up: file operations only. Writes back
// the value stored when the disguise was applied.
BOOL DIDisguiseRestoreFromState(NSString **note);

// Crash-loop guard, shared by the model change (here) and the screen canvas
// (Canvas.m). DIGuardStartup runs once per launch and returns YES when this
// launch has to undo something; DIGuardTargets then says what (IM_GUARD_DISGUISE
// and/or IM_GUARD_CANVAS, IslandPolicy.h): only the change that was armed for
// the guard is undone. DIGuardTick runs every few seconds and costs nothing
// unless the guard is armed. A change arms the guard when it is made
// (DIGuardArmFor) and takes its own bit back when it is undone (DIGuardDoneFor);
// the guard stays armed for whatever is left.
BOOL DIGuardStartup(void);
int DIGuardTargets(void);
void DIGuardTick(void);
BOOL DIGuardArmed(void);
void DIGuardArmFor(int target);
void DIGuardDoneFor(int target);

// FBSystemService exitAndRelaunch:YES, the call Mango uses. NO when this
// SpringBoard does not have it.
BOOL DIRespring(void);
