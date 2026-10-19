# 临时 / 有状态伤害修正 — Lua 能观测到什么

目标版本：The Binding of Isaac: Repentance，Steam **1.7.9b** + **REPENTOGON 1.0.x**。
调研日期：2026-02（文档快照：IsaacDocs 的 rep 页面显示 "Last update: March 31 2026 / March 20 2025"；wiki.gg 为实时页面）。
下文所有内容均读自一手文档页或 wiki 页面。凡是无法打开验证的，都标注为 **未核实**。

访问说明：本机屏蔽了 `github.com` / `raw.githubusercontent.com` / `jsdelivr`，但
`https://gh-proxy.com/raw.githubusercontent.com/...` 和 `https://gh-proxy.com/codeload.github.com/...` 可用，
所以 GitHub 上的源码*确实*读到了（EID、Missing HUD 2）。`steamcommunity.com` 完全无法访问（Stats+ 以及只在 Steam 创意工坊发布的 mod 读不到）。

---

## 任务 1 — 临时效果 API（原版 1.7.9）

### 结论
`EntityPlayer:GetEffects()` **存在**，返回一个 **`TemporaryEffects`** 对象。该对象**没有** `numEffects` / `GetEffect` /
`GetEffectCount` / `HasEffect` / `AddEffect` / `RemoveEffect` / `GetEffectCooldown` —— 所有访问器都是*按类型区分的*
（Collectible / Null / Trinket）。要遍历，得先取到一个 `EffectList` 向量容器再按下标取元素。
**不存在** `PlayerEffect` 或 `TemporaryEffectTag` 枚举：效果是用现有的 `CollectibleType`、`NullItemID` 和 `TrinketType` 枚举来索引的。

### `TemporaryEffects` — 完整成员列表
由 `EntityPlayer:GetEffects()` 取得。

函数（共 17 个，名称与签名照抄）：

| 签名 | 说明 |
|---|---|
| `void AddCollectibleEffect(CollectibleType, boolean AddCostume = true, int Count = 1)` | 遵循 `items.xml` 里的 `cooldown`/`persistent` |
| `void AddNullEffect(NullItemID, boolean AddCostume = true, int Count = 1)` | |
| `void AddTrinketEffect(TrinketType, boolean AddCostume = true, int Count = 1)` | |
| `void ClearEffects()` | |
| `const TemporaryEffect GetCollectibleEffect(CollectibleType)` | |
| `int GetCollectibleEffectNum(CollectibleType)` | |
| `const EffectList GetEffectsList()` | 遍历的入口 |
| `const TemporaryEffect GetNullEffect(NullItemID)` | |
| `int GetNullEffectNum(NullItemID)` | |
| `const TemporaryEffect GetTrinketEffect(TrinketType)` | |
| `int GetTrinketEffectNum(TrinketType)` | |
| `boolean HasCollectibleEffect(CollectibleType)` | |
| `boolean HasNullEffect(NullItemID)` | |
| `boolean HasTrinketEffect(TrinketType)` | |
| `void RemoveCollectibleEffect(CollectibleType, int Count = 1)` | `Count = -1` 表示移除全部 |
| `void RemoveNullEffect(NullItemID, int Count = 1)` | `Count = -1` 表示移除全部 |
| `void RemoveTrinketEffect(TrinketType, int Count = 1)` | `Count = -1` 表示移除全部 |

来源：<https://wofsauge.github.io/IsaacDocs/rep/TemporaryEffects.html>

### `TemporaryEffect` — 完整成员列表
从上面三个 `Get*Effect()` 取回。**只有三个字段，没有任何方法：**

| 成员 | 类型 |
|---|---|
| `Cooldown` | `int` |
| `Count` | `int` |
| `Item` | `ItemConfig Item` |

来源：<https://wofsauge.github.io/IsaacDocs/rep/TemporaryEffect.html>
（该页没有说明 `Cooldown` 的语义 —— 它到底是"剩余帧数"还是"绝对帧号"，**未核实**；`items.xml` 的 `<cooldown>` 文档写的是
*"如果授予了该道具关联的 CollectibleEffect，这个属性表示在自动移除它之前要经过多少帧"* → <https://wofsauge.github.io/IsaacDocs/rep/xml/items.html>）

### `EffectList`（向量容器）
文档中的类名是 `EffectList`，来自 `TemporaryEffects:GetEffectsList()`：

