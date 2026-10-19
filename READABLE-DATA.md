# 以撒可读数据目录（Repentance 1.7.9b + REPENTOGON 1.0.8c）

> 用途：查"这个信息能不能记"。每条标了 **成本 / 建议 / 置信度**。
> 置信度说明：✅ = 本机实测或已核对的文档；⚠️ = 名字待现场验证（用 `core/dump.lua` 一探即知）。
>
> 记录成本按**单个字段**估算：`~2 字节`（整数）/ `~5 字节`（小数）/ `~4 字节/项`（列表）。

---

## 0. 先看结论：最值得加的 8 项

| # | 数据 | 为什么值得 | 成本 | 落在哪 |
|---|---|---|---|---|
| 1 | **层种子** `Seeds:GetStageSeed()` | 复盘能重现楼层；也是"这层为什么这么怪"的答案 | +9 B/层 | `F.seed` |
| 2 | **每层进入/离开时间** | 已有字段 `t`/`ms`，**目前没填**；层时长是节奏分析的骨架 | 0（字段已有） | `F.t` `F.ms` |
| 3 | **击杀数**（每房） | 和"清房耗时"配对，才能判断"这间房是硬还是我快" | +3 B/房 | `M.kills` |
| 4 | **口袋资源**（钱/炸弹/钥匙）进出值 | 你最初就说过"哪个房间补充了一波资源" | +6 B/房 | `M.c` `M.co` … |
| 5 | **Boss ID** | "这层被谁收走"比房型 5 更有信息量 | +3 B/房 | `M.boss` |
| 6 | **是否首次访问** | 区分"探索"和"回程"，回程的房间不该计入节奏统计 | +1 B/房 | `M.first` |
| 7 | **伤害来源**（按敌人类型） | "这局怎么死的"——现有 `dmg` 只是个总数 | +8 B/房 | `M.src` |
| 8 | **临时效果列表** | 解释"战力为什么突然高"（见 E29） | +2 B/项 | `M.fx` |

**不建议加的**：房间网格（135 B/房）、卡牌药丸全文、成就计数器（与复盘无关）。

---

## 1. 局（Run）级

| 数据 | API | 状态 | 备注 |
|---|---|---|---|
| 起始种子 | `Game():GetSeeds():GetStartSeed()` | ✅ 已用 | 注意是 uint32 |
| 每层种子 | `Seeds:GetStageSeed()` | ⚠️ 待验 | 想复盘必加 |
| 角色 | `player:GetPlayerType()` / `GetBabySkin()` | ✅ 已用 | 后者区分双子/皮肤 |
| 结局 | `MC_POST_GAME_END(isGameOver)` | ✅ 已用 | 只有死/通关，没有"打到哪" |
| 到达层数 | 自算（stage key 变化） | ✅ 已用 | 比 `LevelStage` 可靠 |
| 开始时间戳 | `Isaac.GetFrameCount()*1000/30` | ✅ 已用 | 只能给相对时间 |
| 挑战 / 每日挑战 | `Game():GetChallenge()` / `IsDailyChallenge()` | ⚠️ 待验 | 以后支持每日才有用 |
| 分数（结算表） | REPENTOGON `ScoreSheet` | ⚠️ 未验 | 和"战力"不是一回事 |

---

## 2. 层（Floor）级

| 数据 | API | 状态 | 成本 |
|---|---|---|---|
| 层类型 | `Level:GetStage()` → `LevelStage` | ✅ 已用 | — |
| 层变体 | `Level:GetStageType()` | ✅ 已用 | — |
| **诅咒** | `Level:GetCurses()` → 位掩码 | ✅ 已采集 | 1黑暗 2迷宫 4迷失 8未知 16诅咒 32迷阵 64失明 128巨大 |
| 是否镜像/回溯 | `Level:IsMirrorWorld()` / `Room:IsMirrorWorld()` | ⚠️ 待验 | 真结局路线才有 |
| 天使/恶魔房判定 | `Level:GetDevilAngelRoom()` | ⚠️ 待验 | 记录"这层开的是哪个" |
| 星球仪概率 | `Level:GetPlanetariumChance()` | ⚠️ 待验 | 小众 |
| 层进入时间 | 自己记 | ✅ 字段已有（`F.t`）**未填** | 0 |
| 层时长 | 同上（`F.ms`）+ 累加 | ❌ **未实现** | 0 |

