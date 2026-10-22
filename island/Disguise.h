// The device-model half of the Dynamic Island: SpringBoard decides whether to
// build the island from MobileGestalt's ArtworkDeviceSubType, so a notch phone
// gets one by answering 2556 (14 Pro) or 2796 (14 Pro Max) there. Mango does
// exactly this from inside SpringBoard (read from its Beta9 and Beta12
// binaries); so does this, only with a stored original, an explicit restore and
// a crash-loop guard. Everything here is called from SpringBoard (Tweak.m).
//
// Result dictionaries go straight into result.plist: ok (BOOL), message
// (text for the user), and where it applies subtype, original, restore
// (NSNumber) and respring (BOOL).
#pragma once
#import <Foundation/Foundation.h>

NSDictionary *DIDisguiseStatus(double nativeHeight);
NSDictionary *DIDisguiseApply(NSInteger mode, double nativeHeight);
NSDictionary *DIDisguiseRestore(double nativeHeight);

// At SpringBoard launch, before UIKit is up: file operations only. Writes back
// the value stored when the disguise was applied.
BOOL DIDisguiseRestoreFromState(NSString **note);

// Crash-loop guard. DIGuardStartup runs once per launch and returns YES when
// this launch has to undo the disguise; DIGuardTick runs every few seconds and
// costs nothing unless the guard is armed.
BOOL DIGuardStartup(void);
void DIGuardTick(void);
BOOL DIGuardArmed(void);

// FBSystemService exitAndRelaunch:YES, the call Mango uses. NO when this
// SpringBoard does not have it.
BOOL DIRespring(void);
