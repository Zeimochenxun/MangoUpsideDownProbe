"""Record read-only compatibility identifiers from the supplied Beta8 sample."""
import hashlib
import json
import pathlib
import struct
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
AUDIT = ROOT.parent / "审查结果/Mango-Beta8-屏幕倒置"

def identity(blob):
    magic, cpu, subtype, kind, count, size = struct.unpack_from("<6I", blob)
    assert magic == 0xfeedfacf and cpu == 0x100000c
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
    path = AUDIT / "extracted/data/Library/MobileSubstrate/DynamicLibraries"
    images = {name: identity((path / name).read_bytes()) for name in ("MangoPanda.dylib", "MangoHello.dylib", "MangoOSRendering.dylib")}
    source = json.loads((AUDIT / "manifest.json").read_text(encoding="utf-8"))["source"]
    package_hash = hashlib.sha256(pathlib.Path(source).read_bytes()).hexdigest()
    assert package_hash == "8dcb0e02c4402a4dfa92f64b9e3894386a03db327f5eb83f72b795c4c8b5378f"
    record = {"mangoVersion": "1.0-Beta8-1", "samplePackageSHA256": package_hash, "images": images}
    (ROOT / "beta8-compatibility.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(record))

if __name__ == "__main__": main()
