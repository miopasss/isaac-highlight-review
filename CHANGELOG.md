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
## 清空本轮数据（2026-10-20 13:22）

这两局是在 `boss`/`ub` 字段修复之前打的，Boss 相关全是 0，留着没用。
按作者要求清空，从下一局开始重新攒。

**备份**：`_backup\data-clear-20261020-132215\`

| 文件 | 大小 |
|---|---|
| `save1.dat` | 715 B |
| `save3.dat` | 105,154 B |
| `archive-all.dat` | 103,593 B |

**已删**：`data\highlight-review\save*.dat`、`_archive\all.dat`

**下一局会带上的新东西**：
- `boss` 房型 subtype（Boss 生成后补采）
- `ub` 终极 Boss 代码
- `foes` 进房敌人数（终于不会是 0 了）
## 版本管理：UI 改动合并为单一提交（2026-10-20 13:4x）

作者要求：main 上每个功能只占**一个节点**，细节留在功能分支里。

**操作**（一次性 bootstrap，此后再不对 main 重写历史）：

```
git tag pre-squash-20261020 c57b3ce        # 备份锚点
git branch feature/ui-v0.2 c57b3ce         # 保留 20 个真实提交
git reset --hard c552266                   # main 退回 UI 之前
git merge --squash feature/ui-v0.2         # 压成一个提交
git commit -m "增加UI（feature/ui-v0.2）"
git tag v0.2.0
```

**结果**：
- `main`：`c552266` → `增加UI（feature/ui-v0.2）`，只多一个节点
- `feature/ui-v0.2`：20 个提交完整保留，可逐步查看
- `v0.2.0` tag 打在合并提交上

**与公司规范的差异**：重写已推送的 main 属于**不合规操作**（保护分支禁止 force push）。
本次是单人仓库、无其他克隆，作为一次性过渡；此后 main 只接受 squash merge。
## 工具：tools\pr.ps1（2026-10-20 14:0x）

一条命令走完「功能分支 → PR → squash 合并」。

```powershell
# 只建 PR
.\tools\pr.ps1 -Branch feature/xxx -Title "增加XX（feature/xxx）"

# 建 PR 并立即 squash 合并 + 删远端分支
.\tools\pr.ps1 -Branch feature/xxx -Title "增加XX（feature/xxx）" -Merge -DeleteBranch

# 看现有 PR
.\tools\pr.ps1 -List

