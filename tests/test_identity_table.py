"""src/MangoIdentity.h (the only place UUIDs are pinned) must agree with mango-compatibility.json."""
import json
import pathlib
import re
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
header = (ROOT / "src/MangoIdentity.h").read_text(encoding="utf-8")
record = json.loads((ROOT / "mango-compatibility.json").read_text(encoding="utf-8"))


def macro(name):
    return re.search(r"^#define " + name + r"\s+(.+)$", header, re.M).group(1).strip()


assert macro("MS_MANGO_VERSION") == '"' + record["mangoVersion"] + '"'
for label, image in (("HELLO", "MangoHello.dylib"), ("PANDA", "MangoPanda.dylib"), ("RENDERING", "MangoOSRendering.dylib")):
    expected = record["images"][image]["uuid"]
    assert macro(f"MS_{label}_UUID") == '"' + expected + '"', image
    if label != "RENDERING":  # the loader checks Rendering by string only
        written = bytes(int(x, 16) for x in re.findall(r"0x([0-9a-f]{2})", macro(f"MS_{label}_UUID_BYTES")))
        assert written == uuid.UUID(expected).bytes, image + " byte form"
assert int(macro("MS_ADAPTIVE_SUPPORTED")) == int(record.get("adaptiveSupported", False))
# No other source may pin a UUID of its own.
literal = re.compile(r"[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}")
for name in ("src/Beta9Compatibility.m", "modules/orientation/Beta9Identity.h", "src/Loader.m"):
    assert not literal.search((ROOT / name).read_text(encoding="utf-8")), name + " pins a UUID outside MangoIdentity.h"
print("PASS: MangoIdentity.h matches mango-compatibility.json (version, three UUIDs, byte forms, adaptive flag)")
