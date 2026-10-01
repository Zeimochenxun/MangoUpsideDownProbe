"""Execute the actual Beta8 Idle helpers against fading and geometry cases.

macOS: python3 modules/visual/tests/test_idle_handoff.py --require-clang
The fixture uses property stubs, not UIKit or Core Animation.
"""
import argparse
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "MangoIdleIsland/Tweak.m").read_text(encoding="utf-8")

def extract(name):
    match = re.search(r"^static [^\n]+\b" + re.escape(name) + r"\([^\n]*\) \{", SOURCE, re.M)
    assert match, name
    depth, end = 1, match.end()
    while depth:
        if SOURCE[end] == "{": depth += 1
        elif SOURCE[end] == "}": depth -= 1
        end += 1
    return SOURCE[match.start():end]

def main(require_clang):
    clang = shutil.which("clang")
    if sys.platform != "darwin" or not clang:
        if require_clang: raise SystemExit("macOS clang is required to execute actual Objective-C helpers")
        print("SKIP: Objective-C helper execution requires macOS clang")
        return
    helpers = "\n\n".join(extract(n) for n in ["EffectiveOpacity", "StableIdleGeometry", "StableIdleHostGeometry"])
    update = extract("Update")
    need = re.search(r"BOOL needBackground = ([^;]+);", update).group(1)
    backing = re.search(r"CGFloat backingOpacity = backgroundState \? 1\.0 : ([^;]+);", update).group(1)
    policy = "\n".join([
        "static CGFloat Backing(UIView *host, CGFloat activity) {",
        "    BOOL stableGeometry = StableIdleHostGeometry(host);",
        "    BOOL activityState = activity > 0.01;",
        "    BOOL backgroundState = !activityState && stableGeometry;",
        "    BOOL blendableActivity = activityState && stableGeometry;",
        "    BOOL needBackground = " + need + ";",
        "    CGFloat backingOpacity = backgroundState ? 1.0 : " + backing + ";",
        "    return needBackground ? backingOpacity : 0.0;", "}",
    ])
    template = (ROOT / "tests/idle_handoff_harness.m").read_text(encoding="utf-8").replace("/* ACTUAL_POLICY_EXPRESSIONS */", policy)
    assert template.count("/* ACTUAL_HELPERS */") == 1
    # Negative controls ensure the cases detect model/presentation regressions.
    wrong_opacity = helpers.replace("opacity *= layer.opacity;", "opacity *= MIN(p.alpha, layer.opacity);")
    wrong_geometry = helpers.replace("return StableIdleGeometry(visible);", "return StableIdleGeometry(model);")
    assert wrong_opacity != helpers and wrong_geometry != helpers
    # Avoid an unused-variable warning in the deliberate geometry mutation.
    wrong_geometry = wrong_geometry.replace("CGSize visible = presentation.bounds.size;", "")
    with tempfile.TemporaryDirectory(prefix="beta8-idle-") as temp:
        for label, bodies, success in [("candidate", helpers, True), ("double-fade", wrong_opacity, False), ("model-only", wrong_geometry, False)]:
            source, binary = Path(temp) / (label + ".m"), Path(temp) / label
            source.write_text(template.replace("/* ACTUAL_HELPERS */", bodies), encoding="utf-8")
            subprocess.run([clang, "-x", "objective-c", "-std=gnu11", "-Wall", "-Wextra", "-Werror", str(source), "-framework", "Foundation", "-framework", "CoreGraphics", "-o", str(binary)], check=True)
            result = subprocess.run([str(binary)], capture_output=True, text=True)
            assert result.returncode == (0 if success else 1), (label, result.stdout, result.stderr)
            print("PASS:", label, "actual helper behavior" if success else "negative control detected")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-clang", action="store_true")
    main(parser.parse_args().require_clang)
