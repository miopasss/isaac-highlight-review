# Temporary / stateful damage modifiers — what Lua can observe

Target: The Binding of Isaac: Repentance, Steam **1.7.9b** + **REPENTOGON 1.0.x**.
Research date: 2026-02 (docs snapshot: IsaacDocs rep pages "Last update: March 31 2026 / March 20 2025"; wiki.gg live).
Everything below is read from a primary doc page or wiki page. Anything I could not open is marked **UNVERIFIED**.

Access note: `github.com` / `raw.githubusercontent.com` / `jsdelivr` are blocked from this machine, but
`https://gh-proxy.com/raw.githubusercontent.com/...` and `https://gh-proxy.com/codeload.github.com/...` work,
so GitHub sources *were* read (EID, Missing HUD 2). `steamcommunity.com` is fully blocked (Stats+ and
Steam-Workshop-only mods could not be read).

---

## Task 1 — Temporary-effects API (vanilla 1.7.9)

### VERDICT
`EntityPlayer:GetEffects()` **exists** and returns a **`TemporaryEffects`** object. That object does **not**
have `numEffects` / `GetEffect` / `GetEffectCount` / `HasEffect` / `AddEffect` / `RemoveEffect` /
`GetEffectCooldown` — every accessor is *typed* (Collectible / Null / Trinket). To enumerate, you get an
`EffectList` vector container and index it. There is **no** `PlayerEffect` or `TemporaryEffectTag` enum:
effects are keyed by the existing `CollectibleType`, `NullItemID` and `TrinketType` enums.

### `TemporaryEffects` — complete member list
Obtained by `EntityPlayer:GetEffects()`.

Functions (17, exact names and signatures):

| signature | notes |
|---|---|
| `void AddCollectibleEffect(CollectibleType, boolean AddCostume = true, int Count = 1)` | honours `cooldown`/`persistent` from `items.xml` |
| `void AddNullEffect(NullItemID, boolean AddCostume = true, int Count = 1)` | |
| `void AddTrinketEffect(TrinketType, boolean AddCostume = true, int Count = 1)` | |
| `void ClearEffects()` | |
| `const TemporaryEffect GetCollectibleEffect(CollectibleType)` | |
| `int GetCollectibleEffectNum(CollectibleType)` | |
| `const EffectList GetEffectsList()` | the enumeration entry point |
| `const TemporaryEffect GetNullEffect(NullItemID)` | |
| `int GetNullEffectNum(NullItemID)` | |
| `const TemporaryEffect GetTrinketEffect(TrinketType)` | |
| `int GetTrinketEffectNum(TrinketType)` | |
| `boolean HasCollectibleEffect(CollectibleType)` | |
| `boolean HasNullEffect(NullItemID)` | |
| `boolean HasTrinketEffect(TrinketType)` | |
| `void RemoveCollectibleEffect(CollectibleType, int Count = 1)` | `Count = -1` removes all |
| `void RemoveNullEffect(NullItemID, int Count = 1)` | `Count = -1` removes all |
| `void RemoveTrinketEffect(TrinketType, int Count = 1)` | `Count = -1` removes all |

Source: <https://wofsauge.github.io/IsaacDocs/rep/TemporaryEffects.html>

### `TemporaryEffect` — complete member list
Obtained from the three `Get*Effect()` getters. **Only three fields, no methods:**

| member | type |
|---|---|
| `Cooldown` | `int` |
| `Count` | `int` |
| `Item` | `ItemConfig Item` |