* 运算符 `__len()` → `int` —— "返回列表中 TemporaryEffects 的数量"（所以 `#list` 可用）
* `TemporaryEffect Get(int idx)` —— 按下标取元素
* `const int Size` —— "列表中 TemporaryEffects 的数量"

来源：<https://wofsauge.github.io/IsaacDocs/rep/CppContainer_Vector_EffectList.html>
`Get(idx)` 的下标基准**没有文档**（**未核实**；先按 0 起试）。

### 遍历当前生效临时效果的、有文档依据的写法
```lua
local list = player:GetEffects():GetEffectsList()
for i = 0, list.Size - 1 do
    local e = list:Get(i)      -- TemporaryEffect
    -- e.Item.ID, e.Item.Type, e.Count, e.Cooldown
end
```
如果只关心某一个已知道具，最省事的判断是 `player:GetEffects():HasCollectibleEffect(id)`。
（真实代码中就是这么用的：EID，`features/eid_itemprediction.lua:629`。）

### TemporaryEffects 到底是什么（重要，出自文档原文）
文档里有一条明确的"Misinformation（常见误解）"警告：

> "TemporaryEffects 尽管名字如此，并不是、也从来不是被设计成道具的假副本或临时副本。特别是，每一个主动道具在使用时都会
> 自动授予它自己的 CollectibleEffect，而这往往与其效果紧密相关；因此 CollectibleEffects 更可以被看作一件道具的**状态**。"
> ……"像 Hemoptysis 和 Berserk! 这样的道具，仍然用 CollectibleEffects 来管理冷却。"
> "不要假设某件道具以 TemporaryEffect 形式生效时，会和真正获得它时表现得一样。"

所以这套系统是一个**逐道具的状态登记表**，而不是通用的"临时属性加成"列表。它由 `items.xml` 控制：
`<cooldown>`（多少帧后自动移除）与 `<persistent>`（"决定该道具关联的 CollectibleEffect 在房间之间切换时、以及在
保存并继续之后是否保留……默认 false"）。

同一页面列出了约 190 个带有值得注意的 CollectibleEffect 的被动物品。直接相关的有：
`Lusty Blood`（"效果每叠加一层就增加伤害；不会随击杀数增长"）、`Whore of Babylon`、
`Crown of Light`、`Experimental Treatment`（"属性变化按房间做种子"）、`Empty Vessel`、`Holy Mantle`、
`Mars`、`Astral Projection`。**Bloody Lust、Red Stew 以及 Tainted Samson 的狂暴都不在这份列表里。**

### REPENTOGON 在这块的补充
`repentogon.com/TemporaryEffects.html` 和 `repentogon.com/TemporaryEffect.html` **返回 HTTP 404** ——
它们不存在。REPENTOGON 的文档站（sitemap 共 282 个 URL，<https://repentogon.com/sitemap.xml>）没有这两个类的页面；
它们是原版类，REPENTOGON 没有重新文档化、也没有（据其文档）扩展它们。

REPENTOGON 真正新增的是 **`EntityPlayer`** 上的东西 —— 对 `TemporaryEffects` 的便利封装
（<https://repentogon.com/EntityPlayer.html>）：

| 签名 | 文档 |
|---|---|
| `void AddCollectibleEffect(CollectibleType, bool ApplyCostume = false, int Cooldown = VanillaCooldown, bool Additive = true)` | "这是 TemporaryEffects:AddCollectibleEffect 的快捷方式，额外提供了处理冷却的参数。additive 参数决定冷却值是被加到已有冷却值之上，还是直接设为该值。配合 additive 使用负的冷却值可以削减已有冷却。" |
| `void AddNullItemEffect(NullItemID, bool ApplyCostume = false, int Cooldown = VanillaCooldown, bool Additive = true)` | 同上 |
| `void AddTrinketEffect(TrinketType, bool ApplyCostume = false, int Cooldown = VanillaCooldown, bool Additive = true)` | 同上 |

它另外还加了 `AddCustomCacheTag(string OR {string,…}, boolean EvaluateItems = false)` 和
`float GetCustomCacheValue(string CustomCacheTag)`（"返回指定 CustomCacheTag 当前的缓存值。如果该 tag 从未被求值过，
默认返回 0"）—— 也就是说 mod 可以添加*自己的*缓存字段，但没有任何"列出所有属性贡献"的通用 API。

---

## 任务 2 — 那三件道具

### 2a. Red Stew —— `CollectibleType.COLLECTIBLE_RED_STEW` = **621**（被动，Repentance）

