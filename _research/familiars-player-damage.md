# 与主人面板伤害挂钩的宝宝/召唤物（Repentance 1.7.9）

基准：主人 Damage = 3.5、Fire Rate = 2.727 次/秒（MaxFireDelay 10）→ 基础 DPS 9.545。
所有数字取自 bindingofisaacrebirth.wiki.gg 原文；wiki 没写的标 **wiki未给出**，不做推测填充。

## A. 吃 player.Damage 的（可用于等效 DPS）

| 中文名 / 英文名 / id | 伤害来源 | 每发倍率 | 发数 | 射速 | 吃主人 tears/伤害加成 | 备注 | source |
|---|---|---|---|---|---|---|---|
| 魅魔 / **Incubus** / 360（5.100.360） | 复制主人的泪；Repentance 起非 Lilith 角色 **-25%** | **0.75**（Lilith / 双生莉莉丝 1.0）→ 基准 2.625/发 | 1（wiki 未给发数细节） | wiki未给出；Forgotten Lullaby 翻倍后会"比主人快"，可推基线≈主人频率（推断） | 是（伤害、泪效果全跟随） | BFFS! → 1.5× 主人伤害（Lilith 2×）；Conjoined 素材 | [Incubus](https://bindingofisaacrebirth.wiki.gg/wiki/Incubus) |
| 双生宝 / **Twisted Pair** / 698（5.100.698） | 用主人 tears/range/shot speed/泪效果，每只 **0.375×** 伤害 | **0.375 ×2 只 = 合计 0.75**（Lilith 0.5×2=1.0）→ 基准 1.3125/发/只 | 2 只 | wiki未给出（只写"总 DPS 提升与 Incubus 相同"） | 是 | BFFS! 双倍；与 Incubus 几乎等价（wiki 明说） | [Twisted Pair](https://bindingofisaacrebirth.wiki.gg/wiki/Twisted_Pair) |
| 三宝宝变身（**不是宝宝**）/ **Conjoined** / 变身 id 7 | 主人本体的泪，无独立数值 | **1.0**（wiki 无额外倍率） | 每次多 2 颗斜向（合计 3 个方向，同 The Wiz） | 与主人同频 | 是（它就是主人的泪） | 代价 **-0.3 damage / -0.3 tears**；宠物宝宝本身不因此变强 | [Conjoined](https://bindingofisaacrebirth.wiki.gg/wiki/Conjoined) |
| 喷头 / **Sprinkler** / 516 | "tears copy Isaac's stats"，即 1× 面板 | **1.0**（wiki 只写 copy stats；Tech X 环明写 100%） | 单发，沿 8 个方向旋转发射（Loki's Horns→4 方向同发） | 取决于 tears 属性（wiki未给出数值） | 是 | 主动 4 格；BFFS! 只变大不加伤害；Mom's Knife 1.5×；不复制部分泪效果 | [Sprinkler](https://bindingofisaacrebirth.wiki.gg/wiki/Sprinkler) |
| 苍蝇爸爸 / **Papa Fly** / 430（5.100.430） | "Papa Fly's tears deal Isaac's damage" | **1.0** → 3.5/发 | 1 | **固定 1 次/秒** | 是 | 跟随主人有 0.66s 延迟（Rep） | [Papa Fly](https://bindingofisaacrebirth.wiki.gg/wiki/Papa_Fly) |
| 命运的馈赠 / **Fate's Reward** / 361（5.100.361） | "same damage and tear effects as Isaac's tears" | **1.0** → 3.5/发 | 1（20/20 等不加发数） | **固定 0.68 次/秒**（各 familiar 常规 1.36/s 的一半） | 是（含泪效果） | 不吃 range/tear height；只发单发 | [Fate's Reward](https://bindingofisaacrebirth.wiki.gg/wiki/Fate%27s_Reward) |
| 腐烂宝宝 / **Rotten Baby** / 268 | 本体不射击，刷蓝蝇；**蓝蝇 = 2× 主人当前泪伤害** | **2.0**（蓝蝇）→ 7/次 | 同时只有 1 只蝇 | 主人按住开火键时刷（wiki未给出具体频率） | 是（蓝蝇吃 damage） | 蝇自动锁敌；Hive Mind 翻倍 | [Rotten Baby](https://bindingofisaacrebirth.wiki.gg/wiki/Rotten_Baby) + [Familiar](https://bindingofisaacrebirth.wiki.gg/wiki/Familiar) |
| 格洛 / **Gello** / 728 | 用主人 damage/tears/range/shot speed/泪效果，然后 **0.75×** | **0.75**（Lilith / 双生莉莉丝 1.0）→ 2.625/发 | 1 | 主人开火时自动开火（同步） | 是（全套属性跟随） | 主动 2 格、仅本房间；甩出时 3× 伤害穿透；蓄力类自动满蓄释放；文件里叫 `umbilical_baby` | [Gello](https://bindingofisaacrebirth.wiki.gg/wiki/Gello) |
| 小谵妄 / **Lil Delirium** / 519 | 变成别的 familiar，伤害同该 familiar | 取决于形态（变 Incubus 时 0.75） | 1 | 每 10 秒换形态 | 部分（随形态） | 无接触伤害；可变成 Incubus/Robo-Baby 2.0/Rotten Baby/Lil Loki 等 | [Lil Delirium](https://bindingofisaacrebirth.wiki.gg/wiki/Lil_Delirium) |
| 蒙哥宝宝 / **Mongo Baby** / 322 | 复制指定 familiar 的泪；无 familiar 时固定 3.5 | 取决于被复制对象 | 1 | **2.73 次/秒**（Rep，= 主人基础射速） | 部分 | 只复制 Bro.Bobby/Sis.Maggy/Lil Steven/Robo-Baby/Rotten Baby 等；不复制 Seraphim、Buddy in a Box | [Mongo Baby](https://bindingofisaacrebirth.wiki.gg/wiki/Mongo_Baby) |
| 亡魂（饰品）/ **Found Soul** / trinket 180 | 用主人 damage/tears/泪效果，**0.5×** | **0.5**（+Golden Trinket 或 Mom's Box → 0.75；两者都有 → 1.0）→ 1.75/发 | 1 | 用主人 tears | 是 | 受伤即死、下层复活；BFFS! 无效 | [Found Soul](https://bindingofisaacrebirth.wiki.gg/wiki/Found_Soul) |

## B. 固定伤害（对我们没用，排除用）

| 中文名 / 英文名 / id | 伤害来源（固定值） | 每发倍率 | 发数 | 射速 | 吃主人加成 | 备注 | source |
|---|---|---|---|---|---|---|---|
| 小洛基 / **Lil Loki** / 435 | **固定 3.5** | 0 | 十字 4 颗（4 颗全中 14） | 每 **0.75 秒** 1 次（Rep） | 否 | — | [Lil Loki](https://bindingofisaacrebirth.wiki.gg/wiki/Lil_Loki) |
| **Robo-Baby 2.0** / 267 | **固定 3.5**（Technology 激光） | 0 | 1 | wiki未给出（对准才开火） | 否 | 随主人开火方向移动 | [Robo-Baby 2.0](https://bindingofisaacrebirth.wiki.gg/wiki/Robo-Baby_2.0) |
| 兄弟鲍比 / **Brother Bobby** / 8 | **固定 3.5** | 0 | 1 | **1.88 次/秒**（Rep） | 否 | Rep 起射速高于 Sister Maggy | [Brother Bobby](https://bindingofisaacrebirth.wiki.gg/wiki/Brother_Bobby) |
| 玛吉修女 / **Sister Maggy** / 67 | **固定 6** | 0 | 1 | **1.36 次/秒**（Rep） | 否 | Rep 起改成高伤低射速 | [Sister Maggy](https://bindingofisaacrebirth.wiki.gg/wiki/Sister_Maggy) |
| 小史蒂文 / **Little Steven** / 100 | **固定 3.5**（追踪） | 0 | 1 | **1.36 次/秒**（Rep） | 否 | 追踪泪 | [Little Steven](https://bindingofisaacrebirth.wiki.gg/wiki/Little_Steven) |
| 女魅魔 / **Succubus** / 417 | 光环 **固定 2.5/ tick**，约 **7.5–10/秒** | 0（光环）；对主人是 **1.5× 伤害倍率** | 光环持续 tick | 约 7.5–10 伤害/秒 | 否（光环不吃；但给主人 1.5×） | 站光环里主人所有泪 ×1.5，可叠加 | [Succubus](https://bindingofisaacrebirth.wiki.gg/wiki/Succubus) |
| 小阿巴顿 / **Lil Abaddon** / 679 | **固定 3.5 / tick**，每环最多 15 tick = **52.5** | 0 | 1 环 | 蓄力 1 秒 + 持续 1 秒 | 否 | BFFS! 伤害翻倍、范围变大 | [Lil Abaddon](https://bindingofisaacrebirth.wiki.gg/wiki/Lil_Abaddon) |
| **Hushy** / 470 | 接触 **2/tick**，合计 **30 DPS** | 0 | — | 持续接触 | 否 | Repentance+ 才有弹幕环（8 颗 × 6 伤害，每 1.033s）；1.7.9 没有 | [Hushy](https://bindingofisaacrebirth.wiki.gg/wiki/Hushy) |
| 盒子里的伙伴 / **Buddy in a Box** / 518 | **固定 2–6**（不随主人） | 0 | 1 | tear delay 12–30（约 2–5 次/秒） | 否 | 每层重掷外观/数值/泪效果 | [Buddy in a Box](https://bindingofisaacrebirth.wiki.gg/wiki/Buddy_in_a_Box) |
| 宝宝王 / **King Baby** / 472 | wiki未给出任何伤害数值；本身不发射 | — | 0 | — | — | 纯行为改件：主人开火时它停下，其它 familiar 也停下；Rep 改为自动索敌开火 | [King Baby](https://bindingofisaacrebirth.wiki.gg/wiki/King_Baby) |
| 多普 / 邪恶化身 / **Dople / Evil Twin**（怪物 id 53，变体 1） | **不是宝宝，是敌人**；血弹伤害 wiki未给出 | — | Dople 1 发 / Evil Twin 3 发散射 | 与主人同频（Dople；上限 15） | — | 只有主人开火才开火；低 tears 时极危险 | [Dople](https://bindingofisaacrebirth.wiki.gg/wiki/Dople) |
| 稻草人 / **Strawman** / 667 | **不是宝宝**：召唤可操控的 Keeper（第二角色，用**自己**的属性） | 不适用（不吃主人面板） | — | 自己射速 | 否 | 文件里标为 familiar，但 BFFS!/Box of Friends 无效 | [Strawman](https://bindingofisaacrebirth.wiki.gg/wiki/Strawman) |

## 0.75 是谁

wiki 全站 `insource:"0.75x"` 只有 8 条命中，涉及宝宝的只有 **Gello**；`insource:"75% of Isaac"` 只有 C Section（不是宝宝）。所以：

1. **Gello（格洛，728）** —— wiki 原文 "Gello's tears deal **0.75x** Isaac's damage"，且明写用它主人的 damage/tears/range/shot speed/泪效果 = "跟主人发一样的眼泪"。**同时满足两个条件的只有它。**
2. **Incubus（魅魔，360）** —— "伤害 -25%" = 0.75×，但**只在非 Lilith 角色**；Lilith/双生莉莉丝本人是 1.0。
3. 区分方法：Gello 是 2 格充能主动、只在本房间、用脐带挂在主人身上；Incubus 是永久被动宝宝。
