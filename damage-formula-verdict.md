# 以撒（Repentance 1.7.9）伤害 / 攻速公式核对结论

> 用途：这是"战力值"公式的事实底座。所有数值都可追溯到 wiki 原文，不要凭记忆改动。
> 结论状态：**已验证（VERIFIED）**，除注明"未解决"的条目。

## 1. 伤害（Damage）——非线性的，√ 曲线

```
有效伤害 = ( 角色基础 × √(普通伤害提升总数 × 1.2 + 1) + 平坦伤害提升 ) × 伤害乘区
```

- `角色基础`：以撒 = 3.50（角色自带倍率已折入）
- `普通伤害提升总数`：进 sqrt 池的那一类（大多数"伤害提升"道具）
- `平坦伤害提升`：**不进** sqrt 池，sqrt 之后相加（Curved Horn、Ipecac、Polyphemus 的 +4 等）
- `伤害乘区`：最外层相乘（Magic Mushroom ×1.5、Cricket's Head ×1.5 等）

验算（以撒 + n 个 +1 普通伤害提升）：

| n | 有效伤害 | 本次增量 |
|---|---|---|
| 0 | 3.50 | — |
| 1 | 3.5 × √2.2 = **5.191** | **+1.69** |
| 2 | 3.5 × √3.4 = 6.454 | +1.26 |
| 3 | 3.5 × √4.6 = 7.507 | +1.05 |
| 4 | 3.5 × √5.8 = 8.429 | +0.92 |

→ **伤害提升的百分比收益按 √n 衰减，这是游戏设计，不是采样噪声。**
→ 反解：`n ≈ ((Damage / 角色基础 / 乘区)² − 1) / 1.2`（有乘区时会失真，仅作粗估）

来源： <https://bindingofisaacrebirth.wiki.gg/wiki/Damage>

## 2. 攻速（Tears）——加速收益，硬顶 5.0 次/秒

```
TearDelay = 16 − 6 × √(1.3 × T + 1)        （Repentance 不向下取整）
攻速(次/秒) = 30 / (TearDelay + 1)
T >= T_max ≈ 1.816239316  →  TearDelay = 5  →  攻速 = 5.00（硬顶）
```

- 以撒初始：T = 0 → TearDelay = 10 → 30/11 = **2.727**（就是面板那个 2.73）
- 每 +0.35 的 tears up 换来的是 2.73 → 3.07 → 3.45 → 3.86 → 4.33 → 5.00：**递增**，然后到顶
- **攻速的可压缩空间只有 2.73 → 5.00（1.83 倍）**

来源： <https://bindingofisaacrebirth.wiki.gg/wiki/Fire_rate>

## 3. Lua API 里没有显示层换算函数

- `PlayerFormulas` / `CalculateDamage` / `CalculateTears` **不存在**（vanilla globals 列表无、`PlayerFormulas.html` 404、REPENTOGON sitemap 无）
- 含义：`player.Damage` 读出来**已经是曲线之后的值**（游戏每帧重算 cache），直接显示即可，不要自己再过一遍曲线
- `player.MaxFireDelay` 是帧数；显示必须换算成 `30/(MaxFireDelay+1)`
- 字段名注意：`TearRange`（不是 `Range`）；`TearsMultiplier` 不存在

来源： <https://wofsauge.github.io/IsaacDocs/rep/Globals.html> · <https://repentogon.com/sitemap.xml>

## 4. 形态分组用的系数（已查证，可直接标定）

| 形态 | 伤害口径 | 频率 |
|---|---|---|
| 普通泪弹 | 每次泪弹 = `Damage` | `30/(MaxFireDelay+1)`，再乘多弹幕数 |
| Brimstone | 每 tick = `Damage` | 每 4 帧一跳；持续时 `DPS = Damage × 攻速 / 5` |
| Tech X | `Damage` 的 25%→100%（随充能） | 每秒 15 跳 |
| Ludovico | = `Damage` | 每秒 15 跳，**完全不吃攻速** |
| Chocolate Milk | 10%→400%（随蓄力）；攻速≥120 时为 4× | 充能制，非固定节奏 |

来源： <https://bindingofisaacrebirth.wiki.gg/wiki/Brimstone> · [Tech_X](https://bindingofisaacrebirth.wiki.gg/wiki/Tech_X) · [Chocolate_Milk](https://bindingofisaacrebirth.wiki.gg/wiki/Chocolate_Milk) · [Damage](https://bindingofisaacrebirth.wiki.gg/wiki/Damage)

## 5. 对设计的硬含义

1. **"前期涨得猛"是机制**，固定数值道具的百分比收益必然按 √n 衰减 → 判定阈值不该全局固定，应按层/本局分布归一。
2. **输出战力 90% 的戏份在伤害**（伤害无上限，攻速 1.83 倍封顶）→ 卡片上应把两个因子都露出来，别只给一个 DPS。
3. **直读面板是对的做法**（"形态分组公式 + 直读 `player.Damage`"不需要重建曲线）。
4. **`player.Damage += X` 是平坦加伤，绕过曲线**——如果哪天要自己改属性，在高 n 下会明显强于原版道具，别用它来"模拟道具"。
5. `n`（伤害提升次数）**不由 API 暴露** → 若要做"等效道具数"表达，只能自己维护道具表或反解粗估。

## 6. 未解决

- isaacscript-common 的 `getTearsStat` 具体实现没读到（文档站截断 + 所有 CDN 不可达）——但上表公式已经足够，不必依赖它。