* 拾取时：**完全治疗**，并获得 **+21.6 临时伤害**，该加成在**约 3 分钟内衰减到 0**。
* 衰减是非线性的："起始约每半秒 -0.015，随着加成趋近 0 逐渐加快到每半秒约 -0.1"
  （这是伤害公式造成的结果，而不是在属性上挂了一个线性计时器）。
* **默认时长 = 5390 游戏帧**，"略短于 3 分钟"（在没有敌人死亡的情况下就是这个长度）。
* 生效期间它*还会*复制 Lusty Blood 的效果：每次击杀给一点伤害加成，且**跨房间、跨层保留**，
  直到 Red Stew 的加成彻底结束时才消失。这个击杀加成可能超过原本的 +21.6。
* Rock Bottom 会让它永久化。再拾取一个 Red Stew 会重置回满额。
* **不在** TemporaryEffects 的"值得注意的 CollectibleEffects"列表中 → 说明是硬编码实现，没有作为 `TemporaryEffect` 暴露。

来源：<https://bindingofisaacrebirth.wiki.gg/wiki/Red_Stew>

**读取 API（仅 REPENTOGON，已确认）：**
* `int EntityPlayer:GetRedStewBonusDuration()` —— "返回 Red Stew 的伤害加成失效前剩余的帧数。"
* `void EntityPlayer:SetRedStewBonusDuration(int Duration)` —— "把 Red Stew 收藏品提供的伤害加成时长设为指定帧数。
  若原本未激活，把时长设为大于 0 会激活该效果。"

来源：<https://repentogon.com/EntityPlayer.html>
这两个 getter 在原版 1.7.9 中都不存在（不在已记录的 249 个 `EntityPlayer` 函数中）。

### 2b. Bloody Lust —— `COLLECTIBLE_BLOODY_LUST` = **157**（被动，参孙的初始道具）

**任务里的前提是错的** —— 在忏悔中，Bloody Lust 是在**受到伤害**时触发，而不是击杀；并且它**按层**重置（不是按房间）：

* 忏悔中的数值：**首次受击 +0.5，之后每次额外受击 +0.2，到第六次受击时 +1.5。总计上限 +6.0。**
  第六次受击之后的伤害不再增加任何数值。
* （Antibirth/Afterbirth+ 的行为不同：前三次 +0.5，后三次 +33%。）
* 加成**保留整层**，进入新一层时重置。即使道具被移除，"怒气"等级也会保留到本层结束。
* 参孙的 **Birthright** 允许额外 4 次提升，间隔同样是 +0.2 → **上限 +14.0**。
* 计数上升时以撒会肉眼可见地变红。
* **不在** TemporaryEffects 列表中 → 硬编码，不是一个 `TemporaryEffect`。

来源：<https://bindingofisaacrebirth.wiki.gg/wiki/Bloody_Lust>

**不要和 Lusty Blood 混淆 —— `COLLECTIBLE_LUSTY_BLOOD` = 411**（Afterbirth）：每次击杀 +0.5 伤害，
**按房间**，杀 10 个后上限 +5.0。那个*确实*被列为 TemporaryEffect（"效果每叠加一层就增加伤害"），
也就是 `GetEffects():GetCollectibleEffectNum(411)` 反映的是叠层数。
来源：<https://bindingofisaacrebirth.wiki.gg/wiki/Lusty_Blood> 以及上面那个 TemporaryEffects 页面。

**读取 API：** 原版 —— **没有**（不存在 `GetBloodyLustDamage`；计数器是内部的）。
**仅 REPENTOGON：** `int EntityPlayer:GetBloodLustCounter()` 与 `void SetBloodLustCounter(int Counter)`
（<https://repentogon.com/EntityPlayer.html>）。文档页给了签名，但**没有说明取值范围/单位** ——
它返回的是 0–6 的受击次数还是原始伤害值，**未核实**。按实理应理解为受击计数器（0–6，有 Birthright 时 0–10）；需在游戏内确认。

### 2c. Tainted Samson 的狂暴 —— `PlayerType.PLAYERTYPE_SAMSON_B`（Tainted Samson）

**触发：** "每当 Tainted Samson 造成或受到伤害，他会逐渐变得更红。达到某个临界点后，他会激活 Berserk!"。
需要**基础累计造成 120 点伤害，之后每层 +40；受到伤害则计入所需总量的 10%**。
（道具 `Berserk!` = 704 是等价的可主动使用版本；充能方式相同，但忽略受到的伤害。）

