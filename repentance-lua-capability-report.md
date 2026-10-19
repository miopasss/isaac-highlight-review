# The Binding of Isaac: Repentance — Lua Modding Capability Report

**Scope:** vanilla Repentance 1.7.9b + REPENTOGON. Research-only; no mod code.
**Confidence legend:** ✅ = verified against primary doc text retrieved in this session · ⚠️ = **not** verifiable in this environment (page returned nav-only/truncated, host unreachable); stated from established API knowledge — confirm before relying on it.

> **Research limitation (important):** from this sandbox only static GitHub-Pages-style mirrors were reachable (`wofsauge.github.io`, `moddingofisaac.com`, `repentogon.com`, `isaacblueprints.com`, `isaacscript.github.io`). `github.com`, `raw.githubusercontent.com`, `cdn.jsdelivr.net`, `*.fandom.com`, `r.jina.ai` all failed at the transport level (curl exit 35 / TLS). The IsaacDocs and REPENTOGON doc pages carry ~10–25 KB of shared sidebar nav *before* the article body, so most pages came back **nav-only**. Everything marked ✅ was recovered from doc text or doc member-lists (the sidebar TOC reproduces a page's complete member list, which is how the `EntityPlayer` / `Room` / `ModCallbacks` lists below were obtained verbatim).

**Sources**
- IsaacDocs (vanilla Repentance API): <https://wofsauge.github.io/IsaacDocs/rep/index.html> · mirror <https://moddingofisaac.com/docs/rep/index.html>
- REPENTOGON docs: <https://repentogon.com/docs.html>
- Isaac Blueprints (tutorials): <https://isaacblueprints.com/>
- IsaacScript (`isaacscript-common` tears helpers): <https://isaacscript.github.io/isaacscript-common/functions/tears/>

---

## 1. PLAYER STATS — verdict: PARTIAL

### 1.1 The actual field names (✅ verified — this is the complete vanilla `EntityPlayer` variable list)

`BabySkin, CanFly, ControllerIndex, ControlsCooldown, ControlsEnabled, Damage, FireDelay, FriendBallEnemy, HeadFrameDelay, IBSCharge, ItemHoldCooldown, LaserColor, Luck, MaxFireDelay, MoveSpeed, QueuedItem, SamsonBerserkCharge, SecondaryActiveItem, ShotSpeed, TearColor, TearFallingAcceleration, TearFallingSpeed, TearFlags, TearHeight, TearRange, TearsOffset`

Source: member list of <https://moddingofisaac.com/docs/rep/EntityPlayer.html>

| You asked about | Reality |
|---|---|
| `EntityPlayer.Damage` | ✅ exists. Final cached per-tear damage. |
| `EntityPlayer.MaxFireDelay` | ✅ exists. **The evaluated tear delay, in frames** (`FireDelay` is the live countdown that decrements each frame and is reloaded from `MaxFireDelay` on fire). |
| `EntityPlayer.ShotSpeed` | ✅ exists. |
| `EntityPlayer.Range` | ❌ **does not exist.** Use `TearRange` (+ `TearHeight`, `TearFallingAcceleration`, `TearFallingSpeed`). |
| `EntityPlayer.TearsMultiplier` | ❌ **does not exist in vanilla.** No such field on the class. |
| `EntityPlayer.Luck` | ✅ exists (affects tear effects, not raw DPS). |

Useful adjacent members that *do* exist (✅): `CanShoot()`, `GetFireDirection()`, `GetShootingInput()`, `GetTearHitParams()`, `GetMultiShotParams()`, `GetDamageCooldown()`, `GetLastDamageSource()`, `GetTotalDamageTaken()`, `FireTear()`, `FireBrimstone()`, `FireTechLaser()`, `FireKnife()`.

### 1.2 `MaxFireDelay` → shots per second (the `30/(MaxFireDelay+1)` formula)

- Fire delay is measured in **frames at a fixed 30 fps**, so cadence = `MaxFireDelay + 1` frames per tear.
- **shots/sec = 30 / (MaxFireDelay + 1)** — sanity check: Isaac's base `MaxFireDelay = 10` → `30/11 ≈ 2.73` tears/s, which is the game's known base tear rate.
- **Provenance:** this is the community/wiki convention and is the exact inverse implemented by `isaacscript-common`'s tears helpers (`getTearsStat` / tear-delay conversion), <https://isaacscript.github.io/isaacscript-common/functions/tears/>. ⚠️ I could not load the page body to quote the function in this session, and I found **no official Nicalis statement** of the formula — it is a reverse-engineered convention, universally used but not first-party documented.
- ⚠️ Treat `+1` as the *display*-accurate convention; true cadence can deviate (shoot animation, `FireDelay` clamping, `CanShoot()` gates).

### 1.3 Does the HUD differ from the raw fields?

- **Damage:** the HUD "Damage" is `player.Damage`, rounded for display. Magic Mushroom's 1.5× is folded into `player.Damage` **during cache evaluation**, not applied later — so there is **no separate multiplier you need to re-apply**. (Stat-cache mechanism ✅: `MC_EVALUATE_CACHE(player, flag)` runs after each evaluation and is re-run wholesale; see <https://isaacblueprints.com/tutorials/basics/stats_cache/>.)
- **Tears:** HUD "Tears" is derived from `MaxFireDelay` via the formula above (⚠️ rounding/display-cap behaviour not verified).
- **Consequence for DPS:** the honest per-shot number is the **tear's own damage at fire time** (`EntityTear.CollisionDamage` ⚠️), not `player.Damage`, because some items re-scale damage at fire time or on hit.

### 1.4 Cases that break naive `DPS = damage × shots/sec`

| Case | Why it breaks |
|---|---|
| Brimstone / Tech / Tech X | "shot" is a laser/blood beam; damage is per-tick or per-laser, not per-tear; fire delay still governs charge. |
| Chocolate Milk / Monstro's Lung / charged tears | Charge time replaces cadence; damage scales with charge. |
| Ludovico Technique | One persistent tear; damage is a continuous tick, not a rate of fire. |
| Soy Milk | `MaxFireDelay` → ~1–2 (≈10–15/s) while damage is heavily reduced; formula still "works" but the HUD tears value saturates. |
| Kidney Stone | Burst pattern, no steady cadence. |
| Incubus / familiars | Extra tear sources use the *player's* stats; a stats-only formula silently omits them. |
| Multi-shot (`20/20`, Inner Eye, The Wiz) | N tears per volley → multiply by `GetMultiShotParams()` tear count, else undercount. |
| Rubber Cement / Piercing / splash | One tear can damage the same enemy more than once. |

**Recommended measurement instead of a formula:** count tears with `MC_POST_FIRE_TEAR` (✅ vanilla callback) and read each tear's `CollisionDamage`/`Scale`, or sum damage in `MC_ENTITY_TAKE_DMG`. This is immune to every row above.

### 1.5 Does REPENTOGON help?

- ⚠️ No evidence found that REPENTOGON adds `TearsMultiplier` or an `Isaac.GetPlayerStats()`; nothing in its docs index suggests a consolidated stat getter. **Do not assume either exists.** Its stat-related additions appear to be `EvaluateStatStage`, `CustomCacheTag`, `EntityConfig*`, `TemporaryEffect(s)` (✅ those pages exist in the REPENTOGON index).
- Vanilla already gives you the cache hooks you need: `AddCacheFlags()` + `EvaluateItems()` (✅ both on `EntityPlayer`) and `MC_EVALUATE_CACHE` (✅).

---

## 2. EVENT / ROOM HOOKS — verdict: YES (with one real gap: no room-clear callback)

The vanilla `ModCallbacks` enum is **74 members**, `MC_NPC_UPDATE` … `MC_PRE_MOD_UNLOAD` (✅ complete list retrieved from <https://moddingofisaac.com/docs/rep/enums/ModCallbacks.html>).

### 2.1 Exact callback names for your events

| Event | Callback | Status |
|---|---|---|
| Entered a room | `MC_POST_NEW_ROOM` | ✅ vanilla |
| Entered a new floor | `MC_POST_NEW_LEVEL` | ✅ vanilla |
| Run started | `MC_POST_GAME_STARTED` | ✅ vanilla |
| Run ended (death **or** win) | `MC_POST_GAME_END` | ✅ vanilla |
| Leaving run / to menu | `MC_PRE_GAME_EXIT` | ✅ vanilla |
| Took damage | `MC_ENTITY_TAKE_DMG` | ✅ vanilla |
| Using an active item | `MC_USE_ITEM` | ✅ vanilla — **`MC_POST_USE_ITEM` does not exist** |
| Pre-use (cancellable) | `MC_PRE_USE_ITEM` | ✅ vanilla |
| Item picked up | `MC_PRE_GET_COLLECTIBLE`, `MC_POST_GET_COLLECTIBLE` | ✅ vanilla |
| Pickup spawned / ticked | `MC_POST_PICKUP_INIT`, `MC_POST_PICKUP_UPDATE` | ✅ vanilla |
| Pickup collision | `MC_PRE_PICKUP_COLLISION`, `MC_POST_PICKUP_SELECTION` | ✅ vanilla |
| Trinket | `MC_GET_TRINKET` | ✅ vanilla |
| Every frame / render | `MC_POST_UPDATE`, `MC_POST_RENDER` | ✅ vanilla |
| Stat recalculation | `MC_EVALUATE_CACHE` | ✅ vanilla |
| Tear fired | `MC_POST_FIRE_TEAR` | ✅ vanilla |
| **Room cleared** | **no dedicated callback** | ✅ verified absent |
| Mod unload | `MC_PRE_MOD_UNLOAD` | ✅ vanilla |

⚠️ Exact parameter tuples were not readable this session. Standard signatures you should verify: `MC_ENTITY_TAKE_DMG(entity, amount, damageFlags, damageSource, countdown)`; `MC_USE_ITEM(collectibleType, rng, useFlags, activeSlot, customVarData)`; `MC_POST_GAME_END(isGameOver)`; `MC_EVALUATE_CACHE(player, cacheFlag)`.

### 2.2 Detecting room clear / first visit

- **No `MC_POST_ROOM_CLEAR`** in vanilla (✅). Two workable alternatives:
  1. **`MC_PRE_SPAWN_CLEAN_AWARD`** (✅ in the enum) — fires immediately before the clear award spawns: the *de-facto* "room just cleared" hook, fires once per clear. **Best choice.**
  2. Poll `Room:IsClear()` (✅) in `MC_POST_UPDATE` and edge-detect. This is what `isaacscript-common`'s `RoomClearFrame` / `PostRoomClearChanged` features exist to wrap — itself evidence that no native callback exists.
- **First visit:** `Room:IsFirstVisit()` ✅, plus `Room:IsInitialized()` ✅, `Room:GetFrameCount()` ✅. `RoomDescriptor.VisitedCount` / `SeenCount` exist on the descriptor ⚠️.
- Writing clear state is supported: `Room:SetClear()`, `Room:TriggerClear()`, `Room:KeepDoorsClosed()`, `Room:SpawnClearAward()` (✅ all on `Room`).

### 2.3 Distinguishing room types

| Need | API | Status |
|---|---|---|
| Room type | **`Room:GetType()` → `RoomType`** | ✅ |
| Shape | `Room:GetRoomShape()` → `RoomShape` | ✅ |
| Background/floor theme | `Room:GetBackdropType()` → `BackdropType` | ✅ |
| Current descriptor | `Level:GetCurrentRoomDesc()` → `RoomDescriptor` | ⚠️ (`Level` members not retrievable; `RoomDescriptor` class ✅ exists) |
| Descriptor bits | `RoomDescriptor.Data` (int), `.Flags` (`RoomDescriptorFlag`), `.Clear` | ⚠️ |

> **Correction to your assumption:** `RoomDescriptor.Data` is **not** the room type. `Room:GetType()` is. `RoomType` is a real enum (✅ present in the enum index), as are `RoomShape`, `RoomDescriptor`, `DoorState`, `DoorVariant`, `GridEntityType`, `GridCollisionClass`. ⚠️ Numeric values (shop/treasure/boss/secret/curse/sacrifice/devil/angel/arcade/vault/library…) were not readable — read `enums/RoomType.html` locally.
> Sub-typing (which devil room, which shop) is via `RoomDescriptor.Data` / `RoomConfig` (`RoomConfig_Room`, `RoomConfig_Entry` ✅) and, in REPENTOGON, `RoomSubType` (✅).

Room-specific probes that exist (✅): `GetBossID()`, `GetSecondBossID()`, `IsCurrentRoomLastBoss()`, `GetShopLevel()`, `GetDevilRoomChance()`, `IsSacrificeDone()`, `IsAmbushActive()`, `IsAmbushDone()`, `HasCurseMist()`, `IsMirrorWorld()`, `IsLShapedRoom()`.

---

## 3. ROOM GEOMETRY & RE-DRAWING A ROOM AS AN IMAGE

### 3.1 Reading the grid — the real method names (✅ full `Room` member list)

| Purpose | Method | Note |
|---|---|---|
| Dimensions | `Room:GetGridWidth()`, `GetGridHeight()`, `GetGridSize()` | ✅ your names were right |
| Position → index | `Room:GetGridIndex(pos)`, `GetClampedGridIndex(pos)`, `GetGridPosition(idx)` | ✅ |
| Tile collision | **`Room:GetGridCollision(gridIndex)`**, `GetGridCollisionAtPos(pos)` | ⚠️ **takes a grid index, not `(x,y)`** — your assumed `GetGridCollision(x,y)` is wrong |
| Grid entity | **`Room:GetGridEntity(gridIndex)`**, `GetGridEntityFromPos(pos)` | ⚠️ likewise index-based |
| Pathing | `GetGridPath(idx)`, `GetGridPathFromPos(pos)`, `SetGridPath()` | ✅ |
| Raw level-room data | `Room:GetLRoomTileDesc()`, `Room:GetLRoomAreaDesc()` | ✅ (undocumented but present — closest thing to raw tile records) |
| Doors | `Room:GetDoor(slot)`, `GetDoorSlotPosition(slot)`, `IsDoorSlotAllowed(slot)`, `RemoveDoor()`, `TrySpawnDevilRoomDoor()`, `TrySpawnSecretExit()` | ✅ |
| Seeded decoration | `Room:GetDecorationSeed()`, `GetSpawnSeed()`, `GetAwardSeed()`, `GetSeededCollectible()` | ✅ |
| Camera/screen | `Room:WorldToScreenPosition(pos)`, `GetRenderSurfaceTopLeft()`, `GetRenderScrollOffset()`, `GetRenderMode()`, `ScreenWrapPosition()` | ✅ |
| Spawning/editing | `SpawnGridEntity()`, `RemoveGridEntity()`, `DamageGrid()`, `DestroyGrid()` | ✅ |

Grid entity introspection: `GridEntity` + `GridEntityDesc` (✅ classes; `GetType()`, `GetVariant()`, `GetState()`, `GetDesc()` ⚠️ member-level unverified).
**Vanilla typed subclasses are only:** `GridEntityDoor`, `GridEntityPit`, `GridEntityPoop`, `GridEntityPressurePlate`, `GridEntityRock`, `GridEntitySpikes`, `GridEntityTNT` (✅ — this is the complete list).
**REPENTOGON adds:** `GridEntityDecoration`, `GridEntityFire`, `GridEntityGravity`, `GridEntityLock`, `GridEntityStairs`, `GridEntityStatue`, `GridEntityTeleporter`, `GridEntityTrapDoor`, `GridEntityWall`, `GridEntityWeb` (✅ all present in REPENTOGON's index) — i.e. **decorative props are properly typed only under REPENTOGON**; vanilla needs raw `GetType()/GetVariant()` on a generic `GridEntity`.

### 3.2 Can a mod re-draw a room later from saved data? — **YES, but only by re-rendering; there is no snapshot.**

You must persist and replay:
1. `GridCollisionClass` per tile (`GetGridCollision(idx)`), or a coarse walkable/solid bitmask.
2. Per-tile grid entity `type` + `variant` + `state` (+ rock subtype/`GridEntityDesc`) for rocks, poops, pits, spikes, TNT, fireplaces, locks.
3. Door set: which `DoorSlot`s exist, each door's variant/state; plus wall gap implication of `RoomShape`.
4. `RoomShape`, `BackdropType`, `RoomType`.
5. `GetDecorationSeed()` (so procedural grime/props match) + floor/wall colour (`SetFloorColor`/`SetWallColor` exist ✅).

Rendering options, cheapest first:
- **`Isaac.RenderQuad(pos, size, color)` per tile** ⚠️ signature unverified — 15×9 tiles max, trivial cost, gives a readable minimap-style recap. **Recommended.**
- `Sprite` from `gfx/grid/<...>.anm2` and `gfx/backdrop/<...>.anm2`; `Sprite:Render(...)` ⚠️. Sprite names/atlas frame indices are not enumerated in any doc I could reach.
- ⚠️ **Floor-pattern determinism:** `BackdropType` + `GetDecorationSeed()` are seed-derived, but I found **no documented API** to reproduce the exact per-tile floor/wall art. Assume "approximately right", not pixel-exact.

### 3.3 Screenshots / texture readback — **NO** (definitive enough to design around)

- ❌ No `Isaac.GetScreenshot` or equivalent exists in vanilla IsaacDocs; there is no pixel-readback, framebuffer-capture or render-target-fetch function anywhere in the vanilla API surface.
- ❌ REPENTOGON does **not** add readback either: its `Image` class (✅ complete member list) exposes only `GetWidth`, `GetHeight`, `GetPaddedWidth`, `GetPaddedHeight`, `GetName`, `GetTexelRegion`, `Render`, `RenderWithShader` — **no `GetPixels`/`Read`/`Save`**. Source: <https://repentogon.com/renderer/Image.html>
- ⚠️ REPENTOGON does expose render-target-ish machinery (`renderer/SurfaceRenderController`, `Shader`, `RenderSet`, `Beam`, `VertexBuffer`, `Pipeline`) — rendering *into* a surface is plausible, but **reading pixels back is not exposed**, so it cannot yield a shareable image file.
- ✅ And you could not write the file anyway — `io`/`os` are sandboxed out (§5).
- **Verdict:** a "room screenshot" feature is impossible in-engine. Persist geometry and re-render, or accept an external OS screenshot.

---

## 4. CUSTOM UI — verdict: PARTIAL in vanilla, YES with REPENTOGON

### 4.1 What exists

| Capability | API | Status |
|---|---|---|
| Per-frame draw hook | `MC_POST_RENDER` | ✅ vanilla |
| Text | `Isaac.RenderText`, `Isaac.RenderScaledText`, `Isaac.RenderQuad` | ⚠️ names are standard but `Isaac` member list was not retrievable |
| Font objects | `Font` class + `FontRenderSettings` class + `DrawStringAlignment` enum | ✅ classes exist |
| Sprites | `Sprite` class, `Sprite:Render` | ⚠️ |
| Layering | `SortingLayer`, `RenderMode` enums | ✅ |
| World→screen | `Room:WorldToScreenPosition`, `Isaac.WorldToScreenPosition` | ✅ (Room side) |

**Scaling/resolution:** ⚠️ Repentance draws to a fixed logical surface (conventionally 480×270) upscaled to the window; UI mods must therefore author in that space and offset with `Options.HUDOffset`-style values. Could not verify in this session — confirm with `Isaac.GetScreenWidth()`/`GetScreenHeight()` at runtime.

### 4.2 Menu hooks — the important negative result

- ✅ **Vanilla has NO menu render callback.** The complete 74-entry `ModCallbacks` list contains nothing like `MC_POST_MAIN_MENU_RENDER` or `MC_POST_PAUSE_MENU_RENDER` (verified against the full enum). Vanilla mods that draw on menus must piggyback `MC_POST_RENDER` and poll input by hand.
- ✅ **`MC_POST_GAME_END` exists** — but it is an *event* callback, not a render hook; it does not give you a draw pass on the game-over screen.
- ⚠️ **`MC_POST_MAIN_MENU_RENDER` / `MC_POST_PAUSE_MENU_RENDER` are almost certainly REPENTOGON-only** (they are absent from vanilla, and REPENTOGON ships a full menu object model). I could not read the REPENTOGON enum page to confirm the exact spelling — **verify these two strings before depending on them.**
- ✅ REPENTOGON menu surface (classes): `MenuManager`, `MainMenu`, `PauseMenu`, `TitleMenu`, `OptionsMenu`, `ModsMenu`, `StatsMenu`, `BestiaryMenu`, `CollectionMenu`, `CharacterMenu`, `SaveMenu`, `ChallengeMenu`, `DailyChallengeMenu`, `KeyConfigMenu`, `SpecialSeedsMenu`, `ControllerSelectMenu`, `CutscenesMenu`, `CustomChallengeMenu`; plus `MainMenuType`, `PauseMenuStates`, `CharacterMenuStatus` enums; plus `ScoreSheet` (game-over score screen) and full **ImGui** integration (`ImGui` + `ImGui*` enums). This is the supported way to add a real clickable menu entry.

### 4.3 How mods actually inject a main-menu entry

- **Vanilla mechanism (⚠️ reconstruction, not source-verified):** there is no API to add a native button, so mods *overlay* their own list, detect navigation with polled input, and draw with `MC_POST_RENDER`; the entry point is usually reached through the **Mods/Options** menu rather than the title screen. This is inherently hacky and is precisely why REPENTOGON added a menu object model.
- **REPENTOGON mechanism:** construct/attach to `MainMenu` / `MenuManager` and add a real menu element, then draw via the menu render callback. Community references: <https://repentogon.com/menus/MenuManager.html>, <https://repentogon.com/menus/MainMenu.html> (pages reachable, bodies were nav-truncated here).
- I did **not** read Mod Config Menu / External Item Descriptions source (GitHub unreachable), so treat the vanilla mechanism description as informed inference, not a citation.

### 4.4 Input on menus

- ✅ `Mouse` and `Keyboard` enums exist; `Input` class exists; `InputHook` enum exists; `MC_INPUT_ACTION` callback exists; `ButtonAction` enum exists.
- ⚠️ `Isaac.GetMousePosition`, `Input.IsButtonTriggered`, `Input.IsActionTriggered` are the conventional calls but I could not verify the member names.
- ⚠️ **Whether input callbacks fire while the main menu is open is not documented and could not be verified.** `MC_INPUT_ACTION` is documented as player-action oriented. Treat "poll input during main menu" as needing a runtime experiment.

---

## 5. PERSISTENCE — verdict: YES for mod data, NO for arbitrary files

### 5.1 The real API (correcting your assumed signature)

⚠️ **`Isaac.SaveModData(mod, data, key)` / `Isaac.LoadModData` / `Isaac.HasModData` / `Isaac.RemoveModData` do not exist in Repentance.** Persistence is methods on the **`ModReference`** object returned by `RegisterMod` (✅ verified, with a worked tutorial):

| Method | Behaviour |
|---|---|
| `mod:HasData()` → `boolean` | whether this mod has save data |
| `mod:LoadData()` → `string` | raw string from `saveX.dat` |
| `mod:SaveData(str)` | writes the string |
| `mod:RemoveData()` | deletes the file |

Source: <https://isaacblueprints.com/tutorials/concepts/saving_data/> · <https://wofsauge.github.io/IsaacDocs/rep/ModReference.html>

**Scope (✅):**
- Files live in `<game>/data/<YourModFolderName>/save1.dat`, `save2.dat`, `save3.dat` — **one file per save slot**. Per-save-slot separation is therefore **built in**, not something you implement.
- Stored as **plain text**, survives game restarts and mod uninstall/reinstall (the `data/` folder is deliberately outside the mod folder).
- ✅ **`SaveData`/`LoadData` can only be called inside a run** — not from the main menu. Gate them on `MC_POST_GAME_STARTED` / `MC_POST_GAME_END`.
- Data is **per mod** (folder name), so no cross-mod snooping.

**Serialization:** JSON is built in — `local json = require("json")`, then `json.encode` / `json.decode` (✅). You must encode/decode yourself; there is no table-aware save. Documented caveats (✅): sparse arrays get padded with `null` (can bloat files enormously), only string/integer keys (float keys silently stringify), mixed key types stringify all integers, `inf`/`NaN` corrupt the file, functions/userdata (incl. `Vector`) cannot be encoded, and circular references stack-overflow.

**Size limits:** ⚠️ no documented cap. Practical guidance only: the file is rewritten whole on each `SaveData`, is plain text, and is user-editable — keep it to **kilobytes**; a run-recap log of a few hundred rooms is fine, per-frame samples are not. Do not treat this as a hard guarantee.

### 5.2 Arbitrary file I/O — **NO** (✅ definitive)

The Lua sandbox table is explicit (<https://wofsauge.github.io/IsaacDocs/rep/tutorials/Standard-Library.html>):

| Always available | Only with `--luadebug` |
|---|---|
| `json` (`require("json")`), `assert`, `collectgarbage`, `coroutine`, `error`, `getmetatable`, `ipairs`, `load`, `math`, `next`, `pairs`, `pcall`, `print`, `rawequal`, `rawget`, `rawlen`, `rawset`, `require` (safe), `select`, `setmetatable`, `string`, `table`, `tonumber`, `tostring`, `type`, `utf8`, `xpcall` | `socket`, `debug`, `dofile`, **`io`**, `loadfile`, **`os`**, `package`, `require` (unmodified) |

So in vanilla: **no `io`, no `os`, no `dofile`/`loadfile`, no networking.** The docs state the intent directly: "mods are restricted from doing anything harmful, like reading files from the file system", and the `data/` design is justified "for security reasons, as mods being able to create arbitrary files on the user's computer would be very dangerous". `--luadebug` (a Steam launch option the *user* sets) lifts this — a published mod cannot rely on it.

**REPENTOGON:** ⚠️ no evidence it exposes `io` or a file-write API; nothing resembling `Isaac.SaveFile` appears in its class index. Assume **still sandboxed** and verify before designing around it. (Minor note: REPENTOGON's docs link the **Lua 5.4** manual while IsaacDocs links **5.3** — a possible runtime version difference, unverified.)

### 5.3 Surviving restarts / per-run separation

- ✅ Survives restarts (it's a file on disk) — but only if you call `SaveData` again; nothing is auto-persisted.
- ✅ Per-save-slot for free (file per slot).
- **Per-run separation is manual:** store `{[runId] = {...}}` inside one blob, keyed by e.g. start seed + start frame, and keep the last N runs. There is no per-run storage primitive.
- Global (cross-slot) unlocks are a different system: `Isaac.GetPersistentGameData()` / `PersistentGameData` class (✅ classes exist; ⚠️ method names unverified).

---

## 6. REPENTOGON vs VANILLA — delta relevant to a "run recap / power-score history" mod

### 6.1 What REPENTOGON adds (✅ = present in its docs index)

| Area | Addition | Why it matters here |
|---|---|---|
| **Run history** | **`History`** class: `GetCollectiblesHistory()`, `SearchCollectibles()`, `SearchTrinkets()`, `RemoveHistoryItemByIndex()`; plus **`HistoryItem`** | ✅ Directly gives an ordered item-pickup history — much of a recap mod's data model, already built. **Biggest single win.** |
| Score screen | `ScoreSheet` | Hook/inspect the game-over tally |
| Menus | `MenuManager`, `MainMenu`, `PauseMenu`, `TitleMenu`, `StatsMenu`, … + `MainMenuType`/`PauseMenuStates` | Real clickable recap UI, not an overlay hack |
| UI toolkit | `ImGui` + `ImGuiCallback`/`ImGuiWindowFlags`/… enums | Fast tables/graphs for a power-score history |
| Renderer | `Shader`, `Image`, `Beam`, `RenderSet`, `SurfaceRenderController`, `VertexBuffer`, `Pipeline`, `Transformer`, `Vertex`, `BlendMode`, `GLSLType` | Bar/line charts with shaders (no pixel readback, §3.3) |
| Grid entities | 10 extra typed subclasses (Decoration, Fire, Gravity, Lock, Stairs, Statue, Teleporter, TrapDoor, Wall, Web) | Faithful room reconstruction incl. props |
| Room/gen data | `LRoomTileDesc`, `LRoomAreaDesc`, `LevelGenerator`, `LevelGeneratorEntry`, `LevelGeneratorRoom`, `RoomSubType`, `RoomEventOutput`, `DoorMask`, `StbGridType`, `StbType`/`Stb*` | Exact door masks + generator internals |
| Stats | `EvaluateStatStage`, `CustomCacheTag`, `EntityConfig`/`EntityConfigEntity`/`EntityConfigPlayer`, `TemporaryEffect(s)`, `ProceduralItem*` | Finer-grained stat modelling |
| Misc | `EntitySaveStateManager`, `PlayerManager`, `PersistentGameData`, `Camera`, `Backdrop`, `Ambush`, `MusicManager`, `Options`, `Console`, `Debug`, `PathFinder`, `RailManager` | Save per-entity state; control camera for recap screenshots-by-render |
| Callbacks | Menu render callbacks (`MC_POST_MAIN_MENU_RENDER` / `MC_POST_PAUSE_MENU_RENDER`) ⚠️ spelling unverified | Draw on menus natively |

### 6.2 Adoption & the constraint it imposes

- REPENTOGON is a **community-made patch/extension to the game executable**, installed separately by the user (not a Workshop-only dependency). Mods that call its API **hard-crash or error on vanilla Repentance** unless guarded.
- **Constraint:** depending on REPENTOGON shrinks your audience to users who installed it. ⚠️ Precise adoption numbers, the exact declaration a mod uses to advertise the requirement, and current vanilla/Repentance+/1.7.9b version compatibility were **not verifiable** here — check <https://repentogon.com/install.html> and the mod's `metadata.xml` conventions before shipping.
- **Design implication:** feature-detect (`if REPENTOGON then … end` ⚠️ mechanism unverified) and keep a vanilla-only code path; treat `History`, `ImGui`, menu callbacks as optional accelerators, not foundations.

---

## Uncertain / must-verify-before-building

1. ⚠️ `MC_POST_MAIN_MENU_RENDER` / `MC_POST_PAUSE_MENU_RENDER` exact spelling (REPENTOGON-only; absent from vanilla ✅).
2. ⚠️ `Isaac.RenderText` / `RenderQuad` / `RenderScaledText` and `Sprite:Render` signatures — standard, unverified here.
3. ⚠️ `Isaac.GetMousePosition` / `Input.IsButtonTriggered` names; whether input callbacks fire on the main menu.
4. ⚠️ `Level:GetCurrentRoomDesc()`, `RoomDescriptor.Data`/`.Flags`/`.VisitedCount` member semantics.
5. ⚠️ Numeric `RoomType` / `RoomShape` / `GridEntityType` values.
6. ⚠️ REPENTOGON file I/O, runtime Lua version (5.3 vs 5.4), upstream compatibility, adoption.
7. ⚠️ `SaveData` practical size ceiling — undocumented.
8. ⚠️ Whether `MC_ENTITY_TAKE_DMG` returning `false` cancels damage (widely believed; unverified).

## Bottom line

- **Stats (PARTIAL):** `Damage`, `MaxFireDelay`, `ShotSpeed`, `Luck`, `TearRange` are the fields; `Range` and `TearsMultiplier` **do not exist**. `30/(MaxFireDelay+1)` is a community convention, not first-party. Compute DPS from fired tears, never from stats alone.
- **Hooks (YES/one gap):** everything you need exists **except a room-clear callback** — use `MC_PRE_SPAWN_CLEAN_AWARD` or poll `Room:IsClear()`. Room type = `Room:GetType()`, not `RoomDescriptor.Data`.
- **Geometry (YES / redraw PARTIAL):** the grid, doors and seeds are all readable, but `GetGridCollision`/`GetGridEntity` take **grid indices**. Persist per-tile data and re-render (quads are enough). **Screenshots are impossible** — no readback anywhere.
- **UI (PARTIAL→YES):** `MC_POST_RENDER` + `Font`/`Sprite` in vanilla; real menus and menu render callbacks only in REPENTOGON (ImGui included). Vanilla main-menu entries are an overlay hack.
- **Persistence (YES, sandboxed):** `mod:HasData/LoadData/SaveData/RemoveData`, one plain-text blob per mod **per save slot**, `require("json")` for serialization. **No `io`/`os`** without `--luadebug`; `Isaac.SaveModData` does not exist.
- **REPENTOGON delta (high):** `History`/`HistoryItem` alone justifies considering it for a recap mod; but it caps your audience at REPENTOGON installs, so feature-detect and keep a vanilla path.
