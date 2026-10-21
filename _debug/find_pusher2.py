"""用 Wow64GetThreadContext 拿 32 位线程的真实 ESP，在栈里搜 PushRenderTarget 调用点的返回地址。
只读、只短暂 Suspend（微秒级），不写内存、不下断点。
"""
import ctypes, ctypes.wintypes as wt, struct, time, subprocess, sys, re

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

_, TEXT_VA, TEXT_VSZ, TEXT_RAW, _ = next(s for s in secs if s[0] == ".text")
base_va = TEXT_VA + IMAGE_BASE
tdata = data[TEXT_RAW:TEXT_RAW + TEXT_VSZ]
pushes, pops = [], []
for i in range(len(tdata) - 5):
    if tdata[i] == 0xE8:
        rel, = struct.unpack_from("<i", tdata, i + 1)
        t = base_va + i + 5 + rel
        if t == 0x65B570:
            pushes.append(base_va + i)
        elif t == 0x65B650:
            pops.append(base_va + i)
PUSH_RET = {p + 5: p for p in pushes}
POP_RET = {p + 5: p for p in pops}


def hints(v, back=0x500, fwd=0x400):
    o = va2off(v)
    if o is None:
        return []
    out = []
    for k in range(max(0, o - back), min(len(data) - 4, o + fwd)):
        val, = struct.unpack_from("<I", data, k)
        if val in strmap:
            out.append(strmap[val])
    seen, u = set(), []
    for s in out:
        if s not in seen:
            seen.add(s); u.append(s)
    return u


def fstart(v):
    o = va2off(v)
    if o is None:
        return None
    for i in range(o, max(0, o - 0x2000), -1):
        if data[i:i + 3] in (b"\x55\x8b\xec", b"\x55\x89\xe5"):
            return off2va(i)
    return off2va(o)


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
print("pid=%d base=0x%08X delta=0x%X" % (pid, base, delta))

snap = k32.CreateToolhelp32Snapshot(0x4, 0)
te = THREADENTRY32(); te.dwSize = ctypes.sizeof(te)
tids = []
ok = k32.Thread32First(snap, ctypes.byref(te))
while ok:
    if te.th32OwnerProcessID == pid:
        tids.append(te.th32ThreadID)
    ok = k32.Thread32Next(snap, ctypes.byref(te))
k32.CloseHandle(snap)


def read(addr, n):
    b = ctypes.create_string_buffer(n); g = ctypes.c_size_t()
    if k32.ReadProcessMemory(hp, ctypes.c_void_p(addr), b, n, ctypes.byref(g)) and g.value == n:
        return b.raw


def depth():
    b = read(base + (0xBFEC80 - R), 4)
    return struct.unpack("<I", b)[0] if b else None


WOW64_CONTEXT_ALL = 0x0001003F
THREAD_ALL = 0x1F03FF


class SNAP:
    pass


# 缓存每个线程的 ESP（线程栈位置固定，缓存一次就够）
def snapshot_threads():
    res = {}
    for tid in tids:
        ht = k32.OpenThread(THREAD_ALL, False, tid)
        if not ht:
            continue
        k32.SuspendThread(ht)
        ctx = CONTEXT(); ctx.ContextFlags = WOW64_CONTEXT_ALL
        okc = k32.Wow64GetThreadContext(ht, ctypes.byref(ctx))
        k32.ResumeThread(ht)
        k32.CloseHandle(ht)
        if okc:
            res[tid] = (ctx.Eip, ctx.Esp, ctx.Ebp)
    return res


snaps = snapshot_threads()
print("拿到上下文的线程:", {k: (hex(v[0]), hex(v[1])) for k, v in snaps.items()})

# 选 ESP 落在 .text 附近的线程（正在执行游戏代码）
cands = []
for tid, (eip, esp, ebp) in snaps.items():
    raw = read(esp, 0x4000) or b""
    n = 0
    hits = []
    for i in range(0, len(raw) - 4, 4):
        v, = struct.unpack_from("<I", raw, i)
        if TEXT_LO <= v < TEXT_HI:
            n += 1
            f = v - delta
            if f in PUSH_RET:
                hits.append((i, f, "PUSH@0x%08X" % PUSH_RET[f]))
            elif f in POP_RET:
                hits.append((i, f, "POP@0x%08X" % POP_RET[f]))
    cands.append((n, tid, eip, esp, hits))

cands.sort(reverse=True)
print("\n--- 各线程栈上的 .text 返回地址数量 / render target 调用点 ---")
for n, tid, eip, esp, hits in cands[:8]:
    print("tid %6d eip=0x%08X esp=0x%08X  .text帧=%3d  RT调用点=%s" %
          (tid, eip, esp, n, [(h[0], h[2]) for h in hits] or "无"))

# 挑帧最多的线程，在深度>=16 的时刻连续采样，统计调用点直方图
best_tid = cands[0][1] if cands and cands[0][0] else None
print("\n采样线程 =", best_tid)
hist = {}
depth_hist = {}
t0 = time.time()
got = 0
while time.time() - t0 < 8 and got < 400:
    d = depth()
    if d is None:
        break
    if d < 16:
        time.sleep(0.002)
        continue
    s = snapshot_threads()
    if best_tid in s:
        eip, esp, ebp = s[best_tid]
        raw = read(esp, 0x20000) or b""
        got += 1
        depth_hist[d] = depth_hist.get(d, 0) + 1
        for i in range(0, len(raw) - 4, 4):
            v, = struct.unpack_from("<I", raw, i)
            f = v - delta
            if f in PUSH_RET:
                site = PUSH_RET[f]
                hist[site] = hist.get(site, 0) + 1
    time.sleep(0.001)

print("深度分布:", sorted(depth_hist.items()))
print("\n=== 深度>=16 时出现的 push 调用点（%d 次采样）===" % got)
for site, c in sorted(hist.items(), key=lambda kv: -kv[1]):
    print("\n调用点 0x%08X  出现 %d 次  所在函数 %s" % (site, c, hex(fstart(site) or 0)))
    print("  ; " + " | ".join(hints(site))[:420])
