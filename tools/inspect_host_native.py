"""Read-only research helper; never writes original game bytes or disassembly.

Find an ASCII native name and pointers to it in the player's PE image. This
helps locate the native-function registration table during development.
"""
import argparse
import struct
from pathlib import Path

import pefile


parser = argparse.ArgumentParser()
parser.add_argument("executable", type=Path)
parser.add_argument("names", nargs="+")
args = parser.parse_args()
pe = pefile.PE(str(args.executable), fast_load=True)
data = args.executable.read_bytes()
base = pe.OPTIONAL_HEADER.ImageBase


def offsets(needle):
    position = -1
    while True:
        position = data.find(needle, position + 1)
        if position < 0:
            return
        yield position


def address(offset):
    return base + pe.get_rva_from_offset(offset)


for name in args.names:
    print("NAME", name)
    for location in offsets(name.encode("ascii") + b"\0"):
        target = address(location)
        print("  STRING", hex(target))
        for reference in offsets(struct.pack("<I", target)):
            start = max(0, reference - 12)
            end = min(len(data), reference + 24)
            print("  REFERENCE", hex(address(reference)), "WORDS", data[start:end].hex(" "))
