#!/usr/bin/env python3
import pathlib
import subprocess
import sys
import tempfile


def fail(message: str) -> None:
    raise SystemExit(message)


if len(sys.argv) != 2:
    fail("usage: check_package.py PACKAGE.deb")

package = pathlib.Path(sys.argv[1]).resolve()
if not package.is_file():
    fail(f"package not found: {package}")

with tempfile.TemporaryDirectory() as temporary:
    root = pathlib.Path(temporary)
    subprocess.run(["dpkg-deb", "-x", str(package), str(root)], check=True)
    dylibs = list(root.rglob("FaceIDOrientationProbe.dylib"))
    plists = list(root.rglob("FaceIDOrientationProbe.plist"))
    if len(dylibs) != 1 or len(plists) != 1:
        fail(f"unexpected payload: dylibs={len(dylibs)} plists={len(plists)}")
    plist_text = plists[0].read_text(encoding="utf-8", errors="strict")
    for executable in ("biometrickitd", "coreauthd"):
        if f"<string>{executable}</string>" not in plist_text:
            fail(f"missing executable filter: {executable}")
    forbidden = ("SpringBoard", "mango.dylib", "MangoUpsideDownWorld")
    for item in forbidden:
        if item in plist_text:
            fail(f"unexpected existing-project target: {item}")

print("package structure OK")
