// Host shims let the actual controller source run against Foundation on macOS.
// They do not emulate rendering, touch handling or the real iOS Preferences UI.
#import <Preferences/PSListController.h>
@implementation UIViewController
- (void)viewWillAppear:(BOOL)animated { (void)animated; }
- (void)presentViewController:(id)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    self.presentedViewController = controller; (void)animated; if (completion) completion();
}
@end
@implementation UIAlertAction
+ (instancetype)actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^)(UIAlertAction *))handler {
    (void)title; (void)style; (void)handler; return [self new];
}
@end
@implementation UIAlertController
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(UIAlertControllerStyle)style {
    (void)style; UIAlertController *result = [self new]; result.title = title; result.message = message; return result;
}
- (void)addAction:(UIAlertAction *)action { (void)action; }
@end
@implementation PSSpecifier
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(PSCellType)cell edit:(Class)edit {
    (void)edit;
    PSSpecifier *result = [self new]; result.name = name; result.detailClass = detail;
    result.target = target; result.setter = set; result.getter = get;
    result.cellType = cell; result.properties = [NSMutableDictionary new]; return result;
}
+ (instancetype)groupSpecifierWithName:(NSString *)name {
    return [self preferenceSpecifierNamed:name target:nil set:NULL get:NULL detail:Nil cell:PSGroupCell edit:Nil];
}
+ (instancetype)emptyGroupSpecifier { return [self groupSpecifierWithName:@""]; }
- (void)setProperty:(id)value forKey:(NSString *)key { self.properties[key] = value; }
- (id)propertyForKey:(NSString *)key { return self.properties[key]; }
- (void)setButtonAction:(SEL)action { self.properties[@"action"] = NSStringFromSelector(action); }
@end
@implementation PSListController
- (NSArray *)specifiers { return _specifiers; }
- (void)reloadSpecifiers { _specifiers = nil; (void)[self specifiers]; }
@end
@interface MangoIslandAdaptiveColorPrefsController : PSListController @end
@implementation MangoIslandAdaptiveColorPrefsController @end

@interface MangoSuiteDiagnosticsController : PSListController @end
@implementation MangoSuiteDiagnosticsController @end