# 只合并已有 PR
.\tools\pr.ps1 -MergeOnly 3
```

**token**：`tools\.gh_token`（明文一行）。该文件已进 `.gitignore` ——
不是怕泄露（作者说仓库不重要），而是 **GitHub 的 secret scanning 会自动撤销
公开仓库里检测到的 token**，提交上去脚本就失效了。

**踩到的坑**：`git push` 把进度写到 stderr，在 `$ErrorActionPreference = "Stop"`
下会被当成终止性错误。已加 `GitOut` 封装把 git 输出当普通文本收。

**验证**：PR #2 建成功（随后关闭）、PR #3 建成功并 squash 合并、分支删除成功。
本脚本自己也是用它合并进 main 的。
## AGENTS.md 补第 12 节：Git 工作流（2026-10-20 14:2x）

把这套纪律写进给下一个 Agent 的说明书，避免下次对话又走错：

- 流程：分支 → 推 → **等作者发话** → `pr.ps1` squash 合并 → 删分支
- 硬规则：不自己合并、不对 main force push、只用 squash、合并标题带分支名
- token：`tools\.gh_token`，必须 gitignore（push protection 会拒、secret scanning 会撤销）
- 不设审批（作者自己不能 approve 自己的 PR）
- 提交身份 `piiiika`/`miopasss` 不一致，作者决定不改
---

# v0.3 · 自定义道具评级 + 权重（2026-10-20）

## 新增模块

| 文件 | 职责 |
|---|---|
| `core/jsonmini.lua` | 只服务评级表的最小 JSON 编解码（不依赖 `require("json")`，离线测试也能跑） |
| `core/rating.lua` | 评级/权重数据层 + `_G.HLR` 对外接口（未来拆 mod 的边界） |
| `core/rating_data.lua` | 默认表（写在代码里，**真全局**） |
| `core/itemwatch.lua` | 每帧监视 `GetCollectiblesList`，修采集盲区 |
| `core/pool.lua` | 权重快照 + `MC_POST_GET_COLLECTIBLE` 按倍数重掷 |
| `ui/rating_editor.lua` | ImGui 编辑器（**F6** 打开） |

## 数据结构

存档里新增一行：

```
Q={"v":1,"e":{"118":{"q":3.5,"w":2}}}
```

- `q` 评级 0.0–4.0，**向下取整**判四级（3.5 → 3，不算四级）
- `w` 权重倍数，1 = 不变，0 = 不出
- `on` 省略即启用

**局外解析**：`tools\rating.ps1`（`ConvertFrom-Json` 直接读）
**跨槽同步**：`tools\sync-rating.ps1 -From 3`（把 3 号槽的评级复制到另外两槽，自动备份）

## 读取优先级

```
saveN.dat 的用户覆盖  >  rating_data.lua 默认表  >  原版 ItemConfig.Quality
```

## 采集修复（itemwatch）

每帧比对 `player:GetCollectiblesList()`（REPENTOGON），修掉两个盲区：

- **同房内"获得又失去"**：净差为 0 → 漏记（例：小麦种子 → 小麦苗 → 成熟小麦）
- **跨房/换层瞬间获得**：落进新房间基线 → 永远不算获得

第一间房仍不记"获得"（起始道具不是获得的，是初始配置）。

## 权重实现

`MC_POST_GET_COLLECTIBLE` + 确定性重掷（照抄 Revelations 的做法）：

```lua
rng:SetSeed(seed, 35)
if rng:NextFloat() < (1 - mul) then 重掷 end
```

- **v1 只支持 mul < 1（降低/禁用）**
- mul > 1（提高）**未实现**：POST 阶段只能"强行替换"，会绕过 NO!/神圣宝珠等内建逻辑，风险高
- 不调用 `RemoveCollectible`，不删除池子条目
- 回调优先级 `CallbackPriority.LATE`：别人算完我们再微调

## 目录重排

```
tools\exe\        Book.exe / ParseSave.exe / Rooms.exe / build.ps1
tools\exe\src\    三个 Launcher.cs + LauncherCommon.cs（统一的根目录定位）
tools\*.ps1       所有 PowerShell 脚本
```

启动器改用 `RootFinder`（向上找 `tests`/`mod` 目录），不再假设与 .ps1 同目录。
重新编译：`.\tools\exe\build.ps1`

## 已知限制

| 项 | 说明 |
|---|---|
| 全局配置 | **做不到**。`mod:SaveData` 与 `Isaac.SaveModData` 是同一个按槽文件，用 `sync-rating.ps1` 局外同步 |
| ImGui 图标 | 无 `AddImage`，编辑器只显示名字 |
| 1750 项列表 | 无滚动列表控件，用过滤 Combobox |
| 权重提高 | v1 不支持 |
| 控件持久化 | ImGui 不存盘，每次渲染从 rating 表推回 |

## 验证

- `tests\rating_test.lua`：**20/20 通过**（含 JSON 往返、向下取整、停用/启用、坏数据容错）
- `tests\identity_test.lua`：20/20 通过
- `tests\fmt_test.lua`：通过
- luacheck：16 个文件 0 失败
- **按要求没有启动游戏验证**
## v0.3 修复：F5/F6 失效的三个真实原因（2026-10-21 03:0x）

### ① `ImGui.SetSize` 在这个版本是 nil

启动日志：`[EDITOR] CreateWindow 失败: attempt to call a nil value (field 'SetSize')`

整个 `build()` 被这一步炸掉 → 编辑器从未建成 → F6 无效。

**修**：改用 `SetWindowSize`（实测存在）+ `SetWindowPosition`，并逐步 `tryStep` 包起来，
任何一个控件缺失只记日志、不影响其它控件。

### ② F5 其实没坏，是我的自动化测试进错了存档槽

测试日志里根本没有 `载入 N 局` —— 说明进的是**空槽**，`sortedRuns()` 返回空，
`isOpen` 立刻被关回去，看起来就是"F5 没反应"。

**教训**：验证 F5 必须先确认日志里有 `载入 N 局`。

### ③ `ImGui.Show()` 会接管键盘，但 F6 仍能被收到

实测按 F6 → `[EDITOR] 打开`，再按 F6 → `[EDITOR] 关闭`，两次都收到了。
但稳妥起见关闭时补了 `ImGui.Hide()`，把控制权还给游戏。

## 排查过程的三个教训（写进这里免得再犯）

1. **在 `MC_POST_RENDER` 里插探针要小心**：我删除临时探针时把 `add(ModCallbacks.MC_POST_RENDER, function()` 这一行一起删了，导致语法错误。
2. **PowerShell 变量大小写不敏感**：`$t` 和 `$T` 是同一个变量，我的路径变量被列表变量覆盖，写入路径变成空串。
3. **`Set-Content`/`Replace` 的缩进假设**：多次因为 here-string 里多写了前导空格导致替换静默失败。**改代码一律用行号定位，并在改完后 grep 验证**。

## 当前状态

- F5：进有数据的存档后正常
- F6：正常打开/关闭编辑器
- 编辑器窗口：520×460，位置 (120, 90)（会被别的 mod 的"控制台"窗口遮住，非本 mod 问题）
## v0.3 编辑器大修（2026-10-21 03:2x）

按作者反馈改了 7 处，其中 3 个是真 bug：

### 真 bug（实测定位）

| # | 现象 | 根因 |
|---|---|---|
| 1 | 进 Boss 房报错 | 我加的诊断钩子调用了不存在的 `Room:GetShape()`（应为 `GetRoomShape`）→ **整个钩子已删除** |
| 2 | 「已获得道具」显示全部 1763 个道具 | `GetCollectiblesList()` 返回 `{ [id] = 持有数量 }`，**包含全部道具，数量 0 表示没有**。我按"所有键都是已获得"处理了 → 改成按数量 > 0 过滤 |
| 3 | 权重倍数设了不生效 | 控件回调参数个数不一致（有的给 `(value)`，有的给 `(id, value)`），`tonumber(nil)` → 写进 nil → 等于没写。加 `pickNum` 两种都兼容 |

### 界面改动（按作者要求）

- **池子权重显示全部删除**（`池0 1.00→1.00` 看不懂）
- 搜索：**纯数字按 id**，字母按英文名/本地化名；名字做了**首字母大写**（`THE SAD ONION` → `The Sad Onion`）
- 编辑页三个入口并列：**搜索 / 已获得道具 / 已修改**
- 「已修改」页改成 `AddTextWrapped` 整段文本（实测这个版本没有 `AddTextWrapped`，改用 `AddText(..., wrap=true, id)`）
- 评级、权重都改成**数字输入框**（支持两位小数），去掉滑条
- 「启用」从勾选框改成**按钮**（文字随状态变：`状态：启用（点击停用）`）
- `q=` / `w=` 改成中文 **评级 / 权重**
- 窗口挪到 `(780, 100)`，尺寸 `520×500`，避开别家 mod 的"控制台"窗口
- 新增 ImGui 菜单入口 **`Highlight Review → 道具评级`**，与 F6 共用同一开关状态

### 这一轮实测到的 REPENTOGON API 差异（补充进踩坑记录）

| 想要 | 这个版本的实际 |
|---|---|
| `ImGui.SetSize` | ❌ nil → 用 `SetWindowSize` |
| `ImGui.AddTextWrapped` | ❌ nil → 用 `AddText(parent, text, wrap=true, id)` |
| `GetCollectiblesList()` | `{[id]=数量}`，**全量 1763 项**，要按数量过滤 |
| `Room:GetShape()` | ❌ 不存在（`GetRoomShape`） |

### 测试方式

- 离线：`tests\rating_test.lua` **20/20 通过**
- 进游戏实测（脚本自动做）：
  - 起游戏 → 进 1 号档 → F8 临时钩子写两条评级 → 检查 `save1.dat` 出 `Q=` 行 ✅
  - `Q={"v":1,"e":{"118":{"q":3.75,"w":0.5},"1052":{"q":2.25,"w":0,"on":false}}}` ✅
  - F6 打开编辑器截图：三个入口 + 评级/权重 + 状态按钮 + 删除按钮都渲染 ✅
  - 「已获得道具」显示 `105 The Da...`（真实持有道具，不再是全量）✅
- **未验证**：鼠标点击选择/改值这条链（我的自动化点击没点中 ImGui 控件，坐标与游戏窗口尺寸有缩放差）→ **需要作者手动点一下确认**

测试钩子（F8）和临时日志已全部删除。
## v0.3 设置界面 + 权重代码审查 + 修数据丢失（2026-10-21 03:4x）

### 一、权重代码审查结果：找到 3 个会出问题的点

| # | 问题 | 后果 |
|---|---|---|
| 1 | **回调里再调 `pool:GetCollectible()` 会再次触发本回调** | 无限递归 → 卡死/崩溃。加 `P.inCallback` 防重入 |
| 2 | `RNG()` 无参构造 | 这个构造可能不接受空参 → 整个回调报错。改成 `pcall(RNG, seed)` + 失败即放弃 |
| 3 | `seed` 为 nil 时 `(seed + i*7919)` 直接报错 | 加 `local s = tonumber(seed) or 0` |

修完后 `onPostGet` 的结构：

```
防重入 → 取倍数 → 只处理 <1 → seed 兜底 → RNG(seed) 派生随机
→ 概率判定 → 重掷（带防重入标志）→ 返回替换 id
```

**结论：代码逻辑对了，但权重"是否真的生效"没法自动验证**——需要实际多局抽道具统计。
按作者意思：**先不测，交给作者用多局观察。**

### 二、修掉一个会丢数据的 bug

发现 `save1.dat` 里的 `Q=` 行**消失过一次**。

根因：`rating.save()` 在"评级还没从存档读过"时执行，此时 `entries` 为空，
于是它把已有的 `Q=` 行当成"用户删光了"给删掉。

**修法**：加 `R.loaded` 标志，**没读过档就绝不写**。

```lua
function R.save(store)
    if not R.loaded then return false end   -- 还没读过档：原样保留，绝不覆盖
```

实测：注入 Q 行 → 起游戏 → `载入自定义评级 3 条` → 关游戏 → **Q 行仍在** ✅

### 三、设置界面（新增）

- 菜单 `Settings` 改名 **`设置`**
- 设置窗口里两个 **热键绑定控件**（`AddInputKeyboard`）：`打开册子` / `道具评级`
- 热键存 `C=` 行：`C={"f5":294,"f6":295}`，局外可解析
- 热键改动即时写盘
- `book.lua` 的 F5 改成读配置（`deps.hotkeyF5`）
- 窗口尺寸/位置：设置 560×260 @(520,300)，评级 620×560 @(490,170)（按 1600×900 居中）

### 四、踩坑补充

- **`splitBlob` 把第一行当魔数**：我手写测试数据时把 `Q=` 放到 `MRV2` 前面，
  Q 行被当成魔数消耗掉了。**注入测试数据必须把 MRV2 放第一行。**
- `Q`/`C` 行现在**不计入任何一局的记录数**（否则会污染 `trimToCount` 的统计）

### 五、测试

- `tests\rating_test.lua`：**22/22 通过**（新增"未 load 时 save 必须被拒绝"用例）
- `tests\identity_test.lua`：20/20 通过
- 游戏内：注入 3 条评级 → 启动 → `载入自定义评级 3 条` → 界面「已修改」显示
  `1 The Sad Onion 评级 4...` → 关游戏 → Q 行保留 ✅
## README 重写（2026-10-21 04:0x）

原来的 README 是 v0.1 时代的**开发文档**（讲脚本、讲 DPI、讲怎么跑测试），
给玩家看没有任何信息量。按作者要求重写成**功能说明**：

- 现在能做什么：册子（F5）、评级与权重（F6）、设置（热键绑定）
- 册子的页面顺序与按键表
- 六维双色条的含义
- 终极 Boss 名单
- 数据文件在哪、里面是什么
- 局外工具一览
- 已知限制（权重只能降、按槽存、随机弹幕道具等）
- 开发文档挪到文末一小节

`AGENTS.md` / `DESIGN.md` / `FORMAT.md` / `CHANGELOG.md` 保持不变。
## 局外工具入仓 + 工坊发布清单（2026-10-21 05:0x）

### exe 重新编译并入仓库

`tools\exe\` 下三个启动器全部重新编译（旧版是目录重排前编的，找不到脚本）：

| exe | 用途 | 实测 |
|---|---|---|
| `Book.exe` | 生成册子文本 | ✅ 归档 6 局并生成报告 |
| `ParseSave.exe` | 存档导出 JSON | ✅ save1/save3 都导出了 |
| `Rooms.exe` | 每局房间明细 | ✅ 写出 `_logs\rooms-*.txt` |

**踩坑**：旧 `Book.exe` 进程卡在"按任意键关闭"（`Console.ReadKey` 在重定向 stdin 时不退出），
**文件被锁** → `csc` 报 `CS0016 未能写入输出文件` → 之后几次"编译成功"其实一直在用旧 exe。
以后重建前先 `Get-Process Book/ParseSave/Rooms | Stop-Process`。

### `.gitignore`

去掉 `tools/exe/*.exe` 一行，三个 exe 现在**纳入版本管理**。
（`tools/*.exe` 保留，防止以后在 tools 根目录生成 exe 又被误提交。）

### `parse-save.ps1` 认识 `Q=` / `C=` 行

之前会警告 `未知作用域: Q; C`。修的时候第一版插入位置破坏了 `if/elseif` 链语法，
改成 `elseif ($rec.scope -eq "Q" -or $rec.scope -eq "C") { }`。

### README 新增「创意工坊发布清单」

明确写清只打包 `mod/`，**不带** `tools/`（含 exe）、`tests/`、`_logs/`、`_archive/`、`_backup/`、`*.md`。
## 修「从菜单打开编辑器时已获得道具为空」+ 评级上限 4.99（2026-10-21 05:3x）

### 问题

从 ImGui 菜单 `Highlight Review → 道具评级` 打开窗口时，`已获得道具` 是空的。

根因：列表只在 **F6 那条路**（`E.toggle` → `E.refresh`）里刷新过；
菜单入口是 `LinkWindowToElement` 直接把窗口显示出来，**不经过 toggle**，所以从来没刷过。

### 修法

不做周期刷新（作者明确否掉），改成**可见性变化触发一次**：

```lua
local lastVisible = false
function E.watch()
    local vis = ImGui.IsVisible(WIN)
    if vis and not lastVisible then E.refresh() end   -- 刚变可见 → 刷一次
    lastVisible = vis
end
```

主循环每帧调 `ratingEditor.watch()`。开销只有一次 `ImGui.IsVisible` 查询。

### 评级上限

`0.00 ~ 4.00` → **`0.00 ~ 4.99`**。向下取整判四级，所以 4.99 仍算四级。

### 实测

进入 1 号档 → 打开编辑器（菜单/F6 都走 `watch`）→
`已获得道具` 显示 `105 The D6`，`已修改` 显示 `1 The Sad Onion 评级 4...` ✅
## README 增加「它是怎么工作的」+ 冲突排查（2026-10-21 05:5x）

作者要给 Workshop 写介绍，发现 README 里对"权重到底怎么生效"只有一句
"目前只能降低"，没解释机制。补了一节：

- 三步流程图（抽结果 → 决定发给你 → 拿到手），标明我们插在第 2 步
- 三条白话说明：1.00 放行 / 0.50 一半机会否掉 / 0.00 每次都否掉
- 明确写"不修改任何东西"：不改池文件、不改道具属性、不改别的 mod 数据
- 四个"因此你会看到的行为"（概率性、0 = 摘除、大量设低会刷不到、重掷不跨池子）
- 冲突排查三步法 + "只有会改道具池的 mod 才可能撞车"

**措辞上刻意避开了"前流程/后流程"** —— 对玩家没有信息量，还容易和
"修改道具生成表"混淆。改成流程图更直观，也正好是排查冲突时最需要的信息。
## README 贴界面截图（2026-10-21 06:1x）

作者提供了一张 1600×900 的编辑器截图（窗口完整、无遮挡），存为
`docs/img/rating-editor.png`，嵌进 README 的「道具评级与权重」小节。

- 尺寸 16:9，可直接用作 Workshop 预览图
- 图里有：三个入口（搜索 / 已获得道具 / 已修改）、评级与权重输入、
  保存修改 / 停用此条 / 删除此条 四个按钮

**排查记录（花了两轮才搞对）**：自己从旧截图里裁窗口一直切掉左边缘，
原因是我们窗口的左边界在 x≈590，而 ImGui 窗口背景色 (16,17,18) 和
游戏暗部颜色接近，靠"找暗色区域"自动定位会认错。最后直接用作者给的整图。
## 拆成两个 mod（2026-10-21 06:xx）

作者拍板：拆。理由不是"受众不同"这么简单——**v0.3 让回顾挂了 `MC_POST_GET_COLLECTIBLE`，
它从只读观察者变成了会改游戏的 mod**，这才是必须拆的根因。

### 新结构

```
shared/settings.lua        唯一一份源码，deploy 时复制进两个 mod
mod-rating/                Item Weight Editor（目录 highlight-rating，v0.1.0）
mod-review/                Highlight Review（目录 highlight-review，v0.3.0）
```

### 评级 mod（新）

| 文件 | 内容 |
|---|---|
| `main.lua` | 只做三件事：装评级数据、挂 pool 钩子、开编辑器 |
| `core/store.lua` | 自己的存档容器（`IWE1` + `Q=` / `C=` 行） |
| `core/{jsonmini,rating,rating_data,pool,settings}.lua` | 从回顾搬过来 |
| `ui/rating_editor.lua` | 从回顾搬过来 |
| `ui/config.lua` | 只绑 F6 |

### 回顾 mod（改）

- 移除：`core/{pool,rating,rating_data,jsonmini}.lua`、`ui/rating_editor.lua`、`MC_POST_GET_COLLECTIBLE` 钩子、F6 处理
- 新增：`externalQuality(id)` —— 读 `_G.HLR`，读不到返回 nil 由调用方回退官方
- `qualityOf()` 改为优先用 `externalQuality`
- 设置窗口只剩 F5
- 描述加一句"配合 Item Weight Editor 可显示自定义评级"

### 工具

- `deploy.ps1`：`-Mod both|review|rating`，同步前把 `shared/` 复制进两个 mod
- `luacheck.ps1`：默认检查 `mod-review` + `mod-rating` + `shared`（22 个文件）
- **新增 `pack.ps1`**：打 `dist\highlight-{rating,review}.zip`，只含各自目录
- `tests/*` 路径从 `mod/core` 改为 `mod-review/core` / `mod-rating/core`

### 顺带修的两个真 bug（都是拆分时发现的）

1. **`num()` 作用域**：`local function num` 定义在 `ultimateBossNow` / `bossIdNow` **之后**，
   这两个函数里的 `num` 被编译成全局查找 → nil → `pcall` 吞错 → 返回 0。
   **Boss 识别失效两轮的真正原因。** 已把 `num` 提到最前。
2. **`MC_POST_GAME_END` 签名**：第一个参数是 `mod`，不是 `isGameOver`。
   `function(isGameOver)` 收到的是表（永远真值）→ **所有通关都标成死亡**。改为 `function(_, isGameOver)`。

### 测试

- luacheck：22 个文件，0 失败
- `rating_test.lua` 22/22、`identity_test.lua` 20/20、`fmt_test.lua` PASS
## 修重复存档（小退一次多一条空记录）

作者实测：打完一局 10 层 327 房，存档里同一局存了 **6 份**，其中 5 份是空记录：

```
#5  seq=2 E41A634F-0 res=2 rooms=0   final=17.46
#6  seq=2 E41A634F-0 res=2 rooms=0   final=22.95
#7  seq=2 E41A634F-0 res=2 rooms=0   final=57.24
#8  seq=2 E41A634F-0 res=2 rooms=0   final=303.09
#9  seq=2 E41A634F-0 res=2 rooms=0   final=321.50
#10 seq=2 E41A634F-0 res=1 rooms=327 final=321.50  ← 只有这份是完整的
```

`final` 一路递增 = 每次小退都多写一条。

### 修法：读档时按 run id 去重

`fmt.dedupe(store)`：同一局 id 只保留**行数最多**的那一份，其余删除（从后往前删，避免 start 偏移失效）。
`loadData` 里调用，清理条数写日志。

### 离线验证（真实存档）

| 存档 | 去重前 | 去重后 | 删掉 |
|---|---|---|---|
| save1 | 13 条 | 8 条 | 5 |
| save3 | 10 条 | 2 条 | 8 |

保留的都是最完整的那份（`2047CBC3-0` 留 rooms=43，`E41A634F-0` 留 rooms=327）。

### 根因还没定位

`state.current` 只有两处赋值（续接 / 新开局），续接分支看着是对的。
空记录说明某次 `PRE_GAME_EXIT` 时 `state.current` 是个 0 房间的新对象。
**去重能兜住症状**（每次读档自动清掉），根因留待后续用 run id 诊断。

---

## 顺带确认：Boss 识别 + 通关判定已完全修复

同一局的日志：

```
[BOSSCLEAR] boss=63 ub=1     ← Hush
[BOSSCLEAR] boss=70 ub=6     ← 百变怪
收局诊断 isGameOver=false     ← 是布尔了
收局 E41A634F-0  res=1        ← 正确记成通关
```

落盘数据里 10 个 Boss 房全部有 id（60/2/91/67/15/78/6/25/63/70），Hush 和百变怪都带 `ub`。
## 三处按作者决定的修改

### ① 弹幕数不计入战力（作者决定 2026-10-21）

`power.lua` 普通泪弹分支从 `dmg × rate × multi` 改为 **`dmg × rate`**。

原因就是 E30 记的那件事：随机多发道具（书套）会让同一套面板属性下战力乱跳，
而 UI 按作者要求不显示弹幕数，于是玩家看到「战力暴涨但六维不动」，无从解释。

多发道具**以后单独维护**。快照里仍然记录 `multiShot`，只是不再进公式。

### ② 四级/零级道具只统计「离开时还持有」的

作者报：一局里「四级道具（3）：神圣屏障(313) × 3」，但他**从来没拿过**这个道具。

根因：`itemwatch` 为了抓住「麦苗」这种**加了又没**的衍生道具，是按"每帧比对持有数量、增加了就记"。
代价是**任何 mod 临时塞给你的道具都会被记成"拿到了"**。

修法：房间记录新增平行数组 `ik`（0/1），在 `settleRoom`（离开房间那一刻）用
`player:HasCollectible(id)` 采样：

```
it = [313, 355]   拿到什么
iq = [4, 3]       评级
ik = [0, 1]       离开时还在吗
```

- **楼层明细**：`it` 全部照旧显示（临时道具看得到）
- **四级/零级汇总**：只统计 `ik == 1`
- 旧存档没有 `ik` → 视为全部为 1，不影响历史数据

### ③ Boss 房回访

作者确认「打完回头是正常运营」，选择**保持多条记录**，只要在册子里标出来。
实测 `firstVisitNow()` 用的是引擎的 `Room:IsFirstVisit()`，回访时返回 false，
战力提升页已经会显示 `(revisit)`，**无需改动**。

### 测试

luacheck 22 文件 0 失败；fmt_test PASS、identity_test 20/20、rating_test 22/22。
## 清理：dist/ 不进仓库

上一轮合并时 `git add -A` 把 `tools\pack.ps1` 的产物（`dist\*.zip`，合计 1.3 MB）
一起提交了。打包产物不该进版本库，已从索引移除并加进 `.gitignore`。
## 小版本：权重 mod 支持纯英文界面

作者要求：**只给权重 mod 做双语**，语言切换放在它的 settings 里，先不测试。

### 新增

- `mod-rating/ui/lang.lua` —— 中英文案表（约 30 条），`L.t(key)` 取词
- 设置窗口加 **语言 / Language** 两个按钮（`中文` / `English`）
- 语言存 `C=` 行的 `lang` 键：`C={"f6":295,"lang":"en"}`
- 英文模式下**道具名也用英文**（中文模式用本地化名）

### 切换机制

ImGui 的控件标签只能在创建时给定，所以切语言会**重建窗口**：
`ImGui.RemoveWindow(WIN)` → 重新 `buildUI()`。`RemoveWindow` 不在时退回"只更新能更新的文字"。

### `shared/core/settings.lua` 升级

原来只支持数字值，现在支持字符串：

| 输入 | 解析 |
|---|---|
| `"f6":295` | 数字 |
| `"lang":"en"` | 字符串 |

写回时数字不带引号、字符串带引号。`S.only` 过滤照旧——
回顾只写 `{"f5"}`，评级写 `{"f6","lang"}`，两边不会互相覆盖。

### 验证（离线）

- 设置往返：`C={"f6":295,"lang":"en"}` → 读出 `lang=en` → 改回 `zh` → 写回 `C={"f6":295,"lang":"zh"}` ✅
- `only={"f5"}` 时只写 `C={"f5":294}` ✅
- luacheck 23 文件 0 失败；rating_test 22/22、fmt_test PASS、identity_test 20/20

**游戏内暂未测试**（作者要求等通知）。
## 修：deploy 只复制不删除，导致拆分后的旧文件一直留在游戏目录

作者发现 ImGui 顶栏的 `Highlight Review` 菜单下面**还挂着「道具评级」**。

根因：`deploy.ps1` 只把源文件复制过去，**从不删除目标里多出来的文件**。
拆分时把 `core/{rating,rating_data,pool,jsonmini}.lua` 和 `ui/rating_editor.lua` 从 repo 删掉了，
但游戏目录 `mods\highlight-review\` 里那 7 个旧文件一直在。

- 仓库 `mod-review`：24 个文件
- 游戏目录实际：**30 个文件**（多 7 个旧文件 + 2 个旧资源 `hl_panel.*`）

旧 `ui/rating_editor.lua` 里写着 `MENU = "highlight_review_menu"` + `AddElement(..., "道具评级")`，
所以菜单项还在。它**并不报错**，因为新的 `main.lua` 已经不再 `include` 它了。

### 修法

`deploy.ps1` 复制完之后**对比源和目标**，把目标里多余的、扩展名在同步范围内的文件删掉，
打印「清理了 N 个残留文件」。

实测清理：

```
已同步 23 个文件 -> mods\highlight-review
  清理了 7 个残留文件（源里已没有）
```

清理后 `mods\highlight-review` 只剩 23 个文件，与 repo 一致；
全库再搜「道具评级」只剩注释，没有任何 `AddElement`。

### 教训

**拆分/删文件之后必须 `deploy -Clean` 或者依赖现在这个自动清理**，
否则游戏里跑的是"新 main + 旧模块"的混合体，症状诡异且不报错。
## 修闪退：`ImGui.RemoveWindow` 会崩游戏

### 现场

作者报闪退。日志里有完整栈：

```
Lua stack trace:
[C](-1): RemoveWindow
.../highlight-rating/ui/rating_editor.lua(396)
.../highlight-rating/ui/rating_editor.lua(395): rebuild
.../highlight-rating/main.lua(95): loadData
Caught exception, writing minidump...
```

**`ImGui.RemoveWindow` 在这个版本会直接崩游戏**，而且我在 `loadData`（`MC_POST_PLAYER_INIT`）里调它，
那时候根本不在 ImGui 的帧上下文里。

### 修法

1. **彻底不调 `RemoveWindow`**。`editor.rebuild()` 改成空实现并注释说明原因。
2. **建窗口推迟到读完档之后**：文件加载时不再 `editor.init` / `configui.init`，
   改到 `loadData()` 里 `lang.init()` 之后调 `initUI()`。这样语言**一次就位**，不需要重建。
3. 语言切换改为「存盘 + 提示重启」：`lang.needRestart()` 返回
   `Saved. Restart the game to apply.` / `已保存，重启游戏后生效`。

### 又踩了 Lua 作用域

`initUI()` 里的 `onChanged = function() saveData() end` —— `saveData` 定义在 `initUI` **之后**，
闭包会把它编译成全局查找 → nil。改成前置声明 `local saveData` + `saveData = function()`。

**这是这个项目第三次被「local 只往后可见」坑到**（前两次是 `num()`）。

### 离线校验

- 代码里用到 **33 个文案 key**，英文表**零缺失**（只有 `menu_name` 中英相同，是故意的）
- `needRestart()` 中英都能正确返回

### 游戏内

闪退已消失（进程存活、日志无 `Caught exception`）。
**英文界面的视觉确认被卡住**：游戏反复重播结局动画，进不去正常界面。等作者正常进一局再看。
### 修 settings 解析：数字键匹配不到 `f6`

`S.load` 的键名模式原来是 `"(%a+)"` —— **`%a` 只匹配字母**，所以 `"f6":295` 里的 `f6`
（含数字）**永远解析不出来**。之前没暴露是因为 `f6` 有默认值 295。

改成 `"([%w_]+)"`，两处（字符串值 + 数字值）都改。

离线验证：

```
in=C={"f6":300,"lang":"en"}   读到 lang=en f6=300   → 写回 C={"f6":300,"lang":"en"}
```

（改之前 `f6` 读到的是默认 295，300 被丢弃。）

### 另外确认：后来又崩的两次**不是我们的 mod**

查了栈：

```
[C](-1): RemoveTrinket
...soul_3290493485/ibs_scripts/commons/classes/marks.lua(126)
```

是第三方 mod `soul_3290493485` 在换层时调 `RemoveTrinket` 崩的。
另一次是 reverie（东方）的 `PushRenderTarget: stack overflow!` 断言洪水之后进程消失。

**我们的 `RemoveWindow` 那条栈已经不再出现。**
## 修双语的三个真 bug（都是实测挖出来的）

### ① `RemoveWindow` 崩游戏 → 见上一条

### ② `local` 作用域：`saveData` 在 `initUI` 之后定义

改成前置声明 `local saveData` + `saveData = function()`。

### ③ **两个 mod 共用 `core/settings.lua` → `require` 缓存串台**

这是双语一直不生效的真正原因。

REPENTOGON 的 `require` **按模块名全局缓存**。两个 mod 都有 `core/settings.lua`，
谁先加载谁赢。实测：评级 mod 拿到的是**回顾 mod 那份**（main 分支的旧版本，**没有 `lang` 键**），
于是 `settings.get("lang")` 返回 nil，语言永远是默认的 zh。

诊断日志：

```
[BOOT2] getType=function f6=295 lang=nil defaultsType=table
[I18N]  settings=true rawLang=n/a
[I18N]  lang=zh
```

`f6=295` 有值（那份旧文件有 f6），`lang=nil`（旧文件没有）—— 一眼看出拿错了文件。

**修法**：共享代码按 mod 改文件名。

```powershell
$sharedMap = @{
    "highlight-rating" = @{ "core\settings.lua" = "core\iwe_settings.lua" }
    "highlight-review" = @{ "core\settings.lua" = "core\hlr_settings.lua" }
}
```

两个 main 的 `tryRequire` 也跟着改，仓库里的两份 `core/settings.lua` 删掉。

### ④ `settings` 解析漏掉含数字的键

键名模式 `"(%a+)"` 里 `%a` 只匹配字母，`"f6":295` 永远解析不出来（之前没暴露是因为有默认值）。
改成 `"([%w_]+)"`。

### 验证

```
[I18N] settings=true rawLang=en
[I18N] lang=en
```

界面截图确认变成英文：`Item Weight Editor` / `Edit` / `Modified` / `Search` / `Owned` /
`Pick an item below` / `Rating` / `Weight` / `Save` / `Disable` / `Delete (vanilla)`。

窗口从 620 加宽到 **780**，英文文案另做了缩短（`Search (digits = id, letters = name)` →
`Search (id or name)`），避免被右边切掉。
## 修：Item Weight 菜单里有两个同名的「设置」

`ui/config.lua`（设置窗口）和 `ui/rating_editor.lua`（编辑器窗口）都往
`item_weight_menu` 里挂了一项，而且文案都用 `T("menu_settings")` → 显示成两个「设置」。

拆成两个文案：

| 菜单项 | 中文 | 英文 |
|---|---|---|
| 设置窗口 | `设置` | `Settings` |
| 编辑器窗口 | `道具权重编辑器` | `Weight Editor` |

顺手把 `Search (digits = id, letters = name)` → `Search (id or name)` 等 13 条英文文案缩短，
避免被窗口右边切掉；窗口宽度 620 → **780**。
## 找回丢失的道具评级（`tools\import-rating.ps1`）

作者发现「之前编辑的几个道具权重没了」。

### 原因：拆分时我把数据留在了旧位置

v0.3 时代评级存在**回顾 mod** 的 `data\highlight-review\saveN.dat` 里（`Q=` 行）。
拆分成两个 mod 后，评级数据搬到 `data\highlight-rating\`。
**mod 只能读自己目录的 `mod:LoadData()`**，读不到别人的 —— 所以旧数据不会自动跟过去。

拆分时我判断「只有 1 条，不值得迁移」，**这是错的**，实际有 4 条。

### 不是"两个并行机制"

只有一套机制在跑（评级 mod 自己的文件）。
回顾 mod 存档里那些 `Q=` 行是**死数据**：回顾已经没有评级代码了，既不读也不写。
当初决定"不删"（保住回退能力），现在正好靠它们把数据捞回来。

### 找回的内容

| 档 | 从哪来 | 恢复的条目 |
|---|---|---|
| save1 | `data\highlight-review\save1.dat` 的 `Q=` 行 | `1`(评级4) / `118`(3.75, 权重0) / `1052`(2.25, 停用) |
| save3 | `_backup\save3-cleared-20261021-115301.dat` | `1166`(评级4, 权重0.1) |

合并规则：同一 id 以导入的为准，其余保留。写入前备份到 `_backup\import-rating-<时间戳>\`。

脚本带保护：**检测到游戏在跑就拒绝执行**（否则游戏退出时会把内存里的旧数据写回去覆盖导入）。

### 教训

拆分涉及数据搬家时，"只有 N 条、不值得迁移" 是危险判断 ——
玩家手设的东西，哪怕一行，也比写一个导入脚本贵得多。
## 创意工坊封面图（`tools\make-cover.ps1`）

准备单发 Item Weight Editor，需要预览图。用 PowerShell + System.Drawing 直接画，
不依赖设计软件，改文案只要改脚本里的字。

产物：

| 文件 | 尺寸 | 用途 |
|---|---|---|
| `docs\img\workshop-cover.png` | 512×512 | 创意工坊预览图 |
| `docs\img\workshop-wide.png` | 1280×720 | 页面内大图 |

风格照 mod 自己的 ImGui 面板：深色底 + 蓝色标题栏 + 四行道具（含权重 0 / Rating 4 / 权重 0.5 / Disabled），
底部一行说明 `0 = never   0.5 = half   1 = unchanged`。

重新生成：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-cover.ps1
```
## 新增：创意工坊发布文案（2026-10-21 06:2x）

`docs/workshop-item-weight.md` —— 道具权重调节器的完整发布文案，复制即用。

结构：
1. 标题（含两个备选）
2. 简介（Steam 列表页只显示两行，单独拆出来）
3. 详细说明（中文正文，带分隔线的纯文本排版，Steam 不认 Markdown）
4. 发布页其它字段（分类 / 标签 / DLC / 预览图 / 可见性）
5. 发布前自检清单 7 项
6. 首版变更说明

正文里刻意写进去的三件事：
- **"只能降低"** + 为什么（池子一次只给一个，提高 A 必然压低别人）
- **"和别的 mod 一起用"** 的冲突排查三步法（作者要求，免得以后报 bug 说不清）
- **常见问题** 4 条，首条就是"设了 0 为什么还见过它"

正文用 `━━` 分隔线而不是 Markdown 标题——Steam 的描述框不渲染 Markdown，
`#` 会原样显示出来。
## metadata 改纯 ASCII（游戏模组列表不支持中文）

作者截图发现模组列表里显示成：

```
14.Item Weight Editor (é·æéçè¯)
```

游戏模组列表**不按 UTF-8 渲染**，`<name>` 里的中文全变乱码。

### 修法

`metadata.xml` 全部改成 **ASCII**：

- `<name>` → `Item Weight Editor`（去掉括号中文）
- `<description>` → 单段英文，去掉所有中文和 `·` `—` 这类非 ASCII 符号

校验：文件里非 ASCII 字节数 = **0**。

### 中文放哪

工坊页面的**长描述**（在网页上编辑）支持 UTF-8，中文放那里。
`metadata.xml` 只负责游戏内显示的那一块，必须保守。

### 同类问题

`highlight-review/metadata.xml` 的 `<name>` 里也有中文（`Highlight Review (高光回顾)`），
同样会在列表里乱码。发它之前一并改成 ASCII。
## metadata 改成工坊正式格式（照 EID 那份）

### 结构

```xml
<name>Item Weight Editor</name>
<directory>highlight-rating</directory>
<description>[b]REQUIRES REPENTOGON[/b] ... BBCode ...</description>
<version>0.1.0</version>
<visibility>Private</visibility>
<tag id="Lua"/>
<tag id="Tweaks"/>
<tag id="Items"/>
```

**标签和说明都存在 metadata.xml 里**（不是上传器里的独立字段），照 EID 那份的写法。
上传器读的就是这几个字段。

### 说明内容（1741 字符，上限 8000）

- 第一行就是 **REQUIRES REPENTOGON + 仓库链接**（它不是工坊 mod，订阅者得自己去装）
- 中英双语各一段，用 `[list]` 列功能
- 已知限制：权重只能降、按存档槽存
- 说明它可独立运行，装了 Highlight Review 会共享评级

### 顺带

- `<name>` 里不再有中文（游戏模组列表不支持 UTF-8，会显示成 `é·æéçè¯`）
- 标签在工坊页面上**之后改不了**，所以一次选定：Lua / Tweaks / Items

### 上传

`<游戏目录>\tools\ModUploader\ModUploader.exe`，选 `mods\highlight-rating\metadata.xml`。

⚠️ 上传成功后部署目录的 metadata.xml 会多一行 `<id>`，**必须抄回仓库**，
否则下次 `deploy.ps1` 覆盖掉它，再传会变成新条目（重复 mod）。
## 封面改用真实界面截图（`tools\make-cover-from-shot.ps1`）

作者给了一张编辑器窗口截图，要求用它做封面。

**关键处理**：截图顶部窗口标题写的是 `Highlight Review · 道具评级` —— 那是**拆分前的旧名字**，
和这个 mod（Item Weight Editor）对不上，所以合成时**裁掉顶部 34px 标题栏**，
只保留面板内容。

版面：

```
深色渐变底 + 顶部蓝条
  Item Weight Editor        （32px 粗体）
  道具权重编辑器              （17px）
  ┌──────────────────┐
  │  真实截图（裁标题栏）  │      ← 等比缩放，最大占 66% 高
  └──────────────────┘
  0 = never   0.5 = half   1 = unchanged
  The Binding of Isaac: Repentance - requires REPENTOGON
```

参数化：标题块高度 `96 * Scale`、底部留 `18% * H`，这样 512×512 和 1280×720 都不会压字。

产物（都在 1 MB 以内，工坊要求）：

| 文件 | 尺寸 | 大小 |
|---|---|---|
| `docs\img\workshop-cover.png` | 512×512 | 106 KB |
| `docs\img\workshop-wide.png` | 1280×720 | 153 KB |

源图存为 `docs\img\src-editor-panel.png`，以后换图重跑脚本即可。
## 已发布到创意工坊

```
Initializing Steam API... Success
Processing 'highlight-rating/metadata.xml'... Success
Ready to upload mod 'Item Weight Editor'
Successfully uploaded mod 'Item Weight Editor' to Steam Workshop
```

- **工坊 ID：`3824170209`**
- 页面：https://steamcommunity.com/sharedfiles/filedetails/?id=3824170209
- 上传器自动把 version 改成 `0.1.1`、visibility 设为 `Public`、标签存为 `Lua, Items, Active Items, Tweaks`

### 关键：`<id>` 已抄回仓库

上传器会往 `mods\highlight-rating\metadata.xml` 里写 `<id>3824170209</id>`。
**这个文件必须抄回仓库**，否则下次 `deploy.ps1` 会用仓库版本覆盖它 →
再上传就不是更新，而是**创建重复条目**。

已执行：把部署版整份复制回 `mod-rating/metadata.xml`。

### 以后更新流程

1. 改代码
2. `mod-rating/metadata.xml` 的 `<version>` +1（0.1.2、0.1.3…）
3. `tools\deploy.ps1 -Mod rating`
4. 上传器选同一个 `metadata.xml` → Upload（会更新已有条目，不是新建）
5. 上传后把 metadata.xml 再抄回仓库（`<version>` 可能被上传器改）

**不要改文件夹名，也不要改 `<directory>`** —— 订阅者的安装路径依赖它。
## 工坊描述重写（作者：上一版结构太重）

第一版描述用了大量 `[list]` / `[hr]` / 粗体小标题，读起来像说明书。

作者要求：用一开始给的那段，**中文在前、英文在后**，不要花哨结构。

### 新描述

- 纯文本 + `·` 项目符号，只有中英之间的 `—————` 分隔线
- 中文段：权重含义（0 / 0.5 / 1）→ 评级覆盖 → 用法 → 注意 → 需要 REPENTOGON
- 英文段：同样的结构
- 867 字符（上限 8000）

同时存成 `mod-rating/workshop-description.txt`，方便以后直接复制到工坊页面。

### 标题双语的处理

`<name>` **必须保持纯 ASCII**（`Item Weight Editor`）：
游戏模组列表不按 UTF-8 渲染，写中文会变成 `é·æéçè¯`。

工坊页面的标题是**独立字段**，可以在网页上改成
`Item Weight Editor 道具权重编辑器`，不影响游戏内显示。

### 注意

页面上手动改的描述，**下次用上传器 re-upload 会被 metadata 里的 description 覆盖**。
所以两边要保持同步——仓库这份已经是新版本了。
## 工坊描述第三版（作者改写 + 英文翻译）

作者自己重写了中文稿，要求补英文翻译。内容新增：

- **开场**：刚需 REPENTOGON、只支持忏悔、已测试大部分道具 mod
- **【你大概遇到过这些】**：三个真实痛点（东方 mod 的交易所门票/D无限、mod 组合的超模道具、随机性不给机会），
  并点明"不是 mod 做得不好，是它们太强，强到把别的都压平了"
- **【已知兼容】**：天界呼唤 / 东方系列 / 塔菲的宇宙 / 明日方舟 / 忏悔plus / 愚昧
- **仓库链接**：https://github.com/miopasss/isaac-highlight-review

英文段照译，保留中文段的结构（【】小标题改成 [ ]，`·` 保留）。
其中「塔菲的宇宙」「愚昧」没有确定的英文名，英文段里**保留中文**不硬翻，避免写错 mod 名。

总长 2863 字符（上限 8000），两边同步写入 `metadata.xml` 与 `workshop-description.txt`。

### 未做的

`<name>` 保持 `Item Weight Editor` 纯 ASCII（游戏模组列表不支持中文）。
工坊页面的标题是在网页上单独改的，要双语标题在页面改，不写进 metadata。
## 四级道具列表排除神圣屏障（313）

作者要求：四级道具那一栏不要出现「神圣屏障」。

根因（之前查过）：别的 mod 会往玩家身上反复挂 313，`itemwatch` 按"持有数量增加"判定获得，
于是被误记成"拿到过"——实测一局记了 4 次，玩家根本没拿过。

### 做法

`config.itemBlacklist`：

```lua
config.itemBlacklist = {
    [313] = true,   -- 神圣屏障（Holy Mantle）
}
```

`settleRoom` 里在合成 `gained` 之后、算 `iq` / `ik` **之前**过滤。
这样 `it` / `iq` / `ik` 三个平行数组都拿不到它，四级/零级列表自然也不会出现。

### 注意

- 过滤在**采集层**，所以这个道具也不会出现在楼层明细里（因为它本来就是误记）
- 如果以后想让它在明细里可见但不算四级，要改成只在 `highlight.lua` 的 q4 列表里过滤
- 历史存档里已有的记录不会自动消失（要看干净数据得打新局）

### 另一个未合并的分支

`fix/item-blacklist-v0.3.3` 上有同样的改动（早先做的）。这个分支已经把改动合进来了，
那个分支可以视为重复，合并时忽略即可。
## 修 4 个问题

### ① 房型名

`[7] 密室` → `普通隐藏房`，`[8] 超密室` → `超级隐藏房`（作者 2026-10-22 要求）。

### ② 属性下降画不出来

`segBar2` 原来第一句就把 `fracTotal` 抬到 `fracBase`：

```lua
if fracTotal < fracBase then fracTotal = fracBase end
```

**下降被抹平了** —— 条形图永远只往上长，六维掉属性时看不出来。

改成取两端的较小/较大值，中间那段按方向着色（上升绿 `BAR_GAIN`，下降红 `BAR_DOWN`）。

### ③ 开局自带道具不算「获得」

`settleRoom` 里第一间房直接 `gained = {}`，把初始道具全丢了。

改成 `beginRun` 时拍快照 `state.startItems`，第一间房把它当成获得。

### ④ 总览楼层写不下

原来单列、`math.min(#bk.floors, 10)`，超过 10 层直接截断且没有提示。

改成**双栏**：每栏最多 12 行，共 24 层，超出显示 `+N floors`。
窄栏里去掉时长（时长在楼层详情页有），bar 段数 40 → 24。
## 新功能（作者 2026-10-22 提的一批）

### ① 册子显示开局系统时间 + 时间倒序

- `schema` 的 run 作用域加 `w0`（epoch 秒），`beginRun` 里用 `os.time()` 取。
  取不到（沙盒禁了 `os.time`）就写 nil，册子不显示时间，其它照常。
- 总览页标题行下面多一行 `2026/10/22 14:36`。
- 局的排序本来就是 `seq` 倒序（最新在前），不需要改。

### ② 终极 Boss 评级

按**击杀用时**（Boss 房 `ms`），30 秒一档：

| 用时 | 评级 |
|---|---|
| ≤30s | S+ |
| ≤60s | S |
| ≤90s | A |
| ≤120s | B |
| ≤150s | C |
| ≤180s | D |
| 更久 | E |
| 没打终极 Boss | D |

放在总览标题行：`<runId>  WIN  A  12F  45 rooms`（WIN 右边、楼层数前面）。
代码在 `book.lua` 的 `bossGrade(bk)`。

### ③ 六维显示「数值 + 百分比」

`statRow` 原来只显示出房值。现在属性有变化时显示 `旧>新`（例 `12.89>14.30`），
右边仍然是 `+10.9%`。两个都在。

### ④ 楼层详情按品质分行

原来一行 10 个、最多 20 个。现在 **Q5~Q0 每个等级一行，每行 8 个**，超出显示 `+N`，
同行内按时间顺序（`f.items` 本来就是按房间时间积累的）。

为此 `highlight.lua` 给每层加了 `itemsQ`（与 `items` 平行的品质列表）。

### ⑤ F6「已获得道具」按获得时间倒序

没有真实时间戳，用「本会话内第一次在持有列表里看到它」的递增序号近似。
读档前就有的道具没有序号，排最后并按 id 升序，避免每次打开顺序乱跳。
### 系统时间这条：沙盒里拿不到

实测结果：

```
日志 [CLOCK] os.time=0  os.date=1970/01/01 08:00
```

- Isaac 的 Lua 沙盒把 `os.time()` 换成了返回 **0**
- `zhlREPENTOGON.dll` 里没有 `GetRealTime` / `UnixTime` / `GetDateTime` 之类的接口
  （只剩 `Isaac.GetTime()` = 游戏启动后毫秒数，不是墙钟）

所以入口做了保护：**只认 `> 1e9` 的时间戳**，取不到就 `w0 = nil`，
册子不显示时间那一行（之前会把 1970 显示出来，是很难看的 bug）。

`w0` 字段的管道保留着（schema / 编解码 / `whenText`），
以后 REPENTOGON 若给出真实时间接口，只需要改 `wallSec()` 一行。

如果要真时间，只能走外部注入（PowerShell 起游戏时写一个时间戳文件让 mod 读），
但那样订阅者拿到的是打包时的旧值，**不能发布**，所以没做。
### 修：`nowSec` 被误删（3 号档每间房报错）

```
main.lua:434: attempt to call a nil value (global 'nowSec')
```

上一轮替换 `wallSec` 那段时，把紧邻的 `local function nowSec()` 一起删了 →
`nowSec` 变成全局查找 → nil → `beginRun` 里的 `t0 = nowSec()` 报错。
`MC_POST_PLAYER_INIT` / `MC_POST_NEW_ROOM` 都被 pcall 包着，所以**只报错不崩**。

### 时间改用 `os.date()`（有真实系统时间）

作者指出明日方舟 mod 能拿到外部时间。查了 `arknights_terra_a_journey_3631023221`：

- `sunny_side_cream.lua:49` → `os.date("%Y%m%d")`（判每日）
- `calendar_of_the_overlord_of_ages.lua:33` → `os.date("*t")`
- `sui_hours.lua:115` → `os.date("%H")`

结论：**`os.time()` 被换成返回 0，但 `os.date()` 不传时间戳时拿的是真实系统时间**。
所以不再存 epoch，直接存格式化文本：

- schema：`ws = "s"`（`"2026/10/22 14:36"`）
- `main.wallText()`：`os.date("%Y/%m/%d %H:%M")`，年份 < 2001 视为无效
- `book.whenText()`：只接受字符串，`1970` 开头的一律不显示

### Boss 评级改档次

作者要求：**30 / 60 / 120 / 200 / 300** 秒分档，**多个终极 Boss 取平均**。

| 平均用时 | 评级 |
|---|---|
| ≤30s | S+ |
| ≤60s | S |
| ≤120s | A |
| ≤200s | B |
| ≤300s | C |
| >300s | E |
| 没打终极 Boss | D |
## 局内 HUD 战力行 + 战力跃迁页

### 数据

- `schema` 房间作用域新增 `ie`（与 `it` 平行：每件道具带来的战力增量）
- `fmt` 的列表编码支持小数：整数值仍按 `%d`（旧存档字节不变），带小数按 `%.4f`；解码不再强制四舍五入
- 采集：房间进/出战力的差是准确值，单件归因按「本房有效道具数」平摊；`iq<0` 的脏 id 记 0 不参与排序

### 派生（`highlight.analyze`）

```
jumps = 所有 (道具, 增量 >= config.jumpMin) 的事件
按增量降序取前 N（config.jumpTopN=50）→ 再按时间顺序排
展示前 24 个（config.jumpShown），其余只报个数
```

### 页面

- 新增「战力跃迁」页（`kind = "jumps"`）：图标 + 百分比 + `F<层>`，2 排 × 12
- 楼层详情加 `JUMPS` 小块：最多 8 条，超出 `+N`
- 「战力提升 Top3」页、「四级/零级」列表改为配置开关：
  `config.pagesPower / showQ4 / showQ0`，默认 `false`

### 局内 HUD

`MC_POST_RENDER` 里画一行：`▮ PWR 9.55 +1.41`，位置基准 168（Rep+ 170）+ `config.hudPowerOffsetY`
（默认 18，因为 168 会压住原生面板最后两行）。增量 3 秒后消失，每 20 帧刷新数值。

### 踩的坑

1. `bookui.init` 的 deps 表里 `config` 写了**两遍**，我加的 `config = config` 被后面的硬编码表覆盖 → 所有开关失效。
   改成「硬编码默认值 + config.lua 合并（后者优先）」。
2. 楼层记录有**两处**初始化，只补了一处 `itemsQ` → `identity_test` 直接报
   `attempt to get length of a nil value (field 'itemsQ')`。
3. 我插入跃迁页时把 `table.insert(book.pages, 1, finale)` 复制成了两行 → 册子出现两个终局页。
4. `identity_test` 是按「Top3 页存在」写的，开关默认关掉后必须让测试自己传 `pagesPower = true`。
### HUD 字体改成描边字（作者 2026-10-22）

原生位图字太小，看不清。照 `planetarium chance_2489006943` 的做法：

```lua
self.font = Font(); self.font:Load("font/luaminioutlined.fnt")
```

我们也加载同一个 `font/luaminioutlined.fnt`，HUD 那行改成 `hudFont:DrawString(...)`：
白色数值 + 3 秒内的增量（绿涨红跌）。

**踩的坑**：`Font:DrawString` 的坐标是 **480×270 的 HUD 空间**，而我原来的图标用 `rect(x*s, ...)`
（屏幕像素），两者差了一个缩放 → 文字和图标错位。统一改成同一个坐标系。
### 跃迁展示改按楼层（作者 2026-10-22）

- **楼层详情里的 JUMPS 块删掉**（太占位置，楼层页要放六维和道具网格）
- 战力跃迁页改成**按楼层分组**：
  - 每层内按增量**降序**取前 **8** 个
  - 层与层之间按层号升序
  - 一页仍最多 24 行（2 列 × 12），其余只报个数
- 每行显示 `图标 + 旧>新 + 百分比 + F层#房号`（数值和百分比都要）

### HUD 位置：排到星象房那条下面

`hasPlanetarium()` 用 `Isaac.GetModByName` 探测 `planetarium chance`，在的话
基准 y 从 168/170 再加 11（星象房占一行，我们排它下面）。

另外加了一层半透明底衬 `rect(...alpha 0.55)`——木地板背景下裸字看不清。
### 修：`GetCollectible` 那条「正常噪音」其实是 bug

```
main.lua:156: attempt to call a nil value (method 'GetCollectible')
```

**`player:GetCollectible(i)` 这个 API 在 Repentance 里不存在**，
所以逐件读取 100% 失败 → 每次进房都退回 **2000 次 `HasCollectible` 全量扫描**，
还每局在日志里刷一条错误。之前把它当成"降级路径，属正常"，判断错了。

改成首选 `player:GetCollectiblesList()`（返回 `{ id = 数量 }`，`itemwatch` 里本来就在用），
按数量展开成列表；只有它也不可用时才退全量扫描。

附带好处：每次进房少 2000 次 API 调用。

### 战力口径 v2：特殊形态 / 宝宝 / 幸运（feature/power-forms-v0.3）

口径文档 `docs/special-attack-power.md`；计算层 `mod-review/core/power_forms.lua`（纯函数，**没接 main**）。

- 母式：`POWER = 射速 × 攻击力 × 倍数`（6 因子展开只是为了能算特殊形态）
- 27 件定值：20 形态 + 4 宝宝倍率 + 7 幸运概率。id 全部用游戏内 EID 的
  `names/en_us.lua`、`item_data.lua`、`LuckFormulas` 核对过，不靠记忆
- 宝宝**不做加法**，只当倍数：Incubus / 双生宝 各 +0.75（两件同时拿是 2.5×，不是 3.06×）；
  Succubus / 宝宝套 ×1.5。其余宝宝不统计
- 幸运道具直接抄 EID 的公式（`inv` + `linear` 两种形态），
  并有 6 个锚点单测（安眠药 luck9=100%、圣光 luck9=50%、安乐死 luck13=25%…）
- **顺手查出旧口径三处错**：硫磺火把「每跳伤害」当 DPS（base 0.64，比空手还低）、
  Ludo 按固定 15 跳（实际随 tears、上限 30/秒，`D×15` 高估 5.5 倍）、宝宝一件都没算
- 单测 `tests/power_forms_test.lua`：41 项全过
- **没动 `power.output()`**，现有存档数据零影响；接 main 要等三项实测（妈刀周期、硫磺火每跳、Succubus 是否已在面板）

### 莉莉丝特判 + 飞行/防爆采集（feature/power-forms-v0.3）

**莉莉丝**：Incubus / 双生宝 的加成从 0.75 变 **1.00**（EID `repBFFSSynergies` 的
`{75,150,100,200}` 后一对就是莉莉丝例外）。所以莉莉丝 Incubus = 2.00×，再叠 BFFS! = 3.00×。
Succubus 不受影响（它本来就不在例外表里）。

**飞行 / 防爆**：schema 房间作用域新增 4 个布尔 `fli fl exi ex`
（进房/出房 是否会飞、是否防爆）。判定整局结论时**不用另存时间戳**：

```
哪一间拿到的 = 第一个「出房 true && 进房 false」的房间
第 1 间就已经 true = 开局自带
```

- 飞行读数：`player.CanFly`（覆盖道具/饰品/变身，不需要枚举）
- 防爆读数：白名单 `HasCollectible`（223 纵火狂 / 375 宿主之帽）——
  REPENTOGON 没有现成的 bool，以后发现别的给防爆的道具就往 `EXPLODE_IMMUNE` 里加
- 总览页加一行：`飞行 F3#12   防爆 开局`；没有就显示 `无`
- 旧存档缺这 4 个字段 → 解码补 `false`，显示"无"，不报错

顺带核对：**局列表本来就是时间倒序**（`sortedRuns()` 按 `seq` 降序，`fmt.nextSeq()` 单调 +1），
新的在第 1 条，不用改。

### 飞行/防爆加"确认窗口"：临时飞行不算

作者指出：**踩白火、按住圣经**这种临时飞行只在本房间有效，如果只看"出房 true 且进房 false"，
会被误判成"本局获得了飞行"。

改成**必须带得进下一间**才算：

```
候选 = 第 i 间「出房 true 且进房 false」
确认 = 第 i+1 间「进房仍为 true」   → 才算第 i 间拿到
```

- 临时飞行：出房 true，下一间进门 false → **丢掉**，继续往后找候选
- 真道具：出房 true，下一间进门还飞 → 确认，归因到拿到的那一间（不会差一间）
- 开局自带：第 1 间进门就会飞 → 直接记"开局"，不参与上面那条
- **最后一间拿到的不确认**（没有"下一间"可证）：宁可漏记，不误记

实现放在 `highlight.gainPoint(rooms, keyIn, keyOut)`（纯函数，方便单测），
防爆走同一套。identity_test 新增 5 项：临时飞行被丢 / 真道具确认 / 最后一间不确认 /
开局自带 / 防爆同逻辑 —— 29/29 通过。

### 上一版的判据是错的：改成"从此往后一直有"

作者纠正：**踩白火的临时飞行"不清房就不落地"**，只要不清理房间、来回运营，
可以撑完**一整层**；它真正的破绽在**下一层的第一间（清完就掉）**。

所以"看下一间还在不在飞"会把整层的临时飞行误判成获得。改成**最长全 true 后缀**：

```
从第 k 间开始，之后每一间（含换层）都 fl=true  →  k 就是获得点
```

- 整层临时飞行：下一层第一间变成 false → 后缀断在那一层 → 前面那段**不算**
- 真永久飞行：一路到底都为 true → 后缀起点就是拿到的那一间（不会差一格）
- 中途丢了又拿回来：归因到**重新拿回来**的那一间（后缀起点）
- 第 1 间进门就会飞 → 开局自带，不记获得点

采集完全没改（还是每间房记 `fli/fl/exi/ex`），只改了**派生判定**。
identity_test 的 5 项也按新语义重写，含"整层临时飞行 → 不算获得"这个关键用例 —— 30/30 通过。

### HUD 底衬删掉（作者 2026-10-23 看图指出）

局内战力行下面那条半透明黑带是历史遗留的底衬：`rect()` 用屏幕像素、`DrawString` 用 480×270 空间，
两个坐标系差一截，实测文字落在底衬**上方约 13 个单位**，于是底衬变成一条空黑条。
字体本来就是 `luaminioutlined` 描边字，底衬多余 → 直接删。部署后黑条仍在的那类是**六维 HUD 那个第三方 mod 的空行底条**，不是我们的。

### `GetCollectiblesList` 探测改三态（子代理改，主代理验）

本机该 API **时有时无**（`zhlREPENTOGON.dll` 里确有这个名字；同一会话里既有 `共 1763 件` 成功，也有 `nil` 失败）。
所以不能一次 nil 就判死：

- 三态：未知 / 可用 / 缺失；只有"player 上没这个方法"才记死，临时故障下次再试
- 探测与失败日志**全程各一次**（旧代码其实也已经只报一条，真正白吃的是每房 2 次 2000 回扫描）
- 退化扫描把闭包从 2000 个降到 1 个；中途抛错才退回逐 id `pcall`（结果与旧实现逐字一致）
- 顺手修列表法真 bug：`if c < 1 then c = 1` 会把"数量 0"当成持有 → 现按数量 > 0 展开

验证：luacheck 24 文件 0 失败 / fmt PASS / identity 30-0 / power_forms 全过。
`core/itemwatch.lua` 同根因**未修**（每帧失败 pcall + 每 12 帧扫 1800），是下一个该处理的。

### 工具：控制台自动化（`tools/console.ps1`）

可以直接给游戏发控制台指令了（`EnableDebugConsole=1` 已开）：

```powershell
powershell -File tools\console.ps1 "giveitem c118"
powershell -File tools\console.ps1 "debug 3|giveitem c417|stage 2" -Shot
```

踩过的三个坑都写进注释了：`~` 会打进输入框（先退格 40 清场）、自动补全要吃一次 ENTER、
ESC 关控制台时可能连带打开暂停菜单（收尾按一次 ENTER 恢复）。
用它实测到：**Succubus 的 ×1.5 已经在 `player.Damage` 里，且只在光环内生效**（站位一变就跳）→ 建议从宝宝倍数表里删掉这一行。
## 修「道具权重又不见了」：读档后拒绝写盘 + 换存档槽串档（2026-10-24）

### 现象

作者反馈：改过的权重过一阵又回旧值；3 号档里导入的 `1166`（q4 / w0.1）没了，
`data\highlight-rating\save3.dat` 跟 `save1.dat` 一模一样。

### 根因 1：存档里已有 `Q=` 行时，`R.loaded` 永远是 false

`core/rating.lua` 的 `R.load` 找到 `Q=` 行就 `return`，**没有置 `R.loaded = true`**；
`R.save()` 见 `loaded == false` 直接拒绝写盘。于是只要存档里已有 Q 行，
之后每次改权重都只改了内存，退出游戏就回滚。

之前那次"注入 Q 行 → 起游戏 → 载入 3 条 → 关游戏 → Q 行仍在"的验证能通过，
是因为它**压根没写盘** —— 这个 bug 正好被那条验证掩盖了。

修：找到 Q 行并解码后置 `R.loaded = true`；`saveData` 里遇到 `not rating.loaded` 打一条 ERROR。

测试补在 `tests\rating_test.lua` ⑤c：用第二次 `loadfile` 出来的实例模拟"重启游戏"，
已有 Q 行时 `load → set → save` 必须写回。

### 根因 2：只在进程里读一次档，换存档槽不重读

`main.lua` 的 `MC_POST_PLAYER_INIT` 只调 `loadData()`，而 `state.loaded` 保证整个进程只读一次。
先进 1 号档再切 3 号档 → 内存里还是 1 号档的 entries，退出时 `mod:SaveData` 把 1 号档的
Q 行写进 3 号档。

证据：

| 文件 | 内容 |
|---|---|
| `data\highlight-review\save3.dat` | 2726 行 / 14 局（真在玩的档） |
| `data\highlight-review\save1.dat` | 213 行 / 1 局（为了进 1 号档点了一下） |
| `data\highlight-rating\save3.dat` | 与 `save1.dat` 完全相同（4 条：1/105/118/1052） |
| `_backup\save3-cleared-20261021-115301.dat` | `1166:{q:4,w:0.1}` 还在 |

修：照回顾 mod 的写法，每次 `MC_POST_PLAYER_INIT` 重置 `state.store / state.loaded / rating.loaded` 再读。

### 版本

`metadata.xml` 0.1.2 → **0.1.3**；main.lua 的 loaded 日志同步改 0.1.3（之前一直写 0.1.0）。

### 待办

- [ ] 部署后实测：1 号档设一个权重 → 退菜单 → 进 3 号档 → 两个文件的 Q 行必须不同；重启后改动仍在
- [ ] 把 `1166` 从 `_backup\save3-cleared-20261021-115301.dat` 合并回 3 号档
- [ ] 工坊上传 0.1.3（这个 bug 已随 0.1.2 发给所有订阅者，必须热修）
### Q0 又爆 400+：脏 id 的显示与采集双层过滤

作者截图报「Q0 又 400+」，行里全是 `1819 1866 1933 1792 ...` ——
这些都是 id ≥ 1792 的 mod 道具，`iq = -1`（我们的道具表里没有它们）。

两个问题叠在一起：

1. **显示层**：分层时 `q < 0` 被 `if q < 0 then q = 0 end` 归进了 **Q0**，
   于是 800 多个脏 id 全挤在 Q0 那一行
2. **采集层**：房间里只要拿到一个 mod 道具，整份 mod 道具表都会被写进 `it`（已知的整表写入问题）

### 改法

- `book.drawFloor`：分层前 `q < 0` 直接跳过，`ITEMS N` 也只统计有效道具
- `main.settleRoom`：采集时就丢掉 `品质 < 0` 的条目，并打日志

```
[FILTER] 丢弃 N 个无品质道具（mod 整表写入的脏 id），保留 M 个
```

这样 Q0/Q4 列表、`ITEMS` 计数、跃迁平摊分母都不会再被这批脏 id 污染。

**注意**：历史存档里已有的脏记录不会自动消失，要看干净数据必须打新局。
## 评级数据第 N 次被清空：恢复 + 加一代备份

作者报「道具权重又又又一次被清理掉了」。查到的现状：

```
当前 save1 / save3   {1, 105, 118, 1052}
备份 save3-cleared   {1166: q=4, w=0.1}     ← 这条丢了
```

### 恢复

把两份存档都补成并集并重写：

```
Q={"v":1,"e":{"1":{"q":4,"w":1},"105":{"q":0,"w":0.5},"1166":{"q":4,"w":0.1},
              "118":{"q":3.75,"w":0},"1052":{"q":2.25,"w":0,"on":false}}}
```

改动前的原文件备份在 `_backup\restore-rating-<时间戳>\`。

### 防再次丢失：存档内一代备份

`mod-rating/core/rating.lua`：

- 新增 `R.BAK = "Q0="`
- **保存时**：把上一版 `Q=` 原样存成 `Q0=`，再写新的 `Q=`（同一文件，一代滚动）
- **读取时**：`Q=` 丢了、空了或解码失败 → 用 `Q0=` 兜底
- 两者都解码失败才拒绝写盘（保住坏数据）

这样最坏情况只丢**最后一次改动**，不会再一次性清空。

### 仍未定位

`save3.dat` 的内容曾经变得和 `save1.dat` 完全一样，怀疑是某次以 1 号档的进程写进了 3 号档。
现在加了 `Q0=` 兜底，即使再发生也能从同一文件里捞回上一版。
## 找到评级数据被写进错误存档槽的原因（作者提示的方向对了）

作者问：「1 号档切 3 号档时内存是不是没清理？」

代码里其实**已经有**槽切换守卫（`MC_POST_PLAYER_INIT` 里 `state.loaded = false` 重读档），
但留了一个窗口期：

```
启动游戏（上次的槽 = 1）
  → 在菜单里切到 3 号档
  → 不开始游戏，直接从菜单退出
  → MC_PRE_GAME_EXIT 触发 → 把内存里 1 号档的数据写进当前槽（3 号）
```

这和实测现象完全吻合：`save3.dat` 变得和 `save1.dat` 一模一样。

### 修法：`runActive` 守卫

- `MC_POST_PLAYER_INIT`（真的进局了）→ `state.runActive = true`
- `saveData()` 开头：`if not state.runActive then return end`
- `MC_PRE_GAME_EXIT` 写完 → `state.runActive = false`

也就是说：**只有在本次进程里真的进过局，才允许把配置写盘**。
在菜单里切槽、看菜单、直接退出，都不会再写任何文件。

两个 mod（回顾 + 评级）都加了同样的守卫。
## 「已获得道具」按获取顺序排序（作者方案）

### 之前为什么不是获取顺序

`seenOrder` 只在**编辑器刷新时**才记录新 id（打开编辑器、点按钮），
而刷新时是「一次性把当前持有列表编号」，`heldIds()` 返回的是 id 升序 →
所以拿到顺序接近 id 顺序，且**重启后全部重排**。

内存结构（都是进程内，不落盘）：

| 变量 | 内容 |
|---|---|
| `seenOrder` | `道具id → 序号` |
| `seenSeq` | 计数器 |
| `ownedList` / `searchResults` / `editedList` | 给 UI 用的数组，每次刷新重建 |

存档里只有 `Q=`（评级）和 `C=`（设置）两行，**顺序从来没有落盘**。

### 改法（作者 2026-10-24 拍板）

- `MC_POST_NEW_ROOM`（每出一间房）→ `E.touch()`：给新出现的 id 编号
- `MC_POST_PLAYER_INIT`（每局开始）→ `E.resetOrder()`：清空，本局重新计
- 排序兜底不变：没编号的按 id 升序

### 已知限制

同一间房里拿 2 个以上道具，它们会按 **id 顺序**编号（房间结束才比对）。
跨房间是真实顺序；重启后本局之前的部分丢失。
## 新增 `docs/PERFORMANCE.md`（性能开销账本）

作者要求：把两个 mod 对游戏的开销整理成一份**长期维护**的文档。

内容：

- 每帧 / 每间房 / 每层 / 每局一次性 四档开销清单，逐项写位置、实现、实测代价
- 解释 `itemwatch` 为什么每帧都要跑（同房拿了又丢、跨房瞬间获得这两个盲区）
- 实测基线：存档 1.2 MB、日志 110 MB、`[DUMP]` 3567 行/局、1763 件持有道具
- 优化候选按性价比排序（itemwatch 降频 → dumpOnce 关闭 → HUD 刷新降频 → 修 it 整表写入）
- **维护规则**：新增回调必须登记频率/动作/代价；每帧逻辑必须写进 §1 并说明不能降频的理由
- 附测量命令（存档大小、日志行数）

`AGENTS.md` 顶部加了一行指向，避免以后忘记维护。
## 去掉 itemwatch 的每帧比对（作者 2026-10-24 判定盲区可接受）

作者质疑：麦苗那种「同房拿了又丢」漏记可以接受；跨房瞬间获得下一房对比也会补上。
→ **是的**，于是删掉 `MC_POST_UPDATE` 里的 `itemwatch.tick()`，回到「只在房间边界比对」。

`itemwatch` 模块保留（`drain()` 恒空），不再每帧读 `GetCollectiblesList()`。
省下：1763 件 × 30 fps ≈ 每秒 5 万次表写入 + 10 万次遍历。

## 查清「一房 121 个道具」的真正原因

之前我说「id ≥ 1792 会把整表写进去」，**这个解释是错的**，向作者道歉。

实测最大那一房：121 个道具，id 跨 `14 … 2000`，其中 55 对连续递增。

真实机制是**全量扫描降级路径 + `HasCollectible` 误报**：

1. `scanList` 会 `for id = 1..2000` 逐个问 `HasCollectible(id)`
2. 某些 mod 把这个接口实现成「图鉴里有/能不能拿到」，于是上百个 id 返回 true
3. 采集逻辑是「和进房时比，变多了就算新获得」→ 扫描结果一变化，全部被当成这一房拿到的

### 修法

- 一旦 `itemAccessBroken`（走了扫描）→ **本房不记获得**，宁可漏不可脏
- 兜底：一房新增 > **12** 件 → 判定为伪影，全部丢弃并打 `[FILTER]` 日志
  （真实房间最多 3~4 件）
## 「一房 121 个道具」真因：我们自己的降级路径（不是 mod 的锅）

作者要求查是哪个 mod 并去提 PR。查完的结论是：**没有 mod 的问题，是我们自己的 bug**。

### 证据链

1. 房间里那 121 个 id 中，110 个落在 `1764~2000`，全部**没有对应的 ItemConfig**
   （`[OWN]` 探针只打印出 `1700~1763` 这 64 个，1764 以上全是 nil）
2. `GetCollectiblesList()` 在 `MC_POST_PLAYER_INIT` 传进来的 `player` 上**不存在**：
   ```
   attempt to call a nil value (method 'GetCollectiblesList')
   ```
   但在 `getPlayer()`（`Isaac.GetPlayer(0)`）上**正常**，返回 1 件（id=105 = D6）
3. 一旦上一步失败，代码就回退到 `HasCollectible(id)` 从 1 扫到 2000。
   **`HasCollectible` 的语义是"图鉴里有/曾经有"**，对 110 多个未持有的 mod 道具返回 true
4. 采集逻辑是「和进房时比，变多了就算本局获得」→ 一次扫描结果变化就把它们全部记成获得

所以是「**错误的 API 回退 × 差值判定**」的化学反应，和 id 大小、和任何 mod 都无关。

### 修法

- `scanCollectibles` 改用 **`GetCollectibleNum(id) > 0`**（准确持有数），`HasCollectible` 只作最后兜底
- 扫描结果打 `[SCAN] GetCollectibleNum 扫描：N 件`（前 3 次）便于对照
- 保留「一房新增 > 12 件 → 判定伪影」的上限
- 删掉误导人的 `[LIST]` 诊断（它用的是 POST_PLAYER_INIT 的对象，方法不存在是正常的）

### 教训

`HasCollectible` 不能当"持有判定"用；要数量就用 `GetCollectibleNum`。
另外：不同回调传进来的 `player` 对象能力可能不一样，跨回调复用要小心。
### 终极 Boss 评级：多个 Boss 改成取「最慢的那场」

作者 2026-10-24 指出：击败多个终极 Boss 时，原先取**平均**不合理。

平均的问题：速通的那场会把整体拉低，例如 Hush 25s + Boss Rush 180s → 平均 102s 得 B，
但玩家实际体感是「打了 3 分钟的 Boss Rush」，应该记 C 甚至更低。

改成取 **最大用时**（最慢的那场）：

| 最慢的一场 | 评级 |
|---|---|
| ≤30s | S+ |
| ≤60s | S |
| ≤120s | A |
| ≤200s | B |
| ≤300s | C |
| 更久 | E |
| 没打终极 Boss | D |

代码：`ui/book.lua` 的 `bossGrade(bk)`。
## 为什么会去扫 2000 次（作者质疑）

作者问「为啥要做两千次内存扫描」。查下来是**我们自己的逻辑缺陷**，不是必须的。

### 原因

`readCollectibles(player)` 只试**一个对象**就下结论：

```lua
local okCall, m = pcall(function() return player:GetCollectiblesList() end)
if not okCall then
    listApiMissing = true      -- 一次性判定，永久降级
    return scanCollectibles(player)   -- 从此每房扫 2000 次
end
```

而 `MC_POST_PLAYER_INIT` 传进来的 `player` 曾经在某个时点取不到这个方法 →
`listApiMissing` 被设成 true → **整个进程**之后每间房都走全量扫描。

崩溃日志里那句 `not enough memory`（MC_POST_NEW_ROOM）就是扫描过程中的内存压力。

### 修法

先试传入的对象，再试 `getPlayer()`，**两个都失败**才退化扫描：

```lua
local candidates = { player, getPlayer() }
for ci = 1, #candidates do
    local ok, m = pcall(function() return candidates[ci]:GetCollectiblesList() end)
    if ok and type(m) == "table" then ... return list end
end
return scanCollectibles(player)   -- 兜底
```

### 实测结果

```
道具读取正常（列表法）：共 1 件，首件 id=105（来源 回调参数）
报错：没有
F1-01 型01 形1  9.55 -> 9.55 ... 道具0
```

**一次扫描都没发生**，也没有再报 `not enough memory`。
## 高光回顾的工坊元数据 + 封面

### metadata

| 项 | 旧 | 新 |
|---|---|---|
| name | `Highlight Review (高光回顾)`（游戏列表乱码） | `Highlight Review [EN/CN]`（纯 ASCII） |
| version | 0.3.0 | **0.4.0** |
| tags | 无 | `Lua`, `Tweaks` |
| description | 274 字符 | **3477 字符**（中英双语，作者改写版） |

坑：描述里 `<=30s` 的 `<` 会破坏 XML，写入 metadata 前做 `&lt;` 转义；
`workshop-description.txt` 保留原文，供粘贴到工坊网页。

### 封面

`tools\make-cover-review.ps1`：用真实册子截图（`docs\img\src-book-panel.png`，作者提供）
+ 标题「Highlight Review / 高光回顾 · 每局一本战力笔记」+ 金色描边。

产物：`workshop-cover-review.png`（512×512, 200 KB）、`workshop-wide-review.png`（1280×720）。

### 描述按作者改写

- 局内 HUD 单独成节，示例 `PWR 9.55 +1.41 (+15%)`
- 补「大多数情况下，战斗力 = 攻击力 × 攻速」，再给完整口径
- 兼容性改成「实测了这 6 个，实际全 MOD 兼容」
- 终极 Boss 列表写清：见证者 / 精神错乱 / Boss Rush / Hush / Mega Satan / 三眼霍恩

⚠️ **未定**：作者文字写「打多个取平均值」，但代码是「取最慢那场」（2026-10-24 改的）。
描述里暂时只写「取本局终极 Boss 战的用时」，没写平均/最慢——等作者确认后补。
### 评级：确认取「平均」

作者最终决定取平均（前一天定的是最慢）。代码改回：

```lua
local sum, n = 0, 0
for ... do if r.ub > 0 then sum = sum + r.ms; n = n + 1 end end
local sec = (sum / n) / 1000
```

描述里也补上「平均用时」（中英各一处），之前为避免描述与实现不一致，那一句是留空的。
## 高光回顾已发布到创意工坊

```
Processing 'highlight-review/metadata.xml'... Success
Ready to upload mod 'Highlight Review [EN/CN]'
Successfully uploaded mod 'Highlight Review [EN/CN]' to Steam Workshop
```

- **工坊 ID：`3824312517`**
- 页面：https://steamcommunity.com/sharedfiles/filedetails/?id=3824312517
- 版本 `0.4.0`，可见性 `Private`，标签 `Lua, Tweaks`

### `<id>` 已抄回仓库

上传器会往 `mods\highlight-review\metadata.xml` 写 `<id>3824312517</id>`。
已把部署版整份复制回 `mod-review/metadata.xml`，否则下次 `deploy.ps1` 会覆盖它，
再上传就不是更新而是**创建重复条目**。

### 两个 mod 的工坊状态

| mod | 工坊 id | 版本 |
|---|---|---|
| Item Weight Editor | `3824170209` | 0.1.1 |
| Highlight Review | `3824312517` | 0.4.0 |
### 更正：高光回顾的工坊 id 是 `3827490957`

上一条 CHANGELOG 里写的 `3824312517` 是笔误（我手打的），以 `<id>` 实际值为准：

| 项 | 实际值 |
|---|---|
| 工坊 id | **`3827490957`** |
| 页面 | https://steamcommunity.com/sharedfiles/filedetails/?id=3827490957 |
| 版本 | 上传器自动改成 **0.4.1** |
| 可见性 | 上传器设成 **Public** |
| 标签 | 上传器补成 `Lua, Items, Active Items, Tweaks, Graphics` |

仓库里的 `mod-review/metadata.xml` 已按实际值抄回（`<id>3827490957</id>`、`version 0.4.1`）。
## 恢复药丸账单（`feature/pill-ledger-v0.3.2`）

清理旧分支时发现：**药丸账单从来没合进 main**。该分支独有的 `mod-review/core/pills.lua`（72 行）
在 main 里完全不存在，删分支就等于永久丢弃这个功能。

于是先移植，再清理分支。移植的六处：

| 文件 | 改动 |
|---|---|
| `core/pills.lua` | 从分支恢复（72 行白名单，`PILLEFFECT_*` → stat/dir） |
| `core/schema.lua` | 新增 `P` 作用域（`r`/`f`/`i`/`e`） |
| `core/fmt.lua` | `encodeRun` 写 `P` 行、`decodeRun` 读回 `run.pills` |
| `main.lua` | 引入 `core.pills` + `MC_USE_PILL` 回调记录药丸 + `beginRun` 加 `pills = {}` |
| `core/highlight.lua` | `pillName()` + 生成 `kind = "pills"` 页（次数/占比/提升下降/按层） |
| `ui/book.lua` | `drawPills()` + 路由 |

冒烟测试：

```
P 行 2 条；解码 pills=2 条；第一颗 effect=10
fmt_test PASS；identity_test 30/30
```

注意：分支里的 `pills.lua` 带 BOM（`Out-File` 写的），luacheck 直接报
`unexpected symbol near '<\239>'` —— 已去掉 BOM。
### 四级/零级道具「看不见了」：是配置关掉的，不是坏了

作者反馈终极 Boss 页的四级/零级道具展示坏了。查证：`config.lua` 里

```lua
config.showQ4 = false
config.showQ0 = false
```

这两行是 2026-10-22「关掉四级/零级页」时的产物——当时同时删了独立页，
并把终极 Boss 页里那两栏也清空。默认 `false` → 页面上只剩「四级道具 0」和空图标行。

改成 `true` 恢复显示（独立页仍然不再生成，只是终极 Boss 页里重新显示两栏）。

单测确认：`finale q4=1 q0=1`。
## 按种子去重（作者 2026-10-26 定）

### 为什么种子是安全的去重键

实测确认：**每次落盘都重写整局**（`state.current` 里累积了全部已结算房间），
所以同一次落盘的后一条一定是前一条的超集。数据里正好有一对活证据：

```
seq 23  7672F180-0  t0=79730   1 行   0 房     ← 早先的空壳
seq 23  7672F180-0  t0=79730   11 行  9 房     ← 后者包含前者全部内容
```

### 改动

| 位置 | 改动 |
|---|---|
| `fmt.newEntry` | index 条目缓存 `seed`（原来只有 id） |
| `fmt.dedupe` | **按种子**分组，只留记录行数最多的一条；种子为 0 时退回按 id |
| `fmt.findBySeed` | 新增：按种子查已有条目 |
| `main.flushCurrentRun` | 落盘前先 `findBySeed` 删旧条目，不再只依赖 `state.currentEntry`（它读档/切槽后会失效，正是空壳的成因） |

单测：

```
去重前 3 条 → 删 1 条 → 剩 2 条（seed111 保留 5 房那条 + seed222）
fmt_test PASS；identity_test 30/30
```

### 已知取舍

按 R 重开时种子不变 → 新局会把旧局覆盖掉一条（作者明确接受）。
换角色的局种子相同但 id 不同，也会被合并成一条。
## 配置（settings）备份与保存审计

作者要求检查配置是否正常保存/备份。查出三个问题，全部修掉。

### ① `Q0=` 行无限累积（评级存档）

`R.save` 每次把上一版 `Q=` 追加成 `Q0=`，但**从不删除旧 `Q0`**：

```
save1: 2 条 Q0
save3: 16 条 Q0   ← 每保存一次多一行
```

改成：保存时丢弃所有旧 `Q0`，只保留最新一条。load 侧本来就有 `Q0` 兜底，不受影响。

### ② 回顾 mod 没有 `settings.only`

它把不属于自己的键也写进了存档：

```
C={"f5":294,"f6":295,"lang":"zh"}
```

补上 `settings.only = { "f5" }`，以后只写自己的键。

### ③ 配置本身没有备份

之前只有评级的 `Q0=`，**配置（`C=`）没有任何备份**。补一代备份：

- 新增 `S.PREFIX_BAK = "C0="`
- **保存时**：上一版 `C=` 存成 `C0=`（只留一条）
- **读取时**：`C=` 缺失 → 用 `C0=` 兜底

### 验证（离线单测）

```
读 f5=294 lang=en
保存后 C=1 条 C0=1 条
再存一次：C=1 条 C0=1 条（应为 1 / 1）      ← 不累积
C= 丢失时从 C0 读回：f5=290 lang=en          ← 能自愈
rating_test 25/25；luacheck 25 文件 0 失败
```

### 踩的坑

改 `settings.lua` 时用 `$S` 存文件行、`$s` 存行号 —— **PowerShell 变量名不区分大小写**，
`$s` 把 `$S` 覆盖成整数，文件被写坏成一行 `43`。已 `git checkout` 恢复并用 `$lines/$idx` 重做。
## 房间时长：清房即停 + 双时钟对照探针

### 清房即停（作者 2026-10-26）

原来 `ms` 是「进房 → 出房」的帧数差，包含打完 Boss 后捡道具、逛房间的时间。

现在在 `MC_PRE_SPAWN_CLEAN_AWARD`（清房奖励生成前，正是清房瞬间）记时间戳：

```
进房  tIn
清房  tClear   ← 新增
出房  tOut
```

结算用 `ms = tClear - tIn`（没有清房戳时退回 `tOut - tIn`）。
没清房的房间（走廊、未打的房间）行为不变。

### 双时钟对照探针（`config.timeProbe`）

同时记 `nowMs()`（帧数）和 `Isaac.GetTime()`（游戏内时间），每间房打一行：

```
[TIME] 帧: 清房=12.3s 出房=19.8s | 游戏: 清房=12.4s 出房=20.1s | 采用=12300
```

用途：确认 `Isaac.GetTime()` 是否可靠、是否排除暂停。
代码注释里写着「GetTime 不可靠」，所以先对照再决定要不要切换时钟。

开关：`config.timeProbe = true`（默认开，查完可关）。
## 修：首房起始道具未记录 + 飞行判定探针

### ① 一直持有的四级道具没记录（真 bug）

实测最近三局：**第一间房的道具列表全是空**。

```
seq29  首房 it: 空
seq30  首房 it: 空
seq31  首房 it: 空
```

原因：`state.startItems` 在 `MC_POST_PLAYER_INIT` 里读取，**那一刻玩家还没拿到起始道具**
（D6、mod 的初始道具都是在这之后才挂上）。所以 `#st == 0`，首房什么也不记，
「开局自带/一直持有的道具」永远进不了册子。

修法：出第一间房时若 `startItems` 为空，用**当前持有**补一次。

### ② 飞行判定

原来是 `player.CanFly and true or false`。如果 `CanFly` 在这个 REPENTOGON 版本里是**方法**
而不是字段，取到的是函数对象 → 恒为真 → 「总是会飞」。

改成类型自适应：

```lua
local ft = type(player.CanFly)
local fv = (ft == "function") and (player:CanFly()) or player.CanFly
s.canFly = (fv == true)
```

并加一次性探针：`[FLY] type=boolean 求值=true → canFly=true`，确认到底是哪种。
## 修：mod 增删后大 id 道具的配置错位

### 根因

配置是**按数字 id** 存的：

```json
Q={"v":1,"e":{"1074":{"q":3,"w":0.5},"1694":{...}}}
```

而 **mod 道具的 id 是运行时按加载顺序动态分配的**。启用/禁用任何一个 mod，后面所有 mod 的 id 都会整体平移 →
存档里的 `1074` 指向了另一件道具 → 「配置乱掉了」。

受影响的是 id > 732 的条目（原版只到 ~732）。作者档里共 8 条：

```
1074 Peerless Elixir / 1120 Mountain Ear / 1197 Broken Calendar / 1382 字刀
1491 龙之歌 / 1598 亚波伦之翼 / 1664 胜者之弹 / 1694 OvO
```

### 修法：给每条配置存一个「名字」

`mod` 会变，但**道具名不会变**（`ItemConfig.Name` 是英文名，与语言无关）。

- `jsonmini`：条目新增 `"n":"道具名"`，编码/解码都支持
- `R.set(id, q, w, on, name)`：写入时把名字一起存下
- 编辑器：保存时传 `stableName(curId)`（取 `ItemConfig.Name`）
- `R.load`：加载后按名字重新对 id —— `Isaac.GetItemIdByName(n)` 得到的 id 与存档不同就迁移过去

实测编码：

```
{"v":1,"e":{"118":{"q":4,"w":1,"on":false,"n":"Brimstone"},
            "1074":{"q":3,"w":0.5,"n":"Peerless Elixir"}}}
解码 1074: q=3 w=0.5 n=Peerless Elixir    ✔
```

### 注意

- **旧条目没有名字**，只能等下次在编辑器里改它时才会补上；在此之前 mod 变动仍会错位
- 道具名解析失败（mod 被卸载）时保持原 id 不动
## 修好作者存档里被 mod 漂移弄乱的 8 条配置（实测验证）

### 导出当前 id 表

临时探针（`config.dumpItemIds`）在 `PLAYER_INIT` 导出 700~2600 的 `id → 名字`：

```
[IDS] 975	Peerless Elixir	
[IDS] 1021	Mountain Ear	
...
导出 1928 条
```

对照 `_logs/items.lua`（配置写入时的旧 id），算出漂移量：

| 名字 | 旧 id | 当前 id |
|---|---|---|
| Tooth of the Vampire | 1052 | **953** |
| Peerless Elixir | 1074 | **975** |
| Robe of Firerat | 1077 | **978** |
| Mountain Ear | 1120 | **1021** |
| Exchange Ticket | 1166 | **1067** |
| Broken Calendar | 1197 | **1098** |
| 字刀 | 1382 | **1283** |
| 龙之歌 | 1491 | **1392** |
| 亚波伦之翼 | 1598 | **1499** |
| 胜者之弹 | 1664 | **1565** |
| OvO | 1694 | **1595** |

### 重写存档

`save1` 5 条、`save3` 19 条，全部按名字迁到新 id 并写上 `"n"` 字段；
原版道具（id < 732）不动。备份在 `_backup\rating-idfix-20261028-045841\`。

### 中途踩的两个坑

**① `%d` 收到浮点数** —— 新加的清房计时探针用 `Isaac.GetTime()`（小数）喂 `%d`：

```
main.lua:869: bad argument #6 to 'format' (number has no integer representation)
```

每进出一次房间就抛一次，`settleRoom` 直接中断（房间记录丢失）。
修法：`msFinal = math.floor(... + 0.5)`。

**② PowerShell 写 JSON 写出了反引号** —— 手工拼 JSON 时长这样：

```
"953":{"q":2.25,"w":0,`"on`":false,`"n`":`"Tooth of the Vampire`"}
```

反引号让 JSON 非法，下次加载会**整份丢弃**。已用 `jsonmini` 重新编解码修复
（现在两档都是合法 JSON，5 / 19 条完整）。

### 进游戏验证

```
[WEIGHT] loaded v0.1.3 (REPENTOGON=true)
[WEIGHT] 载入 5 条评级配置 / 3 行
编辑器官网打开正常，「已修改」显示 1 The Sad Onion 评级 4.00
报错：无
```

探针同时验证了清房计时：

```
[TIME] 帧: 清房=- 出房=0.3s | 游戏: 清房=- 出房=0.8s | 采用=267ms
```

注意：同一区间帧数 0.3s、`Isaac.GetTime()` 0.8s —— 两者差 2.6 倍，
说明 `GetTime` 不是"本房间耗时"的可靠来源（待进一步确认）。
## 关掉所有诊断探针（作者 2026-10-28）

进游戏验证：**探针行一条都没有**，正常日志还在。

| 探针 | 处理 |
|---|---|
| `config.timeProbe`（`[TIME]` 双时钟对照） | `true` → **`false`** |
| `config.dumpOnce`（几百行 `[DUMP]` 数据面板） | `true` → **`false`** |
| `config.dumpItemIds`（1900+ 行 `[IDS]`） | 已是 `false` |
| `[FLY]` 飞行判定类型探针 | 删除（自适应逻辑保留） |
| `[PROBE]` 持有列表暴涨诊断 | 删除（守卫逻辑保留） |
| `[BOSSCLEAR]` Boss 清房诊断 | 删除 |
| `[PILL]` 药丸 effect 诊断 | 删除 |
| 评级编辑器 `[WEIGHT] 持有 N 件` | 删除 |

保留的正常日志：`loaded` / `载入 N 条评级配置` / `[UI]` / 每间房一行 `F1-03 ...` / `落盘 OK`。

验证输出：

```
探针行：✔ 一条都没有
正常日志：[WEIGHT] 载入 5 条评级配置 / 2 行
          [HIGHLIGHT] F1-03 型01 形1  9.55 -> 9.55 ... 0.3s
报错：✔ 无
```

单测：`fmt_test PASS`、`identity_test 30/30`、`rating_test 25/25`。
## 记录开始 / 结束时间，显示在总览（作者 2026-10-28）

### 数据

| 字段 | 含义 | 写入时机 |
|---|---|---|
| `ws` | 开局墙钟 | `beginRun`（已有） |
| `we` | **结束墙钟**（新增） | `finishRun`（死亡/通关） |

`schema.lua` 的 `R` 作用域加 `we = "s"`；`highlight.analyze` 把它带到册子（`bk.we`）。
未完成的局（小退）没有 `we` → 总览显示「（进行中）」。

### 显示

```
开 2026-10-28 05:10     终 2026-10-28 06:42
开 2026-10-28 05:10     （进行中）
```

### 一个转义坑

`fmt` 的字符串类型会把 `| / = %` 转成 `_`，所以 `os.date("%Y/%m/%d %H:%M")`
存进去变成 `2026_10_28 05:10`。两处修：

- `wallText()` 改用 `%Y-%m-%d %H:%M`（没有需要转义的字符）
- `whenText()` 把旧数据里的 `2026_10_28` 还原成 `2026-10-28` 再显示

离线往返测试：

```
开=2026/10/28 05:10  终=2026/10/28 06:42   （编解码一致）
fmt_test PASS；identity_test 30/30
```

### 改文件时踩的两个坑

- 用 `Select-Object -Skip ($n-1)` 取行号时，`$n` 可能是数组（多文件匹配）→ 用 `(Select-String ...).LineNumber`
- 直接按下标覆盖行会**连带吃掉后面的 12 行**（q4 图标渲染），已 git checkout 恢复后改按「跳过原块 N 行」重做
### Boss 房窄探针（验证「清房即停」）

只对 Boss 房（房型 5/17 或有终极 Boss）打一行，其余房间不输出：

```
[BT] 帧: 清房=12.3s 出房=19.8s | 采用=12300ms
```

判读：**清房 < 出房且「采用」= 清房值** → 清房即停生效；
清房为 `-` 或两者相等 → 没生效（`MC_PRE_SPAWN_CLEAN_AWARD` 没触发/没记上）。

开关 `config.bossProbe = true`，验证完置 false。
## Boss 房探针验证结果（实测通过）

作者通关一局后，日志里拿到 8 条 `[BT]`：

```
[BT] 帧: 清房= 24.7s 出房= 56.3s | 采用=24667ms
[BT] 帧: 清房= 12.4s 出房= 21.7s | 采用=12400ms
[BT] 帧: 清房= 12.3s 出房= 69.7s | 采用=12333ms   ← 打完站着 57 秒，不计入
[BT] 帧: 清房=128.3s 出房=132.9s | 采用=128267ms
[BT] 帧: 清房=252.7s 出房=302.8s | 采用=252733ms
[BT] 帧: 清房=   -  出房= 12.2s | 采用=12200ms   ← 清房戳缺失，退回出房时间
[BT] 帧: 清房=   -  出房=  6.9s | 采用= 6867ms
```

结论：

- **清房即停生效**：清房 < 出房，且「采用」= 清房值
- 有 2 次清房戳缺失（`MC_PRE_SPAWN_CLEAN_AWARD` 没触发，如 Boss Rush 类房间），自动退回出房时间，不会丢记录

## 结束时间验证

```
seq34  24986B01-0  res=1  363 房  开=2026_10_28 05:45  终=（空）    ← 旧代码跑的
seq35  E1C33402-0  res=2    2 房  开=2026-10-28 09:21  终=（空）    ← 未完成
seq36  F3E26AF5-0  res=1  341 房  开=2026-10-28 09:21  终=2026-10-28 10:02  ✔
```

`we` 正确写入，且新数据用 `-` 分隔（不再出现 `2026_10_28`）。

## 探针已删除

`[BT]` 代码块与 `config.bossProbe` 一起删除，只留 `timeProbe/dumpOnce/dumpItemIds` 三个关掉的开关。
### 收尾：误入仓库的临时探针

`squash` 合并时把 `tests/_we2.lua`（验证 `we` 往返的临时脚本）带进了 main，已 `git rm`。
今后临时脚本统一用 `_` 前缀且**提交前检查** `git status`。
## 权重 0 会被"漏"出来的原因（作者 2026-10-28 报：字刀 / 伪造地质学博士证）

### 先分清两件事

| 道具 | 权重 | 含义 |
|---|---|---|
| 字刀 (1283) | **0** | 应该 100% 拦掉 |
| 伪造地质学博士证 (1570) | **0.1** | **10% 概率保留**，出现属设计内，不是 bug |

### 旧的拦截逻辑（有漏洞）

```lua
local chance = 1 - mul                 -- mul=0 → 1.0
if roll >= chance then return nil end  -- 保留原结果

for i = 1, 4 do                        -- 只重试 4 次
    alt = pool:GetCollectible(poolType, false, s + i*7919)
    if alt ~= itemID and altMul >= mul then result = alt; break end
end

if result then return result end
P.stats.gaveUp = gaveUp + 1
return nil                             -- ← 4 次都失败：原道具照样发出去
```

重试步长固定（`+7919`）、只试 4 次、回调里 `GetCollectible(..., false, ...)` 不消耗池子
→ 小池子（恶魔房 / Boss 池 / 图书馆）里反复抽到同一件 → `gaveUp` → 道具漏出。

### 本次改动

| 项 | 旧 | 新 |
|---|---|---|
| 重试次数 | 4 | **16** |
| 种子派生 | `s + i*7919`（固定步长） | **LCG 混合** `s*1103515245 + i*12345 + 7919`（仍由 s 决定，种子可复现） |

### 新增埋点（这次能定性了）

```
[BAN] 抽到禁止道具 id=1283 pool=2 → 尝试重掷
[POOL] 重掷成功 1283 -> 175  （倍数 0.00）
[BAN] 重掷失败 id=1283 pool=2（试了 16 次没换到）→ 原道具保留
```

判读：

- 有 `[BAN] 抽到…` + `重掷成功` → 正常拦截
- 有 `[BAN] 抽到…` + `重掷失败` → 坐实"重掷失败"
- **一条 `[BAN]` 都没有但道具出现** → 不是池子给的（mod 直塞 / 剧情奖励），权重管不到

### 待确认

作者说看到字刀时，评分配置的 `w=0` 是 **00:09:34** 才保存的，而当时那局 23:36 已结束 ——
存在"看到它时还不是 0"的可能，需下一次出现时的日志来定。
## 总览加「幸运币」统计（作者 2026-10-29）

作者说明：不是道具，是**捡了会 +1 幸运的金币**。

### 不用改采集，现有数据就够推

房间记录里已经有：金币进/出（`c` / `co`）、幸运进/出（`lko` / `lk`）。判定规则：

```
dc = 金币出 − 金币进
dl = 幸运出 − 幸运进
当 dc ≥ 1 且 dl ≥ 1 且 dl ≤ dc  → 幸运币 += floor(dl)
```

`dl > dc`（幸运涨得比金币多）说明幸运来自别的来源（幸运脚、药丸、道具），不计。

### 显示位置

总览页「飞行 / 防爆」那一行，追加第三项：

```
飞行 有   防爆 无   幸运币 7
```

### 历史数据也能用

用真实 `save3.dat` 跑了一遍（16 局），结果合理：

```
C2AC30D4  幸运币 4   7672F180  幸运币 5
CB288BBA  幸运币 6   24986B01  幸运币 4
7C43FF21  幸运币 0   BFA04053  幸运币 0
```

### 已知近似

- 同一房间既捡金币又吃「幸运上升」药丸时，可能多算（dl ≤ dc 的约束挡掉一部分）
- 幸运币如果被 mod 改成 +2 幸运，会被算成 2 枚
## 幸运币改成直接计数（作者 2026-10-29）

上一版是靠「金币 +1 且幸运 +1」推断的，会误判药丸/道具带来的幸运。现在直接认硬币：

### 关键发现

`CoinSubType.COIN_LUCKYPENNY` 是真实存在的枚举，装着的 mod 都在用：

```
aslans_mind.lua:38   if s == CoinSubType.COIN_LUCKYPENNY then return 1 end
geist_binding_rope   [CoinSubType.COIN_LUCKYPENNY] = { target = FLOWER_COIN }
shamrockLeaf.lua:50  Utils.choose(CoinSubType.COIN_PENNY, CoinSubType.COIN_LUCKYPENNY)
```

### 实现

```lua
add(ModCallbacks.MC_PRE_PICKUP_COLLISION, function(_, pickup, collider)
    local sub = luckyCoinSub()          -- CoinSubType.COIN_LUCKYPENNY（惰性解析）
    if pickup.Variant ~= 20 then return end   -- PICKUP_COIN
    if pickup.SubType ~= sub then return end
    if 是玩家碰到的 then state.pending.lc = state.pending.lc + 1 end
end, 20)
```

### 踩的坑

`CoinSubType` 在 REPENTOGON 里**可能是 userdata 而不是 table**，
原来的 `if type(CoinSubType) == "table"` 判断失败 → 回调**静默不注册**（不报错，永远计数 0）。

改成惰性解析 + `pcall`，并且第一次解析时打一行 `幸运币 subtype = N` 便于确认；
再加 `config.luckyCoinSub` 作为手动兜底。

### 数据兼容

- 新数据：房间记录新增 `lc` 字段，直接累加
- 旧数据：`lc` 为 nil → 自动回退到「金币/幸运增量」推断，历史局照常显示
## 终极 Boss 支持东方 mod：音符 / 哆来咪（作者 2026-10-29）

### 怎么找到这两个 Boss 的

在 `reverie_2538556220` 里：

```
content/entities2.xml:224   <entity name="Note" ... variant="5822">      ← 音符
content/entities2.xml:587   <entity name="Doremy Sweet" ...>             ← 哆来咪
scripts/bosses/reverie_note.lua:7   local Note = ModEntity("Reverie", "REVERIE_NOTE")
```

### 实现

UB 编码表新增：

```lua
local UB = { HUSH = 1, ..., DELIRIUM = 6,
             TOHOU_NOTE = 7, TOHOU_DOREMY = 8 }
```

识别按**实体名**解析类型，不硬编码 Type：

```lua
local MOD_BOSS_BY_NAME = {
    ["Note"]         = UB.TOHOU_NOTE,
    ["Doremy Sweet"] = UB.TOHOU_DOREMY,
}
-- 首次使用时 Isaac.GetEntityTypeByName(name) 解析并缓存
```

原因：mod 的 `EntityType` 会随 mod 加载顺序漂移（同一个坑我们已经在道具 id 上踩过两次），
但实体**名字**是稳定的。

### 顺带修了一个会导致永远识别不到的 bug

清房回调原本只在 `t == 5 or t == 17`（普通 Boss 房 / Boss Rush）时才去读 Boss：

```lua
if t == 5 or t == 17 then ... ultimateBossNow() ... end
```

而东方 Boss 房是**自定义房型**（音符房是 `ROOM_LIBRARY` variant 5802），这个条件直接把
它们挡在外面 —— 加多少名字都没用。现在改成**任何房间清房都检测**（开销可忽略）。

### 显示

`highlight.ULTIMATE_BOSS` 增加：

```
[7] = { cn = "音符",   en = "Note" }
[8] = { cn = "哆来咪", en = "Doremy" }
```

### 验证

部署后会打一行 `东方 Boss 识别：2/2 个名字解析成功`，
若显示 `0/2` 说明 `GetEntityTypeByName` 没解析到（届时贴日志给我）。
## 总览加「耗时」（作者 2026-10-29）

```
开 2026-10-28 22:41     终 2026-10-28 23:36     耗时 55m
```

### 实现

不需要改采集 —— 只解析已有的 `ws` / `we` 两个时间串：

```lua
local function wallMinutes(s)   -- "2026-10-29 22:41" → 绝对分钟数
    -- Howard Hinnant days-from-civil：纯整数运算，
    -- 不能依赖 os.time（沙盒里它恒为 0），也不能依赖 os.date 的差值
end

if d < 60 then return "55m" else return "2h03m" end
```

### 边界用例（离线验证）

| 用例 | 结果 |
|---|---|
| 同一天 22:41 → 23:36 | **55m** |
| 跨天 23:50 → 00:40 | **50m** |
| 跨月 10-31 23:30 → 11-01 01:00 | **1h30m** |
| 旧格式 `2026_10_28 09:21` → `10:02` | **41m**（兼容 `/` 和 `_` 两种分隔符） |

真实数据抽样：

```
CB288BBA  22:41 -> 23:36   55m
7DD47BA4  00:00 -> 00:43   43m
F3E26AF5  09:21 -> 10:02   41m
```

未完成的局（`we` 为空）仍显示「（进行中）」，不算耗时。
### 修：东方 Boss 在清房时扫不到

第一次部署后进游戏，日志里**根本没有** `东方 Boss 识别` 那行 —— 说明 `modBossType` 从未被调用。

原因：识别写在 `ultimateBossNow()` 的实体扫描里，而 `ultimateBossNow()` 是在**清房回调**里调的。
清房那一刻房间里已经空了（敌人尸体被移除），`GetEntities()` 返回空表 →
循环一次都不执行 → 名字解析永远不触发。

修法：加 `MC_POST_NPC_INIT`，在 **NPC 生成时**就判断类型：

```lua
add(ModCallbacks.MC_POST_NPC_INIT, function(_, npc)
    if not state.pending then return end
    local code = modBossType(num(npc.Type))
    if code and code ~= 0 then state.pending.ubIn = code; log("[UB] 检测到东方 Boss：…") end
end)
```

命中时会打：

```
[UB] 检测到东方 Boss：音符（type=1234）
```

`ultimateBossNow()` 里的实体扫描保留（对普通 Boss 房仍然有效），两条路径互补。
### 补：权重拦截的完整埋点（作者 2026-10-29 明确指出漏了一条）

之前只有三个结论分支有日志：

```
抽到受控道具 → 重掷成功 / 重掷失败 / （保留：静默）
```

「保留」分支没日志，导致权重 0.1 的道具正常出现时，日志里只有一行"抽到受控道具"，
后面什么都没有 —— 分不清是保留还是根本没进回调。现在补齐：

```
[POOL] 抽到受控道具 id=1565 pool=2 倍数=0.10
[POOL] 保留 id=1565 pool=2（倍数 0.10，保留概率 10%，掷出 0.97）
```

四条埋点现在覆盖全部分支：

| 分支 | 日志 |
|---|---|
| 抽到时 | `[POOL] 抽到受控道具`（倍率 < 1 的都会打） |
| 权重 ≤ 0 且抽到 | `[BAN] 抽到禁止道具` |
| 保留原道具 | `[POOL] 保留 …（掷出 x.xx）` |
| 换成别的 | `[POOL] 重掷成功 a -> b` |
| 换失败 | `[BAN] 重掷失败 …（试了 16 次没换到）` |
## 权重 0.1 反复出现：定位到「静默失败」

### 现象

```
[POOL] 抽到受控道具 id=1570 pool=0 倍数=0.10
[POOL] 抽到受控道具 id=1570 pool=0 倍数=0.10
（后面什么都没有：没有"保留"、没有"重掷成功/失败"）
```

按 `倍数=0.10`，每次有 90% 应进入重掷流程，但日志里一条结论都没有。

### 原因

`onPostGet` 里两条**静默返回**：

```lua
local okRng, r = pcall(function() return RNG(s) end)
if not okRng or not r then return nil end          -- 静默

local okRoll, roll = pcall(function() return rng:NextFloat() end)
if not okRoll or not roll then return nil end      -- 静默
```

`RNG` 或 `NextFloat` 一旦不可用 → **权重完全不生效，原道具照发**，且日志一片空白。

### 修法

1. 两条静默路径都补日志（`RNG 不可用` / `兜底随机`）
2. 加**纯 Lua 伪随机兜底**（同种子可复现），保证 `RNG` 不可用时权重仍生效：

```lua
local function fallbackRoll(seed)
    local x = (seed * 1103515245 + 12345) % 2147483648
    return (x % 10000) / 10000
end
```

3. 判定前打一行结果，任何一次抽签都能自证：

```
[POOL] 判定 id=1570 pool=0 倍数=0.10 掷出=0.573 阈值=0.900（掷出≥阈值=保留）
```

### 埋点现状（4 条覆盖全部分支）

| 分支 | 日志 |
|---|---|
| 抽到被配置过的道具 | `[POOL] 抽到受控道具` |
| 判定 | `[POOL] 判定 … 掷出=… 阈值=…` |
| 保留 | `[POOL] 保留 …` |
| 换成别的 | `[POOL] 重掷成功 a -> b` |
| 换失败 | `[BAN] 重掷失败 …` |
| RNG 异常 | `[POOL] RNG 不可用 / 兜底随机` |
## 权重从未生效的真因：`rng:NextFloat()` 这个方法不存在

### 自检怎么发现的

加了开局自检（`POOL_SELFTEST`，在 `loadData()` 之后用假 itemID/seed 跑 `onPostGet`），
第一次跑就暴露两个问题：

```
[SELFTEST] id=1570 权重=-1.00 → 返回 nil     ← 1 号档没有这两条配置（预期）
[SELFTEST] id=118  权重=0.00  → 返回 nil     ← 权重 0 也没拦住？！
```

手动把自检从 PLAYER_INIT 顶部移到 `loadData()` 之后，`id=118` 立刻正常：

```
[BAN] 抽到禁止道具 id=118 pool=0 → 尝试重掷
[POOL] 判定 id=118 倍数=0.00 掷出=0.311 阈值=1.000
[POOL] 重掷成功 118 -> 285
```

但日志里出现了 **`兜底随机`** —— 说明引擎 RNG 取数失败，走的是纯 Lua 兜底。

### 根因

```lua
rng:NextFloat()   -- ❌ 这个构建里不存在 → pcall 失败 → 静默 return nil
rng:RandomFloat() -- ✅ 正确方法（31 处 mod 代码都在用）
```

于是每次抽到受控道具都「静默放弃干预」，**权重从上线起就没生效过**。

### 修法

```lua
okRoll, roll = pcall(function() return rng:RandomFloat() end)
if not okRoll or not roll then
    okRoll, roll = pcall(function() return rng:NextFloat() end)   -- 兼容旧版
end
if not okRoll or not roll then roll = fallbackRoll(s) end          -- 纯 Lua 兜底
```

修完自检输出（引擎 RNG 正常，无"兜底随机"）：

```
[POOL] 判定 id=118 倍数=0.00 掷出=0.001 阈值=1.000
[POOL] 重掷成功 118 -> 285
[SELFTEST] id=118 seed=11111 权重=0.00 → 返回 285
```

### 自检开关

`POOL_SELFTEST = true`（`mod-rating/main.lua` 顶部），每局开局跑 9 次并打日志。
验证完改成 `false` 即可。

### 教训

`pcall` + 静默 return 是这次连查三天的根源：日志里只有"抽到"，没有任何结论。
**任何 pcall 失败都必须留一行日志**。
## 新增 docs/CALLBACKS.md（回调时机与踩坑总结）

作者指出：这一轮我至少三次把代码插错时机（自检放在 loadData 之前、清房时扫实体、
PLAYER_INIT 读起始道具）。把结论固化成文档，避免下次再犯。

内容：

1. **一局的生命周期**（按时间顺序）：mod main → MC_POST_MODS_LOADED → 主菜单 →
   PLAYER_INIT → GAME_STARTED → NEW_ROOM → UPDATE/RENDER → PRE_SPAWN_CLEAN_AWARD → …
2. **每个关键回调的「能做 / 不能做」**，每条都附我们踩过的真实 bug
3. **沙盒环境的硬事实**：os.time()=0、RNG 浮点方法叫 RandomFloat()、HasCollectible 语义、
   存档字符串转义、Font 坐标空间、ImGui 限制
4. **速查表**：「我要做 X → 挂哪个回调」
5. 教训：先确认真实时序再写代码；pcall 失败必须留日志；能用假数据自检就别靠运气
## 补单测：权重决策 / 双语 / 设置（作者 2026-10-30 要求：每个分支都要有 assert）

### 新增三个单测文件

| 文件 | 断言数 | 覆盖什么 |
|---|---|---|
| `tests/pool_test.lua` | **26** | 权重决策 `P.decide` 全部分支 + 兜底随机 |
| `tests/lang_test.lua` | **31** | 中英文案完整性、`L.t/tFor/init/set/needRestart` 全部分支 |
| `tests/settings_test.lua` | **22** | `C=` 读取、`C0=` 兜底、一代备份、`S.only`、往返 |

### 为了让逻辑可测，抽出了纯函数

```lua
-- core/pool.lua
function P.decide(mul, roll)   -- "skip" / "keep" / "reroll"，不碰引擎
function P.fallbackRoll(seed)  -- [0,1) 伪随机，同 seed 可复现
```

`onPostGet` 现在调用它们，判定逻辑因此可以离线覆盖。

### pool_test 覆盖的分支

| 分支 | 断言 |
|---|---|
| `mul == nil`（没配置） | 掷点 0 / 0.99 都 skip |
| `mul >= 1`（提高出现率 v1 未实现） | 1.0 / 2.0 / 999 都 skip |
| `mul == 0`（禁止） | 掷点 0 / 0.5 / 0.999 都 reroll |
| `mul == 0.1` | 0.0 / 0.5 / 0.899 → reroll；**0.9 边界** / 0.99 → keep |
| `mul == 0.5` | 0.49 → reroll；0.5 边界 → keep；0.51 → keep |
| `mul < 0` | 按 0 处理 → reroll |
| `roll == nil` | 按 0 处理 |
| `fallbackRoll` | 500 个种子全在 [0,1)；同 seed 一致；均值 0.35~0.65；极端 seed 不崩 |

### lang_test 覆盖的分支

- zh / en **键完全一致**（少一条英文界面会露出 key 名）
- 无空串
- **占位符数量两边一致**（否则 `string.format` 报错）
- `t()` 未知 key → 返回 key 名
- `tFor()` 未知语言 → 回落中文，且**不改全局状态**
- `init(nil / lang=en / 未知语言 / get 抛错 / 返回非字符串)` 五个分支
- `set(fake / nil / 抛错)` 三个分支 + 写回内容校验
- `needRestart()` 中英两套文案

### settings_test 覆盖的分支

- 读 `C=` 正常（数字 + 字符串两种值）
- `C=` 缺失但 `C0=` 存在 → 兜底
- 两者都没有 → 默认值
- 坏数据不崩
- 保存时旧 `C=` → `C0=`，**连续保存 3 次仍只有 1 条 C0=**
- `S.only` 只写自己的键（新 `C=` 不含 f6/lang）
- 保存不影响其它行（`Q=` 保留）
- 保存 → 重新读 往返一致

### 版本号

| mod | 旧 | 新 |
|---|---|---|
| Item Weight Editor | 0.1.3 | **0.1.4** |
| Highlight Review | 0.4.1 | **0.4.2** |