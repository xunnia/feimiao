"""Classify only the current drive attempt, before logcat diagnostics."""

import re
import sys
from pathlib import Path


def is_retryable(log: str) -> bool:
    if re.search(r"TestFailure|EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK|"
                 r"Some tests failed|AssertionError|Expected:", log):
        return False
    return bool(re.search(r"Service has disappeared|device offline|"
                          r"bad color buffer handle", log))


if __name__ == "__main__":
    log = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
    raise SystemExit(0 if is_retryable(log) else 1)
