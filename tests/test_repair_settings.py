import os
import pathlib
import subprocess
import tempfile
root=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="mango-repair-settings-") as directory:
    work=pathlib.Path(directory)
    binary=work/"repair-settings"
    host=root/"tests/host"
    subprocess.run(["xcrun","clang","-fobjc-arc","-Wall","-Wextra","-Werror","-I"+str(host),
        "-framework","Foundation",str(host/"RootHide.m"),str(host/"RepairSettingsCheck.m"),
        str(root/"src/SuitePreferences.m"),"-o",str(binary)],check=True)
    subprocess.run([str(binary)],env=dict(os.environ,MANGOSUITE_HOST_ROOT=str(work/"root")),check=True)
