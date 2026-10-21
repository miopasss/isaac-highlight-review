"""改进版：只接受"确实像返回地址"的栈值（前一两条指令是 call），
再在深度>=16 时刻打印主线程调用链。"""
import ctypes, ctypes.wintypes as wt, struct, time, subprocess, re

PROC = "isaac-ng.exe"; R = 0x400000
k32 = ctypes.WinDLL("kernel32", use_last_error=True)
EXE = r"D:\lenovosoftstore\install\steam\steamapps\common\The Binding of Isaac Rebirth\isaac-ng.exe"
data = open(EXE, "rb").read()
pe = data.index(b"PE\0\0"); nsec, = struct.unpack_from("<H", data, pe + 6); opt = pe + 24
IMAGE_BASE, = struct.unpack_from("<I", data, opt + 28); so = opt + struct.unpack_from("<H", data, pe + 20)[0]
secs = []
for i in range(nsec):
    off = so + i * 40; name = data[off:off+8].rstrip(b"\0").decode("latin1")
    vsize, vaddr, rsize, raddr = struct.unpack_from("<IIII", data, off + 8)
    secs.append((name, vaddr, vsize, raddr, rsize))
_, TEXT_VA, TEXT_VSZ, TEXT_RAW, _ = next(s for s in secs if s[0] == ".text")


def off2va(o):
    for n, va, vsz, ra, rs in secs:
        if ra and ra <= o < ra + rs:
            return va + (o - ra) + IMAGE_BASE


def va2off(v):
    r = v - IMAGE_BASE
    for n, va, vsz, ra, rs in secs:
        if va <= r < va + max(vsz, rs) and ra:
            return ra + (r - va)


strmap = {}
for m in re.finditer(rb"[\x20-\x7E]{6,}", data):
    va = off2va(m.start())
    if va:
        strmap[va] = m.group().decode("latin1")[:70]


def is_call_before(foff):
    """v 是返回地址，检查它前面的字节像不像 call。"""
    if foff < 8:
        return False
    b = data
    if b[foff - 5] == 0xE8:                                  # call rel32
        return True
    if b[foff - 6] == 0xFF and b[foff - 5] in (0x15, 0x25):   # call [abs32]
        return True
    if b[foff - 2] == 0xFF and (b[foff - 1] & 0x38) == 0x10:  # call r/m32 (/2)
        return True
    if b[foff - 3] == 0xFF and b[foff - 2] in (0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57):
        return True
    if b[foff - 7] == 0xFF and (b[foff - 6] & 0x38) == 0x10:  # call [reg+disp8]
        return True
    return False


_fc = {}


def fstart_f(fv):
    if fv in _fc:
        return _fc[fv]
    o = va2off(fv)
    res = None
    if o is not None:
        for i in range(o, max(0, o - 0x1C00), -1):
            if data[i:i + 3] in (b"\x55\x8b\xec", b"\x55\x89\xe5"):
                res = off2va(i); break
        if res is None:
            res = off2va(o)
    _fc[fv] = res
    return res


def hints_f(fv, back=0x600, fwd=0x300):
    o = va2off(fv)
    out = []
    if o is not None:
        for k in range(max(0, o - back), min(len(data) - 4, o + fwd)):
            val, = struct.unpack_from("<I", data, k)
            if val in strmap:
                out.append(strmap[val])
    seen, u = set(), []
    for s in out:
        if s not in seen:
            seen.add(s); u.append(s)
    return u


class CONTEXT(ctypes.Structure):
    _fields_ = [("ContextFlags", wt.DWORD), ("Dr0", wt.DWORD), ("Dr1", wt.DWORD), ("Dr2", wt.DWORD),
                ("Dr3", wt.DWORD), ("Dr6", wt.DWORD), ("Dr7", wt.DWORD), ("FloatSave", ctypes.c_byte * 112),
                ("SegGs", wt.DWORD), ("SegFs", wt.DWORD), ("SegEs", wt.DWORD), ("SegDs", wt.DWORD),
                ("Edi", wt.DWORD), ("Esi", wt.DWORD), ("Ebx", wt.DWORD), ("Edx", wt.DWORD),
                ("Ecx", wt.DWORD), ("Eax", wt.DWORD), ("Ebp", wt.DWORD), ("Eip", wt.DWORD),
                ("SegCs", wt.DWORD), ("EFlags", wt.DWORD), ("Esp", wt.DWORD), ("SegSs", wt.DWORD),
                ("ExtendedRegisters", ctypes.c_byte * 512)]


