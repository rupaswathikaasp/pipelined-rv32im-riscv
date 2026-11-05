#!/usr/bin/env python3
"""Pure-python replacement for: riscv32-unknown-elf-objcopy test.elf -O binary out.bin
Usage: python3 elf2bin.py test.elf build/tcm.bin"""
import struct, sys
src, dst = sys.argv[1], sys.argv[2]
d = open(src, 'rb').read()
assert d[:4] == b'\x7fELF' and d[4] == 1, "not a 32-bit ELF"
e_phoff, = struct.unpack_from('<I', d, 0x1C)
e_phentsize, e_phnum = struct.unpack_from('<HH', d, 0x2A)
segs = []
for i in range(e_phnum):
    p_type, p_off, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = \
        struct.unpack_from('<8I', d, e_phoff + i * e_phentsize)
    if p_type == 1 and p_filesz:          # PT_LOAD
        segs.append((p_paddr, d[p_off:p_off + p_filesz]))
base = min(s[0] for s in segs)
end = max(s[0] + len(s[1]) for s in segs)
img = bytearray(end - base)
for a, b in segs:
    img[a - base:a - base + len(b)] = b
open(dst, 'wb').write(img)
print(f"base=0x{base:x} size={len(img)} bytes -> {dst}")
