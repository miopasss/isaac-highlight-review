# CALLBACKS.md · 游戏什么时候走哪个回调（踩坑总结）

> 这份文档只回答一件事：**我想做的这件事，应该挂在哪个回调上？**
> 每条都附"我们实际踩过的错"，不是从文档抄的，是从 bug 里换来的。

---

## 1. 一局的生命周期（按时间顺序）

```
mod main.lua 执行（两个 mod 各一次）
   ↓
MC_POST_MODS_LOADED            所有 mod 的 main 都跑完了 → 跨 mod 交互（读 _G.HLR 等）
   ↓
主菜单 / 选存档槽 / 存档内菜单      ← 这里没有玩家、没有 LoadData 以外的世界
   ↓
MC_POST_PLAYER_INIT            进局瞬间（每局一次）★ 起始道具还没挂上
   ↓
MC_POST_GAME_STARTED           读档完成、道具池已就绪
   ↓
MC_POST_NEW_ROOM               进入每一间房（含第一间）★ 实体可能还没生成
   ↓
MC_POST_UPDATE / MC_POST_RENDER 每帧（30 fps）
   ↓
MC_PRE_SPAWN_CLEAN_AWARD       清房瞬间（只在"有清房奖励"的房间触发）★ 房间已空
   ↓
MC_POST_NEW_ROOM               下一间房 → 回到上面，循环
   ↓
MC_POST_GAME_END               死亡/通关结算（第一个参数是 mod！）
   ↓
MC_PRE_GAME_EXIT               小退/退出到菜单 → 最后写盘机会
```

---

## 2. 关键回调的「能做 / 不能做」

### MC_POST_PLAYER_INIT（进局，每局一次）

| 能 | 不能 |
|---|---|
| `mod:LoadData()` 读当前存档槽 | ❌ 读起始道具（D6、mod 初始道具**还没挂上**） |
| 重置本局状态（计数器、缓存） | ❌ 读 Boss（房间里还没有东西） |
| 计算种子/角色 id | ❌ 依赖 `Game():GetRoom()` 的房间内容 |

> **踩过**：`state.startItems = readCollectibles(player)` 放在这里 → 永远是空表 →
> 「开局自带道具」从来没进过册子。修法：出第一间房时若为空，用当前持有兜底。

> **踩过**：开局自检放在 `PLAYER_INIT` 的最前面 → `rating.load` 还没跑 → 评级表为空 →
> `getWeightMul` 全返回 nil → 自检 9 条全是 `返回 nil`，看起来像"权重没配"。
> **凡是依赖存档数据的逻辑，必须放在 `loadData()` 之后。**

### MC_POST_GAME_STARTED

| 能 | 不能 |
|---|---|
| `ItemPool` 快照（池子已可读） | ❌ 读起始道具（同样太早） |

### MC_POST_NEW_ROOM（进房瞬间）

| 能 | 不能 |
|---|---|
| 拍属性快照（血量/六维/金币/道具） | ❌ 识别 Boss：`GetBossID()` 返回 0（Boss 还没生成） |
| 记房间身份（stageId/variant/listIndex） | ❌ 依赖房间内的敌人/掉落物 |

> **踩过**：`ubIn = ultimateBossNow()` 在进房瞬间扫实体 → 扫不到 Boss。

### MC_PRE_SPAWN_CLEAN_AWARD（清房瞬间）

| 能 | 不能 |
|---|---|
| 记"清房时间戳"（我们的时长就在这里停止） | ❌ **扫实体**：此刻敌人尸体已被移除，`GetEntities()` 是空的 |
| 读 `Room:GetBossID()`（此时才可靠） | ❌ 读掉落物（奖励还没生成） |

> **踩过**：东方 Boss（音符/哆来咪）识别写在清房时的实体扫描里 → 永远命中不了。
> 修法：改挂 `MC_POST_NPC_INIT`，**NPC 生成那一刻**按实体名判断。

### MC_POST_NPC_INIT（NPC 生成）

| 能 | 不能 |
|---|---|
| 按 Type 识别 Boss（含 mod Boss） | ❌ 判断"是不是 Boss 房"（要看房型，另一个来源） |
| 记 Boss 出现的房间 | — |

> 建议：mod 实体的 **Type 会随加载顺序漂移**，用 `Isaac.GetEntityTypeByName("名字")` 解析，
> 名字取自 mod 的 `content/entities2.xml`（如 `Note`、`Doremy Sweet`）。

### MC_POST_GET_COLLECTIBLE（**只在道具池抽签时**触发）

```
引擎从道具池抽道具
   → MC_POST_GET_COLLECTIBLE(mod, itemID, poolType, decrease, seed)   ★ 只有这里能改
   → 返回别的 id 就替换
```

| 会触发 | 不会触发 |
|---|---|
| 宝箱房 / Boss 房 / 商店 / 恶魔房 / 天使房 / 诅咒房等**池子抽签** | ❌ 控制台 `spawn 5.100.xxx` |
| 池子里被 mod 用 `itempools.xml` 注入的道具 | ❌ `player:AddCollectible()` 直接给 |
| | ❌ 掉落物被 **Morph / 镜像骰 / 伪装** 改成的道具 |
| | ❌ 抽卡类 mod 自己 spawn 的收藏品 |

> **踩过**：作者看到「权重 0.1 的伪造地质学博士证」反复出现，以为拦截失效。
> 实际是**回调进来了但内部静默失败**（见下一条）；另外确实存在 Morph 路径完全绕过回调。

