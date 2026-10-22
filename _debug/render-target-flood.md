# `[ASSERT] - PushRenderTarget: stack overflow!` 刷屏 —— 定位报告

> 起因：日志一次会话 13 MB，其中 89% 是同一行断言。
> 本文记录：这行哪来的、为什么每帧都刷、是哪些 mod 叠上去的、怎么止血。
> 取证脚本在 `_debug/`，实验原始产物在 `_logs/bisect/`（`_logs/` 不入库）。

---

## 0. 结论（TL;DR）

| 问题 | 答案 |
|---|---|
| 这是谁报的错 | **引擎本身**（`isaac-ng.exe`），不是 Lua 报错 |
| 报错条件 | 引擎内部的 render target（FBO）栈深度 **≥ 16**（反汇编原话：`cmp ecx, 0x10`） |
| 报错后会发生什么 | 引擎**不中止**：照样 push、照样 `深度+1`，所以只是每帧继续刷 |
| 当前实测深度 | 每帧 `0 → 18 → 0`，超上限 2 层 ⇒ **每帧 2 行** |
| 刷屏速率 | 进场后 **≈119 行/秒**（≈ 60 帧 × 2 行），稳态不停，进菜单也不停 |
| 触发条件 | **必须在对局里**；停在大标题画面 150 秒 0 行 |
| 谁把层数叠上去的 | **累加的**：引擎 + 一堆声明了自定义 shader 的 mod 已叠到 16（贴着上限），reverie 再叠 2 层 → 18。**只关 reverie 不刷（r7），只关 heaven's call 同样不刷（r14）** |
| 我们的 mod 有没有责任 | 没有：册子关着时 `book.render` 直接 `return`，不建资源（§6） |
| 能不能修 | 我们这边修不了。对症：少装一个声明 shader 的 mod，或 `tools\strip-log.ps1` 剥噪音 |

---

## 1. 日志量化（用户那次会话）

```
log.txt                                       12.6 MB → 13.6 MB（还在长）
总行数                                        264,551
"[ASSERT] - PushRenderTarget: stack overflow!" 236,503 行 = 89.4%
增长速度                                      ≈ 4,980 字节/秒 ≈ 84 行/秒
```

断言只有这一种，**没有** `PopRenderTarget: stack is empty!`（说明 pop 不比 push 多，不是"pop 多了"）。

---

## 2. 反汇编引擎：上限 16，而且报错后继续 push

用 `_debug/find_xref.py`（PE 解析 + capstone）在 `isaac-ng.exe`（ImageBase `0x400000`）里定位到这条字符串的唯一引用：

```
PushRenderTarget @ 0x0065B570
  0x65B57C  mov  ecx, dword ptr [0xBFEC80]     ; 当前栈深度
  0x65B57E  cmp  ecx, 0x10                     ; 上限 = 16
  0x65B581  jb   0x65B598                      ; < 16 正常继续
  0x65B583  push 0x00B47428                    ; "PushRenderTarget: stack overflow!"
  0x65B588  push 3
  0x65B58A  call 0x0095E330                    ; 写日志（就是日志里那一行）
  ...                                          ; 注意：没有 ret，报完继续往下 push
  0x65B625  inc  dword ptr [0xBFEC80]          ; 深度 +1

PopRenderTarget @ 0x0065B650
  0x65B651  cmp  dword ptr [0xBFEC80], 0
  0x65B65A  push 0x00B47404                    ; "PopRenderTarget: stack is empty!"
  0x65B6D2  sub  dword ptr [0xBFEC80], 1       ; 深度 -1
```

栈是 hashmap，每层存一份"当前 FBO"快照：

| 地址 | 含义 |
|---|---|
| `0xBFEC74` | 容器指针 |
| `0xBFEC78` | mask（涨到过 **16**，说明确实超过 16 层） |
| `0xBFEC7C` | head |
| `0xBFEC80` | **深度**（本文主角） |

全 exe 只有 **37 处** `call PushRenderTarget`、**41 处** `call PopRenderTarget`（`_debug/find_callers.py`）。
**Lua 侧没有任何 API 能碰这个栈**：64 个 mod 全 grep，`PushRenderTarget / SetRenderTarget / Canvas` 只命中我们自己代码里的两条注释。

