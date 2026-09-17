// MangoUpsideDownCamera 1.1.0. Experimental; see EVIDENCE.md.
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
//
// 1.1.0 real-device result: with 1.0.0 installed, Camera.app's preview did
// NOT follow inversion, in both tested configurations -- a cold launch
// performed while already physically inverted, and a live flip while
// Camera.app was already open in the foreground. Both failing rules out an
// iOS-16-specific "the system never re-queries orientation live" theory
// (a cold launch queries fresh regardless of that), and points at the
// limitation this file's own 1.0.0 comments already disclosed up front:
// Camera.app's real view controller (or something wrapping it) very likely
// overrides -supportedInterfaceOrientations itself, bypassing a hook on
// UIViewController's own base implementation entirely. Rather than jump
// straight to blindly hooking every class in every process that overrides
// this method (the actual "Tier B" this file's own history already
// disclosed as the next, riskier step), this version adds a read-only,
// toggle-gated diagnostic that names the REAL overriding class(es) in
// whatever process it runs in -- the same "log real runtime state before
// hooking anything new" discipline the sibling MangoUpsideDownWorld project
// already used (alpha5/6/11's CLASSDUMP) to turn blind guesses on the pill
// into a single confirmed class name, rather than repeating alpha1-8's
// mistake of hooking based on inference alone.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <string.h>

static const char *Disabled="/var/mobile/Library/Preferences/MangoUpsideDownCamera.disabled";
// 1.1.0: same toggle-file mechanism the sibling project's TracePath already
// uses, checked once at Install() time -- this is a one-shot per-process
// diagnostic (the runtime class scan below), not a continuous poll loop
// like the sibling's Reconcile(), so there is no periodic re-check here.
static const char *TracePath="/var/mobile/Library/Preferences/MangoUpsideDownCamera.trace";
static BOOL InvertOrientations=YES;
static BOOL Tracing=NO;
// Cached once at Install() time rather than re-queried on every hook call:
// NSBundle.mainBundle.bundleIdentifier does not change for the lifetime of
// a process, and this hook can fire from any app on the device, so caching
// it once avoids repeated Foundation calls in what is meant to be a cheap,
// frequently-reachable hook -- and lets every log line from a given
// process's shared, cross-app log file be attributed to the right app.
static NSString *BundleID;

// 1.1.0: this file has no periodic reconciliation loop and (until now) no
// persistent log -- unlike the sibling project, whose Log() is the single
// chokepoint every one of its 25+ log call sites already goes through, this
// file previously only used bare NSLog(), which requires a Mac/Console.app
// or an on-device syslog viewer to read. Since every process this dylib
// injects into shares the SAME log file path, lines are tagged with
// BundleID so a mixed log (many apps writing to it over time) stays
// attributable. Mirrors the sibling's Log() structure (mkdir, O_APPEND,
// 512KB truncation) as an independent, self-contained implementation --
// this file still shares no code with the sibling's Tweak.xm.
static void Log(NSString *s){
    NSString *tagged=[NSString stringWithFormat:@"[%@] %@",BundleID?:@"?",s];
    NSLog(@"[MangoUDCamera] %@",tagged);
    mkdir("/var/mobile/Library/Logs",0755);
    int fd=open("/var/mobile/Library/Logs/MangoUpsideDownCamera.log",O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW,0600);
    if(fd<0)return;
    struct stat st;
    if(fstat(fd,&st)||!S_ISREG(st.st_mode)){close(fd);return;}
    if(st.st_size>512*1024)ftruncate(fd,0);
    NSData *b=[[NSString stringWithFormat:@"%.3f %@\n",NSDate.timeIntervalSinceReferenceDate,tagged] dataUsingEncoding:NSUTF8StringEncoding];
    (void)write(fd,b.bytes,b.length);close(fd);
}

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
static BOOL ValidClass(Class c,Class base){for(;c;c=class_getSuperclass(c))if(c==base)return YES;return NO;}

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
// mask bypasses this hook entirely; there is no single hook point that
// transparently reaches every possible override in every app. 1.1.0's
// real-device result (see the file-header comment) confirms Camera.app is
// one such case; LogOverridingClasses() below exists to name the real
// class responsible instead of guessing one to hook next.
static UIInterfaceOrientationMask (*OrigSupportedOrientations)(id,SEL);
static UIInterfaceOrientationMask HookSupportedOrientations(UIViewController *self,SEL cmd){
    UIInterfaceOrientationMask orig=OrigSupportedOrientations(self,cmd);
    if(Tracing)Log([NSString stringWithFormat:@"CALL class=%@ orig=0x%lx",NSStringFromClass(self.class),(unsigned long)orig]);
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
    UIDeviceOrientation device=UIDevice.currentDevice.orientation;
    if(device!=UIDeviceOrientationPortraitUpsideDown)return orig;
    UIInterfaceOrientationMask patched=orig|UIInterfaceOrientationMaskPortraitUpsideDown;
    if(Tracing)Log([NSString stringWithFormat:@"HIT class=%@ device=%ld patched=0x%lx",NSStringFromClass(self.class),(long)device,(unsigned long)patched]);
    return patched;
}

