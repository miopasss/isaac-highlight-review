"""只读探测：读取运行中的以撒进程里 PushRenderTarget 的栈深度计数器。

引擎源码（反汇编）事实：
  PushRenderTarget @ 0x0065B570
      mov ecx, [0xBFEC80]     ; 当前 render target 栈深度
      cmp ecx, 0x10           ; 上限 16
      jb  skip                ; <16 时不报错
      ... "PushRenderTarget: stack overflow!"
      ; 注意：报错后仍然继续 push，计数继续 +1
  PopRenderTarget  @ 0x0065B650
      cmp [0xBFEC80], 0       ; 为 0 时报 "stack is empty!"
      ... sub [0xBFEC80], 1

所以：只要 [0xBFEC80] 持续增长 = 每帧有一次 push 没有配对 pop（泄漏），
增长速率 ≈ 帧率。
"""
import ctypes, ctypes.wintypes as wt, struct, time, subprocess, sys

PROC = "isaac-ng.exe"
RVA_DEPTH = 0xBFEC80 - 0x400000      # 0x7FEC80
RVA_MAP_PTR = 0xBFEC74 - 0x400000    # 栈容器指针
RVA_MASK = 0xBFEC78 - 0x400000
RVA_HEAD = 0xBFEC7C - 0x400000
RVA_CUR_FBO = 0xBC7A48 - 0x400000
RVA_CUR_FLAG = 0xBC7A4C - 0x400000

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
PROCESS_VM_READ = 0x0010
PROCESS_QUERY_INFORMATION = 0x0400

TH32CS_SNAPMODULE = 0x8
TH32CS_SNAPMODULE32 = 0x10


class MODULEENTRY32(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("th32ModuleID", wt.DWORD), ("th32ProcessID", wt.DWORD),
                ("GlblcntUsage", wt.DWORD), ("ProccntUsage", wt.DWORD), ("modBaseAddr", ctypes.c_void_p),
                ("modBaseSize", wt.DWORD), ("hModule", wt.HMODULE), ("szModule", ctypes.c_char * 256),
                ("szExePath", ctypes.c_char * 260)]


def module_base(pid, name):
    snap = k32.CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid)
    if snap == -1:
        return None
    me = MODULEENTRY32()
    me.dwSize = ctypes.sizeof(me)
    ok = k32.Module32First(snap, ctypes.byref(me))
    base = None
    while ok:
        if me.szModule.decode("latin1").lower() == name.lower():
            base = me.modBaseAddr
            break
        ok = k32.Module32Next(snap, ctypes.byref(me))
    k32.CloseHandle(snap)
    return base


out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq " + PROC, "/FO", "CSV", "/NH"],
                     capture_output=True, text=True).stdout.strip()
if not out or out.startswith("信息") or "isaac" not in out.lower():
    print("游戏没在跑:", out[:200]); sys.exit(1)
pid = int(out.split(",")[1].strip('"'))
print("pid =", pid)

h = k32.OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, False, pid)
if not h:
    print("OpenProcess 失败, err =", ctypes.get_last_error()); sys.exit(1)

base = module_base(pid, PROC)
print("模块基址 = 0x%08X" % (base or 0))


def rd_dword(off):
    buf = ctypes.create_string_buffer(4)
    n = ctypes.c_size_t(0)
    if not k32.ReadProcessMemory(h, ctypes.c_void_p(base + off), buf, 4, ctypes.byref(n)) or n.value != 4:
        return None
    return struct.unpack("<I", buf.raw)[0]


def rd_byte(off):
    buf = ctypes.create_string_buffer(1)
    n = ctypes.c_size_t(0)
    if not k32.ReadProcessMemory(h, ctypes.c_void_p(base + off), buf, 1, ctypes.byref(n)) or n.value != 1:
        return None
    return buf.raw[0]


samples = []
t0 = time.time()
for i in range(9):
    d = rd_dword(RVA_DEPTH)
    samples.append((time.time() - t0, d))
    print("t=%5.2fs  栈深度=%s  当前FBO=0x%X  flag=%s" %
          (samples[-1][0], d, rd_dword(RVA_CUR_FBO) or 0, rd_byte(RVA_CUR_FLAG)))
    time.sleep(1.0)

if len(samples) >= 2 and samples[0][1] and samples[-1][1]:
    dt = samples[-1][0] - samples[0][0]
    dd = samples[-1][1] - samples[0][1]
    print("\n%d 秒里深度增长 %d  ->  %.2f 次 push/秒（≈ 帧率）" % (round(dt), dd, dd / dt))
