"""Query this build and retrieve artifacts using in-memory Git credentials."""
import argparse
import hashlib
import io
import json
import pathlib
import sys
import urllib.parse
import zipfile
from fetch_github_artifact import credential, api_request, archive_bytes, bounded_read

BASE = "https://api.github.com/repos/Zeimochenxun/MangoUpsideDownProbe"
ROOT = pathlib.Path(__file__).resolve().parents[1]


def get(path, token):
    with api_request(BASE + path, token) as response:
        return json.loads(bounded_read(response, 10 * 1024 * 1024))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["status", "download", "logs"])
    parser.add_argument("--sha")
    parser.add_argument("--run", type=int)
    args = parser.parse_args()
    token = credential()
    if args.action == "status":
        query = urllib.parse.urlencode({"branch": "codex/mango-suite-beta9", "per_page": 10})
        runs = get("/actions/runs?" + query, token)["workflow_runs"]
        if args.sha:
            runs = [r for r in runs if r["head_sha"].startswith(args.sha)]
        for run in runs[:2]:
            output = {key: run[key] for key in ("id", "status", "conclusion", "html_url", "head_sha")}
            output["jobs"] = [{"id": j["id"], "status": j["status"], "conclusion": j["conclusion"],
                               "steps": [{k: s.get(k) for k in ("name", "status", "conclusion")} for s in j["steps"]]}
                              for j in get(f'/actions/runs/{run["id"]}/jobs', token)["jobs"]]
            print(json.dumps(output, ensure_ascii=True))
        return
    if not args.run:
        parser.error("--run is required")
    if args.action == "logs":
        data = archive_bytes(f"{BASE}/actions/runs/{args.run}/logs", token)
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            for info in archive.infolist():
                content = archive.read(info).decode("utf-8", errors="replace")
                if "error:" in content or "Traceback" in content or "FAIL" in content:
                    print(info.filename)
                    print(content[-12000:])
        return
    metadata = get(f"/actions/runs/{args.run}/artifacts", token)
    matches = [a for a in metadata["artifacts"] if a["name"] == "MangoSuite-Beta9-helper-arm64e-RootHide"]
    if len(matches) != 1 or matches[0]["expired"]:
        raise RuntimeError("Expected one current build artifact")
    artifact = matches[0]
    data = archive_bytes(f'{BASE}/actions/artifacts/{artifact["id"]}/zip', token)
    digest = hashlib.sha256(data).hexdigest()
    if artifact.get("digest"):
        assert artifact["digest"] == "sha256:" + digest
    destination = ROOT / "build-artifacts" / str(args.run)
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "helper.zip").write_bytes(data)
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for item in archive.infolist():
            if item.is_dir():
                continue
            path = pathlib.PurePosixPath(item.filename)
            assert not path.is_absolute() and ".." not in path.parts
            target = destination.joinpath(*path.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(item))
    (destination / "artifact.json").write_text(json.dumps({"run": args.run, "artifact": artifact["id"], "sha256": digest}, indent=2))
    print(json.dumps({"output": str(destination), "sha256": digest, "debs": [str(p) for p in destination.rglob("*.deb")]}, ensure_ascii=True))


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    try:
        main()
    except Exception as error:
        print(type(error).__name__, file=sys.stderr)
        raise SystemExit(1)