**时长：** 起始 **5 秒**，狂暴期间每次击杀 **+1 秒**（有 Birthright 时 +3 秒）。计时显示在他头顶。
**跨房间保留。** 狂暴期间他不会死亡（可以停在 0 红心）。

**狂暴期间被修改的属性：**

| 效果 | 数值 |
|---|---|
| 速度 | **+0.40** 固定值（并且每次击杀**再 +0.40**，直到结束） |
| 伤害 | **+3** 固定值 |
| 射速 | 泪延迟做 **×0.5 再 +2** 的改动（除非射速已 ≥ 4，否则表现为射速*提升*） |
| 武器 | 眼泪被替换成**下颌骨近战武器**（Forgotten 风格）：每次挥击 **3× 伤害属性**，投掷时每跳 **1.5×**；挥击可反弹敌方子弹 |
| 其他 | 近战命中（约 0.25 秒）与击杀时有短暂无敌；狂暴期间不会死亡 |

来源：<https://bindingofisaacrebirth.wiki.gg/wiki/Tainted_Samson>、
<https://bindingofisaacrebirth.wiki.gg/wiki/Berserk!>

**它算临时效果，还是玩家状态标志？** 就已有文档的 API 而言，两者都不是：
* 它**不是** `TemporaryEffect`（没有为它列出任何 `CollectibleEffect`，而 `PlayerForm` 里也没有狂暴项 ——
  该枚举是 Guppy…Flight，共 15 个值，<https://wofsauge.github.io/IsaacDocs/rep/enums/PlayerForm.html>）。
* 它也**没有**暴露成布尔型的玩家字段：已记录的 28 个 `EntityPlayer` 变量中**不**包含
  `Berserk`/`IsBerserk` 之类的东西（<https://wofsauge.github.io/IsaacDocs/rep/EntityPlayer.html>）。
* 唯一有文档的抓手是**充能值**：`int EntityPlayer.SamsonBerserkCharge` ——
  "由 Tainted Samson 内部使用，根据造成的伤害增长，**范围为 0-100000**"。注意这个*充能值*上限是 100000，
  它并不能说明狂暴当前是否**激活**。
* REPENTOGON 的 `EntityPlayer` 页面（新增 300 个函数）里**没有** `IsBerserk`，也完全没有提到 "Berserk"。
→ **目前没有已记录的方法能读取"Tainted Samson 此刻是否处于狂暴"。** 以下候选绕法均**未核实**，必须在游戏内实测：
(a) `GetEffects():HasCollectibleEffect(704)` —— 文档确实说 Berserk! "仍然用 CollectibleEffects 管理冷却"，
这暗示主动道具版本会留下一个 collectible effect；(b) `HasWeaponType(...)` —— 但 `WeaponType`
没有 jawbone/berserk 成员（<https://wofsauge.github.io/IsaacDocs/rep/enums/WeaponType.html>）；
(c) 激活后 `SamsonBerserkCharge` 立刻掉到 0（推测，无文档）。

---

## 任务 3 — 哪些读取 API 真的存在

完整过了一遍原版 `EntityPlayer` 页面：**249 个函数、28 个变量**
（<https://wofsauge.github.io/IsaacDocs/rep/EntityPlayer.html>）。

| 询问的 API | 是否存在 | 确切名称 / 说明 |
|---|---|---|
| `GetEffects` | **是** | `TemporaryEffects GetEffects()` |
| `IsBerserk` | **否** | 原版文档中没有，REPENTOGON 新增的 300 个函数中也没有 |
| `GetBloodyLustDamage` | **否**（原版） | REPENTOGON：`int GetBloodLustCounter()` / `SetBloodLustCounter(int)` |
| 类似 `GetTemporaryDamage` 的东西 | **否**，没有通用的；只有 REPENTOGON 的部分访问器 | `int GetDamageModifier()` —— "用于 Experimental Treatment 以及 Void 带来的属性增益。该修饰值以固定伤害的形式加到玩家身上。Experimental Treatment 会加 -1、0 或 1……Void 可能随机加 1。"；`float GetStatMultiplier()` —— "返回作用于任何道具所得属性之上的乘数。乘数：Tainted Bethany ×0.75，Cracked Crown ×1.2"；`float GetRockBottomDamage()`；`float GetD8DamageModifier()`；`float GetEdenDamage()`（Eden 的随机基础偏移）；`int GetRedStewBonusDuration()`；`int GetBloodLustCounter()`；`float GetCustomCacheValue(string)` |
| `GetCacheFlags` | **否** —— 没有这个 getter | 只有 `void AddCacheFlags(CacheFlag)`："提供的缓存标志会在下一次缓存重算时被重新计算。" |
| `AddCacheFlags` | **是** | 见上 |
| `EvaluateItems` | **是** | `void EvaluateItems()` —— "触发一次缓存重算，会触发 MC_EVALUATE_CACHE 回调。使用此函数前，需要先设置好相应的缓存标志。" |
| 其他"非永久贡献"的读法 | | `void ClearTemporaryEffects()` —— 文档文字："玩家离开房间时会被调用。"（也就是说它会清空 TemporaryEffects 列表；没有任何按效果给出 delta 的 API） |
| 相关的其他 API | | `CollectibleType GetItemState()`（存在，**语义无文档**）、`boolean HasTimedItem()`（"第一个主动栏位里是定时主动道具，比如 Brown Nugget"）、`boolean HasPlayerForm(PlayerForm)`、`int GetCollectibleNum(CollectibleType)`、`boolean HasCollectible(CollectibleType)` |

