"""Ogg Vorbis encoding, pinned so a re-render is byte-identical.

libsndfile stamps every Ogg stream with a random serial number, which is the
one source of run-to-run variance in this repo: the Vorbis payload itself is
already a pure function of the samples. So the serial is rewritten to a fixed
value and each page's CRC recomputed, which restores the promise the README
makes about bytes.

COMPRESSION is libsndfile's 0 (largest) to 1 (smallest) scale. 0.6 is about
100 kbps mono, measured at 22 dB SNR against the rendered samples with the
peak, rms, tempo and loop-seam gates all reading the same as the source.
"""

from __future__ import annotations

import io

import numpy as np
import soundfile as sf

from .dsp import RATE, to_int16

COMPRESSION = 0.6
SERIAL = 0x47434D53  # "GCMS", any fixed value would do

_CRC_TABLE: list[int] = []
for _byte in range(256):
    _r = _byte << 24
    for _ in range(8):
        _r = (
            ((_r << 1) ^ 0x04C11DB7) & 0xFFFFFFFF
            if _r & 0x80000000
            else (_r << 1) & 0xFFFFFFFF
        )
    _CRC_TABLE.append(_r)


def _crc(page: bytes) -> int:
    r = 0
    for b in page:
        r = ((r << 8) & 0xFFFFFFFF) ^ _CRC_TABLE[((r >> 24) & 0xFF) ^ b]
    return r


def _pin_serials(stream: bytes) -> bytes:
    out = bytearray(stream)
    at = 0
    while at < len(out):
        if bytes(out[at : at + 4]) != b"OggS":
            raise ValueError(f"not an Ogg page boundary at byte {at}")
        segments = out[at + 26]
        end = at + 27 + segments + sum(out[at + 27 : at + 27 + segments])
        out[at + 14 : at + 18] = SERIAL.to_bytes(4, "little")
        out[at + 22 : at + 26] = b"\0\0\0\0"
        out[at + 22 : at + 26] = _crc(bytes(out[at:end])).to_bytes(4, "little")
        at = end
    return bytes(out)


def vendor_string(stream: bytes) -> str:
    """The encoder libVorbis stamped into the stream's comment header.

    Two Oggs of the same samples only agree byte for byte when the same
    encoder made them, so this is what tells a stale file from a differently
    encoded one.
    """
    at = stream.find(b"\x03vorbis")
    if at < 0:
        raise ValueError("no Vorbis comment header in stream")
    start = at + 11
    length = int.from_bytes(stream[at + 7 : start], "little")
    if len(stream) < start + length:
        raise ValueError("Vorbis comment header is truncated")
    return stream[start : start + length].decode("utf-8")


def ogg_bytes(x: np.ndarray) -> bytes:
    buf = io.BytesIO()
    sf.write(
        buf,
        to_int16(x),
        RATE,
        format="OGG",
        subtype="VORBIS",
        compression_level=COMPRESSION,
    )
    return _pin_serials(buf.getvalue())
