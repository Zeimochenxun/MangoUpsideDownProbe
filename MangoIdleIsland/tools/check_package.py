#!/usr/bin/env python3
import io, pathlib, plistlib, struct, subprocess, sys, tarfile

package = sys.argv[1]

with tarfile.open(fileobj=io.BytesIO(subprocess.check_output(['dpkg-deb', '--fsys-tarfile', package]))) as t:
    members = t.getmembers()
    regular = [m for m in members if m.isfile()]
    assert len(regular) >= 4, [m.name for m in regular]
    assert not any(m.issym() or m.islnk() for m in members)
    assert all('MangoIdleIsland' in m.name for m in regular), [m.name for m in regular]

    p = next(m for m in regular if m.name.endswith('/MangoIdleIsland.plist'))
    b = next(m for m in regular if m.name.endswith('/MangoIdleIsland.dylib'))
    assert plistlib.loads(t.extractfile(p).read()) == {'Filter': {'Bundles': ['com.apple.springboard']}}

    data = t.extractfile(b).read()
    magic, cpu, subtype, filetype = struct.unpack_from('<4I', data)
    assert magic == 0xfeedfacf and cpu == 0x100000c and (subtype & 0xffffff) == 2 and filetype == 6
    for required in [
        b'MSHookMessageEx',
        b'SBSystemApertureContainerView',
        b'Status.log',
        b'initWithFrame:groupName:filterType:',
        b'go.mangoos.island',
        b'PillGlass.Enabled',
        b'original-island-glass-observed',
        b'Island.SpecularEnabled',
        b'go.mangoos/ParametersReloaded',
        b'mode=fresh-init',
        b'Island.TintStrength',
        b'TintRGBARepair101Done',
    ]:
        assert required in data, required
    for forbidden in [
        b'MSHookFunction',
        b'locationInView:',
        b'translationInView:',
        b'reapplyFilterForParameterReload',
    ]:
        assert forbidden not in data, forbidden

    prefs_member = next(m for m in regular if m.name.endswith('/MangoIdleIslandPrefs.bundle/MangoIdleIslandPrefs'))
    prefs_data = t.extractfile(prefs_member).read()
    pmagic, pcpu, psubtype, ptype = struct.unpack_from('<4I', prefs_data)
    assert pmagic == 0xfeedfacf and pcpu == 0x100000c and (psubtype & 0xffffff) == 2 and ptype == 6

    # 1.0.1 tint UI must operate on Mango's final light/dark RGBA values.
    for required in [
        b'MangoIdleIsland.TintAlpha',
        b'Island.LightTintColor',
        b'Island.DarkTintColor',
        b'Island.TintStrength',  # only cleared to remove the 1.0.0 scalar state
    ]:
        assert required in prefs_data, required

    entry = next(m for m in regular if m.name.endswith('/PreferenceLoader/Preferences/MangoIdleIslandPrefs.plist'))
    assert plistlib.loads(t.extractfile(entry).read())['entry']['bundle'] == 'MangoIdleIslandPrefs'

with tarfile.open(fileobj=io.BytesIO(subprocess.check_output(['dpkg-deb', '--ctrl-tarfile', package]))) as t:
    regular = [m for m in t if m.isfile()]
    assert len(regular) == 1 and pathlib.PurePosixPath(regular[0].name).name == 'control'
    control = t.extractfile(regular[0]).read().decode()
    assert 'Version: 1.0.1' in control and 'Architecture: iphoneos-arm64e' in control

print('PASS: 1.0.1 arm64e; fresh-init Mango glass reload; RGBA tint-alpha control; one-time 1.0.0 TintStrength repair; SpringBoard-only tweak')
