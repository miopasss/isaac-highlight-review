# PERFORMANCE.md · 两个 mod 对游戏的性能开销账本

> 用途：**每次改代码前先看这里**，改完把新增/变化的开销更新进来。
> 最后更新：2026-10-24
>
> 环境基线（所有数字都在这个环境测的）：
> - REPENTOGON 1.0.12e，游戏 1.7.9b
> - 同时加载 64 个 mod（含明日方舟、reverie、天界呼唤等）
> - 样本存档：3 号档 **1763 件道具**、300+ 间房、10 层
> - 帧率上限 30 fps（游戏锁帧）

---

## 0. 一句话总览

| 频率 | 开销 | 状态 |
|---|---|---|
| **每帧** | `itemwatch` 读一次整张持有表（1763 件） | ⚠️ 最大单项 |
| **每 20 帧** | HUD 战力 `snapshot()` 一次 | 🟡 中等 |
| **每间房** | 快照 + 读取列表 + 品质查表 | ✅ 可接受 |
| **每层** | 序列化整份存档并写盘（**1.2 MB**） | ⚠️ I/O 最大项 |
| **每局开局** | `[DUMP]` 打 3567 行日志 | ⚠️ 纯浪费 |
| **抽道具时** | 重掷判定（评级 mod） | ✅ 可接受 |

---

## 1. 每帧开销（30 fps）

### 1.1 回顾 mod · `itemwatch.tick()` —— ⚠️ 最大单项

**位置**：`mod-review/main.lua` 的 `MC_POST_UPDATE` → `itemwatch.tick(getPlayer(), 1800)`
**实现**：`mod-review/core/itemwatch.lua`

```lua
local list = readList(player)        -- player:GetCollectiblesList()，每帧一次
for id, n in pairs(list) do ... end  -- 遍历整张表
W.last = list
```

**它为什么存在**：房间级比对会漏两类道具——

| 盲区 | 例子 |
|---|---|
| 同房拿了又丢 | 麦苗：拿 → 临时道具 → 立刻消失，房间结束时对比看不见 |
| 跨房瞬间获得 | 传送、箱子连锁 |

所以每帧盯一次，把「数量变多」的 id 记进 `pending`，离房时 `drain()` 合并。

**实测代价**：1763 件道具 × 30 fps ≈ **每秒 5.3 万次表写入 + 10.6 万次遍历**
（`pcall` 每次调用也有一层开销）

**优化候选**：
- 改成每 3~5 帧比对一次（捡道具延迟最多 0.17 秒；离房还有 `drain()` 兜底）
- 或把 `pairs()` 换成「只关心新增」的写法：记录表长度，长度没变就跳过遍历

### 1.2 回顾 mod · HUD 战力刷新 —— 🟡 中等

**位置**：`MC_POST_RENDER` 里 `fc % 20 == 0` 时调 `snapshot(player)`
**代价**：一次完整战力公式（查表 + 宝宝 + 幸运 + 六维），每 20 帧一次 ≈ 每秒 1.5 次
**优化候选**：改成每 30 帧；或只在「持有道具数量变化」时才重算

### 1.3 回顾 mod · 册子渲染 —— ✅ 便宜

`bookui.update` / `bookui.render` 每帧调用，但**册子没开就早退**。
册子开着时每帧画整页（纸张 + 文字 + 图标），一页约 100 次绘制调用。

### 1.4 评级 mod · `editor.watch()` —— ✅ 便宜

每帧一次 `ImGui.IsVisible(WIN)` + 热键判定，无分配。

---

## 2. 每间房开销

| 时机 | 动作 | 备注 |
|---|---|---|
| 进房 | `snapshot(player)`：血量/六维/金币/炸弹/钥匙 | 一次读十几个 API |
| 房内 | `state.pending` 补采：敌人数、Boss id、终极 Boss | 只在待结算时跑 |
| 出房 | `readCollectibles`（`GetCollectiblesList` 一次）+ 品质查表（缓存）+ `itemwatch.drain()` | 可接受 |
| 出房 | `MC_POST_NEW_ROOM`（评级 mod）→ `E.touch()` 再读一次列表 | 2026-10-24 新增，一次/房 |

300 间房 ≈ 300 次快照 + 600 次列表读取（两个 mod 各一次）。

---

