"""零风险采样：发现 render target 栈深度 >= 16 时，短暂挂起主线程读它的调用栈。

不写内存、不下断点，只 SuspendThread + GetThreadContext + ReadProcessMemory + ResumeThread。
目的是回答：到底是谁在每帧把 render target 叠到 18 层。
"""
import ctypes, ctypes.wintypes as wt, struct, time, subprocess, sys, re

PROC = "isaac-ng.exe"
R = 0x400000
k32 = ctypes.WinDLL("kernel32", use_last_error=True)

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


# 字符串表：VA -> 文本
strmap = {}
for m in re.finditer(rb"[\x20-\x7E]{6,}", data):
    va = off2va(m.start())
    if va:
        strmap[va] = m.group().decode("latin1")[:70]

TEXT_VA, TEXT_VSZ = next((va, vsz) for n, va, vsz, ra, rs in secs if n == ".text")
TEXT_LO, TEXT_HI = IMAGE_BASE + TEXT_VA, IMAGE_BASE + TEXT_VA + TEXT_VSZ


def fstart(v):
    """往前找函数头 55 8B EC / 55 89 E5"""
    o = va2off(v)
    if o is None:
        return None
    for i in range(o, max(0, o - 0x2000), -1):
        if data[i:i + 3] in (b"\x55\x8b\xec", b"\x55\x89\xe5"):
            return off2va(i)
    return off2va(o)


def hints(v, back=0x700, fwd=0x900):
    """给地址附近引用到的字符串做注释 —— 猜这个函数在干什么"""
    o = va2off(v)
    if o is None:
        return []
    out = []
    lo = max(0, o - back)
    for k in range(lo, min(len(data) - 4, o + fwd)):
        val, = struct.unpack_from("<I", data, k)
        if val in strmap:
            out.append(strmap[val])
    seen, uniq = set(), []
    for s in out:
        if s not in seen:
            seen.add(s)
            uniq.append(s)
    return uniq


ok2 = k32.OpenProcess(0x0010 | 0x0400, False, 0)  # placeholder

PROCESS_VM_READ, PROCESS_QUERY_INFORMATION = 0x10, 0x400
TH32CS_SNAPTHREAD = 0x4


class THREADENTRY32(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD), ("th32ThreadID", wt.DWORD),
                ("th32OwnerProcessID", wt.DWORD), ("tpBasePri", wt.LONG), ("tpDeltaPri", wt.LONG),
                ("dwFlags", wt.DWORD)]


class CONTEXT(ctypes.Structure):
    _fields_ = [("ContextFlags", wt.DWORD),
                ("Dr0", wt.DWORD), ("Dr1", wt.DWORD), ("Dr2", wt.DWORD), ("Dr3", wt.DWORD),
                ("Dr6", wt.DWORD), ("Dr7", wt.DWORD),
                ("FloatSave", ctypes.c_byte * 112),
                ("SegGs", wt.DWORD), ("SegFs", wt.DWORD), ("SegEs", wt.DWORD), ("SegDs", wt.DWORD),
                ("Edi", wt.DWORD), ("Esi", wt.DWORD), ("Ebx", wt.DWORD), ("Edx", wt.DWORD),
                ("Ecx", wt.DWORD), ("Eax", wt.DWORD), ("Ebp", wt.DWORD), ("Eip", wt.DWORD),
                ("SegCs", wt.DWORD), ("EFlags", wt.DWORD), ("Esp", wt.DWORD), ("SegSs", wt.DWORD),
                ("ExtendedRegisters", ctypes.c_byte * 512)]


CONTEXT_FULL = 0x00010007


def tasklist_pid(proc):
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq " + proc, "/FO", "CSV", "/NH"],
                         capture_output=True, text=True).stdout
    if "isaac" not in out.lower():
        return None
    return int(out.split(",")[1].strip('"'))


def threads_of(pid):
    snap = k32.CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0)
    te = THREADENTRY32(); te.dwSize = ctypes.sizeof(te)
    out = []
    ok = k32.Thread32First(snap, ctypes.byref(te))
    while ok:
        if te.th32OwnerProcessID == pid:
            out.append(te.th32ThreadID)
        ok = k32.Thread32Next(snap, ctypes.byref(te))
    k32.CloseHandle(snap)
    return out


