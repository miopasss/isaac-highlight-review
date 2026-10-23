"""反汇编 PushRenderTarget/PopRenderTarget 附近 + 找所有调用点。"""
import struct, re
from capstone import Cs, CS_ARCH_X86, CS_MODE_32
from capstone.x86 import X86_OP_IMM

EXE = r"D:\lenovosoftstore\install\steam\steamapps\common\The Binding of Isaac Rebirth\isaac-ng.exe"
data = open(EXE, "rb").read()
pe = data.index(b"PE\0\0")
nsec, = struct.unpack_from("<H", data, pe + 6)
opt = pe + 24
image_base, = struct.unpack_from("<I", data, opt + 28)
so = opt + struct.unpack_from("<H", data, pe + 20)[0]
sections = []
for i in range(nsec):
    off = so + i * 40
    name = data[off:off + 8].rstrip(b"\0").decode("latin1")
    vsize, vaddr, rsize, raddr = struct.unpack_from("<IIII", data, off + 8)
    sections.append((name, vaddr, vsize, raddr, rsize))

def off2va(o):
    for n, va, vsz, ra, rs in sections:
        if ra and ra <= o < ra + rs:
            return va + (o - ra) + image_base
def va2off(v):
    r = v - image_base
    for n, va, vsz, ra, rs in sections:
        if va <= r < va + max(vsz, rs) and ra:
            return ra + (r - va)

strmap = {}
for m in re.finditer(rb"[\x20-\x7E]{5,}", data):
    va = off2va(m.start())
    if va:
        strmap[va] = m.group().decode("latin1")[:100]

md = Cs(CS_ARCH_X86, CS_MODE_32)
md.detail = True

def dis(va_start, length, label=""):
    off = va2off(va_start)
    if off is None:
        print("!! bad va", hex(va_start)); return
    print("\n===== %s @ 0x%08X =====" % (label, va_start))
    code = data[off:off + length]
    for ins in md.disasm(code, va_start):
        note = ""
        for op in ins.operands:
            if op.type == X86_OP_IMM and op.imm in strmap:
                note += '   ; "%s"' % strmap[op.imm]
        print("0x%08X  %-22s %s %s%s" % (ins.address, ins.bytes.hex(), ins.mnemonic, ins.op_str, note))

# 1) Push/Pop 附近
dis(0x65B480, 0x260, "Push/PopRenderTarget 区域")

# 2) 找调用这些函数的 call 点：先确定函数入口
# Push 的 assert 在 0x65B584，函数头大概在 0x65B520 附近；先看这段代码再判断。
