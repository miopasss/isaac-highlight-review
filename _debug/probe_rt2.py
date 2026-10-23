"""校验基址 + 高频采样栈深度，看每帧的 push/pop 剖面。"""
import ctypes, ctypes.wintypes as wt, struct, time, subprocess, sys

PROC = "isaac-ng.exe"
R = 0x400000
RVA_DEPTH = 0xBFEC80 - R
RVA_MAP = 0xBFEC74 - R
RVA_MASK = 0xBFEC78 - R
RVA_HEAD = 0xBFEC7C - R
RVA_CUR_FBO = 0xBC7A48 - R
RVA_CUR_FLAG = 0xBC7A4C - R
RVA_STR = 0xB47428 - R

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
PROCESS_VM_READ, PROCESS_QUERY_INFORMATION = 0x10, 0x400


class MODULEENTRY32(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("th32ModuleID", wt.DWORD), ("th32ProcessID", wt.DWORD),
                ("GlblcntUsage", wt.DWORD), ("ProccntUsage", wt.DWORD), ("modBaseAddr", ctypes.c_void_p),
                ("modBaseSize", wt.DWORD), ("hModule", wt.HMODULE), ("szModule", ctypes.c_char * 256),
                ("szExePath", ctypes.c_char * 260)]


def module_info(pid, name):
    snap = k32.CreateToolhelp32Snapshot(0x18, pid)
    me = MODULEENTRY32(); me.dwSize = ctypes.sizeof(me)
    ok = k32.Module32First(snap, ctypes.byref(me)); res = {}
    while ok:
        n = me.szModule.decode("latin1").lower()
        res[n] = (me.modBaseAddr, me.modBaseSize)
        if n == name.lower():
            k32.CloseHandle(snap); return me.modBaseAddr, me.modBaseSize
        ok = k32.Module32Next(snap, ctypes.byref(me))
    k32.CloseHandle(snap); return None, None


out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq " + PROC, "/FO", "CSV", "/NH"],
                     capture_output=True, text=True).stdout
pid = int(out.split(",")[1].strip('"'))
h = k32.OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, False, pid)
base, size = module_info(pid, PROC)
print("pid=%d base=0x%08X size=0x%X" % (pid, base, size))


def read(addr, n):
    buf = ctypes.create_string_buffer(n); got = ctypes.c_size_t(0)
    if not k32.ReadProcessMemory(h, ctypes.c_void_p(addr), buf, n, ctypes.byref(got)) or got.value != n:
        return None
    return buf.raw


# 1) 基址校验：读 .rdata 里的字符串
s = read(base + RVA_STR, 0x24)
print("基址校验 ->", s)
print("MZ 头 ->", read(base, 2))

# 2) 关键全局
for name, rva in (("depth", RVA_DEPTH), ("map", RVA_MAP), ("mask", RVA_MASK),
                  ("head", RVA_HEAD), ("curFBO", RVA_CUR_FBO)):
    v = read(base + rva, 4)
    print("%-7s @+0x%06X = %s" % (name, rva, struct.unpack('<I', v)[0] if v else None))

# 3) 高频采样 1.2 秒
print("\n--- 2ms 采样 1.2s，只打印变化 ---")
t0 = time.perf_counter(); last = -1; n = 0; marks = []
while time.perf_counter() - t0 < 1.2:
    v = read(base + RVA_DEPTH, 4)
    d = struct.unpack('<I', v)[0] if v else -1
    if d != last:
        marks.append((round((time.perf_counter() - t0) * 1000, 1), d))
        last = d
    n += 1
print("采样 %d 次，深度变化 %d 次" % (n, len(marks)))
print("前 40 个变化:", marks[:40])
print("最大深度:", max(d for _, d in marks) if marks else None)
print("末尾 20 个:", marks[-20:])
