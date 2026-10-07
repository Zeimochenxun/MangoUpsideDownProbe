"""Export the verified package and build evidence; never include private inputs."""
import hashlib
import argparse
import io
import json
import pathlib
import shutil
import subprocess
import zipfile
from fetch_github_artifact import credential, api_request, archive_bytes, bounded_read
from assemble import VERSION, OUTPUT_NAME

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASE = "https://api.github.com/repos/Zeimochenxun/MangoUpsideDownProbe"
parser = argparse.ArgumentParser()
parser.add_argument("--run", required=True, type=int)
RUN = parser.parse_args().run
ARTIFACTS = ROOT / "build-artifacts" / str(RUN)
PACKAGE = ROOT / "packages" / OUTPUT_NAME
proof = json.loads((ROOT / "packages/verification.json").read_text(encoding="utf-8"))
source_commit = (ARTIFACTS / "build-info/source-commit.txt").read_text().strip()
assert source_commit == proof["sourceCommit"]
assert hashlib.sha256(PACKAGE.read_bytes()).hexdigest() == proof["packageSHA256"]
assert proof["result"] == "PASS" and proof["deviceTested"] is False
token = credential()

def get(path):
    with api_request(BASE + path, token) as response:
        return json.loads(bounded_read(response, 10 * 1024 * 1024))

run = get(f"/actions/runs/{RUN}")
assert run["conclusion"] == "success" and run["head_sha"] == source_commit
jobs = get(f"/actions/runs/{RUN}/jobs")["jobs"]
assert jobs and all(job["conclusion"] == "success" for job in jobs)
commit = get("/git/commits/" + source_commit)
tree = get("/git/trees/" + commit["tree"]["sha"] + "?recursive=1")
assert not tree.get("truncated")
compiled_sources = {}
for item in tree["tree"]:
    name = item["path"]
    if item["type"] != "blob":
        continue
    relevant = name.startswith(("src/", "prefs/", "modules/orientation/", "modules/visual/MangoIdleIsland/"))
    path = pathlib.PurePosixPath(name)
    relevant = relevant and (path.suffix in (".m", ".h", ".plist") or path.name in ("Makefile", "control"))
    relevant = relevant or name in ("Makefile", "control", "AMangoSuiteLoader.plist", "beta9-compatibility.json")
    relevant = relevant or name == "diagnostics/capture-runtime.sh"
    if not relevant:
        continue
    # Publisher sends UTF-8 text after universal-newline normalization.
    blob = (ROOT / name).read_text(encoding="utf-8").encode("utf-8")
    git_hash = hashlib.sha1(b"blob " + str(len(blob)).encode() + b"\0" + blob).hexdigest()
    assert git_hash == item["sha"], "Production source changed after the verified build: " + name
    compiled_sources[name] = hashlib.sha256(blob).hexdigest()
assert compiled_sources
assert "diagnostics/capture-runtime.sh" in compiled_sources, "Collector must belong to the verified build source"
passes = set()
logs = archive_bytes(f"{BASE}/actions/runs/{RUN}/logs", token)
with zipfile.ZipFile(io.BytesIO(logs)) as archive:
    for item in archive.infolist():
        for line in archive.read(item).decode("utf-8-sig", errors="replace").splitlines():
            if "PASS:" in line:
                passes.add(line[line.index("PASS:"):])
