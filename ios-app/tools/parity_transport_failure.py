"""Classify only the current drive attempt, before logcat diagnostics."""

import re
import sys
from pathlib import Path


def is_retryable(log: str, status: int | None = None) -> bool:
    if re.search(r"TestFailure|EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK|"
                 r"Some tests failed|AssertionError|Expected:", log):
        return False
    return status == 124 or bool(re.search(
        r"Service has disappeared|Service connection disposed|"
        r"device offline|bad color buffer handle", log))


if __name__ == "__main__":
    log = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
    status = int(sys.argv[2]) if len(sys.argv) > 2 else None
    raise SystemExit(0 if is_retryable(log, status) else 1)