> 注：`F.curse` 已经从字符串改成整数位掩码，渲染时用 `highlight.curseNames()` 解成人话。

---

## 3. 房间（Room）级

### 3.1 身份与几何（`RoomDescriptor` + `RoomConfigRoom`）

| 数据 | API | 状态 |
|---|---|---|
| 房型 | `desc.Data.Type`（等价 `Room:GetType()`） | ✅ 已用 |
| 形状 | `desc.Data.Shape` | ✅ 已用 |
| 门位掩码 | `desc.AllowedDoors`（退回 `Data.Doors`） | ✅ 已用 |
| 房间配置 ID | `Data.StageID` / `Data.Variant` / `Data.Subtype` | ✅ 已用（后一个未记） |
| 唯一索引 | `desc.ListIndex` | ✅ 已用（跨维度唯一，比 GridIndex 可靠） |
| 宽高 | `Data.Width` / `Data.Height` | ⚠️ 可推导，可省 |
| **难度** | `Data.Difficulty` | ⚠️ 已 dump 到（值 1），未记录 |
| **权重/稀有度** | `Data.Weight` / `Data.InitialWeight` | ⚠️ 同上（都是 1.0） |
| 房间名 | `Data.Name`（如 "Start Room"） | ⚠️ 可读，但大量重复 |
| 道具座 | `Data.Spawns` | ⚠️ **注意**：这是**所有**刷怪点，不是只有道具座 |
| 是否首次访问 | `Room:IsFirstVisit()` | ⚠️ 待验 |
| 是否清房 | `Room:IsClear()` / `desc.Clear` | ✅ 已记（`clr`） |
| Boss ID | `Room:GetBossID()` | ⚠️ 待验 |
| 商店等级 | `Room:GetShopLevel()` | ⚠️ 待验 |
| 恶魔房概率 | `Room:GetDevilRoomChance()` | ⚠️ 待验 |
| 祭坛进度 | `Room:IsSacrificeDone()` | ⚠️ 待验 |
| 坑/屎数量 | `desc.PitsCount` / `desc.PoopCount` | ⚠️ 可读，价值一般 |
| 各种 Seed | `desc.SpawnSeed` / `AwardSeed` / `DecorationSeed` | ⚠️ 可读，复盘才用 |

### 3.2 房间内容（要遍历实体，成本较高）

| 数据 | API | 成本 | 建议 |
|---|---|---|---|
| 敌人数/类型 | `Room:GetEntities()` + `entity.Type/Variant` | 高（每房 1~30 条） | 只记数量 |
| 掉落物 | 同上（`EntityType.ENTITY_PICKUP`） | 中 | 记数量/类型 |
| 网格实体 | `Room:GetGridEntity(i)` | 极高（135 格） | ❌ 不建议 |
| 房间网格快照 | REPENTOGON `GetGridEntitiesSaveState()` | 中（~30 B/房 RLE） | 🔒 留作"以后画房间图" |

---

## 4. 玩家（Player）级

### 4.1 属性（都是纯数字，读起来几乎零成本）

| 属性 | 字段 | 我们算战力用不用 |
|---|---|---|
| 伤害 | `player.Damage` | ✅ 核心 |
| 射击间隔 | `player.MaxFireDelay` | ✅ 核心（换算攻速） |
| 射速 | `player.ShotSpeed` | 间接（影响命中率） |
| 射程 | `player.TearRange` / `TearHeight` | 隐性战力 |
| 幸运 | `player.Luck` | 影响掉落，不算战力 |
| 移速 | `player.MoveSpeed` | 隐性战力（走位） |
| 弹幕数 | `player:GetMultiShotParams():GetNumTears()` | ✅ 核心（REPENTOGON） |
| 弹道标志 | `player.TearFlags` | 形态判定用 |
| 飞行 | `player.CanFly` | 隐性（无伤躲坑） |

