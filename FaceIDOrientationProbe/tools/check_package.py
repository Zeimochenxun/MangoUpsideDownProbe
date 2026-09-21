#!/usr/bin/env python3
"""Read package without extracting/chown; reject unexpected injection targets."""
import io
import pathlib
import plistlib
import struct
import subprocess
import sys
import tarfile

if len(sys.argv) != 2:
    raise SystemExit("usage: check_package.py PACKAGE.deb")
package = pathlib.Path(sys.argv[1]).resolve()
data = subprocess.check_output(["dpkg-deb", "--fsys-tarfile", str(package)])
with tarfile.open(fileobj=io.BytesIO(data), mode="r:") as archive:
    files = [m for m in archive.getmembers() if m.isfile()]
    assert len(files) == 2, [m.name for m in files]
    assert not any(m.issym() or m.islnk() for m in archive.getmembers())
    plists = [m for m in files if m.name.endswith("/FaceIDOrientationProbe.plist")]
    dylibs = [m for m in files if m.name.endswith("/FaceIDOrientationProbe.dylib")]
    assert len(plists) == len(dylibs) == 1
    config = plistlib.loads(archive.extractfile(plists[0]).read())
    assert config == {"Filter": {"Executables": ["biometrickitd"]}}, config
    binary = archive.extractfile(dylibs[0]).read()
    magic, cpu, subtype, filetype = struct.unpack_from("<4I", binary)
    assert magic == 0xFEEDFACF and cpu == 0x0100000C and (subtype & 0xFFFFFF) == 2 and filetype == 6
    for value in (b"BiometricKitXPCServerPearl", b"BKFaceDetectStateInfo", b"PearlCoreAnalytics", b"MSHookMessageEx", b"20F66", b"iPhone14,4"):
        assert value in binary, value
control_tar = subprocess.check_output(["dpkg-deb", "--ctrl-tarfile", str(package)])
with tarfile.open(fileobj=io.BytesIO(control_tar), mode="r:") as archive:
    controls = [m for m in archive.getmembers() if m.isfile()]
    assert len(controls) == 1 and pathlib.PurePosixPath(controls[0].name).name == "control", "unexpected maintainer scripts"
    control = archive.extractfile(controls[0]).read().decode()
assert "Version: 0.2.0" in control
assert "Architecture: iphoneos-arm64e" in control
assert "Package: com.chenxun.faceidorientationprobe" in control
print("PASS: exact biometrickitd filter, two payload files, arm64e Mach-O dylib, version and hook guards")
