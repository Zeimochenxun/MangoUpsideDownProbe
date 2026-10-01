"""Assemble one installable suite from verified originals + the compiled helper."""
import argparse
import json
import math
import pathlib
import plistlib
import struct
from deb import read_deb, sha256, write_deb

ROOT = pathlib.Path(__file__).resolve().parents[1]
DYNAMIC = "Library/MobileSubstrate/DynamicLibraries/"
MODULES = "Library/MangoSuite/Modules/"


def control_fields(blob):
    return dict(line.split(": ", 1) for line in blob.decode().splitlines() if ": " in line)


def arm64e(data):
    magic, cpu, subtype, filetype = struct.unpack_from("<4I", data)
    assert (magic, cpu, subtype & 0xffffff, filetype) == (0xfeedfacf, 0x100000c, 2, 6)
    assert subtype & 0x80000000, "arm64e ABI flag must be present"


def assemble(helper_path, output):
    sources = json.loads((ROOT / "inputs/sources.json").read_text())
    helper = read_deb(helper_path)
    helper_control = control_fields(helper["control"]["control"][0])
    assert helper_control["Architecture"] == "iphoneos-arm64e"
    assert helper_control["Package"] == "com.chenxun.mangosuite.helper"
    data = {}
    for name, item in helper["data"].items():
        assert name.startswith(DYNAMIC + "AMangoSuiteLoader.") or name.startswith("Library/PreferenceBundles/MangoSuitePrefs.bundle/") or name == "Library/PreferenceLoader/Preferences/MangoSuitePrefs.plist", name
        data[name] = item
    assert DYNAMIC + "AMangoSuiteLoader.dylib" in data
    assert "Library/PreferenceBundles/MangoSuitePrefs.bundle/MangoSuitePrefs" in data
    # The final package, not the helper, owns the only visible Settings entry.
    entry = {"entry": {"cell": "PSLinkCell", "label": "Mango 整合", "bundle": "MangoSuitePrefs",
                       "detail": "MangoSuitePrefsController", "isController": True}}
    data["Library/PreferenceLoader/Preferences/MangoSuitePrefs.plist"] = (plistlib.dumps(entry), 0o644)
    manifest = {"suiteVersion": "1.0.0~alpha2", "helperSHA256": sha256(helper_path.read_bytes()), "modules": {}}
    for label, source in sources.items():
        path = ROOT / "inputs" / source["file"]
        assert sha256(path.read_bytes()) == source["sha256"], f"Input checksum mismatch: {label}"
        package = read_deb(path)
        fields = control_fields(package["control"]["control"][0])
        assert fields["Package"] == source["package"]
        assert fields["Version"] == source["version"]
        assert fields["Architecture"] == "iphoneos-arm64e"
        module = source["module"]
        binary, mode = package["data"][DYNAMIC + module + ".dylib"]
        arm64e(binary)
        original_filter = plistlib.loads(package["data"][DYNAMIC + module + ".plist"][0])
        expected_filter = {"Filter": {"Bundles": ["com.apple.backboardd"]}} if label == "AdaptiveColor" else {"Filter": {"Bundles": ["com.apple.springboard"]}}
        assert original_filter == expected_filter, (label, original_filter)
        data[MODULES + module + ".dylib"] = (binary, mode)
        # AdaptiveColor 0.1.3's exact UI binary is available and retained.
        # The Idle page is rebuilt into the unified UI to explain shader priority.
        if label == "AdaptiveColor":
            for name, item in package["data"].items():
                if name.startswith("Library/PreferenceBundles/"):
                    data[name] = item
        manifest["modules"][label] = {**source, "binarySHA256": sha256(binary),
                                       "originalFilter": original_filter, "binaryUnchanged": True}
    # The original signed images reference @loader_path/.jbroot/usr/lib/...
    # Three parents from Library/MangoSuite/Modules is the jailbreak root.
    data[MODULES + ".jbroot"] = ("../../..", 0o777)
    data["Library/MangoSuite/manifest.json"] = (json.dumps(manifest, ensure_ascii=False, indent=2).encode(), 0o644)
    installed_size = sum(math.ceil(len(blob)/1024) for blob, _ in data.values() if isinstance(blob, bytes))
    original_ids = [s["package"] for s in sources.values()]
    conflicts = original_ids + ["com.chenxun.mangoupsidedownfix", "com.chenxun.mangoorientationprobe"]
    provides = [f'{s["package"]} (= {s["version"]})' for s in sources.values()]
    control = "\n".join([
        "Package: com.chenxun.mangosuite", "Name: Mango Suite", "Version: 1.0.0~alpha2",
        "Architecture: iphoneos-arm64e", "Section: Tweaks", "Maintainer: Chen Xun", "Author: Chen Xun",
        "Description: Unified Mango patch suite with independent startup switches and a single Settings panel. Requires Mango on iOS 16.5 RootHide.",
        "Depends: mobilesubstrate, preferenceloader, firmware (= 16.5)",
        "Conflicts: " + ", ".join(conflicts),
        "Replaces: " + ", ".join(original_ids + ["com.chenxun.mangoupsidedownfix"]),
        "Provides: " + ", ".join(provides), f"Installed-Size: {installed_size}", "",
    ]).encode()
    write_deb(output, {"control": (control, 0o644)}, data)
    manifest["outputSHA256"] = sha256(output.read_bytes())
    evidence = output.with_suffix(".manifest.json")
    evidence.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"package": str(output), "sha256": manifest["outputSHA256"], "files": len(data)}, ensure_ascii=True))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--helper-deb", required=True, type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path, default=ROOT / "packages/MangoSuite-1.0.0-alpha2-RootHide-arm64e.deb")
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    assemble(args.helper_deb, args.output)