`CacheFlag` 枚举（16 个成员，<https://wofsauge.github.io/IsaacDocs/rep/enums/CacheFlag.html>）：
`CACHE_DAMAGE, CACHE_FIREDELAY, CACHE_SHOTSPEED, CACHE_RANGE, CACHE_SPEED, CACHE_TEARFLAG, CACHE_TEARCOLOR,
CACHE_FLYING, CACHE_WEAPON, CACHE_FAMILIARS, CACHE_LUCK, CACHE_SIZE, CACHE_COLOR, CACHE_PICKUP_VISION,
CACHE_ALL, CACHE_TWIN_SYNC`。

`MC_EVALUATE_CACHE`（<https://wofsauge.github.io/IsaacDocs/rep/enums/ModCallbacks.html>）：
参数 `(EntityPlayer, CacheFlag)`，返回 `void`。
> "当玩家属性被重算时被调用一次或多次。例如，玩家拾取提供属性的收藏品、或使用属性药丸之后会触发。可选参数可用于指定
> 一个 CacheFlag；它必须是单个 CacheFlag，两个或更多 CacheFlag 的组合不会生效。……需要实现任何改变玩家属性、跟班、
> 飞行、武器等等的逻辑时，用这个回调。"

至于属性字段本身，`EntityPlayer.Damage`（`float`）的文档写着：
"**玩家属性——只应在 MC_EVALUATE_CACHE 的回调里修改。**"它等于伤害属性。

### mod 能不能"按需重算"以拿到一个干净的值？
机制上可以 —— `AddCacheFlags(CacheFlag.CACHE_DAMAGE)` + `EvaluateItems()` 会强制做一次完整重算，
并且 `MC_EVALUATE_CACHE` 会触发。但**这并不能给你一个"干净"的数字**：缓存求值会重新应用*所有*贡献，
包括临时的那部分，所以重算之后读到的还是同一个被加成过的值。引擎没有"只看基础伤害"的访问器。
wiki 也印证了这是同一个被持续重算的数字："伤害属性是持续重算的，而伤害乘数会与最终结果相乘"
（<https://bindingofisaacrebirth.wiki.gg/wiki/Damage>）。另外，没有任何文档说明属性在求值前会被重置为基础值 ——
这一点**未核实**，而且无论如何都没用，因为原版道具加成在任何 mod 回调运行之前就已经应用了。
反推公式（如果你想按游戏的方式显示某个属性会用到）在同一张 wiki 页面上：
`Bonus = (1/1.2)·[((EffectiveDamage/Multipliers − FlatDmgUps)/CharBaseDmg)² − 1]`。

---

## 任务 4 — 现有的属性显示 mod 是怎么做的

**Missing HUD 2**（C++/OpenGL 覆盖层，直接读游戏内存 —— 不是 Lua mod）：
> "与其他基于统计的 mod 不同，它在跑局中使用你**实时的角色属性**。这意味着即使拾取了 Experimental Treatment、
> Libra 这类道具，Missing HUD 2 仍保持 100% 准确。"
> "实时显示你的**原始属性**在你拾取道具和使用药丸时如何变化。"

