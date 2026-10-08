#import <UIKit/UIKit.h>
void MSLauncherSurfacesInstall(void (^changed)(void));
void MSLauncherSurfacesUpdate(UIViewController *controller,BOOL active);
void MSLauncherSurfacesFinish(BOOL active);
