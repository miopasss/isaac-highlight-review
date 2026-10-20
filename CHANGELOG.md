# 更新日志 · Highlight Review

> **规则：只在文件末尾追加，不改上面的内容。**
> 每一次追加用 `---` 分隔，写清：这一轮做了什么 / 出了什么问题 / 怎么解决的 / 下次怎么配合更省。
> 目的：换聊天窗口时，新会话读这一个文件就能接上。

---

# 第 0 轮 · 设计阶段（只讨论，不写代码）

**做了什么**
- 用 `grilling` 技能做了 4 轮拷问，把"以撒战力编年史"这个想法拆成设计树。
- 派了 3 个研究子代理，产出 3 份带来源的技术报告：
  - 能力边界（REPENTOGON 1.0.8c 能做什么、不能做什么）
  - 先例（社区有没有同类 mod）
  - 房间/道具数据能拿到什么
- 产出两份契约文档：
  - `DESIGN.md` —— 已定决策、不变量、未定项、**扩展点仓库（24 条）**、踩坑记录
  - `FORMAT.md` —— 数据格式 v1（这是最贵的东西，改动规则写在 §5）

**关键事实（设计建立在上面）**
- 伤害是 **√ 曲线**：`(角色基础 × √(伤害提升数 × 1.2 + 1) + 平坦提升) × 乘区`。
  以撒 3.5 拿 +1 → **5.19**（作者一开始说的数是对的，AI 一开始算成 4.5 是错的）。
- 攻速是**加速收益**、硬顶 5.0 次/秒，可压缩空间只有 1.83 倍 → 输出战力 90% 看伤害。
- 只能直读 `player.Damage`（已是曲线后的值），Lua 里**没有** `PlayerFormulas`。
- 截图/像素读回**不存在**；`io` 被沙箱移除 → **只能通过 `mod:SaveData()` 落盘**。
- 存档是**按存档槽分文件**：`data/<文件夹>/save1|2|3.dat`。

**给下一次的提示**
- 想清楚"我要的是记录还是改造"再开工。这个 mod 只记录，不改游戏。
- 概念一旦确定就写进 `DESIGN.md`，否则几轮之后没人记得当初为什么这么定。

---

# 第 1 轮 · v0.1 采集器落地（2026-10-20 凌晨）

**做了什么**
- 写 `mod/`：`main.lua` + `core/fmt.lua`（格式编解码，纯 Lua）+ `core/power.lua`（战力公式）+ `config.lua`
- 写工具链：
  - `tools/luacheck.ps1` / `tools/luarun.ps1` —— **借游戏自带的 `Lua5.4.dll` 做语法检查和单测**（这台机器没有 Lua 解释器，`luac.exe` 缺 VC 运行库跑不起来）
  - `tests/fmt_test.lua` —— 30 项单测，全过
  - `tools/deploy.ps1` —— 同步到游戏 mods 目录
- 数据格式实测：单房间 40 字节，一局 40 房 ≈ 1.6 KB，500 局 ≈ 800 KB

**出了什么问题**

1. **一开局就闪退（minidump）**
   - 现象：`Caught exception, writing minidump`，栈指向 `main.lua:169 GetRoomShape`
   - 原因：在 `MC_POST_PLAYER_INIT` 里读房间，此时房间还没初始化；`room:GetRoomShape()` 抛的是 **C++ 异常，`pcall` 接不住**
   - 修法：① 开局回调里**只**开账，不碰房间 ② 房间信息全部改读数据字段（`Data.Type` / `Data.Shape` / `AllowedDoors`），**一次引擎调用都不打**

2. **日志里一个字都没有**
   - 现象：mod 明明加载了，`log.txt` 搜不到任何输出
   - 原因：这个版本里 Lua 的 **`print()` 只往游戏内控制台走，不写 `log.txt`**
   - 修法：统一走 `Isaac.DebugString()`（日志里显示成 `[INFO] - Lua Debug: ...`），包一层 `emit()`

**学到的事实**
- `pcall` 不是防崩保险丝。要防的是"别在错误时机调引擎方法"。
- 观察手段：`log.txt`、每次启动的 `isaacv*.txt` 快照、`repentogon.log`、`data/<mod>/save*.dat`、游戏内控制台（`EnableDebugConsole=1` 已开）。
- 这环境的 PowerShell 5.1 **只认带 BOM 的 UTF-8**，`.ps1` 没 BOM 会被按 GBK 读、中文注释直接炸。

**给下一次的提示**
- 让我读日志前，先跑 `tools/check.ps1`（定向提取，几十行），不要整份读。日志能被某个渲染 mod 刷到 40 MB。

---

# 第 2 轮 · 改名 + 第二次崩溃（2026-10-20 02:2x）

**做了什么**
- 名字改了三次：`Run Chronicle` → `Isaac Codex` → **`Highlight Review`**（目录 `highlight-review`，日志前缀 `[HIGHLIGHT]`）
- 改名的代价：`data/<文件夹>` 是按文件夹名建的，**有数据之后再改就等于换了一个存档目录**。趁没数据改是对的。

**出了什么问题**

3. **`main.lua:437 attempt to call a nil value (method 'ToPlayer')`，刷了 2498 次**
   - 原因：`MC_ENTITY_TAKE_DMG` 的实参和文档对不上。探针实测是 `1=table 2=userdata 3=number ...`——**第一个参数是 mod 表，不是 Entity**
   - 修法：不再猜顺序，改成扫描全部实参（userdata 里找能转成玩家的，第一个 number 当金额）

4. **报错刷屏但没重启，误以为修好了**
   - 现象：改了代码、部署了，日志里还是旧错误
   - 原因：**换存档槽 / 回主菜单都不会重载 Lua**，只有进程重启才会
   - 修法：验证前先确认 `isaac-ng.exe` 的启动时间早于部署时间

**给下一次的提示**
- 部署后先看进程启动时间，再看日志。否则会在旧代码上排查半天。

---

# 第 3 轮 · 第一次真正跑通（2026-10-20 02:4x）

**做了什么**
- 管线全通：加载 → 自检 → 采集 → **落盘**（`save3.dat` 1147 字节 / 2 局 / 魔数 `MRV1`）
- `Save & Quit` 续接合并生效（`续接未完成的局 1CCD0D98-0`）
- **数据面板导出成功：1752 条道具**（你这套 60+ mod 环境下的全量）
- 道具池探针全绿：`GetCollectible` / `AddItem` / `RemoveItem` / `GetNumCollectibles` / `GetCollectibleFromPool` / `GetPoolForCollectible` / `GetRemovedCollectibles` **全部存在** → 扩展点 E27（调道具池权重）技术上可行

**从存档里挖出的 4 个数据 bug（全部已修）**

| 现象 | 根因 | 修法 |
|---|---|---|
| `basePower=0.00` | 开局那刻 `player.Damage` 还没算出来 | 基线改到**第一间房**补记 |
| 房间时长 `19518000 ms`（5.4 小时） | `Isaac.GetTime()` 语义不可靠 | 改用 `Isaac.GetFrameCount() × 1000/30` |
| 层数记到 F3（实际二层） | `MC_POST_NEW_LEVEL` 续接时重复触发 | 改成按 **stage key 变化**判层 |
| `peds` 塞了几十个坐标 | `Data.Spawns` 是**所有刷怪点**，不是道具座 | 默认关闭 `capturePeds`，等做类型过滤 |

顺带修了 `check.ps1` 自己的匹配 bug（`[HIGHLIGHT][DUMP]` 少了空格，实际是 `[HIGHLIGHT] [DUMP]`，导致误报"没导出"）。

