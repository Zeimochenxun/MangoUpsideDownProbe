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
        b'go.mangoos/ParametersReloaded',
        b'com.go.mangoosprefs/Reload',
        b'Island.SpecularEnabled',
        b'Island.SpecularOpacity',
        b'reapplyFilterForParameterReload',
        b'updateSpecular',
        b'island-glass-count=',
        b'owner=active',
        b'owner=idle',
        b'observed-mango-refresh',
        b'invoked-fallback',
        b'no-safe-runtime-refresh',
        b'mode=global-island-native-reapply+idle-fresh-init',
        b'global-Island-glass-logic=enabled',
        b'TintRGBARepair101Done',
        b'version=1.1.2-probe',
        b'[SPECULAR]',
        b'forced=',
        b'[SPECULAR-PROBE]',
        b'before-updateSpecular',
        b'after-updateSpecular',
        b'_specularBoost',
        b'_specularDark',
    ]:
        assert required in data, required

    for forbidden in [
        b'MSHookFunction',
        b'locationInView:',
        b'translationInView:',
    ]:
        assert forbidden not in data, forbidden

    prefs_member = next(m for m in regular if m.name.endswith('/MangoIdleIslandPrefs.bundle/MangoIdleIslandPrefs'))
    prefs_data = t.extractfile(prefs_member).read()
    pmagic, pcpu, psubtype, ptype = struct.unpack_from('<4I', prefs_data)
    assert pmagic == 0xfeedfacf and pcpu == 0x100000c and (psubtype & 0xffffff) == 2 and ptype == 6

    for required in [
        b'MangoIdleIsland.TintAlpha',
        b'Island.Blur',
        b'Island.LightTintColor',
        b'Island.DarkTintColor',
        b'Island.TintStrength',
        b'Island.SpecularEnabled',
        b'Island.SpecularOpacity',
        b'Island.DispersionEnabled',
        b'Global.DispersionStrength',
        b'com.go.mangoosprefs/Reload',
    ]:
        assert required in prefs_data, required

    entry = next(m for m in regular if m.name.endswith('/PreferenceLoader/Preferences/MangoIdleIslandPrefs.plist'))
    assert plistlib.loads(t.extractfile(entry).read())['entry']['bundle'] == 'MangoIdleIslandPrefs'

with tarfile.open(fileobj=io.BytesIO(subprocess.check_output(['dpkg-deb', '--ctrl-tarfile', package]))) as t:
    regular = [m for m in t if m.isfile()]
    assert len(regular) == 1 and pathlib.PurePosixPath(regular[0].name).name == 'control'
    control = t.extractfile(regular[0]).read().decode()
    assert 'Version: 1.1.2' in control
    assert 'Architecture: iphoneos-arm64e' in control
    assert 'Depends: mobilesubstrate, firmware (= 16.5)' in control

print('PASS: MangoIdleIsland 1.1.2 arm64e RootHide; read-only Active updateSpecular probe included; Island scoping preserved')
