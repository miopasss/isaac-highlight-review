"""用 EBP 链做精确回溯；命中 render target 深度 >=16 时打印调用链，
并标记"这个返回地址正好是 PushRenderTarget / PopRenderTarget 的调用点"。
"""
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

# 调用点表（文件 VA）
tdata = data[TEXT_RAW:TEXT_RAW + TEXT_VSZ]
base_va = TEXT_VA + IMAGE_BASE
PUSH_SITES, POP_SITES = set(), set()
for i in range(len(tdata) - 5):
    if tdata[i] == 0xE8:
        rel, = struct.unpack_from("<i", tdata, i + 1)
        t = base_va + i + 5 + rel
        if t == 0x65B570:
            PUSH_SITES.add(base_va + i)
        elif t == 0x65B650:
            POP_SITES.add(base_va + i)


def is_call_before(foff):
    if foff < 8:
        return False
    b = data
    return (b[foff - 5] == 0xE8 or
            (b[foff - 6] == 0xFF and b[foff - 5] in (0x15, 0x25)) or
            (b[foff - 2] == 0xFF and (b[foff - 1] & 0x38) == 0x10) or
            (b[foff - 3] == 0xFF and b[foff - 2] in range(0x50, 0x58)) or
            (b[foff - 7] == 0xFF and (b[foff - 6] & 0x38) == 0x10))


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


def read(addr, n):
    b = ctypes.create_string_buffer(n); g = ctypes.c_size_t()
    if k32.ReadProcessMemory(hp, ctypes.c_void_p(addr), b, n, ctypes.byref(g)) and g.value == n:
        return b.raw


def rd32(addr):
    b = read(addr, 4)
    return struct.unpack("<I", b)[0] if b else None


def depth():
    return rd32(base + (0xBFEC80 - R))


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


def ebp_chain(ebp, esp, limit=40):
    """从 EBP 走帧指针链"""
    frames = []
    cur = ebp
    for _ in range(limit):
        if cur is None or cur <= esp - 4 or cur >= 0x7FFFFFFF:
            break
        ra = rd32(cur + 4)
        nxt = rd32(cur)
        if ra is None:
            break
        fv = ra - delta
        fo = va2off(fv)
        ok = fo is not None and is_call_before(fo)
        frames.append((cur, fv, ok))
        if nxt is None or nxt <= cur:
            break
        cur = nxt
    return frames


# 选主线程：EBP 链最像样的
scores = []
for tid in tids:
    c = thread_ctx(tid)
    if not c:
        continue
    ch = ebp_chain(c[2], c[1], 60)
    good = sum(1 for _, _, ok in ch if ok)
    scores.append((good, tid, c, ch))
scores.sort(key=lambda x: -x[0])
print("EBP 链质量 top5:", [(g, t) for g, t, _, _ in scores[:5]])
main_tid = scores[0][1]

print("\n等深度 >=16 ...")
t0 = time.time(); pick = None
while time.time() - t0 < 20:
    d = depth()
    if d and d >= 16:
        c = thread_ctx(main_tid)
        d2 = depth()
        if c and d2 and d2 >= 16:
            pick = (d2, c); break
    time.sleep(0.001)
if not pick:
    print("没等到"); raise SystemExit(0)

d, (eip, esp, ebp) = pick
print("深度=%d EIP=0x%08X ESP=0x%08X EBP=0x%08X" % (d, eip, esp, ebp))
ch = ebp_chain(ebp, esp)
print("\n=== EBP 链（内 → 外），%d 帧 ===" % len(ch))
for ebpv, fv, ok in ch:
    st = fstart_f(fv - 1)
    mark = ""
    if (fv - 1) in PUSH_SITES or (fv - 5) in PUSH_SITES:
        mark = "   <<<< 这是 PushRenderTarget 调用点"
    elif (fv - 1) in POP_SITES or (fv - 5) in POP_SITES:
        mark = "   <<<< 这是 PopRenderTarget 调用点"
    elif not ok:
        mark = "   (?)"
    print("  ebp=0x%08X RA=0x%08X func=0x%08X%s\n        %s" %
          (ebpv, fv, st or 0, mark, (" | ".join(hints_f(fv)))[:200]))
