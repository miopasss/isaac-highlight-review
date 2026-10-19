# Static RoomConfig route for schematic room cards — targeted fact-check

**Scope note (matters for every answer).** Two different doc corpora are in play:
- **Vanilla 1.7.9 API** = https://wofsauge.github.io/IsaacDocs/rep/ (that site keeps a separate "Repentance+" tab, so `/rep/` is the pre-Repentance+ corpus).
- **REPENTOGON / Repentance+ 1.9.7.12** = https://repentogon.com/ (`/install.html` names `1.9.7.12`; copyright 2026). These pages are a **delta doc**: unchanged vanilla classes are linked *out* to wofsauge. Proof: repentogon.com/RoomConfig.html links "Room" to `https://wofsauge.github.io/IsaacDocs/rep/RoomConfig_Room.html`, and `RoomConfigSpawn.html` simply 404s there (nothing changed).
Method: HTML pages from both sites + REPENTOGON's own C++ source (GitHub API, `--ssl-no-revoke`). **No in-game test was run** — every claim is doc/source-derived; inferences are flagged.

---

## 1. Does `RoomConfig` exist in Lua? `GetRoomByStageTypeAndVariant`?

**VERDICT: NO in vanilla Repentance 1.7.9b. YES only with REPENTOGON (both the 1.7.9b-era 1.0.x line and the 1.9.7 line).**

Evidence:
- In the 1.7.9 docs `RoomConfig` is **only a nav grouping** (RoomConfig → Entry / Room / Spawn), there is no class page: `https://wofsauge.github.io/IsaacDocs/rep/RoomConfig.html` → **HTTP 404**. The whole-site search index (`/rep/search/search_index.json`) has **0 hits** for `GetRoomByStageTypeAndVariant` and 0 for `StbType`.
- REPENTOGON docs page **`Global Class "RoomConfig"`** — "You can get this class by using the RoomConfig global table. Note that to call these functions, you must use a `.` (period) instead of a `:` (colon)!" Members: `AddRooms`, `GetRandomRoom`, `GetRoomByStageTypeAndVariant`, `GetStage`, `LoadStb`. → https://repentogon.com/RoomConfig.html
- Full signature, verbatim from that page:
  `RoomConfigRoom GetRoomByStageTypeAndVariant ( StbType Stage, RoomType Type, int Variant, int Mode = -1 )`
  ("Returns a RoomConfigRoom corresponding to the given params.")
- **Decisive proof it is REPENTOGON-provided, not vanilla:** the binding *creates* the global table inside a LuaEngine hook —
  `lua_newtable(L); lua::TableAssoc(L,"GetRoomByStageTypeAndVariant",…); … lua_setglobal(L,"RoomConfig");` in `HOOK_METHOD(LuaEngine, RegisterClasses, …)`
  → https://github.com/TeamREPENTOGON/REPENTOGON/blob/main/repentogon/LuaInterfaces/Room/LuaRoomConfig.cpp
- **1.7.9b-era check:** the same binding, same 4-arg signature, exists on branch `release/1.0.12` (REPENTOGON 1.0.12e, Sep–Nov 2024 = last pre-Repentance+ line) → https://github.com/TeamREPENTOGON/REPENTOGON/blob/release/1.0.12/repentogon/LuaInterfaces/Room/LuaRoomConfig.cpp
- The *underlying C++* is vanilla retail: `__thiscall RoomConfig_Room* RoomConfig::GetRoomByStageTypeAndVariant(uint32_t stage, uint32_t type, uint32_t variant, int32_t mode)` → https://github.com/TeamREPENTOGON/REPENTOGON/blob/main/libzhl/functions/RoomConfig.zhl (libzhl = signatures read out of the shipped binary). So the capability is in the retail 1.7.9b exe; only the **Lua binding** is REPENTOGON's.
- Arg validation in the binding: stage `0..36`, type `1..29`, mode optional (default `-1`, silently clamped to `-1` if outside `[-2,1]`). **So you pass a plain integer `Data.StageID`; no enum object is required.**

---

## 2. `RoomConfigRoom` — complete member list

**VERDICT: YES for all eight you asked about (`Shape`, `Doors`, `Type`, `Variant`, `Subtype`, `Name`, `Difficulty`, `Weight`, `Spawns`). No Lua methods.**

Verbatim from the Variables section (page order, 1.7.9 docs):