class THREADENTRY32(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD), ("th32ThreadID", wt.DWORD),
                ("th32OwnerProcessID", wt.DWORD), ("tpBasePri", wt.LONG), ("tpDeltaPri", wt.LONG), ("dwFlags", wt.DWORD)]


out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq " + PROC, "/FO", "CSV", "/NH"],
                     capture_output=True, text=True).stdout
pid = int(out.split(",")[1].strip('"'))
hp = k32.OpenProcess(0x0010 | 0x0400, False, pid)
base = None
for cand in (0x400000, 0x2D0000, 0x10000000):
    b = ctypes.create_string_buffer(0x24); n = ctypes.c_size_t()
    if k32.ReadProcessMemory(hp, ctypes.c_void_p(cand + (0xB47428 - R)), b, 0x24, ctypes.byref(n)) and b"PushRenderTarget" in b.raw:
        base = cand; break
delta = base - IMAGE_BASE
TEXT_LO, TEXT_HI = base + TEXT_VA, base + TEXT_VA + TEXT_VSZ


def read_some(addr, size, page=0x1000):
    buf = bytearray()
    for off in range(0, size, page):
        b = ctypes.create_string_buffer(min(page, size - off)); g = ctypes.c_size_t()
        if k32.ReadProcessMemory(hp, ctypes.c_void_p(addr + off), b, len(b), ctypes.byref(g)):
            buf += b.raw[:g.value]
        else:
            buf += b"\0" * min(page, size - off)
    return bytes(buf)


def depth():
    return struct.unpack("<I", read_some(base + (0xBFEC80 - R), 4))[0]


snap = k32.CreateToolhelp32Snapshot(0x4, 0)
te = THREADENTRY32(); te.dwSize = ctypes.sizeof(te)
tids = []
ok = k32.Thread32First(snap, ctypes.byref(te))
while ok:
    if te.th32OwnerProcessID == pid:
        tids.append(te.th32ThreadID)
    ok = k32.Thread32Next(snap, ctypes.byref(te))
k32.CloseHandle(snap)


def thread_ctx(tid):
    ht = k32.OpenThread(0x001F03FF, False, tid)
    if not ht:
        return None
    k32.SuspendThread(ht)
    ctx = CONTEXT(); ctx.ContextFlags = 0x0001003F
    okc = k32.Wow64GetThreadContext(ht, ctypes.byref(ctx))
    k32.ResumeThread(ht); k32.CloseHandle(ht)
    return (ctx.Eip, ctx.Esp, ctx.Ebp) if okc else None


def real_frames(esp, size=0x10000):
    """返回 [(stackoffset, file_va_return)]，只保留像返回地址的"""
    raw = read_some(esp, size)
    res = []
    for i in range(0, len(raw) - 4, 4):
        v, = struct.unpack_from("<I", raw, i)
        if not (TEXT_LO <= v < TEXT_HI):
            continue
        fv = v - delta
        fo = va2off(fv)
        if fo and is_call_before(fo):
            res.append((i, fv))
    return res


scores = []
for tid in tids:
    c = thread_ctx(tid)
    if not c:
        continue
    scores.append((len(real_frames(c[1])), tid, c))
scores.sort(reverse=True)
print("各线程真实帧数 top5:", [(n, t) for n, t, _ in scores[:5]])
if not scores or scores[0][0] == 0:
    print("没有线程有像样的栈帧"); raise SystemExit(0)
main_tid = scores[0][1]

print("\n等深度 >=16 ...")
t0 = time.time(); best = None
while time.time() - t0 < 20:
    d = depth()
    if d and d >= 16:
        c = thread_ctx(main_tid)
        d2 = depth()
        if c and d2 and d2 >= 16:
            best = (d2, c); break
    time.sleep(0.001)
if not best:
    print("没等到"); raise SystemExit(0)
d, (eip, esp, ebp) = best
print("深度=%d EIP=0x%08X ESP=0x%08X" % (d, eip, esp))
if TEXT_LO <= eip < TEXT_HI:
    print("EIP 函数 0x%08X ; %s" % (fstart_f(eip - delta) or 0, " | ".join(hints_f(eip - delta))[:200]))

fr = real_frames(esp, 0x30000)
print("\n真实栈帧 %d 个\n=== 调用链（从内到外）===" % len(fr))
prev = None
for off, fv in fr:
    st = fstart_f(fv - 1)
    if st == prev:
        continue
    prev = st
    print("  +0x%05X  RA=0x%08X  func=0x%08X  %s" % (off, fv, st or 0, " | ".join(hints_f(fv))[:220]))