// 1.1.0: read-only, toggle-gated. Runs once per process, only when
// TracePath exists, and never modifies anything it finds -- it walks every
// currently-loaded class, keeps the ones that are UIViewController
// subclasses (excluding UIViewController itself, already covered by the
// hook above) AND directly define (not inherit) their own
// -supportedInterfaceOrientations, and logs their real names. This answers
// directly, for whatever process it runs in, which concrete class(es) --
// if any -- bypass the base-class hook, the same way the sibling project's
// CLASSDUMP turned "some private subclass probably overrides this" into a
// single confirmed name (SBSystemApertureLongPressGestureRecognizer)
// instead of guessing and hooking blindly. Bounded like every runtime walk
// in the sibling project's own Tweak.xm: capped list length so a class with
// an unexpectedly large number of matches cannot flood the log.
static void LogOverridingClasses(void){
    unsigned count=0;
    Class *classes=objc_copyClassList(&count);
    if(!classes){Log(@"CLASSDUMP scan-failed");return;}
    NSMutableArray<NSString *> *overriders=[NSMutableArray array];
    SEL sel=@selector(supportedInterfaceOrientations);
    for(unsigned i=0;i<count&&overriders.count<40;i++){
        Class c=classes[i];
        if(c==UIViewController.class||!ValidClass(c,UIViewController.class))continue;
        unsigned mcount=0;
        Method *methods=class_copyMethodList(c,&mcount);
        BOOL defines=NO;
        for(unsigned j=0;j<mcount;j++)if(method_getName(methods[j])==sel){defines=YES;break;}
        free(methods);
        if(defines)[overriders addObject:NSStringFromClass(c)];
    }
    free(classes);
    Log([NSString stringWithFormat:@"CLASSDUMP overriders=%lu classes=%@",
        (unsigned long)overriders.count,overriders.count?[overriders componentsJoinedByString:@","]:@"none"]);
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
    BundleID=NSBundle.mainBundle.bundleIdentifier?:@"(unknown bundle)";
    // Never run inside SpringBoard: that process's own upside-down handling
    // is MangoUpsideDownWorld's job end to end, and two independently
    // written pieces of code both adjusting orientation logic in the same
    // process is exactly the kind of conflict this project's own
    // Conflicts: field (between MangoUpsideDownWorld and the older
    // MangoUpsideDownFix) already guards against elsewhere.
    if([BundleID isEqualToString:@"com.apple.springboard"])return;
    Tracing=access(TracePath,F_OK)==0;
    if(Tracing)LogOverridingClasses();
    Class vc=UIViewController.class;
    SEL sel=@selector(supportedInterfaceOrientations);
    if(!Signature(vc,sel,@encode(UIInterfaceOrientationMask),@[])){
        InvertOrientations=NO;Log(@"NO HOOK: signature mismatch");return;}
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
    Log(@"INSTALLED 1.1.0");
}
__attribute__((constructor)) static void StartCamera(void){@autoreleasepool{Install();}}
