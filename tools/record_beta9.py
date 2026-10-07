"""Record read-only identifiers from the supplied Beta9 package and exact rewrite."""
import argparse
import hashlib
import json
import pathlib
import struct
import uuid
from deb import read_deb

ROOT = pathlib.Path(__file__).resolve().parents[1]
SAMPLE_SHA256 = "4826d2e73c59f05e0ff529da1e7db47e494ebfc89498fd3c8280917268e2dadd"
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mango-deb", required=True, type=pathlib.Path)
    parser.add_argument("--adaptive-shader", type=pathlib.Path,
                        help="Optionally replace the hash using the exact private Apple Metal input; otherwise preserve it")
    args = parser.parse_args()
    package_hash = hashlib.sha256(args.mango_deb.read_bytes()).hexdigest()
    assert package_hash == SAMPLE_SHA256, "Only the supplied audited Beta9 sample is supported"
    package = read_deb(args.mango_deb)
    fields = dict(line.split(": ", 1) for line in package["control"]["control"][0].decode().splitlines() if ": " in line)
    assert fields["Package"] == "com.go.mango" and fields["Version"] == "1.0-Beta9-1"
    assert fields["Architecture"] == "iphoneos-arm64e"
    images = {name: identity(package["data"][DYNAMIC + name][0])
              for name in ("MangoPanda.dylib", "MangoHello.dylib", "MangoOSRendering.dylib")}
    destination = ROOT / "beta9-compatibility.json"
    # Preserve additional audit metadata only when it belongs to this exact sample.
    record = json.loads(destination.read_text(encoding="utf-8")) if destination.is_file() else {}
    if record:
        assert record["mangoVersion"] == "1.0-Beta9-1" and record["samplePackageSHA256"] == package_hash
    record.update({"mangoVersion": "1.0-Beta9-1", "samplePackageSHA256": package_hash, "images": images})
    if args.adaptive_shader:
        shader = args.adaptive_shader.read_bytes()
        assert 0 < len(shader) < 34000
        record["adaptiveShaderSHA256"] = hashlib.sha256(shader).hexdigest()
    destination.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(record))


if __name__ == "__main__":
    main()
