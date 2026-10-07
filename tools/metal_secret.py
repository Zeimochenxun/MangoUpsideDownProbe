"""Temporarily supply a private test input to the existing macOS build runner.

The shader is never committed, printed, or uploaded as an artifact. Remove the
unique secret after completed validation. Git credentials remain in memory.
"""
import argparse
import base64
import hashlib
import json
import pathlib
import sys
import urllib.error
import urllib.request
from fetch_github_artifact import credential, NoRedirect, bounded_read

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASE = "https://api.github.com/repos/Zeimochenxun/MangoUpsideDownProbe"
NAME = "MANGOSUITE_BETA9_METAL_4826D2"

def main(action):
    token = credential()
    def api(method, endpoint, content=None):
        request = urllib.request.Request(BASE + endpoint, method=method,
            data=None if content is None else json.dumps(content).encode(),
            headers={"Authorization": "Bearer " + token, "User-Agent": "MangoSuite-build-test",
                     "Accept": "application/vnd.github+json", "Content-Type": "application/json"})
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=45) as response:
            blob = bounded_read(response, 1024*1024)
            return json.loads(blob) if blob else None
    endpoint = "/actions/secrets/" + NAME
    report_path = ROOT / "build-secret.json"
    if action == "remove":
        report = json.loads(report_path.read_text())
        assert report["name"] == NAME and report["createdByThisBuild"]
        api("DELETE", endpoint)
        report["removed"] = True
        report_path.write_text(json.dumps(report, indent=2) + "\n")
        print("Removed temporary Metal validation input")
        return
    try:
        api("GET", endpoint)
    except urllib.error.HTTPError as error:
        if error.code != 404: raise
    else:
        raise RuntimeError("Refusing to overwrite an existing build secret")
    key = api("GET", "/actions/secrets/public-key")
    sys.path.insert(0, str(pathlib.Path.home() / ".codex/tmp/mangosuite-build-deps"))
    from nacl.public import PublicKey, SealedBox
    blob = (ROOT / "modules/visual/Beta9-adaptive-exact-rewrite.metal").read_bytes()
    assert len(blob) < 34000
    config = json.loads((ROOT / "beta9-compatibility.json").read_text(encoding="utf-8"))
    assert hashlib.sha256(blob).hexdigest() == config["adaptiveShaderSHA256"], "Private shader input must match the recorded exact Beta9 rewrite"
    value = base64.b64encode(blob)
    encrypted = SealedBox(PublicKey(base64.b64decode(key["key"]))).encrypt(value)
    api("PUT", endpoint, {"encrypted_value": base64.b64encode(encrypted).decode(), "key_id": key["key_id"]})
    report_path.write_text(json.dumps({"name": NAME, "createdByThisBuild": True, "removed": False,
                                      "sourceSHA256": hashlib.sha256(blob).hexdigest()}, indent=2) + "\n")
    print("Created temporary private Metal validation input; no source in Git or artifacts")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["create", "remove"])
    try: main(parser.parse_args().action)
    except Exception as error:
        print(type(error).__name__, file=sys.stderr)
        raise SystemExit(1)
