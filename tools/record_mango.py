"""Record read-only identifiers from one supplied Mango package and optional exact rewrite.

The package is untrusted data: keep it in its own empty directory and run
python -I tools/record_mango.py --mango-deb <deb> --version 1.0-Beta11-1 --sha256 <sha256>
"""
import argparse
import hashlib
import json
import pathlib
import re
import struct
import sys
import uuid

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))  # python -I drops the script directory
from deb import read_deb

ROOT = pathlib.Path(__file__).resolve().parents[1]
DYNAMIC = "Library/MobileSubstrate/DynamicLibraries/"


def identity(blob):
    magic, cpu, subtype, kind, count, size = struct.unpack_from("<6I", blob)
    assert (magic, cpu, subtype, kind) == (0xfeedfacf, 0x100000c, 0x80000002, 6)
    assert 0 < count <= 4096 and 8 <= size <= 262144 and 32 + size <= len(blob)
    position, identifier = 32, None
    for _ in range(count):
        command, length = struct.unpack_from("<II", blob, position)
        assert length >= 8 and position + length <= 32 + size
        if command == 0x1b:
            assert length == 24 and identifier is None
            identifier = str(uuid.UUID(bytes=blob[position + 8:position + 24])).upper()
        position += length
    assert position == 32 + size and identifier
    return {"uuid": identifier, "sha256": hashlib.sha256(blob).hexdigest(), "cpuSubtype": hex(subtype)}


def original_shader(blob):
    # MangoOSRendering embeds one NUL-terminated Metal source. Record its size and hash only.
    hits = [match.start() for match in re.finditer(rb"metal_stdlib", blob)]
    assert len(hits) == 1, "Expected exactly one embedded Metal source"
    source = blob[blob.rfind(b"\0", 0, hits[0]) + 1:blob.index(b"\0", hits[0])]
    return {"originalShaderBytes": len(source), "originalShaderSHA256": hashlib.sha256(source).hexdigest()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mango-deb", required=True, type=pathlib.Path)
    parser.add_argument("--version", required=True, help="Expected control Version, e.g. 1.0-Beta11-1")
    parser.add_argument("--sha256", required=True, help="SHA256 of the audited sample package")
    parser.add_argument("--adaptive-shader", type=pathlib.Path,
                        help="Optionally replace the hash using the exact private Apple Metal input; otherwise preserve it")
    args = parser.parse_args()
    beta = re.fullmatch(r"1\.0-Beta(\d+)-\d+", args.version)
    assert beta, "Expected a Mango 1.0-BetaN-R version"
    package_hash = hashlib.sha256(args.mango_deb.read_bytes()).hexdigest()
    assert package_hash == args.sha256.lower(), "Only the supplied audited sample is supported"
    package = read_deb(args.mango_deb)
    fields = dict(line.split(": ", 1) for line in package["control"]["control"][0].decode().splitlines() if ": " in line)
    assert fields["Package"] == "com.go.mango" and fields["Version"] == args.version
    assert fields["Architecture"] == "iphoneos-arm64e"
    images = {name: identity(package["data"][DYNAMIC + name][0])
              for name in ("MangoPanda.dylib", "MangoHello.dylib", "MangoOSRendering.dylib")}
    destination = ROOT / "mango-compatibility.json"
    # Judgement keys (adaptiveSupported, adaptiveShaderSHA256) belong to one audited sample: keep them
    # only for the same package, otherwise start fresh so they must be re-decided for the new build.
    record = json.loads(destination.read_text(encoding="utf-8")) if destination.is_file() else {}
    if record.get("samplePackageSHA256") != package_hash:
        record = {}
    record.update({"mangoVersion": args.version, "samplePackageSHA256": package_hash, "images": images,
                   **original_shader(package["data"][DYNAMIC + "MangoOSRendering.dylib"][0])})
    if args.adaptive_shader:
        shader = args.adaptive_shader.read_bytes()
        assert 0 < len(shader) < 34000
        record["adaptiveShaderSHA256"] = hashlib.sha256(shader).hexdigest()
    # LF on every host: assemble.py records this file's raw SHA256, which must not depend on the checkout.
    destination.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps(record))
    print("Now copy the three UUIDs into src/MangoIdentity.h (string and byte forms) and decide MS_ADAPTIVE_SUPPORTED;"
          " tests/test_identity_table.py checks the header against this file.", file=sys.stderr)


if __name__ == "__main__":
    main()