> `EntityPlayer` 变量表已核对过（27 个），**没有 `Range`、没有 `TearsMultiplier`**。

### 4.2 生存与资源

| 数据 | API | 状态 |
|---|---|---|
| 红心（半心） | `player:GetHearts()` | ✅ 已用（进/出各一份） |
| 魂心+黑心（半心） | `player:GetSoulHearts()` | ✅ 已用 |
| 骨心（颗） | `player:GetBoneHearts()` | ✅ 已用 |
| 最大血量 | `GetMaxHearts()` / `GetEffectiveMaxHearts()` | ⚠️ **值得加**（区分"掉血"和"上限被削"） |
| 金币 | `player:GetNumCoins()` | ⚠️ 值得加 |
| 炸弹 | `player:GetNumBombs()` | ⚠️ 值得加 |
| 钥匙 | `player:GetNumKeys()` | ⚠️ 值得加 |
| 饰品槽 | `player:GetTrinket(0/1)` | ✅ 已用 |
| 卡牌/药丸/胶囊 | `player:GetCard(0)` / `GetPill(0)` | ⚠️ 可加（谁用了什么） |
| 主动道具与充能 | `GetActiveItem(0)` / `GetActiveCharge()` | ⚠️ 值得加 |

### 4.3 状态类（解释"战力为什么突然变"）

| 数据 | API | 状态 |
|---|---|---|
| 临时效果列表 | `player:GetEffects():GetEffectsList()` | ⚠️ 见 E29，覆盖 ~190 个道具 |
| 红豆汤剩余帧 | `GetRedStewBonusDuration()`（REPENTOGON） | ⚠️ 专用 getter |
| 嗜血层数 | `GetBloodLustCounter()`（REPENTOGON） | ⚠️ 专用 getter |
| 堕化参孙狂暴 | **无 API**（只有 `SamsonBerserkCharge` 是充能不是状态） | ❌ 放弃 |
| 累计受伤 | `player:GetTotalDamageTaken()` | ⚠️ 可和我们的 `dmg` 交叉校验 |
| 最后伤害来源 | `player:GetLastDamageSource()` → `EntityRef` | ⚠️ "被谁打的" |
| 双子/合作者 | `player:IsCoopGhost()` / `GetOtherTwin()` | 低优先 |

---

## 5. 道具 / 饰品 / 卡牌

| 数据 | API | 状态 |
|---|---|---|
| 全部道具表 | `Isaac.GetItemConfig():GetCollectible(id)` | ✅ 已 dump（1752 条，最大 id 1763） |
| 道具品质 | `.Quality`（0~4） | ✅ 在读 |
| 道具标签 | `.Tags`（位掩码）/ `.CacheFlags` | ⚠️ 可读（dump 里已见） |
| 道具名/描述 | `.Name` / `.Description` → **本地化 key**（`#THE_D6_NAME`） | ⚠️ 要显示中文需再查本地化表 |
| 手持道具列表 | `GetCollectibleCount()` + `GetCollectible(i)` | ❌ **`GetCollectible(i)` 这个版本不存在** → 已改 `HasCollectible(id)` 扫 1..2000 |
| 饰品表 | `GetItemConfig():GetTrinket(id)` | ⚠️ 同道具 |
| 卡牌/药丸 | `.GetCard(id)` / `.GetPill(id)` | ⚠️ 未验 |

---

## 6. 道具池（对"调出现率"这个扩展点很关键）

本机实测，这些方法**全部存在**：

```
ItemPool:GetCollectible(num, decrease, seed, skip)
ItemPool:AddCollectible(id, add, party, greed)
ItemPool:RemoveCollectible(id)
ItemPool:GetNumCollectibles(pool)
ItemPool:GetCollectibleFromPool(...)
ItemPool:GetPoolForCollectible(...)
ItemPool:GetRemovedCollectibles()
ItemPool:AddTrinket / RemoveTrinket
```

