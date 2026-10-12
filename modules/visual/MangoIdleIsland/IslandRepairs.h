#pragma once
#import <UIKit/UIKit.h>
BOOL MSIslandUsesOwnedRim(void);
BOOL MSIslandRepairsNeedFrames(void);
void MSIslandRepairUpdate(UIView *host, UIView *idle, BOOL edgeOptIn);
void MSIslandNotificationLayout(UIView *view);
// Mean luminance (0...1) of the ring around the island, -1 when unknown. Throttled to about one capture a second.
double MSIslandBackgroundLuminance(UIView *host, UIView *glass);
