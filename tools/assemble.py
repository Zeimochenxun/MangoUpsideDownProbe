"""Assemble Beta8 source modules plus the retained AdaptiveColor 0.1.3 images."""
import argparse
import json
import math
import pathlib
import plistlib
import re
import struct
from deb import read_deb, sha256, write_deb

ROOT = pathlib.Path(__file__).resolve().parents[1]
DYNAMIC = "Library/MobileSubstrate/DynamicLibraries/"
MODULES = "Library/MangoSuite/Modules/"
PREFS = "Library/PreferenceBundles/MangoSuitePrefs.bundle/"
VERSION = "1.1.0~beta8.3"
OUTPUT_NAME = "MangoSuite-1.1.0-Beta8.3-RootHide-arm64e.deb"
COMPILED = {
    "IdleIsland": ("MangoIdleIsland", "1.1.9.3~beta8.3"),
    "UpsideDownWorld": ("MangoUpsideDownWorld", "1.3.0~beta8.3"),
    "SplitUpsideDownFix": ("MangoSplitUpsideDownFix", "0.1.1~beta8.3"),
}
NATIVE_PREFERENCE = {
    "domain": "com.go.mangoosprefs",
    "key": "LeXiang.UpsideDown.Enabled",
    "independentOfSuiteMaster": True,
}
EXTRA_CONFLICTS = ["local.mango.upsidedownprefs", "com.chenxun.mangoupsidedownfix",
                   "com.chenxun.mangoorientationprobe"]


def control_fields(blob):
    return dict(line.split(": ", 1) for line in blob.decode().splitlines() if ": " in line)


def arm64e(data, filetypes=(6,)):
    magic, cpu, subtype, filetype = struct.unpack_from("<4I", data)
    assert (magic, cpu, subtype) == (0xfeedfacf, 0x100000c, 0x80000002), "Current arm64e ABI required"
    assert filetype in filetypes, "Unexpected Mach-O file type"


def load_inputs():
    sources = json.loads((ROOT / "inputs/sources.json").read_text(encoding="utf-8"))
    assert set(sources) == set(COMPILED) | {"AdaptiveColor"}
    for label, (module, _) in COMPILED.items():
        assert sources[label]["module"] == module
    assert sources["AdaptiveColor"]["module"] == "MangoIslandAdaptiveColor"
    assert sources["AdaptiveColor"]["version"] == "0.1.3"
    return sources


def verified_adaptive(source):
    path = ROOT / "inputs" / source["file"]
    assert sha256(path.read_bytes()) == source["sha256"], "AdaptiveColor input checksum mismatch"
    package = read_deb(path)
    fields = control_fields(package["control"]["control"][0])
    assert fields["Package"] == source["package"]
    assert fields["Version"] == source["version"]
    assert fields["Architecture"] == "iphoneos-arm64e"
    module = source["module"]
    arm64e(package["data"][DYNAMIC + module + ".dylib"][0])
    original_filter = plistlib.loads(package["data"][DYNAMIC + module + ".plist"][0])
    assert original_filter == {"Filter": {"Bundles": ["com.apple.backboardd"]}}
    return package, original_filter


def compatibility_metadata():
    blob = (ROOT / "beta8-compatibility.json").read_bytes()
    metadata = json.loads(blob)
    assert metadata["mangoVersion"] == "1.0-Beta8-1"
    assert set(metadata["images"]) == {"MangoPanda.dylib", "MangoHello.dylib", "MangoOSRendering.dylib"}
    return metadata, sha256(blob)


def helper_contents(helper_path):
    helper = read_deb(helper_path)
    fields = control_fields(helper["control"]["control"][0])
    assert fields["Package"] == "com.chenxun.mangosuite.helper"
    assert fields["Version"] == VERSION
    assert fields["Architecture"] == "iphoneos-arm64e"
    required = {DYNAMIC + "AMangoSuiteLoader.dylib", DYNAMIC + "AMangoSuiteLoader.plist",
                PREFS + "Info.plist", PREFS + "MangoSuitePrefs"}
    required |= {DYNAMIC + module + ".dylib" for module, _ in COMPILED.values()}
    optional = {DYNAMIC + module + ".plist" for module, _ in COMPILED.values()}
    optional |= {PREFS + ".jbroot", "Library/PreferenceLoader/Preferences/MangoSuitePrefs.plist"}
    assert required <= set(helper["data"]), "Compiled helper is missing a Beta8 component"
    assert set(helper["data"]) <= required | optional, "Unexpected helper payload"
    assert plistlib.loads(helper["data"][DYNAMIC + "AMangoSuiteLoader.plist"][0]) == {
        "Filter": {"Executables": ["SpringBoard", "backboardd"]}}
    for module, _ in COMPILED.values():
        arm64e(helper["data"][DYNAMIC + module + ".dylib"][0])
        filter_path = DYNAMIC + module + ".plist"
        if filter_path in helper["data"]:
            assert plistlib.loads(helper["data"][filter_path][0]) == {
                "Filter": {"Executables": ["SpringBoard"]}}
    arm64e(helper["data"][DYNAMIC + "AMangoSuiteLoader.dylib"][0])
    arm64e(helper["data"][PREFS + "MangoSuitePrefs"][0], (6, 8))
    info = plistlib.loads(helper["data"][PREFS + "Info.plist"][0])
    assert info.get("NSPrincipalClass") == "MangoSuitePrefsController"
    return helper


