"""Compare the first-write regression against the actual Beta8.3 helper.

Run with macOS clang: python3 modules/orientation/tests/test_split_regression.py
The fixed-coordinate fixture is a host model, not a phone visual test.
"""
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile


TESTS = Path(__file__).resolve().parent
ORIENTATION = TESTS.parent
BASELINE = TESTS / "fixtures/split-beta83-baseline.h"
# git rev-parse cabc13e:modules/orientation/SplitReconcile.h
BASELINE_BLOB = "451ec8358bc53427de722a7f5f2d3370ec3dd6e7"

PROBE = r'''#define main split_full_suite
#include "tests/split_reconcile_test.c"
#undef main

int main(void) {
    MSSplitOwnership state = {0};
    Fixture fixture = upright();
    fixture.ineligibleAfterWrite = 1;
    unsigned result = reconcile(&fixture, &state, 1);
    printf("result=%u writes=%u applied=%d suspended=%d\n",
           result, fixture.writes, state.applied, state.suspended);
    return !(result == MSSplitApplied && fixture.writes == 1 &&
             state.applied && !state.suspended);
}
'''


def main():
    baseline = BASELINE.read_bytes()
    blob_header = f"blob {len(baseline)}\0".encode("ascii")
    actual_blob = hashlib.sha1(blob_header + baseline).hexdigest()
    if actual_blob != BASELINE_BLOB:
        raise AssertionError(f"Beta8.3 baseline blob changed: {actual_blob}")
    clang = shutil.which("clang")
    if not clang:
        raise SystemExit("clang is required to execute the production C helper comparison")

    cases = [
        ("candidate", (ORIENTATION / "SplitReconcile.h").read_bytes(), 0,
         "result=4 writes=1 applied=1 suspended=0"),
        ("beta83-baseline", baseline, 1,
         "result=9 writes=2 applied=0 suspended=1"),
    ]
    with tempfile.TemporaryDirectory(prefix="beta8-split-regression-") as temporary:
        compiled = []
        # Both compilations must succeed before an expected failing execution
        # can count as a detected regression.
        for label, header, expected_exit, expected_output in cases:
            work = Path(temporary) / label
            (work / "tests").mkdir(parents=True)
            (work / "SplitReconcile.h").write_bytes(header)
            shutil.copyfile(ORIENTATION / "WorldMath.h", work / "WorldMath.h")
            shutil.copyfile(TESTS / "split_reconcile_test.c",
                            work / "tests/split_reconcile_test.c")
            source, binary = work / "probe.c", work / "probe"
            source.write_text(PROBE, encoding="utf-8")
            subprocess.run([clang, "-std=c11", "-Wall", "-Wextra", "-Werror",
                            str(source), "-lm", "-o", str(binary)], check=True)
            compiled.append((label, binary, expected_exit, expected_output))
        for label, binary, expected_exit, expected_output in compiled:
            result = subprocess.run([str(binary)], capture_output=True, text=True)
            if (result.returncode != expected_exit or
                    result.stdout.strip() != expected_output or result.stderr):
                raise AssertionError((label, result.returncode, result.stdout, result.stderr))

    print("PASS: candidate keeps first turn; exact Beta8.3 baseline restores and suspends it")


if __name__ == "__main__":
    main()
