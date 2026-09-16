#!/usr/bin/env python3
"""Read-only CI check of the exact deb produced by this project (no installation)."""
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


def check(path):
    members = ar_members(path.read_bytes())
    control = tar_files(next(v for k, v in members.items() if k.startswith("control.tar")))
    data = tar_files(next(v for k, v in members.items() if k.startswith("data.tar")))
    fields = dict(line.split(": ", 1) for line in control["control"].decode().splitlines()
                  if ": " in line and not line.startswith(" "))
    require(fields.get("Package") == "com.chenxun.mangoupsidedownworld", "wrong package ID")
    require(fields.get("Architecture") == "iphoneos-arm64e", "wrong RootHide package architecture")
    require(set(control).issubset({"control", "md5sums"}), "unexpected package scripts")
    by_name = {Path(k).name: v for k, v in data.items()}
    require(len(data) == 2 and set(by_name) == {"MangoUpsideDownWorld.dylib", "MangoUpsideDownWorld.plist"},
            "unexpected payload; original Mango must never be included")
    plist = plistlib.loads(by_name["MangoUpsideDownWorld.plist"])
    require(plist == {"Filter": {"Bundles": ["com.apple.springboard"]}}, "unexpected injection filter")
    dylib = by_name["MangoUpsideDownWorld.dylib"]
    magic, cpu, subtype, kind, ncmds, sizeofcmds, flags, reserved = struct.unpack_from("<8I", dylib)
    require(magic == 0xfeedfacf and cpu == 0x0100000c and subtype & 0xffffff == 2 and kind == 6,
            "expected a thin arm64e Mach-O dylib")
    pos = 32
    rpaths, dependencies = [], []
    signed = False
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", dylib, pos)
        require(size >= 8 and pos + size <= 32 + sizeofcmds <= len(dylib), "bad load command")
        if cmd in (0x8000001c, 0xc, 0x80000018, 0x8000001f):
            offset = struct.unpack_from("<I", dylib, pos + 8)[0]
            value = dylib[pos + offset:pos + size].split(b"\0", 1)[0].decode()
            (rpaths if cmd == 0x8000001c else dependencies).append(value)
        if cmd == 0x1d:
            offset, length = struct.unpack_from("<II", dylib, pos + 8)
            signed = length > 0 and offset + length <= len(dylib)
        pos += size
    require(
        any(".jbroot" in p for p in rpaths) or
        any(".jbroot" in p for p in dependencies),
        "missing RootHide .jbroot linkage",
    )
    require(not any(p.startswith("/var/jb/") for p in dependencies), "unexpected hardcoded rootless dependency")
    require(signed, "missing embedded code-signature data")
    print(f"PASS {path.name}: {fields['Architecture']}, arm64e, SpringBoard only, two payload files, signature data present")
    print("RPATH:", rpaths)
    print("DEPENDENCIES:", dependencies)
    print("This checks package structure; it does not prove on-device ABI or behavior.")


if __name__ == "__main__":
    require(len(sys.argv) > 1, "provide one or more .deb paths")
    for filename in sys.argv[1:]:
        check(Path(filename))

