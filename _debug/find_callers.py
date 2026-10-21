"""找 PushRenderTarget(0x65B570) / PopRenderTarget(0x65B650) 的所有直接调用点，
并把每个调用点所在函数里引用到的字符串打出来 —— 用来判断是哪个渲染子系统在 push。"""
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
        strmap[va] = m.group().decode("latin1")[:110]

PUSH, POP = 0x65B570, 0x65B650
_, tva, tvsz, tra, trsz = next(s for s in sections if s[0] == ".text")
tdata = data[tra:tra + trsz]
base_va = tva + image_base

calls = {PUSH: [], POP: []}
for i in range(len(tdata) - 5):
    if tdata[i] == 0xE8:
        rel, = struct.unpack_from("<i", tdata, i + 1)
        tgt = base_va + i + 5 + rel
        if tgt in calls:
            calls[tgt].append(base_va + i)

print("PushRenderTarget 调用点: %d 个" % len(calls[PUSH]))
print("PopRenderTarget  调用点: %d 个" % len(calls[POP]))

md = Cs(CS_ARCH_X86, CS_MODE_32)
md.detail = True


def func_start(va):
    """从调用点往回找函数头（靠 c3 + cc 填充界定的边界）。"""
    off = va2off(va)
    end = off
    i = off - 1
    floor = max(0, off - 0x2000)
    while i > floor:
        if data[i] == 0xCC and data[i + 1] == 0xCC:
            # 跳过一段 cc
            j = i
            while j > floor and data[j] == 0xCC:
                j -= 1
            if data[j] in (0xC3, 0xCB, 0xC2):
                return off2va(j + 1)
            i = j
            continue
        i -= 1
    return None


def strings_in(vstart, vend):
    out = []
    off = va2off(vstart)
    n = vend - vstart
    for m in re.finditer(struct.pack("<I", 0), b""):
        pass
    # 扫连续 4 字节窗口，命中字符串 VA 就记下来
    for k in range(0, min(n, 0x3000) - 4):
        v, = struct.unpack_from("<I", data, off + k)
        if v in strmap:
            out.append(strmap[v])
    seen, uniq = set(), []
    for s in out:
        if s not in seen:
            seen.add(s)
            uniq.append(s)
    return uniq


for name, sites in (("PUSH", calls[PUSH]), ("POP", calls[POP])):
    print("\n############ %s 的调用点 ############" % name)
    for s in sorted(sites):
        fs = func_start(s)
        funcname_hint = ""
        if fs:
            strs = strings_in(fs, s)
            funcname_hint = " | ".join(strs[-6:])
        print("  调用 @0x%08X  函数头=%s  ; %s" % (s, hex(fs) if fs else "?", funcname_hint[:230]))
