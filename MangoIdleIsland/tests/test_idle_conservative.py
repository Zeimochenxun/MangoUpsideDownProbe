#!/usr/bin/env python3
"""Source-derived regressions; on macOS also run actual helpers in ObjC stubs.

Run: python3 tests/test_idle_conservative.py [--require-clang]
These checks do not simulate Core Animation timing or certify device behavior.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass, field
import hashlib
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "Tweak.m").read_text(encoding="utf-8")
BASELINE_HELPERS = (ROOT / "tests" / "fixtures" / "idle119_helpers.m").read_text(encoding="utf-8")
BASELINE_NORMALIZED_SHA256 = "213948934e9b6b505b43ed1010d52723c27890716384d04f3e8f964794763402"


def extract_function(name: str, source: str = SOURCE) -> str:
    match = re.search(r"^static [^\n]+\b" + re.escape(name) + r"\([^\n]*\) \{", source, re.M)
    if not match:
        raise AssertionError(f"Missing actual helper: {name}")
    start = match.start()
    depth = 1
    end = match.end()
    while depth:
        if source[end] == "{":
            depth += 1
        elif source[end] == "}":
            depth -= 1
        end += 1
    return source[start:end]


def body(name: str, source: str = SOURCE) -> str:
    source = extract_function(name, source)
    source = source[source.index("{") + 1:-1]
    return re.sub(r"//[^\n]*|/\*.*?\*/", "", source, flags=re.S).strip()


def expression(source: str, **values):
    source = source.replace("&&", " and ").replace("||", " or ")
    source = re.sub(r"!(?!=)", " not ", source)
    source = re.sub(r"\bYES\b", "True", source)
    source = re.sub(r"\bNO\b", "False", source)
    names = {"MAX": max, "MIN": min, "fabs": abs, "isfinite": math.isfinite,
             "StableIdleGeometry": stable_size, **values}
    return eval("(" + source.strip() + ")", {"__builtins__": {}}, names)


@dataclass(eq=False)
class Size:
    width: float = 125.0
    height: float = 36.67


@dataclass(eq=False)
class Bounds:
    size: Size = field(default_factory=Size)


@dataclass(eq=False)
class Layer:
    opacity: float = 1.0
    hidden: bool = False
    presentationLayer: Layer | None = None
    bounds: Bounds = field(default_factory=Bounds)
    # Deliberately differ these in tests: local bounds guards must ignore them.
    transform: float = 1.0
    position: tuple = (0.0, 0.0)


@dataclass(eq=False)
class View:
    alpha: float = 1.0
    hidden: bool = False
    layer: Layer = field(default_factory=Layer)
    superview: View | None = None
    bounds: Bounds = field(default_factory=Bounds)


def make_view(model=1.0, presented=None, parent=None, size=None, presentation_size=None):
    size = size or Size()
    layer = Layer(opacity=model, bounds=Bounds(size))
    if presented is not None or presentation_size is not None:
        layer.presentationLayer = Layer(opacity=model if presented is None else presented,
                                        bounds=Bounds(presentation_size or size))
    return View(alpha=model, layer=layer, superview=parent, bounds=Bounds(size))


# Extract the loop, its guards, the chosen layer, and numerical expressions from
# actual source. A full-match shape check rejects unhandled Objective-C changes
# rather than silently evaluating a stale hand-written implementation.
OPACITY_SHAPE = re.compile(
    r"CGFloat opacity = (?P<initial>[^;]+);\s*"
    r"for \(UIView \*p = v; (?P<condition>[^;]+); p = p\.superview\) \{\s*"
    r"if \((?P<hidden>[^\n]+)\) return 0;\s*"
    r"CALayer \*layer = (?P<layer>[^;]+);\s*"
    r"opacity \*= (?P<factor>[^;]+);\s*\}\s*"
    r"return (?P<result>[^;]+);", re.S)
OPACITY_PARTS = OPACITY_SHAPE.fullmatch(body("EffectiveOpacity"))
assert OPACITY_PARTS, "EffectiveOpacity source shape changed: update the runner explicitly"


def effective_opacity(v, host, parts=OPACITY_PARTS):
    opacity = expression(parts["initial"])
    p = v
    while expression(parts["condition"], p=p, host=host):
        if expression(parts["hidden"], p=p):
            return 0.0
        options = parts["layer"].split("?:")
        assert len(options) == 2
        layer = expression(options[0], p=p) or expression(options[1], p=p)
        opacity *= expression(parts["factor"], p=p, layer=layer)
        p = p.superview
    return expression(parts["result"], opacity=opacity)


SIZE_SHAPE = re.compile(r"return (?P<result>.+);", re.S)
SIZE_PARTS = SIZE_SHAPE.fullmatch(body("StableIdleGeometry"))
assert SIZE_PARTS, "StableIdleGeometry source shape changed"


def stable_size(size):
    return expression(SIZE_PARTS["result"], size=size)


HOST_SHAPE = re.compile(
    r"CGSize model = (?P<model>[^;]+);\s*"
    r"if \((?P<exclude>[^\n]+)\) return NO;\s*"
    r"CALayer \*presentation = (?P<presentation>[^;]+);\s*"
    r"if \((?P<absent>[^\n]+)\) return YES;\s*"
    r"CGSize visible = (?P<visible>[^;]+);\s*"
    r"return (?P<result>.+);", re.S)
HOST_PARTS = HOST_SHAPE.fullmatch(body("StableIdleHostGeometry"))
assert HOST_PARTS, "StableIdleHostGeometry source shape changed"


def stable_host(host):
    model = expression(HOST_PARTS["model"], host=host)
    if expression(HOST_PARTS["exclude"], model=model):
        return False
    presentation = expression(HOST_PARTS["presentation"], host=host)
    if expression(HOST_PARTS["absent"], presentation=presentation):
        return True
    visible = expression(HOST_PARTS["visible"], presentation=presentation)
    return expression(HOST_PARTS["result"], model=model, visible=visible)


UPDATE = extract_function("Update")
NEED = re.search(r"BOOL needBackground = ([^;]+);", UPDATE).group(1)
BACKING = re.search(r"CGFloat backingOpacity = backgroundState \? 1\.0 : ([^;]+);", UPDATE).group(1)


def backing_policy(host, element=0.0, glass=0.0):
    activity = max(element, glass)  # Existing fallback intentionally retained.
    activity_state = activity > 0.01
    stable = stable_host(host)
    background = not activity_state and stable
    need = expression(NEED, backgroundState=background,
                      blendableActivity=activity_state and stable, activity=activity)
    alpha = 1.0 if background else expression(BACKING, activity=activity)
    return bool(need), alpha if need else 0.0


class HandoffTests(unittest.TestCase):
    def test_presentation_fades_and_model_fallback(self):
        host = make_view()
        cases = [
            (0.0, 1.0, 1.0), (0.0, 0.75, 0.75), (0.0, 0.25, 0.25),
            (0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (1.0, 0.25, 0.25),
            (1.0, 1.0, 1.0), (0.4, None, 0.4),
        ]
        for model, presented, expected in cases:
            with self.subTest(model=model, presentation=presented):
                self.assertAlmostEqual(effective_opacity(make_view(model, presented, host), host), expected)

    def test_ancestor_opacity_hidden_and_host_exclusion(self):
        host = make_view(model=0.1, presented=0.1)
        ancestor = make_view(model=0.0, presented=0.7, parent=host)
        child = make_view(model=0.0, presented=0.6, parent=ancestor)
        self.assertAlmostEqual(effective_opacity(child, host), 0.42)
        for target, field_name in [(child, "hidden"), (child.layer, "hidden"),
                                   (ancestor, "hidden"), (ancestor.layer, "hidden")]:
            with self.subTest(hidden=field_name, target=type(target).__name__):
                setattr(target, field_name, True)
                self.assertEqual(effective_opacity(child, host), 0.0)
                setattr(target, field_name, False)
        self.assertEqual(effective_opacity(host, host), 1.0)

    def test_geometry_return_and_both_dimensions(self):
        for width, height, expected in [
            (150.0, 44.0, False), (143.0, 40.0, False), (125.6, 36.67, False),
            (125.4, 36.67, True), (125.0, 37.27, False), (125.0, 37.07, True),
            (125.0, 36.67, True), (float("nan"), 36.67, False),
            (125.0, float("inf"), False), (109.0, 36.67, False),
        ]:
            with self.subTest(width=width, height=height):
                host = make_view(presentation_size=Size(width, height))
                self.assertEqual(bool(stable_host(host)), expected)
        self.assertTrue(stable_host(make_view()))  # No presentation: original behavior.
        self.assertFalse(stable_host(make_view(size=Size(150, 44), presentation_size=Size())))
        self.assertFalse(stable_host(make_view(size=Size(float("inf"), 36.67))))

    def test_press_transform_and_position_do_not_suppress_idle(self):
        host = make_view(presentation_size=Size())
        host.layer.transform = 1.0
        host.layer.presentationLayer.transform = 1.08
        host.layer.position = (80, 20)
        host.layer.presentationLayer.position = (82, 19)
        self.assertTrue(stable_host(host))
        self.assertEqual(backing_policy(host), (True, 1.0))

    def test_inverse_backing_and_existing_content_fallback(self):
        host = make_view()
        native = make_view(model=0.0, presented=1.0, parent=host)
        self.assertEqual(backing_policy(host, glass=effective_opacity(native, host)), (False, 0.0))
        for opacity in [0.75, 0.25]:
            native.layer.presentationLayer.opacity = opacity
            need, alpha = backing_policy(host, glass=effective_opacity(native, host))
            self.assertTrue(need)
            self.assertAlmostEqual(alpha, 1.0 - opacity)
        returning = make_view(presentation_size=Size(150, 44))
        self.assertEqual(backing_policy(returning), (False, 0.0))
        self.assertEqual(backing_policy(returning, glass=0.25), (False, 0.0))
        # This unresolved behavior is deliberately unchanged in the alpha.
        self.assertEqual(backing_policy(host, element=1.0, glass=0.0), (False, 0.0))

    def test_regressions_reject_previous_decisions(self):
        previous = body("EffectiveOpacity", BASELINE_HELPERS)
        old_parts = OPACITY_SHAPE.fullmatch(previous)
        self.assertIsNotNone(old_parts)
        host = make_view()
        native = make_view(model=0, presented=1, parent=host)
        self.assertEqual(effective_opacity(native, host, parts=old_parts), 0)
        self.assertEqual(effective_opacity(native, host), 1)
        returning = make_view(presentation_size=Size(150, 44))
        baseline_size = SIZE_SHAPE.fullmatch(body("StableIdleGeometry", BASELINE_HELPERS))
        self.assertIsNotNone(baseline_size)
        self.assertTrue(expression(baseline_size["result"], size=returning.bounds.size))
        self.assertFalse(stable_host(returning))
        print("PASS: negative controls using actual 1.1.9 helpers fail fade-out and return-geometry expectations; candidate passes.")

    def test_patch_scope_and_both_call_sites(self):
        self.assertIn("BOOL stableIdleGeometry = StableIdleHostGeometry(host);", extract_function("Eligibility"))
        self.assertIn("BOOL stableGeometry = StableIdleHostGeometry(host);", UPDATE)
        self.assertIn("*activity = MAX(glassOpacity, elementOpacity);", extract_function("Eligibility"))
        # Undo exactly the authorized edits and compare all other source to
        # the normalized 1.1.9 baseline. This includes hooks, timer, and reloads.
        restored = SOURCE.replace(extract_function("StableIdleHostGeometry") + "\n\n", "", 1)
        restored = restored.replace(
            "        // During a fade, the presentation layer is the currently visible\n"
            "        // value. The model alpha is already the destination of the animation.\n"
            "        opacity *= layer.opacity;",
            "        opacity *= MIN(p.alpha, layer.opacity);", 1)
        restored = restored.replace("BOOL stableIdleGeometry = StableIdleHostGeometry(host);",
                                    "BOOL stableIdleGeometry = StableIdleGeometry(size);", 1)
        restored = restored.replace("BOOL stableGeometry = StableIdleHostGeometry(host);",
                                    "BOOL stableGeometry = StableIdleGeometry(host.bounds.size);", 1)
        restored = restored.replace("version=1.1.9.1~alpha1-stable-idle-handoff", "version=1.1.9-stable-idle-handoff", 1)
        restored = restored.replace(" presentation-opacity=1 presentation-bounds-guard=1", "", 1)
        self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), BASELINE_NORMALIZED_SHA256)
        for name in ["EffectiveOpacity", "StableIdleGeometry"]:
            self.assertEqual(extract_function(name, BASELINE_HELPERS), extract_function(name, restored))
        control = (ROOT / "control").read_text(encoding="utf-8")
        self.assertIn("Version: 1.1.9.1~alpha1", control.splitlines())


def run_objc_stub(require_clang=False):
    clang = shutil.which("clang")
    if sys.platform != "darwin" or not clang:
        if require_clang:
            raise SystemExit("FAIL: --require-clang requires macOS + clang; no native Objective-C checks ran")
        print("SKIP: actual Objective-C stub execution requires macOS + clang; source-derived checks ran locally.")
        return
    helpers = "\n\n".join(extract_function(n) for n in ["EffectiveOpacity", "StableIdleGeometry", "StableIdleHostGeometry"])
    old_helpers = "\n\n".join(extract_function(n, BASELINE_HELPERS) for n in ["EffectiveOpacity", "StableIdleGeometry"])
    # The old implementation called the size predicate directly in Eligibility
    # and Update. This adapter preserves that behavior for the common harness.
    old_helpers += "\nstatic BOOL StableIdleHostGeometry(UIView *host) { return StableIdleGeometry(host.bounds.size); }\n"
    template = (ROOT / "tests" / "idle_handoff_harness.m").read_text(encoding="utf-8")
    assert template.count("/* ACTUAL_HELPERS */") == 1
    with tempfile.TemporaryDirectory(prefix="idle-handoff-") as directory:
        for label, bodies, expected_success in [("candidate", helpers, True), ("baseline", old_helpers, False)]:
            harness = Path(directory) / (label + ".m")
            executable = Path(directory) / label
            harness.write_text(template.replace("/* ACTUAL_HELPERS */", bodies), encoding="utf-8")
            subprocess.run([clang, "-x", "objective-c", "-std=gnu11", "-Wall", "-Wextra", "-Werror",
                            str(harness), "-framework", "Foundation", "-framework", "CoreGraphics",
                            "-o", str(executable)], check=True)
            result = subprocess.run([str(executable)], capture_output=True, text=True)
            diagnostic = f"{label} returncode={result.returncode}\nstdout={result.stdout!r}\nstderr={result.stderr!r}"
            if expected_success:
                assert result.returncode == 0, diagnostic
                print(result.stdout.strip())
            else:
                assert result.returncode == 1, "Baseline did not show the expected assertion failures: " + diagnostic
                print("PASS: compiled baseline helpers failed the same new behavior expectations (expected negative control).")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-clang", action="store_true",
                        help="Fail unless actual helpers are compiled/executed on macOS")
    args = parser.parse_args()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(HandoffTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        sys.exit(1)
    run_objc_stub(args.require_clang)