→ 不可能有 mod "直接"把栈用满，只能是**引擎某条渲染路径每帧多叠几层**。

---

## 3. 运行中只读探测：每帧 0 → 18 → 0

`_debug/probe_rt2.py`：对正在跑的游戏 `OpenProcess(PROCESS_VM_READ)` + `ReadProcessMemory` 读 `[基址+0x7FEC80]`，**不挂调试器、不写内存、不撒断点**。

用户那次会话（pid 92864，上限 16）：

```
2 ms 采样下的深度:  0 → 1,2,3 … 18（0.3 ms 内冲上去）→ 停一会儿 → 一路降到 0
1,300,000 次采样分布:
    0 : 81.4%      ← 帧间空闲
   18 : 17.6%
   17 : 10.7%
   16 :  0.9%
```

即：**每一帧都真的叠到 18 层**，超上限 2 次 ⇒ 每帧 2 行。断言速率 ≈ (深度 − 16) × 帧率：
用户那局 84 行/秒 ÷ 2 ≈ 42 fps，实验里 119 行/秒 ÷ 2 ≈ 60 fps —— 数量级完全对得上。

> 顺带排掉一个猜测：不是"泄漏一次然后一直满"。深度每帧都回 0 —— 是**每帧重新叠一遍**，只是叠得比 16 高。

---

## 4. 对照实验（`_debug/bisect.ps1`，每轮 2~3 分钟）

做法：给要关的 mod 目录加 `disable.it`（引擎认这个文件，实测 `Running Lua Script` 只剩没加的那些），`steam.exe -applaunch 250900` 起游戏，按 4~5 次 Enter 进局，数 `log.txt` 里的断言行；部分轮次同时在外部用 `_debug/probe_long.py` **只读**采样 `[0xBFEC80]`，直接量出该轮峰值层数。