**学到的事实**
- `GetHearts()` 返回**半心**（`r=4 s=2` → 生存 6 = 3 颗心），换算对。
- 同一个"初始状态"在不同角色下战力不同（8.43 / 6.85 / 12.89）→ **不能硬编码 3.5**，基线必须每局自己记。
- `desc.ListIndex` 是跨维度唯一的房间键，比 `GridIndex` 可靠。
- 道具的 `Name` 在 `ItemConfig` 里给的是**本地化 key**（`#THE_D6_NAME`），不是"骰子"，要显示名字得再查本地化表。

---

# 第 4 轮 · 工具化 + 二次验证（2026-10-20 03:0x）

**做了什么**
- 新增 `tools/parse-save.ps1`：把紧凑格式解析成**人能看懂的 JSON**（字段展开 + 派生 `delta` / `deltaPct` / `seconds`）
- 新增 `tools/ParseSave.exe`：C# 写的双击启动器，包着上面那个脚本（`csc.exe` 本地编译，5 KB）
- 新增 `tools/strip-log.ps1`：生成**去噪日志副本**（原文件只读、头部记账、连续重复折叠成一行+次数）。实测 102 万行 → 1.2 万行，3.2 秒
- 清空旧存档（移入 `_backup/data-<时间>/`，没硬删）

**验证结果**
- ✅ 受伤计数生效（`伤2` / `伤3`，探针确认金额在第 3 个参数）
- ✅ 战力跳变抓到了（`12.89 → 23.76`、`+25.77`）
- ✅ 基线补记正常（`6.85 / 12.89`）
- ⚠️ **道具 id 仍然记录不到**：`GetCollectibleCount` 说"持有 4 件"，但逐件读取没拿到 → 已加精确探针（会打出 `GetCollectible(i)` 的失败原因）
- ⚠️ **runId 可能重复**：`1CCD0D98-0` 在不同会话里出现过两次，怀疑 `GetStartSeed()` 语义不对 → 已加原始 seed 打印，并把"续接合并"限制成**只认最新那一局**

**给下一次的提示**
- 每次改完代码，先跑 `luacheck` + `fmt_test.lua`，再 `deploy`，再让作者重启游戏。
- 验证一轮的成本大约是"重启 + 打一局"，所以**一次只改一类问题**，别把五个改动混在一起验证。
- 要看数据别读 `saveN.dat` 原文，跑 `ParseSave.exe` 出 JSON。

---

# 待办（下一轮优先）

1. 道具 id 记录 —— 探针会告诉我们 `GetCollectible(i)` 到底错在哪
2. runId 唯一性 —— 看原始 seed 是否每次都变
3. `capturePeds` 的真实实现（按 `EntityType==5 && Subtype==100` 过滤出道具座）
4. 高光阈值：等干净数据积累几局后，用 Δ 分布定 `relPct` / `absDelta`
5. v0.2：存档 + 纯文字册（暂停菜单入口）

---

# 第 5 轮 · 道具读取失败 & 数据污染（2026-10-20 03:1x）

**做了什么**
- 分析第 4 轮之后的第二次验证数据，发现记录仍然不合格 → **数据全部归档并清空**

**出了什么问题**

5. **我自己的探针崩了，还把真正的错误掩盖了**
   - 现象：`main.lua:122 attempt to call a nil value (global 'safeToString')`
   - 原因：`safeToString` 定义在文件后面，`readCollectibles` 在它之前就调用了 → 前向引用 nil
   - 后果：探针本来要打印 `GetCollectible(i)` 的失败原因，结果自己先炸，**真正的错误信息一个字都没拿到**
   - 修法：把 `safeToString` 提到文件前部；探针改成只在真的读到东西时才说"正常"（上次在 0 件时误报了"逐件读取正常"）

6. **道具读取确实失败**
   - 证据：3 处战力跳变但 `items` 全空
     - `#2` 最后一房 `12.89 → 23.76`（+84%）
     - `#3` 祭坛房 `12.89 → 25.77`
     - `#5` Boss 房 `12.89 → 15.61`
   - 修法：加**兜底路径**——一旦发现 `GetCollectible(i)` 不行，整个会话改用 `HasCollectible(id)` 扫 1~800。这个 API 在形态判定里已验证可用，慢但一定准

7. **空壳局被落盘**
   - 现象：`#4 505B054F-0` 有 0 个房间、`finalPower=0`
   - 原因：开局后立刻退出/崩溃，`PRE_GAME_EXIT` 把空局存了
   - 修法：`saveData` 里丢弃"0 房间且未完成"的局

8. **换存档槽不重载历史 → 两个槽出现同一个 runId**
   - 现象：`save1.dat` 和 `save3.dat` 都有 `1CCD0D98-0`，同样 2 个房间
   - 原因：内存里的历史属于上一个槽，切槽后没有清空，直接写进了新槽
   - 修法：接 `MC_POST_SAVESLOT_LOAD`（REPENTOGON，值 1470），切槽时清空内存 + 重新标记待载入

9. **落盘打了两次**
   - 现象：`落盘 OK：5 局 / 1736 字节` 连续两行
   - 原因：`MC_POST_GAME_END` 和 `MC_PRE_GAME_EXIT` 都会存
   - 修法：加 `lastBlob` 比对，内容没变就跳过并打"落盘跳过"

**学到的事实**
- `GetCollectibleCount()` 能用、但逐件读取不一定能用 —— **"数量"和"内容"是两个不同 API，必须分别验证**。
- seed 是变化的（`1348142415` / `1970014577`），所以 runId 重复的锅不在 seed，在"换槽没重载"。
- **探针代码本身也会出 bug**，而且它一崩就把调查方向带偏。探针要写在最安全的位置、只用最简单的原语。

**给下一次的提示**
- 一轮只修一类问题。这轮同时有"探针崩溃"和"数据污染"，混在一起导致第一次分析得出了错误结论。
- 数据分析的结论要能落到具体房间行（哪一局哪一间），否则不要下结论。

**数据处置**
- `save1.dat`（1736 字节 / 5 局 / 37 房）、`save3.dat` 已归档到 `_backup\data-<时间>\`，游戏目录已清空。
- 原因：items 字段不可信，这批数据的"高光"缺了最关键的一维（拿了什么）。
---

# 第 6 轮 · 道具记录通了，但数据仍不干净（2026-10-20 03:2x）

**突破**
- `GetCollectible` 在这个版本**根本不存在**（`attempt to call a nil value (method 'GetCollectible')`）→ 兜底 `HasCollectible(id)` 扫描生效
- 首次真正记录到道具：`道具:34`、`道具:385`

**新发现的问题（已修）**

10. **`MC_POST_SAVESLOT_LOAD` 一局内触发 7 次以上**
    - 后果：每次清空内存 → 正在进行的局被清掉 → 多出 `0.3 秒 / 1 房间` 的垃圾局（本轮 `#1` `#2` 就是）
    - 修法：**不再监听这个回调**，改成"每次进局（`MC_POST_PLAYER_INIT`）强制从磁盘重读"

11. **第一间房会误记"获得道具"**
    - 现象：`#4` 的第一间房记了 `道具:34`，但那是角色自带/初始化残留
    - 原因：进局瞬间玩家还没初始化完，`itemsIn` 是空的，结算时扫出来了
    - 修法：**一局的第一间房一律不记获得道具**

