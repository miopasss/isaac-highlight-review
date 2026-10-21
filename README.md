# Isaac Highlight 系列

两个《以撒的结合》mod，**互相独立**，可以只装一个，也可以都装。

| mod | 干什么 | 需要什么 |
|---|---|---|
| **[Item Weight Editor](mod-rating/README.md)**<br>道具权重编辑器 | 改任意道具的**掉落权重**：让它少出现、或者干脆不出现。也能覆盖道具评级 | REPENTOGON |
| **[Highlight Review](mod-review/README.md)**<br>高光回顾 | 记录每间房的**战力变化**，打完翻成一本可以复盘的小册子 | REPENTOGON |

**两个一起装**：高光回顾会读到你在权重编辑器里设的评级，用它判「四级道具」。
**只装一个**：各自都能正常工作，谁也不会报错。

---

## 快速上手

### 装

把对应目录放进：

```
<游戏目录>\mods\highlight-rating\     ← Item Weight Editor
<游戏目录>\mods\highlight-review\     ← Highlight Review
```

然后在游戏里启用。两个都需要 **REPENTOGON** 作为前置。

### 用

| 操作 | 按什么 |
|---|---|
| 打开**道具权重编辑器** | `F6` |
| 打开**高光回顾册子** | `F5` |

两个热键都能在各自的设置里改：

- 权重编辑器 → ImGui 顶栏 `Item Weight` → `设置`
- 高光回顾 → ImGui 顶栏 `Highlight Review` → `设置`

---

## 为什么拆成两个

一开始是一个 mod，后来分开了，原因很实际：

| | 会改游戏吗 | 受众 |
|---|---|---|
| **Item Weight Editor** | **会**（改道具池抽取） | 想改掉落的人，受众广 |
| **Highlight Review** | **不会**（纯观察，只写自己的存档） | 想复盘的人，受众窄 |

**「高光回顾」卸掉之后不该有任何副作用**，所以它必须保持只读。权重是另一回事——它就是来改游戏的。混在一起会让只想复盘的人平白多背一份风险。

---

## 数据存在哪

| mod | 路径 |
|---|---|
| Item Weight Editor | `<游戏目录>\data\highlight-rating\save{1,2,3}.dat` |
| Highlight Review | `<游戏目录>\data\highlight-review\save{1,2,3}.dat` |

两边都是**纯文本**，可以用记事本直接打开。

## 仓库结构

```
mod-rating/        Item Weight Editor（发布目录）
mod-review/        Highlight Review（发布目录）
shared/            两边共用的源码（构建时复制进各自目录）
tools/             开发工具（不进发布包）
tests/             离线单测（不进发布包）
docs/img/          README 用图
```

`shared/` 里的文件由 `tools\deploy.ps1` 在同步前复制进两个 mod——游戏沙箱里 `include` 只能读自己 mod 目录，不能跨目录引用。

## 创意工坊发布清单

两个 mod **各自**打包，只含自己的目录：

```
highlight-rating.zip  ← mod-rating\ 的内容
highlight-review.zip  ← mod-review\ 的内容
```

**不要带**：`tools/`（含里面的 `.exe`）、`tests/`、`shared/`、`docs/`、`_logs/`、`_archive/`、`_backup/`、`*.md`。

---

## 给开发者

- `AGENTS.md` —— 怎么自动启动游戏验证、Git 工作流、拆分的决策记录
- `DESIGN.md` —— 设计决策与待办
- `FORMAT.md` —— 回顾的数据格式规范
- `CHANGELOG.md` —— 每轮改动记录

```powershell
# 语法校验（必须 32 位 PowerShell）
C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\luacheck.ps1

# 离线单测
C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\luarun.ps1 tests\rating_test.lua

# 同步两个 mod 到游戏
powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy.ps1
```