> `poolType` 是 **0-based**：`0 = 宝箱房`、`2 = Boss 房`、`3 = 恶魔房`。

### MC_POST_ADD_COLLECTIBLE（任何来源获得道具）

只要"玩家获得道具"就触发（不管来自池子还是直接给）。
**要给"所有权重拦截兜底"就只能挂这里**（代价：会跟镜像骰这类玩法打架）。

### MC_POST_UPDATE / MC_POST_RENDER

| 能 | 不能 |
|---|---|
| 每帧逻辑 / 采样（我们的战力采样每 20 帧） | ⚠ `POST_RENDER` 早于游戏 UI → **暂停菜单会盖住你画的东西** |
| HUD 绘制、`Font:DrawString` | ❌ 在这里 `ImGui.RemoveWindow`（**会崩游戏**） |

> **踩过**：`Isaac.GetFrameCount()` 在**暂停/主菜单也照常增长** → 用它算房间时长会把掉线、
> 暂停、看册子的时间全算进去。修法：清房时打时间戳，用清房时间戳结算。

### MC_PRE_GAME_EXIT（小退/退出到菜单）

**这是唯一可靠的写盘时机**：不写就丢本局数据。
但注意存档槽可能已经被切换 → 写入前必须确认 `runActive`（我们踩过"1 号档数据写进 3 号档"）。

### MC_POST_GAME_END

> **踩过**：签名是 `function(_, isGameOver)` —— **第一个参数是 mod**，不是 `isGameOver`。
> 写成 `function(isGameOver)` 会拿到一张表（永远真值）→ 所有通关都被记成死亡。

---

## 3. 沙盒环境的硬事实（不是回调，但同样会咬人）

| 事实 | 影响 |
|---|---|
| `os.time()` 返回 **0** | 不能用它算耗时/时间戳 |
| `os.date("%Y-%m-%d %H:%M")` **可用** | 墙钟时间只能这么取（拿到的是真实系统时间） |
| `RNG` 的浮点方法叫 **`RandomFloat()`** | `NextFloat()` 不存在 → pcall 失败 |
| `pcall` 失败不留日志 = 看不见的 bug | **任何 pcall 都要在失败分支打一行日志** |
| `player:GetCollectiblesList()` 在部分来源的 player 上不可用 | 先试传入的 player，再试 `getPlayer()` |
| `player:GetCollectible(i)` / `GetCollectiblesList` 有无随版本 | 都要 pcall + 兜底 |
| `HasCollectible(id)` 语义是"曾经拥有/已解锁" | 不能用来数持有数，用 `GetCollectibleNum(id)` |
| `Font:DrawString` 坐标是 480×270 空间 | `rect()` 要 `* s`（屏幕像素），混用会错位 |
| ImGui 控件标签创建时固定 | 改语言只能 `RemoveWindow` 重建（但 `RemoveWindow` 会崩 → 重启游戏） |
| 存档字符串会把 `\| / = %` 转成 `_` | 时间戳别用 `/`，用 `-` |

---

## 4. 速查表：我要做 X，挂哪个回调

| 需求 | 回调 | 注意 |
|---|---|---|
| 每局初始化、读存档 | `MC_POST_PLAYER_INIT` | 必须在 `loadData()` 之后才能用存档数据 |
| 读起始道具 | 第一间房的 `MC_POST_NEW_ROOM` / 出第一间房时 | `PLAYER_INIT` 时还没有 |
| 每进入一个房间拍快照 | `MC_POST_NEW_ROOM` | 别指望房间里有实体 |
| 清房即停计时 | `MC_PRE_SPAWN_CLEAN_AWARD` | 记时间戳，别扫实体 |
| 识别 Boss（含 mod Boss） | `MC_POST_NPC_INIT` | 用 `GetEntityTypeByName`，别硬编码 Type |
| 读 BossID（原版 Boss） | 清房回调里 | 进房瞬间是 0 |
| 改道具出现率 / 抽签 | `MC_POST_GET_COLLECTIBLE` | 只管池子；Morph/直给拦不到 |
| 兜住所有获得来源 | `MC_POST_ADD_COLLECTIBLE` | 会和改道具的 mod 打架 |
| 掉落物监控 | `MC_POST_PICKUP_INIT` / `MC_POST_PICKUP_UPDATE` | 每帧扫有性能代价 |
| 写盘 | `MC_PRE_GAME_EXIT` + 换层检查点 | 必须确认当前槽没变 |
| 每帧逻辑 / 采样 | `MC_POST_UPDATE` | 30 fps；暂停时帧数照样涨 |
| 画 HUD / 册子 | `MC_POST_RENDER` | 会被暂停菜单盖住 |
| 跨 mod 通信 | `MC_POST_MODS_LOADED` 之后 | 沙盒不能 `require` 别的 mod |

---

## 5. 这次的教训（写给下一个 agent）

1. **先确认真实时序，再写代码**。同一个 bug 我改了三次位置才对（自检、Boss 识别、起始道具）。
2. **pcall 失败必须打日志**。`rng:NextFloat()` 不存在这件事，因为静默 return 藏了好几天。
3. **回调名词≈触发时机**：`PRE_SPAWN_CLEAN_AWARD` 是"清房那一刻"，`POST_NEW_ROOM` 是"进房那一刻"。
   凡是"那一刻房间里有没有 X"，都要先问一遍。
4. **改完立刻自检**：能用假数据跑通的链路（如 `onPostGet`），就别等玩家运气触发。
