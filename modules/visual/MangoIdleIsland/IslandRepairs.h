#pragma once
#import <UIKit/UIKit.h>
BOOL MSIslandUsesOwnedRim(void);
BOOL MSIslandRepairsNeedFrames(void);
void MSIslandRepairUpdate(UIView *host, UIView *idle, BOOL edgeOptIn);
void MSIslandNotificationLayout(UIView *view);
