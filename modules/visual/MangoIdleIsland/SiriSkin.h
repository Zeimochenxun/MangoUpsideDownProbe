#pragma once
#import <UIKit/UIKit.h>
// iOS 27 "new Siri" look for the idle Island: dark glass above, clear below, a prismatic light streak between.
// Drawn over the glass backing and clipped to the same pill, so the Island shape and Mango's refraction stay.
UIView *MSSiriSkinCreate(void);
// Sizes the skin to host.bounds, places it directly above backing, and applies opacity.
void MSSiriSkinSync(UIView *skin, UIView *host, UIView *backing, CGFloat opacity);
