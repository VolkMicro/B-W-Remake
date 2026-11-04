"""Compare the port's influence falloff with the player's installed original.

The game executable and Info block are read in memory. Only the 1.2 routine
at the known executable address is emulated; no original bytes are written.
Output is JSON for BW_INFLUENCE_ORACLE, consumed by verify_influence.gd.
Requires the optional research dependencies pefile and unicorn.
"""
import argparse
import json
import struct
from pathlib import Path

import pefile
from unicorn import Uc, UC_ARCH_X86, UC_MODE_32
from unicorn.x86_const import UC_X86_REG_ESP


parser = argparse.ArgumentParser()
parser.add_argument("--bw", type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
formats = json.loads((root / "design/host_info_formats.json").read_text(encoding="utf-8"))
binary = (args.bw / "runblack.exe").read_bytes()
pe = pefile.PE(data=binary, fast_load=True)
if pe.OPTIONAL_HEADER.ImageBase != 0x400000:
    raise SystemExit("Unsupported original executable image base")
function_address = 0x5CD560
offset = pe.get_offset_from_rva(function_address - pe.OPTIONAL_HEADER.ImageBase)
function = binary[offset:offset + 0x9C]
if len(function) != 0x9C:
    raise SystemExit("Original influence routine is unavailable")
info_file = (args.bw / "Scripts/info.dat").read_bytes()
position = 8
info = b""
if info_file[:8] != b"LiOnHeAd":
    raise SystemExit("Original Info file header is invalid")
while position + 36 <= len(info_file):
    name = info_file[position:position + 32].split(b"\0")[0]
    size = struct.unpack_from("<I", info_file, position + 32)[0]
    position += 36
    if size > len(info_file) - position:
        raise SystemExit("Original Info file is truncated")
    if name == b"Info":
        info = info_file[position:position + size]
        break
    position += size
fmt = next((item for item in formats if item["info_size"] == len(info)), None)
if fmt is None or fmt["id"] != "bw_1_2":
    raise SystemExit("Unsupported original Info version")
start = fmt["influence_offset"]
constants = info[start:start + fmt["influence_float_count"] * 4]
if len(constants) != 12:
    raise SystemExit("Original influence settings are truncated")
full, gradient, _ = struct.unpack("<3f", constants)

samples = []
fractions = (0.0, 0.1, full - 0.001, full, full + 0.001,
             full + gradient / 2, full + gradient - 0.001,
             full + gradient, full + gradient + 0.001, 0.8, 0.999, 1.0, 1.1)
for radius in (10.0, 30.0, 120.0):
    for fraction in fractions:
        distance = struct.unpack("<f", struct.pack("<f", radius * fraction))[0]
        cpu = Uc(UC_ARCH_X86, UC_MODE_32)
        for address in (0x5CD000, 0x8AA000, 0x8C7000, 0xD17000, 0x1000000, 0x2000000):
            cpu.mem_map(address, 0x1000)
        cpu.mem_write(function_address, function)
        for address, length in ((0x8AA390, 4), (0x8AA398, 4), (0x8C7C68, 8)):
            source = pe.get_offset_from_rva(address - pe.OPTIONAL_HEADER.ImageBase)
            cpu.mem_write(address, binary[source:source + length])
        cpu.mem_write(0xD17CD0, constants)
        # The return stub stores x87 ST0 in the emulator's private memory.
        cpu.mem_write(0x2000000, b"\xd9\x1d" + struct.pack("<I", 0x2000100))
        cpu.mem_write(0x1000800, struct.pack("<Iff", 0x2000000, distance, radius))
        cpu.reg_write(UC_X86_REG_ESP, 0x1000800)
        cpu.emu_start(function_address, 0x2000006, count=100)
        strength = struct.unpack("<f", cpu.mem_read(0x2000100, 4))[0]
        samples.append({"distance": distance, "radius": radius, "strength": strength})
print(json.dumps(samples, separators=(",", ":")))
