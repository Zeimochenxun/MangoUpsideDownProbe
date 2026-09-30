#!/usr/bin/env python3
"""Reconstruct integration locally; never include the output in a public upload.

Requires the user's actual package and a separately supplied original Mango
shader. Every original hook target must occur exactly once. This tool provides
local integration evidence only; it does not compile the shader.
"""
from __future__ import annotations

import argparse
import lzma
import re
import sys
from pathlib import Path

from patch_actual_adaptive import (REPLACEMENT_PAIRS, STRING_SPECS, cstring,
                                  entry_payload, get_entry, patch_package, read_ar,
                                  require, sha256, DYLIB_NAME)


def reconstruct(package: bytes, shader: str) -> str:
    require(len(re.findall(r"constant\s+float\s+kDispersionGreenIndex\s*=\s*1\.00\s*;", shader)) == 1,
            "Expected unique kDispersionGreenIndex == 1.00, required for dispersion-independent green sample mapping")
    _, _, fragments = patch_package(package)
    raw = lzma.decompress(read_ar(package)[2].data)
    binary = entry_payload(raw, get_entry(raw, DYLIB_NAME))
    output = shader
    for old_offset, new_offset in REPLACEMENT_PAIRS:
        old = cstring(binary, old_offset).decode("ascii")
        name = next(name for name, spec in STRING_SPECS.items() if spec[0] == new_offset)
        require(output.count(old) == 1, f"Hook target at {old_offset:#x} does not occur exactly once")
        output = output.replace(old, fragments[name].decode("ascii"))
    entry = cstring(binary, 0x5587).decode("ascii")
    require(output.count(entry) == 1, "Helper insertion target does not occur exactly once")
    return output.replace(entry, fragments["helper"].decode("ascii") + entry)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="Exact original private deb")
    parser.add_argument("--mango-shader", required=True, type=Path, help="Original private Mango shader")
    parser.add_argument("--output", required=True, type=Path, help="Local validation file, never a release artifact")
    args = parser.parse_args()
    try:
        require(args.output.resolve() not in (args.input.resolve(), args.mango_shader.resolve()),
                "Output must differ from every input")
        output = reconstruct(args.input.read_bytes(), args.mango_shader.read_text(encoding="utf-8"))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("x", encoding="utf-8", newline="\n") as stream:
            stream.write(output)
        print(f"Local integration created; SHA256={sha256(output.encode('utf-8'))}. Do not publish this file.")
        return 0
    except (ValueError, OSError) as error:
        print(f"Local shader reconstruction failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
