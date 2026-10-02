"""Validate the delivery against its actual compiled helper and retained input."""
import argparse
import json
import pathlib
import plistlib
import posixpath
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from deb import read_deb, sha256
from assemble import (COMPILED, DIAGNOSTIC_CAPTURE, DYNAMIC, EXTRA_CONFLICTS, MODULES, NATIVE_PREFERENCE,
                      PREFS, VERSION, compatibility_metadata, control_fields,
                      helper_contents, load_inputs, verified_adaptive)
from macho import inspect
from check_directories import check_directory_members


def verify(filename, helper_path):
    directory_counts = check_directory_members(filename)
    suite = read_deb(filename)
    helper = helper_contents(helper_path)
    data = suite["data"]
    ctl = control_fields(suite["control"]["control"][0])
    assert ctl["Package"] == "com.chenxun.mangosuite"
    assert ctl["Version"] == VERSION
    assert ctl["Architecture"] == "iphoneos-arm64e"
    assert {part.strip() for part in ctl["Depends"].split(",")} == {
        "firmware (= 16.5)", "preferenceloader", "mobilesubstrate", "com.go.mango (= 1.0-Beta8-1)"}
    assert set(suite["control"]) == {"control"}, "No install-time mutation scripts allowed"
    assert sorted(n for n in data if n.startswith(DYNAMIC)) == [
        DYNAMIC + "AMangoSuiteLoader.dylib", DYNAMIC + "AMangoSuiteLoader.plist"]
    assert plistlib.loads(data[DYNAMIC + "AMangoSuiteLoader.plist"][0]) == {
        "Filter": {"Executables": ["SpringBoard", "backboardd"]}}
    entries = [n for n in data if "/PreferenceLoader/" in n]
    assert entries == ["Library/PreferenceLoader/Preferences/MangoSuitePrefs.plist"]
    entry = plistlib.loads(data[entries[0]][0])["entry"]
    assert entry["bundle"] == "MangoSuitePrefs" and entry["detail"] == "MangoSuitePrefsController"
    assert entry["isController"] is True
    bundle_info = plistlib.loads(data[PREFS + "Info.plist"][0])
    assert bundle_info.get("NSPrincipalClass") == entry["detail"]
    assert "CFBundlePrincipalClass" not in bundle_info
    links = [(n, content) for n, (content, _) in data.items() if isinstance(content, str)]
    assert sorted(links) == [(MODULES + ".jbroot", "../../.."), (PREFS + ".jbroot", "../../..")]
    for name, target in links:
        assert posixpath.normpath(posixpath.join(posixpath.dirname(name), target)) == "."
    expected_layout = json.loads((ROOT / "tests/install-layout.json").read_text(encoding="utf-8"))
    assert len(data) == 15 and set(data) == {row["path"] for row in expected_layout}, "Unexpected payload layout"
    for row in expected_layout:
        assert data[row["path"]][1] == row["mode"]
        if "link" in row:
            assert data[row["path"]][0] == row["link"]
    sources = load_inputs()
    manifest = json.loads(data["Library/MangoSuite/manifest.json"][0])
    assert manifest["suiteVersion"] == manifest["helperPackageVersion"] == VERSION
    assert manifest["helperSHA256"] == sha256(helper_path.read_bytes())
    assert re.fullmatch(r"[0-9a-f]{40}", manifest["sourceCommit"])
    compatibility, compatibility_sha = compatibility_metadata()
    assert manifest["compatibility"] == compatibility
    assert manifest["compatibilityMetadataSHA256"] == compatibility_sha
    assert manifest["nativePreference"] == NATIVE_PREFERENCE
    collector = (ROOT / "diagnostics/capture-runtime.sh").read_text(encoding="utf-8").encode("utf-8")
    assert collector.startswith(b"#!/bin/sh\n") and b"\r" not in collector
    assert data[DIAGNOSTIC_CAPTURE] == (collector, 0o644), "Changed or missing diagnostic collector"
    assert manifest["diagnostics"] == {
        "collectorPath": DIAGNOSTIC_CAPTURE, "collectorSHA256": sha256(collector),
        "loggerTTLSeconds": 1200, "loggerFileLimitBytes": 262144,
        "captureFileLimitBytes": 1048576, "repairBehaviorChanged": False,
    }
    assert set(manifest["modules"]) == set(sources)
    for name in (DYNAMIC + "AMangoSuiteLoader.dylib", DYNAMIC + "AMangoSuiteLoader.plist",
                 PREFS + "Info.plist", PREFS + "MangoSuitePrefs"):
        assert data[name] == helper["data"][name], "Changed helper component: " + name
    for label, (module, version) in COMPILED.items():
        destination = MODULES + module + ".dylib"
        assert data[destination] == helper["data"][DYNAMIC + module + ".dylib"], "Changed compiled module: " + label
        record = manifest["modules"][label]
        assert record["module"] == module and record["package"] == sources[label]["package"]
        assert record["version"] == version and record["replacesVersion"] == sources[label]["version"]
        assert record["sourceKind"] == "compiled-beta8-source"
        assert record["sourceCommit"] == manifest["sourceCommit"]
        assert record["binaryUnchanged"] is False and record["process"] == "SpringBoard"
        assert record["binarySHA256"] == sha256(data[destination][0])
    source = sources["AdaptiveColor"]
    original, original_filter = verified_adaptive(source)
    destination = MODULES + source["module"] + ".dylib"
    assert data[destination] == original["data"][DYNAMIC + source["module"] + ".dylib"]
    adaptive = manifest["modules"]["AdaptiveColor"]
    for key, value in source.items():
        assert adaptive[key] == value
    assert adaptive["sourceKind"] == "retained-original-input"
    assert adaptive["binaryUnchanged"] is True and adaptive["process"] == "backboardd"
    assert adaptive["originalFilter"] == original_filter
    assert adaptive["binarySHA256"] == sha256(data[destination][0])
    ui_names = {name for name in original["data"] if name.startswith("Library/PreferenceBundles/")}
    assert len(ui_names) == 2 and set(adaptive["uiSHA256"]) == ui_names
    for name in ui_names:
        assert data[name] == original["data"][name], "Changed AdaptiveColor UI: " + name
        assert adaptive["uiSHA256"][name] == sha256(data[name][0])
    expected_conflicts = {s["package"] for s in sources.values()} | set(EXTRA_CONFLICTS)
    assert {part.strip() for part in ctl["Conflicts"].split(",")} == expected_conflicts
    assert ctl["Replaces"] == ctl["Conflicts"]
    assert {part.strip() for part in ctl["Provides"].split(",")} == {
        f'{record["package"]} (= {record["version"]})' for record in manifest["modules"].values()}
    report = {"packageSHA256": sha256(pathlib.Path(filename).read_bytes()),
              "helperSHA256": manifest["helperSHA256"], "sourceCommit": manifest["sourceCommit"],
              "binaries": {}, "explicitDirectoryCounts": directory_counts}
    for name, (blob, mode) in data.items():
        if isinstance(blob, bytes) and blob[:4] == b"\xcf\xfa\xed\xfe":
            assert mode & 0o111
            report["binaries"][name] = inspect(blob)
    assert len(report["binaries"]) == 7  # Three rebuilt modules, Adaptive, loader, and two UI images.
    assert manifest["payloadSHA256"] == {
        name: sha256(blob) for name, (blob, _) in data.items()
        if isinstance(blob, bytes) and name != "Library/MangoSuite/manifest.json"}
    store_path = b"/var/mobile/Library/Application Support/MangoSuite/settings.plist"
    roothide = "@loader_path/.jbroot/usr/lib/libroothide.dylib"
    for name in (DYNAMIC + "AMangoSuiteLoader.dylib", PREFS + "MangoSuitePrefs"):
        assert store_path in data[name][0], "UI and loader must use the same shared store"
        assert roothide in report["binaries"][name]["dependencies"]
    for module, _ in COMPILED.values():
        assert roothide in report["binaries"][MODULES + module + ".dylib"]["dependencies"]
    for key in (NATIVE_PREFERENCE["domain"], NATIVE_PREFERENCE["key"]):
        assert key.encode() in data[PREFS + "MangoSuitePrefs"][0]
    for metadata in compatibility["images"].values():
        assert metadata["uuid"].encode() in data[DYNAMIC + "AMangoSuiteLoader.dylib"][0]
    world = data[MODULES + COMPILED["UpsideDownWorld"][0] + ".dylib"][0]
    for identity in (b"XMFloatingWindow", b"XMPortraitVC", b"MangoSuiteXiaoMang"):
        assert identity in world, "Missing compiled XiaoMang adapter: " + identity.decode()
    report["result"] = "PASS"
    report["checks"] = [
        "three compiled Beta8 modules exactly match the actual helper",
        "AdaptiveColor 0.1.3 module and UI match the verified original input",
        "seven current arm64e images and all signed code pages",
        "one Settings entry and only one automatic loader filter",
        "RootHide module and Settings bundle dependency links",
        "exact Mango Beta8 and iOS 16.5 dependencies with legacy replacement/conflicts",
        "explicit parent directories precede every archive entry",
        "fifteen payload paths and modes match the dpkg fixture layout",
        "bounded read-only diagnostic collector exactly matches normalized source and manifest",
        "source commit, helper hash, module hashes, and Beta8 image metadata recorded",
        "native upside-down domain/key remain separate from the Suite shared store",
        "XiaoMang window adapter compiled into the existing World module",
    ]
    report["deviceTested"] = False
    report["validationScope"] = "Archive, compiled-image integrity, provenance, and dependency metadata; device behavior is not inferred."
    (ROOT / "packages").mkdir(parents=True, exist_ok=True)
    (ROOT / "packages/verification.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=True, indent=2))
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=pathlib.Path)
    parser.add_argument("--helper-deb", required=True, type=pathlib.Path)
    args = parser.parse_args()
    verify(args.package, args.helper_deb)
