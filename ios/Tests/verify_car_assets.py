"""Reject partial PNG uploads before Xcode can compile broken car layers."""
from pathlib import Path
import hashlib
import json
import struct
import zlib

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / "Tests/car_asset_checksums.json").read_text())
for relative, expected in manifest.items():
    data = (root / relative).read_bytes()
    assert hashlib.sha256(data).hexdigest() == expected, f"Checksum mismatch: {relative}"
    assert data[:8] == b"\x89PNG\r\n\x1a\n", relative
    offset = 8
    ended = False
    while offset < len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + length]
        end = offset + 12 + length
        assert end <= len(data), f"Truncated chunk: {relative}"
        crc = struct.unpack(">I", data[end - 4:end])[0]
        assert zlib.crc32(kind + payload) == crc, f"Invalid PNG chunk: {relative}"
        if kind == b"IHDR":
            assert struct.unpack(">II", payload[:8]) == (1920, 1200), relative
        offset = end
        if kind == b"IEND":
            ended = True
            break
    assert ended and offset == len(data), f"Missing PNG end: {relative}"

# The complete door/hatch envelope is fitted once on every supported width.
for width in (288, 343, 382, 736, 992):
    scale = (width - 8) / 1794
    left = width / 2 + (63 - 960) * scale
    right = width / 2 + (1857 - 960) * scale
    bottom = (1154 - 46) * scale
    assert left >= 3.99 and right <= width - 3.99
    assert bottom < width * 1165 / 1794
print(f"{len(manifest)} complete PNG layers verified; fixed car envelope fits all widths")
