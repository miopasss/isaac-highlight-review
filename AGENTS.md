# AGENTS.md · 自己进游戏验证（给下一个 Agent 的说明书）

> 目标：改完 mod 不用喊人，自己启动游戏 → 进存档 → 按 F5 → **看截图** → 判断功能对不对。
> 本文只讲"怎么用、怎么判、出问题怎么办"。设计/格式/历史见 `DESIGN.md` / `FORMAT.md` / `CHANGELOG.md`。

---

## 0. 一句话流程

```powershell
# ① 改代码 → ② 一条命令 → ③ 自己看 03-book.png
powershell -NoProfile -ExecutionPolicy Bypass -File tools\verify.ps1 -Deploy -Launch -Enter -F5
```

跑完在 `_logs\verify\<时间戳>\` 里拿截图和结论。**必须自己 `read_image` 看截图**，
`exit code 0` 只代表"没报错"，不代表"界面画对了"。

---

## 1. 环境事实（先记住，能省一小时）

| 项 | 值 | 影响 |
|---|---|---|
| Shell | **Windows PowerShell 5.1**（没有 `pwsh` 7） | 脚本用 `powershell -File` 跑；`.ps1` 必须 UTF-8 **with BOM** |
| 显示 | 双屏，主屏 1920×1080 @**125%** | 进程必须 DPI-aware，否则截图缺 1/1.25（已内置） |
| 游戏目录 | `D:\LenovoSoftstore\Install\Steam\steamapps\common\The Binding of Isaac Rebirth` | 别硬编码，用 `tools\_paths.ps1`（`$IsaacDir`） |
| 启动 | `steam.exe -applaunch 250900`（Steam 会附加 `-popupwindow -borderless -nostartupmovies`） | launcher 会卡联网；直接开 exe 会挂死 |
| 加载时长 | **约 60~90 秒**（60+ 个 mod） | 一轮完整验证 ≈ 2 分钟，别为改文案跑全套 |
| 日志 | `%USERPROFILE%\Documents\My Games\Binding of Isaac Repentance\log.txt` | 每次启动会被**截断**，脚本按 offset 读增量 |
| 存档 | `<游戏目录>\data\highlight-review\save1.dat` | 纯文本，可直接看 |
| REPENTOGON | 1.0.12e（`zhlREPENTOGON.dll` 这套） | `REPENTOGON ~= nil` 为真 |
| 前置条件 | **必须有一局可续的存档** | 否则连按 Enter 只能到主菜单，进不了局 |

---

## 2. 命令速查

| 场景 | 命令 |
|---|---|
| 改完代码，全套 | `... verify.ps1 -Deploy -Launch -Enter -F5` |
| 游戏已经开着 | `... verify.ps1 -Enter -F5`（复用当前实例） |
| 有僵死进程（进程在、窗口没了） | `-Fresh` 加上 |
| 跑完关游戏（存档由游戏写盘） | `-Close` 加上 |
| 只想看主菜单 | `-Launch`（不加 `-Enter`） |
| 等得更久（机器卡） | `-WaitMenuSec 300` |
| 输出到指定目录 | `-OutDir _logs\verify\my-test` |

参数全表：`-Deploy -Fresh -Launch -ViaLauncher -Enter -F5 -Close -WaitMenuSec <秒> -WaitRunSec <秒> -OutDir <目录>`。

---

## 3. 脚本内部做了什么（按控制台输出顺序）

| 输出段 | 做的事 | 判定信号 |
|---|---|---|
| `0) 准备` | 建输出目录、记日志起点 | offset 数字 |
| `1) 部署 mod` | 调 `deploy.ps1` 把 `mod/` 同步进游戏 | `已同步 N 个文件` |
| `2) 进程与窗口` | 找 `isaac-ng`；进程在但没窗口 = 僵尸进程；启动前修 `options.ini` 几何 | `✓ 游戏窗口：0x...` |
| `3) 等 mod 加载` | 等日志 `[HIGHLIGHT] loaded`；等窗口标题去掉 `LuaEngine Initialized`；**再量一次窗口**（游戏是先开小窗再改尺寸） | `✓ mod 已加载` + `✓ 窗口完整可见` |
| `4) 进存档` | 连按 Enter，最多 4 次（标题画面 → 存档槽 → 存档内菜单 →「继续游戏」），看到进局日志就停 | `✓ 进局成功（按了 N 次 Enter）` |
| `5) 按 F5` | 按 F5，截图，看有没有 `[UI]` 日志 | `✓ 册子有响应（[UI] 日志）` |
| `6) 结论` | 分类统计：FATAL / Lua 报错 / 警告 / 引擎断言；写 `summary.txt` | 见 §5 |
| `7) 关闭游戏` | （`-Close` 时）优雅关闭并等 `Isaac has shut down successfully` | `✓ 游戏已正常退出` |

**按键是真的模拟键盘**（SendInput 扫描码）。发之前会确认游戏窗口在前台；抢不到前台就
**中止**并返回 `3`，不会把按键误发到别的程序。

---

## 4. 退出码

| 码 | 含义 | 下一步 |
|---|---|---|
| `0` | 跑完了，没有 Lua 报错 | **仍然要去看截图** |
| `1` | 检测到 FATAL 或 Lua 报错 | 看控制台红字 + `summary.txt`，几行内通常是真因 |
| `2` | 环境问题：没进程/没窗口/等不到加载/Steam 没拉起 | 按 §7 剧本处理 |
| `3` | 按键前窗口被别的程序抢走 | 手离开键盘重跑一次；反复出现就查是不是有置顶窗口 |

---

## 5. 产物怎么看

```
_logs\verify\<yyyyMMdd-HHmmss>\
  00-timeout.png    只在失败时出现（等不到加载）
  01-menu.png       主菜单（确认游戏起来了、窗口没缺边）
  02-run.png        进存档后的画面
  03-book.png       ★ 按 F5 之后的册子 —— 判断功能对不对就看这张
  summary.txt       结论 + 最近 60 行 [HIGHLIGHT]/[ASSERT]
