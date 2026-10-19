# Highlight Review · 高光回顾

记录《以撒的结合》每一局的战力跳变：**哪一层、哪个房间、拿到了什么、涨了多少**。
打完能翻开一本册子复盘。

> 依赖 **REPENTOGON**。当前目标环境：Repentance **1.7.9b.J835** + REPENTOGON **1.0.8c**。

---

## 文档

| 文件 | 内容 |
|---|---|
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

## 进游戏验

```powershell
pwsh tools\deploy.ps1
```

然后启动游戏（走 `REPENTOGONLauncher.exe`）→ 进一局打几个房间 → 看
`%USERPROFILE%\Documents\My Games\Binding of Isaac Repentance\log.txt` 里的 `[HIGHLIGHT]`。

采集正常的话，每离开一个房间会打一行：

```
[HIGHLIGHT] F1 型01 形1    9.55 ->  12.29  d +2.74 (+28.7%)  生存   6->  6  道具1   4.2s  伤0  [tears]
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
