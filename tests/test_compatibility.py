"""Run the actual disk compatibility parser against inert Mach-O fixtures."""
import json
import os
import pathlib
import struct
import subprocess
import tempfile
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="mangosuite-beta9-identity-") as directory:
    work = pathlib.Path(directory)
    host = ROOT / "tests/host"
    executable = work / "compatibility-check"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror", "-I" + str(host),
                    "-framework", "Foundation", str(host / "RootHide.m"), str(host / "CompatibilityCheck.m"),
                    str(ROOT / "src/Beta9Compatibility.m"), "-o", str(executable)], check=True)
    data = json.loads((ROOT / "mango-compatibility.json").read_text())
    path = work / "root/Library/MobileSubstrate/DynamicLibraries"
    path.mkdir(parents=True)
    env = dict(os.environ, MANGOSUITE_HOST_ROOT=str(work / "root"))
    payloads = {}
    for name, image in data["images"].items():
        payload = struct.pack("<8I", 0xfeedfacf, 0x100000c, 0x80000002, 6, 1, 24, 0, 0)
        payload += struct.pack("<II", 0x1b, 24) + uuid.UUID(image["uuid"]).bytes
        payloads[name] = payload
        (path / name).write_bytes(payload)
    subprocess.run([str(executable), "pass"], env=env, check=True)
    # Every earlier Mango build the suite was pinned to must be rejected image by image.
    legacy_builds = json.loads((ROOT / "tests/legacy-identities.json").read_text())
    for version, identities in legacy_builds.items():
        assert version != data["mangoVersion"]
        for name, legacy in identities.items():
            original = payloads[name]
            assert legacy != data["images"][name]["uuid"]
            (path / name).write_bytes(original[:40] + uuid.UUID(legacy).bytes)
            subprocess.run([str(executable), "fail"], env=env, check=True)
            (path / name).unlink()
            subprocess.run([str(executable), "fail"], env=env, check=True)
            (path / name).write_bytes(original)

    name = "MangoHello.dylib"
    original = payloads[name]
    def patch_word(offset, value):
        return original[:offset] + struct.pack("<I", value) + original[offset + 4:]
    malformed = [
        original[:40] + bytes(16), original[:32], original[:20],
        patch_word(0, 0), patch_word(4, 0x1000007), patch_word(8, 2), patch_word(12, 8),
        patch_word(16, 0), patch_word(16, 4097), patch_word(16, 2),
        patch_word(20, 0), patch_word(20, 262145),
        patch_word(36, 7), patch_word(36, 25), patch_word(36, 0xffffffff),
        patch_word(32, 0x1a),
        struct.pack("<8I", 0xfeedfacf, 0x100000c, 0x80000002, 6, 2, 48, 0, 0) + original[32:] * 2,
        patch_word(20, 32) + bytes(8),
    ]
    for altered in malformed:
        (path / name).write_bytes(altered)
        subprocess.run([str(executable), "fail"], env=env, check=True)
    (path / name).write_bytes(original)
    subprocess.run([str(executable), "pass"], env=env, check=True)
    print("PASS: installed-file guard accepts all matching images and rejects each Beta8/Beta9 UUID, missing image, invalid ABI, and malformed load-command layout", flush=True)