| member | declared type |
|---|---|
| `Difficulty` | `const int` |
| `Doors` | `const int` |
| `Height` | `const int` |
| `InitialWeight` | `const float` |
| `Mode` | `const userdata` ← **bug** |
| `Name` | `const string` |
| `OriginalVariant` | `const int` |
| `Shape` | `const RoomShape` |
| `SpawnCount` | `const int` |
| `Spawns` | `const RoomConfigSpawns` |
| `StageID` | `const int` |
| `Subtype` | `const int` |
| `Type` | `const RoomType` |
| `Variant` | `const int` |
| `Weight` | `const float` |
| `Width` | `const int` |

Details:
- `Doors` doc text: "Returns a bit mask of the positions of valid door positions in this room. It is a combination of bit flags of the DoorSlotFlag enum" — followed by `LEFT0 = 1 << DoorSlot.LEFT0` … `DOWN1 = 1 << DoorSlot.DOWN1` (8 slots).
- `Mode` carries an explicit **Bug** callout: "This variable is broken and returns userdata." Fixed by REPENTOGON — the 1.9.7 page lists only "**Modified Variables → Mode → const int** — Same as default, but now returns a proper integer value instead of userdata"; the same getter fix is already on `release/1.0.12` (`Lua_RoomConfigRoomGetMode` pushing `roomConfig->Mode` as an integer).
- The page has **no Functions section** → nothing callable on the object.
- C++ layout cross-check (`RoomConfigRoom.zhl`, identical offsets on `release/1.0.12`, so same in 1.7.9b): `StageId 0x0 · Mode 0x4 · Type 0x8 · Variant 0xC · Subtype 0x10 · Name(std::string) 0x14 · Difficulty 0x2C · InitialWeight 0x30 · Weight 0x34 · Doors(uint32) 0x38 · QuestDoors 0x3C · Spawns(RoomSpawn*) 0x40 · SpawnCount(uint16) 0x44 · Width(int8) 0x46 · Height(int8) 0x47 · Shape(int32) 0x48 · Flags 0x4C · MergedData[2] 0x50 · originalVariant 0x58` · `sizeof = 0x5C`.

Sources: https://wofsauge.github.io/IsaacDocs/rep/RoomConfig_Room.html · https://github.com/TeamREPENTOGON/REPENTOGON/blob/main/libzhl/functions/RoomConfigRoom.zhl · https://repentogon.com/RoomConfigRoom.html

---

## 3. `RoomConfigSpawn`: `X` / `Y`, iteration, and staticness

**VERDICT: YES — `X` and `Y` exist, they are authored grid coordinates from the room file, and they are readable for a room the player has never entered.**

Verbatim (1.7.9 page):
- Variables: `RoomConfigEntries Entries` · `int EntryCount` · `float SumWeights` · `int X` · `int Y`
- Function: `const RoomConfigEntry PickEntry ( float r )` — "r is a value between 0 and 1"

