"""深度 >=16 时高频采样所有线程的 EIP，做函数直方图 —— 谁在这个时刻跑 = 谁在叠 render target。"""
import ctypes, ctypes.wintypes as wt, struct, time, subprocess, re
from collections import Counter

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
for m in re.finditer(rb"[\x20-\x7E]{6,}", data):
    va = off2va(m.start())
    if va:
        strmap[va] = m.group().decode("latin1")[:60]

_fc = {}


def fstart_f(fv):
    if fv in _fc:
        return _fc[fv]
    o = va2off(fv); res = None
    if o is not None:
        for i in range(o, max(0, o - 0x2000), -1):
            if data[i:i+3] in (b"\x55\x8b\xec", b"\x55\x89\xe5") or data[i:i+4] == b"\x8b\xff\x55\x8b":
                res = off2va(i); break
        if res is None:
            res = off2va(o)
    _fc[fv] = res
    return res


def hints_f(fv, back=0x700, fwd=0x300):
    o = va2off(fv); out = []
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
                ("Dr3", wt.DWORD), ("Dr6", wt.DWORD), ("Dr7", wt.DWORD), ("FloatSave", ctypes.c_byte*112),
                ("SegGs", wt.DWORD), ("SegFs", wt.DWORD), ("SegEs", wt.DWORD), ("SegDs", wt.DWORD),
                ("Edi", wt.DWORD), ("Esi", wt.DWORD), ("Ebx", wt.DWORD), ("Edx", wt.DWORD),
                ("Ecx", wt.DWORD), ("Eax", wt.DWORD), ("Ebp", wt.DWORD), ("Eip", wt.DWORD),
                ("SegCs", wt.DWORD), ("EFlags", wt.DWORD), ("Esp", wt.DWORD), ("SegSs", wt.DWORD),
                ("ExtendedRegisters", ctypes.c_byte*512)]


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


def rd32(a):
    b = ctypes.create_string_buffer(4); g = ctypes.c_size_t()
    if k32.ReadProcessMemory(hp, ctypes.c_void_p(a), b, 4, ctypes.byref(g)) and g.value == 4:
        return struct.unpack("<I", b.raw)[0]


def ctx_of(tid):
    ht = k32.OpenThread(0x1F03FF, False, tid)
    if not ht:
        return None
    k32.SuspendThread(ht)
    c = CONTEXT(); c.ContextFlags = 0x0001003F
    ok = k32.Wow64GetThreadContext(ht, ctypes.byref(c))
    k32.ResumeThread(ht); k32.CloseHandle(ht)
    return (c.Eip, c.Esp) if ok else None


snap = k32.CreateToolhelp32Snapshot(0x4, 0)
te = THREADENTRY32(); te.dwSize = ctypes.sizeof(te)
tids = []
ok = k32.Thread32First(snap, ctypes.byref(te))
while ok:
    if te.th32OwnerProcessID == pid:
        tids.append(te.th32ThreadID)
    ok = k32.Thread32Next(snap, ctypes.byref(te))
k32.CloseHandle(snap)

hist = Counter()
depth_at = Counter()
n_samp = 0
n_raw = 0
t0 = time.time()
while time.time() - t0 < 15:
    d = rd32(base + (0xBFEC80 - R))
    if not d or d < 16:
        continue
    hit = False
    for tid in tids:
        c = ctx_of(tid)
        if not c:
            continue
        eip = c[0]
        if TEXT_LO <= eip < TEXT_HI:
            hit = True
            n_raw += 1
            hist[fstart_f(eip - delta)] += 1
    if hit:
        n_samp += 1
        depth_at[d] += 1

print("采样 %d 次；深度分布 %s" % (n_samp, dict(depth_at)))
print("\n=== 深度>=16 时 EIP 落在的函数 ===")
for fn, c in hist.most_common(14):
    if fn == "(dll)":
        print("  DLL 内 %d 次" % c); continue
    print("\n  函数 0x%08X  %d 次 (%.0f%%)" % (fn, c, 100.0*c/max(1,n_samp)))
    print("     %s" % (" | ".join(hints_f(fn + 8))[:300]))
