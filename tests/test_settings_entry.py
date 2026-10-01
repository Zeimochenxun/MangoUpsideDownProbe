"""Exercise NSBundle's real principal-class resolution with the actual UI source.

Uses host shims for private iOS classes on a macOS runner. This checks root
selection and specifier construction, not physical iPhone UI rendering.
"""
import pathlib
import os
import plistlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="mangosuite-entry-") as directory:
    work = pathlib.Path(directory)
    host = ROOT / "tests/host"
    common = ["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror", "-I" + str(host), "-framework", "Foundation", "-framework", "CoreFoundation"]
    shared = [str(host / "RootHide.m"), str(ROOT / "src/SuitePreferences.m")]
    subprocess.run(common + [str(host / "Support.m"), str(host / "EntryCheck.m")] + shared + ["-Wl,-export_dynamic", "-o", str(work / "entry-check")], check=True)
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
    env = dict(os.environ, MANGOSUITE_HOST_ROOT=str(work / "jbroot"))
    for bundle, expected in ((broken, "MangoSuiteGlassController"), (fixed, "MangoSuitePrefsController")):
        subprocess.run([str(work / "entry-check"), str(bundle), expected], env=env, check=True)

    subprocess.run(common + [str(host / "Support.m"), str(host / "SaveCheck.m")] + shared + ["-Wl,-export_dynamic", "-o", str(work / "save-check")], check=True)
    subprocess.run(common + [str(host / "PersistenceCheck.m")] + shared + ["-o", str(work / "readback-check")], check=True)
    legacy = work / "LegacySave.bundle"
    legacy.mkdir()
    subprocess.run(common + ["-bundle", "-undefined", "dynamic_lookup", str(ROOT / "prefs/GlassPage.m"), str(ROOT / "tests/fixtures/Prefs.alpha3.m"), "-o", str(legacy / executable)], check=True)
    fixed_info = plistlib.loads((fixed / "Info.plist").read_bytes())
    (legacy / "Info.plist").write_bytes(plistlib.dumps(fixed_info))
    subprocess.run([str(work / "save-check"), str(legacy), "reproduce-save"], env=env, check=True)
    subprocess.run([str(work / "save-check"), str(fixed), "combinations"], env=env, check=True)
    subprocess.run([str(work / "readback-check"), "21"], env=env, check=True)
    store = pathlib.Path(env["MANGOSUITE_HOST_ROOT"]) / "var/mobile/Library/Application Support/MangoSuite/settings.plist"
    assert plistlib.loads(store.read_bytes()) == dict(zip(("Enabled", "IdleEnabled", "AdaptiveEnabled", "WorldEnabled", "SplitEnabled"), (True, False, True, False, True)))

    migration_root = work / "migration-jbroot"
    old = migration_root / "var/mobile/Library/Preferences/com.chenxun.mangosuite.plist"
    old.parent.mkdir(parents=True)
    old_state = {"Enabled": True, "IdleEnabled": False, "AdaptiveEnabled": True, "WorldEnabled": False, "SplitEnabled": True, "futureSetting": "preserve"}
    old.write_bytes(plistlib.dumps(old_state))
    migration_env = dict(env, MANGOSUITE_HOST_ROOT=str(migration_root))
    subprocess.run([str(work / "save-check"), str(fixed), "migrate"], env=migration_env, check=True)
    subprocess.run([str(work / "readback-check"), "23"], env=migration_env, check=True)
    assert plistlib.loads(old.read_bytes()) == old_state
    migrated = migration_root / "var/mobile/Library/Application Support/MangoSuite/settings.plist"
    assert plistlib.loads(migrated.read_bytes()) == dict(old_state, IdleEnabled=True)

    before = store.read_bytes()
    store.parent.chmod(0o555)
    try:
        subprocess.run([str(work / "save-check"), str(fixed), "failure"], env=env, check=True)
        assert store.read_bytes() == before
    finally:
        store.parent.chmod(0o755)
    store.write_bytes(b"corrupt settings must not be overwritten")
    subprocess.run([str(work / "save-check"), str(fixed), "failure"], env=env, check=True)
    assert store.read_bytes() == b"corrupt settings must not be overwritten"
    print("PASS: atomic-write failure and corrupt settings do not reset saved data", flush=True)