```

### 判读 `03-book.png` 的合格特征

- 纸张完整：**左右两条边都看得到**，右上角有 `1/2` 这种分页角标
- 标题「总览」，下面有 `种子 UNFINISHED 1F N ROOMS`
- `POWER 12.89 > 12.89  +0.00 (+0.0%)` 这类战力行
- `Floor 1 12.89 ▮▮▮▮... +0.0%`
- 底部有按键提示（`UP/DOWN RUN  ENTER/RIGHT OPEN  LEFT/RIGHT PAGE  F5 CLOSE`）

不合格的长什么样：一片黑（还在加载）、纸只出现右半边（窗口出界）、
字全是方块/问号（中文字体没加载）、整页没有数据（`getStore()` 为空）。

> 想看第二页（某一局的亮点页）：开册子后按 `ENTER` 或 `→`。脚本不自动按，
> 需要时用下节的"手动补一步"。

### 手动补一步（不写脚本也能按）

```powershell
. tools\_win.ps1
$w = Get-GameWindow
[void](Focus-Window $w)
Send-GameKey ENTER          # 或 RIGHT / DOWN / ESCAPE / F5
Save-WindowShot $w "_logs\verify\manual.png"
```

---

## 6. 日志判读规则

### 我们自己会打的（前缀 `[HIGHLIGHT]`）

| 行 | 含义 |
|---|---|
| `loaded v2 (REPENTOGON=true)` | mod 装载完成 |
| `fmt 自检通过：...` | 编解码自检 |
| `[UI] 打开册子：6 局 cjk=yes` | 册子被打开、中文可用 |
| `[UI] page=1/2 pages=0 floors=1 ... screen=479x247 scale=0.91` | 当前页/总页数/分辨率 |
| `F1-48 型01 形6 12.89 -> 12.89 d +0.00 ... 道具1 0.3s 伤0 [tears ...]` | **每离开一个房间打一行**，采集器的心脏 |
| `检查点落盘（换层）...` / `落盘跳过：内容未变` | 存档写入 |
| `[DUMP] ...` | 一次性数据面板（几百行，**看报告时请忽略**） |
| `[CJK] ...` / `[ICON] ...` | 字体/图标诊断 |
| `ERROR:` / `FATAL` / `!!!` | 真问题 |

### 别人的噪音（不是我们的锅，别追）

| 噪音 | 来源 |
|---|---|
| `[ASSERT] - PushRenderTarget: stack overflow!`（每秒上百行） | **reverie（东方组合）**，`scripts/items/th14/d_flip.lua` 那套，开场刷到关游戏 |
| `[Lua Debug] Pair: [...]` | 同上（reverie） |
| 屏幕下半部分的米色横条 + 红字 | External Item Descriptions 的道具说明浮层 |
| `[ASSERT] - invalid tag: ...` / `unlockachievement` | 其它第三方 mod 的旧写法 |
| `逐件读取失败（GetCollectible）→ 全量扫描` | 我们自己的**降级**路径，属正常 |

`verify.ps1` 已经把断言降级成"提示"，不参与退出码；判断我们有没有事，只看 FATAL / Lua 报错 / `[UI]` 行。

---

## 7. 故障剧本（symptom → 判断 → 动作）

| 现象 | 判断 | 动作 |
|---|---|---|
| `游戏没在跑。加 -Launch` | 正常保护 | 加 `-Launch` |
| `进程在但没有任何可见窗口` | 僵尸进程（关游戏卡住） | 加 `-Fresh` |
| `Steam 40 秒内没把游戏拉起来` | Steam 脏了（刚强杀过游戏进程） | 等 1 分钟重跑；还不行就重启 Steam |
| 窗口一直"启动中"、等不到 `loaded` | mod 没同步 / 日志路径不对 | 先 `-Deploy`；再看 `mods\highlight-review\metadata.xml` 的 `<directory>` |
| `按键前窗口没拿到前台`（exit 3） | 有窗口抢焦点（任务栏浮层/Snipaste 之类） | 手别碰鼠标键盘，重跑；脚本会自己发 ESC 赶走任务栏浮层 |
| 截图缺一条边 / 里面混进任务栏 | 窗口出界或 DPI 没生效 | 看 `窗口客户区 ...` 那行；脚本应自动归位，失败会提示"挪不动" |
| `没看到进局日志` | 没有可续的局，或停在别的菜单 | 人先进一局退出，再重跑 |
| `没看到 [UI] 日志` | 册子没开 / 没有可显示的对局 | 看截图；确认 F5 没被别的 mod 抢 |
| 改完 `.ps1` 后一堆 `Unexpected token` | BOM 丢了（GBK 解析中文） | `powershell -File tools\fix-bom.ps1` |
| `deploy.ps1` 后游戏里还是旧代码 | mod 不会热重载 | **退出游戏重开**再跑验证（本轮里 F5 是册子开关，不会重载 Lua） |

---

## 8. 硬规则

1. **`.ps1` 必须是 UTF-8 with BOM**。任何工具（含 `edit`）写回后都可能丢 BOM，
   改完跑一次 `tools\fix-bom.ps1`。
2. **不要硬编码游戏路径**，一律 dot-source `tools\_paths.ps1` 拿 `$IsaacDir`。
3. **一次只改一件事**，改完立刻 `-Deploy` 验证；别攒三个改动一起跑。
4. **截图必须自己看**（`read_image`）。只看日志会漏掉"字画歪了/被切成方块"这类。
5. **`[DUMP]` 行不要往聊天里贴**（几百行）。要贴就只贴 `[HIGHLIGHT] F...` / `[UI]` 那几行。
6. 每轮改完：更新 `CHANGELOG.md`（**只在末尾追加**）→ `git commit`。
7. **别为了改一句文案跑全套**（2 分钟）；纯 Lua 逻辑用离线单测：
   ```powershell
   C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\luarun.ps1 tests\fmt_test.lua
   C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\luacheck.ps1
   ```
8. 工具箱里的 `_logs/ _archive/ _backup/ tools/*.exe REPENTOGONUpdater_Base.exe savedatapath.txt` **不进仓库**。

---

## 9. 扩展（加按键 / 加一步）

- 新按键：往 `_win.ps1` 的 `$script:KeyMap` 里加 `"X" = @(虚拟键码, 扫描码, 是否扩展键)`
  （字母 `A`=0x1E、`B`=0x30 …；方向键/Insert 区要 `$true`）。
- 新步骤：照 `verify.ps1` 里 `5) 按 F5` 那段抄——`Press "<键>"` → `Start-Sleep` → `Shot "<名字>"` →
  `Read-NewLog` 里筛关键字判定。
- 想让某张截图带上"这一步之前/之后"的日志：在 `Press` 前记 `$script:AllNew.Count`，
  之后用 `AllNew[before..end]` 切片（第 5 步就是这么写的）。

---

## 10. 一次真实成功的输出（照这个对）

```
== 2) 进程与窗口 ==
  ✓ 游戏窗口：0x1205CE  The Binding of Isaac: Repentance (+ REPENTOGON 1.0.12e) - LuaEngine Initialized ...
  窗口客户区 960x540 @ (41,70)   DPI=per-monitor-v2

== 3) 等 mod 加载 + 主菜单就绪 ==
  ✓ mod 已加载
  ✓ 窗口完整可见：1600x900 @ (137,121)
  [截图] ...\01-menu.png  (1600x900)

== 4) 进存档 ==
  [窗口] 已在前台
  [按键] ENTER  ×4
  ✓ 进局成功（按了 4 次 Enter）
  [截图] ...\02-run.png  (1600x900)

== 5) 按 F5（册子开关） ==
  [按键] F5
  [截图] ...\03-book.png  (1600x900)
  ✓ 册子有响应（[UI] 日志）

== 6) 结论 ==
  ! 引擎断言洪水 x539：PushRenderTarget: stack overflow!（可能来自第三方 mod）
  summary: ...\summary.txt

== 7) 关闭游戏 ==
  ✓ 游戏已正常退出（存档已写盘）
```

对应判读：截图 1600×900 说明窗口完整；`[UI]` 有响应说明 F5 生效；断言洪水是 reverie 的，
不管；结论里没有 FATAL/报错 → 这一轮算通过。

---

## 11. 已知限制

- **不能替我打游戏**：我不会走位/射击/捡道具，只能验证"打开界面、进出房间、日志采集"这类。
  要验证"捡到道具后战力跳变"，得人先玩到那一步，或者用游戏内控制台（`EnableDebugConsole=1` 已开）刷道具。
- **必须有可续的局**才能"进存档"。
- **一轮 ~2 分钟**，其中 90 秒是 60+ 个 mod 的加载。
- 本 mod **不会热重载**：改完代码（哪怕只改一行 Lua）都要退出游戏重开再验证；
  这个环境里 F5 是册子开关，不是"重载 mod"键。
- 册子底部按键提示文字超宽会切掉尾巴（`footer()` 固定坐标，未按字宽折行），已知未修。

---

## 12. Git 工作流（作者定的版本管理纪律）

**核心诉求**：main 上每个功能只占**一个节点**，细节留在功能分支里。

### 流程

1. 改代码（本地随意 commit）
2. 开分支：`feature/<功能>-v<版本>`，例：`feature/ui-v0.3`
3. 推分支：`git push -u origin feature/<功能>-v<版本>`
4. **等作者发话**（「合并吧」/「提 PR」）
5. 一条命令走完：
   ```powershell
   .\tools\pr.ps1 -Branch feature/<功能>-v<版本> -Title "增加XX（feature/<功能>-v<版本>）" -Merge -DeleteBranch
   ```
6. main 多一个节点，远端分支自动删除

### 硬规则

| # | 规则 |
|---|---|
| 1 | **不要自己合并**。没听到作者明确说「合并」，就停在推分支那步 |
| 2 | **禁止对 main 做 force push**。main 只能通过 PR 前进（唯一例外：作者明确要求重写历史） |
| 3 | 合并只用 **squash**，不用 merge commit、不用 rebase |
| 4 | 合并提交标题必须**带分支名** |
| 5 | 每轮改完：CHANGELOG 末尾追加 → commit → push（**攒一批再推是预期内的**，作者认可） |
| 6 | **不设审批**。作者自己不能 approve 自己的 PR；分支保护也没开，按作者要求不配 |

### token

位置：`tools\.gh_token`（明文一行，作者允许）。

**必须 gitignore** —— 不是怕泄露，而是：

- GitHub **push protection** 会直接拒绝含 token 的推送（实测报 `push declined due to repository rule violations`）
- **secret scanning** 检测到会自动撤销 token，脚本就失效了

### 合并方式对照

| 方式 | main 上看到 |
|---|---|
| **Squash（本项目用这个）** | 1 个节点 |
| Merge commit | 合并节点 + 全部提交 |
| Rebase | N 个提交 |

### tag

每个版本一个 tag，与合并提交对齐：

```powershell
git tag v0.2.0
git push origin v0.2.0
```

现有参考：`v0.2.0`（UI 合并提交）、`pre-squash-20261020`（重写 main 前的备份）

### 提交身份（已知问题，暂不处理）

本地 `user.email` 是 Gitee 的 `...@user.noreply.gitee.com`，
所以 GitHub 上部分提交显示作者为 `piiiika`，贡献者统计里不计入 `miopasss`。
作者决定「就这样吧」，不改。