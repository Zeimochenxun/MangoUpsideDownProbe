#pragma once
#import <UIKit/UIKit.h>
// Mango's circle black glow ("Black Glow Shape: circle") drawn on the idle pill; opacity and spread
// follow Mango's own Glow Opacity / Glow Spread settings.
UIView *MSIdleGlowCreate(void);
// Sizes the glow to host.bounds, places it directly above backing, and applies opacity.
void MSIdleGlowSync(UIView *glow, UIView *host, UIView *backing, CGFloat opacity);
