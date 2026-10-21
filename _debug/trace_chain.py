"""在 render target 深度 >=16 的时刻，把主线程的调用栈符号化打印出来。
（只读 + 微秒级 Suspend，不写内存）"""
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

_func_cache = {}


def fstart_f(fv):
    o = va2off(fv)
    if o is None:
        return None
    for i in range(o, max(0, o - 0x1C00), -1):
        if data[i:i + 3] in (b"\x55\x8b\xec", b"\x55\x89\xe5"):
            return off2va(i)
    return off2va(o)


def hints_f(fv, back=0x480, fwd=0x300):
    key = fv
    if key in _func_cache:
        return _func_cache[key]
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
    _func_cache[key] = u
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


def depth():
    b = read(base + (0xBFEC80 - R), 4)
    return struct.unpack("<I", b)[0] if b else None


snap = k32.CreateToolhelp32Snapshot(0x4, 0)
te = THREADENTRY32(); te.dwSize = ctypes.sizeof(te)
tids = []
ok = k32.Thread32First(snap, ctypes.byref(te))
while ok:
    if te.th32OwnerProcessID == pid:
        tids.append(te.th32ThreadID)
    ok = k32.Thread32Next(snap, ctypes.byref(te))
k32.CloseHandle(snap)

WOW64_CONTEXT_ALL = 0x0001003F


def thread_ctx(tid):
    ht = k32.OpenThread(0x001F03FF, False, tid)
    if not ht:
        return None
    k32.SuspendThread(ht)
    ctx = CONTEXT(); ctx.ContextFlags = WOW64_CONTEXT_ALL
    okc = k32.Wow64GetThreadContext(ht, ctypes.byref(ctx))
    k32.ResumeThread(ht); k32.CloseHandle(ht)
    return (ctx.Eip, ctx.Esp, ctx.Ebp) if okc else None


# 找主线程：栈上 .text 帧最多的
best = (0, None)
for tid in tids:
    c = thread_ctx(tid)
    if not c:
        continue
    raw = read(c[1], 0x4000) or b""
    n = sum(1 for i in range(0, len(raw) - 4, 4) if TEXT_LO <= struct.unpack_from("<I", raw, i)[0] < TEXT_HI)
    if n > best[0]:
        best = (n, tid)
main_tid = best[1]
print("主线程 tid=%s（栈上 %d 个 .text 帧）" % (main_tid, best[0]))

# 等到深度 >= 16 再抓
print("\n等待深度 >=16 ...")
t0 = time.time()
sample = None
while time.time() - t0 < 15:
    d = depth()
    if d and d >= 16:
        c = thread_ctx(main_tid)
        d2 = depth()
        if c and d2 and d2 >= 16:
            sample = (d2, c)
            break
    time.sleep(0.002)

if not sample:
    print("没等到"); raise SystemExit(0)

d, (eip, esp, ebp) = sample
print("抓到：深度=%d EIP=0x%08X ESP=0x%08X EBP=0x%08X" % (d, eip, esp, ebp))
raw = read(esp, 0x40000) or b""
print("读到栈 %d 字节" % len(raw))

prev_sig = None
frames = 0
print("\n=== 调用链（从内到外）===")
for i in range(0, len(raw) - 4, 4):
    v, = struct.unpack_from("<I", raw, i)
    if not (TEXT_LO <= v < TEXT_HI):
        continue
    fv = v - delta
    st = fstart_f(fv - 1)
    sig = st
    if sig == prev_sig:
        continue
    prev_sig = sig
    hs = hints_f(fv)
    frames += 1
    print("  +0x%05X  RA=0x%08X  func=0x%08X  %s" % (i, fv, st or 0, (" | ".join(hs))[:250]))
    if frames > 60:
        print("  ...")
        break
