"""Run the actual disk compatibility parser against inert Mach-O fixtures."""
import json
import os
import pathlib
import struct
import subprocess
import tempfile
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="mangosuite-beta8-identity-") as directory:
    work = pathlib.Path(directory)
    host = ROOT / "tests/host"
    executable = work / "compatibility-check"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror", "-I" + str(host),
                    "-framework", "Foundation", str(host / "RootHide.m"), str(host / "CompatibilityCheck.m"),
                    str(ROOT / "src/Beta8Compatibility.m"), "-o", str(executable)], check=True)
    data = json.loads((ROOT / "beta8-compatibility.json").read_text())
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
    name = "MangoHello.dylib"
    original = payloads[name]
    for altered in (original[:40] + bytes(16), original[:32], original[:36] + struct.pack("<I", 0xffffffff) + original[40:]):
        (path / name).write_bytes(altered)
        subprocess.run([str(executable), "fail"], env=env, check=True)
    (path / name).write_bytes(original)
    (path / "MangoPanda.dylib").unlink()
    subprocess.run([str(executable), "fail"], env=env, check=True)
