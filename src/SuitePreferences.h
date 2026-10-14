#import <Foundation/Foundation.h>

NSString *MSPreferencesPath(void);
NSDictionary *MSReadPreferences(NSError **error);
BOOL MSPreferenceFlag(NSDictionary *snapshot, NSString *key);
BOOL MSWritePreferenceFlag(NSString *key, BOOL enabled, NSError **error);
BOOL MSWritePreferenceValue(NSString *key, id value, NSError **error);
NSArray<NSString *> *MSRepairKeys(void);
NSString *MSMarkerForKey(NSString *key);
NSArray<NSString *> *MSMarkerPathsForKey(NSString *key);
BOOL MSHasEmergencyMarker(NSString *key);