assert passes, "Build test output must be retained in delivery evidence"
shader = json.loads((ARTIFACTS / "build-info/metal-verification.json").read_text())
assert shader["compiled"] and shader["shaderSHA256"] == json.loads((ROOT / "beta9-compatibility.json").read_text())["adaptiveShaderSHA256"]
assert not shader.get("reusedUnchangedInput"), "This first Beta9 delivery requires actual Apple Metal compilation"
assert shader["verifiedRun"] == RUN and shader["sourceCommit"] == source_commit
assert json.loads((ROOT / "build-secret.json").read_text())["removed"]
summary = {
    "version": VERSION, "buildURL": run["html_url"], "sourceCommit": source_commit,
    "packageSHA256": proof["packageSHA256"], "packageBytes": PACKAGE.stat().st_size,
    "artifact": json.loads((ARTIFACTS / "artifact.json").read_text()),
    "jobs": [{"name": job["name"], "conclusion": job["conclusion"],
              "steps": [{"name": step["name"], "conclusion": step["conclusion"]} for step in job["steps"]]} for job in jobs],
    "testPassLines": sorted(passes), "metal": shader, "compiledSourceSHA256": compiled_sources,
    "finalPackageVerification": proof, "temporaryPrivateBuildInputRemoved": True,
    "nativePreferenceHistoricalUserFeedback": "Original Mango Beta8 with the independent preference tool; not this Beta9 suite build.",
    "completeSuiteDeviceTested": False, "suiteDeviceVerificationStatus": "pending",
    "diagnosticCollectorIncluded": True, "repairBehaviorChanged": True,
    "adaptedMangoVersion": "1.0-Beta9-1", "priorMangoVersion": "1.0-Beta8-1",
    "privateShaderValidation": "The supplied original Mango Beta8 and Beta9 shader bytes match. The exact private rewrite uses LF and was compiled again with Apple Metal in this build.",
    "device": "iPhone 13 mini / iOS 16.5 / Dopamine RootHide / authorized Mango 1.0-Beta9-1",
}
output = ROOT / "delivery" / VERSION.replace("~", "-")
output.mkdir(parents=True, exist_ok=True)
shutil.copy2(PACKAGE, output / PACKAGE.name)
def export_document(source, name):
    content = (ROOT / source).read_text(encoding="utf-8")
    content = content.replace("(modules/orientation/XIAOMANG.md)", "(小芒倒置适配.md)")
    content = content.replace("(diagnostics/RUNTIME.md)", "(诊断说明.md)")
    content = content.replace("(../../diagnostics/RUNTIME.md)", "(诊断说明.md)")
    content = content.replace("(ACCEPTANCE.md)", "(真机验收.md)")
    (output / name).write_text(content, encoding="utf-8")

export_document("README.md", "使用说明.md")
export_document("ACCEPTANCE.md", "真机验收.md")
export_document("REGRESSIONS.md", "REGRESSIONS.md")
export_document("modules/orientation/XIAOMANG.md", "小芒倒置适配.md")
shutil.copy2(ROOT / "diagnostics/RUNTIME.md", output / "诊断说明.md")
(output / "capture-runtime.sh").write_bytes(
    (ROOT / "diagnostics/capture-runtime.sh").read_text(encoding="utf-8").encode("utf-8"))
shutil.copy2(ROOT / "packages/verification.json", output / "package-verification.json")
shutil.copy2(PACKAGE.with_suffix(".manifest.json"), output / "module-manifest.json")
(output / "build-validation.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
(output / "SHA256SUMS.txt").write_text(proof["packageSHA256"] + "  " + PACKAGE.name + "\n", encoding="utf-8")
source_archive = output / "MangoSuite-Beta9-源码.zip"
tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
with zipfile.ZipFile(source_archive, "w", zipfile.ZIP_DEFLATED) as archive:
    for name in sorted(filter(None, tracked)):
        path = ROOT / name
        if not path.is_file():
            continue
        assert path.suffix not in (".metal", ".dylib", ".deb", ".air", ".metallib", ".zip")
        assert not name.startswith(("inputs/", "packages/", "build-artifacts/", "build-info/", "delivery/"))
        archive.write(path, "MangoSuiteBeta9/" + name)
    archive.write(ROOT / "inputs/sources.json", "MangoSuiteBeta9/inputs/sources.json")
with zipfile.ZipFile(source_archive) as archive:
    assert archive.testzip() is None
print(json.dumps({"delivery": str(output), "packageSHA256": proof["packageSHA256"],
                  "packageBytes": PACKAGE.stat().st_size, "result": "PASS", "completeSuiteDeviceTested": False}, ensure_ascii=True))
