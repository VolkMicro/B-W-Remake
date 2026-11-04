"""Disassemble a bounded range from the installed host in memory only."""
import argparse
from pathlib import Path
import capstone
import pefile

parser = argparse.ArgumentParser()
parser.add_argument("executable", type=Path)
parser.add_argument("address", type=lambda value: int(value, 0))
parser.add_argument("--size", type=int, default=128)
args = parser.parse_args()
if not 1 <= args.size <= 1024:
    raise SystemExit("size must be between 1 and 1024")
image = pefile.PE(str(args.executable), fast_load=True)
rva = args.address - image.OPTIONAL_HEADER.ImageBase
offset = image.get_offset_from_rva(rva)
with args.executable.open("rb") as file:
    file.seek(offset)
    code = file.read(args.size)
decoder = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
for instruction in decoder.disasm(code, args.address):
    print(f"{instruction.address:08x}  {instruction.mnemonic:8} {instruction.op_str}")
