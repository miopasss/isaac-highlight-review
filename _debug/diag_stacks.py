import ctypes, ctypes.wintypes as wt, struct, time, subprocess, re

PROC = "isaac-ng.exe"; R = 0x400000
k32 = ctypes.WinDLL("kernel32", use_last_error=True); ntdll = ctypes.WinDLL("ntdll")
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

out = subprocess.run(["tasklist","/FI","IMAGENAME eq "+PROC,"/FO","CSV","/NH"], capture_output=True, text=True).stdout
pid = int(out.split(",")[1].strip('"'))
hp = k32.OpenProcess(0x0010|0x0400, False, pid)
base = None
for cand in (0x400000, 0x2D0000, 0x10000000):
    b = ctypes.create_string_buffer(0x24); n = ctypes.c_size_t()
    if k32.ReadProcessMemory(hp, ctypes.c_void_p(cand + (0xB47428-R)), b, 0x24, ctypes.byref(n)) and b"PushRenderTarget" in b.raw:
        base = cand; break
print("pid", pid, "base", hex(base))
TEXT_LO, TEXT_HI = base + TEXT_VA, base + TEXT_VA + TEXT_VSZ

class TBI(ctypes.Structure):
    _fields_ = [("ExitStatus", ctypes.c_long), ("TebBaseAddress", ctypes.c_void_p),
                ("UniqueProcess", ctypes.c_void_p), ("UniqueThread", ctypes.c_void_p),
                ("AffinityMask", ctypes.c_void_p), ("BasePriority", ctypes.c_long), ("Pad", ctypes.c_byte*16)]
class THREADENTRY32(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD),("cntUsage", wt.DWORD),("th32ThreadID", wt.DWORD),
                ("th32OwnerProcessID", wt.DWORD),("tpBasePri", wt.LONG),("tpDeltaPri", wt.LONG),("dwFlags", wt.DWORD)]

snap = k32.CreateToolhelp32Snapshot(0x4, 0); te = THREADENTRY32(); te.dwSize = ctypes.sizeof(te)
tids = []; ok = k32.Thread32First(snap, ctypes.byref(te))
while ok:
    if te.th32OwnerProcessID == pid: tids.append(te.th32ThreadID)
    ok = k32.Thread32Next(snap, ctypes.byref(te))
k32.CloseHandle(snap)

def read(addr, n):
    b = ctypes.create_string_buffer(n); g = ctypes.c_size_t()
    if k32.ReadProcessMemory(hp, ctypes.c_void_p(addr), b, n, ctypes.byref(g)) and g.value == n: return b.raw

def depth():
    b = read(base + (0xBFEC80-R), 4)
    return struct.unpack("<I", b)[0] if b else None

print("\n--- 线程 TEB / 栈范围 / 栈上 .text 返回地址数 ---")
stacks = []
for tid in tids:
    ht = k32.OpenThread(0x0040, False, tid)
    if not ht: continue
    tbi = TBI(); r = ctypes.c_ulong(0)
    st = ntdll.NtQueryInformationThread(ctypes.c_void_p(ht), 0, ctypes.byref(tbi), ctypes.sizeof(tbi), ctypes.byref(r))
    k32.CloseHandle(ht)
    if st != 0: 
        print(" tid %6d  NtQueryInformationThread fail %d" % (tid, st)); continue
    tib = read(tbi.TebBaseAddress, 12)
    if not tib: print(" tid %6d  TEB 读失败" % tid); continue
    ex, sb, sl = struct.unpack("<III", tib, 0)
    raw = read(sl, sb - sl) or b""
    cnt = 0
    for i in range(0, len(raw)-4, 4):
        v, = struct.unpack_from("<I", raw, i)
        if TEXT_LO <= v < TEXT_HI: cnt += 1
    print(" tid %6d teb=0x%08X  stack=[0x%08X,0x%08X) %6dKB  .text返回地址 %5d" % (tid, tbi.TebBaseAddress, sl, sb, (sb-sl)//1024, cnt))
    stacks.append((tid, sl, sb, cnt, tbi.TebBaseAddress))

print("\n--- 6 秒内采样深度分布 ---")
hist = {}
t0 = time.time()
while time.time() - t0 < 6:
    d = depth()
    hist[d] = hist.get(d, 0) + 1
print(sorted(hist.items(), key=lambda kv: -kv[1])[:12])
