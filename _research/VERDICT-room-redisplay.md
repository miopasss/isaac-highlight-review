# Verdict Sheet — Room Identity / Re-display Feasibility
### The Binding of Isaac: Repentance Lua modding (vanilla API + REPENTOGON)

**Scope:** research only, no mod code. All findings from primary docs (IsaacDocs / REPENTOGON docs mirrors).

---

## ⚠️ Version caveat — read first

The user's target is **Repentance 1.7.9**. The REPENTOGON docs site I could reach documents
**Repentance+ v1.9.7.12** (`repentogon.com` front page: *"REPENTOGON is a mod for The Binding of
Isaac: Repentance+ version v1.9.7.12"*).

> **Consequence:** every `repentogon.com` API below is verified *for the current Repentance+ build*.
> The 1.7.9-era REPENTOGON (0.x/1.0.x line) may lack the newer surfaces — most importantly
> `RoomDescriptor:GetGridEntitiesSaveState()` (Task 4), which is the single most useful API found.
> **Action for parent:** pin the REPENTOGON version before designing on Task 4's result. Vanilla
> findings (Tasks 1, 2, 6) are version-stable and unaffected.

### Access note (fixes the previous research pass)
The earlier "github/raw/jsdelivr failed at transport level" diagnosis was **wrong**. The real cause
was Windows schannel failing certificate **revocation** checks (`CRYPT_E_REVOCATION_OFFLINE`),
because the CRL server is unreachable. `curl --ssl-no-revoke` fixes it and the GitHub-Pages mirrors
work fine with full HTML. `github.com` / `raw.githubusercontent.com` are still genuinely reset, but
they are not needed. **`repentogon.com` and `wofsauge.github.io/IsaacDocs` were both fully usable.**

---

## TASK 1 — Stable room identity

**QUESTION:** What fields exist on `RoomDescriptor`, and which is a stable identifier for "this room in this floor"? Is a RoomConfig id reachable?

**VERDICT: PARTIAL — YES for a per-floor handle, YES for a room-config id, NO for a single intrinsic "this exact room forever" id.**

### Complete `RoomDescriptor` variable list (VERIFIED — full page body read, matches sidebar TOC exactly)

| Field | Type | Note |
|---|---|---|
| `AllowedDoors` | `DoorSet` | *Vanilla: "contains userdata and is therefore not useable"*. **REPENTOGON fixes this** into a real bitmask of enabled door slots |
| `AwardSeed` | int | clear-award / shop-init seed |
| `BossDeathSeed` | const int | **REPENTOGON-only** |
| `ChallengeDone` | boolean | |
| `Clear` | boolean | room cleared; won't respawn enemies |
| `ClearCount` | int | |
| `Data` | **`RoomConfigRoom`** | ← the static room-config object. `nil` ⇒ invalid descriptor |
| `DecorationSeed` | int | cosmetic (backdrops, decorations, shopkeeper skins) |
| `DeliriumDistance` | int | The Void helper |
| `DisplayFlags` | int | minimap bits: `1<<0` visible, `1<<1` shadow, `1<<2` icon; needs `Level:UpdateVisibility()` |
| `Flags` | `RoomDescriptor` (flags) | |
| `GridIndex` | int | cell on 13×13 level grid, row-major from top-left. For multi-cell rooms = **top-left** quadrant. For `ROOMSHAPE_LTL` = the quadrant **not inside** the room. ≠ `Level:GetCurrentRoomIndex()` |
| `HasWater` | boolean | |
| `ListIndex` | int | index into `Level:GetRooms()` = **order of floor-generation creation** |
| `NoReward` | boolean | |
| `OverrideData` | `RoomConfigRoom` | variant override (minibosses etc.) |
| `PitsCount` | int | |
| `PoopCount` | int | |
| `PressurePlatesTriggered` | boolean | |
| `SacrificeDone` | boolean | |
| `SafeGridIndex` | int | normalized quadrant; multi-cell = top-left, **`LTL` = top-right** (inconsistent on purpose). ≠ `GetCurrentRoomIndex()` |
| `ShopItemDiscountIdx` | int | −1..7 |
| `ShopItemIdx` | int | 0..7 |
| `SpawnSeed` | int | used to spawn entities at room load + enemy drop seeds |
| `SurpriseMiniboss` | boolean | |
| `VisitedCount` | int | how often visited |

**`SeenCount` does NOT exist** (verified absence — not in body, not in TOC). The user's list guessed it; the real field is `VisitedCount`.

### Index-field comparison (VERIFIED — doc text is explicit)

| Field | Stable for | Caveat |
|---|---|---|
| `GridIndex` | same floor, same dimension | wrong for multi-cell rooms; **not unique across dimensions** |
| `SafeGridIndex` | same floor, same dimension, geometry-friendly | **not unique across dimensions**; `LTL` maps to top-right |
| **`ListIndex`** | **← docs explicitly recommend this** | *"Data structures that store data per room should use `ListIndex` as a key instead of `GridIndex`, since the former is unique across different dimensions."* Still only unique **within one floor** |

### Is a RoomConfig id reachable from Lua?

**YES.** `RoomDescriptor.Data` is a `RoomConfigRoom`, and that class exposes the STB identity triple:

- `RoomConfigRoom.StageID` (`const int`) — stage the room was **designed** for (see Stage-ID table below)
- `RoomConfigRoom.Type` (`const RoomType`)
- `RoomConfigRoom.Variant` (`const int`)
- `RoomConfigRoom.Subtype` (`const int`), `.Shape` (`const RoomShape`), `.Width`, `.Height`, `.Doors` (bitmask), `.Name`, `.Weight`, `.InitialWeight`, `.Difficulty`, `.OriginalVariant`, `.SpawnCount`, `.Spawns`
- REPENTOGON additionally **fixes `.Mode`** (vanilla: broken userdata)

REPENTOGON then lets you go the other way:

```lua
RoomConfig.GetRoomByStageTypeAndVariant(StbType Stage, RoomType Type, int Variant, int Mode = -1)
    -> RoomConfigRoom
RoomConfig.GetStage(StbType Stage) -> RoomConfigStage
RoomConfig.GetRandomRoom(Seed, ReduceWeight, StbType, RoomType, RoomShape, ...) -> RoomConfigRoom
RoomConfig.AddRooms(StbType, int Mode, table[] Rooms) -> RoomConfigRoom[]
RoomConfig.LoadStb(StbType, int Mode, string StbFileName) -> RoomConfigRoom[]
```

**`Isaac.GetRoomConfig(...)` does NOT exist** (verified absence — `RoomConfig` appears only in the nav sidebar of the `Isaac` page, never in the members).
**`Room:GetRoomConfig()` does NOT exist** (verified absence). The only config-ish thing on a live `Room` is:

```lua
Room:GetRoomConfigStage() -> int    -- "Returns the ID of the stage the room was designed for"
```

**Sources:** [RoomDescriptor](https://wofsauge.github.io/IsaacDocs/rep/RoomDescriptor.html) · [RoomConfigRoom](https://wofsauge.github.io/IsaacDocs/rep/RoomConfig_Room.html) · [Room](https://wofsauge.github.io/IsaacDocs/rep/Room.html) · [Isaac](https://wofsauge.github.io/IsaacDocs/rep/Isaac.html) · [REPENTOGON RoomConfig](https://repentogon.com/RoomConfig.html) · [REPENTOGON RoomDescriptor](https://repentogon.com/RoomDescriptor.html)

---

## TASK 2 — Access to non-current rooms

**QUESTION:** Can Lua get a `Room` object for a room the player is not in? Does `GetRoomByIdx` work for (a) other rooms on this floor, (b) rooms on floors already left? Are past floors destroyed?

**VERDICT: NO for `Room` objects anywhere. YES for `RoomDescriptor` on the current floor. NO for anything on a left floor.**

### The function exists — and returns a *descriptor*, not a `Room`

```lua
RoomDescriptor Level:GetRoomByIdx( int RoomIdx, int Dimension = -1 )
```

VERIFIED doc text:
- *"This function always returns a valid `RoomDescriptor` object, so error checking is recommended. The `Data` property of an invalid `RoomDescriptor` object is `nil`."*
- Dimension: `-1` current · `0` main · `1` secondary (Downpour mirror / Mines escape) · `2` Death Certificate.
- Use `GetRoomByIdx(level:GetCurrentRoomIndex())` to get the **writable** descriptor; `GetCurrentRoomDesc()` is read-only.

### (a) Other rooms on the current floor — **YES (descriptor only)**

`Level:GetRoomByIdx(idx)` / `Level:GetRooms()` give valid `RoomDescriptor`s for rooms you have never entered. There is **no** corresponding way to get a live `Room` object: the only `Room` accessors are `Level:GetCurrentRoom()` and `Game():GetRoom()`. So for a non-current room you cannot call `Room:GetGridEntity`, `Room:GetGridCollision`, etc.

### (b) Rooms on floors already left — **NO**

Verified **absence of any handle**:
- `Game` has exactly one level accessor: `Game:GetLevel()`. (REPENTOGON adds only `GetLastLevelWithDamage()` / `GetLastLevelWithoutHalfHp()`, and those return `LevelStage` — an enum, not a `Level`.)
- `Level` has no `GetPreviousLevel`, no level-by-index, nothing. Full member list checked.
- `Level`'s dimension parameter covers dimensions **of the current floor only** (`Dimension` enum: CURRENT/-1, NORMAL/0, KNIFE_PUZZLE=MIRROR=MINESHAFT/1, DEATH_CERTIFICATE/2).
- `Level:GetLastRoomDesc()` and `Level:GetPreviousRoomIndex()` are the **same floor** only.

> **UNVERIFIED (inference, flagged):** whether the old `Level`/`RoomDescriptor` memory is physically freed on descent is an engine internal and is not documented anywhere I could reach. It is **moot** — Lua holds no reference path to a previous floor, so a stored `RoomDescriptor` cannot be dereferenced after a floor change regardless.

**Sources:** [Level (vanilla)](https://wofsauge.github.io/IsaacDocs/rep/Level.html) · [Level (REPENTOGON)](https://repentogon.com/Level.html) · [Game](https://wofsauge.github.io/IsaacDocs/rep/Game.html) · [Dimension](https://repentogon.com/enums/Dimension.html)

---

## TASK 3 — Static room data (the promising route)

**QUESTION:** Can a mod read a room's *original, static* STB grid by room config id?

**VERDICT: PARTIAL.**
- **Static entity/pickup spawn positions: YES** — genuinely reachable, and reachable for rooms the player is not in. *This was the surprise finding.*
- **Static per-tile terrain grid (rocks/pits/walls/poop): NO** — no API reaches the STB grid section.

### What the STB data surfaces actually expose

| Class | Access path | Members (VERIFIED) | Tile grid? |
|---|---|---|---|
| `RoomConfigRoom` | `RoomDescriptor.Data` / `.OverrideData` / `RoomConfig.GetRoomByStageTypeAndVariant` | `Difficulty, Doors, Height, InitialWeight, Mode(REP: fixed), Name, OriginalVariant, Shape, SpawnCount, Spawns, StageID, Subtype, Type, Variant, Weight, Width` | **NO** |
| `RoomConfigSpawn` | `RoomConfigRoom.Spawns:Get(i)` | **`X` (int), `Y` (int)** ← grid coords · `Entries, EntryCount, SumWeights, PickEntry(float r)` | pos only |
| `RoomConfigEntry` | `RoomConfigSpawn:PickEntry(r)` | `Type (EntityType), Variant, Subtype, Weight` | — |
| `RoomConfigStage` | `RoomConfig.GetStage(StbType)` | `GetBackdrop, GetBossSpot, GetDisplayName, GetID, GetMusic, GetPlayerSpot, GetRoomSet, GetSuffix, GetXMLName, IsLoaded` + setters | — |
| `LevelGenerator` | **only** via `MC_POST_LEVEL_LAYOUT_GENERATED` callback param | `GetAllRooms(), GetDeadEnds(), GetNonDeadEnds(), PlaceRoom(Col,Row,Shape,Origin)` | **NO** |
| `LevelGeneratorRoom` | from `LevelGenerator` / `MC_PRE_LEVEL_PLACE_ROOM` | `Column(), DoorMask(), GenerationIndex(), IsDeadEnd(), Neighbors(), Row(), Shape()` | **NO** |
| `LevelGeneratorEntry` | `Isaac.LevelGeneratorEntry()` | `SetAllowedDoors(), SetColIdx(), SetLineIdx()` | **NO** |
| `LRoomTileDesc` | `Room:GetLRoomTileDesc()` | `GetHighTopLeft/BottomRight, GetLowTopLeft/BottomRight, GetRandomTile(seed)` → `int[2]` | L-shape geometry only |
| `LRoomAreaDesc` | `Room:GetLRoomAreaDesc()` | same four corners → `Vector` | L-shape geometry only |
| `StbGridType` | **enum only** | see below | — |
| `StbType` | **enum only** | stage ids 0–36 | — |
| `RoomSubType` | **enum only** | shop/treasure/miniboss/etc. subtypes | — |
| `DoorMask` | **enum only** | `1<<0` LEFT0 … `1<<7` DOWN1 | — |

### The key gap, stated precisely

`StbGridType` is the **exact per-tile codec for the STB grid section**:

```
DECORATION=0, ROCK=1000, BOMB_ROCK=1001, ALT_ROCK=1002, MARKED_ROCK/TINTED_ROCK=1003,
ALT_ROCK_MARKED/MARKED_SKULL=1008, EVENT_ROCK=1009, SPIKE_ROCK=1010, FOOLS_GOLD_ROCK=1011,
TNT=1300, RED_POOP=1490, RAINBOW_POOP=1494, CHUNKY/CORN_POOP=1495, GOLDEN_POOP=1496,
BLACK_POOP=1497, HOLY/WHITE_POOP=1498, GIANT_POOP=1499, POOP=1500, CHARMING_POOP=1501,
BLOCK=1900, PILLAR/TALL_BLOCK=1901, SPIKES=1930, RETRACTING_SPIKES=1931, COBWEB=1940,
INVISIBLE_BLOCK=1999, PIT=3000, BUTTON_RAIL/EVENT_RAIL=3002, EVENT_PIT=3009,
KEY_BLOCK/LOCK=4000, PRESSURE_PLATE/BUTTON=4500, DEVIL_STATUE=5000, ANGEL_STATUE=5001,
RAIL=6000, RAIL_PIT=6001, TELEPORTER=6100, TRAP_DOOR/LEVEL_EXIT=9000,
CRAWLSPACE/STAIRCASE=9100, GRAVITY=10000
```

So the *format* is known and exposed **as an enum**, but **no class returns a grid of these values**. Note it contains **no WALL and no DOOR code** — walls/doors in a loaded room come from `RoomShape` + `DoorMask`, not the STB grid section. That is consistent with `RoomConfigRoom` having `Shape`/`Doors`/`Width`/`Height` but no grid member.

There is **no `Stb*` class** in REPENTOGON — the sidebar lists only `StbGridType, StbPoopSubType, StbRailVariant, StbRockSubType, StbTeleporterSubType, StbType`, all under **Enums**. (Verified by complete sidebar enumeration.)

### So what static data *can* you get for an unvisited room?

```lua
local desc = Game():GetLevel():GetRoomByIdx(idx)      -- any room on this floor
local cfg  = desc.Data                                -- RoomConfigRoom, static STB config
-- cfg.Shape / cfg.Width / cfg.Height / cfg.Doors / cfg.Type / cfg.Variant / cfg.StageID / cfg.Subtype
for i = 0, cfg.SpawnCount - 1 do
    local sp = cfg.Spawns:Get(i)
    -- sp.X, sp.Y  = static grid coords of that spawn
    local e = sp:PickEntry(0)                         -- RoomConfigEntry: Type/Variant/Subtype/Weight
end
```

That gives you **the static pedestal / pickup / prop positions and their entity identity** for a room you have never entered — but **not** the rocks/pits/poop/spikes.

**Sources:** [RoomConfig_Room](https://wofsauge.github.io/IsaacDocs/rep/RoomConfig_Room.html) · [RoomConfig_Spawn](https://wofsauge.github.io/IsaacDocs/rep/RoomConfig_Spawn.html) · [RoomConfigEntry](https://wofsauge.github.io/IsaacDocs/rep/RoomConfig_Entry.html) · [REPENTOGON LevelGenerator](https://repentogon.com/LevelGenerator.html) · [LevelGeneratorRoom](https://repentogon.com/LevelGeneratorRoom.html) · [LevelGeneratorEntry](https://repentogon.com/LevelGeneratorEntry.html) · [LRoomTileDesc](https://repentogon.com/LRoomTileDesc.html) · [LRoomAreaDesc](https://repentogon.com/LRoomAreaDesc.html) · [StbGridType](https://repentogon.com/enums/StbGridType.html) · [StbType](https://repentogon.com/enums/StbType.html)

---

## TASK 4 — Snapshot / redraw alternatives

**QUESTION:** Is there any API to snapshot a room as *data*? Can it be used for a past room if hooked at the right time? What's the minimum to persist?

**VERDICT: YES — but only while the room is reachable (current floor). There is no post-hoc route for a left floor.**

### What exists per-layer

| Layer | API | Notes |
|---|---|---|
| Single grid entity | `Room:GetGridEntity(int Index) -> GridEntity \| nil` | live only |
| | `GridEntity:GetGridIndex() -> int`, `GetSaveState() -> GridEntityDesc`, `GetType()`, `GetVariant()`, `State` | |
| Collision per tile | `Room:GetGridCollision(int GridIndex)` · `Room:GetGridCollisionAtPos(Vector)` | both return `GridCollisionClass` |
| Grid geometry | `Room:GetGridWidth()`, `Room:GetGridHeight()`, `Room:GetGridSize()` | **dims confirmed below** |
| Seeds | `Room:GetSpawnSeed()`, `Room:GetDecorationSeed()`, `Room:GetAwardSeed()` | |
| Room metadata | `Room:GetType()`, `GetRoomShape()`, `GetRoomConfigStage()`, `IsFirstVisit()`, `IsClear()` | |
| REPENTOGON | `Room:SaveState()` (void) — *"Saves the current state of the room"* | manual trigger of engine save state |
| REPENTOGON | `Room:GetGridIndexByTile(int GridRow, int GridColumn)` / `(int[2])` | row/col → grid index |
| **Descriptor-level (the real prize)** | **`RoomDescriptor:GetGridEntitiesSaveState() -> GridEntitiesSaveStateVector`** | ← *works off the descriptor, so it reaches rooms you are not standing in* |
| | `RoomDescriptor:GetEntitiesSaveState() -> EntitiesSaveStateVector` | pickups/enemies with `GetPos()` |
| | `RoomDescriptor:GetDecoSaveState() -> EntitiesSaveStateVector` | decorations |
| | `RoomDescriptor:GetDimension() -> Dimension`, `GetNeighboringRooms()`, `Doors` (const int[]) | |

**`GridEntitiesSaveStateVector`**: `Get(int Index) -> GridEntityDesc`, `GetByType(GridEntityType) -> GridEntityDesc`, `__len()`.
**`EntitiesSaveState`** (per entity): `GetB1/GetB2, GetF1/GetF2, GetI1..GetI8, GetType, GetVariant, GetSubType, GetPos, GetGridSpawnIdx, GetInitSeed, GetDropSeed, GetSpawnerType, GetSpawnerVariant, GetU1` (+ setters).
**`GridEntityDesc`** (vanilla): `Initialized, SpawnCount, SpawnSeed, State, Type, VarData, VariableSeed, Variant`.

### ⚠️ Two hard uncertainties on the descriptor route

1. **`GridEntityDesc` has NO grid-index field.** So position recovery depends entirely on `GridEntitiesSaveStateVector:Get(int Index)` interpreting `Index` as the *grid index* rather than a dense sequential index. **UNVERIFIED** — the docs give no description for that parameter. Treat `GetByType(t)` as the only semantically safe accessor.
2. **Do the save states exist for a never-visited room?** The engine writes a room's save state when you leave it. For an untouched room the vector is presumably empty. **UNVERIFIED.**
3. **Does `GetGridEntitiesSaveState()` include the wall ring?** `GridEntityType.GRID_WALL = 15` exists, so walls *are* grid entities, but the save state may only store dynamic ones (walls are reconstructed from the layout). **UNVERIFIED.** Design so you don't need them — derive walls from `Shape` + `Doors`.

**Practical upshot:** the descriptor save-state route is a genuine "same floor, rooms I already cleared" reader. It does **not** survive a floor transition, so it does **not** remove the need to persist data.

### Grid dimensions — CONFIRMED

**A 1×1 room is 15 × 9 = 135 collision tiles**, grid indices **0–134**.

Two independent confirmations:
- `RoomShape` doc's *"Possible Gridindicies"* column: `ROOMSHAPE_1x1 → 0-134`; `1x2 → 0-239` (15×16=240); `2x1 → 0-251` (28×9=252); `2x2 → 0-447` (28×16=448).
- IsaacScript `gridIndexToGridPosition` doc: *"in a 1x1 room, grid index 0 is equal to Vector(-1,-1) and grid index 16 is equal to Vector(0,0)"* → 16 = 1×15+1 ⇒ **width 15**. 135/15 = **height 9**.
- (Cross-check: `RoomShape.ROOMSHAPE_1x1 = 1`, not 0 — REPENTOGON's `GetValidNeighborPlacementLocations` default is `RoomShape = 1`.)

### Minimum data to redraw a room later

| Tier | Fields | Bytes/room (binary) |
|---|---|---|
| **T0 — geometry only** | `Shape`(1) + `DoorMask`/`AllowedDoors`(1) + `Width`(1) + `Height`(1) + `Type`(1) + `Variant`(2) + `StageID`(1) + `BackdropType`(1) | **~9 B** |
| **T1 — + terrain (recognisable picture)** | T0 + one tile-type byte per cell: 135 × 1 B | **~144 B** |
| T1′ — same, RLE-compressed | typical room 20–60 B | **~30–70 B** |
| **T2 — + grid entities** | T1 + per grid entity: `Type`(1) `Variant`(1) `State`(1) `VarData`(1) `gridIndex`(1) ≈ 5–6 B · typically 10–40 non-wall entities | **+60–250 B** → **~0.2–0.4 KB** |
| **T3 — + pickups/props** | T2 + per entity: `Type`(1) `Variant`(1) `SubType`(1) `Pos`(4) `InitSeed`(4) ≈ 11 B · 0–10 entities | **+0–110 B** → **~0.3–0.5 KB** |

Realistic plan: **T1 as the always-on cost (~145 B/room), T2/T3 only for rooms the player actually entered.** A 13×13 level grid caps at 169 cells but real floors are ~13–20 rooms ⇒ **~2–3 KB per floor at T1**, **~5–10 KB per floor at T3**. A 10-floor run at T1 ≈ **25–30 KB**.

### Rendering caveat (design-blocking)

There is **no API that draws a non-current room**. `MC_POST_RENDER` + `Isaac.Render*` / `Sprite` / `Image`, or a custom minimap/HUD, is the only route — the mod must draw from its own stored data. Confirmed by the absence of any "render room" member anywhere and by IsaacScript's entire minimap helper set being *display-flag* manipulation only (`addRoomDisplayFlag`, `setRoomDisplayFlags`, `clearFloorDisplayFlags`, …), never layout drawing.

**Sources:** [Room (vanilla)](https://wofsauge.github.io/IsaacDocs/rep/Room.html) · [GridEntity](https://wofsauge.github.io/IsaacDocs/rep/GridEntity.html) · [GridEntityDesc](https://wofsauge.github.io/IsaacDocs/rep/GridEntityDesc.html) · [REPENTOGON Room](https://repentogon.com/Room.html) · [REPENTOGON RoomDescriptor](https://repentogon.com/RoomDescriptor.html) · [GridEntitiesSaveStateVector](https://repentogon.com/GridEntitiesSaveStateVector.html) · [EntitiesSaveState](https://repentogon.com/EntitiesSaveState.html) · [RoomShape](https://wofsauge.github.io/IsaacDocs/rep/enums/RoomShape.html) · [IsaacScript roomGrid](https://isaacscript.github.io/isaacscript-common/functions/roomgrid/) · [IsaacScript minimap](https://isaacscript.github.io/isaacscript-common/functions/minimap/)

---

## TASK 5 — Familiar / pet stats

**QUESTION:** Can a mod read per-familiar theoretical damage / fire rate?

**VERDICT: NO direct values. PARTIAL — derivable from player stats × a REPENTOGON multiplier.**

### `EntityFamiliar` has no damage or fire-rate field — VERIFIED

Complete vanilla member list (variables **and** functions, full body read):

- **Variables:** `Coins, FireCooldown, HeadFrameDelay, Hearts, IsDelayed, IsFollower, Keys, LastDirection, MoveDirection, OrbitAngleOffset, OrbitDistance, OrbitLayer, OrbitSpeed, Player, RoomClearCount, ShootDirection, State`
- **No `Damage`. No `MaxFireDelay`. No `TearFlags`.** (`TearFlags` is an enum on `EntityPlayer`, not a familiar field.)
- Functions: `AddCoins/AddHearts/AddKeys, AddToDelayed, AddToFollowers, AddToOrbit, FireProjectile(Dir), FollowParent, FollowPosition, GetOrbitDistance, GetOrbitPosition, MoveDelayed, MoveDiagonally, PickEnemyTarget, PlayChargeAnim/PlayFloatAnim/PlayShootAnim, RecalculateOrbitOffset, RemoveFrom*, Shoot()`

`Entity` (the base class) also has **no** `Damage`: only `CollisionDamage`, `HitPoints`, `MaxHitPoints`, `SizeMulti`.

### Config classes don't carry it either — VERIFIED

- **`EntityConfigFamiliar` does not exist.** 404 on both `repentogon.com/EntityConfigFamiliar.html` and `wofsauge.github.io/.../EntityConfigFamiliar.html`. The `EntityConfig` family in the REPENTOGON sidebar is exactly `EntityConfig / EntityConfigBaby / EntityConfigEntity / EntityConfigPlayer`.
- `EntityConfig.GetEntity(EntityType, Variant=-1, SubType=-1) -> EntityConfigEntity` → exposes `GetBaseHP, GetCollisionDamage, GetCollisionInterval, GetCollisionRadius, GetMass, GetFriction, GetShieldStrength, GetStageHP, GetGibFlags, GetEntityTags, GetAnm2Path, GetBossID, ...` — **no damage, no fire delay**.
- `EntityConfig.GetPlayer(PlayerType) -> EntityConfigPlayer`, `GetBaby(BabySubType) -> EntityConfigBaby` — character/baby metadata.

### What IS readable

| Value | API | Status |
|---|---|---|
| Player tear damage | `EntityPlayer.Damage` (float) | VERIFIED |
| Player fire rate | `EntityPlayer.MaxFireDelay` (int) | VERIFIED |
| Player tear flags | `EntityPlayer.TearFlags` (`TearFlags`) | VERIFIED |
| **Familiar damage multiplier** | **`EntityFamiliar:GetMultiplier() -> float`** (REPENTOGON) | VERIFIED — *"Returns the 'multiplier' for the familiar, from effects such as BFFS! or Hive Mind. Typically used to multiply things such as familiar damage."* Values: BFFS!/Hive Mind **×2.0**, Tainted Bethany **×0.75** |
| Source item | `EntityFamiliar:GetItemConfig() -> ItemConfigItem` (REPENTOGON) | VERIFIED — `nil` if not item-spawned |
| Familiar's weapon | `EntityFamiliar:GetWeapon()`, `GetActiveWeaponEntity()`, `GetActiveWeaponNumFired()` (REPENTOGON) | VERIFIED |
| Familiar identity | `EntityFamiliar.Type/Variant/SubType`, `FamiliarVariant` enum | VERIFIED |
| Orbit/geometry | `OrbitDistance`, `OrbitLayer`, `OrbitSpeed`, `OrbitAngleOffset` | VERIFIED |

> **So:** familiar tear damage = player damage × per-familiar constant. That per-familiar constant lives in the engine's hardcoded familiar behaviors (not in any XML/config the Lua API exposes), **except** for the BFFS!/Hive Mind/T.Bethany multiplier which REPENTOGON now exposes. Any "theoretical DPS" needs a hand-maintained table of per-`FamiliarVariant` coefficients — **that table is not queryable via the API.**

**Sources:** [EntityFamiliar (vanilla)](https://wofsauge.github.io/IsaacDocs/rep/EntityFamiliar.html) · [Entity](https://wofsauge.github.io/IsaacDocs/rep/Entity.html) · [EntityPlayer](https://wofsauge.github.io/IsaacDocs/rep/EntityPlayer.html) · [REPENTOGON EntityFamiliar](https://repentogon.com/EntityFamiliar.html) · [EntityConfig](https://repentogon.com/EntityConfig.html) · [EntityConfigEntity](https://repentogon.com/EntityConfigEntity.html)

---

## TASK 6 — Enum tables (VERIFIED)

### `RoomType`
| Val | Name | Val | Name |
|---|---|---|---|
| 0 | `ROOM_NULL` | 15 | `ROOM_ANGEL` |
| 1 | `ROOM_DEFAULT` | 16 | `ROOM_DUNGEON` (crawlspace) |
| 2 | `ROOM_SHOP` | 17 | `ROOM_BOSSRUSH` |
| 3 | `ROOM_ERROR` | 18 | `ROOM_ISAACS` |
| **4** | **`ROOM_TREASURE`** | 19 | `ROOM_BARREN` |
| **5** | **`ROOM_BOSS`** | 20 | `ROOM_CHEST` |
| 6 | `ROOM_MINIBOSS` | 21 | `ROOM_DICE` |
| **7** | **`ROOM_SECRET`** ← *not devil* | 22 | `ROOM_BLACK_MARKET` |
| 8 | `ROOM_SUPERSECRET` | 23 | `ROOM_GREED_EXIT` |
| 9 | `ROOM_ARCADE` | 24 | `ROOM_PLANETARIUM` |
| 10 | `ROOM_CURSE` | 25 | `ROOM_TELEPORTER` (unused) |
| 11 | `ROOM_CHALLENGE` | 26 | `ROOM_TELEPORTER_EXIT` (unused) |
| 12 | `ROOM_LIBRARY` | 27 | `ROOM_SECRET_EXIT` |
| 13 | `ROOM_SACRIFICE` | 28 | `ROOM_BLUE` |
| **14** | **`ROOM_DEVIL`** ← *the actual devil value* | 29 | `ROOM_ULTRASECRET` |
| | | 30 | `NUM_ROOMTYPES` / `ROOM_DEATHMATCH` (DLC-gated) |

**Correction to the user's guess:** treasure=4 ✓, boss=5 ✓, but **devil=14 and 7 is secret**. `NUM_ROOMTYPES`=30 or 31 depending on DLC (the doc lists both rows).

### `RoomShape`  (note: starts at **1**)
`1 ROOMSHAPE_1x1 (grid 0-134)` · `2 ROOMSHAPE_IH` · `3 ROOMSHAPE_IV` · `4 ROOMSHAPE_1x2 (0-239)` · `5 ROOMSHAPE_IIV` · `6 ROOMSHAPE_2x1 (0-251)` · `7 ROOMSHAPE_IIH` · `8 ROOMSHAPE_2x2 (0-447)` · `9 ROOMSHAPE_LTL` · `10 ROOMSHAPE_LTR` · `11 ROOMSHAPE_LBL` · `12 ROOMSHAPE_LBR` · `13 NUM_ROOMSHAPES`

### `GridEntityType`
| Val | Name | Val | Name |
|---|---|---|---|
| 0 | `GRID_NULL` | 14 | `GRID_POOP` |
| 1 | `GRID_DECORATION` | **15** | **`GRID_WALL`** |
| 2 | `GRID_ROCK` | **16** | **`GRID_DOOR`** |
| 3 | `GRID_ROCKB` (block) | 17 | `GRID_TRAPDOOR` |
| 4 | `GRID_ROCKT` (tinted) | 18 | `GRID_STAIRS` |
| 5 | `GRID_ROCK_BOMB` | 19 | `GRID_GRAVITY` |
| 6 | `GRID_ROCK_ALT` (pot/mushroom/skull) | 20 | `GRID_PRESSURE_PLATE` |
| 7 | `GRID_PIT` | 21 | `GRID_STATUE` |
| 8 | `GRID_SPIKES` | 22 | `GRID_ROCK_SS` (super tinted) |
| 9 | `GRID_SPIKES_ONOFF` | 23 | `GRID_TELEPORTER` |
| 10 | `GRID_SPIDERWEB` | 24 | `GRID_PILLAR` |
| 11 | `GRID_LOCK` (key block) | 25 | `GRID_ROCK_SPIKED` |
| 12 | `GRID_TNT` | 26 | `GRID_ROCK_ALT2` (tinted skull) |
| 13 | `GRID_FIREPLACE` (unused) | 27 | `GRID_ROCK_GOLD` |

### `GridCollisionClass`
`0 COLLISION_NONE` · `1 COLLISION_PIT` · `2 COLLISION_OBJECT` · `3 COLLISION_SOLID` · `4 COLLISION_WALL` · `5 COLLISION_WALL_EXCEPT_PLAYER`

### `DoorSlot` / `DoorMask`
`-1 NO_DOOR_SLOT` · `0 LEFT0` · `1 UP0` · `2 RIGHT0` · `3 DOWN0` · `4 LEFT1` · `5 UP1` · `6 RIGHT1` · `7 DOWN1` · `8 NUM_DOOR_SLOTS`
`DoorMask` = `1 << DoorSlot` for each of the 8.

### `Dimension`
`-1 CURRENT` · `0 NORMAL` · `1 KNIFE_PUZZLE = MIRROR = MINESHAFT` · `2 DEATH_CERTIFICATE`

### `StbType` (stage id, for `RoomConfig.GetStage`)
`0 SPECIAL_ROOMS, 1 BASEMENT … 12 SCARRED_WOMB, 13 BLUE_WOMB, 14 SHEOL, 15 CATHEDRAL, 16 DARK_ROOM, 17 CHEST, 26 THE_VOID/VOID, 27 DOWNPOUR, 28 DROSS, 29 MINES, 30 ASHPIT, 31 MAUSOLEUM, 32 GEHENNA, 33 CORPSE, 34 MORTIS, 35 HOME, 36 ASCENT`
(`RoomConfigRoom.StageID` uses the same numbering; the IsaacDocs table notes **Stage ID 34 does not exist** in the vanilla list while REPENTOGON maps 34→`MORTIS`.)

**Sources:** [RoomType](https://wofsauge.github.io/IsaacDocs/rep/enums/RoomType.html) · [RoomShape](https://wofsauge.github.io/IsaacDocs/rep/enums/RoomShape.html) · [GridEntityType](https://wofsauge.github.io/IsaacDocs/rep/enums/GridEntityType.html) · [GridCollisionClass](https://wofsauge.github.io/IsaacDocs/rep/enums/GridCollisionClass.html) · [DoorSlot](https://wofsauge.github.io/IsaacDocs/rep/enums/DoorSlot.html) · [DoorMask](https://repentogon.com/enums/DoorMask.html) · [Dimension](https://repentogon.com/enums/Dimension.html) · [StbType](https://repentogon.com/enums/StbType.html)

---

## ✅ CONCLUSION — so the mod must persist X, Y, Z

**The core question's answer: NO — a room identifier alone is not enough. There is no path from a stored id to that room's layout, on any floor you have left, and not even for an unvisited room on the current floor.**

Breakdown of why, per route:

| Route back to a past room's layout | Works? |
|---|---|
| `Room` object for a past room | **NO** — `Level:GetCurrentRoom()` / `Game():GetRoom()` only |
| `Level` for a past floor | **NO** — `Game:GetLevel()` is the only accessor; no previous-level handle exists |
| `RoomDescriptor:GetGridEntitiesSaveState()` | **Same floor only** — and semantics of `Get(Index)` + empty-for-unvisited are unverified |
| Static STB grid by `(StageID, Type, Variant)` | **NO** — `RoomConfigRoom` has no tile grid; `StbGridType` is an enum with no reader |
| Static STB **spawn** positions by room config | **YES** — `Data.Spawns:Get(i).X/.Y` + `PickEntry(r)`; this is the only static-layout data exposed |
| Re-render a non-current room with an engine call | **NO** — must draw it yourself in `MC_POST_RENDER` |

### The mod must persist, per room:

1. **Identity** — `LevelStage` + `StageType` (floor), `Dimension`, and `ListIndex` (**not** `GridIndex`; docs recommend `ListIndex`) — or `SafeGridIndex` + `Dimension` if you prefer geometry. ≈ **4–6 B**
2. **Geometry** — `RoomShape` (1 B), `AllowedDoors`/`DoorMask` (1 B). *This is what lets you draw walls.* ≈ **2 B**
3. **Theme** — `BackdropType` (1 B) + `RoomType` (1 B) + `RoomConfig.StageID`/`Variant` (3 B), so the redraw uses the right tileset/palette. ≈ **5 B**
4. **Terrain grid** — 135 bytes, one tile-type byte per cell (your own ~20-value palette mapped from `GridEntityType`). Non-negotiable; this is the picture. ≈ **135 B**
5. **Optional fidelity** — grid entities (`Type/Variant/State/VarData/gridIndex`, ~5–6 B each, 10–40 per room) and pickups (`Type/Variant/SubType/Pos/InitSeed`, ~11 B each, 0–10 per room).

### Byte budget

| Tier | Per 1×1 room | Per floor (~13–20 rooms) | 10-floor run |
|---|---|---|---|
| **Minimum for a recognisable picture** (1–4) | **≈ 145 B** (≈ 30–70 B with RLE) | **≈ 2–3 KB** | **≈ 25–30 KB** |
| **+ grid entities** (5a) | ≈ 0.2–0.4 KB | ≈ 5 KB | ≈ 50 KB |
| **+ pickups / pedestals** (5b) | ≈ 0.3–0.5 KB | ≈ 8 KB | ≈ 80 KB |

Multi-cell rooms scale by quadrant count (2×1 = 252 B, 2×2 = 448 B at T1).

### Cheapest correct architecture

Persist **T1 (~145 B/room)** for every room, and *additionally* persist **T2/T3** only for rooms the player actually entered. If REPENTOGON's `RoomDescriptor:GetGridEntitiesSaveState()` turns out to key by grid index (must be tested in-game), you can skip writing your own terrain capture for **same-floor revisits** and only persist across floor transitions.

---

## Uncertainty register (explicit)

| # | Item | Status |
|---|---|---|
| 1 | REPENTOGON API surface documented is **Repentance+ 1.9.7.12**, not 1.7.9 | **VERSION MISMATCH — blocking for design** |
| 2 | `GridEntitiesSaveStateVector:Get(int Index)` — is `Index` a grid index? | **UNVERIFIED** (docs give no description) |
| 3 | Do descriptor save states exist for never-visited rooms? | **UNVERIFIED** (presumed empty) |
| 4 | Does `GetGridEntitiesSaveState()` include the wall ring? | **UNVERIFIED** |
| 5 | Is the old `Level` physically freed on descent? | **UNVERIFIED** — internal, undocumented; moot for Lua |
| 6 | Whether `Room:SaveState()` writes into the `RoomDescriptor` save-state slots | **UNVERIFIED** (strongly implied by naming) |
| 7 | `Room:GetGridWidth()` returning exactly 15 for 1×1 | **VERIFIED indirectly** (RoomShape 0–134 + IsaacScript index-16 math), not from a literal doc sentence |
| 8 | Per-`FamiliarVariant` damage coefficients | **NOT IN ANY API** — hand-maintained table required |

## Sources
- IsaacDocs (vanilla Repentance API): <https://wofsauge.github.io/IsaacDocs/rep/>
- REPENTOGON docs (Repentance+): <https://repentogon.com/>
- IsaacScript docs (independent cross-check on grid math): <https://isaacscript.github.io/isaacscript-common/functions/roomgrid/>

*Access note: `curl --ssl-no-revoke` is required from this machine — the failure was `CRYPT_E_REVOCATION_OFFLINE`, not a blocked host.*
