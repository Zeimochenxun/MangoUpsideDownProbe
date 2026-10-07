"""Compile a private shader, or reuse recorded evidence for the exact unchanged input."""
import base64
import hashlib
import json
import os
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
config = json.loads((ROOT / "beta9-compatibility.json").read_text(encoding="utf-8"))
encoded = os.environ.pop("BETA9_METAL_SOURCE", "")
if not encoded:
    evidence = json.loads((ROOT / "tests/verified-metal.json").read_text(encoding="utf-8"))
    assert evidence["compiled"] and evidence["shaderSHA256"] == config["adaptiveShaderSHA256"], "The exact Beta9 private build input differs from recorded evidence; actual Apple Metal compilation is required"
    assert isinstance(evidence["verifiedRun"], int) and evidence["verifiedRun"] > 0 and evidence["airBytes"] > 0
    evidence["reusedUnchangedInput"] = True
    output = ROOT / "build-info"
    output.mkdir(exist_ok=True)
    (output / "metal-verification.json").write_text(json.dumps(evidence, indent=2))
    print("REUSED: exact unchanged Adaptive shader; actual Apple Metal validation from run " + str(evidence["verifiedRun"]))
    raise SystemExit(0)
source = base64.b64decode(encoded, validate=True)
assert hashlib.sha256(source).hexdigest() == config["adaptiveShaderSHA256"]
with tempfile.TemporaryDirectory(prefix="mangosuite-metal-") as directory:
    work = pathlib.Path(directory)
    shader, result = work / "Beta9.metal", work / "Beta9.air"
    shader.write_bytes(source)
    command = ["xcrun", "-sdk", "iphoneos", "metal", "-c", str(shader), "-o", str(result)]
    compilation = subprocess.run(command, capture_output=True, text=True)
    if compilation.returncode:
        # Compiler source context is private; only single-line diagnostics are allowed.
        for line in compilation.stderr.splitlines():
            if "error:" in line or "warning:" in line:
                print(line)
        raise SystemExit("FAIL: actual Apple Metal compiler rejected the final Beta9 shader")
    assert result.is_file() and result.stat().st_size > 0
    report = {"shaderSHA256": config["adaptiveShaderSHA256"], "compiled": True,
              "inputBytes": len(source), "airBytes": result.stat().st_size,
              "compiler": "Apple Metal / iphoneos", "mangoVersion": config["mangoVersion"]}
    if os.environ.get("GITHUB_RUN_ID"):
        report["verifiedRun"] = int(os.environ["GITHUB_RUN_ID"])
        report["sourceCommit"] = os.environ["GITHUB_SHA"]
    output = ROOT / "build-info"
    output.mkdir(exist_ok=True)
    (output / "metal-verification.json").write_text(json.dumps(report, indent=2))
    print("PASS: exact Beta9 shader after all four Adaptive rewrites compiled with Apple Metal")