Iteration (there is no `Spawns` property on the spawn — iteration is on the room's collection):
- `desc.Data.Spawns` is class **`RoomConfigSpawns`**: `RoomConfigSpawn Get(int idx)`, `const int Size` ("The amount of spawnables in the list"), operator `__len` (`#`) — "Returns the amount of spawnables in this list".
- `spawn.Entries` is class **`RoomConfigEntries`**: `RoomConfigEntry Get(int idx)`, `const int Size`, `__len`.
- So: `for i = 0, spawns.Size - 1 do local sp = spawns:Get(i) end` (0-based `Get`).

Staticness — three independent legs:
1. **Data layout**: C++ `struct RoomSpawn { uint16_t X; uint16_t Y; RoomEntry* Entries; uint8_t CountEntries; float SumWeights; }` (16 bytes) — a plain value array hanging off `RoomConfig_Room::Spawns`, not a live-room structure.
2. **When it is filled**: `RoomConfig::LoadStageBinary(unsigned int Stage, unsigned int Mode)` + `RoomConfig::read_room(RoomSet* set, int idx, int stageId, KAGE_Filesys_IFile* file)` parse the stage's `.stb` files at stage load (also declared in `RoomConfig.zhl`). Nothing in that path requires the room to have been entered.
3. **Semantics**: the reason `PickEntry(float r)` exists is that a spawn point holds a *weighted list of alternatives* that is only resolved when the room is actually instantiated. The static side is "where + what could be there", never "what was there".

Coordinate space: **grid, not pixels** — REPENTOGON's own code passes spawn coords straight into the vanilla door helper `RoomConfig::get_door_from_position(roomSpawn.X, roomSpawn.Y, room.Shape)`, and its Lua-room builder reads fields literally named `"GRIDX"`/`"GRIDY"` into `RoomSpawn.X/Y`.
⚠️ **Flagged uncertainty:** the prose docs never *state* the coordinate convention. It is the **13×7 config grid** (`Width`=13, `Height`=7 defaults; shape→dims table `{13,7},{13,14},{26,7},{26,14},…`), **not** the 15×9 = 135 live terrain grid — so expect a `(+1,+1)` offset when converting to `Room:GetGridPosition`/`GridIndex`. That offset is my inference from the two grid sizes, **not** verified against a primary source — check empirically on a known room.

Sources: https://wofsauge.github.io/IsaacDocs/rep/RoomConfig_Spawn.html · https://wofsauge.github.io/IsaacDocs/rep/CppContainer_ArrayProxy_RoomConfigSpawns.html · https://wofsauge.github.io/IsaacDocs/rep/CppContainer_ArrayProxy_RoomConfigEntries.html · https://github.com/TeamREPENTOGON/REPENTOGON/blob/main/libzhl/functions/RoomSpawn.zhl

---

## 4. `RoomConfigEntry` / `RoomConfigSpawnEntry`

**VERDICT: `RoomConfigEntry` exists; there is NO `RoomConfigSpawnEntry` class.**

Verbatim (1.7.9 page, all four members, no methods):
`int Subtype` · `EntityType Type` · `int Variant` · `float Weight`

- C++ struct is `RoomEntry` (Lua name `RoomConfigEntry`); reached via `RoomConfigSpawn:PickEntry(r)` or `spawn.Entries:Get(i)`.
- ⚠️ Decay: `Type` is declared `EntityType` but REPENTOGON's validity asserts show the field also carries non-EntityType "room spawn type" values (e.g. their `eRoomSpawnType::SPAWN_PRESSURE_PLATE`). Don't assume every entry `Type` is a legal `EntityType` when filtering for pedestals.
- Also from REPENTOGON: "The game allows multiple spawns to have the same coordinates" — one tile can host several spawn points.

Source: https://wofsauge.github.io/IsaacDocs/rep/RoomConfig_Entry.html

---

## 5. Stable identity for a static re-query

**VERDICT: YES on all four fields — `Data` is a `RoomConfigRoom`, and `Data.StageID` / `.Type` / `.Variant` / `.Mode` all exist. But "(StageID,Type,Variant,Mode) is a unique key" is NOT documented — treat it as probable, not verified.**

- `RoomDescriptor.Data` → declared type **`RoomConfigRoom`** (C++ `RoomConfig_Room*`). Also `RoomDescriptor.OverrideData` → `RoomConfigRoom`, doc: "The room variant is in Data. Because Room::Init uses a mix of data, one from level layout and one from replacement data like minibosses, we need to hold the new room data somewhere." → prefer **`desc.OverrideData or desc.Data`** if you want the *effective* config.
- `Data.StageID` = "The ID of the stage the room was designed for" (Stage-ID table on the same page: 0 Special Rooms … 33 Corpse, **34 does not exist**, 35 Home, 36 Backwards/Ascent). `Data.Type` (`RoomType`), `Data.Variant` (int), `Data.Mode` (int — but **userdata in vanilla**, int with REPENTOGON).
- **`StbType` argument:** `StbType` does **not** exist in 1.7.9 Lua (0 hits in the 1.7.9 search index). The documented `StbType Stage` is just an integer stage id (`luaL_checkinteger`, validated `0..36`) → **pass `desc.Data.StageID` directly**. The enum only appears in the 1.9.7 docs: `SPECIAL_ROOMS 0, BASEMENT 1 … HOME 35, ASCENT 36` (and `MORTIS 34`, a Repentance+ stage absent from 1.7.9). → https://repentogon.com/enums/StbType.html
- **Uniqueness (the part that matters for you):** not stated anywhere. Structural evidence *for* uniqueness: `RoomSet` keeps `variantSetMap` and `RoomConfig_VariantSet::AddUnique(variant)` bumps to `upperBound + 1` when a variant is already taken — i.e. one room per (type, variant) per stage-mode set, with collisions auto-resolved on insert. Evidence *against* relying on it: REPENTOGON's own room-identity struct is stricter — `RoomIdentifier { int stageId; int mode; int type; uint32_t variant; int shape; std::string name; }` with `tie() == (stageId, mode, type, variant, shape, name)` — shape **and** name are part of "which room is this". → https://github.com/TeamREPENTOGON/REPENTOGON/blob/main/repentogon/RoomConfigUtility.h
- ⚠️ **Second gotcha, also inference:** `OriginalVariant` exists because variants get synthesized at runtime; `RoomConfigRoom.zhl` defines `BOSS_DOUBLE_TROUBLE_START = 3700` / `BOSS_DOUBLE_TROUBLE_END = 3850`, and `MergedData[2]` holds merged boss configs. If `Data.Variant ~= Data.OriginalVariant`, the value is likely synthetic and the authored variant is `Data.OriginalVariant` — try that as the lookup fallback. **Not documented prose; verify in-game on a Double Trouble room.**

Sources: https://wofsauge.github.io/IsaacDocs/rep/RoomDescriptor.html · https://github.com/TeamREPENTOGON/REPENTOGON/blob/main/libzhl/functions/RoomSet.zhl · https://github.com/TeamREPENTOGON/REPENTOGON/blob/main/libzhl/functions/RoomConfigVariantSet.zhl

---

## 6. Shape and doors without touching the grid

**VERDICT: YES for both, via `.Data`. Two important caveats.**

- `RoomDescriptor.Data.Shape` → `const RoomShape` — the authored shape. Footprint comes free: shape→`(width,height)` is a fixed table in the binary (`{13,7} 1x1, {13,14} 1x2, {26,7} 2x1, {26,14} 2x2, …`, one entry per `NUM_ROOMSHAPES`), and `Data.Width` / `Data.Height` are exposed anyway.
- `RoomDescriptor.Data.Doors` → `const int` DoorSlotFlag bitmask of **valid door positions** — static.
- ⚠️ **Caveat A:** `Data.Doors` is the *authored potential* door mask, not "doors that were physically there when I visited". For the live set use either `RoomDescriptor.AllowedDoors` — vanilla 1.7.9 doc: "This variable contains userdata and is therefore not useable"; REPENTOGON 1.9.7: "Now properly returns a value. Returns a bitmask corresponding to which door slots are currently enabled" — or `Room:GetDoor(DoorSlot)` (vanilla: "Returns the GridEntityDoor at the given DoorSlot position. Returns nil if no Door is located there").
- ⚠️ **Caveat B — name collision:** `RoomDescriptor.Doors` (no `.Data`) is a **different, REPENTOGON-1.9.7-only** member: `const int[]`, "Allows you to check which level grid index each DoorSlot in the room connects to… `-1` if the RoomShape does not allow a door in that slot." Do not use it as a door mask.

Sources: https://wofsauge.github.io/IsaacDocs/rep/RoomDescriptor.html · https://wofsauge.github.io/IsaacDocs/rep/Room.html · https://repentogon.com/RoomDescriptor.html

---

## 7. Version scope: 1.7.9b vs Repentance+ 1.9.7.12

| Capability | 1.7.9b **vanilla** | 1.7.9b **+ REPENTOGON** (1.0.x line) | 1.9.7.12 **+ REPENTOGON** (1.1.x) | Documented where |
|---|---|---|---|---|
| `RoomConfigRoom` + `Shape`/`Doors`/`Width`/`Height`/`Spawns`/`SpawnCount`/`StageID`/`Type`/`Variant`/`Subtype`/`Name`/`Difficulty`/`Weight`/`InitialWeight`/`OriginalVariant` | ✅ | ✅ | ✅ | 1.7.9 docs (unchanged in 1.9.7 — that page only lists `Mode` as modified) |
| `RoomConfigRoom.Mode` usable as int | ❌ userdata ("broken") | ✅ fixed | ✅ fixed | 1.7.9 docs (bug) / repentogon.com/RoomConfigRoom.html (fix) |
| `RoomConfigSpawn.X` / `.Y`, `.Entries`, `.EntryCount`, `.PickEntry`; `RoomConfigSpawns/Entries` `Get`/`Size`/`#` | ✅ | ✅ | ✅ | 1.7.9 docs; no 1.9.7 page exists (delegated = unchanged) |
| `RoomConfigSpawnEntry` class | ❌ doesn't exist | ❌ | ❌ | — |
| **`RoomConfig` global table** (`GetRoomByStageTypeAndVariant`, `GetRandomRoom`, `GetStage`, `AddRooms`, `LoadStb`) | ❌ **absent** (404 page, 0 search hits) | ✅ (verified on `release/1.0.12`) | ✅ | **1.9.7/REPENTOGON docs only** |
| `StbType` enum | ❌ | ❌ (not in 1.7.9 docs; binding takes an int) | ✅ enum page | **1.9.7 docs only** |
| `RoomDescriptor.AllowedDoors` | ❌ userdata | ✅ fixed | ✅ fixed | 1.9.7 docs (fix) / 1.7.9 docs (bug) |
| `RoomDescriptor.Doors` (`int[]` neighbour indices) | ❌ | ❌ (not on the 1.7.9-era branch) | ✅ | **1.9.7 docs only** |
| Underlying C++ `RoomConfig::GetRoomByStageTypeAndVariant` | ✅ in the exe (libzhl signature) | ✅ | ✅ | libzhl `.zhl` |

Version mapping honesty: the 1.0.x releases (last: `1.0.12e`, 2024-11-03) predate the 1.1.x line, and `release/1.0.12`'s `LuaRoomConfig.cpp` / `RoomConfigRoom.zhl` are byte-identical in the relevant parts to `main`. That the 1.0.x line targets 1.7.9b is **inferred from release dates + the 1.1.x line's Repentance+ content**, not from an explicit statement I could find.

---

## 8. If the static route cannot deliver shape/doors — cheapest alternative

It *can* deliver them, so the alternative is only needed if you want to avoid REPENTOGON or avoid the uniqueness assumption. Cheapest capture-time reads (all **vanilla 1.7.9b**, no grid iteration):
- `local cfg = desc.OverrideData or desc.Data` → `cfg.Shape`, `cfg.Doors`, `cfg.Width`, `cfg.Height`;
- or `Room:GetRoomShape()`, `Room:GetGridWidth()`, `Room:GetGridHeight()`, and `Room:GetDoor(slot) ~= nil` for `slot = 0..7` if you want the doors that physically existed.

**Minimal persisted payload: 2 bytes.** shape = 4 bits (13 `RoomShape` values), live door mask = 8 bits (8 `DoorSlot`s) → 12 bits total. Width/height need 0 extra bits (derived from shape). Optional pedestal pins: **1 byte each** (`x` 4 bits + `y` 3 bits, 13×7 grid). Compare with 135 bytes for the terrain grid — i.e. the whole card costs ~2–4 bytes plus whatever pedestals you pin.

---

## Bottom line: can a schematic room card be rebuilt from a stored room identity alone?

**Partially — and I would not ship it that way.** Shape, footprint and the door *mask* are genuinely static: `RoomDescriptor.Data.Shape` and `RoomDescriptor.Data.Doors` are fields of the parsed room config (offsets `0x48` / `0x38` in `RoomConfig_Room`), filled when the stage's `.stb` is read at stage load, so a room the player never entered is fully described and no 135-tile grid is involved. The catch is the *re-query*: `RoomConfig.GetRoomByStageTypeAndVariant(Stage, Type, Variant, Mode)` exists **only with REPENTOGON** — vanilla 1.7.9b has no `RoomConfig` global table at all (the C++ member exists in the retail exe, but is not bound to Lua), so "store identity, resolve later" is a hard dependency on REPENTOGON plus on the same mod set being loaded (modded rooms enter via `AddRooms` / `LoadStb`, both REPENTOGON-only). On top of that, `(StageID, Type, Variant, Mode)` is not a documented unique key — the engine's variant-set structure implies one room per (type, variant) per stage-mode set, but REPENTOGON's own `RoomIdentifier` needs `shape` + `name` as well, `Data.Mode` is userdata-broken in vanilla, and Double Trouble boss rooms can carry a synthetic variant in 3700–3850 whose authored value lives in `Data.OriginalVariant`. Pedestals are the weakest link: `Data.Spawns` gives authored spawn *points* with weighted alternative entries (`PickEntry`), so it reproduces "a pedestal goes here", never "the item I actually saw" — shops, devil deals, Jera'd or effect-created pedestals are runtime-only. My recommendation: treat the 2-byte payload as mandatory at capture time — **`shape` (4 bits) + `doors` (8 bits), read from `desc.OverrideData or desc.Data`; add `1 byte per pedestal` (`x`,`y` packed) if the card must show the pedestals you actually saw** — and treat `RoomConfig.GetRoomByStageTypeAndVariant` as an optional enrichment/cross-check (it can supply `Width`, `Height`, `SpawnCount`, authored spawn points and `Name`), not as the source of truth. Two things I could not verify and you should test in-game: the exact `(+1,+1)` / 15-stride offset between config spawn coordinates and `Room:GetGridPosition`, and the `OriginalVariant` fallback behaviour on Double Trouble rooms.
