# Highlight Review · 高光回顾

记录《以撒的结合》每一局的战力跳变：**哪一层、哪个房间、拿到了什么、涨了多少**。
打完能翻开一本册子复盘。

> 依赖 **REPENTOGON**。当前目标环境：Repentance **1.7.9b.J835** + REPENTOGON **1.0.8c**。

---

## 文档

| 文件 | 内容 |
|---|---|
| [AGENTS.md](AGENTS.md) | **给 Agent 的操作说明书**：怎么自己启动游戏 → 进存档 → 按 F5 → 看截图判断 |
| [DESIGN.md](DESIGN.md) | **设计文档**：已定决策、不变量、未定项、扩展点仓库（§12） |
| [FORMAT.md](FORMAT.md) | **数据格式规范 v1**：这是最贵的东西，改动规则在 §5 |
| [damage-formula-verdict.md](damage-formula-verdict.md) | 伤害/攻速公式核对结论（带来源） |
| [_research/](_research/) | 三轮技术调研的原始结论 |

> ⚠️ **	ools/ 和 	ests/ 是开发工具，不随 mod 发布。**
> 玩家只需要 mod/ 一个目录。发布时把 	ools/、	ests/、_logs/、_archive/、_backup/ 全部排除。

## 目录

```
mod/                   mod 本体（同步到游戏的 mods/highlight-review）
  main.lua             回调接线 + 采集
  config.lua           运行期配置
  core/schema.lua      字段唯一真相（加需求只改这里）
  core/fmt.lua         数据格式编解码（纯 Lua，可离线测）
  core/power.lua       战力公式（纯函数）
  core/highlight.lua   册子内容层（判定+组织，唯一真相）
  core/text_render.lua 册子文本渲染（离线用）
tests/fmt_test.lua     离线单测
tools/deploy.ps1       同步到游戏目录
tools/check.ps1         一键体检（mod 有没有加载 / 采集行 / 报错 / 存档）
tools/strip-log.ps1     生成去噪日志副本（原文件只读，头部记账）
tools/luacheck.ps1     语法校验（借游戏自带 Lua5.4.dll）
tools/luarun.ps1       离线执行 Lua（借同一个 DLL）
tools/verify.ps1       自动进游戏自检：启动 → 进存档 → 按 F5 → 截图 + 查日志
tools/_win.ps1         verify 的底层：找窗口 / 发键盘扫描码 / 截窗口图 / DPI + 窗口归位
tools/fix-bom.ps1      把 tools\*.ps1 重新存成 UTF-8 with BOM
```

## 离线跑测试（不用启动游戏）

游戏的 `Lua5.4.dll` 是 32 位，所以要用 **32 位** PowerShell 宿主：

```powershell
# 语法校验全部 .lua
C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -NoProfile `
  -ExecutionPolicy Bypass -File tools\luacheck.ps1

# 跑单测
C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -NoProfile `
  -ExecutionPolicy Bypass -File tools\luarun.ps1 tests\fmt_test.lua
```

> 两个 .ps1 都是 **UTF-8 with BOM** 保存的（Windows PowerShell 5.1 只认带 BOM 的 UTF-8）。
> 改完记得重新加 BOM，否则中文注释会把脚本解析炸掉。

## 进游戏验（可以全自动）

一条命令跑完「部署 → 启动 → 进存档 → 按 F5 开册子 → 截图 → 查日志」：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\verify.ps1 -Deploy -Launch -Enter -F5
```

跑完看 `_logs\verify\<时间戳>\`：

| 文件 | 内容 |
|---|---|
| `01-menu.png` | 主菜单（确认游戏真的起来了） |
| `02-run.png` | 进存档后的画面 |
| `03-book.png` | 按 F5 之后的册子 |
| `summary.txt` | 结论：mod 是否加载 / Lua 报错 / 引擎断言 / 关键日志 |

退出码：`0` 正常，`1` 有 Lua 报错，`2` 环境问题（没进程/没窗口/超时），
`3` 按键前窗口被别的程序抢走（已中止，不会把按键误发到别处）。

- 游戏已经开着：`-Enter -F5` 就行，会复用当前实例，不再启动。
- `-Fresh`：收拾"进程还在但窗口没了"的僵尸进程（关游戏时卡住的常见形态）。
- `-Close`：跑完优雅关掉游戏（游戏自己会把存档写盘）。
- 启动默认走 Steam（`steam.exe -applaunch 250900`，Steam 会给游戏加上
  `-popupwindow -borderless -nostartupmovies`）；40 秒没进程就报错退出，不会傻等。
  `REPENTOGONLauncher.exe` 会卡在 "Checking for update..."，不用；直接开 `isaac-ng.exe`
  在这台机器上会挂死（steam_api 初始化卡住），所以只在 Steam 完全没开时才用它。
- 按键是 **SendInput 发扫描码**（不是 SendKeys），游戏能收到；发之前会确认窗口在前台。

### 截图为什么曾经缺一条边（已修）

两个原因叠在一起，和册子的排版无关：

1. **PowerShell 默认 DPI-unaware**。主屏是 1920×1080 @125%，所以 `GetClientRect` 拿到的是
   1536×864 这种**逻辑**值，而 `CopyFromScreen` 抓的是**物理**像素 → 只截到窗口左上角 1/1.25，
   右边自然被切。修法：脚本启动时把进程切成 per-monitor-v2 感知（`_win.ps1` 的 `Enable-DpiAwareness`）。
2. **游戏窗口本身出界**。几何存在 `options.ini`（`WindowWidth/Height`、`WindowPosX/Y`，物理像素），
   这台机器上是 `1919×989 @ (201,230)` → 右下角都在屏幕外。修法两层：
   启动前把 ini 里放不下的几何改成 16:9 居中；画完主菜单后再量一次，还在界外就用 `SetWindowPos` 挪回来。

现在截图尺寸 = 窗口客户区的物理像素（例如 1600×900），册子右边缘 / 分页角标都完整。

> 顺带：`tools\fix-bom.ps1` 会把 `tools\*.ps1` 重新存成 UTF-8 with BOM。
> 任何编辑器/工具把 BOM 弄丢之后跑一下，否则 5.1 会按 GBK 解析中文注释直接炸。

手动验还是老办法：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy.ps1
```

然后启动游戏 → 进一局打几个房间 → 看
`%USERPROFILE%\Documents\My Games\Binding of Isaac Repentance\log.txt` 里的 `[HIGHLIGHT]`。

采集正常的话，每离开一个房间会打一行：

```
[HIGHLIGHT] F1-48 型01 形6    12.89 ->   12.89  d  +0.00 (  +0.0%)  红1→1 魂0→0 骨0→0  道具1    0.3s  伤0  [tears 伤害4.72 弹幕1]
```

## 数据存在哪

```
<游戏目录>\data\highlight-review\save1.dat     ← 存档槽 1
                                save2.dat     ← 存档槽 2
                                save3.dat     ← 存档槽 3
```

纯文本，可以直接用记事本打开看（这也是玩家"手动导出"的唯一途径——沙箱里没有 `io`）。

## 当前进度

| 版本 | 状态 |
|---|---|
| v0.1 采集器（无 UI，按最终格式落盘） | ✅ 代码完成，语法/单测通过，**待进游戏验证** |
| v0.2 存档 + 纯文字册 | ⬜ |
| v0.3 封面折线图 + 主菜单入口 | ⬜ |
| v0.4 宝宝折算 + 需求比例 + 双语 → 发工坊 | ⬜ |
