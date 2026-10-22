#!/usr/bin/env python3
"""Read-only CI check of the exact deb produced by island/ (no installation).

Same method as check_package.py, for the Dynamic Island package: a SpringBoard
tweak dylib with its filter, and a Settings bundle with its PreferenceLoader
entry. Nothing from Mango may be in the payload.
"""
import io
import plistlib
import struct
import sys
import tarfile
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def ar_members(raw):
    require(raw.startswith(b"!<arch>\n"), "not a Debian ar archive")
    pos = 8
    members = {}
    while pos < len(raw):
        header = raw[pos:pos + 60]
        require(len(header) == 60 and header[58:] == b"`\n", "bad ar header")
        size = int(header[48:58])
        name = header[:16].decode().strip().rstrip("/")
        payload = raw[pos + 60:pos + 60 + size]
        require(len(payload) == size, "truncated ar member")
        members[name] = payload
        pos += 60 + size + size % 2
    return members


def tar_files(raw):
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:*") as archive:
        files = {}
        for member in archive.getmembers():
            if member.isdir():
                continue
            require(member.isfile(), "unexpected link or special file in package")
            files[member.name.removeprefix("./")] = archive.extractfile(member).read()
        return files


def macho_summary(name, data):
    """Thin arm64e Mach-O with RootHide linkage and signature data; returns (rpaths, dependencies)."""
    magic, cpu, subtype, kind, ncmds, sizeofcmds, flags, reserved = struct.unpack_from("<8I", data)
    require(magic == 0xfeedfacf and cpu == 0x0100000c and subtype & 0xffffff == 2 and kind == 6,
            f"{name}: expected a thin arm64e Mach-O dylib/bundle")
    pos = 32
    rpaths, dependencies = [], []
    signed = False
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, pos)
        require(size >= 8 and pos + size <= 32 + sizeofcmds <= len(data), f"{name}: bad load command")
        if cmd in (0x8000001c, 0xc, 0x80000018, 0x8000001f):
            offset = struct.unpack_from("<I", data, pos + 8)[0]
            value = data[pos + offset:pos + size].split(b"\0", 1)[0].decode()
            (rpaths if cmd == 0x8000001c else dependencies).append(value)
        if cmd == 0x1d:
            offset, length = struct.unpack_from("<II", data, pos + 8)
            signed = length > 0 and offset + length <= len(data)
        pos += size
    require(any(".jbroot" in p for p in rpaths) or any(".jbroot" in p for p in dependencies),
            f"{name}: missing RootHide .jbroot linkage")
    require(not any(p.startswith("/var/jb/") for p in dependencies), f"{name}: unexpected hardcoded rootless dependency")
    require(signed, f"{name}: missing embedded code-signature data")
    return rpaths, dependencies


def check(path):
    members = ar_members(path.read_bytes())
    control = tar_files(next(v for k, v in members.items() if k.startswith("control.tar")))
    data = tar_files(next(v for k, v in members.items() if k.startswith("data.tar")))
    fields = dict(line.split(": ", 1) for line in control["control"].decode().splitlines()
                  if ": " in line and not line.startswith(" "))
    require(fields.get("Package") == "com.chenxun.dynamicisland", "wrong package ID")
    require(fields.get("Architecture") == "iphoneos-arm64e", "wrong RootHide package architecture")
    require("preferenceloader" in fields.get("Depends", ""), "missing preferenceloader dependency")
    require(set(control).issubset({"control", "md5sums"}), "unexpected package scripts")

    by_name = {}
    for name, payload in data.items():
        base = Path(name).name
        require(base not in by_name, f"duplicate payload file name {base}")
        by_name[base] = (name, payload)
    expected = {"DynamicIsland.dylib", "DynamicIsland.plist", "DynamicIslandPrefs", "Info.plist", "DynamicIslandPrefs.plist"}
    require(set(by_name) == expected, f"unexpected payload {sorted(by_name)}; original Mango must never be included")

    where = {base: name for base, (name, _) in by_name.items()}
    require("MobileSubstrate/DynamicLibraries/" in where["DynamicIsland.dylib"], "tweak dylib is not in DynamicLibraries")
    require("MobileSubstrate/DynamicLibraries/" in where["DynamicIsland.plist"], "tweak filter is not in DynamicLibraries")
    require("PreferenceBundles/DynamicIslandPrefs.bundle/" in where["DynamicIslandPrefs"], "bundle binary is not in its bundle")
    require("PreferenceBundles/DynamicIslandPrefs.bundle/" in where["Info.plist"], "bundle Info.plist is not in its bundle")
    require("PreferenceLoader/Preferences/" in where["DynamicIslandPrefs.plist"], "Settings entry is not in PreferenceLoader")

    flt = plistlib.loads(by_name["DynamicIsland.plist"][1])
    require(flt == {"Filter": {"Bundles": ["com.apple.springboard"]}}, "unexpected injection filter")
    info = plistlib.loads(by_name["Info.plist"][1])
    require(info.get("CFBundleExecutable") == "DynamicIslandPrefs", "bundle executable name")
    require(info.get("NSPrincipalClass") == "DynamicIslandRootController", "bundle principal class")
    require(info.get("CFBundleShortVersionString") == fields.get("Version"), "bundle version differs from the package version")
    entry = plistlib.loads(by_name["DynamicIslandPrefs.plist"][1]).get("entry", {})
    require(entry.get("bundle") == "DynamicIslandPrefs" and entry.get("detail") == "DynamicIslandRootController",
            "Settings entry does not point at the bundle")

    tweak = macho_summary("DynamicIsland.dylib", by_name["DynamicIsland.dylib"][1])
    bundle = macho_summary("DynamicIslandPrefs", by_name["DynamicIslandPrefs"][1])
    print(f"PASS {path.name}: {fields['Architecture']}, arm64e, SpringBoard tweak + Settings bundle, signature data present")
    print("TWEAK RPATH:", tweak[0], "DEPENDENCIES:", tweak[1])
    print("BUNDLE RPATH:", bundle[0], "DEPENDENCIES:", bundle[1])
    print("This checks package structure; it does not prove on-device ABI or behavior.")


if __name__ == "__main__":
    require(len(sys.argv) > 1, "provide one or more .deb paths")
    for filename in sys.argv[1:]:
        check(Path(filename))
