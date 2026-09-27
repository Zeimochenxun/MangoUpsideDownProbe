#!/usr/bin/env python3
"""Static regression checks for the Island handoff and adaptive color curves."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def smoothstep(low: float, high: float, value: float) -> float:
    t = max(0.0, min(1.0, (value - low) / (high - low)))
    return t * t * (3.0 - 2.0 * t)


def adaptive_output(luminance: float) -> float:
    bright = smoothstep(0.06, 0.72, luminance)
    neutral = 0.14 + (0.42 - 0.14) * bright
    return neutral * 0.38 + luminance * 0.62


def idle_opacity(activity: float) -> float:
    return 1.0 - smoothstep(0.55, 0.98, activity)


def assert_monotonic(values: list[float], direction: str) -> None:
    pairs = zip(values, values[1:])
    if direction == "up":
        assert all(right + 1e-12 >= left for left, right in pairs)
    else:
        assert all(right <= left + 1e-12 for left, right in pairs)


samples = [index / 1000.0 for index in range(1001)]
colors = [adaptive_output(value) for value in samples]
handoff = [idle_opacity(value) for value in samples]

assert_monotonic(colors, "up")
assert_monotonic(handoff, "down")
assert 0.05 < colors[0] < 0.06
assert 0.77 < colors[-1] < 0.79
assert handoff[0] == 1.0 and handoff[-1] == 0.0
assert max(abs(b - a) for a, b in zip(colors, colors[1:])) < 0.002
assert max(abs(b - a) for a, b in zip(handoff, handoff[1:])) < 0.004

idle_source = (ROOT / "MangoIdleIsland" / "Tweak.m").read_text(encoding="utf-8")
color_source = (ROOT / "MangoIslandAdaptiveColor" / "Tweak.m").read_text(encoding="utf-8")
assert "presentation ? presentation.opacity : p.alpha" in idle_source
assert "SmoothStep(0.55, 0.98, activity)" in idle_source
assert "if (eligible && (!bg || upgrading))" in idle_source
assert "preferredFramesPerSecond = 60" in idle_source
assert "smoothstep(0.06, 0.72, luminance)" in color_source
assert "return mix(float3(neutral), background, 0.62)" in color_source

print("PASS: adaptive luma is monotonic; Idle/Active handoff is continuous and monotonic")

