#!/usr/bin/env python3
"""Hash and stage the canonical UTF-8 JSON representation of a fixture.

Git checkouts can materialize text files with CRLF when a developer has
``core.autocrlf=true``.  The parity contract intentionally hashes the logical
UTF-8/LF representation, so all capture entry points use this small helper
instead of hashing checkout bytes directly.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


def canonical_bytes(path: Path) -> bytes:
    return path.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n")


def canonical_sha256(path: Path) -> str:
    return hashlib.sha256(canonical_bytes(path)).hexdigest().upper()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    parser.add_argument(
        "--copy-to",
        type=Path,
        help="write the canonical bytes to this path before printing the hash",
    )
    args = parser.parse_args()

    data = canonical_bytes(args.path)
    if args.copy_to is not None:
        args.copy_to.parent.mkdir(parents=True, exist_ok=True)
        args.copy_to.write_bytes(data)
    print(hashlib.sha256(data).hexdigest().upper())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
