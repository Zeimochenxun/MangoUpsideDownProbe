"""Create a self-contained handoff containing sources, result, evidence, rollback."""
import hashlib
import json
import pathlib
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
output = ROOT / "delivery"
output.mkdir(exist_ok=True)
files = [ROOT / n for n in ("README.md", "ACCEPTANCE.md", "Makefile", "control", "AMangoSuiteLoader.plist", ".gitignore", "build-source.json")]
for folder in ("src", "prefs", "tools", "tests", ".github", "packages"):
    files.extend(p for p in (ROOT / folder).rglob("*") if p.is_file() and "__pycache__" not in p.parts)
sources = json.loads((ROOT / "inputs/sources.json").read_text())
files.append(ROOT / "inputs/sources.json")
files.extend(ROOT / "inputs" / source["file"] for source in sources.values())
builds = list((ROOT / "build-artifacts").glob("*/artifact.json"))
assert len(builds) == 1
build = builds[0].parent
files.extend(p for p in build.rglob("*") if p.is_file() and p.suffix not in (".deb", ".zip") and "verified-images" not in p.parts)
files = sorted(set(files))
hashes = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
archive = output / "MangoSuite-1.0.0-alpha2-完整工程与回退.zip"
with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
    for p in files:
        z.write(p, "MangoSuite/" + p.relative_to(ROOT).as_posix())
    z.writestr("MangoSuite/SHA256SUMS.json", json.dumps(hashes, ensure_ascii=False, indent=2) + "\n")
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for name, digest in hashes.items():
        assert hashlib.sha256(z.read("MangoSuite/" + name)).hexdigest() == digest
package = ROOT / "packages/MangoSuite-1.0.0-alpha2-RootHide-arm64e.deb"
report = {"archive": archive.name, "archiveSHA256": hashlib.sha256(archive.read_bytes()).hexdigest(),
          "package": package.name, "packageSHA256": hashlib.sha256(package.read_bytes()).hexdigest(),
          "files": len(files), "deviceTested": False}
(output / "交付校验.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report, ensure_ascii=True))
