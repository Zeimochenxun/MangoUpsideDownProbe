#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
@interface MangoSuitePrefsController : PSListController
- (id)readValue:(PSSpecifier *)specifier;
- (void)writeValue:(id)value specifier:(PSSpecifier *)specifier;
- (void)addSection:(NSString *)name;
- (void)addSwitch:(NSString *)name key:(NSString *)key;
- (void)showMessage:(NSString *)message title:(NSString *)title;
- (void)showRestartHelp;
- (void)showMissingAdaptive;
@end
