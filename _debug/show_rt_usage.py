"""把 Push/Pop 的某一处调用点前后反汇编出来，看引擎实际的 save/restore 写法。"""
import struct, re
from capstone import Cs, CS_ARCH_X86, CS_MODE_32
from capstone.x86 import X86_OP_IMM

EXE = r"D:\lenovosoftstore\install\steam\steamapps\common\The Binding of Isaac Rebirth\isaac-ng.exe"
data = open(EXE, "rb").read()
pe = data.index(b"PE\0\0")
nsec, = struct.unpack_from("<H", data, pe + 6)
opt = pe + 24
IMAGE_BASE, = struct.unpack_from("<I", data, opt + 28)
so = opt + struct.unpack_from("<H", data, pe + 20)[0]
secs = []
for i in range(nsec):
    off = so + i * 40
    name = data[off:off + 8].rstrip(b"\0").decode("latin1")
    vsize, vaddr, rsize, raddr = struct.unpack_from("<IIII", data, off + 8)
    secs.append((name, vaddr, vsize, raddr, rsize))


def va2off(v):
    r = v - IMAGE_BASE
    for n, va, vsz, ra, rs in secs:
        if va <= r < va + max(vsz, rs) and ra:
            return ra + (r - va)


def off2va(o):
    for n, va, vsz, ra, rs in secs:
        if ra and ra <= o < ra + rs:
            return va + (o - ra) + IMAGE_BASE


strmap = {}
for m in re.finditer(rb"[\x20-\x7E]{5,}", data):
    va = off2va(m.start())
    if va:
        strmap[va] = m.group().decode("latin1")[:60]

# 已知的全局：当前绑定的 FBO
NOTE = {
    0xBC7A48: "[当前绑定的 FBO id]",
    0xBC7A4C: "[是否默认帧缓冲 flag]",
    0xBFEC80: "[render target 栈深度]",
    0xBFEC7C: "[栈 head]",
    0xBFEC78: "[栈 mask]",
    0xBFEC74: "[栈容器]",
}

md = Cs(CS_ARCH_X86, CS_MODE_32)
md.detail = True


def show(start, length, label):
    off = va2off(start)
    print("\n===== %s  0x%08X =====" % (label, start))
    for ins in md.disasm(data[off:off + length], start):
        note = ""
        for op in ins.operands:
            if op.type == X86_OP_IMM:
                if op.imm in strmap:
                    note += '  ; "%s"' % strmap[op.imm]
                elif op.imm in NOTE:
                    note += "  ; " + NOTE[op.imm]
        print("0x%08X  %-20s %s %s%s" % (ins.address, ins.bytes.hex(), ins.mnemonic, ins.op_str, note))


# 例子1：collection / item surface 那处 push→pop 很近的一对
show(0x932800, 0x80, "Push/Pop 成对：Procedural Item Surface 附近")
# 例子2：背景 shading（房间背景 shader）那处
show(0x7B0580, 0x70, "背景 shading 的 push")
# 例子3：GL 侧真正切 framebuffer 的动作（用 0x8D40 = GL_FRAMEBUFFER）
o = None
for m in re.finditer(rb"\x68\x40\x8d\x00\x00", data):
    va = off2va(m.start())
    if va and 0x600000 < va:
        show(va - 0x30, 0x60, "切换 framebuffer 的 GL 动作（push 0x8D40=GL_FRAMEBUFFER）")
        break