**数据处置**
- 这批仍不合格（含 2 个垃圾局 + 1 条误记道具 + 1 个 0.0 秒房间）→ 归档到 `_backup\data-<时间>\`，游戏目录清空

**待办更新**
- 新增 **E28**：战力上涨的非道具来源（硬币等）+属性 —— 作者明确"暂时认为正常、不记录、不追查"，写进 `DESIGN.md §15`
---

# 第 7 轮 · 换成 v2 记录流格式（2026-10-20 03:5x）

**这一轮是架构级改动，动因来自两个判断**
1. 位置式字段每加一个需求要改四处（编码器/解码器/解析脚本/文档），撑不住频繁变更
2. "整份解码 + 整份重编码"在 500 局时会变成进局卡顿和写盘开销

**改了什么**

| 项 | v1 | v2 |
|---|---|---|
| 结构 | 一局一行，房间塞第 11 个字段 | **一条记录一行**：`R`(局) / `F`(层) / `M`(房间) |
| 字段 | 位置式，靠顺序 | **`key=value`**，靠 schema 定类型 |
| 加需求 | 改四处 | 改 `schema.lua` **一处** |
| 层维度 | 没有 | **有**（`F` 记录，诅咒/楼层类型有地方放） |
| 历史 | 全部解码成表 | **只存原始字符串，永不解码** |
| 保存 | 全量重新编码 | **只编码当前局**，历史原样拼回 |
| 保险 | 无 | `maxBlobBytes = 1.2 MB`，超了按局淘汰最旧 |

**新增/重写**
- `mod/core/schema.lua` —— 字段唯一真相，含类型与默认值
- `mod/core/fmt.lua` —— schema 驱动编解码、切行建索引、按需解单局、预算裁剪
- `mod/main.lua` —— 全面改写成 v2 模型
- `FORMAT.md` —— 重写为 v2 规格
- `tools/parse-save.ps1` —— **不再需要知道字段表**（键值自描述）

**实测数字**
- 单个房间记录 **124 字节**（22 个字段全写）
- 一局 40 房 ≈ **5 KB**
- 500 局 ≈ **2.45 MB** ← 超过 1.2 MB 预算，实际会淘汰到约 240 局
- 单测：22 项全过（往返、未知键保留、缺键补默认、按需解码、裁剪后行号仍正确、schema 加键自动生效）

**留下的隐患**
- 体积比 v1 大 3 倍（键名开销）。若需要跑满 500 局，下一步做**稀疏编码**（值等于上一间就省略），预计省 30~40%
- `parse-save.ps1` 已经用合成样本验证过，但**还没在真实游戏数据上跑过**

**给下一次的提示**
- 加字段只需改 `schema.lua` + 采集处赋值，**不要**再动 `fmt.lua`
- 看到 `extra` 字段说明有未知键（旧版写、新版读），属正常

**数据处置**
- v1 存档（`save1.dat`）已归档到 `_backup\v1-last\`，游戏目录清空
---

# 第 8 轮 · 离线册子 + 「同一份实现」架构（2026-10-20 04:3x）

**作者提的关键约束**
> "有办法保证离线的册子和在代码里面得到的册子调用的是同一个函数吗？只有这样的话才能保证我们做的东西是正确的。"

**解决方案：内容层与渲染层分离**

```
core/highlight.lua      ← 唯一真相：判定 + 组织册子结构（纯 Lua，无游戏 API）
        │
        ├── core/text_render.lua   → 纯文本（离线册子用）
        └──（以后）ui/*.lua         → 图形（游戏内册子用）
```

离线册子不是"另写一套"，而是**用同一个 Lua 运行时（游戏自带的 Lua5.4.dll）跑同一份 highlight.lua**，只换渲染器。
所以离线验证过的排序、阈值、取舍，游戏内不会走样。

**新增文件**
| 文件 | 作用 |
|---|---|
| `mod/core/highlight.lua` | 判定高光、层汇总、战力曲线——纯数据，无渲染 |
| `mod/core/text_render.lua` | 把册子结构渲染成文本（离线） |
| `tests/book_offline.lua` | 读真实存档 → 出册子（写 `_logs/book-*.txt`） |
| `tests/book_demo.lua` | 造一份带跳变的数据 → 出样例（验证排版） |
| `tools/book.ps1` | 一键入口：`pwsh tools\book.ps1` / `-Demo` |

**同时完成的**
- **层诅咒**：采集 `Level:GetCurses()` 位掩码，`F` 记录的 `curse` 从字符串改成整数
  （1黑暗 2迷宫 4迷失 8未知 16诅咒 32迷阵 64失明 128巨大）
- **取消 `pmn`/`pmx`**：作者判断房间内采样解决不了问题，且"进/出房读数"对"进房才启动的临时增益"反而更精确

**踩到的坑**
- 文本渲染时把函数当字符串打印了（`duration` 传的是函数没调用）→ 已修
- 中文经 PowerShell 管道会乱码 → 改成**Lua 直接写 UTF-8 文件**，再读文件（顺便让作者能直接打开）
- 种子的 uint32 溢出 Int32 → 解析脚本里 `[int]` 全改 `[long]`

**当前样例输出（造的数据，3 层 3 次跳变）**
```
【本局最强跳变】
  #1  F3-02 宝箱    29.40 →   48.20   +18.80 (+63.9%)
  #2  F2-02 恶魔    18.90 →   29.40   +10.50 (+55.6%)
  #3  F1-02 宝箱    11.45 →   18.90   +7.45 (+65.1%)

【层 2】
  诅咒：黑暗、诅咒
  3 间房  ·  1分48秒  ·  受伤 4  ·  战力 18.90 → 29.40  (+10.50)
  道具：331
  ★ 02 恶魔   18.90 →   29.40  +10.50 (+55.6%)  8秒  道具 331
```

**下一步**
- 作者正常游玩积累数据（不需要刻意测试）
- 等有 10~20 局真实数据后，用离线册子调阈值 `relPct` / `absDelta`
- 排版稳定后再做游戏内 UI（那时是"翻译成渲染调用"，不是重新设计）
---

# 第 9 轮 · 只留 10 局 + 永久离线档案（2026-10-20 04:3x）

**作者要求**
> "不需要五百局了。只记录最近 10 局，更多的局数我希望能在游戏外离线读取。"

**做法：游戏内环形缓冲 10 局 + 外部永久档案（只增不减）**

| 层 | 位置 | 容量 | 谁维护 |
|---|---|---|---|
| 游戏内 | `data/highlight-review/saveN.dat` | **最近 10 局** | mod 自己裁剪 |
| 离线档案 | `_archive/all.dat` | **无限** | `tools/archive.ps1`，**每次出册子时自动跑** |

- 档案按"R 行"做去重键（seq+id+seed+base 天然唯一），**只增不减**
- 合并后按 seq 排序，格式仍是 MRV2，册子/解析器直接能读
- `book.ps1` 现在会先归档再出册子 → **只要你看册子就不会丢数据**

**顺带修的**
- `config.maxRuns` 以前根本没被强制执行（只按字节预算裁），现在 `saveData` 里加 `fmt.trimToCount`
- `archive.ps1` 写文件时用 CRLF 导致魔数行变成 `MRV2\r` → 改成 LF；`fmt.splitBlob` 也顺手容忍行尾 `\r`
- `book_offline.lua` 有档案时**只读档案**（否则会和游戏存档重复计数）

**⚠️ 已知风险（需要作者注意）**
如果一次性连玩 **超过 10 局** 且中间不跑 `book.ps1`，第 1 局会先被游戏淘汰，档案里没来得及拿到 → 永久丢失。
- 缓解 A：每次退出游戏后跑一次 `pwsh tools\book.ps1`
- 缓解 B：把 `maxRuns` 提到 30（多占 ~140 KB，给 3 倍安全边际）

**工具清单更新**
| 命令 | 作用 |
|---|---|
| `pwsh tools\archive.ps1` | 把游戏存档合并进 `_archive/all.dat`（去重） |
| `pwsh tools\book.ps1` | **先归档，再出册子** |
| `pwsh tools\book.ps1 -Demo` | 用造的数据看排版 |
---

# 第 10 轮 · 只在启动前备份 + Steam 启动也能触发（2026-10-20 04:4x）

**作者要求**
> "只在看游戏前做吧，关游戏后就不保存了。另外我希望在 Steam 启动的时候做一次自动保存，能不能做到？
> 我印象中是有一个 mod 实现过，就是在启动之前去检测那个 mod 的更新。"

**① 关掉了"退出后归档"**
`play.ps1` 现在只做一次：**启动前归档 → 启动游戏 → 结束**。

**② Steam 启动的自动备份：靠系统层蹲守，不靠 mod**
- 作者印象里"启动前检测更新"的那个是 **REPENTOGON 的启动器**，不是 mod——它是替换启动入口的外部程序。
- 游戏内的 mod **没法调外部进程**（`io`/`os` 被沙箱移除），所以从 Steam 直接启动时，mod 侧没有任何办法。
- 解决：`tools/watch.ps1` 每 2 秒看一眼 `isaac-ng.exe`，**首次出现时归档一次**；退出不归档；下次启动再归档。

**已安装**
- 开机自启快捷方式：
  `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\HighlightReview-Watch.lnk`
- 取消：`pwsh tools\watch.ps1 -Uninstall`
- 当前已有一个脱离会话的常驻实例在跑

**③ 顺手修了归档去重的一个真 bug**
原来用整条 R 行做去重键，但这行含 `res`/`final`——同一局从"未完成"变"通关"时 R 行会变，会被当成两局，档案里出现幽灵重复。
现在用稳定身份 `seq|id|t0` 当键，冲突时**保留内容更全的那份**（行数更多 = 房间更多）。

**触发点汇总（现在有三个，但只有前两个会真的写档案）**
| 时机 | 是否归档 |
|---|---|
| 双击 `play.cmd` 启动前 | ✅ |
| 从 Steam 启动（蹲守检测到进程） | ✅ |
| 跑 `book.ps1` 看册子 | ✅ |
| 游戏退出后 | ❌（按要求关闭） |
---

# 第 11 轮 · 4 级/0 级道具（起飞 / 封盘）（2026-10-20 05:0x）

**作者需求**
> "之前提到过记录四级道具。现在想加上 0 级道具也记录。这两种能直接导致起飞或者封盘。现在有在记录吗？"

**答案：之前没记录等级**——只记了道具 id（`it`），所以系统不知道哪个是 Q4、哪个是 Q0。

**改法**
- schema 里 `M` 作用域加 **`iq`**：与 `it` **平行的品质列表**（0~4，-1 = 查不到）
- 采集时用 `Isaac.GetItemConfig():GetCollectible(id).Quality` 查，带缓存（同一 id 只查一次）
- 成本：每个道具约 +2 字节
- 判定：房间里拿到 **Q≥4 → 「起飞」**，拿到 **Q=0 → 「封盘」**
- 这两类**不看阈值**，全部强制收录进册子（`book.mustSee`）

**样例输出**
```
【起飞 / 封盘】
  起飞 F1-02 宝箱    11.45 →   18.90   道具 118 (Q4)
  封盘 F3-02 宝箱    29.40 →   48.20   道具 1286 (Q0)
```

**已知局限**
- 册子里显示的是**道具 id**，不是名字 —— 因为 `ItemConfig.Name` 给的是本地化 key（`#THE_D6_NAME`），要显示中文得再查一次本地化表（扩展点 E23）
- Q0 ≠ 负收益，只是"官方认为没有收益"。如果真实数据里出现 Q0 但战力上涨，册子会同时显示两个信号，正好用来验证官方评分和实测的差异
---

# 第 12 轮 · 游戏内册子 UI（2026-10-20 07:xx）

**目标**：把离线册子搬进游戏，做成 MCM / DSS 菜单那种结构。

## 已实现

| 部分 | 内容 |
|---|---|
| 入口 | **F5** 开关（原先 F1，作者要求改 F5） |
| 模式 1 | 局列表，↑↓ 选择（支持长按连发）、Enter 进入 |
| 模式 2 | 书页，←→ 翻页、↑↓ 滚动房间、Esc 返回 |
| 第 1 页 | 本局封面 + 每层战力条（真矩形） |
| 第 2~n 页 | 每层房间表（`^` 涨 / `v` 跌） |
| 背景 | 程序生成的 256×256 羊皮纸（噪点 + 污渍 + 暗边），24,858 B |
| 字体 | 游戏自带 `teammeatfontextended16bold.fnt` + `teammeatfont12.fnt` |

## 三次踩坑（都值得记住）

**① `Sprite:Load(path, loadGraphics)` —— 第二个参数不是"是不是 anm2"**

```lua
-- 游戏自带 resources/scripts/main.lua(645)
function META:Load(path, loadGraphics)
    Sprite_Load(self, path, loadGraphics ~= false)
end
```

`Sprite` **只接受 anm2**。喂 PNG 会让引擎按 XML 解析 → 原生断言 → **进程直接退出，`pcall` 挡不住**。

**② anm2 是 Version 5 结构，我写成了旧版**

- 错：`<Info Version="1"/>` + `<FrameAnimations><FrameAnimation .../>`
- 对：`<Info Version="5" Fps="30"/>` + `<LayerAnimations><LayerAnimation LayerId="0"><Frame .../>`

对照物：`mods/!!difflib_.../resources/gfx/ui/ex/difficulty_widget.anm2`（一个能用的最小 UI anm2）。

**③ 输入必须在 `MC_POST_RENDER` 里读**

放在 `MC_POST_UPDATE` 里读 `Input.IsButtonTriggered` 会**大量漏触发**，表现为"要按很多下才出来"。
参考 `mods/boss butch_3297246061/butch_scripts/dss/dssmenucore.lua`（Dead Sea Scrolls 菜单框架）——它的 `post_render` 同时负责输入和绘制。

**④ 字体颜色要 `KColor`，不是 `Color`**

```
bad argument #7 to 'Font_DrawStringScaled' (KColor expected, got userdata)
```

`Color()` 给 Sprite 用，`Font:DrawStringScaled` 要 `KColor(r,g,b,a)`。

## 被否决的视觉特性（记录以免重复讨论）

| 特性 | 否决理由 |
|---|---|
| 房间图（像素级） | 引擎没有 framebuffer readback，只能手工铺贴图，成本 1~2 周 |
| 房间网格布局（`██` 格子） | 玩家认不出房间 |
| 房间轮廓（形状 + 门位） | 同上，纯视觉噪音 |

**结论**：册子的价值在"数字和因果"，不在画图。

## 其他

- 游戏内不再有任何 STB / 静态房间数据的依赖
- 面板缺少时会退化成纯文字（`getPaper()` 失败 → `rect()` 空操作）
---

# 第 13 轮 · 游戏内册子 v2（结构重做）（2026-10-20 08:xx）

**作者定的结构**
```
第 1 页    Overview
第 2..N    亮点回顾：战力提升 Top3（3 页）+ 四级道具 Top3（时间顺序，同房合并）
                      + 零级道具 1 个（最早那一个）
最后       楼层页：时长 · 受伤 · 战力变化 · 诅咒 · 六维 · 道具图标网格
```

**同时删掉**：房间逐条明细（"没人喜欢看房间明细"）。

## 数据层

- 新增六维**进房值** `tso / sso / rgo / mvo / lko`，出房伤害 `dvo`
  （原来六维只在出房记一次，算不出"进房→出房"的提升）
- `highlight.analyze` 输出改为：`pages[]`（有序的亮点页）+ `floors[].stats`（楼层六维）
- 六维归一化基准：**本局各维度最大值**（先试这个，效果不好再上对数）

## 三次踩坑

**① 中文字符串直接进游戏字体 → 乱码**

```
Floor 9  room 21  Ã©Ã...     ← 宝箱房
228ç§                       ← 3分48秒
```

游戏位图字体只有 ASCII。所有进游戏 UI 的文本必须走英文：
新增 `roomNameEn()` / `durationEn()` / `curseNamesEn()`，`book.lua` 只用这套。
`text_render.lua`（离线）继续用中文，两边各取所需。

**② `ReplaceSpritesheet` 的 sheet id 是 1，不是 0**

anm2 里 `<Spritesheet Id="1">` + `<Layer SpritesheetId="1">`，然后
`sprite:ReplaceSpritesheet(1, png路径)` + `sprite:LoadGraphics()`。
（照 DSS/EID 的写法；id=0 时图标贴不上）

**③ 硬编码坐标在换字体后必然错位**

字宽变了，条就压到字上。改成**先量字宽再摆条**：

```lua
local wLab = textW(label, sc) / s
local xVal = x0 + wLab + 8
local wVal = textW(valStr, sc) / s
local xBar = xVal + wVal + 8
```

`textW` 用 `Font:GetStringWidth()`。

## 其他

- 纸加宽到 **360**（原 252 / 300），底条加高到 20
- 第 1 页也能用 →/Enter 进书（原来只有 Enter，导致"右边没反应"的错觉）
- `highlight.analyze` 现在会**合并默认配置**，避免调用方漏传键时 `math.min(nil)` 崩

## 仍未做

- 房型图标（皇冠/骷髅头）：还没找到小地图图标资源路径
- ImGui 配置页仍是空壳（已挂上菜单，只有一行占位文字）
---

# 第 14 轮 · 图标修好 + 中文尝试 + 诊断埋点（2026-10-20 09:xx）

## 图标终于出来了

根因：**字段名是 `GfxFileName`，不是 `Gfx`**。

```lua
-- EID features/eid_api.lua:1276-1279
spriteDummy:Load("gfx/eid_inline_icons.anm2", true)
spriteDummy:ReplaceSpritesheet(0, backgroundImage)
spriteDummy:ReplaceSpritesheet(1, item.GfxFileName)   -- ← 关键
spriteDummy:LoadGraphics()
```

我们的 dump 里 `Gfx` 恒为 `-`，就是因为读错了字段名。改正后：
`[UI] icons=8 fail=0` —— 8 个道具图标全部成功。

## 中文：还在试，但路径已明确

- 游戏自带 `mplus_12b.fnt` **没有汉字字形**（探针只出 `[CJK probe] ->`，右边空白）
- EID 自带 4 套中文字体（`eid_cn_default.fnt` 388 KB + 对应 png 599 KB），且自己用
  `"../mods/<folder>/resources/font/..."` 这种**跨 mod 相对路径**加载 → 我们照抄
- **`cjk=yes` 已经打出来了**，说明字体加载成功，问题在**绘制方法**：
  EID 用的是 `Font:DrawStringScaledUTF8(str, x, y, sx, sy, color, 0, false)`，
  我们一开始用的 `DrawStringUTF8` 什么都不画

## 诊断埋点（一次做全）

每次打开册子 / 每次翻页各打一条：

```
[UI] 打开册子：6 局  cjk=yes
[UI] page=1/16 pages=6 floors=9 cjk=yes icons=8 fail=0 screen=479x247 scale=0.91
```

| 字段 | 用途 |
|---|---|
| `page=x/y` | 当前页 / 总页数 |
| `pages` / `floors` | 亮点页数 / 楼层数 |
| `cjk` | 中文字体是否可用 |
| `icons` / `fail` | 图标成功 / 失败数 |
| `screen` / `scale` | 分辨率与缩放比（排版问题一看便知） |

另有 `[CJK] 使用字体: <路径>`、`[CJK] DrawStringScaledUTF8 失败：<err>`、
`[ICON] <id> OK/FAIL <路径>`、`[册子 UI render 出错：...]`。

## 重复犯的错（第 3 次）

替换代码块时用「从 A 到 B」的区间删除，结果**吞掉了夹在中间的无关函数**：
- 第 1 次吞掉 `txt()`
- 第 2 次吞掉 `segBar2()`

**教训**：改这个文件必须用精确的整行/整段替换，禁止区间删除。

## 流程约定（作者要求，长期有效）

> 每次代码修改都要：① 更新 CHANGELOG ② git commit 一下。
## 第 14 轮的补充修正（同日）

**字体加载的三个必需细节**（照 `EID:loadFont` 抄，之前全漏了）：

```lua
local ff = Font()
ff:Load(path, "")              -- ① 第二个参数必须给空串（GoG 版本兼容）
ff:SetMissingCharacter(2)      -- ② 设置缺字符号
if not ff:IsLoaded() then ... end   -- ③ 用 IsLoaded() 判断，不能靠 pcall
```

`Font:Load` 失败时**不抛错、静默返回**，所以之前的
`pcall(function() ff:Load(p) return ff end)` 永远"成功"，
`cjk=yes` 是个**假阳性**——字体对象有、字形没有。

现在三道校验：`Load(path, "")` → `IsLoaded()` → `GetStringWidth("伤害") > 0`，
任何一步不过就记 `[CJK] 加载失败: <路径> 原因=<...>` 并试下一个候选。

**六维增量改为百分比**（作者要求）：
`+2.74` → `+12.3%`。进房值为 0 时无法算比例，退回绝对值。
## 第 14 轮 · 字体路径排查（同日续）

**`CJK FONT: NOT FOUND`** —— 三个候选路径全部被 `IsLoaded()` 拒绝。
说明问题在**路径写法**，不是字体文件本身。

已核实的 EID 字体资产：

| 文件 | 大小 | 说明 |
|---|---|---|
| `eid_cn_default.fnt` | 388,858 B | **二进制 BMFont**（文件头 `BMF`） |
| `eid_cn_default_0.png` | 599,501 B | 主字形图 |
| `eid_cn_fix_0.png` | 115 B | 修补页（fnt 里引用了两次） |

注意 fnt 里 page 引用写的是**裸文件名**（`eid_cn_default_0.png`、`eid_cn_fix_0.png`），
按 BMFont 规范应相对于 fnt 所在目录解析——这一点需要验证 `Font:Load` 是否照做。

**六维增量**：进房值为 0 时统一显示 `0%`（不再退回绝对值）。

**下一步**：等 EID 字体加载路径的深度调研结论（子代理进行中），
拿到确定的路径字符串后再改。
## 第 14 轮 · 中文字体落地（同日续）

按作者决定：**把 EID 的中文字体复制进本 mod**，并注明来源（EID 免费开源）。

```
mod/resources/font/
  eid_cn_default.fnt     388,858 B   二进制 BMFont
  eid_cn_default_0.png   599,501 B   主字形页
  eid_cn_fix_0.png           115 B   修补页（fnt 内引用两次）
  CREDITS.txt                700 B   来源与授权说明
```

来源：External Item Descriptions（wofsauge 等），路径 `resources/font/`。

**加载顺序**改为先找自己这份：
```lua
CJK_CANDIDATES = {
    "font/eid_cn_default.fnt",                                   -- 内置，首选
    "../mods/external item descriptions_836319872/resources/font/eid_cn_default.fnt",
    "../mods/external item descriptions/resources/font/eid_cn_default.fnt",
}
```

## 顺带修掉一个部署 bug

`deploy.ps1` 的扩展名白名单里**没有 `.fnt`**，导致字体文件同步不过去
（部署目录只有 png，没有 fnt）。白名单已补
`.fnt / .ttf / .ogg / .wav / .json`。

> 这个坑同样适用于以后新增的任何非 lua/png 资源。
## 第 14 轮 · Overview 也改成百分比（同日续）

每层的增益从绝对值改为百分比（相对**进这一层时的战力**）：

```
Floor 5   101.26  ████...██  +70.9%   5m59s
```

进层战力为 0 时显示 `0%`（与六维同一套规则）。
条宽/文字位置仍按 `GetStringWidth` 动态算，所以改成百分比后不会错位。
## 第 14 轮 · 字体路径调研结论（子代理，含实证）

**核心结论：`Font:Load` 只认三种路径**（扫描了 64 个 mod 的 139 处 `:Load(...fnt)`）：

| 形式 | 例子 | 是否可用 |
|---|---|---|
| ① mod 自己的 VFS 键 | `font/pftempestasevencondensed.fnt` | ✅ 游戏自带字体就用这个 |
| ② 游戏根相对 | `mods/highlight-review/resources/font/x.fnt` | ✅ `heaven's call` 在用 |
| ③ 绝对 Windows 路径 | `D:\...\mods\x\resources\font\x.fnt` | ✅ EID / qing 在用 |
| `../mods/...` | 我们之前试的 | ❌ **无任何 mod 这么用** |

EID 里那段 `"../mods/"..modfolder.."...` 是**死代码**——它的 Site A（绝对路径）永远成功，
Site B 从没被执行过。

**跨 mod 加载字体=不可行**，实证：`log.txt:6223-6226` 三个候选全部失败。
需要 CJK 的中文 mod `qing_2787337337` 的做法是**自带字体**（`resources/font/eid9/` + 26 张页图）。

**EID 中文实际用的是 `eid_cn_alt.fnt`**（`descriptions/ab+/zh_cn.lua:20`，
`fonts[1].name = "cn_alt"`，行高 10），不是 `cn_default`（行高 13）。

**fnt 是二进制 BMFont v3**（魔数 `42 4D 46 03`），页名是**裸文件名**，按 fnt 同目录解析；
必须连 `eid_cn_fix_0.png`（16×16 存根，115 B）一起放，否则第 2/3 页坏掉。

## 本轮修正

- 候选路径改为：`font/eid_cn_alt.fnt` → `mods/highlight-review/resources/font/eid_cn_alt.fnt`
  → `font/eid_cn_default.fnt` → 游戏根相对版本
- 补拷 `eid_cn_alt.fnt`（256 KB）+ `eid_cn_alt_0.png`（467 KB）
- **修日志 bug**：原来打印的是 pcall 的第二个返回值（永远是 nil，所以每行都是 `原因=nil`），
  现在明确打 `IsLoaded=... width=...`
## 第 14 轮 · 两个真 bug（同日再续）

### ① 死亡却显示 UNFINISHED

`finishRun` 追加最终记录时，**没有先删掉换层检查点写进去的那一份**。

于是同一局在档案里存两条：
- 检查点版：`res=2`（未完成），房间少
- 收局版：`res=0`（死亡），房间全

UI 按 seq 排序后显示的是**旧那条**，所以 9 层 316 房的死亡局看起来是"未完成"。

修法：
```lua
if state.currentEntry then
    fmt.removeEntry(state.store, state.currentEntry)   -- 先撤检查点那份
    state.currentEntry = nil
end
fmt.appendRun(state.store, run)
```

### ② 中文字体加载时机

EID 是在 **`main.lua` 顶部（mod 初始化）** 加载字体的；
我们之前是在 `MC_POST_RENDER` 里懒加载 —— **渲染上下文里加载资源可能被引擎拒绝**。

改为 `book.init()` 里预先加载一次（init 在 mod 加载阶段执行）。

### ③ 探针加详

每次尝试都打一行完整状态：

```
[CJK] probe font/eid_cn_alt.fnt | Load返回=... | IsLoaded=false | width(汉字)=0 | width(AA)=0 | lineHeight=0
```

四个指标一起看就知道断在哪：
- `Load返回` 为 nil 且 `IsLoaded=false` → 引擎没加载（路径/格式问题）
- `IsLoaded=true` 但 `width(汉字)=0` → 字体加载了但没有汉字字形
- `width(AA)>0` 而 `width(汉字)=0` → 字体只有拉丁字形
## 第 14 轮 · 中文终于通了（同日终）

**实测结论：`Font:Load` 的三种路径里，只有「游戏根相对」形式有效。**

| 路径形式 | 结果 |
|---|---|
| `"mods/highlight-review/resources/font/eid_cn_alt.fnt"` | ✅ `IsLoaded=true`，汉字宽度 36，lineHeight=10 |
| `"font/eid_cn_alt.fnt"`（本 mod 的 VFS 键） | ❌ `IsLoaded=false`，且 `GetLineHeight()` 返回垃圾值 `8302` |
| `"../mods/..."`（EID 里的写法） | ❌ `IsLoaded=false` |

这与 heaven's call 的用法一致（`computer.lua:37` 用 `mods/<folder>/resources/...`），
也与 EID 自己用绝对路径（`main.lua:168`）的行为吻合——**VFS 键在这里不可靠**。

**教训**：加载失败时 `GetLineHeight()` 会返回未初始化的内存值（8302），
不能用它判断成功；必须用 `IsLoaded()` + `GetStringWidth()`。

最终候选（按优先级）：
```lua
local CJK_CANDIDATES = {
    "mods/highlight-review/resources/font/eid_cn_alt.fnt",
    "mods/highlight-review/resources/font/eid_cn_default.fnt",
    "font/eid_cn_alt.fnt",
}
```

---

# 第 15 轮 · 让 AI 自己进游戏点 F5（2026-10-20 09:3x）

**作者的要求**：改完 mod 不要每次都喊人进游戏点一遍，你自己进去按 F5 看功能对不对。

## 结论：可以，做成了一条命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\verify.ps1 -Deploy -Launch -Enter -F5
```

跑完在 `_logs\verify\<时间戳>\` 拿到 `01-menu.png` / `02-run.png` / `03-book.png`
和 `summary.txt`（mod 是否加载、Lua 报错、引擎断言、关键日志）。
退出码 0/1/2/3 分别是 正常 / 有错 / 环境问题 / 键盘被抢已中止。

## 这条路踩到的四个坑（下次别再踩）

| 坑 | 现象 | 解法 |
|---|---|---|
| `SendKeys` 不够用 | 游戏（SDL2+D3D）收不到"贴"进去的按键 | **SendInput 发键盘扫描码**（`_win.ps1` 的 `Send-GameKey`） |
| 窗口句柄会变 | 切全屏/换分辨率后重建窗口，`Process.MainWindowHandle` 变成 0，脚本以为"没窗口" | 用 `EnumWindows` 按 PID 枚举可见窗口，取面积最大的 |
| 前台锁 | `SetForegroundWindow` 返回 true 但其实没提到前台，按键会打进别的程序 | `AttachThreadInput` + `SetForegroundWindow` + **按前再确认一次前台**，不成就中止（退出码 3） |
| 启动器联网卡死 | `REPENTOGONLauncher.exe` 停在 "Checking for update..."，游戏永远不启动 | 默认走 **Steam**（`steam://rungameid/250900`）；launcher 只作 `-ViaLauncher` 备用 |

另外两个"什么时候算准备好了"的判据：

- mod 加载完：日志出现 `[HIGHLIGHT] loaded`
- 主菜单画出来了：**窗口标题不再含 `LuaEngine Initialized`**（启动阶段标题会带这个后缀）

进存档要按 **3 次** Enter：标题画面 → 存档槽（1/2/3）→ 存档内菜单（默认停在「继续游戏」）。
脚本就是这么连按的，看到日志出现 `[HIGHLIGHT] F\d|开局` 就停手。

## 第一次自动跑，抓到的问题（含一次自己的误判）

### ① 日志被 `[ASSERT] - PushRenderTarget: stack overflow!` 刷爆 —— 凶手不是我们

- 频率约 **190 行/秒（5.5 KB/s）**，一旦开始就**不停**（关掉册子也不停）
- 一开始我按"F5 前后的增量"判读，误以为是册子引起的；**用行号一对就翻案了**：

```
4103  第一条 Pair 日志        ← reverie_2538556220 打出来的
4802  第一条 PushRenderTarget ← 比册子早 200 多行
4824  我们的 F1 房间记录
5023  [UI] 打开册子
```

- 结论：**reverie（东方组合，`scripts/items/th14/d_flip.lua`）**在某个房间开始刷这个断言，
  我们的册子只是恰好在同一局里被打开。历史日志最高 45,825 条、单会话 2.8 MB 也是它。
- 顺带做的改动：字体/纸背景的加载提到 `book.preload()`（EID 同款做法）。
  它没治断言（本来也不是它的锅），但"别在渲染回调里加载资源"这条仍然成立，保留。
- `verify.ps1` 现在把断言单列成**提示**，不影响退出码（否则每次都会被第三方 mod 判红）。

### ② 册子右半边被切掉

当前窗口 1550×829（≈1.87:1），日志里 `screen=479x247 scale=0.91`。
`layout()` 用 `GetScreenWidth()/s` 居中、`PADW=360`，算出来右边界超出了画布 →
纸上内容在右边缘被裁。要按实际宽高比算，或者给 `PADW` 加上限。

## 又一次踩到 BOM

`.ps1` 写完没 BOM，Windows PowerShell 5.1 按 GBK 解析中文注释，
整份脚本 `Unexpected token` 直接炸。**新建/改完 .ps1 必须确认前三个字节是 `EF BB BF`。**

## 给下一次的提示

- 我可以自己跑这一轮并把截图**看懂**（`read_image`），不需要人描述画面。
- 想让我"进存档"，前提是**有可续的局**；没有的话最多到主菜单，脚本会提示。
- 每次循环约 2 分钟（60+ 个 mod 的加载时间是大头），所以别为了改一行文案去跑全套。

---

# 第 16 轮 · 截图缺边的真因：DPI + 窗口出界（2026-10-20 09:5x）

作者指出：双屏、游戏启动时不在屏幕左上角，截图才不完整。一查，是两个原因叠加。

## ① PowerShell 是 DPI-unaware，抓的是物理像素却按逻辑坐标算

主屏 1920×1080 @**125%**（`AppliedDPI=120`）。于是：

| 调用 | 返回 | 单位 |
|---|---|---|
| `GetClientRect` | 1550×829 | 逻辑（1536×864 是屏的大小） |
| `BitBlt`（CopyFromScreen 底层） | 真的像素 | 物理 |

1.25 倍的错位 → 截出来只有窗口左上角 1/1.25，右边那条自然没了。
册子页面在 1919 宽的画布里居中，被截到 1535 处，看着就像"右边缘被裁"。
**修法**：进程启动时 `SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2)`。

## ② 游戏窗口本身就一半在屏幕外

`options.ini` 里躺着：

```
WindowWidth=1919   WindowHeight=989
WindowPosX=201     WindowPosY=230
```

1919+201=2120 > 1920，989+230=1219 > 1080 —— 右下角都在屏幕外，
人眼看游戏也是缺的（作者截图里能看到窗口贴着屏幕右/下边被切）。
**修法**两层：

1. 启动前读 `options.ini`，放不下就改成 16:9 居中（这台机器 → 1600×900 @ (160,65)）
2. 主菜单画出来之后再量一次客户区（游戏是先建小窗、再按 ini 改尺寸的，早量会量到 978×587），
   还在界外就 `SetWindowPos` 挪回来——实测游戏不完全听 `WindowPosX/Y`，会自己放在 (128,128)

## 结果

```
窗口客户区 1600x900 @ (137,121)  DPI=per-monitor-v2
[截图] 03-book.png (1600x900)      ← 尺寸 = 客户区物理像素
```

截图里册子右边缘、右上角 `1/2` 分页角标、底部按键提示都在了。

## 顺手加的

- `tools/fix-bom.ps1`：把 `tools/*.ps1` 统一重存成 UTF-8 with BOM。
  这轮又被 BOM 坑了两次（`edit` 工具会写回无 BOM），以后改完跑一下就完事。
- `verify.ps1` 把断言洪水降级成"提示"（第三方 mod 刷的，不该由它判红），退出码只看 Lua 报错。

## 还留着的小问题（不急）

- 册子底部那行按键提示文字比页宽长，末尾 `F5 CLOS...` 会被切；
  `footer()` 用的是固定坐标，没按 `GetStringWidth` 折行。
- EID 的道具说明框会盖在册子下半部分（那串红字），是 EID 的浮层，不是我们的。

## 启动路径也顺手修了

排查时发现两种启动方式各有坑：

| 方式 | 现象 |
|---|---|
| `REPENTOGONLauncher.exe` | 卡在 "Checking for update..."，游戏永远不启动 |
| 直接开 `isaac-ng.exe` | **挂死**：进程在、窗口不响应、日志不写、mod 不加载（steam_api 初始化卡住） |
| `steam.exe -applaunch 250900` | 可靠；Steam 会给游戏加 `-popupwindow -borderless -nostartupmovies` |

所以 `Start-Game` 现在是：`steam.exe -applaunch` → `steam://` → （Steam 没开才）直接开 exe，
40 秒还没进程就明确报错退出（退出码 2），不再傻等。

另外：Steam 刚被强杀过游戏进程时会有一段"以为游戏还在跑"的脏状态，
`-applaunch` 会卡在 `CheckShaderDepotManifest` 一分钟以上。重启 Steam 即可，不是脚本的问题。
## 第 14 轮 · 颜色 / 探针 / 底部文字（同日终）

**颜色加深**（原来在米黄纸上对比不足）：

| 变量 | 原值 | 现值 | 用途 |
|---|---|---|---|
| `INK` | 0.24,0.19,0.14 | **0.16,0.12,0.08** | 主文字 |
| `INK_DIM` | 0.45,0.39,0.30 | **0.33,0.26,0.17** | 次要文字（原来的灰几乎看不见） |
| `INK_RED` | 0.52,0.17,0.12 | **0.46,0.10,0.06** | 标题红 |
| `INK_UP` | 0.16,0.40,0.18 | **0.10,0.32,0.12** | 上涨绿 |
| `INK_DN` | 0.55,0.12,0.10 | **0.50,0.08,0.05** | 下跌红 |

**删掉 CJK 探针**：`[CJK probe] ->` / `CJK FONT: NOT FOUND` 这些调试行已从界面移除
（`getCJK()` 的诊断日志仍保留在 log 里）。

**底部提示自适应**：原来固定字号，文字必然超出纸边被切；
现在用 `textW()` 量宽度，超了就按比例缩：

```lua
local avail = (PADW - 20) * s
local sc = s * 0.54
local wpx = textW(text, sc)
if wpx > avail and wpx > 0 then sc = sc * (avail / wpx) end
```

AGENTS.md 里"底部提示超宽会切掉尾巴（已知未修）"这条可以划掉了。

## 验证过程踩的坑（重要）

用 `verify.ps1` 截图后以为改动没生效，实际是**游戏跑的是旧代码**：

```
进程启动 10:19:56   源码修改 10:22:56   ← 差 3 分钟
```

AGENTS.md 已经写了"mod 不会热重载"，但我还是先截了图。
**正确顺序：改代码 → deploy → 杀进程 → 重启 → 截图**，
并且要核对 `进程启动时间 > 源文件修改时间`。
## 清空旧数据（2026-10-20 10:30）

旧存档全是"六维进房值"等字段加入之前写的，数据不完整（六维恒为 0），
按作者决定全部清空，从零开始攒新数据。

**备份位置**：`_backup\data-clear-20261020-103043\`
- `save1.dat` 135,965 B
- `save3.dat` 623 B
- `archive-all.dat` 73,594 B

**已删除**：
- `<游戏目录>\data\highlight-review\save*.dat`
- `_archive\all.dat`

**下一步**：作者会在 **3 号存档槽** 打新局，mod 会写到 `save3.dat`；
归档脚本扫的是 `save*.dat`，任何槽都能处理。
## 六维条区间修正（2026-10-20 10:4x）

**症状**：伤害 4.21，条一格都没有。

**原因**：条的比例算的是 `(值 - 本局最小值) / (本局最大值 - 本局最小值)`。
本局伤害最小值恰好就是 4.21，所以 `(4.21-4.21)/span = 0` → 空条。

作者最初的要求是「**0 到最大值**（幸运用最小值到最大值）」，是我实现时全部从最小值算起了。

**修正**：
```lua
-- 幸运可能为负，从最小值算；其它维度一律从 0 开始
local mn = (k == "lk") and (bk.statMin[k] or 0) or 0
```

离线验算（用真实量级的数据）：

| 维度 | 进房 | 出房 | 本局最大 | 棕 | 绿 | 增量 |
|---|---|---|---|---|---|---|
| 伤害 | 4.21 | 4.21 | 20.42 | **21%** | 0% | +0.0% |
| 攻速 | 2.95 | 4.86 | 5.50 | 54% | 35% | +64.7% |
| 射程 | 6.43 | 4.00 | 6.40 | 100% | 0% | -37.8% |

射程那行 `in > max` 时封顶 100%，`out < in` 时不出绿条，增量显示负数——行为正确。

**本次按要求没有启动游戏验证**，只做了离线验算 + luacheck + deploy。
## 终极 Boss 页 + 房间明细脚本（2026-10-20 13:0x）

### 新页：终极Boss与终极道具

页序改为：`Overview → 终极Boss与终极道具 → 战力 Top3 → 楼层`

- 终极 Boss 名单（号码来自调研，见下）
- 四级 / 零级道具并到这一页，取消原来的单独页
- 这一页**总是存在**（空则只显示标题）
- Overview 增加：本局四级图标（8 个/行，超出 `+N`）+ 终极 Boss 总结

### 终极 Boss 号码（调研确认）

`Room:GetBossID()` 返回的是**房间 subtype**（entities2.xml 的 `bossID`），不是实体类型。
两个特例：**祸兽房间返回 0**、**Boss Rush 没有 bossID**。

| Boss | 识别方式 |
|---|---|
| Hush | bossID **63** |
| 超级撒旦 | bossID **55** |
| 老干妈（Mother） | bossID **88** |
| 百变怪（Delirium） | bossID **70** 或实体 412 |
| 祸兽（The Beast） | 房间返回 0 → 实体 Type **951** |
| Boss Rush | RoomType **17** |

"见证者"确认**不存在于原版**（是 Antibirth 的 Boss），已按作者指示改用 Mother。

### 新增 tools：房间明细

`tests\rooms_dump.lua` → 输出 `_logs\rooms-<时间>.txt`，
把每局每一间房的全部字段列成表格（战力/停留/受伤/敌人/清房/口袋/六维进出/道具品质/终极Boss）。

### 用数据核实的两个问题

**① "只抓到一个四级道具"——实际是 0 个，且记录正确**

交叉验证 17 个道具的品质，与 `[DUMP] ITEM` 道具表**全部一致**。
那局 45 个道具的品质分布：Q0×2、Q1×19、Q2×15、Q3×9、**Q4×0**。
是这局确实没拿到四级，不是 bug。

**② "赢了却显示死亡"——存疑，已加收局诊断**

那局最后一间房：`型5(Boss) 形8  停留 402.3s  受伤 24  血量 99→0  isGameOver=true`。
99 颗红心挨 24 下不该归零，怀疑是胜利结算清零被当成死亡。

现在 `MC_POST_GAME_END` 会打一行：
```
收局诊断 isGameOver=? victoryLap=? hearts=? soul=? stage=? roomType=? maxHearts=?
```
下次收局就能判断 `isGameOver` 到底靠不靠得住。

### 顺带发现

那局战力在 **67.97 ↔ 135.94** 之间来回跳，正好 ×2——
就是之前说的"隔一个房间翻倍/减半"那个道具，符合已知行为。
## tools\Rooms.exe —— 房间明细一键导出（2026-10-20 13:1x）

把命令包成双击可用的 exe，做法沿用 `Book.exe` / `ParseSave.exe`（`csc.exe` 本地编译）。

- 源码：`tools\RoomsLauncher.cs`（6 KB exe）
- 等价于：`luarun.ps1 tests\rooms_dump.lua`
- 跑完自动打开最新的 `_logs\rooms-*.txt`

**踩到的坑**：`luarun.ps1` 依赖 **32 位 LuaJIT DLL**，
用 64 位 `powershell.exe` 会直接报"必须用 32 位 PowerShell"。
启动器现在固定调用 `C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe`。

编译命令：
```
csc /nologo /target:exe /out:tools\Rooms.exe tools\RoomsLauncher.cs
```
## Boss 房补采（2026-10-20 13:4x）

用房间明细核对作者记忆：**F9 的 Boss 房确实是 Hush，F10 的确实是百变怪**。

| 层 | stage | 关卡 | Boss |
|---|---|---|---|
| F9 | 9 | BlueWomb (???) | **Hush** ✓ |
| F10 | 12 | Void | **百变怪** ✓ |

但发现两个字段**全为 0**，原因是同一个：

```
F9 第12间 型5 boss=0  292.2s 受伤14    ← 本该 63 (Hush)
F10 第4间 型5 boss=0  402.3s 受伤24    ← 本该 70 (百变怪)
```

**根因**：`Room:GetBossID()` 文档写的是"返回房间里**第一个 Boss 实体**的 id"——
我们在 `MC_POST_NEW_ROOM`（刚进房）调用，Boss 还没生成，所以返回 0。
同理 `foes`（进房敌人数）在进房瞬间也是 0，导致全档案 374 间房全是 `敌0`。

**修法**：加一个 `MC_POST_UPDATE` 每帧补采，读到非 0 就停：

```lua
if (p.foes or 0) == 0 then p.foes = countFoes() end          -- 补敌人数量
if (p.bossIn or 0) ~= 0 and (p.ubIn or 0) ~= 0 then return end
-- 只在型5/Boss Rush房做，Boss 生成后再读 GetBossID
```

**影响**：终极 Boss 页在修复前**永远不会触发**（ub 恒为 0）。
修复后需**新开一局**才有数据。

## 房间明细核对结论（作者那局 E6A68F51-0）

- 374 间房 / 148 分钟
- 最久：F1 第28间 67 分钟（挂机）
- 真正的 Boss 战：F10 第14间 402 秒（百变怪）、F9 第12间 292 秒（Hush）
## 记一笔：随机弹幕数污染战力（不实现，仅记录）

「书套」这类道具**每次射击 50% 概率多发一颗**，而战力公式含 `multiShot` 因子：

```
战力 = 伤害 × 攻速 × 弹幕数        -- power.lua:68
```

我们只在进房/出房各采样一次 `GetMultiShotParams():GetNumTears()`，
所以**同一套面板属性下战力会在 ×1 与 ×2 之间随机跳**：

| 局 | 房间 | 战力 | 六维 |
|---|---|---|---|
| E6A68F51 | F7 第6间 | 58.52 ↔ 117.04 | 完全没变 |
| E6A68F51 | F4 第21间 | 76.76 → 38.38 | 完全没变 |

验算：`6.56 × 5.86 = 38.44` ≈ 出房战力 38.38 → 出房弹幕数 = 1；
进房 76.76 ≈ ×2 → 进房弹幕数 = 2。

**作者决定**：不在 UI 显示弹幕数；这类道具"应该单独维护"，**现在先不做**。
已记入 `DESIGN.md` 第 15 节 **E30**，包含以后可选的三种做法。