Source: <https://wofsauge.github.io/IsaacDocs/rep/TemporaryEffect.html>
(`Cooldown` semantics are not described on the page — **UNVERIFIED** whether it is "frames remaining"
or an absolute frame; `items.xml`'s `<cooldown>` is documented as *"Number of frames until this item's
associated CollectibleEffect is auto-removed if granted"* → <https://wofsauge.github.io/IsaacDocs/rep/xml/items.html>)

### `EffectList` (the vector container)
Documented as class `EffectList`, from `TemporaryEffects:GetEffectsList()`:

* Operator `__len()` → `int` — "Returns the amount of TemporaryEffects in the list" (so `#list` works)
* `TemporaryEffect Get(int idx)` — element access
* `const int Size` — "The amount of TemporaryEffects in the list"

Source: <https://wofsauge.github.io/IsaacDocs/rep/CppContainer_Vector_EffectList.html>
Index base of `Get(idx)` is **not documented** (**UNVERIFIED**; test 0-based first).

### Exact documented way to enumerate active temporary effects
```lua
local list = player:GetEffects():GetEffectsList()
for i = 0, list.Size - 1 do
    local e = list:Get(i)      -- TemporaryEffect
    -- e.Item.ID, e.Item.Type, e.Count, e.Cooldown
end
```
For a single known item, the cheap check is `player:GetEffects():HasCollectibleEffect(id)`.
(Real-world usage of exactly that call: EID, `features/eid_itemprediction.lua:629`.)

### What TemporaryEffects actually are (important, from the docs themselves)
The docs carry an explicit "Misinformation" warning:

> "TemporaryEffects, despite their names, are not and were never intended to be fake or temporary copies
> of items. Notably every single active item automatically grants its CollectibleEffect on use, and this
> is often closely tied to its effect; CollectibleEffects can therefore be visualised more as an item's
> **state**."
> …"some such as Hemoptysis and Berserk! still use CollectibleEffects for their cooldowns."
> "You should not assume that any given item will work as a TemporaryEffect the same as it does when
> actually obtained."

So the system is a **per-item state registry**, not a generic "temporary stat buff" list. `items.xml`
controls it: `<cooldown>` (frames until auto-removed) and `<persistent>` ("Determines whether the item's
associated CollectibleEffect is retained when transitioning between rooms, or across save & continue …
False by default").

The same page lists the ~190 passive items with notable CollectibleEffects. Directly relevant ones:
`Lusty Blood` ("each count of the effect increases damage; doesn't increase with kills"), `Whore of Babylon`,
`Crown of Light`, `Experimental Treatment` ("stat changes are seeded per room"), `Empty Vessel`, `Holy Mantle`,
`Mars`, `Astral Projection`. **Bloody Lust, Red Stew and Tainted Samson's berserk are NOT in that list.**

### REPENTOGON additions here
`repentogon.com/TemporaryEffects.html` and `repentogon.com/TemporaryEffect.html` **return HTTP 404** —
they do not exist. REPENTOGON's docs site (282 sitemap URLs, <https://repentogon.com/sitemap.xml>) has no
page for either class; they are vanilla classes and REPENTOGON does not re-document or (per its docs)
extend them.

What REPENTOGON *does* add is on **`EntityPlayer`** — convenience wrappers around `TemporaryEffects`
(<https://repentogon.com/EntityPlayer.html>):

| signature | doc |
|---|---|
| `void AddCollectibleEffect(CollectibleType, bool ApplyCostume = false, int Cooldown = VanillaCooldown, bool Additive = true)` | "Shortcut of TemporaryEffects:AddCollectibleEffect with extra arguments to handle cooldown. The additive parameter determines if the cooldown should be added to the preexistent cooldown value or if it should be set for that value. You can use negative cooldown values with additive to reduce preexistent cooldown." |
| `void AddNullItemEffect(NullItemID, bool ApplyCostume = false, int Cooldown = VanillaCooldown, bool Additive = true)` | same |
| `void AddTrinketEffect(TrinketType, bool ApplyCostume = false, int Cooldown = VanillaCooldown, bool Additive = true)` | same |

It also adds `AddCustomCacheTag(string OR {string,…}, boolean EvaluateItems = false)` and
`float GetCustomCacheValue(string CustomCacheTag)` ("Returns the current cached value for the specified
CustomCacheTag. Will return 0 by default if the provided tag has not been evaluated") — i.e. mods can add
their *own* cache fields, but there is no generic "list all stat contributions" API.

---

## Task 2 — The three items

### 2a. Red Stew — `CollectibleType.COLLECTIBLE_RED_STEW` = **621** (passive, Repentance)

* On pickup: **fully heals** and grants **+21.6 temporary damage**, which **decays to 0 over ~3 minutes**.
* Decay is non-linear: "starting at ~-0.015 per half second and increasing to ~-0.1 per half second as the
  bonus approaches 0" (consequence of the damage formula, not a linear timer on the stat).
* **Default length = 5390 game frames**, "just short of 3 minutes" (that is the length if no enemies die).
* While active it *also* copies Lusty Blood: a small damage bonus per kill that **persists between rooms
  and floors**, and disappears when the Red Stew bonus finally runs out. That kill bonus can exceed the
  original +21.6.
* Rock Bottom turns it permanent. Picking up a second Red Stew resets to full.
* **Not** in the TemporaryEffects "notable CollectibleEffects" list → treated as hardcoded, not exposed
  as a `TemporaryEffect`.

Source: <https://bindingofisaacrebirth.wiki.gg/wiki/Red_Stew>

**Read API (REPENTOGON only, confirmed):**
* `int EntityPlayer:GetRedStewBonusDuration()` — "Returns the frames left until the damage bonus from Red
  Stew expires."
* `void EntityPlayer:SetRedStewBonusDuration(int Duration)` — "Sets the duration of the damage bonus given
  by the Red Stew collectible to the specified amount of frames. Setting the duration above 0 will activate
  the effect if it wasn't active already."

Source: <https://repentogon.com/EntityPlayer.html>
Neither getter exists in vanilla 1.7.9 (not in the 249 documented `EntityPlayer` functions).

### 2b. Bloody Lust — `COLLECTIBLE_BLOODY_LUST` = **157** (passive, Samson's starter)

**The premise in the task is wrong** — in Repentance Bloody Lust triggers on **taking damage**, not on
kills, and it resets **per floor** (not per room):

* Repentance numbers: **+0.5 for the first hit, then +0.2 per additional hit, up to +1.5 on the sixth hit.
  Maximum total +6.0.** Any damage past the sixth hit adds nothing.
* (Antibirth/Afterbirth+ behaved differently: first three hits +0.5, next three +33%.)
* Bonus **stays for the whole floor**, resets on entering a new floor. Even if the item is removed the
  "rage" level is kept for the rest of the floor.
* Samson's **Birthright** allows 4 extra boosts at the same +0.2 interval → **max +14.0**.
* Isaac turns visibly redder as the counter rises.
* **Not** in the TemporaryEffects list → hardcoded, not a `TemporaryEffect`.

Source: <https://bindingofisaacrebirth.wiki.gg/wiki/Bloody_Lust>

**Do not confuse with Lusty Blood — `COLLECTIBLE_LUSTY_BLOOD` = 411** (Afterbirth): +0.5 damage per kill,
**per room**, max +5.0 after 10 kills. That one *is* listed as a TemporaryEffect ("each count of the effect
increases damage"), i.e. `GetEffects():GetCollectibleEffectNum(411)` reflects the stack count.
Sources: <https://bindingofisaacrebirth.wiki.gg/wiki/Lusty_Blood> and the TemporaryEffects page above.

**Read API:** vanilla — **none** (no `GetBloodyLustDamage`; the counter is internal).
**REPENTOGON only:** `int EntityPlayer:GetBloodLustCounter()` and `void SetBloodLustCounter(int Counter)`
(<https://repentogon.com/EntityPlayer.html>). The doc page gives the signature but **no description of the
range/units** — **UNVERIFIED** whether it returns 0–6 hits or the raw damage. Empirically it should be the
hit counter (0–6, or 0–10 with Birthright); confirm in-game.

### 2c. Tainted Samson's Berserk — `PlayerType.PLAYERTYPE_SAMSON_B` (Tainted Samson)

**Trigger:** "Whenever Tainted Samson deals or takes damage, he will grow progressively more red. After
reaching a certain point, he activates Berserk!". Requires a **base total of 120 damage dealt, +40 for every
next floor; taking damage adds 10% of the required total.** (Item `Berserk!` = 704 is the activated-item
equivalent; it charges the same way but ignores damage taken.)

**Duration:** **5 seconds** at start, **+1 second per kill** during it (+3 s with Birthright). Timer is shown
above his head. **Persists between rooms.** He cannot die while it is active (can sit at 0 hearts).

**Stats modified while berserk:**

| effect | value |
|---|---|
| Speed | **+0.40** flat (and **another +0.40 per kill** until it ends) |
| Damage | **+3 flat** |
| Fire rate | **×0.5 then +2** tear-delay change (a tears *up* unless tears ≥ 4) |
| Weapon | tears replaced by a **jawbone melee weapon** (Forgotten-style): **3× damage stat** per swing, **1.5× per tick** thrown; swing reflects enemy projectiles |
| Misc | brief invincibility on melee hit (~0.25 s) and on kill; no death while active |

Sources: <https://bindingofisaacrebirth.wiki.gg/wiki/Tainted_Samson>,
<https://bindingofisaacrebirth.wiki.gg/wiki/Berserk!>

**Is it a temporary effect or a player-state flag?** Neither, as far as the documented API goes:
* It is **not** a `TemporaryEffect` (no `CollectibleEffect` is listed for it, and `PlayerForm` has no berserk
  entry — the enum is Guppy…Flight, 15 values, <https://wofsauge.github.io/IsaacDocs/rep/enums/PlayerForm.html>).
* It is **not** exposed as a boolean player field: the 28 documented `EntityPlayer` variables do **not**
  include anything like `Berserk`/`IsBerserk`
  (<https://wofsauge.github.io/IsaacDocs/rep/EntityPlayer.html>).
* The only documented handle is the **charge**: `int EntityPlayer.SamsonBerserkCharge` —
  "Internally used by Tainted Samson, increases based on damage dealt, **range is 0-100000**". Note the
  *charge* is capped at 100000 and says nothing about whether berserk is currently **active**.
* REPENTOGON's `EntityPlayer` page (300 added functions) contains **no** `IsBerserk` and no mention of
  "Berserk" at all.
→ **There is no documented way to read "is Tainted Samson berserk right now".** Candidate workarounds are
**UNVERIFIED** and must be tested in-game: (a) `GetEffects():HasCollectibleEffect(704)` — the docs do say
Berserk! "still use[s] CollectibleEffects for their cooldowns", which hints the active-item version leaves a
collectible effect behind; (b) `HasWeaponType(...)` — but `WeaponType` has no jawbone/berserk member
(<https://wofsauge.github.io/IsaacDocs/rep/enums/WeaponType.html>); (c) `SamsonBerserkCharge` dropping to 0
right after activation (inference, not documented).

---

## Task 3 — Which read APIs actually exist

Enumerated the full vanilla `EntityPlayer` page: **249 functions, 28 variables**
(<https://wofsauge.github.io/IsaacDocs/rep/EntityPlayer.html>).

| asked about | exists? | exact name / notes |
|---|---|---|
| `GetEffects` | **YES** | `TemporaryEffects GetEffects()` |
| `IsBerserk` | **NO** | absent from vanilla docs *and* from REPENTOGON's 300 added functions |
| `GetBloodyLustDamage` | **NO** (vanilla) | REPENTOGON: `int GetBloodLustCounter()` / `SetBloodLustCounter(int)` |
| `GetTemporaryDamage`-like | **NO** generic; partial REPENTOGON accessors only | `int GetDamageModifier()` — "Used for Experimental Treatment and for stat boosts from Void. Modifier is applied to the player as flat damage. Experimental Treatment adds -1, 0 or 1 … Void may randomly add 1."; `float GetStatMultiplier()` — "Returns the multiplier added to stats gained from any items. Multipliers: Tainted Bethany ×0.75, Cracked Crown ×1.2"; `float GetRockBottomDamage()`; `float GetD8DamageModifier()`; `float GetEdenDamage()` (Eden's random base offset); `int GetRedStewBonusDuration()`; `int GetBloodLustCounter()`; `float GetCustomCacheValue(string)` |
| `GetCacheFlags` | **NO** — there is no getter | only `void AddCacheFlags(CacheFlag)`: "Will reevaluate the cache flags provided in the next cache reevaluation." |
| `AddCacheFlags` | **YES** | see above |
| `EvaluateItems` | **YES** | `void EvaluateItems()` — "Triggers a cache reevaluation. Will trigger the MC_EVALUATE_CACHE callback. Before you use this function, you need to set the appropriate cache flags first." |
| other "non-permanent contribution" reads | `void ClearTemporaryEffects()` — doc text: "Will be called when player exits the room." (i.e. it wipes the TemporaryEffects list; there is no per-effect delta API) |
| misc adjacent | `CollectibleType GetItemState()` (exists, **undocumented semantics**), `boolean HasTimedItem()` ("timed active item such as Brown Nugget in the first active slot"), `boolean HasPlayerForm(PlayerForm)`, `int GetCollectibleNum(CollectibleType)`, `boolean HasCollectible(CollectibleType)` |

`CacheFlag` enum (16 members, <https://wofsauge.github.io/IsaacDocs/rep/enums/CacheFlag.html>):
`CACHE_DAMAGE, CACHE_FIREDELAY, CACHE_SHOTSPEED, CACHE_RANGE, CACHE_SPEED, CACHE_TEARFLAG, CACHE_TEARCOLOR,
CACHE_FLYING, CACHE_WEAPON, CACHE_FAMILIARS, CACHE_LUCK, CACHE_SIZE, CACHE_COLOR, CACHE_PICKUP_VISION,
CACHE_ALL, CACHE_TWIN_SYNC`.

`MC_EVALUATE_CACHE` (<https://wofsauge.github.io/IsaacDocs/rep/enums/ModCallbacks.html>):
args `(EntityPlayer, CacheFlag)`, returns `void`.
> "Called one or more times when a player's stats are re-evaluated. For example, this will fire after the
> player picks up a collectible item that grants stats or uses a stat pill. The optional parameter can be
> used to specify a CacheFlag. It must be a singular CacheFlag, a composition of two or more CacheFlags will
> not work. … Use this callback to implement anything that changes the player's stats, familiars, flying,
> weapons, and so on."

And on the stat fields themselves, `EntityPlayer.Damage` (`float`) is documented as
"**Player stat – Only change this in a callback to MC_EVALUATE_CACHE.** This is equal to the Damage Stat."

### Can a mod "recompute on demand" to get a clean value?
Mechanically yes — `AddCacheFlags(CacheFlag.CACHE_DAMAGE)` + `EvaluateItems()` forces a full re-evaluation,
and `MC_EVALUATE_CACHE` fires. But **that does not give you a "clean" number**: cache evaluation re-applies
*all* contributions, including the temporary ones, so the value you read afterwards is the same buffed value.
The engine has no "base damage only" accessor. The wiki corroborates that this is one continuously
recomputed number: "the damage stat is constantly recalculated and the damage multipliers are multiplied
with the end result" (<https://bindingofisaacrebirth.wiki.gg/wiki/Damage>). Also note there is no documented
statement that stats are reset to base before evaluation — **UNVERIFIED**, and in any case it would not help,
because vanilla item buffs are applied before any mod callback runs.
The reverse formula (useful if you want to display a stat the way the game does) is on the same wiki page:
`Bonus = (1/1.2)·[((EffectiveDamage/Multipliers − FlatDmgUps)/CharBaseDmg)² − 1]`.

---

## Task 4 — What existing stat-display mods do

**Missing HUD 2** (C++/OpenGL overlay, reads game memory — not a Lua mod):
> "Unlike other statistic based mods, it uses your **live character statistics** during a run. This
> translates to Missing HUD 2 remaining 100% accurate even after picking up items like Experimental
> Treatment and Libra."
> "Shows how your **raw statistics** change as you pick up items and use pills, real-time."

→ It reads the **final, post-cache** values (the same numbers as `player.Damage` etc.) and does **not**
split out a "+X temporary" line. It also has no notion of temporary vs permanent — its "raw statistics"
means *unrounded/undisplayed*, not *unbuffed*.
Source: <https://gh-proxy.com/raw.githubusercontent.com/dparamoshkin/missinghud2/master/README.md>
(mirror of <https://github.com/dparamoshkin/missinghud2>; original <https://github.com/networkMe/missinghud2>)

**External Item Descriptions (EID)** — the only large Lua mod I could read in full:
* It reads `player.Damage` / `player.MoveSpeed` / `player.MaxFireDelay` / `player.TearRange` directly and
  runs them *backwards* through the damage formula to print a stat number
  (`features/eid_modifiers.lua:466`: `playerStats[3] = EID:SimpleRound(((player.Damage^0.56)*2.231179) - 2)`).
  → again the **buffed** value, with no temporary/permanent split.
* Where it cares about temporary item state it uses the typed TemporaryEffects API, e.g.
  `features/eid_itemprediction.lua:629`: `if player:GetEffects():HasCollectibleEffect(tempItem) then …` —
  used to predict Liberty Cap / Broken Syringe / Mom's Lock outcomes.
Source: <https://gh-proxy.com/codeload.github.com/wofsauge/External-Item-Descriptions/zip/refs/heads/master>
(repo <https://github.com/wofsauge/External-Item-Descriptions>)

**Stats+ / Isaac Run Logger** — **UNVERIFIED**. Stats+ appears to be Steam-Workshop-only (no GitHub repo
found; `steamcommunity.com`, `catalogue.smods.ru` and `goodmods.info` all return 403/blocked from this
machine), and "Isaac Run Logger" as named does not correspond to any repo I could confirm (the closest hit,
`aymericingargiola/repentance-run-tracker`, is an external desktop app, not a Lua mod). Do not rely on any
claim about their internals.

### Net best-practice finding
Every stat display I could verify reads the **single already-evaluated stat** and shows that. None of them
generically decomposes it into permanent + temporary contributions, because the engine does not expose that
decomposition. The only place a mod can be precise is per-item, using dedicated accessors
(`GetRedStewBonusDuration`, `GetBloodLustCounter`) or the TemporaryEffects registry (for items that happen to
register a `CollectibleEffect`).

---

## Recommendation — cheapest → most expensive (5 lines)

1. **Free:** treat `player.Damage` (sampled in `MC_EVALUATE_CACHE`/`MC_POST_PEFFECT_UPDATE`) as the "live" value and diff it against your own recorded *permanent* baseline (recompute baseline only on `MC_POST_NEW_LEVEL`, item add/remove, or `MC_POST_PICKUP_INIT`) — flags "something temporary is active" but not *which*.
2. **Cheap + exact for the 3 items:** call REPENTOGON's `GetRedStewBonusDuration() > 0` and `GetBloodLustCounter() > 0`; both are one-liners and give the true magnitude for Red Stew's remaining frames and Bloody Lust's hit count.
3. **Cheap + generic-ish:** enumerate `GetEffects():GetEffectsList()` and report each `TemporaryEffect` (`Item.ID`, `Count`, `Cooldown`) as a *separate* "+X from effect" row — but this only covers items that register a CollectibleEffect (~190 passives + active-item states); it will silently miss Bloody Lust, Red Stew and berserk.
4. **Medium:** add explicit per-item sampling for whichever stateful items your mod cares about (Berserk charge via `SamsonBerserkCharge`, per-item REPENTOGON getters `GetRockBottomDamage`/`GetD8DamageModifier`/`GetEdenDamage`/`GetStatMultiplier`/`GetDamageModifier`), and show them as annotated "+temp" chips next to the live stat.
5. **Not possible:** **you cannot observe this generically.** Vanilla 1.7.9 exposes no "current temporary stat contribution", no `IsBerserk`, no cache-flag getter, and no clean/base stat; REPENTOGON closes part of the gap only with item-specific getters. Design the HUD as "live value + per-item annotations", and treat Tainted Samson's berserk active-state as unavailable until you empirically find a proxy.
