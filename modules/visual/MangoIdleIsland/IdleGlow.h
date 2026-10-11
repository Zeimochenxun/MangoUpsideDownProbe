#pragma once
#import <UIKit/UIKit.h>
// The Island's black glow (black at the top feathering to clear, "aligned with iOS 27") on the idle pill.
// Style, opacity and spread follow Mango's own Black Glow Shape / Opacity / Range settings.
UIView *MSIdleGlowCreate(void);
// Sizes the glow to host.bounds, places it directly above backing, and applies opacity.
void MSIdleGlowSync(UIView *glow, UIView *host, UIView *backing, CGFloat opacity);
