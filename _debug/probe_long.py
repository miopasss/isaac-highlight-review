"""长时间只读采样 render target 栈深度：等游戏起来后采 N 秒，输出最大值与分布。"""
import ctypes, struct, time, subprocess, sys

PROC = "isaac-ng.exe"
R = 0x400000
k32 = ctypes.WinDLL("kernel32", use_last_error=True)
PROCESS_VM_READ, PROCESS_QUERY_INFORMATION = 0x10, 0x400
RVA_DEPTH = 0xBFEC80 - R
RVA_STR = 0xB47428 - R

secs = int(sys.argv[1]) if len(sys.argv) > 1 else 150


def pid_of():
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq " + PROC, "/FO", "CSV", "/NH"],
                         capture_output=True, text=True).stdout
    try:
        return int(out.split(",")[1].strip('"'))
    except Exception:
        return None


def open_game():
    pid = pid_of()
    if pid is None:
        return None, None
    hp = k32.OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, False, pid)
    if not hp:
        return None, None
    # 找基址：校验字符串
    for cand in (0x400000, 0x2D0000, 0x10000000):
        b = ctypes.create_string_buffer(0x24); n = ctypes.c_size_t()
        if k32.ReadProcessMemory(hp, ctypes.c_void_p(cand + RVA_STR), b, 0x24, ctypes.byref(n)) \
                and b"PushRenderTarget" in b.raw:
            return hp, cand
    return hp, None


print("等待游戏进程 ...")
while True:
    hp, base = open_game()
    if hp and base:
        break
    time.sleep(2)
print("pid ok, base=0x%08X, 采样 %d 秒" % (base, secs))


def depth():
    b = ctypes.create_string_buffer(4); n = ctypes.c_size_t()
    if k32.ReadProcessMemory(hp, ctypes.c_void_p(base + RVA_DEPTH), b, 4, ctypes.byref(n)) and n.value == 4:
        return struct.unpack("<I", b.raw)[0]


hist = {}
mx = 0
t0 = time.time()
n = 0
while time.time() - t0 < secs:
    d = depth()
    n += 1
    if d is None:
        break
    hist[d] = hist.get(d, 0) + 1
    if d > mx:
        mx = d
print("采样 %d 次  最大深度 = %d" % (n, mx))
print("分布(深度:次数, 前 12):")
for k, v in sorted(hist.items(), key=lambda kv: -kv[1])[:12]:
    print("   %2d : %7d  (%.1f%%)" % (k, v, 100.0 * v / max(1, n)))