| 轮次 | 改动 | 进局方式 | 断言 | 实测峰值深度 |
|---|---|---|---|---|
| r1 | 全部 19 个 mod，**只停在大标题** | – | **0** | – |
| r3 | 全部 19 个 | 续接 | **119 行/秒** | 18 |
| r4 | 全部 19 个（重复验证） | 续接 | **119 行/秒** | – |
| r10 | 全部 19 个 | 新开一局 | **119 行/秒** | – |
| r5 | 关 8 个（含 reverie） | 新开 | 0 | – |
| r6 | 关 4 个（含 reverie） | 续接 | 0 | – |
| **r7** | **只关 reverie 一个**（其余 18 个全开） | 续接 | **0** | – |
| r8 | 只留 reverie + CuerLib + StageAPI | 续接 | 0 | – |
| r9 | reverie + EID + CuerLib + StageAPI | 续接 | 0 | – |
| r11 | reverie + {arknights, benighted soul, deliverance, goodtrip, heaven's call, retribution, taptapsword} + 依赖 | 续接 | **120 行/秒** | – |
| r12 | 收窄到 reverie + {arknights, heaven's call, retribution, goodtrip} + 依赖 | 续接 | **60 行/秒** | **17**（1 次/帧） |
| r13 | 再收窄到 reverie + heaven's call + 依赖 | 续接 | **0** | **16**（刚好贴上限） |
| **r14** | **全部 19 个，只关 heaven's call** | 续接 | **0** | – |

读法：

1. **r1 vs r3**：同样的 mod，只在标题画面 0 行 → 刷屏需要**对局在渲染**，不是 mod 加载阶段。
2. **深度是"层数"**：r13 峰值 16（没超，不刷）→ r12 加两个 mod 变 17（1 行/帧）→ 全开 18（2 行/帧）。**断言条数 = 深度 − 16**。
3. **r7（只关 reverie）= 0，r14（只关 heaven's call）= 0** ⇒ 不是某个 mod 单独有 bug，而是**自定义 shader 的离屏 pass 一层层叠过 16**；这两个 mod 恰好是最后那一两层。
4. **r8 / r9 / r13**：只有 reverie + 少量依赖 → 峰值 16，贴着上限但不超 ⇒ 没有别人先垫上去，reverie 自己也刷不起来。

启用中的 mod 里声明了自定义 shader 的（`content/shaders.xml`）：

| mod | 声明 shader 数 |
|---|---|
| heaven's call | 6 |
| reverie | 3（另有 1 个被注释掉，不算） |
| stageapi15 | 2 |
| arknights | 2 |
| benighted soul | 1 |
| cuerlib | 1 |

**机制（推断，但有实验支撑）**：Repentance 里 mod 的自定义 shader 是"全屏后处理"，引擎必须先把这一帧画进离屏 FBO 再贴回来 —— 每多一层激活的自定义 shader，render target 栈就多一层。这个 mod 包的 shader 加起来正好把深度顶到 16~18，越界就每帧刷。

**不属于这个机制的部分**：reverie 在文件作用域里打的那一大段 `Pair: [...]`（`scripts/items/th14/d_flip.lua:305`）只是普通的 `Isaac.DebugString`，跟断言无关 —— 它只是**碰巧紧挨着**第一次断言出现（都在进局那几秒），所以早期结论把它当成了元凶。

---

## 5. 影响 & 止血

影响：

- 日志 13~20 MB/次，真正的报错被埋掉（仓库里早有 `tools\strip-log.ps1`，注释写着"96% 是 PushRenderTarget"）。
- 每帧多 2 次日志写盘 + 2 次 FBO 状态保存/恢复 + hashmap 扩容 → 有实际帧率损耗。
- **不会坏存档**：这是纯渲染状态，深度超了引擎也只是照 push。

止血（按代价从低到高）：

1. **读日志前先剥噪音**：`powershell -File tools\strip-log.ps1`
2. **少装/关掉一个声明了自定义 shader 的 mod**（heaven's call 的 6 个最重，reverie 3 个）；总数压到 16 以下就不刷。
3. 要彻底解决，得**报给 reverie / heaven's call 作者**（附本文 §2 的引擎证据）：不该让全屏后处理 shader 每帧常驻。

---

## 6. 为什么不是我们的 mod

- `mod-review/ui/book.lua` 的 `render()` 第一行 `if not isOpen then return end`；册子关着时不建任何资源。
- 字体/纸张在**加载阶段** `book.preload()` 一次性建好 —— 这条规矩就是当初踩同一个坑（在 POST_RENDER 里首次 `Font:Load` 会留下不平衡的 render target）之后定的，见 `mod-review/ui/book.lua:137` 的注释和 `CHANGELOG.md`。
- 实验印证：r11 / r12 / r13 里我们的 mod 是**关掉的**，照样刷。

---

## 7. 复现 & 探测

```powershell
# 一轮对照实验（自动加/删 disable.it、启动、进局、数断言、关游戏）
powershell -NoProfile -ExecutionPolicy Bypass -File _debug\bisect.ps1 `
    -Tag my-round -EnterRun -Disable "reverie_2538556220"

# 游戏跑着的时候，只读探测栈深度
python _debug\probe_rt2.py
python _debug\probe_long.py 120
```

```powershell
# 引擎侧取证
python _debug\find_xref.py       # 断言字符串的引用点
python _debug\find_callers.py    # Push/Pop 的全部调用点
```

结果追加到 `_logs/bisect/bisect-results.jsonl`，每轮日志另存 `_logs/bisect/<tag>-log.txt`。

---

## 8. 踩过的两个坑（写给下一个 agent）

1. **日志要先删**。游戏只在启动时 truncate；脚本若在 truncate 前读，会把上一局的 13 MB 当成这一局 → 误判"2 秒就刷"。`bisect.ps1` 现在先 `Remove-Item log.txt` 再启动。
2. **带 `[ ]` 的 mod 目录名**（`heaven's call [solar update] chinese_...`）会被 `Test-Path` / `Remove-Item` 当通配符 → 必须 `-LiteralPath`，否则会留下删不掉的 `disable.it`，把作者原来的启用状态改掉。
