# Prior art: "post-run book recap with per-room power curve" (Isaac: Repentance)

Research date: 2026-10-19. Research report only — no mod code was written.

## Read this first: research limitations

- **steamcommunity.com (and therefore all Steam Workshop item pages) was unreachable from this environment** (`fetch failed` at the network layer, for every URL and subdomain tried). Workshop mods below are identified by the IDs that appear in search-engine result URLs, and characterised from (a) the mod's GitHub source/README where one exists, (b) search-result titles/snippets. Entries resting only on a snippet are marked **[snippet only]**.
- **reddit.com, fandom.com, smods.ru, goodmods.\*, huijiwiki** were also blocked (403/Cloudflare/fetch failure), so community discussion quotes are scarce; GitHub repositories, GitHub search API, jsDelivr mirrors of GitHub files, moddingofisaac.com, isaacscript.github.io and repentogon.com *were* reachable and are the backbone of this report.
- I read actual source/READMEs for: Isaac Run Logger, [F9] Run Tracker, Stats+, Missing HUD 2, TFOI, Scoresheet in Vanilla. That is where the strongest claims come from.

---

## 1. Existing mods that already do part of this

### 1a. Run history / recap / trackers

**Isaac Run Logger** — https://github.com/haydenr42/Isaac-Run-Logger · Workshop `?id=3812241982`
Repentance stats tracker that logs *every* run and shows aggregated stats in an in-game window with tabs: Summary, Items (pickup/seen/encounter rate/pick rate/avg floor found/win rate/hits-per-min after pickup), Damage Sources (attributed to the spawning enemy), Hits by floor, Transformations, **Recent runs (last 50, with what killed you)**, Settings. Per-slot `saveN.dat`; console command `runlogger ui` opens the window. **Requires REPENTOGON.**
**Verdict: closest existing thing — direct partial competitor.** It already solves "persistent per-run log you can browse in-game" and per-floor aggregation. It does **not** have a per-room timeline, no room imagery, no power score, no book UI, and it opens from the console, not a menu.

**The Finding of Items (TFOI)** — https://moddingofisaac.com/mod/900/the-finding-of-items · https://github.com/espilioto/TFOI
External Windows/.NET (WPF) app that tails `log.txt` and builds an SQLite run database: seed/character/items/floor+curse/boss/time per run, plus item collections and char/boss collections with run statistics and win rates. Afterbirth+ era, last release Jan 2017, Linux/Mac unsupported.
**Verdict: partial overlap** (browse-able run history + per-item run stats), different platform (outside the game), no per-room geometry or power metric.

**repentance-run-tracker** — https://github.com/aymericingargiola/repentance-run-tracker
Electron/Vue desktop app (MIT, ~24★) presenting runs as card-style pages with character portraits, win streaks, run editing, entity icons. Repo contents are a UI app; I did not verify its data source (manual entry vs. save-file import).
**Verdict: different problem / low overlap** — external app, no in-game presence. *(Source-tree inspection only; data-entry path unverified.)*

**[F9] Run Tracker** — https://github.com/AgeOfWar/RunTracker (Lua, source read)
In-run stats screen toggled with **F9**, drawn from a custom `.anm2` menu sprite (`gfx/ui/runstats/menu.anm2`) with a cursor, character list, and a scrolling column layout; also a streak counter HUD. Data: per-character × per-difficulty wins / deaths / resets / playtime / streak / longest streak, persisted as one JSON blob via `Isaac.SaveModData`. Refuses to open in unsafe rooms (plays an error buzz).
**Verdict: partial overlap** — proves the "custom browsable menu inside Repentance" pattern and cross-run persistence, but it stores only aggregates, never per-run or per-room records.

**Scoresheet in Vanilla** — https://github.com/epfly6/ScoresheetInVanilla · Workshop `?id=3206833441`
Displays the *daily-run scoresheet* when you beat a major boss (Isaac, Satan, Lamb, ???, Mega Satan); goal set randomly at run start; settings live in an ImGui bar.
**Verdict: nearest thing to an official-style "post-run screen" mod**, but it is a points scoresheet — no damage history, no rooms. Good precedent for *where* to inject a post-run summary.

### 1b. Stat / DPS HUDs (current stats only)

