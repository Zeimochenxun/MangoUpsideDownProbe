"""Verify actual delivery archive, including original-image equality and signing."""
import json
import pathlib
import plistlib
import posixpath
import sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from deb import read_deb, sha256
from assemble import control_fields, MODULES, DYNAMIC
from macho import inspect
from check_directories import check_directory_members


def verify(filename):
    directory_counts = check_directory_members(filename)
    suite = read_deb(filename)
    data = suite["data"]
    ctl = control_fields(suite["control"]["control"][0])
    assert ctl["Package"] == "com.chenxun.mangosuite"
    assert ctl["Version"] == "1.0.0~alpha2"
    assert ctl["Architecture"] == "iphoneos-arm64e"
    assert "firmware (= 16.5)" in ctl["Depends"]
    assert "preferenceloader" in ctl["Depends"]
    assert set(suite["control"]) == {"control"}, "No install-time mutation scripts allowed"
    assert sorted(n for n in data if n.startswith(DYNAMIC)) == [DYNAMIC + "AMangoSuiteLoader.dylib", DYNAMIC + "AMangoSuiteLoader.plist"]
    assert plistlib.loads(data[DYNAMIC + "AMangoSuiteLoader.plist"][0]) == {"Filter": {"Executables": ["SpringBoard", "backboardd"]}}
    entries = [n for n in data if "/PreferenceLoader/" in n]
    assert entries == ["Library/PreferenceLoader/Preferences/MangoSuitePrefs.plist"]
    entry = plistlib.loads(data[entries[0]][0])["entry"]
    assert entry["bundle"] == "MangoSuitePrefs" and entry["detail"] == "MangoSuitePrefsController"
    links = [(n, content) for n, (content, _) in data.items() if isinstance(content, str)]
    assert links == [(MODULES + ".jbroot", "../../..")]
    assert posixpath.normpath(posixpath.join(MODULES, links[0][1])) == "."
    sources = json.loads((ROOT / "inputs/sources.json").read_text())
    report = {"packageSHA256": sha256(pathlib.Path(filename).read_bytes()), "binaries": {}, "explicitDirectoryCounts": directory_counts}
    expected_layout = json.loads((ROOT / "tests/install-layout.json").read_text())
    assert set(data) == {row["path"] for row in expected_layout}, "Final package differs from the dpkg-tested path layout"
    manifest = json.loads(data["Library/MangoSuite/manifest.json"][0])
    for label, source in sources.items():
        original_path = ROOT / "inputs" / source["file"]
        assert sha256(original_path.read_bytes()) == source["sha256"]
        original = read_deb(original_path)
        source_blob = original["data"][DYNAMIC + source["module"] + ".dylib"][0]
        destination = MODULES + source["module"] + ".dylib"
        assert source_blob == data[destination][0], f"Changed original module: {label}"
        assert manifest["modules"][label]["binarySHA256"] == sha256(source_blob)
        assert source["package"] in ctl["Conflicts"] and source["package"] in ctl["Replaces"]
        assert f'{source["package"]} (= {source["version"]})' in ctl["Provides"]
    assert "com.chenxun.mangoupsidedownfix" in ctl["Conflicts"]
    assert "com.chenxun.mangoorientationprobe" in ctl["Conflicts"]
    for name, (blob, mode) in data.items():
        if isinstance(blob, bytes) and blob[:4] == b"\xcf\xfa\xed\xfe":
            assert mode & 0o111
            report["binaries"][name] = inspect(blob)
    assert len(report["binaries"]) == 7  # Four original modules + loader + two UI images.
    report["result"] = "PASS"
    report["checks"] = ["four exact versions", "unchanged original module hashes", "arm64e ABI",
                         "all signed code pages", "one settings entry", "isolated process routing",
                         "RootHide module dependency link", "legacy package replacement/conflicts",
                         "explicit parent directories precede every archive entry", "dpkg fixture layout matches final package"]
    report["deviceTested"] = False
    (ROOT / "packages/verification.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=True, indent=2))


if __name__ == "__main__":
    verify(sys.argv[1])
