import json
import pathlib
import plistlib
import sys
from deb import read_deb
from macho import inspect
from assemble import VERSION

for filename in sys.argv[1:]:
    package = read_deb(filename)
    content = package["data"]
    prefix = "Library/MobileSubstrate/DynamicLibraries/AMangoSuiteLoader"
    assert plistlib.loads(content[prefix + ".plist"][0]) == {"Filter": {"Executables": ["SpringBoard", "backboardd"]}}
    binaries = [prefix + ".dylib", "Library/PreferenceBundles/MangoSuitePrefs.bundle/MangoSuitePrefs"]
    for module in ("MangoIdleIsland", "MangoUpsideDownWorld", "MangoSplitUpsideDownFix"):
        path = "Library/MobileSubstrate/DynamicLibraries/" + module
        assert plistlib.loads(content[path + ".plist"][0]) == {"Filter": {"Executables": ["SpringBoard"]}}
        binaries.append(path + ".dylib")
    info = plistlib.loads(content["Library/PreferenceBundles/MangoSuitePrefs.bundle/Info.plist"][0])
    assert info.get("NSPrincipalClass") == "MangoSuitePrefsController"
    assert "CFBundlePrincipalClass" not in info
    extracted = pathlib.Path("build-info/verified-images")
    extracted.mkdir(parents=True, exist_ok=True)
    for name in binaries:
        print(json.dumps({"file": name, **inspect(content[name][0])}))
        target = extracted / pathlib.PurePosixPath(name).name
        target.write_bytes(content[name][0])
        target.chmod(0o755)
    prefs = content[binaries[1]][0]
    assert ("version=" + VERSION).encode() in content[binaries[0]][0], "Loader version was not migrated"
    for string in [b"MangoSuitePrefsController", b"MangoSuiteGlassController", b"com.chenxun.mangosuite",
                   b"IdleEnabled", b"AdaptiveEnabled", b"WorldEnabled", b"SplitEnabled",
                   b"LeXiang.UpsideDown.Enabled", b"com.go.mangoosprefs"]:
        assert string in prefs, string
    print("PASS: five compiled images, current arm64e ABI, signatures, process scopes, and native Settings integration")