def assemble(helper_path, output, source_commit):
    assert re.fullmatch(r"[0-9a-f]{40}", source_commit), "An exact build source commit is required"
    sources = load_inputs()
    helper = helper_contents(helper_path)
    compatibility, compatibility_sha = compatibility_metadata()
    retained = (DYNAMIC + "AMangoSuiteLoader.dylib", DYNAMIC + "AMangoSuiteLoader.plist",
                PREFS + "Info.plist", PREFS + "MangoSuitePrefs")
    data = {name: helper["data"][name] for name in retained}
    # Only the loader is injected automatically. All module filters are removed.
    entry = {"entry": {"cell": "PSLinkCell", "label": "Mango 整合", "bundle": "MangoSuitePrefs",
                       "detail": "MangoSuitePrefsController", "isController": True}}
    data["Library/PreferenceLoader/Preferences/MangoSuitePrefs.plist"] = (plistlib.dumps(entry), 0o644)
    manifest = {
        "suiteVersion": VERSION, "sourceCommit": source_commit,
        "helperSHA256": sha256(helper_path.read_bytes()), "helperPackageVersion": VERSION,
        "compatibility": compatibility, "compatibilityMetadataSHA256": compatibility_sha,
        "nativePreference": NATIVE_PREFERENCE, "modules": {},
    }
    for label, (module, version) in COMPILED.items():
        binary, mode = helper["data"][DYNAMIC + module + ".dylib"]
        data[MODULES + module + ".dylib"] = (binary, mode)
        manifest["modules"][label] = {
            "module": module, "package": sources[label]["package"], "version": version,
            "sourceKind": "compiled-beta8-source", "sourceCommit": source_commit,
            "binarySHA256": sha256(binary), "binaryUnchanged": False,
            "replacesVersion": sources[label]["version"], "process": "SpringBoard",
        }
    source = sources["AdaptiveColor"]
    adaptive, original_filter = verified_adaptive(source)
    module = source["module"]
    binary, mode = adaptive["data"][DYNAMIC + module + ".dylib"]
    data[MODULES + module + ".dylib"] = (binary, mode)
    ui = {name: item for name, item in adaptive["data"].items()
          if name.startswith("Library/PreferenceBundles/")}
    adaptive_prefs = "Library/PreferenceBundles/MangoIslandAdaptiveColorPrefs.bundle/"
    assert set(ui) == {adaptive_prefs + "Info.plist", adaptive_prefs + "MangoIslandAdaptiveColorPrefs"}
    data.update(ui)
    manifest["modules"]["AdaptiveColor"] = {
        **source, "sourceKind": "retained-original-input", "binarySHA256": sha256(binary),
        "binaryUnchanged": True, "originalFilter": original_filter, "process": "backboardd",
        "uiSHA256": {name: sha256(item[0]) for name, item in sorted(ui.items())},
    }
    # Both locations resolve @loader_path/.jbroot into the RootHide root.
    data[MODULES + ".jbroot"] = ("../../..", 0o777)
    data[PREFS + ".jbroot"] = ("../../..", 0o777)
    manifest["payloadSHA256"] = {name: sha256(blob) for name, (blob, _) in sorted(data.items())
                                  if isinstance(blob, bytes)}
    data["Library/MangoSuite/manifest.json"] = (json.dumps(manifest, ensure_ascii=False, indent=2).encode(), 0o644)
    installed_size = sum(math.ceil(len(blob) / 1024) for blob, _ in data.values() if isinstance(blob, bytes))
    original_ids = [s["package"] for s in sources.values()]
    conflicts = original_ids + EXTRA_CONFLICTS
    provides = [f'{module["package"]} (= {module["version"]})' for module in manifest["modules"].values()]
    control = "\n".join([
        "Package: com.chenxun.mangosuite", "Name: Mango Suite", "Version: " + VERSION,
        "Architecture: iphoneos-arm64e", "Section: Tweaks", "Maintainer: Chen Xun", "Author: Chen Xun",
        "Description: Mango Beta8 suite with source-built modules, retained AdaptiveColor 0.1.3, and one Settings panel for iOS 16.5 RootHide.",
        "Depends: mobilesubstrate, preferenceloader, firmware (= 16.5), com.go.mango (= 1.0-Beta8-1)",
        "Conflicts: " + ", ".join(conflicts), "Replaces: " + ", ".join(conflicts),
        "Provides: " + ", ".join(provides), f"Installed-Size: {installed_size}", "",
    ]).encode()
    expected_layout = json.loads((ROOT / "tests/install-layout.json").read_text(encoding="utf-8"))
    assert len(data) == 14 and set(data) == {row["path"] for row in expected_layout}
    for row in expected_layout:
        blob, mode = data[row["path"]]
        assert mode == row["mode"], (row["path"], mode)
        if "link" in row:
            assert blob == row["link"]
    output.parent.mkdir(parents=True, exist_ok=True)
    write_deb(output, {"control": (control, 0o644)}, data)
    manifest["outputSHA256"] = sha256(output.read_bytes())
    output.with_suffix(".manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"package": str(output), "sha256": manifest["outputSHA256"],
                      "files": len(data), "sourceCommit": source_commit}, ensure_ascii=True))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--helper-deb", required=True, type=pathlib.Path)
    parser.add_argument("--source-commit", required=True, help="40-character commit used to build the helper")
    parser.add_argument("--output", type=pathlib.Path, default=ROOT / "packages" / OUTPUT_NAME)
    args = parser.parse_args()
    assemble(args.helper_deb, args.output, args.source_commit)
