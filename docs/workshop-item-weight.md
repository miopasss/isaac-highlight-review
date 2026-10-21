# 创意工坊发布文案 · 道具权重调节器

> 复制即用。Steam 发布页分三个字段，下面第 1 / 2 / 3 节分别对应。
> 预览图：`docs/img/rating-editor.png`（1600×900，16:9）

---

## 1. 标题（Title）

```
道具权重调节器 · Item Weight Tuner
```

备选标题：

- `别再出超模道具了 · Item Weight Tuner`
- `道具权重调节器（可自定义每个道具的出现率）`

---

## 2. 简介（列表页只看得到这段，约两行）

```
不想再被超模道具毁掉一局？给任意道具单独调一个出现频率，
从「照常出现」到「永不出现」，你说了算。
```

---

## 3. 详细说明（Description）

```markdown
不想再被超模道具毁掉一局？
给任意道具单独调一个出现频率，从「照常出现」到「永不出现」，你说了算。

━━━━━━━━━━━━━━━━━━━━

【你大概遇到过这些】

· 某个 mod 的道具强到离谱（比如东方 mod 的交易所门票），拿到就通关，没拿到就受苦
· 某些 mod 组合总能凑出同一套无敌打法，玩十局像玩一局
· 想玩得花一点，但随机性不给你机会

这是个很尴尬的局面：不是 mod 做得不好，是它们太强，强到把别的都压平了。

这个 mod 就是来收拾这个局面的——给每个道具单独设一个出现频率。

━━━━━━━━━━━━━━━━━━━━

【它能做什么】

在游戏从道具池里抽出道具的那一刻介入，按你设的频率决定"保留"还是"重掷"。

  0.00  →  永不出现
  0.50  →  出现率减半
  1.00  →  照常（不改动）

调完之后进下一间房就生效。

只影响之后的抽取，不会动你身上已有的道具。

━━━━━━━━━━━━━━━━━━━━

【怎么用】

按 F6（可改）打开面板，三个入口并列：

· 搜索 —— 输入数字按 id 找，输入字母按英文名找
· 已获得道具 —— 只列你身上有的，点一下就能改
· 已修改 —— 已经调过的，点一下继续改

改完点「保存修改」，写进存档。

没点保存就关游戏，改动会丢（按钮上会出现一个星号提醒你）。

━━━━━━━━━━━━━━━━━━━━

【它是怎么工作的】

游戏给你一件道具，实际上是三步：

  ① 从池子里抽出结果  →  ② 决定发给你  →  ③ 你拿到手
                     ↑
               我们在这里插一脚

具体来说：
1. 游戏从池子里已经抽出了某个道具
2. 我们看一眼你给它的权重
   1.00 → 什么都不做，直接放行
   0.50 → 一半机会否掉它
   0.00 → 每次都否掉它
3. 被否掉时，我们让池子重新抽一次，把结果换成另一个道具
4. 游戏把最终结果发给你

我们不修改任何东西——不改道具池文件、不改道具属性、不改别的 mod 的数据。
只在这一刻决定"这一次要不要"。

━━━━━━━━━━━━━━━━━━━━

【因此你会看到这些行为】

· 设 0.5 不是"数量减半"，而是"每次一半机会被换掉" —— 效果是概率性的
· 设 0.00 的道具再也不会出现 —— 每次都被换掉，等于从池子里摘除
· 给很多道具设低权重后"好像刷不到东西了" —— 池子在反复重抽，这是预期结果
· 重掷只会在同一个池子里发生 —— 宝箱房的道具不会变成恶魔房的

━━━━━━━━━━━━━━━━━━━━

【和别的 mod 一起用】

因为我们在"抽道具"这个环节介入，同样介入这一环节的 mod 可能互相影响
—— 比如其他改掉率、改道具池、重定向池子的 mod。

遇到异常时，按这个顺序排查：
1. 先只留本 mod，看问题还在不在
2. 再把其他 mod 一个个开回来
3. 定位到冲突后，把还装了哪些 mod 告诉我，我尽量适配

单纯"新增道具"的 mod 不会冲突 —— 我们不碰它们的数据。
只有会改道具池的 mod 才可能撞车。

已实测共存的 mod：
· 天界呼唤（Heaven's Call）
· 东方系列
· 塔菲的宇宙
· 明日方舟

━━━━━━━━━━━━━━━━━━━━

【顺带：给道具打分】

除了频率，还能给每个道具打 0.00 ~ 4.99 的评级。

这个分数本身不影响游戏，但配套的「高光回顾」会用它来判断
"本局拿到了几个四级道具"。

（不装高光回顾也完全没问题，打分功能独立可用。）

━━━━━━━━━━━━━━━━━━━━

【已知限制】

· 只能降低，不能提高出现率（填 > 1 会提示暂不生效）
  原因：池子每次只给一个道具，"提高 A" 必然是从别的道具那里抢来的，
  两个道具都填 2.0 就等于都没变。提高需要另一套权重模型。
· 频率按存档槽保存，三个槽互不相通
· 对「书套」这类随机多发弹幕的道具，战力会在两档间跳，这是原版行为

━━━━━━━━━━━━━━━━━━━━

【依赖】

· The Binding of Isaac: Repentance（忏悔）
· REPENTOGON

目前只在忏悔版本测试过。

━━━━━━━━━━━━━━━━━━━━

【常见问题】

Q：设成 0 了，为什么还见过它？
A：① 改动前它已经出现过；② 那是"必定给你"的位置（初始道具、某些奖励）；
   ③ 权重没保存——看一眼按钮上有没有星号。

Q：会影响成就和进度吗？
A：不会。我们只换抽取结果，不动解锁、成就、完成度这些逻辑。

Q：能提高出现率吗？
A：这个版本不行，见上面「已知限制」。

Q：Why no English? / Is there an English UI?
A：界面暂时只有中文，英文说明见下方。

━━━━━━━━━━━━━━━━━━━━

【English】

Tired of over-powered items ending your runs, or the same invincible combo
showing up every game?

Item Weight Tuner lets you set a drop frequency for any collectible:
  0.00 = never appears
  0.50 = half as often
  1.00 = unchanged

Press F6 (rebindable), pick an item (search by name or id, or choose from what
you currently hold), set its weight, then hit Save. Takes effect from the next
room.

How it works: the game already rolled the item; we decide whether to reject it
and ask the pool to roll again. Nothing is modified — no pool files, no item
stats, no other mod's data.

Note: weights can only be LOWERED in this version. Raising a drop rate requires
a different weighting model (a fixed pool hands out one item, so "raise A"
always means "lower everything else").

Also lets you rate items 0.00-4.99, which the companion mod "Highlight Review"
uses for its tier-4 item count.

Requires Repentance + REPENTOGON.
Tested alongside Heaven's Call, the Touhou mods, 塔菲的宇宙 and 明日方舟.
```

