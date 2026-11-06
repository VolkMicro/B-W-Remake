"""Read-only lookup of BW1 1.2 native handlers from its registration routine."""
import argparse
from pathlib import Path
import capstone
import pefile

parser = argparse.ArgumentParser()
parser.add_argument("executable", type=Path)
parser.add_argument("ids", type=int, nargs="+")
args = parser.parse_args()
pe = pefile.PE(str(args.executable), fast_load=True)
base = pe.OPTIONAL_HEADER.ImageBase
start = pe.get_offset_from_rva(0x6FFFD0 - base)
data = args.executable.read_bytes()[start:start + 0x8C30]
decoder = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
decoder.detail = True
handlers = {}
for instruction in decoder.disasm(data, 0x6FFFD0):
    if instruction.mnemonic != "mov" or len(instruction.operands) != 2:
        continue
    destination, source = instruction.operands
    if destination.type != capstone.x86.X86_OP_MEM or source.type != capstone.x86.X86_OP_IMM:
        continue
    memory = destination.mem
    if memory.base or memory.index:
        continue
    index, remainder = divmod(memory.disp - 0xC0DB98, 144)
    if remainder == 0 and 0 <= index < 464:
        handlers[index] = source.imm
for native_id in args.ids:
    address = handlers.get(native_id)
    print(native_id, hex(address) if address else "not found")
