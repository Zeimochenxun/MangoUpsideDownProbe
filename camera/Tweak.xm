// MangoUpsideDownCamera 1.0.0. Experimental; see EVIDENCE.md.
//
// Separate package from MangoUpsideDownWorld, deliberately: that dylib only
// injects into com.apple.springboard and its entire job is making Mango
// cooperate with an inversion state that already exists there. This one
// injects into every process that has UIApplication loaded (see the
// Filter.Classes entry in MangoUpsideDownCamera.plist) so that any app's
// camera-facing view controller -- not just SpringBoard's own UI -- can be
// asked to allow the upside-down orientation while the phone is physically
// inverted. That is a categorically different injection scope and risk
// profile (a mistake here can reach every app on the device, not just
// SpringBoard), which is the whole reason this ships as its own
// dylib/plist/control/disable-file rather than folding into the existing
// project -- see EVIDENCE.md for the full reasoning and the research this
// was based on.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#include <unistd.h>

static const char *Disabled="/var/mobile/Library/Preferences/MangoUpsideDownCamera.disabled";
static BOOL InvertOrientations=YES;

// Self-contained: this is a fully separate binary from MangoUpsideDownWorld's
// Tweak.xm and shares no code with it (each package is compiled and injected
// independently), so it carries its own minimal copy of the same
// verify-before-hook check that file's Signature() already does, rather than
// assume a public API's shape can never change across iOS versions -- the
// same reasoning, applied to a public UIKit method instead of a private
// Mango class.
static BOOL Signature(Class c,SEL sel,const char *ret,NSArray<NSString *> *args){
    Method m=class_getInstanceMethod(c,sel);char buf[512]={0};
    if(!m||method_getNumberOfArguments(m)!=args.count+2)return NO;
    method_getReturnType(m,buf,sizeof(buf));if(strcmp(buf,ret))return NO;
    for(NSUInteger i=0;i<args.count;i++){method_getArgumentType(m,(unsigned)i+2,buf,sizeof(buf));if(strcmp(buf,args[i].UTF8String))return NO;}
    return YES;
}

// -[UIViewController supportedInterfaceOrientations] decides, per view
// controller, whether that view is even allowed to rotate to
// PortraitUpsideDown -- Apple's own documented default on iPhone (when a
// subclass doesn't override this) is AllButUpsideDown, i.e. every app is
// upside-down-excluded unless it opts in. This hook only ever ADDS the
// upside-down bit onto whatever the real original implementation already
// returns, and only in the one moment the device is actually physically
// inverted -- an app's own restrictions (portrait-only, no landscape, etc.)
// are preserved untouched. The moment device orientation says otherwise,
// this is a byte-for-byte passthrough, matching the "inert when not
// applicable" posture every hook in the sibling MangoUpsideDownWorld
// project already has.
//
// Real limitation, disclosed rather than hidden: hooking THIS class's own
// (the UIViewController base class's) implementation only affects view
// controllers that never overrode the method themselves and so actually
// dispatch to this base implementation. Apple's own guidance treats
// supportedInterfaceOrientations as meant to be fully replaced, not chained
// with super -- so any view controller that declares its own orientation
// mask (plausibly including Apple's own Camera.app) bypasses this hook
// entirely; there is no single hook point that transparently reaches every
// possible override in every app. Confirming whether Camera.app itself is
// covered by this first pass requires a real-device test (see README.md);
// if it isn't, the next step is a broader, riskier pass that finds and
// patches every overriding subclass individually at install time, held
// back until this simpler pass is confirmed insufficient rather than built
// up front.
static UIInterfaceOrientationMask (*OrigSupportedOrientations)(id,SEL);
static UIInterfaceOrientationMask HookSupportedOrientations(UIViewController *self,SEL cmd){
    UIInterfaceOrientationMask orig=OrigSupportedOrientations(self,cmd);
    if(!InvertOrientations||![NSThread isMainThread])return orig;
    // Re-checked live on every call, not just once at Install() time: this
    // file has no periodic reconciliation loop the way the sibling
    // MangoUpsideDownWorld project does (its Reconcile() polls its own
    // Disabled file every 250ms even for already-running state), so
    // without this the kill switch would only ever take effect for an
    // app's NEXT launch, never for one already running -- too weak a
    // guarantee for what this file's own README already calls an
    // emergency escape hatch. access() is one cheap syscall and this
    // method is only ever called when UIKit is actually deciding whether
    // to rotate, not every frame, so checking it here every time costs
    // nothing that matters.
    if(access(Disabled,F_OK)==0)return orig;
    // UIDevice.orientation, not anything Mango- or SpringBoard-specific:
    // Mango's own orientation report (what MangoUpsideDownWorld's
    // Orientation() reads) is a class method Mango itself injects only
    // into SpringBoard's process -- it does not exist here. UIDevice's
    // orientation is real accelerometer-derived hardware state, identical
    // in every process, with no dependency on any inversion plugin's own
    // state: the phone being physically upside-down is a fact about the
    // phone, not about what any plugin has done to a UI.
    if(UIDevice.currentDevice.orientation!=UIDeviceOrientationPortraitUpsideDown)return orig;
    return orig|UIInterfaceOrientationMaskPortraitUpsideDown;
}