pid = tasklist_pid(PROC)
hp = k32.OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, False, pid)
base = None
# 用 MZ 校验 + 前面已知的字符串地址找基址
for cand in (0x400000, 0x2D0000, 0x10000000):
    buf = ctypes.create_string_buffer(2); n = ctypes.c_size_t()
    if k32.ReadProcessMemory(hp, ctypes.c_void_p(cand), buf, 2, ctypes.byref(n)) and buf.raw == b"MZ":
        # 再校验字符串
        sb = ctypes.create_string_buffer(0x24); n2 = ctypes.c_size_t()
        if k32.ReadProcessMemory(hp, ctypes.c_void_p(cand + (0xB47428 - R)), sb, 0x24, ctypes.byref(n2)) \
                and b"PushRenderTarget" in sb.raw:
            base = cand
            break
if base is None:
    print("找不到基址"); sys.exit(1)
print("pid=%d  base=0x%08X" % (pid, base))

RVA_DEPTH = 0xBFEC80 - R


def depth():
    b = ctypes.create_string_buffer(4); n = ctypes.c_size_t()
    if k32.ReadProcessMemory(hp, ctypes.c_void_p(base + RVA_DEPTH), b, 4, ctypes.byref(n)) and n.value == 4:
        return struct.unpack("<I", b.raw)[0]
    return None


thr = threads_of(pid)
print("线程数 =", len(thr))

samples = []
t0 = time.time()
while time.time() - t0 < 25 and len(samples) < 6:
    d = depth()
    if d is None:
        break
    if d < 16:
        time.sleep(0.001)
        continue
    # 在这一刻抓所有线程的栈（主线程优先，其实全都抓）
    for tid in thr:
        ht = k32.OpenThread(0x0008 | 0x0040, False, tid)  # SUSPEND_RESUME | GET_CONTEXT
        if not ht:
            continue
        try:
            k32.SuspendThread(ht)
            ctx = CONTEXT(); ctx.ContextFlags = CONTEXT_FULL
            if k32.GetThreadContext(ht, ctypes.byref(ctx)):
                d2 = depth()
                stack = ctypes.create_string_buffer(0x3000)
                n = ctypes.c_size_t()
                got = k32.ReadProcessMemory(hp, ctypes.c_void_p(ctx.Esp), stack, 0x3000, ctypes.byref(n))
                if got:
                    raws = stack.raw[:n.value]
                else:
                    raws = b""
                samples.append((tid, d2, ctx.Eip, ctx.Esp, raws))
        finally:
            k32.ResumeThread(ht)
            k32.CloseHandle(ht)
    # 同一时刻只抓一轮
    if samples:
        break
    time.sleep(0.002)

print("抓到 %d 个样本" % len(samples))
for tid, d2, eip, esp, raws in samples:
    print("\n--- tid=%d  取样时深度=%s  EIP=0x%08X ESP=0x%08X ---" % (tid, d2, eip, esp))
    # EIP 所在函数
    if TEXT_LO <= eip <= TEXT_HI:
        print("  EIP 所在函数 0x%08X : %s" % (fstart(eip) or 0, " | ".join(hints(eip)[-4:])))
    # 栈回溯：找 .text 里的返回地址
    seen = set()
    printed = 0
    for i in range(0, len(raws) - 4, 4):
        v, = struct.unpack_from("<I", raws, i)
        if not (base + (TEXT_VA + R - R) <= v <= base + (TEXT_VA + TEXT_VSZ + R - R)):
            continue
        if v in seen:
            continue
        seen.add(v)
        st = fstart(v)
        if st in seen:
            continue
        seen.add(st)
        hs = hints(v)
        print("  [esp+0x%04X] RA=0x%08X  func=0x%08X  ; %s" % (i, v, st or 0, " | ".join(hs[-5:])[:200]))
        printed += 1
        if printed >= 22:
            break
