"""Use real Linux dpkg in isolated roots with the delivery's exact path layout.

Binary payload bytes are inert fixtures; signed iOS modules remain local. The
actual diagnostic shell source is installed and parsed, never run. Reproduce
the old missing-directory failure, then verify initial unpack and upgrades.
"""
import gzip
import io
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import deb
from check_directories import check_directory_members
from assemble import DIAGNOSTIC_CAPTURE


def legacy_tar(files):
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        for path, (data, mode) in sorted(files.items()):
            info = tarfile.TarInfo("./" + path)
            info.mode = mode
            if isinstance(data, str):
                info.type, info.linkname = tarfile.SYMTYPE, data
                archive.addfile(info)
            else:
                info.size = len(data)
                archive.addfile(info, io.BytesIO(data))
    return gzip.compress(buffer.getvalue(), mtime=0)


class DpkgInstallTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("dpkg") or not shutil.which("dpkg-deb"):
            raise RuntimeError("Real dpkg is required; this test must not silently skip")
        cls.layout = json.loads((ROOT / "tests/install-layout.json").read_text())
        assert len(cls.layout) == 15 and len({r["path"] for r in cls.layout}) == 15
        assert next(r for r in cls.layout if r["path"] == DIAGNOSTIC_CAPTURE)["mode"] == 0o644
        cls.collector = (ROOT / "diagnostics/capture-runtime.sh").read_text(encoding="utf-8").encode("utf-8")
        assert cls.collector.startswith(b"#!/bin/sh\n") and b"\r" not in cls.collector
        cls.shell = shutil.which("sh")
        if not cls.shell:
            raise RuntimeError("Shell syntax validation is required; this test must not silently skip")

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mangosuite-dpkg-")
        self.addCleanup(self.temporary.cleanup)
        self.work = pathlib.Path(self.temporary.name)
        self.root = self.work / "isolated-root"
        self.admin = self.root / "var/lib/dpkg"
        self.admin.mkdir(parents=True)
        (self.admin / "status").write_text("")

    def package(self, version, faulty=False):
        data = {r["path"]: (r.get("link", ("inert fixture " + version + "\n").encode()), r["mode"]) for r in self.layout}
        data[DIAGNOSTIC_CAPTURE] = (self.collector, 0o644)
        control = ("Package: com.chenxun.mangosuite\nVersion: " + version + "\nArchitecture: iphoneos-arm64e\n"
                   "Maintainer: Test <test@example.invalid>\nDescription: Isolated directory unpack regression\n").encode()
        destination = self.work / (version + ".deb")
        original = deb.make_tar
        try:
            if faulty:
                deb.make_tar = legacy_tar
            deb.write_deb(destination, {"control": (control, 0o644)}, data)
        finally:
            deb.make_tar = original
        return destination, data

    def unpack(self, package):
        assert self.root.is_relative_to(self.work) and self.root != pathlib.Path("/")
        command = ["dpkg", "--root=" + str(self.root), "--admindir=" + str(self.admin),
                   "--force-architecture", "--force-not-root", "--unpack", str(package)]
        result = subprocess.run(command, capture_output=True, text=True, env={**os.environ, "LC_ALL": "C"}, timeout=30)
        return result.returncode, result.stdout + result.stderr

    def assert_payload(self, expected):
        for name, (value, mode) in expected.items():
            path = self.root / name
            if isinstance(value, str):
                self.assertTrue(path.is_symlink())
                self.assertEqual(os.readlink(path), value)
            else:
                self.assertEqual(path.read_bytes(), value)
                self.assertEqual(path.stat().st_mode & 0o777, mode)
        self.assertFalse(list(self.root.rglob("*.dpkg-new")))
        self.assertEqual((self.root / "Library/MangoSuite/Modules/.jbroot").resolve(), self.root.resolve())
        self.assertEqual((self.root / "Library/PreferenceBundles/MangoSuitePrefs.bundle/.jbroot").resolve(), self.root.resolve())

    def test_old_archive_reproduces_missing_parent(self):
        package, _ = self.package("1.0.0~alpha1", faulty=True)
        with self.assertRaisesRegex(AssertionError, "Missing preceding directory"):
            check_directory_members(package)
        code, log = self.unpack(package)
        self.assertNotEqual(code, 0, log)
        self.assertIn("No such file or directory", log)
        # dpkg stops at the first sorted payload, now the diagnostic collector.
        # Require its exact failed create path; the missing-parent negative
        # control still proves the actual unpack failure, not just any error.
        failed_target = str(self.root / DIAGNOSTIC_CAPTURE) + ".dpkg-new"
        self.assertIn("unable to create '" + failed_target + "'", log)
        self.assertIn("while processing './" + DIAGNOSTIC_CAPTURE + "'", log)
        print("REPRODUCED: old archive fails real dpkg with missing parent directory", flush=True)

    def test_fixed_archive_installs_on_empty_root(self):
        package, expected = self.package("1.0.0~alpha4")
        check_directory_members(package)
        code, log = self.unpack(package)
        self.assertEqual(code, 0, log)
        self.assert_payload(expected)

    def test_install_after_failed_old_unpack(self):
        old, _ = self.package("1.0.0~alpha1", faulty=True)
        self.assertNotEqual(self.unpack(old)[0], 0)
        fixed, expected = self.package("1.0.0~alpha4")
        code, log = self.unpack(fixed)
        self.assertEqual(code, 0, log)
        self.assert_payload(expected)

    def test_diagnostic_collector_installs_with_source_and_valid_shell_syntax(self):
        package, expected = self.package("1.1.0~beta8.4.1")
        check_directory_members(package)
        code, log = self.unpack(package)
        self.assertEqual(code, 0, log)
        self.assert_payload(expected)
        installed = self.root / DIAGNOSTIC_CAPTURE
        self.assertEqual(installed.read_bytes(), self.collector)
        parsed = subprocess.run([self.shell, "-n", str(installed)], capture_output=True, text=True, timeout=10)
        self.assertEqual(parsed.returncode, 0, parsed.stdout + parsed.stderr)
        print("PASS: actual diagnostic collector installed with explicit parent directories, exact source/mode, and valid shell syntax", flush=True)

    def test_upgrade_preserves_preferences(self):
        older, _ = self.package("1.0.0~alpha1")
        self.assertEqual(self.unpack(older)[0], 0)
        preferences = self.root / "var/mobile/Library/Preferences/com.chenxun.mangosuite.plist"
        preferences.parent.mkdir(parents=True)
        preferences.write_bytes(b"user preferences must survive")
        shared = self.root / "var/mobile/Library/Application Support/MangoSuite/settings.plist"
        shared.parent.mkdir(parents=True)
        shared.write_bytes(b"saved suite switch selections must survive")
        fixed, expected = self.package("1.0.0~alpha4")
        code, log = self.unpack(fixed)
        self.assertEqual(code, 0, log)
        self.assert_payload(expected)
        self.assertEqual(preferences.read_bytes(), b"user preferences must survive")
        self.assertEqual(shared.read_bytes(), b"saved suite switch selections must survive")


if __name__ == "__main__":
    unittest.main(verbosity=2)
