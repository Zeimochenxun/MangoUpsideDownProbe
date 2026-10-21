"""Build through GitHub Actions (no Theos on this PC), over the REST API.

  publish            commit the git-tracked tree to the build branch (triggers CI)
  status [--sha X]   latest runs on the build branch
  download --run N   fetch the package artifact into build-artifacts/N
  logs --run N       print the failing parts of a run's logs

The token comes from Git Credential Manager and stays in memory; it is never
sent to the artifact storage host.
"""
import argparse
import hashlib
import io
import json
import os
import pathlib
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASE = "https://api.github.com/repos/Zeimochenxun/MangoUpsideDownProbe"
BRANCH = "codex/double-dock"
ARTIFACT = "DoubleDock-arm64e-RootHide"
LIMIT = 100 * 1024 * 1024
STORAGE = (".blob.core.windows.net", ".actions.githubusercontent.com", ".githubusercontent.com")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def credential():
    env = dict(os.environ, GCM_INTERACTIVE="never", GIT_TERMINAL_PROMPT="0")
    result = subprocess.run(["git", "credential", "fill"], input="protocol=https\nhost=github.com\n\n",
                            text=True, capture_output=True, env=env, timeout=30, check=False)
    token = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line).get("password")
    if result.returncode or not token:
        # Never print the helper's output: it can contain secrets.
        raise RuntimeError("No noninteractive GitHub credential is available.")
    return token


def open_url(url, token=None, method="GET", data=None):
    headers = {"User-Agent": "DoubleDock-build", "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"}
    if token:
        headers["Authorization"] = "Bearer " + token
    if data is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(data).encode()
    request = urllib.request.Request(url, method=method, data=data, headers=headers)
    return urllib.request.build_opener(NoRedirect()).open(request, timeout=60)


def api(path, token, method="GET", data=None):
    with open_url(BASE + path, token, method, data) as response:
        return json.loads(response.read(LIMIT))


def archive(url, token):
    try:
        with open_url(url, token) as response:
            return response.read(LIMIT)
    except urllib.error.HTTPError as error:
        if error.code not in (301, 302, 303, 307, 308):
            raise
        location = urllib.parse.urlparse(error.headers.get("Location", ""))
        if location.scheme != "https" or location.username or not (location.hostname or "").lower().endswith(STORAGE):
            raise RuntimeError("Unexpected artifact download host.") from None
        with open_url(location.geturl()) as response:
            return response.read(LIMIT)


def publish(token):
    files = [f for f in subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0") if f]
    tree = [{"path": f, "mode": "100644", "type": "blob", "content": (ROOT / f).read_text(encoding="utf-8")} for f in files]
    try:
        parents = [api("/git/ref/heads/" + BRANCH, token)["object"]["sha"]]
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        parents = []
    message = subprocess.check_output(["git", "log", "-1", "--format=%B"], cwd=ROOT).decode("utf-8").strip()
    commit = api("/git/commits", token, "POST", {"message": message, "parents": parents,
                                                  "tree": api("/git/trees", token, "POST", {"tree": tree})["sha"]})["sha"]
    if parents:
        api("/git/refs/heads/" + BRANCH, token, "PATCH", {"sha": commit, "force": False})
    else:
        api("/git/refs", token, "POST", {"ref": "refs/heads/" + BRANCH, "sha": commit})
    print(json.dumps({"branch": BRANCH, "sha": commit, "files": len(tree)}))


def status(token, sha):
    runs = api("/actions/runs?" + urllib.parse.urlencode({"branch": BRANCH, "per_page": 10}), token)["workflow_runs"]
    for run in [r for r in runs if not sha or r["head_sha"].startswith(sha)][:2]:
        jobs = api(f"/actions/runs/{run['id']}/jobs", token)["jobs"]
        print(json.dumps({**{k: run[k] for k in ("id", "status", "conclusion", "head_sha")},
                          "steps": [(s["name"], s["conclusion"] or s["status"]) for j in jobs for s in j["steps"]]}, ensure_ascii=False))


def download(token, run):
    matches = [a for a in api(f"/actions/runs/{run}/artifacts", token)["artifacts"] if a["name"] == ARTIFACT]
    if len(matches) != 1 or matches[0]["expired"]:
        raise RuntimeError("Expected one current package artifact.")
    data = archive(f"{BASE}/actions/artifacts/{matches[0]['id']}/zip", token)
    digest = hashlib.sha256(data).hexdigest()
    if matches[0].get("digest"):
        assert matches[0]["digest"] == "sha256:" + digest
    destination = ROOT / "build-artifacts" / str(run)
    with zipfile.ZipFile(io.BytesIO(data)) as bundle:
        for item in bundle.infolist():
            path = pathlib.PurePosixPath(item.filename)
            assert not path.is_absolute() and ".." not in path.parts
            if not item.is_dir():
                target = destination.joinpath(*path.parts)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(bundle.read(item))
    print(json.dumps({"output": str(destination), "zip_sha256": digest, "debs": [str(p) for p in destination.rglob("*.deb")]}))


def logs(token, run):
    with zipfile.ZipFile(io.BytesIO(archive(f"{BASE}/actions/runs/{run}/logs", token))) as bundle:
        for item in bundle.infolist():
            text = bundle.read(item).decode("utf-8", errors="replace")
            if "error:" in text or "Assertion failed" in text or "##[error]" in text:
                print("==", item.filename)
                print(text[-12000:])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["publish", "status", "download", "logs"])
    parser.add_argument("--sha")
    parser.add_argument("--run", type=int)
    args = parser.parse_args()
    if args.action in ("download", "logs") and not args.run:
        parser.error("--run is required")
    token = credential()
    {"publish": lambda: publish(token), "status": lambda: status(token, args.sha),
     "download": lambda: download(token, args.run), "logs": lambda: logs(token, args.run)}[args.action]()


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    try:
        main()
    except Exception as error:
        print(type(error).__name__, getattr(error, "code", ""), file=sys.stderr)
        raise SystemExit(1)
