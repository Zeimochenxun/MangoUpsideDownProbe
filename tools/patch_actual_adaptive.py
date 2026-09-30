#!/usr/bin/env python3
"""Patch only two owned Metal strings in the exact supplied 0.1.3 package.

No recompilation, instruction patching, pointer relocation, or marker protocol
change is performed. Input archives are never extracted onto the filesystem.
The existing unsigned CodeDirectory is repaired, not replaced. Device loading
and Apple's Metal compiler still require separate validation.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import lzma
import struct
import sys
import tarfile
from dataclasses import dataclass
from pathlib import Path

BASELINE_SHA256 = "840d1d77b7d6b10a6c2959371e1abc367041ef343ba9e393c831186f39b5ba5c"
VERSION = "0.1.3.3~alpha1"
PACKAGE_NAME = f"AdaptiveColor-{VERSION}-RootHide-arm64e-experimental.deb"
DYLIB_NAME = "Library/MobileSubstrate/DynamicLibraries/MangoIslandAdaptiveColor.dylib"
STRING_SPECS = {
    "flat": (0x56BD, 0x3B, 0x83C0),
    "curved": (0x56F9, 0x187, 0x83E0),
    "dispersion": (0x5881, 0x140, 0x8400),
    "glare": (0x59C2, 0x7B, 0x8420),
    "helper": (0x5A3E, 0x128F, 0x8440),
}
REPLACEMENT_PAIRS = ((0x559F, 0x56BD), (0x55D9, 0x56F9),
                     (0x5616, 0x5881), (0x5651, 0x59C2))
OLD_GUARD = "if (!miaIsIslandMarker(tint)) return 0.0;"
NEW_GUARD = "uint p=miaPackedMarker(tint);\n    if(p==0xFFFFFFFFu||(p&7u)==0u)return 0.0;"
REMOVED_COMMENT = "    // Highlight Glass: preserve RGB relationships and backdrop detail.\n"
NEW_DISPERSION = (
    "float dispersion=clamp(u.dispersionStrength,0.0,20.0);\n"
    "if(miaIsIslandMarker(u.tintColor)){\n"
    " float4 c=src.sample(s,backdropSampleUV(capturePx,px,dispPx,isCoverSheet,u));\n"
    " if(c.a<.01)c=src.sample(s,captureUV);\n"
    " dispersion=clamp(dispersion*mix(1.0,1.60,miaHighlightAmount(c.rgb,u.tintColor)),0.0,20.0);\n}"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


@dataclass(frozen=True)
class ArMember:
    name: str
    header: bytes
    data: bytes
    padding: bytes


def read_ar(data: bytes) -> list[ArMember]:
    require(data[:8] == b"!<arch>\n", "Not a Debian ar archive")
    members = []
    cursor = 8
    while cursor < len(data):
        header = data[cursor:cursor + 60]
        require(len(header) == 60 and header[58:] == b"`\n", "Invalid ar header")
        name = header[:16].decode("ascii").strip().rstrip("/")
        require(name and name not in ("/", "//") and not name.startswith("#1/"),
                "Unsupported extended ar name")
        size = int(header[48:58])
        require(size >= 0 and cursor + 60 + size + size % 2 <= len(data), "Truncated ar member")
        payload = data[cursor + 60:cursor + 60 + size]
        padding = data[cursor + 60 + size:cursor + 60 + size + size % 2]
        members.append(ArMember(name, header, payload, padding))
        cursor += 60 + size + size % 2
    require(cursor == len(data), "Trailing ar bytes")
    require([m.name for m in members] == ["debian-binary", "control.tar.gz", "data.tar.lzma"],
            "Unexpected package member layout")
    require(members[0].data == b"2.0\n", "Unexpected Debian format version")
    return members


def write_ar(members: list[ArMember], replacements: dict[str, bytes]) -> bytes:
    result = bytearray(b"!<arch>\n")
    for member in members:
        payload = replacements.get(member.name, member.data)
        header = member.header
        if len(payload) != len(member.data):
            size = str(len(payload)).encode("ascii")
            require(len(size) <= 10, "ar payload too large")
            header = header[:48] + size.ljust(10, b" ") + header[58:]
        result += header + payload
        if len(payload) % 2:
            result += member.padding if member.padding else b"\n"
    return bytes(result)


def tar_entries(raw: bytes) -> list[tarfile.TarInfo]:
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:") as archive:
        return archive.getmembers()


def normalized_name(name: str) -> str:
    return name.removeprefix("./").rstrip("/")


def get_entry(raw: bytes, name: str) -> tarfile.TarInfo:
    matches = [entry for entry in tar_entries(raw) if normalized_name(entry.name) == name]
    require(len(matches) == 1 and matches[0].isfile(), f"Missing or duplicate regular file: {name}")
    require(not matches[0].pax_headers, "Unexpected PAX metadata on patched entry")
    return matches[0]


def entry_payload(raw: bytes, entry: tarfile.TarInfo) -> bytes:
    return raw[entry.offset_data:entry.offset_data + entry.size]


def replace_tar_payload(raw: bytes, entry: tarfile.TarInfo, replacement: bytes) -> bytes:
    """Preserve exact headers, padding, order, and metadata of every other entry."""
    require(entry.offset_data == entry.offset + 512, "Unsupported extended tar header")
    old_span = (entry.size + 511) // 512 * 512
    new_span = (len(replacement) + 511) // 512 * 512
    header = raw[entry.offset:entry.offset_data]
    if len(replacement) != entry.size:
        require(len(replacement) < 8 ** 11, "tar payload too large")
        header = bytearray(header)
        header[124:136] = f"{len(replacement):011o}".encode() + b"\0"
        header[148:156] = b" " * 8
        header[148:156] = f"{sum(header):06o}".encode() + b"\0 "
        header = bytes(header)
    return (raw[:entry.offset] + header + replacement.ljust(new_span, b"\0")
            + raw[entry.offset_data + old_span:])


def cstring(binary: bytes, offset: int) -> bytes:
    return binary[offset:binary.index(0, offset)]


def code_directory(binary: bytes) -> dict:
    require(len(binary) == 69664, "Unexpected baseline dylib size")
    require(struct.unpack_from("<I", binary)[0] == 0xFEEDFACF, "Expected thin 64-bit Mach-O")
    require(struct.unpack_from("<I", binary, 4)[0] == 0x100000C, "Expected arm64 CPU")
    cursor, signature = 32, None
    for _ in range(struct.unpack_from("<I", binary, 16)[0]):
        command, size = struct.unpack_from("<II", binary, cursor)
        require(size >= 8 and cursor + size <= len(binary), "Invalid Mach-O load command")
        if command == 0x1D:
            require(signature is None, "Duplicate code signature command")
            signature = struct.unpack_from("<II", binary, cursor + 8)
        cursor += size
    require(signature == (0x10C70, 0x3B0), "Unexpected code signature location")
    signature_offset, signature_size = signature
    magic, length, count = struct.unpack_from(">III", binary, signature_offset)
    require(magic == 0xFADE0CC0 and length <= signature_size and count == 2,
            "Unexpected signature superblob")
    directory = None
    slots = []
    for index in range(count):
        slot, relative = struct.unpack_from(">II", binary, signature_offset + 12 + 8 * index)
        offset = signature_offset + relative
        blob_magic, blob_length = struct.unpack_from(">II", binary, offset)
        require(offset + blob_length <= signature_offset + length, "Invalid signature blob")
        slots.append((slot, blob_magic))
        if slot == 0 and blob_magic == 0xFADE0C02:
            require(directory is None, "Multiple CodeDirectories")
            version, flags, hash_offset, identifier_offset, special, pages, limit = struct.unpack_from(">7I", binary, offset + 8)
            hash_size, hash_type, platform, page_shift = struct.unpack_from("4B", binary, offset + 36)
            require((version, flags, special, pages, limit, hash_size, hash_type, platform, page_shift)
                    == (0x20400, 0, 2, 17, 0x10C70, 32, 2, 0, 12),
                    "Unexpected CodeDirectory format")
            require(hash_offset == 201 and identifier_offset == 88, "Unexpected CodeDirectory offsets")
            directory = {"offset": offset, "length": blob_length,
                         "hash_offset": hash_offset, "page_count": pages,
                         "code_limit": limit, "page_size": 1 << page_shift, "hash_size": hash_size}
    require(slots == [(0, 0xFADE0C02), (2, 0xFADE0C01)], "Unexpected signature slots or CMS signature")
    require(directory is not None, "No SHA256 CodeDirectory")
    return directory


def verify_code_hashes(binary: bytes) -> dict:
    directory = code_directory(binary)
    for page in range(directory["page_count"]):
        start = page * directory["page_size"]
        end = min(start + directory["page_size"], directory["code_limit"])
        position = directory["offset"] + directory["hash_offset"] + page * directory["hash_size"]
        require(binary[position:position + 32] == hashlib.sha256(binary[start:end]).digest(),
                f"CodeDirectory hash mismatch on page {page}")
    return directory


def patch_dylib(original: bytes) -> tuple[bytes, dict, dict[str, bytes]]:
    directory = verify_code_hashes(original)
    fragments = {}
    for name, (offset, length, cf_offset) in STRING_SPECS.items():
        fragment = cstring(original, offset)
        require(len(fragment) == length and fragment.isascii(), f"Unexpected {name} string")
        pointer, cf_length = struct.unpack_from("<QQ", original, cf_offset + 16)
        require(pointer == 0x10000000000000 + offset and cf_length == length,
                f"Unexpected {name} CFString pointer/length")
        fragments[name] = fragment
    helper = fragments["helper"].decode("ascii")
    require(helper.count(OLD_GUARD) == 1, "Missing unique highlight guard")
    require(helper.count(REMOVED_COMMENT) == 1, "Missing unique expendable comment")
    new_helper = helper.replace(OLD_GUARD, NEW_GUARD).replace(REMOVED_COMMENT, "").encode("ascii")
    require(len(new_helper) == 4713, "Unexpected helper patch length")
    old_dispersion = fragments["dispersion"]
    require(old_dispersion.count(b"src.sample(s, captureUV)") == 1,
            "Missing unique original dispersion sample")
    require(len(NEW_DISPERSION.encode("ascii")) == 301, "Unexpected dispersion patch length")
    fragments["helper"] = new_helper.ljust(4751, b" ")
    fragments["dispersion"] = NEW_DISPERSION.encode("ascii").ljust(320, b" ")
    patched = bytearray(original)
    allowed_ranges = []
    for name in ("helper", "dispersion"):
        offset, length, _ = STRING_SPECS[name]
        patched[offset:offset + length] = fragments[name]
        allowed_ranges.append((offset, offset + length))
    changed_pages = []
    for page in range(directory["page_count"]):
        start = page * directory["page_size"]
        end = min(start + directory["page_size"], directory["code_limit"])
        new_hash = hashlib.sha256(patched[start:end]).digest()
        hash_position = directory["offset"] + directory["hash_offset"] + page * 32
        if new_hash != original[hash_position:hash_position + 32]:
            changed_pages.append(page)
            patched[hash_position:hash_position + 32] = new_hash
            allowed_ranges.append((hash_position, hash_position + 32))
    require(changed_pages == [5, 6], "Unexpected changed code pages")
    patched = bytes(patched)
    require(len(patched) == len(original), "Dylib length changed")
    differences = [index for index, (before, after) in enumerate(zip(original, patched)) if before != after]
    require(all(any(start <= index < end for start, end in allowed_ranges) for index in differences),
            "Unexpected modification outside owned shader strings and page hashes")
    verify_code_hashes(patched)
    for name, (offset, length, cf_offset) in STRING_SPECS.items():
        require(cstring(patched, offset) == fragments[name], f"Modified {name} NUL boundary")
        require(patched[offset + length] == 0, f"Missing {name} NUL")
        require(patched[cf_offset:cf_offset + 32] == original[cf_offset:cf_offset + 32],
                f"Modified {name} CFString")
    evidence = {
        "original_dylib_sha256": sha256(original), "patched_dylib_sha256": sha256(patched),
        "dylib_bytes": len(patched), "changed_byte_count": len(differences),
        "permitted_ranges": [{"start": hex(start), "end_exclusive": hex(end)} for start, end in allowed_ranges],
        "changed_code_pages": changed_pages, "verified_code_pages": directory["page_count"],
        "only_owned_strings_and_code_hashes_changed": True,
        "all_cfstring_records_and_nul_boundaries_preserved": True,
        "cpu_instructions_load_commands_and_non_shader_bytes_preserved": True,
        "cms_signature_present": False,
    }
    return patched, evidence, fragments


def compare_tar(original: bytes, patched: bytes, changed_name: str, expected_payload: bytes) -> dict:
    before, after = tar_entries(original), tar_entries(patched)
    require(len(before) == len(after), "Changed tar member count")
    unchanged = []
    for left, right in zip(before, after):
        require(left.name == right.name, "Changed tar member order/name")
        keys = ("mode", "uid", "gid", "uname", "gname", "mtime", "type", "linkname", "pax_headers")
        require(all(getattr(left, key) == getattr(right, key) for key in keys),
                f"Changed tar metadata: {left.name}")
        if normalized_name(left.name) == changed_name:
            require(entry_payload(patched, right) == expected_payload, "Unexpected changed file payload")
        else:
            require(left.size == right.size and entry_payload(original, left) == entry_payload(patched, right),
                    f"Changed unrelated tar payload: {left.name}")
            # This baseline needs no relocation, making exact header preservation checkable.
            require(original[left.offset:left.offset_data] == patched[right.offset:right.offset_data],
                    f"Changed unrelated tar header: {left.name}")
            if left.isfile():
                unchanged.append({"path": left.name, "sha256": sha256(entry_payload(original, left))})
    return {"member_count": len(before), "metadata_preserved": True, "unchanged_files": unchanged}


def patch_package(package: bytes) -> tuple[bytes, dict, dict[str, bytes]]:
    require(sha256(package) == BASELINE_SHA256, "Input package SHA256 differs from the exact supplied baseline")
    members = read_ar(package)
    control_raw = gzip.decompress(members[1].data)
    data_raw = lzma.decompress(members[2].data, format=lzma.FORMAT_ALONE)
    dylib_entry = get_entry(data_raw, DYLIB_NAME)
    original_dylib = entry_payload(data_raw, dylib_entry)
    patched_dylib, evidence, fragments = patch_dylib(original_dylib)
    patched_data = replace_tar_payload(data_raw, dylib_entry, patched_dylib)
    require(len(patched_data) == len(data_raw), "Data tar layout changed")
    allowed_start = dylib_entry.offset_data
    require(patched_data[:allowed_start] == data_raw[:allowed_start]
            and patched_data[allowed_start + dylib_entry.size:] == data_raw[allowed_start + dylib_entry.size:],
            "Unrelated raw data tar bytes changed")
    control_entry = get_entry(control_raw, "control")
    original_control = entry_payload(control_raw, control_entry)
    require(original_control.count(b"Version: 0.1.3\n") == 1, "Missing unique exact Version field")
    new_control = original_control.replace(b"Version: 0.1.3\n", f"Version: {VERSION}\n".encode())
    patched_control = replace_tar_payload(control_raw, control_entry, new_control)
    require(len(patched_control) == len(control_raw), "Unexpected control tar block relocation")
    control_gzip = gzip.compress(patched_control, compresslevel=9, mtime=0)
    require(members[1].data[:4] == b"\x1f\x8b\x08\x00", "Unexpected gzip header flags")
    control_gzip = members[1].data[:10] + control_gzip[10:]
    require(gzip.decompress(control_gzip) == patched_control, "Control compression round trip failed")
    data_lzma = lzma.compress(patched_data, format=lzma.FORMAT_ALONE, preset=9)
    require(data_lzma[:5] == members[2].data[:5], "LZMA properties changed")
    require(lzma.decompress(data_lzma, format=lzma.FORMAT_ALONE) == patched_data,
            "Data compression round trip failed")
    result = write_ar(members, {"control.tar.gz": control_gzip, "data.tar.lzma": data_lzma})
    final_members = read_ar(result)
    require(final_members[0] == members[0], "Debian binary ar member changed")
    for left, right in zip(members, final_members):
        require(left.header[:48] == right.header[:48] and left.header[58:] == right.header[58:],
                f"ar metadata changed: {left.name}")
    evidence.update({
        "baseline_package_sha256": BASELINE_SHA256, "patched_package_sha256": sha256(result),
        "version_before": "0.1.3", "version_after": VERSION,
        "control_only_version_changed": new_control.replace(f"Version: {VERSION}\n".encode(),
                                                             b"Version: 0.1.3\n") == original_control,
        "ar_member_order_and_metadata_preserved": True,
        "data_tar_raw_bytes_outside_dylib_preserved": True,
        "data_tar": compare_tar(data_raw, patched_data, DYLIB_NAME, patched_dylib),
        "control_tar": compare_tar(control_raw, patched_control, "control", new_control),
        "changes": ["masterCode == 0 disables additional edge/highlight enhancements",
                    "dispersion brightness uses the same backdropSampleUV coordinates and alpha fallback as greenSample"],
        "green_sample_alignment": {
            "baseline_green_index": 1.0,
            "green_scale_formula": "1.0 - (kDispersionGreenIndex - 1.0) * dispersion",
            "green_scale_is_one_independent_of_dispersion": True,
            "displacement": "dispPx",
            "alpha_fallback_threshold": 0.01,
            "prerequisite": "Current original Mango shader has kDispersionGreenIndex == 1.00; checked separately during local integration",
        },
        "unchanged_marker_protocol": True,
        "verification_limits": ["No iOS/RootHide loading test", "No GPU rendering or Apple Metal compilation in this script"],
    })
    return result, evidence, fragments


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    try:
        package, evidence, fragments = patch_package(args.input.read_bytes())
        artifacts = {PACKAGE_NAME: package,
                     "manifest.json": (json.dumps(evidence, ensure_ascii=False, indent=2) + "\n").encode("utf-8")}
        artifacts.update({f"{name}.metal": fragment for name, fragment in fragments.items()})
        out = args.output_dir.resolve()
        require(out != args.input.resolve().parent, "Output must be separate from the input directory")
        out.mkdir(parents=True, exist_ok=True)
        require(not any((out / name).exists() for name in artifacts), "Refusing to overwrite an existing output artifact")
        for name, payload in artifacts.items():
            with (out / name).open("xb") as output:
                output.write(payload)
        print(json.dumps({"package": str(out / PACKAGE_NAME), "manifest": str(out / "manifest.json"),
                          "sha256": evidence["patched_package_sha256"], "code_pages_verified": 17},
                         ensure_ascii=False))
        return 0
    except (ValueError, OSError, EOFError, struct.error, tarfile.TarError, lzma.LZMAError) as error:
        print(f"AdaptiveColor patch failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
