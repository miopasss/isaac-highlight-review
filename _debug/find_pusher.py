"""找出"谁在每帧叠 18 层 render target"：
从每个线程的 TEB 拿栈范围，然后在栈里搜 PushRenderTarget 的 37 个调用点的返回地址。
栈里出现哪些返回地址 = 正在嵌套的渲染路径。

（不挂断点、不改内存；只读。）
"""
import ctypes, ctypes.wintypes as wt, struct, time, subprocess, sys, re

PROC = "isaac-ng.exe"
R = 0x400000
k32 = ctypes.WinDLL("kernel32", use_last_error=True)
ntdll = ctypes.WinDLL("ntdll")

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

_, TEXT_VA, TEXT_VSZ, _, _ = next(s for s in secs if s[0] == ".text")
tdata = data[next(s[3] for s in secs if s[0] == ".text"):][:TEXT_VSZ]
base_va = TEXT_VA + IMAGE_BASE
PUSH, POP = 0x65B570, 0x65B650
pushes, pops = [], []
for i in range(len(tdata) - 5):
    if tdata[i] == 0xE8:
        rel, = struct.unpack_from("<i", tdata, i + 1)
        t = base_va + i + 5 + rel
        if t == PUSH:
            pushes.append(base_va + i)
        elif t == POP:
            pops.append(base_va + i)
print("push 调用点 %d 个, pop 调用点 %d 个" % (len(pushes), len(pops)))


def hints(v, back=0x600, fwd=0x500):
    o = va2off(v)
    if o is None:
        return []
    out = []
    for k in range(max(0, o - back), min(len(data) - 4, o + fwd)):
        val, = struct.unpack_from("<I", data, k)
        if val in strmap:
            out.append(strmap[val])
    seen, uniq = set(), []
    for s in out:
        if s not in seen:
            seen.add(s); uniq.append(s)
    return uniq


def fstart(v):
    o = va2off(v)
    if o is None:
        return None
    for i in range(o, max(0, o - 0x2000), -1):
        if data[i:i + 3] in (b"\x55\x8b\xec", b"\x55\x89\xe5"):
            return off2va(i)
    return None


# ---------- 进程/线程 ----------
out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq " + PROC, "/FO", "CSV", "/NH"],
                     capture_output=True, text=True).stdout
pid = int(out.split(",")[1].strip('"'))
hp = k32.OpenProcess(0x0010 | 0x0400, False, pid)

base = None
for cand in (0x400000, 0x2D0000, 0x10000000):
    b = ctypes.create_string_buffer(0x24); n = ctypes.c_size_t()
    if k32.ReadProcessMemory(hp, ctypes.c_void_p(cand + (0xB47428 - R)), b, 0x24, ctypes.byref(n)) \
            and b"PushRenderTarget" in b.raw:
        base = cand; break
print("pid=%d base=0x%08X" % (pid, base))
delta = base - IMAGE_BASE   # 运行时基址 - 文件基址


class TIB(ctypes.Structure):
    _fields_ = [("ExceptionList", wt.DWORD), ("StackBase", wt.DWORD), ("StackLimit", wt.DWORD),
                ("SubSystemTib", wt.DWORD), ("FiberData", wt.DWORD), ("ArbitraryUserPointer", wt.DWORD),
                ("Self", wt.DWORD)]


class TBI(ctypes.Structure):
    _fields_ = [("ExitStatus", ctypes.c_long), ("TebBaseAddress", ctypes.c_void_p),
                ("UniqueProcess", ctypes.c_void_p), ("UniqueThread", ctypes.c_void_p),
                ("AffinityMask", ctypes.c_void_p), ("BasePriority", ctypes.c_long),
                ("Pad", ctypes.c_byte * 16)]


TH32CS_SNAPTHREAD = 0x4


class THREADENTRY32(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD), ("th32ThreadID", wt.DWORD),
                ("th32OwnerProcessID", wt.DWORD), ("tpBasePri", wt.LONG), ("tpDeltaPri", wt.LONG),
                ("dwFlags", wt.DWORD)]


snap = k32.CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0)
te = THREADENTRY32(); te.dwSize = ctypes.sizeof(te)
tids = []
ok = k32.Thread32First(snap, ctypes.byref(te))
while ok:
    if te.th32OwnerProcessID == pid:
        tids.append(te.th32ThreadID)
    ok = k32.Thread32Next(snap, ctypes.byref(te))
k32.CloseHandle(snap)
print("线程 %d 个" % len(tids))

RVA_DEPTH = 0xBFEC80 - R


def depth():
    b = ctypes.create_string_buffer(4); n = ctypes.c_size_t()
    if k32.ReadProcessMemory(hp, ctypes.c_void_p(base + RVA_DEPTH), b, 4, ctypes.byref(n)) and n.value == 4:
        return struct.unpack("<I", b.raw)[0]


def read(addr, n):
    b = ctypes.create_string_buffer(n); g = ctypes.c_size_t()
    if k32.ReadProcessMemory(hp, ctypes.c_void_p(addr), b, n, ctypes.byref(g)) and g.value == n:
        return b.raw


pushset = {p + 5 - delta: p + 5 for p in pushes}   # 返回地址(运行时) -> 调用点(文件VA)
# 注意：delta 是运行时基址偏移，调用点也在运行时域里；统一用文件 VA 表示
push_ret_file = {p + 5: p for p in pushes}

def scan_once():
    found = {}
    for tid in tids:
        ht = k32.OpenThread(0x0008 | 0x0040 | 0x0002 | 0x0001, False, tid)
        if not ht:
            continue
        tbi = TBI(); ret = ctypes.c_ulong(0)
        st = ntdll.NtQueryInformationThread(ctypes.c_void_p(ht), 0, ctypes.byref(tbi),
                                            ctypes.sizeof(tbi), ctypes.byref(ret))
        k32.CloseHandle(ht)
        if st != 0 or not tbi.TebBaseAddress:
            continue
        tib = read(tbi.TebBaseAddress, 28)
        if not tib:
            continue
        ex, sb, sl = struct.unpack_from("<III", tib, 0)
        if not (0x10000 < sl < sb < 0x7FFFFFFF and sb - sl < 0x400000):
            continue
        size = sb - sl
        raw = read(sl, size)
        if not raw:
            continue
        for i in range(0, len(raw) - 4, 4):
            v, = struct.unpack_from("<I", raw, i)
            fv = v - delta
            if fv in push_ret_file:
                site = push_ret_file[fv]
                found.setdefault(site, []).append((tid, sl + i, fv - 5))
    return found


best = None
for attempt in range(200):
    d = depth()
    if d and d >= 16:
        f = scan_once()
        if f and (best is None or sum(len(v) for v in f.values()) > sum(len(v) for v in best[1].values())):
            best = (d, f)
            if len(f) >= 1:
                break
    time.sleep(0.004)

if not best:
    print("没抓到（也许栈在别的线程 / 深度没到 16）")
    sys.exit(0)

d, f = best
print("\n=== 深度 %d 时的栈上 push 调用点 ===" % d)
for site, hits in sorted(f.items(), key=lambda kv: -len(kv[1])):
    print("\n调用点 0x%08X（命中 %d 次，最深处 esp=0x%08X）" % (site, len(hits), min(h[1] for h in hits)))
    print("  所在函数 0x%08X" % (fstart(site) or 0))
    print("  附近字符串: %s" % (" | ".join(hints(site))[:400]))
