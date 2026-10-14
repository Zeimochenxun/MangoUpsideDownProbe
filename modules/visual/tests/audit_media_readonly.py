"""Local read-only Beta8 media/idle interoperation evidence.

Uses the existing local review parser; does not write or patch Mango binaries.
XOR recovered strings are static leads, not proof of a branch executing.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

REVIEW = Path(__file__).resolve().parents[4] / "审查结果/Mango-Beta8-屏幕倒置"
sys.path.insert(0, str(REVIEW))
from macho_analysis import MachO
from decode_xor_strings import scan


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("module", choices=["MangoPanda", "MangoHello"])
    parser.add_argument("--from-address", type=lambda x: int(x, 0), default=0)
    parser.add_argument("--function", type=lambda x: int(x, 0))
    parser.add_argument("--output", type=Path)
    parser.add_argument("--verify-media-abi", action="store_true")
    args = parser.parse_args()
    binary = REVIEW / "extracted/data/Library/MobileSubstrate/DynamicLibraries" / (args.module + ".dylib")
    m = MachO(binary)
    if args.verify_media_abi:
        assert args.module == "MangoPanda", "Evidence addresses belong to the supplied Panda image"
        strings = scan(m, *m.function(0x4567c0))
        export = "MRMediaRemoteGetNowPlayingApplicationIsPlaying"
        assert any(x["text"] == export for x in strings)
        signature_pointer = m.ptr(0x9c6238)
        signature = m.cstr(signature_pointer)
        assert signature == "v12@?0B8", signature
        instructions = list(m.instructions(0x4573b0, 0x4573c4))
        expected = [
            (0x4573b0, "ldur", "x1, [x29, #-0x78]"),
            (0x4573b4, "ldur", "x8, [x29, #-0x98]"),
            (0x4573b8, "adrp", "x0, #0x9c4000"),
            (0x4573bc, "ldr", "x0, [x0, #0xb08]"),
            (0x4573c0, "blraaz", "x8"),
        ]
        assert [(x.address, x.mnemonic, x.op_str) for x in instructions] == expected
        assert m.imports[0x9c4b08] == "__dispatch_main_q"
        evidence = {
            "binary": args.module + ".dylib",
            "sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
            "export": export,
            "decodedExport": [x for x in strings if x["text"] == export],
            "callbackDescriptor": "0x9c6218",
            "callbackSignaturePointerSlot": "0x9c6238",
            "callbackSignatureAddress": hex(signature_pointer),
            "callbackSignature": signature,
            "callInstructions": [{"address": hex(a), "mnemonic": n, "operands": o} for a, n, o in expected],
            "queueImport": {"address": "0x9c4b08", "symbol": m.imports[0x9c4b08]},
            "claim": "Read-only main-queue query with BOOL completion matches supplied Beta8 call ABI; no API creates media content",
            "limitation": "Static call ABI only; no evidence proving Idle glass caused the reported missing media, and no connected-device validation",
        }
        if args.output:
            args.output.write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps(evidence, ensure_ascii=False, indent=2))
        return
    pattern = re.compile(r"MGLiveBackdropView|SBSystemAperture|SAUIElement|nowplaying|nowPlaying|NowPlaying|MRMedia|media|Media|island|Island|hasContent", re.I)
    targets = [m.function(args.function)] if args.function else list(zip(m.starts, m.starts[1:]))
    results = []
    for start, end in targets:
        if start < args.from_address:
            continue
        strings = scan(m, start, end)
        selected = [x for x in strings if pattern.search(x["text"])]
        if selected:
            result = {"function": hex(start), "label": m.labels.get(start), "size": end-start, "strings": selected}
            results.append(result)
            print(json.dumps(result, ensure_ascii=False), flush=True)
    if args.output:
        args.output.write_text(json.dumps({"module": args.module, "binary": str(binary), "note": "Static XOR leads; no execution or device result", "matches": results}, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
