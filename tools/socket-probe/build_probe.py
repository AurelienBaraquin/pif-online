#!/usr/bin/env python3
"""Packs probe.rb into a Scripts.rxdata file readable by mkxp-z (RGSS1 format)."""

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


def build_scripts_archive(source: bytes) -> bytes:
    entry = b"[" + marshal_int(3)
    entry += b"i" + marshal_int(1)
    entry += marshal_string(b"probe")
    entry += marshal_string(zlib.compress(source))
    return b"\x04\x08[" + marshal_int(1) + entry


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: build_probe.py <probe.rb> <Scripts.rxdata>", file=sys.stderr)
        return 2
    source_path, target_path = Path(sys.argv[1]), Path(sys.argv[2])
    target_path.write_bytes(build_scripts_archive(source_path.read_bytes()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
