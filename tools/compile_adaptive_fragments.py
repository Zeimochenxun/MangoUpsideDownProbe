#!/usr/bin/env python3
"""Compile the plugin's own Metal snippets against a small interface harness.

No MangoOS binary or original shader is required or distributed. The harness
checks the actual replacement snippets and the signatures used at insertion
sites; this is a compile check, not an iOS rendering test.
"""
import argparse
from pathlib import Path
import subprocess

PRELUDE = '''#include <metal_stdlib>
using namespace metal;
struct Uniforms { float dispersionStrength; float4 tintColor;
                 float refractiveIndex; float fresnelGlareStrength; };
// Interface stubs: only their signatures are relevant to this compile check.
float2 backdropSampleUV(float2 capturePx, float2 logicalPx,
                       float2 displacementPx, bool isCoverSheet,
                       constant Uniforms &u) { return capturePx * 0.001; }
float fresnelAtRatio(float bezelRatio, float refractiveIndex) {
    return clamp(bezelRatio, 0.0, 1.0);
}
'''

def make_harness(fragments):
    read = lambda name: (fragments / (name + '.metal')).read_text(encoding='utf-8')
    helper = read('helper')
    dispersion = read('dispersion')
    curved = read('curved')
    flat = read('flat')
    glare = read('glare')
    return PRELUDE + helper + '''
kernel void checkAdaptive(texture2d<float, access::sample> src [[texture(0)]],
                          texture2d<float, access::write> dst [[texture(1)]],
                          constant Uniforms &u [[buffer(0)]],
                          uint2 tid [[thread_position_in_grid]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 capturePx=float2(tid), px=float2(tid), captureUV=capturePx*0.001;
    float2 dispPx=float2(0.2);
    bool isCoverSheet=false;
    float4 bg=src.sample(s,captureUV);
    float bezelRatio=0.2, edgeOpacity=0.8;
''' + dispersion + '\n' + curved + '\nfloat glare=0.1;\n' + glare + '''
    float3 curvedRGB=outRGB;
    {
        float4 flat=bg;
''' + flat + '''
        dst.write(float4((flat.rgb+curvedRGB)*0.5,1.0),tid);
    }
}
'''

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--fragments', type=Path, default=Path('AdaptiveColorPatch'))
    parser.add_argument('--out-dir', type=Path, default=Path('build-info/adaptive'))
    parser.add_argument('--generate-only', action='store_true')
    args=parser.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    source=args.out_dir / 'AdaptiveColor-fragment-harness.metal'
    source.write_text(make_harness(args.fragments), encoding='utf-8')
    if not args.generate_only:
        subprocess.run(['xcrun','--sdk','iphoneos','metal','-std=ios-metal2.4',
                        '-Werror','-c',str(source),'-o',str(args.out_dir/'AdaptiveColor.air')],check=True)
        subprocess.run(['xcrun','--sdk','iphoneos','metallib',str(args.out_dir/'AdaptiveColor.air'),
                        '-o',str(args.out_dir/'AdaptiveColor.metallib')],check=True)
        print('PASS: actual plugin fragments compile and link; device rendering remains untested')
    else:
        print(source)

if __name__ == '__main__':
    main()
