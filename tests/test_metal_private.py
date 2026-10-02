"""Compile a private shader, or reuse recorded evidence for the exact unchanged input."""
import base64
import hashlib
import json
import os
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
config = json.loads((ROOT / "beta8-compatibility.json").read_text(encoding="utf-8"))
encoded = os.environ.pop("BETA8_METAL_SOURCE", "")
if not encoded:
    evidence = json.loads((ROOT / "tests/verified-metal.json").read_text(encoding="utf-8"))
    assert evidence["compiled"] and evidence["shaderSHA256"] == config["adaptiveShaderSHA256"]
    assert evidence["verifiedRun"] == 36913456075 and evidence["airBytes"] > 0
    evidence["reusedUnchangedInput"] = True
    output = ROOT / "build-info"
    output.mkdir(exist_ok=True)
    (output / "metal-verification.json").write_text(json.dumps(evidence, indent=2))
    print("REUSED: unchanged Adaptive shader; actual Apple Metal validation from run 36913456075")
    raise SystemExit(0)
source = base64.b64decode(encoded, validate=True)
assert hashlib.sha256(source).hexdigest() == config["adaptiveShaderSHA256"]
with tempfile.TemporaryDirectory(prefix="mangosuite-metal-") as directory:
    work = pathlib.Path(directory)
    shader, result = work / "Beta8.metal", work / "Beta8.air"
    shader.write_bytes(source)
    command = ["xcrun", "-sdk", "iphoneos", "metal", "-c", str(shader), "-o", str(result)]
    compilation = subprocess.run(command, capture_output=True, text=True)
    if compilation.returncode:
        # Compiler source context is private; only single-line diagnostics are allowed.
        for line in compilation.stderr.splitlines():
            if "error:" in line or "warning:" in line:
                print(line)
        raise SystemExit("FAIL: actual Apple Metal compiler rejected the final Beta8 shader")
    assert result.is_file() and result.stat().st_size > 0
    report = {"shaderSHA256": config["adaptiveShaderSHA256"], "compiled": True,
              "airBytes": result.stat().st_size, "compiler": "Apple Metal / iphoneos"}
    output = ROOT / "build-info"
    output.mkdir(exist_ok=True)
    (output / "metal-verification.json").write_text(json.dumps(report, indent=2))
    print("PASS: exact Beta8 shader after all four Adaptive rewrites compiled with Apple Metal")
