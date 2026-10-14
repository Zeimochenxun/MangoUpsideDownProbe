"""Inspect arm64e images and verify their embedded signed code pages."""
import hashlib
import struct


def inspect(blob):
    magic, cpu, subtype, filetype, count, size, flags, reserved = struct.unpack_from("<8I", blob)
    assert magic == 0xfeedfacf and cpu == 0x100000c
    assert subtype == 0x80000002, f"Expected current arm64e ABI: {subtype:#x}"
    assert filetype in (6, 8), f"Expected dylib or bundle: {filetype}"
    pos, dependencies, signature = 32, [], None
    for _ in range(count):
        command, length = struct.unpack_from("<2I", blob, pos)
        assert length >= 8 and pos + length <= 32 + size
        if command in (0xc, 0x80000018, 0x8000001f):
            offset = struct.unpack_from("<I", blob, pos + 8)[0]
            dependencies.append(blob[pos + offset:pos + length].split(b"\0", 1)[0].decode())
        if command == 0x1d:
            offset, length_ = struct.unpack_from("<2I", blob, pos + 8)
            signature = blob[offset:offset + length_]
            assert len(signature) == length_
        pos += length
    assert pos == 32 + size and signature is not None
    magic, length, count = struct.unpack_from(">3I", signature)
    assert magic == 0xfade0cc0 and length <= len(signature)
    verified_directories = 0
    for i in range(count):
        kind, offset = struct.unpack_from(">2I", signature, 12 + i * 8)
        cd = signature[offset:]
        if struct.unpack_from(">I", cd)[0] != 0xfade0c02:
            continue
        cd_length, version = struct.unpack_from(">2I", cd, 4)
        hash_offset, ident_offset, special, slots, code_limit = struct.unpack_from(">5I", cd, 16)
        hash_size, hash_type, platform, page_exp = struct.unpack_from("4B", cd, 36)
        assert cd_length <= len(cd)
        if version >= 0x20300 and code_limit == 0xffffffff:
            code_limit = struct.unpack_from(">Q", cd, 56)[0]
        assert 0 < code_limit <= len(blob)
        algorithm = {1: "sha1", 2: "sha256", 3: "sha256", 4: "sha384"}[hash_type]
        page_size = 1 << page_exp
        assert slots == (code_limit + page_size - 1) // page_size
        for page in range(slots):
            start, end = page * page_size, min((page + 1) * page_size, code_limit)
            actual = hashlib.new(algorithm, blob[start:end]).digest()[:hash_size]
            expected = cd[hash_offset + page * hash_size:hash_offset + (page + 1) * hash_size]
            assert actual == expected, f"Invalid code signature page {page}"
        verified_directories += 1
    assert verified_directories
    return {"architecture": "arm64e", "abi": "current", "dependencies": dependencies,
            "verifiedCodeDirectories": verified_directories}
