"""Exercise NSBundle's real principal-class resolution with the actual UI source.

Uses host shims for private iOS classes on a macOS runner. This checks root
selection and specifier construction, not physical iPhone UI rendering.
"""
import pathlib
import plistlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="mangosuite-entry-") as directory:
    work = pathlib.Path(directory)
    host = ROOT / "tests/host"
    common = ["xcrun", "clang", "-fobjc-arc", "-fblocks", "-I" + str(host), "-framework", "Foundation", "-framework", "CoreFoundation"]
    subprocess.run(common + [str(host / "Support.m"), str(host / "EntryCheck.m"), "-Wl,-export_dynamic", "-o", str(work / "entry-check")], check=True)
    fixed = work / "Fixed.bundle"
    broken = work / "Broken.bundle"
    fixed.mkdir()
    broken.mkdir()
    # Deliberately link the glass controller first to reproduce the former
    # wildcard order. Correct metadata must still select the root controller.
    executable = "HostMangoSuitePrefs"
    subprocess.run(common + ["-bundle", "-undefined", "dynamic_lookup", str(ROOT / "prefs/GlassPage.m"), str(ROOT / "prefs/Prefs.m"), "-o", str(fixed / executable)], check=True)
    info = plistlib.loads((ROOT / "prefs/Resources/Info.plist").read_bytes())
    assert info["NSPrincipalClass"] == "MangoSuitePrefsController"
    info["CFBundleExecutable"] = executable
    (fixed / "Info.plist").write_bytes(plistlib.dumps(info))
    shutil.copy2(fixed / executable, broken / executable)
    del info["NSPrincipalClass"]
    info["CFBundlePrincipalClass"] = "MangoSuitePrefsController"
    (broken / "Info.plist").write_bytes(plistlib.dumps(info))
    for bundle, expected in ((broken, "MangoSuiteGlassController"), (fixed, "MangoSuitePrefsController")):
        subprocess.run([str(work / "entry-check"), str(bundle), expected], check=True)
