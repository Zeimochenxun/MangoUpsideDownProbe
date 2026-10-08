"""Execute production crash export and hook-free recording on macOS.

Filesystem and loader fixtures are host tests, not iPhone crash verification.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="mango-crash-isolation-") as temporary:
    work=Path(temporary)
    host=ROOT/"tests/host"
    common=["xcrun","clang","-fobjc-arc","-fblocks","-Wall","-Wextra","-Werror","-I"+str(host),"-framework","Foundation","-framework","CoreFoundation"]
    env=dict(os.environ,MANGOSUITE_HOST_ROOT=str(work/"root"))
    binary=work/"reports-test"
    subprocess.run(common+[str(host/"CrashReportsCheck.m"),str(host/"RootHide.m"),str(ROOT/"src/CrashReports.m"),"-o",str(binary)],check=True)
    subprocess.run([str(binary),str(work/"files")],env=env,check=True)
    fixture=work/"Library/MangoSuite/Modules/MangoIdleIsland.dylib"
    fixture.parent.mkdir(parents=True)
    fixture_source=work/"fixture.c"
    fixture_source.write_text("int no_hooks_fixture(void) { return 1; }\n",encoding="utf-8")
    subprocess.run(["xcrun","clang","-dynamiclib",str(fixture_source),"-o",str(fixture)],check=True)
    binary=work/"startup-test"
    subprocess.run(common+[str(host/"StartupRecordingCheck.m"),str(host/"RootHide.m"),str(ROOT/"src/SuitePreferences.m"),"-o",str(binary)],check=True)
    subprocess.run([str(binary),str(fixture)],env=env,check=True)