池成员与权重来自 `itempools.xml` 的 `<Item Name= Weight= DecreaseBy= RemoveOn=>`。
**运行时能否读权重未验证**（可能只能读"有哪些"，读不到"多少"）。

---

## 7. 敌人 / Boss / 战斗

| 数据 | API | 价值 |
|---|---|---|
| 房间实体枚举 | `Room:GetEntities()` | 中（要控制采样频率） |
| 击杀事件 | `MC_ENTITY_KILL`? ⚠️ 待验 | **高**（击杀数是最便宜的"战斗强度"指标） |
| 受伤来源 | `MC_ENTITY_TAKE_DMG` 的第 5 参 `EntityRef` | **高**（能归因到具体敌人类型） |
| Boss 击杀 | `MC_POST_ENTITY_KILL(nil, boss)` | 中 |
| 敌人血量上限 | `entity.MaxHitPoints` | 低（可推房间强度） |

---

## 8. 全局统计（跨局、跨存档）

| 数据 | API | 说明 |
|---|---|---|
| 成就/计数 | `Isaac.GetPersistentGameData():Get(key)` | 与复盘无关，**不建议** |
| 图鉴击杀数 | 同一来源 | 同上 |
| 解锁表 | 同一来源 | 同上 |
| 道具拾取历史 | REPENTOGON `History:GetCollectiblesHistory()` | 我们已有等价物 |
| 结算评分 | REPENTOGON `ScoreSheet` | ⚠️ 和"战力"不同维度 |

---

## 9. 明确拿不到的（别再花时间）

| 想要 | 为什么不行 |
|---|---|
| 截图 / 像素读回 | 引擎没有 framebuffer readback（vanilla 和 REPENTOGON 都没有） |
| 自建文件 / 数据库 | `io`/`os` 被沙箱移除；唯一写通道是 `mod:SaveData()` |
| 基础属性（去掉临时加成） | 没有 base-only accessor；重算也会带上临时加成 |
| `IsBerserk` | 不存在（vanilla + REPENTOGON 都没有） |
| 房间网格按 roomId 事后还原 | 离开楼层后 `Level` 被销毁；静态 STB 无读取器 |
| `GetCollectible(i)` | 这个版本没有该方法 |

---

## 10. 怎么自己验证任何一条

`mod/core/dump.lua` 已经能把字段全量打出来（日志里搜 `[HIGHLIGHT] [DUMP]`）。想探某个新 API：

```lua
-- 加到 dump.lua 里，或临时写在任何一个回调里
local p = Isaac.GetPlayer(0)
local probes = { "GetMaxHearts", "GetNumCoins", "GetEffects", "IsFirstVisit" }
for _, name in ipairs(probes) do
    local ok, v = pcall(function() return p[name] end)
    Isaac.DebugString(name .. " = " .. tostring(ok and "存在" or "不存在") ..
                      (ok and (" / " .. type(v)) or ""))
end
```

**注意**：探针自身也会崩（我们踩过一次），所以一定要 `pcall` 包住，并且**只打类型不打值**。

---

## 11. 如果要加，按这个顺序

1. **`F.ms`（层时长）** —— 字段已有，纯粹是没填，零成本
2. **击杀数** —— 一个事件回调，+3 B/房
3. **口袋资源（钱/炸弹/钥匙）** —— 3 个 getter × 进出，+6 B/房
4. **最大血量** —— 1 个 getter，区分"掉血"和"上限被削"
5. **Boss ID + 首次访问** —— 2 个 getter，+4 B/房
6. **层种子** —— +9 B/层
7. **临时效果列表** —— 遍历 `GetEffectsList()`，+2 B/项

前 5 项加起来约 **+16 字节/房**，500 局仍然是可控范围（当前 124 B/房 → 约 140 B/房）。
