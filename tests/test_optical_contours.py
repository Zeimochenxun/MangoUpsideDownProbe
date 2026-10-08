"""Execute the production contour with real macOS CoreGraphics/QuartzCore.

UIBezierPath is a small CGPath adapter; this is not a phone rendering test.
"""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "modules/visual/MangoIdleIsland/IslandRepairs.m").read_text(encoding="utf-8")

def extract(name):
    match = re.search(r"^static [^\n]+\b" + name + r"\([^\n]*\) \{", SOURCE, re.M)
    assert match, name
    depth, end = 1, match.end()
    while depth:
        if SOURCE[end] == "{": depth += 1
        elif SOURCE[end] == "}": depth -= 1
        end += 1
    return SOURCE[match.start():end]

ADAPTER = r'''
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#include <assert.h>
#include <math.h>
#include <stdio.h>
@interface UIBezierPath : NSObject <NSCopying> { CGPathRef _path; }
@property(nonatomic,readonly) CGPathRef CGPath;
@property(nonatomic,readonly) CGRect bounds;
+ (instancetype)bezierPathWithCGPath:(CGPathRef)path;
+ (instancetype)bezierPathWithRoundedRect:(CGRect)rect cornerRadius:(CGFloat)radius;
- (void)applyTransform:(CGAffineTransform)t;
@end
@implementation UIBezierPath
+ (instancetype)bezierPathWithCGPath:(CGPathRef)path { UIBezierPath *p=[self new];p->_path=CGPathCreateCopy(path);return p; }
+ (instancetype)bezierPathWithRoundedRect:(CGRect)rect cornerRadius:(CGFloat)radius {
    CGPathRef path=CGPathCreateWithRoundedRect(rect,radius,radius,NULL);
    UIBezierPath *p=[self bezierPathWithCGPath:path];CGPathRelease(path);return p;
}
- (CGPathRef)CGPath { return _path; }
- (CGRect)bounds { return CGPathGetBoundingBox(_path); }
- (id)copyWithZone:(NSZone *)zone { (void)zone;return [UIBezierPath bezierPathWithCGPath:_path]; }
- (void)applyTransform:(CGAffineTransform)t { CGPathRef p=CGPathCreateCopyByTransformingPath(_path,&t);CGPathRelease(_path);_path=p; }
- (void)dealloc { CGPathRelease(_path); }
@end
'''

CASES = r'''
static BOOL NearRect(CGRect a,CGRect b) { return fabs(a.origin.x-b.origin.x)<1e-6 && fabs(a.origin.y-b.origin.y)<1e-6 && fabs(a.size.width-b.size.width)<1e-6 && fabs(a.size.height-b.size.height)<1e-6; }
int main(void) { @autoreleasepool {
    CALayer *glass=[CALayer layer];
    for (unsigned height=2;height<=120;height++) for (unsigned width=125;width<=301;width+=44) {
        glass.bounds=CGRectMake(0,0,width,height);glass.cornerRadius=0;glass.mask=nil;
        BOOL native=NO;
        double stroke=fmin(4,height*.4);
        UIBezierPath *path=Contour(glass,glass.mask,stroke,&native);
        CGRect expected=CGRectInset(glass.bounds,stroke*.5,stroke*.5);
        assert(!native && NearRect(path.bounds,expected));
        assert(CGPathContainsPoint(path.CGPath,NULL,CGPointMake(width*.5,height*.5),NO));
    }
    glass.bounds=CGRectMake(0,0,301,91.5);
    CAShapeLayer *mask=[CAShapeLayer layer];mask.frame=glass.bounds;
    CGPathRef original=CGPathCreateWithRoundedRect(glass.bounds,28,28,NULL);
    mask.path=original;glass.mask=mask;
    BOOL native=NO;
    UIBezierPath *path=Contour(glass,glass.mask,4,&native);
    assert(native && CGPathEqualToPath(path.CGPath,original));
    for (unsigned i=0;i<4;i++) {
        CGPoint corner=CGPointMake(i&1 ? 300 : 1,i&2 ? 90.5 : 1);
        assert(!CGPathContainsPoint(path.CGPath,NULL,corner,NO));
    }
    // A compact mask lingering during an expanded layout is rejected.
    CGPathRef stale=CGPathCreateWithRoundedRect(CGRectMake(0,0,125,36.67),18,18,NULL);
    mask.path=stale;native=NO;
    path=Contour(glass,glass.mask,4,&native);
    assert(!native && NearRect(path.bounds,CGRectInset(glass.bounds,2,2)));
    // The native mask wins over a different layer radius, including a translated
    // mask: all four corners keep the exact native path and its local placement.
    glass.bounds=CGRectMake(10,20,301,91.5); mask.frame=glass.bounds;
    glass.cornerRadius=45;mask.path=original;
    native=NO; path=Contour(glass,glass.mask,1.2,&native);
    CGAffineTransform offset=CGAffineTransformMakeTranslation(10,20);
    CGPathRef moved=CGPathCreateCopyByTransformingPath(original,&offset);
    assert(native && CGPathEqualToPath(path.CGPath,moved));
    // Negative control: rebuilding a round rect AFTER nonuniform projection
    // changes its corners. Transforming a local contour inherits the same spring
    // scale as the glass and must match the transformed native path exactly.
    CGAffineTransform spring=CGAffineTransformMakeScale(1.4,.6);
    CGPathRef inherited=CGPathCreateCopyByTransformingPath(path.CGPath,&spring);
    CGPathRef projected=CGPathCreateWithRoundedRect(CGRectApplyAffineTransform(path.bounds,spring),28*.6,28*.6,NULL);
    assert(!CGPathEqualToPath(inherited,projected));
    [path applyTransform:spring];assert(CGPathEqualToPath(path.CGPath,inherited));
    CGPathRelease(original);CGPathRelease(stale);CGPathRelease(moved);CGPathRelease(inherited);CGPathRelease(projected);
    puts("PASS: production contour preserves native mask and four corners, rejects stale geometry, supports short heights and local offsets; projected-round-rect negative control detects nonuniform spring distortion");
} return 0; }
'''

with tempfile.TemporaryDirectory(prefix="mango-optical-contours-") as directory:
    source, binary = Path(directory)/"contours.m", Path(directory)/"contours"
    source.write_text(ADAPTER + extract("FiniteMap") + extract("Contour") + CASES, encoding="utf-8")
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror", "-framework", "Foundation",
                    "-framework", "CoreGraphics", "-framework", "QuartzCore", str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