**Missing HUD 2** — https://github.com/networkMe/missinghud2 (forks: `z96`, `baitnfatty`)
Not a Workshop mod: a **DLL injector + OpenGL overlay** that reads game memory (signature scanning, Boost.Interprocess + protobuf shared memory) and draws speed, range, **tear delay ("lower is faster")**, shot speed, shot height, damage, luck, Devil/Angel chance, tears fired. Explicitly claims to stay accurate after Experimental Treatment and Libra because it reads *live* stats. Afterbirth-era.
**Verdict: different problem (live overlay, zero history), but it is the canonical "show the player the numbers the game hides" precedent** — and notably it shows **tear delay, not a DPS number**.

**Stats+** — https://github.com/aleksander-ciesielski/isaac-stats-plus · Workshop `?id=2729900570` (GPL-3.0)
Extends the existing HUD with extra stat information, "native-like renderer" with subtle animations, deeply configurable through Mod Config Menu, and exposes a Lua/TypeScript provider API so other mods can register their own stat sources.
**Verdict: partial overlap** — in-run HUD only, no history; but its *provider API* is a good model if you want other mods to feed your power score.

**Found HUD** — Workshop: **[snippet only]**, contemporary companion HUD that exposes damage/tears/etc. in-game; widely recommended in "how to see your stats" guides. Not verified beyond snippets.
**[Rep] Extra Data HUD (test version)** — https://steamcommunity.com/sharedfiles/filedetails/?id=3141286406 — **[snippet only]**; Chinese-titled "额外数据显示" extra-stat-data overlay.
**What's My DPS?** / **Damage Tracker** — surfaced only as third-party catalogue listings (smods.ru archives 267862 / 363939), pages Cloudflare-blocked. **Could not verify content; treat as unconfirmed.** Do not cite these as prior art without re-checking on the Workshop.

**External Item Descriptions** — https://github.com/wofsauge/External-Item-Descriptions (359★, very active)
In-run item/trinket/room descriptions and stat deltas on pickup/selection.
**Verdict: different problem**, but the reference implementation for "compute and display a stat delta caused by a pickup" — directly reusable logic for "what did this room do to my damage".

---

## 2. How the data is presented; does anything keep a browsable per-run log?

Two clearly separated camps:

