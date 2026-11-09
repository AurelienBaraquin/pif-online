#!/usr/bin/env python3
"""Packs Ruby sources into a Scripts.rxdata file readable by mkxp-z (RGSS1)."""

import sys
import zlib
from pathlib import Path


def marshal_int(value: int) -> bytes:
    """Encodes a non-negative integer using Ruby's Marshal fixnum format."""
    if value == 0:
        return b"\x00"
    if value < 123:
        return bytes([value + 5])
    payload = value.to_bytes((value.bit_length() + 7) // 8, "little")
    return bytes([len(payload)]) + payload


def marshal_string(data: bytes) -> bytes:
    return b'"' + marshal_int(len(data)) + data


def build_archive(sources: list[Path]) -> bytes:
    archive = b"\x04\x08[" + marshal_int(len(sources))
    for index, source in enumerate(sources, start=1):
        archive += b"[" + marshal_int(3) + b"i" + marshal_int(index)
        archive += marshal_string(source.name.encode())
        archive += marshal_string(zlib.compress(source.read_bytes()))
    return archive


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: pack_scripts.py <Scripts.rxdata> <source.rb>...", file=sys.stderr)
        return 2
    target, *sources = sys.argv[1:]
    Path(target).write_bytes(build_archive([Path(source) for source in sources]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
