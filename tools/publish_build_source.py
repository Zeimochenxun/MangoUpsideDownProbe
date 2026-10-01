"""Publish only git-tracked helper source to its dedicated build branch via REST.

Used when the host's git HTTPS transport is unavailable. Never uploads inputs.
"""
import json
import argparse
import pathlib
import subprocess
import urllib.error
import urllib.request
from fetch_github_artifact import credential, NoRedirect, bounded_read

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASE = "https://api.github.com/repos/Zeimochenxun/MangoUpsideDownProbe"
BRANCH = "codex/mango-suite-1.0.0-alpha1"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", default="build-source.json")
    args = parser.parse_args()
    token = credential()
    def api(method, path, data=None):
        request = urllib.request.Request(BASE + path, method=method,
            data=None if data is None else json.dumps(data).encode(),
            headers={"Authorization": "Bearer " + token, "User-Agent": "MangoSuite-build",
                     "Accept": "application/vnd.github+json", "Content-Type": "application/json"})
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=60) as response:
            return json.loads(bounded_read(response, 10*1024*1024))
    paths = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
    tree = []
    for filename in filter(None, paths):
        assert not filename.startswith(("inputs/", "packages/", "build-artifacts/"))
        assert pathlib.Path(filename).suffix not in (".deb", ".dylib", ".zip")
        content = (ROOT / filename).read_text(encoding="utf-8")
        assert len(content) < 100000
        tree.append({"path": filename, "mode": "100644", "type": "blob", "content": content})
    try:
        branch = api("GET", "/git/ref/heads/" + BRANCH)
        parents = [branch["object"]["sha"]]
        new = False
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        parents = []
        new = True
    created_tree = api("POST", "/git/trees", {"tree": tree})
    commit = api("POST", "/git/commits", {"message": "Build Mango Suite loader and unified settings with independent module switches", "tree": created_tree["sha"], "parents": parents})
    if new:
        api("POST", "/git/refs", {"ref": "refs/heads/" + BRANCH, "sha": commit["sha"]})
    else:
        api("PATCH", "/git/refs/heads/" + BRANCH, {"sha": commit["sha"], "force": False})
    report = {"branch": BRANCH, "sha": commit["sha"], "files": len(tree), "created": new}
    (ROOT / args.report).write_text(json.dumps(report, indent=2))
    print(json.dumps(report))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(type(error).__name__)
        raise SystemExit(1)
