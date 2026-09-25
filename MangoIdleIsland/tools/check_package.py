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
    for required in [b'MSHookMessageEx', b'SBSystemApertureContainerView', b'Status.log', b'initWithFrame:groupName:filterType:', b'go.mangoos.island', b'PillGlass.Enabled', b'original-island-glass-observed', b'Island.SpecularEnabled', b'go.mangoos/ParametersReloaded']:
        assert required in data, required
    for forbidden in [b'MSHookFunction', b'locationInView:', b'translationInView:']:
        assert forbidden not in data, forbidden
    prefs = next(m for m in regular if m.name.endswith('/MangoIdleIslandPrefs.bundle/MangoIdleIslandPrefs'))
    pmagic, pcpu, psubtype, ptype = struct.unpack_from('<4I', t.extractfile(prefs).read())
    # Theos bundle.mk links preference bundles as Mach-O MH_DYLIB (6).
    assert pmagic == 0xfeedfacf and pcpu == 0x100000c and (psubtype & 0xffffff) == 2 and ptype == 6
    entry = next(m for m in regular if m.name.endswith('/PreferenceLoader/Preferences/MangoIdleIslandPrefs.plist'))
    assert plistlib.loads(t.extractfile(entry).read())['entry']['bundle'] == 'MangoIdleIslandPrefs'
with tarfile.open(fileobj=io.BytesIO(subprocess.check_output(['dpkg-deb', '--ctrl-tarfile', package]))) as t:
    regular = [m for m in t if m.isfile()]
    assert len(regular) == 1 and pathlib.PurePosixPath(regular[0].name).name == 'control'
    control = t.extractfile(regular[0]).read().decode()
    assert 'Version: 0.5.0' in control and 'Architecture: iphoneos-arm64e' in control
print('PASS: arm64e; SpringBoard-only tweak; separate preferences bundle; no maintainer scripts')
