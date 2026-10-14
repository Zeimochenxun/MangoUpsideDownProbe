#!/usr/bin/env python3
"""Download a pinned Actions artifact without writing GitHub credentials to disk.

Authentication comes from Git Credential Manager (or the configured Git helper).
The authenticated API request never follows a redirect with its Authorization
header. Only the expected ZIP and DEB SHA-256 digests are accepted.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile


MAX_ARCHIVE_BYTES = 100 * 1024 * 1024
MAX_MEMBER_BYTES = 50 * 1024 * 1024


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def credential() -> str:
    git = shutil.which("git")
    if not git:
        raise RuntimeError("Git was not found in PATH.")
    env = os.environ.copy()
    env["GCM_INTERACTIVE"] = "never"
    env["GIT_TERMINAL_PROMPT"] = "0"
    result = subprocess.run(
        [git, "credential", "fill"],
        input="protocol=https\nhost=github.com\n\n",
        text=True,
        capture_output=True,
        env=env,
        timeout=30,
        check=False,
    )
    values = dict(
        line.split("=", 1) for line in result.stdout.splitlines() if "=" in line
    )
    token = values.get("password")
    if result.returncode or not token:
        # Never surface credential-helper stdout/stderr: either can contain secrets.
        raise RuntimeError("No noninteractive GitHub credential is available.")
    return token


def digest(value: str) -> str:
    if not re.fullmatch(r"[0-9a-fA-F]{64}", value):
        raise argparse.ArgumentTypeError("Expected a SHA-256 digest.")
    return value.lower()


def bounded_read(response, limit: int) -> bytes:
    data = response.read(limit + 1)
    if len(data) > limit:
        raise RuntimeError("Download exceeds the configured size limit.")
    return data


def api_request(url: str, token: str):
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": "Bearer " + token,
            "User-Agent": "MangoSuite-artifact-fetcher",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    return urllib.request.build_opener(NoRedirect()).open(request, timeout=60)


def archive_bytes(url: str, token: str) -> bytes:
    try:
        with api_request(url, token) as response:
            return bounded_read(response, MAX_ARCHIVE_BYTES)
    except urllib.error.HTTPError as error:
        if error.code not in (301, 302, 303, 307, 308):
            raise RuntimeError(f"GitHub archive request failed (HTTP {error.code}).") from None
        location = error.headers.get("Location", "")
        parsed = urllib.parse.urlparse(location)
        host = (parsed.hostname or "").lower()
        allowed = any(
            host.endswith(suffix)
            for suffix in (".blob.core.windows.net", ".actions.githubusercontent.com", ".githubusercontent.com")
        )
        if parsed.scheme != "https" or parsed.username or parsed.password or not allowed:
            raise RuntimeError("GitHub returned an unexpected artifact download host.") from None
        # Start a fresh unauthenticated request. Do not leak the GitHub credential
        # to the signed artifact-storage URL or print that short-lived URL.
        request = urllib.request.Request(location, headers={"User-Agent": "MangoSuite-artifact-fetcher"})
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=60) as response:
            return bounded_read(response, MAX_ARCHIVE_BYTES)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--artifact-id", required=True, type=int)
    parser.add_argument("--zip-sha256", required=True, type=digest)
    parser.add_argument("--deb-sha256", required=True, type=digest)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repo) or args.artifact_id <= 0:
        parser.error("Invalid repository or artifact ID.")

    api_url = f"https://api.github.com/repos/{args.repo}/actions/artifacts/{args.artifact_id}"
    token = credential()
    try:
        with api_request(api_url, token) as response:
            metadata = json.loads(bounded_read(response, 1024 * 1024))
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"GitHub metadata request failed (HTTP {error.code}).") from None
    if metadata.get("expired"):
        raise RuntimeError("This GitHub artifact has expired.")

    data = archive_bytes(api_url + "/zip", token)
    del token
    if hashlib.sha256(data).hexdigest() != args.zip_sha256:
        raise RuntimeError("ZIP SHA-256 mismatch; nothing was extracted.")

    matches = []
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for member in archive.infolist():
            if member.is_dir() or not member.filename.endswith(".deb"):
                continue
            if member.file_size > MAX_MEMBER_BYTES:
                raise RuntimeError("DEB member exceeds the configured size limit.")
            candidate = archive.read(member)
            if hashlib.sha256(candidate).hexdigest() == args.deb_sha256:
                if not candidate.startswith(b"!<arch>\n"):
                    raise RuntimeError("Pinned DEB does not have an ar archive header.")
                matches.append((PurePosixPath(member.filename).name, candidate))
    if len(matches) != 1:
        raise RuntimeError(f"Expected one DEB matching the pinned digest; found {len(matches)}.")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    zip_path = args.output_dir / f"artifact-{args.artifact_id}.zip"
    deb_name, deb_data = matches[0]
    if "\\" in deb_name or deb_name in ("", ".", ".."):
        raise RuntimeError("Unexpected DEB filename.")
    deb_path = args.output_dir / deb_name
    zip_path.write_bytes(data)
    deb_path.write_bytes(deb_data)
    report = {
        "repository": args.repo,
        "artifact_id": args.artifact_id,
        "artifact_name": metadata.get("name"),
        "workflow_run_id": (metadata.get("workflow_run") or {}).get("id"),
        "zip": zip_path.name,
        "zip_sha256": args.zip_sha256,
        "deb": deb_path.name,
        "deb_sha256": args.deb_sha256,
    }
    (args.output_dir / f"artifact-{args.artifact_id}.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
        # Network exceptions may contain signed URLs. Only our RuntimeError
        # messages are safe to print verbatim.
        message = str(error) if isinstance(error, RuntimeError) else type(error).__name__
        print(f"Artifact download failed: {message}", file=sys.stderr)
        raise SystemExit(1)
