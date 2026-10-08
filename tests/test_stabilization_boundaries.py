"""Enforce removal of reported Beta9.4 mutation paths in compiled sources.

This source boundary check cannot prove phone stability or visual correctness.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

def check(world, surface, glass, tweak):
    assert not re.search(r'MSHookMessageEx\s*\(\s*UIPanGestureRecognizer', world)
    assert not any(x in world for x in ('HookTranslation', 'HookVelocity', 'MSB9RunPanQueries', 'MSB8RunPanCorrection'))
    assert 'MSRunObservedPan(' in world
    assert not any(x in surface for x in ('MSHookMessageEx(', 'MSSurfaceReconcile(', 'setTransform:', '.transform=', '.center=', '.frame=', '.bounds='))
    assert not re.search(r'(?:glass|state\.glass)\.layer\.mask\s*=',glass)
    for name in ('NotificationLayout','NotificationSet','LayoutHostSet','PillUpdate'):
        body=re.search(r'static void '+name+r'\([^\n]+\) \{([^}]+)\}',tweak).group(1)
        assert 'QueueNotificationRefresh(self);' in body and ' NotificationRefresh(self);' not in body

world=(ROOT/'modules/orientation/World.m').read_text(encoding='utf-8')
surface=(ROOT/'modules/orientation/LauncherSurfaces.m').read_text(encoding='utf-8')
glass=(ROOT/'modules/visual/MangoIdleIsland/IslandRepairs.m').read_text(encoding='utf-8')
tweak=(ROOT/'modules/visual/MangoIdleIsland/Tweak.m').read_text(encoding='utf-8')
check(world,surface,glass,tweak)
for index,addition in ((0,'MSHookMessageEx(UIPanGestureRecognizer.class,x,y,z);'),
                       (1,'view.transform=CGAffineTransformIdentity;'),
                       (2,'glass.layer.mask=state.clip;')):
    args=[world,surface,glass,tweak];args[index]+='\n'+addition
    try: check(*args)
    except AssertionError: pass
    else: raise AssertionError('Reported mutation path was not rejected')
split=(ROOT/'modules/orientation/Split.m').read_text(encoding='utf-8')
assert 'MSSplitReconcileRecovery(&owned,active,1,RootSnapshot,RootWrite' in split
assert 'MSLauncherSurfacesInstall(' not in split
prefs=(ROOT/'prefs/Prefs.m').read_text(encoding='utf-8')
assert '7 通知上下滑动方向修复（暂停）' in prefs
assert 'if ([key isEqualToString:@"SwipeDirectionEnabled"]) return;' in prefs
print('PASS: compiled-source boundaries exclude global pan rewrite, child surface writes, native glass-mask replacement and synchronous notification refresh; negative controls rejected')