---

## 4. 发布页其它字段

| 字段 | 填什么 |
|---|---|
| 分类 | **Mods** → Gameplay |
| 标签 | `Gameplay`、`Items`、`Tweaks` |
| 需要 DLC | **The Binding of Isaac: Repentance** |
| 前置 | REPENTOGON（写在说明里即可） |
| 预览图 | `docs/img/rating-editor.png`（1600×900） |
| 可见性 | Public |
| 变更说明 | 首版，见文末 |

---

## 5. 发布前自检

- [ ] mod 目录名是 `highlight-rating`（`metadata.xml` 里的 `<directory>`）
- [ ] `metadata.xml` 的 `name` / `version` / `description` 已填
- [ ] 打包只含 mod 本体：**不带** `tools/`、`tests/`、`docs/`、`_logs/`、`*.md`
- [ ] 至少 1 张 16:9 预览图
- [ ] 说明里"只能降低"这句还在（别删，能挡掉大量提问）
- [ ] 自己进游戏按一次 F6 确认能开

---

## 6. 首版更新日志（可贴「变更说明」）

```
v0.1.0 首次发布

· 支持给任意道具设置出现权重（0.00 永不出现 ~ 1.00 照常）
· F6 打开面板：搜索 / 已获得道具 / 已修改 三个入口
· 支持给道具打分（0.00 ~ 4.99），可与「高光回顾」联动
· 设置界面可重绑热键
· 已实测与天界呼唤、东方系列、塔菲的宇宙、明日方舟共存
```
