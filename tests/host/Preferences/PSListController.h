#import <UIKit/UIKit.h>
#import <Preferences/PSSpecifier.h>
@interface PSListController : UIViewController {
@protected
    NSMutableArray *_specifiers;
}
- (NSArray *)specifiers;
- (void)reloadSpecifiers;
@end
