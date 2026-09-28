#!/usr/bin/env python3
"""Read-only validation of the built adaptive-color RootHide package."""
import io
import pathlib
import plistlib
import struct
import subprocess
import sys
import tarfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


path = pathlib.Path(sys.argv[1])
with tarfile.open(fileobj=io.BytesIO(subprocess.check_output(["dpkg-deb", "--fsys-tarfile", path]))) as archive:
    files = [member for member in archive if member.isfile()]
    plist_member = next(member for member in files if member.name.endswith("/MangoIslandAdaptiveColor.plist"))
    dylib_member = next(member for member in files if member.name.endswith("/MangoIslandAdaptiveColor.dylib"))
    require(plistlib.loads(archive.extractfile(plist_member).read()) ==
            {"Filter": {"Executables": ["SpringBoard", "backboardd"]}},
            "adaptive color must cover the SpringBoard view and backboardd renderer")
    dylib = archive.extractfile(dylib_member).read()

magic, cpu, subtype, filetype = struct.unpack_from("<4I", dylib)
require(magic == 0xFEEDFACF, "expected a 64-bit Mach-O")
require(cpu == 0x0100000C and subtype & 0xFFFFFF == 2, "expected arm64e")
require(filetype == 6, "expected a dylib")
for marker in (
    b"0.1.8 dual-process",
    b"MangoIslandAdaptiveColor.Adaptation",
    b"Island.LightTintColor",
    b"Island.DarkTintColor",
    b"mangoIslandAdaptiveColor",
    b"Island adaptive mix compiled",
):
    require(marker in dylib, f"missing runtime marker: {marker!r}")

control = subprocess.check_output(["dpkg-deb", "--field", path]).decode()
require("Package: com.chenxun.mangoislandadaptivecolor" in control, "wrong package ID")
require("Version: 0.1.8" in control, "wrong package version")
require("Architecture: iphoneos-arm64e" in control, "wrong package architecture")
require("com.chenxun.mangoidleisland (>= 1.1.8)" in control, "missing cohesive Idle dependency")

print("PASS: MangoIslandAdaptiveColor 0.1.8 arm64e RootHide; SpringBoard view and backboardd renderer verified")
