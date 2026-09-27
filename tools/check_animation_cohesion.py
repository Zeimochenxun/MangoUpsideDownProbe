#!/usr/bin/env python3
"""Static regression checks for the Island handoff and adaptive color curves."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def smoothstep(low: float, high: float, value: float) -> float:
    t = max(0.0, min(1.0, (value - low) / (high - low)))
    return t * t * (3.0 - 2.0 * t)


def adaptive_output(luminance: float, slider: float, adaptation: float) -> float:
    bright = smoothstep(0.10, 0.85, luminance)
    adaptive_target = 0.18 + (0.025 - 0.18) * bright
    target = 0.10 + (adaptive_target - 0.10) * adaptation
    strength = 0.42 * smoothstep(0.0, 1.0, slider)
    return luminance * (1.0 - strength) + target * strength


def idle_opacity(activity: float) -> float:
    return 1.0 - smoothstep(0.55, 0.98, activity)


def assert_monotonic(values: list[float], direction: str) -> None:
    pairs = zip(values, values[1:])
    if direction == "up":
        assert all(right + 1e-12 >= left for left, right in pairs)
    else:
        assert all(right <= left + 1e-12 for left, right in pairs)


samples = [index / 1000.0 for index in range(1001)]
handoff = [idle_opacity(value) for value in samples]

for adaptation in (0.0, 0.25, 0.5, 0.75, 1.0):
    for slider in (0.0, 0.25, 0.5, 0.75, 1.0):
        colors = [adaptive_output(value, slider, adaptation) for value in samples]
        assert_monotonic(colors, "up")
        assert max(abs(b - a) for a, b in zip(colors, colors[1:])) < 0.002

assert adaptive_output(0.0, 0.0, 1.0) == 0.0
assert adaptive_output(1.0, 0.0, 1.0) == 1.0
assert 0.075 < adaptive_output(0.0, 1.0, 1.0) < 0.076
assert 0.590 < adaptive_output(1.0, 1.0, 1.0) < 0.591
assert adaptive_output(0.5, 0.25, 1.0) != adaptive_output(0.5, 0.75, 1.0)
assert adaptive_output(0.0, 1.0, 0.0) != adaptive_output(0.0, 1.0, 1.0)
assert_monotonic(handoff, "down")
assert handoff[0] == 1.0 and handoff[-1] == 0.0
assert max(abs(b - a) for a, b in zip(handoff, handoff[1:])) < 0.004

idle_source = (ROOT / "MangoIdleIsland" / "Tweak.m").read_text(encoding="utf-8")
color_source = (ROOT / "MangoIslandAdaptiveColor" / "Tweak.m").read_text(encoding="utf-8")
idle_filter = (ROOT / "MangoIdleIsland" / "MangoIdleIsland.plist").read_text(encoding="utf-8")
color_filter = (ROOT / "MangoIslandAdaptiveColor" / "MangoIslandAdaptiveColor.plist").read_text(encoding="utf-8")
assert "presentation ? presentation.opacity : p.alpha" in idle_source
assert "SmoothStep(0.55, 0.98, activity)" in idle_source
assert "if (eligible && (!bg || upgrading))" in idle_source
assert "preferredFramesPerSecond = 60" in idle_source
assert "AlphaSuffix(original, LightKey)" in color_source
assert "AlphaSuffix(original, DarkKey)" in color_source
assert "smoothstep(0.10, 0.85, luminance)" in color_source
assert "float strength = 0.42 * userStrength" in color_source
assert "float target = mix(0.10, adaptiveTarget, adaptation)" in color_source
assert "<key>Executables</key>" in idle_filter and "SpringBoard" in idle_filter
assert "Executables" in color_filter and "backboardd" in color_filter

print("PASS: user tint strength is preserved; adaptive luma and Island handoff are monotonic")
