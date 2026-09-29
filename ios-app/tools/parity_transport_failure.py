"""Classify only the current drive attempt, before logcat diagnostics."""

import re
import sys
from pathlib import Path

# A 0-byte read is not evidence of a bad capture: the emulator dropped while
# the file was being pulled. Judge such a log by the transport error that
# follows it. A mismatch with real bytes still fails fast (see below).
_ZERO_BYTE_READ = re.compile(
    r"Capture receipt hash/length mismatch:[^\n]*\bactualLength=0\b[^\n]*")

_NOT_RETRYABLE = re.compile(
    r"TestFailure|EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK|"
    r"Some tests failed|AssertionError|Expected:|"
    r"Capture receipt hash/length mismatch|Invalid capture receipt path")

_TRANSPORT_LOSS = re.compile(
    r"Service has disappeared|Service connection disposed|"
    r"device offline|bad color buffer handle|"
    r"ADB capture read failed: error: device '[^']*' not found")


def is_retryable(log: str, status: int | None = None) -> bool:
    log = _ZERO_BYTE_READ.sub("", log)
    if _NOT_RETRYABLE.search(log):
        return False
    return status == 124 or bool(_TRANSPORT_LOSS.search(log))


if __name__ == "__main__":
    log = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
    status = int(sys.argv[2]) if len(sys.argv) > 2 else None
    raise SystemExit(0 if is_retryable(log, status) else 1)
