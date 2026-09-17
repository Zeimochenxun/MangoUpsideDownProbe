#!/usr/bin/env python3
import io, plistlib, struct, sys, tarfile
from pathlib import Path

def require(value, message):
    if not value: raise ValueError(message)

def ar_members(raw):
    require(raw.startswith(b"!<arch>\n"), "not a deb archive")
    out, pos = {}, 8
    while pos < len(raw):
        header = raw[pos:pos+60]
        require(len(header) == 60 and header[58:] == b"`\n", "bad ar header")
        size = int(header[48:58]); name = header[:16].decode().strip().rstrip("/")
        out[name] = raw[pos+60:pos+60+size]
        pos += 60 + size + size % 2
    return out

def tar_files(raw):
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:*") as archive:
        out = {}
        for member in archive.getmembers():
            if member.isdir(): continue
            require(member.isfile(), "unexpected link/special file")
            out[member.name.removeprefix("./")] = archive.extractfile(member).read()
        return out

def check_macho(raw):
    magic,cpu,subtype,kind,ncmds,sizeofcmds,flags,reserved = struct.unpack_from("<8I", raw)
    require(magic == 0xfeedfacf and cpu == 0x0100000c, "not arm64 Mach-O")
    require(subtype & 0xffffff == 2 and kind == 6, "expected thin arm64e dylib")
    pos, signed, dependencies, rpaths = 32, False, [], []
    for _ in range(ncmds):
        cmd,size = struct.unpack_from("<II", raw, pos)
        require(size >= 8 and pos + size <= 32 + sizeofcmds <= len(raw), "bad load command")
        if cmd in (0x8000001c,0xc,0x80000018,0x8000001f):
            off = struct.unpack_from("<I", raw, pos+8)[0]
            value = raw[pos+off:pos+size].split(b"\0",1)[0].decode()
            (rpaths if cmd == 0x8000001c else dependencies).append(value)
        if cmd == 0x1d:
            off,length = struct.unpack_from("<II", raw, pos+8)
            signed = length > 0 and off + length <= len(raw)
        pos += size
    require(signed, "missing code signature")
    require(not any(x.startswith("/var/jb/") for x in dependencies), "hardcoded rootless path")
    for dep in dependencies:
        system = dep.startswith("/System/Library/") or dep.startswith("/usr/lib/")
        roothide = ".jbroot" in dep or (dep.startswith("@rpath/") and any(".jbroot" in r for r in rpaths))
        require(system or roothide, f"unresolved dependency {dep}")

def check(path):
    members = ar_members(path.read_bytes())
    control = tar_files(next(v for k,v in members.items() if k.startswith("control.tar")))
    data = tar_files(next(v for k,v in members.items() if k.startswith("data.tar")))
    fields = dict(line.split(": ",1) for line in control["control"].decode().splitlines() if ": " in line)
    require(fields.get("Package") == "com.chenxun.mangoorientationprobe", "wrong package id")
    require(fields.get("Architecture") == "iphoneos-arm64e", "wrong package architecture")
    require(set(control).issubset({"control","md5sums"}), "unexpected maintainer script")
    by_name = {Path(k).name:v for k,v in data.items()}
    require(set(by_name) == {"MangoOrientationProbe.dylib","MangoOrientationProbe.plist"}, "unexpected payload")
    expected = {"Filter":{"Bundles":["com.apple.springboard"]}}
    require(plistlib.loads(by_name["MangoOrientationProbe.plist"]) == expected, "wrong injection filter")
    check_macho(by_name["MangoOrientationProbe.dylib"])
    print(f"PASS {path.name}: arm64e RootHide, SpringBoard-only, no package scripts")

for name in sys.argv[1:]: check(Path(name))
