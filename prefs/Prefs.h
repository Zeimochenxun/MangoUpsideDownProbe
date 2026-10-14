#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
@interface MangoSuitePrefsController : PSListController
- (id)readValue:(PSSpecifier *)specifier;
- (void)writeValue:(id)value specifier:(PSSpecifier *)specifier;
- (void)addSection:(NSString *)name footer:(NSString *)footer;
- (void)addSwitch:(NSString *)name key:(NSString *)key;
- (void)addSlider:(NSString *)name key:(NSString *)key min:(double)min max:(double)max;
- (void)addLink:(NSString *)name detail:(Class)detail;
- (void)showMessage:(NSString *)message title:(NSString *)title;
- (void)showRestartHelp;
- (void)showMissingAdaptive;
@end
