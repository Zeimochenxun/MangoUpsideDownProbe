#!/usr/bin/env python3
from pathlib import Path

path = Path("Tweak.m")
source = path.read_text(encoding="utf-8")
original = source


def replace_exact(old: str, new: str, expected: int = 1) -> None:
    global source
    count = source.count(old)
    if count != expected:
        raise SystemExit(f"idle autoresize patch mismatch: expected {expected}, found {count}: {old[:120]!r}")
    source = source.replace(old, new)

# The Idle glass is manually framed by Update(). It must not also participate in
# parent-driven UIView autoresizing, otherwise host long-press expansion can
# resize it before our next Update() clamps it back.
replace_exact(
    "    view.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;",
    "    view.autoresizingMask = UIViewAutoresizingNone;"
)

# Add a diagnostic whenever the size guard toggles so device logs tell us whether
# the visible presentation layer still diverges from the manually pinned UIView.
old_log = '''                    Log([NSString stringWithFormat:@"[IDLE-GEOMETRY] guard=%d host=%.2fx%.2f idle=%.2fx%.2f",
                         geometryGuard, host.bounds.size.width, host.bounds.size.height,
                         stable.size.width, stable.size.height]);'''
new_log = '''                    CALayer *presentation = bg.layer.presentationLayer;
                    CGRect modelFrame = bg.frame;
                    CGRect presentationFrame = presentation ? presentation.frame : CGRectZero;
                    Log([NSString stringWithFormat:@"[IDLE-GEOMETRY] guard=%d host=%.2fx%.2f idle=%.2fx%.2f",
                         geometryGuard, host.bounds.size.width, host.bounds.size.height,
                         stable.size.width, stable.size.height]);
                    Log([NSString stringWithFormat:@"[IDLE-LAYER] autoresize=0 model=%.2f,%.2f %.2fx%.2f presentation=%.2f,%.2f %.2fx%.2f",
                         modelFrame.origin.x, modelFrame.origin.y, modelFrame.size.width, modelFrame.size.height,
                         presentationFrame.origin.x, presentationFrame.origin.y,
                         presentationFrame.size.width, presentationFrame.size.height]);'''
replace_exact(old_log, new_log)

replace_exact(
    '[SESSION] version=1.1.7-preview-handoff background=Mango-glass duplicate-preview-suppression=1 idle-size-guard=1 implicit-animation=off activity-detaches-idle touch=unchanged',
    '[SESSION] version=1.1.8-no-autoresize background=Mango-glass duplicate-preview-suppression=1 idle-size-guard=1 view-autoresize=off implicit-animation=off activity-detaches-idle touch=unchanged'
)

if source == original:
    raise SystemExit("idle autoresize patch made no changes")

path.write_text(source, encoding="utf-8")
print("Applied MangoIdleIsland 1.1.8 no-autoresize fix")