static void Install(void){
    if(access(Disabled,F_OK)==0)return;
    // Defensive, even though MangoUpsideDownCamera.plist's own
    // Filter.Classes entry is already supposed to be the reason this dylib
    // is only ever loaded into a process that has UIApplication in the
    // first place: this project's own established style re-verifies
    // preconditions in code rather than trust a single upstream guarantee
    // (the sibling project's Install() re-checks method signatures at
    // runtime instead of trusting that a private class still looks the way
    // prior research said it did -- same idea, applied here to the
    // injection boundary itself). objc_getClass, not
    // UIApplication.sharedApplication: this constructor runs at dylib
    // load time, before UIApplicationMain has run in this process, so the
    // shared instance does not exist yet even in a completely normal app;
    // checking that the CLASS is loaded (true as soon as dyld has mapped
    // UIKit, which happens before constructors run) is the check that is
    // actually meaningful this early.
    if(!objc_getClass("UIApplication"))return;
    // Never run inside SpringBoard: that process's own upside-down handling
    // is MangoUpsideDownWorld's job end to end, and two independently
    // written pieces of code both adjusting orientation logic in the same
    // process is exactly the kind of conflict this project's own
    // Conflicts: field (between MangoUpsideDownWorld and the older
    // MangoUpsideDownFix) already guards against elsewhere.
    NSString *bundleID=NSBundle.mainBundle.bundleIdentifier;
    if([bundleID isEqualToString:@"com.apple.springboard"])return;
    Class vc=UIViewController.class;
    SEL sel=@selector(supportedInterfaceOrientations);
    if(!Signature(vc,sel,@encode(UIInterfaceOrientationMask),@[])){
        InvertOrientations=NO;NSLog(@"[MangoUDCamera] NO HOOK: signature mismatch");return;}
    MSHookMessageEx(vc,sel,(IMP)HookSupportedOrientations,(IMP *)&OrigSupportedOrientations);
    // Deferred to the main queue, not called directly here: unlike the
    // method swizzle above (which only patches a class's IMP and needs no
    // run loop), generating live device-orientation notifications is tied
    // to the main run loop, which is not yet spinning at raw constructor
    // time (dylib load happens before this process's own main() runs).
    // Calling it once further ties the fallback ("not yet known") case to
    // an actual .unknown reading rather than never becoming live at all;
    // apps that already call this themselves are unaffected -- multiple
    // begin/end callers are supported by design.
    dispatch_async(dispatch_get_main_queue(),^{
        [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
    });
    NSLog(@"[MangoUDCamera] INSTALLED 1.0.0 in %@",bundleID?:@"(unknown bundle)");
}
__attribute__((constructor)) static void StartCamera(void){@autoreleasepool{Install();}}