| Presentation | Mods | Persistent history? |
|---|---|---|
| Live in-run HUD/overlay | Missing HUD 2, Stats+, Found HUD, Extra Data HUD, EID | none |
| In-game window you open yourself | Isaac Run Logger (console `runlogger ui`), [F9] Run Tracker (F9 key) | Isaac Run Logger: yes, ~50 recent runs + aggregates. Run Tracker: aggregates only |
| Post-boss/post-run injected screen | Scoresheet in Vanilla | no (it's a score sheet) |
| External app / database | TFOI, repentance-run-tracker | yes, but outside the game |

**Answer to the question:** exactly one mod (Isaac Run Logger) keeps a persistent per-run log that can be browsed later from inside the game — and it opens from a **console command**, not a menu, and it has no per-room dimension. **Nothing found keeps a per-*room* log at all.** No mod in this space hooks the main menu or the game-over screen to offer a browsable archive.

---

## 3. Re-rendering a previously visited room as a picture

**I could not find any mod that re-displays a visited room as a graphic.** This appears to be genuinely unoccupied territory. Closest things, all different:

- **The vanilla minimap** — schematic room rectangles only, no art.
- **Basement Renovator** — https://github.com/Basement-Renovator/basement-renovator (Python, 86★, active)
  Off-game room *editor* that parses `.stb` room files and renders the room layout with real tiles. **Technique reference only**: it proves a room can be drawn from data (grid + tile sheet + wall/door pass) without the game running, but it is not a replay feature and not in-game.
- **Room overlay sprite sheets** — https://www.spriters-resource.com/pc_computer/bindingofisaacrebirth/asset/211334/
  The actual tile graphics the game uses to compose room floors/walls/gaps. Useful as the art source if you draw rooms yourself.
- **Floor-map screenshots in external trackers** — several run trackers draw a floor diagram after the fact; I could not open any tracker page to confirm a *room-level* render, so I am not claiming it.

**Technique options in-engine (from the API surface, not from an existing implementation):**
1. **Redraw from grid data** (works in vanilla): iterate the room grid via `Room` grid accessors, read collision/grid entities, and blit the backdrop/overlay tiles from `resources/gfx/backdrop/...` per the sprite sheet above. You get a schematic-but-recognisable room. Cost: your own tile→sprite mapping table per stage.
2. **Redraw from the room's `.stb` data** (REPENTOGON): `LevelGeneratorRoom` exposes `Shape()`, `Neighbors()`, `DoorMask()`, `Row()`, `Column()`, `GenerationIndex()`, `IsDeadEnd()`, and there are `StbType` / `StbGridType` / `StbRockSubType` enums — i.e. parsed room-file semantics are exposed, so a faithful layout is reconstructible. Draw with `renderer/Image`, `Renderer`, `Shape`.
3. **Store a live snapshot** instead of re-deriving: capture once when the spike happens. Note that vanilla Lua has no screenshot API; REPENTOGON adds an ImGui/renderer stack, which is the realistic route for a bitmap grab.

Also relevant: `Level:GetRooms()` / the current `RoomDescriptor` give the floor's room list and shape, which is how you would know *which* rooms were visited.

---

## 4. Browsable "library/book"-style screens and main-menu entries

**What mods actually hook (verified):**

- **[F9] Run Tracker (vanilla-compatible pattern, source read).** Draw a custom screen in `MC_POST_RENDER` when a flag is set; hide the game HUD with `Game():GetHUD():SetVisible(false)`; navigate with `ButtonAction.ACTION_MENUUP/DOWN/LEFT/RIGHT` (plus keyboard triggers, via an "InputHelper" shim); swallow all input while open by returning `false` from `MC_INPUT_ACTION` (except fullscreen/console); force-close when the game is paused, when Mod Config Menu is visible, or when the room stops being safe; restore the HUD on close (with a special case for The Beast fight). This is the known-good, dependency-free pattern for "mod screen inside a Repentance run".
- **Scoresheet in Vanilla** injects a *post-boss* screen (via REPENTOGON/ImGui settings) — precedent for a summary that appears when a run milestone completes.
- **Mod Config Menu** is the de-facto UI host other mods hang their settings off (`ModConfigMenu.AddKeyboardSetting`, etc., used by Run Tracker; Stats+ advertises MCM integration).

**REPENTOGON menu API (the real "add a menu" route):**
`MenuManager` plus first-class menu classes: `MainMenu`, `TitleMenu`, `PauseMenu`, `StatsMenu`, `CollectionMenu`, `CharacterMenu`, `ModsMenu`, `BestiaryMenu`, `OptionsMenu`, `SaveMenu`, `DailyChallengeMenu`, `CutsceneMenu`, `ChallengeMenu`, `KeyConfigMenu`, `SpecialSeedsMenu`, `ControllerSelectMenu`, `CustomChallengeMenu`. `MainMenu` exposes `GetGameMenuSprite()`, `GetContinueWidgetSprite()`, `GetSelectedElement()` / `SetSelectedElement()` — i.e. you can drive/observe the main-menu selection rather than only painting over it.

**Book/page-turn visuals:** REPENTOGON documents an **`ItemOverlay`** class with a **`Giantbook`** enum — the game's own "giant book" overlay used for the big book animation. *(Enum/class names confirmed from the docs navigation; I did not read the full page bodies, so confirm the callable surface before designing around it.)* There is also a `ScoreSheet` class for the end-of-run score sheet. Either is a plausible way to get page-flip aesthetics without authoring them.

**What I could NOT find:** no mod (vanilla or REPENTOGON) that adds a **clickable main-menu button** of its own. [F9] Run Tracker deliberately stays in-run and refuses to open outside safe rooms. Treat "post-run entry point on the main menu" as the risky part of the idea: it needs either REPENTOGON's `MenuManager`/`MainMenu` or a hand-rolled clickable overlay on the title screen with its own mouse/controller hit-testing, and there is no copy-paste precedent I could point you at. The **game-over/continue screen** and the **pause menu** are much better-trodden ground.

---

## 5. Community pain points (with citations)

Almost all concrete evidence is from developers documenting their own scars:

- **JSON decoding is too slow for save data.** Isaac Run Logger's README states `json.decode` is "far too slow on large input: decoding a 225 KB stats object took about 6 seconds", so it stores aggregates as plain text and only decodes small JSON headers. → Any per-room history you keep must be a compact custom format, not one big `json.encode` blob. (https://github.com/haydenr42/Isaac-Run-Logger)
- **Save-data size is a real budget.** Same mod caps at **300 runs or 1500 KB per save slot**, one file per slot, with a documented file layout. [F9] Run Tracker instead serialises its *entire* state as one JSON string through `Isaac.SaveModData` on every change (`SaveData()` called from input handlers) — a pattern that scales badly if you add per-room records.
- **Co-op is the known blind spot.** Run Logger: "Co-op is untested. Hits and pickups from all players are recorded together, and the end-of-run inventory is player 1's." → A per-player power curve in co-op is unsolved by prior art; expect to attribute stats per `player` index yourself.
- **Continued runs break per-run continuity.** Save & Quit logs the run as abandoned and Continue starts a *new* entry with the same seed holding only what happens afterwards. → Per-run recap must handle "same run, multiple sessions".
- **Modded item ID drift.** Logged modded items can be misattributed when the mod list changes, because ids shift.
- **Per-run event caps.** Max 300 damage events kept per run — a precedent for capping per-room logging too.
- **True DPS requires reading live stats, not inferring them.** Missing HUD 2 needed a **DLL injector + memory signature scanning** pre-Repentogon to get accurate numbers, and still chose to display *tear delay* rather than a composite DPS. Its README explicitly markets accuracy after Experimental Treatment / Libra, i.e. the failure mode of naive "damage × tears" formulas is well known.
- **Charge weapons / multishot / conditional damage are not representable** in a `damage × 30/(tearDelay+1)` formula (Brimstone-class charging, Monstro's Lung, Chocolate Milk, multishot via `MultiShotParams`, crits, status effects). *This one is inference from the API surface — I found no developer write-up stating it explicitly; treat as a design caveat, not a cited fact.*
- **HUD/overlay conflicts.** [F9] Run Tracker defers to Mod Config Menu (closes itself when MCM opens), hides/restores the HUD, and special-cases `SEED_NO_HUD`, challenges, and The Beast fight — showing how many edge cases a screen-drawing mod must handle.
- **Noise warning:** GitHub search surfaces several "Binding of Isaac Trainer" repos (`CANDIE999/Binding-of-Isaac-Rebirth-Trainer-Enhanced`, `lauraw9394/...-run-toolkit`) that are SEO/trainer spam, not mods. Ignore them.

---

## 6. Is there an established "power score"?

**No.** There is no community-standard "power score"/"战斗力" number, no accepted DPS→item-quality mapping, and no shared "power level of a run" metric. What exists:

- **DPS as the de-facto yardstick.** The standard derivation is tears/second = `30 / (tear delay + 1)` and DPS = `damage × tears/second`, with the well-known fire-rate cap (tear delay floors out around 5 → 5.0 tears/s) and a damage cap discussion in the Steam forums (https://steamcommunity.com/app/250900/discussions/0/133255810023690895). The canonical write-up lives on the wiki's Attributes/Tears pages (https://bindingofisaacrebirth.fandom.com/wiki/Tears) — **fetch-blocked here, so verify the exact constants before hard-coding them.**
- **Item quality tiers 0–4** (Repentance's built-in `quality`) are the accepted "how good is this item" scale, and are already in the API (`ItemConfig`), so "which floor gave me a Tier-4 item" is cheap and unambiguous.
- **The game's own score sheet** (points; `ScoreSheet` / daily scores) is a *score*, not a power metric, and doesn't correlate with build strength.
- Tier lists and "DPS tier" videos are opinion, not a convention.

**Implication for the idea:** the "power score" is a *new* invention, which is both the opportunity (nothing to be compatible with) and the risk (you must define and defend it). The defensible version is: publish the formula, clamp at the same caps the game uses, split "tears-based DPS" from "+X from familiars/pets" (familiars are separate entities and cannot be folded into `damage`), and let the item-quality tier 0–4 carry the "big moment" semantics rather than inventing a second quality scale.

---

## Bottom line

- **Run history browsing exists** (Isaac Run Logger in-game; TFOI/repentance-run-tracker externally) — but always at run/floor granularity, never per room.
- **Per-room power curve: nothing.** No mod records a per-room timeline of damage/fire-rate, health, or pickups.
- **Room-as-picture: nothing in-game.** Only Basement Renovator (off-game, editor) and the vanilla minimap. You would be building the first one; plan for grid+tile redraw or a REPENTOGON snapshot.
- **Book UI + main-menu entry: nothing to copy.** Use REPENTOGON `MenuManager`/`ItemOverlay`/`Giantbook` for the aesthetics, and prefer the pause menu or game-over screen over the main menu, where no precedent exists.
- **The genuinely novel combination** is (per-room timeline) × (room imagery) × (post-run browsable book) — each axis individually has partial prior art, the union does not.
