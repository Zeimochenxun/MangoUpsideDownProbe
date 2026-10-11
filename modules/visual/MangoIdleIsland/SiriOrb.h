#pragma once
#import <UIKit/UIKit.h>
// iOS 27 "new Siri" glass orb used as the idle Island skin (pure Core Animation).
UIView *MSSiriOrbCreate(void);
// Centers a host-height circle in host at the given opacity; inserts it at the bottom of host.
void MSSiriOrbSync(UIView *orb, UIView *host, CGFloat opacity);
