#import <Foundation/Foundation.h>
typedef NS_ENUM(NSInteger, PSCellType) { PSGroupCell, PSLinkCell, PSSwitchCell, PSSliderCell, PSButtonCell };
@interface PSSpecifier : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic) Class detailClass;
@property(nonatomic) PSCellType cellType;
@property(nonatomic, strong) NSMutableDictionary *properties;
@property(nonatomic, weak) id target;
@property(nonatomic) SEL setter;
@property(nonatomic) SEL getter;
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(PSCellType)cell edit:(Class)edit;
+ (instancetype)groupSpecifierWithName:(NSString *)name;
+ (instancetype)emptyGroupSpecifier;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
- (void)setButtonAction:(SEL)action;
@end
