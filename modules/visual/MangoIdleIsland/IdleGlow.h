#pragma once
#import <UIKit/UIKit.h>
// Top-black "Siri" glow for the idle pill: black fading to clear, a soft lower edge, and the glass backing
// faded to clear underneath. Density and fade position come from the suite settings.
UIView *MSIdleGlowCreate(void);
// Sizes the glow to host.bounds, places it directly above backing, applies opacity, and fades the backing.
void MSIdleGlowSync(UIView *glow, UIView *host, UIView *backing, CGFloat opacity);
// Removes the backing fade this module installed (no-op otherwise).
void MSIdleGlowRelease(UIView *backing);
