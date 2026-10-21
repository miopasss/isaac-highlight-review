"""在 isaac-ng.exe 里找 "PushRenderTarget: stack overflow!" 的引用点，并反汇编所在函数。

目的：搞清楚引擎是在哪个渲染环节 push render target —— 这决定了是"谁"把栈用满了。
"""
import struct, sys
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

EXE = r"D:\lenovosoftstore\install\steam\steamapps\common\The Binding of Isaac Rebirth\isaac-ng.exe"
data = open(EXE, "rb").read()

# ---------- PE ----------
pe = data.index(b"PE\0\0")
nsec, = struct.unpack_from("<H", data, pe + 6)
opt = pe + 24
image_base, = struct.unpack_from("<I", data, opt + 28)
sections = []
so = opt + struct.unpack_from("<H", data, pe + 20)[0]
for i in range(nsec):
    off = so + i * 40
    name = data[off:off + 8].rstrip(b"\0").decode("latin1")
    vsize, vaddr, rsize, raddr = struct.unpack_from("<IIII", data, off + 8)
    sections.append((name, vaddr, vsize, raddr, rsize))
print("ImageBase = 0x%08X" % image_base)
for s in sections:
    print("  %-8s VA=0x%08X vsz=0x%06X raw=0x%08X rsz=0x%06X" % s)


def off2va(o):
    for name, va, vsz, ra, rs in sections:
        if ra and ra <= o < ra + rs:
            return va + (o - ra) + image_base
    return None


def va2off(v):
    r = v - image_base
    for name, va, vsz, ra, rs in sections:
        if va <= r < va + max(vsz, rs):
            return ra + (r - va)
    return None


strings = [b"PushRenderTarget: stack overflow!", b"PopRenderTarget: stack is empty!"]
targets = {}
for s in strings:
    o = data.find(s)
    print("%-40s file_off=0x%08X VA=0x%08X" % (s.decode(), o, off2va(o)))
    targets[s.decode()] = off2va(o)

# ---------- 找 xref（imm32 = VA） ----------
text = next(s for s in sections if s[0] == ".text")
_, tva, tvsz, tra, trsz = text
tdata = data[tra:tra + trsz]
xrefs = {}
for label, va in targets.items():
    needle = struct.pack("<I", va)
    for i in range(len(tdata) - 4):
        if tdata[i:i + 4] == needle:
            # 往前看 1 字节是否是 push imm32 (0x68) / mov reg,imm32 (0xB8..0xBF) / call? 
            prev = tdata[i - 1] if i else 0
            kind = ""
            if prev == 0x68:
                kind = "push imm32"
            elif 0xB8 <= prev <= 0xBF:
                kind = "mov reg,imm32"
            elif tdata[i-2] == 0x68 if i >= 2 else False:
                kind = "push imm32 (+1 pad)"
            xrefs.setdefault(label, []).append((tva + image_base + i, kind, tdata[i-1]))
for label, xs in xrefs.items():
    print("\n== xrefs for %s ==" % label)
    for va, kind, prev in xs:
        print("  0x%08X  (%s, prevbyte=0x%02X)" % (va, kind or "?", prev))

# ---------- 反汇编 xref 所在函数 ----------
md = Cs(CS_ARCH_X86, CS_MODE_32)
md.detail = False

# 收集所有"看起来像字符串"的地址，方便注释
strmap = {}
for m in __import__("re").finditer(rb"[\x20-\x7E]{6,}", data):
    va = off2va(m.start())
    if va:
        strmap[va] = m.group().decode("latin1")[:90]


def find_func_start(off):
    """向前找函数头：常见的序言 55 8B EC / 55 89 E5 / 8B FF 55 8B EC，或 CC 填充后"""
    best = off
    i = off
    limit = max(0, off - 0x1200)
    while i > limit:
        i -= 1
        if data[i:i + 3] in (b"\x55\x8b\xec", b"\x55\x89\xe5") or data[i:i + 4] == b"\x8b\xff\x55\x8b":
            best = i
            break
        if data[i] == 0xCC and data[i + 1] in (0x55, 0xCC) and i + 2 < len(data):
            # int3 填充 -> 下一个字节可能是函数头
            best = i + 1
            break
    return best


for label, xs in xrefs.items():
    for va, kind, prev in xs:
        xo = va2off(va)
        if xo is None:
            continue
        fs = find_func_start(xo)
        print("\n########## %s @ 0x%08X  (函数起始 0x%08X, file 0x%08X) ##########" %
              (label, va, off2va(fs), fs))
        code = data[fs:fs + 0x500]
        for ins in md.disasm(code, off2va(fs)):
            line = "0x%08X  %-24s %s %s" % (ins.address, ins.bytes.hex(), ins.mnemonic, ins.op_str)
            # 注释字符串引用
            for op in ins.operands:
                if op.type == 3 and op.imm in strmap:  # X86_OP_IMM
                    line += '   ; "%s"' % strmap[op.imm]
            if ins.address > va + 0x120:
                break
            print(line)
