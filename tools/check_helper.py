import json
import pathlib
import plistlib
import sys
from deb import read_deb
from macho import inspect

for filename in sys.argv[1:]:
    package = read_deb(filename)
    content = package["data"]
    prefix = "Library/MobileSubstrate/DynamicLibraries/AMangoSuiteLoader"
    assert plistlib.loads(content[prefix + ".plist"][0]) == {"Filter": {"Executables": ["SpringBoard", "backboardd"]}}
    binaries = [prefix + ".dylib", "Library/PreferenceBundles/MangoSuitePrefs.bundle/MangoSuitePrefs"]
    extracted = pathlib.Path("build-info/verified-images")
    extracted.mkdir(parents=True, exist_ok=True)
    for name in binaries:
        print(json.dumps({"file": name, **inspect(content[name][0])}))
        target = extracted / pathlib.PurePosixPath(name).name
        target.write_bytes(content[name][0])
        target.chmod(0o755)
    prefs = content[binaries[1]][0]
    for string in [b"MangoSuitePrefsController", b"MangoSuiteGlassController", b"com.chenxun.mangosuite",
                   b"IdleEnabled", b"AdaptiveEnabled", b"WorldEnabled", b"SplitEnabled"]:
        assert string in prefs, string
    print("PASS: helper architecture, embedded signatures, two process scopes, and UI classes")