## 3. 每层开销 —— ⚠️ I/O 最大项

**位置**：`flushCurrentRun("换层")` → `fmt` 序列化整份 store → `mod:SaveData(blob)`

**实测**：

```
data/highlight-review/save3.dat   1,197,732 B   ≈ 1.2 MB（正卡在 config.maxBlobBytes 上限）
data/highlight-review/save1.dat      47,406 B
```

**为什么这么大**：房间里只要拿到一个 mod 道具（id ≥ 1792），整份 mod 道具表
（96~111 个 id）都会被写进 `it`。一局下来几千条垃圾记录。

**后果**：每换一层要拼 1.2 MB 字符串 + 写盘，一局 10 次。

**缓解**：
- 采集层已加 `[FILTER]`，丢弃品质 < 0 的条目（2026-10-24）
- **历史存档里的脏记录不会自动消失**，要彻底解决需要清洗 + 修 `it` 整表写入

---

## 4. 每局一次性开销

| 项 | 代价 | 建议 |
|---|---|---|
| `[DUMP]` 数据面板（`config.dumpOnce = true`） | `for id = 1..2000` 每件打一行 → 本次日志 **3567 行** | **默认关掉**，需要时手动开 |
| `fmt` 自检 | 一次编解码校验，毫秒级 | 保留 |
| 读档解析 | 1.2 MB 文本 → 行数组 + 索引（每局进局时） | 随存档瘦身一起下降 |

**日志文件现状：110 MB**（主要是 `[DUMP]` + 引擎断言洪水）。

---

## 5. 抽道具时（评级 mod）

`MC_POST_GET_COLLECTIBLE` → `poolmod.onPostGet()`：只在**生成道具**时触发，
权重 = 1 的直接返回，权重 < 1 的才走重掷。开销可接受。

---

## 6. 内存占用（进程内，不落盘）

| 结构 | 规模 |
|---|---|
| 回顾 store（文本行 + 索引） | 1.2 MB 文本 + 索引表 |
| `bookui` 分析缓存 `cache[seq]` | 每局一个分析结果，开册子才算 |
| 图标缓存 `iconCache` | 69 个 sprite + 25 个失败标记（失败也缓存，不重试）✅ |
| 评级 `seenOrder` | 每件持有道具一个整数 |
| 评级 `ownedList`/`searchResults`/`editedList` | 每次刷新重建 |

---

## 7. 优化候选（按性价比排序）

| # | 项 | 预期收益 | 风险 |
|---|---|---|---|
| 1 | `itemwatch` 每帧 → 每 3~5 帧 | 每秒少 8~10 万次操作 | 低（离房还有 drain） |
| 2 | `dumpOnce` 默认关闭 | 日志少 3567 行/局，开局更快 | 无 |
| 3 | HUD `snapshot` 20 帧 → 30 帧 / 按需 | 小 | 无 |
| 4 | 修 `it` 整表写入 + 清洗历史存档 | 存档 1.2 MB → 几十 KB，每层写盘大幅变快 | 中（要改采集逻辑 + 一次性数据清洗） |

---

## 8. 维护规则

1. **每次新增回调**（`MC_*`），必须在第 1/2/3/4 节里登记：频率、动作、估计代价
2. **每次新增每帧逻辑**，必须写进 §1，并说明为什么不能降频
3. 改动后如果关键数字变了（存档大小、日志行数、帧率），更新对应数字并改「最后更新」日期
4. 新增性能相关的开关（如 `dumpOnce`）写进 §4 或 §7
5. 怀疑卡顿时：先看 `[HIGHLIGHT]`/`[WEIGHT]` 日志里有没有新增的每帧输出

---

## 9. 怎么测

```powershell
# 存档大小
Get-ChildItem "<游戏目录>\data\highlight-review","<游戏目录>\data\highlight-rating" -File |
    Select-Object Name, Length, LastWriteTime

# 日志量
$log = "$env:USERPROFILE\Documents\My Games\Binding of Isaac Repentance\log.txt"
(Get-Item $log).Length / 1MB
(Select-String -Path $log -Pattern '\[DUMP\]').Count
(Select-String -Path $log -Pattern '\[HIGHLIGHT\] F\d').Count

# 帧率：游戏右上角，或 [_logs] 截图里的 FPS
```