→ 它读的是**缓存求值后的最终值**（和 `player.Damage` 等是同一批数字），**不会**拆出一行"+X 临时"。
它也没有临时/永久的概念 —— 它说的"原始属性"指的是*未取整/未显示*，而不是*未加成*。
来源：<https://gh-proxy.com/raw.githubusercontent.com/dparamoshkin/missinghud2/master/README.md>
（镜像自 <https://github.com/dparamoshkin/missinghud2>；原仓库 <https://github.com/networkMe/missinghud2>）

**External Item Descriptions (EID)** —— 我唯一能完整读到的较大型 Lua mod：
* 它直接读 `player.Damage` / `player.MoveSpeed` / `player.MaxFireDelay` / `player.TearRange`，
  再把它们*反向*代入伤害公式，算出一个用于显示的数值
  （`features/eid_modifiers.lua:466`：`playerStats[3] = EID:SimpleRound(((player.Damage^0.56)*2.231179) - 2)`）。
  → 同样是被加成后的值，没有临时/永久拆分。
* 在需要关心临时道具状态的地方，它用的是带类型的 TemporaryEffects API，例如
  `features/eid_itemprediction.lua:629`：`if player:GetEffects():HasCollectibleEffect(tempItem) then …` ——
  用来预测 Liberty Cap / Broken Syringe / Mom's Lock 的结果。
来源：<https://gh-proxy.com/codeload.github.com/wofsauge/External-Item-Descriptions/zip/refs/heads/master>
（仓库 <https://github.com/wofsauge/External-Item-Descriptions>）

**Stats+ / Isaac Run Logger** —— **未核实**。Stats+ 看起来只有 Steam 创意工坊版本（没找到 GitHub 仓库；
`steamcommunity.com`、`catalogue.smods.ru`、`goodmods.info` 在本机都返回 403 或被屏蔽），而 "Isaac Run Logger"
这个名字对不上任何我能确认的仓库（最接近的 `aymericingargiola/repentance-run-tracker` 是一个外部桌面应用，
不是 Lua mod）。不要相信任何关于它们内部实现的说法。

### 综合得出的最佳实践结论
每一个我能核实的属性显示，都是读**那个已经被求值过的单一属性值**并把它显示出来。没有一个会把它通用地拆成
"永久贡献 + 临时贡献"，因为引擎根本不暴露这种拆分。mod 唯一能精确的地方是逐道具的：用专用访问器
（`GetRedStewBonusDuration`、`GetBloodLustCounter`）或 TemporaryEffects 登记表（仅对恰好注册了
`CollectibleEffect` 的道具有效）。

---

## 建议 —— 从最便宜到最贵（5 条）

1. **零成本：** 把 `player.Damage`（在 `MC_EVALUATE_CACHE`/`MC_POST_PEFFECT_UPDATE` 里采样）当作"实时值"，
   并与你自己记录的*永久*基线做差（基线只在 `MC_POST_NEW_LEVEL`、道具增删、`MC_POST_PICKUP_INIT` 时重算）——
   能标出"有临时效果在生效"，但标不出*是哪个*。
2. **便宜且对那 3 件道具是精确的：** 调用 REPENTOGON 的 `GetRedStewBonusDuration() > 0` 和 `GetBloodLustCounter() > 0`；
   都是一行代码，并且能给出 Red Stew 剩余帧数、Bloody Lust 受击次数的真实量级。
3. **便宜、近似通用：** 遍历 `GetEffects():GetEffectsList()`，把每个 `TemporaryEffect`（`Item.ID`、`Count`、
   `Cooldown`）作为*单独的*一行"+X 来自某效果"报出来 —— 但它只覆盖注册了 CollectibleEffect 的道具
   （约 190 个被动 + 主动道具状态）；会静默漏掉 Bloody Lust、Red Stew 和狂暴。
4. **中等成本：** 对你 mod 关心的那些有状态道具逐个显式采样（`SamsonBerserkCharge` 取狂暴充能，
   以及 REPENTOGON 的逐道具 getter `GetRockBottomDamage`/`GetD8DamageModifier`/`GetEdenDamage`/
   `GetStatMultiplier`/`GetDamageModifier`），在实时属性旁边以带注释的"+temp"小块展示。
5. **做不到：** **你无法通用地观测到这一点。** 原版 1.7.9 没有暴露"当前临时属性贡献"，没有 `IsBerserk`，
   没有缓存标志的 getter，也没有干净的基础属性值；REPENTOGON 只是用逐道具的 getter 补上了一部分缺口。
   HUD 应设计成"实时值 + 逐道具注释"，并且在实测找到代理信号之前，把 Tainted Samson 的狂暴激活状态视为不可读。
