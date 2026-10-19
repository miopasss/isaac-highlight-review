-- ============================================================================
-- main.lua —— Highlight Review v2（采集器，无 UI）
--
-- 数据模型（见 FORMAT.md v2）：
--   旧局只保留**原始字符串行**，绝不解码；
--   只有当前局是 Lua 表，保存时只编码当前局。
--
-- 硬规则（都是一路踩出来的，改之前先看 DESIGN.md §14）：
--   1. 不在回调里调 Room 的引擎方法（会抛 C++ 异常，pcall 接不住）
--   2. 日志必须走 Isaac.DebugString（print 不进 log.txt）
--   3. 动画/时长时钟用 Isaac.GetFrameCount()（Isaac.GetTime 不可靠）
--   4. 道具读不到就用 HasCollectible 扫 1..2000（GetCollectible 这个版本不存在）
-- ============================================================================
local mod = RegisterMod("Highlight Review", 1)

local LOG_PREFIX = "[HIGHLIGHT] "

local function emit(msg)
    local text = tostring(msg)
    local ok = pcall(function() Isaac.DebugString(text) end)
    if not ok then pcall(function() print(text) end) end
end

local function tryRequire(...)
    for i = 1, select("#", ...) do
        local name = select(i, ...)
        local ok, res = pcall(require, name)
        if ok and res ~= nil then return res end
    end
    return nil
end

local schema = tryRequire("core.schema", "core/schema")
local fmt    = tryRequire("core.fmt", "core/fmt")
local power  = tryRequire("core.power", "core/power")
local config = tryRequire("config")
local dump   = tryRequire("core.dump", "core/dump")

if not schema or not fmt or not power or not config then
    emit("[CHRONICLE] FATAL: module load failed (schema=" .. tostring(schema ~= nil) ..
         " fmt=" .. tostring(fmt ~= nil) .. " power=" .. tostring(power ~= nil) ..
         " config=" .. tostring(config ~= nil) .. ")")
    return
end
fmt.setSchema(schema)

local function log(msg) if config.debug then emit(LOG_PREFIX .. tostring(msg)) end end
local function err(msg) emit(LOG_PREFIX .. "ERROR: " .. tostring(msg)) end

local function safeToString(v)
    local ok, s = pcall(tostring, v)
    if ok then return s end
    return "<" .. type(v) .. ">"
end

-- ---------------------------------------------------------------- 状态

local state = {
    loaded      = false,
    store       = nil,      -- { lines = {...}, index = {...} }
    current     = nil,      -- 当前局的 Lua 表（唯一被解码的）
    pending     = nil,      -- 待结算的房间
    floorDepth  = 0,        -- 第几层（按 stage key 变化判定）
    lastStageKey= nil,
    roomInFloor = 0,        -- 本层第几间房
    hasRP       = (REPENTOGON ~= nil),
    dumped      = false,
}

local saveData, loadData

-- ---------------------------------------------------------------- 小工具

local function getPlayer()
    local ok, p = pcall(function() return Isaac.GetPlayer(0) end)
    if ok then return p end
    return nil
end

local function isMainPlayer(player)
    if not player then return false end
    local idx = nil
    pcall(function() idx = player.ControllerIndex end)
    return idx == 0 or idx == nil
end

--- 30 帧/秒换算毫秒；Isaac.GetFrameCount() 在暂停/主菜单时也照常增长
local function nowMs()
    local ok, f = pcall(function() return Isaac.GetFrameCount() end)
    if ok and type(f) == "number" then return f * (1000 / 30) end
    return 0
end

local function nowSec() return math.floor(nowMs() / 1000) end

-- ---------------------------------------------------------------- 道具读取

local itemsProbed, itemsProbed2, itemAccessBroken = false, false, false
local SCAN_MAX_ID = 2000

local function scanCollectibles(player)
    local list = {}
    for id = 1, SCAN_MAX_ID do
        local ok, has = pcall(function() return player:HasCollectible(id) end)
        if ok and has then list[#list + 1] = id end
    end
    return list
end

local function readCollectibles(player)
    local list = {}
    if not player then return list end
    if itemAccessBroken then return scanCollectibles(player) end

    local okN, n = pcall(function() return player:GetCollectibleCount() end)
    if not okN or type(n) ~= "number" then
        if not itemsProbed then
            itemsProbed = true
            log("GetCollectibleCount 不可用 → " .. safeToString(n) .. "，改用全量扫描")
            itemAccessBroken = true
        end
        return scanCollectibles(player)
    end

    for i = 0, n - 1 do
        local ok, id = pcall(function() return player:GetCollectible(i) end)
        if ok and type(id) == "number" then
            list[#list + 1] = id
        elseif not itemAccessBroken then
            itemAccessBroken = true
            log("逐件读取失败（" .. safeToString(id) .. "），本会话改用全量扫描")
            return scanCollectibles(player)
        end
    end
    if not itemsProbed2 and #list > 0 then
        itemsProbed2 = true
        log("道具读取正常：共 " .. #list .. " 件，首件 id=" .. tostring(list[1]))
    end
    return list
end

--- 道具品质（0~4）。带缓存，同一个 id 只查一次。
local qualityCache = {}
local function qualityOf(id)
    local q = qualityCache[id]
    if q then return q end
    q = -1
    pcall(function()
        local cfg = Isaac.GetItemConfig():GetCollectible(id)
        if cfg and type(cfg.Quality) == "number" then q = cfg.Quality end
    end)
    qualityCache[id] = q
    return q
end

local function toSet(list)
    local set = {}
    for i = 1, #list do set[list[i]] = (set[list[i]] or 0) + 1 end
    return set
end

--- 口袋资源（钱/炸弹/钥匙）
local function readPockets(player)
    local p = { c = 0, b = 0, k = 0 }
    if not player then return p end
    pcall(function() p.c = player:GetNumCoins() or 0 end)
    pcall(function() p.b = player:GetNumBombs() or 0 end)
    pcall(function() p.k = player:GetNumKeys() or 0 end)
    return p
end

--- 进房时的敌人数量（房间强度代理；击杀回调不存在，用这个）
local function countFoes()
    local n = 0
    pcall(function()
        local es = Game():GetRoom():GetEntities()
        for i = 1, #es do
            local e = es[i]
            if e and e:IsActiveEnemy(false) then n = n + 1 end
        end
    end)
    return n
end

--- 读当前手上的饰品（槽 0/1）。不同版本方法名可能不同，两个都试。
local trinketProbed = false
local function readTrinkets(player)
    local list = {}
    if not player then return list end
    for slot = 0, 1 do
        local t = nil
        local ok = pcall(function() t = player:GetTrinket(slot) end)
        if not ok then
            local fn = (slot == 0) and "GetTrinket0" or "GetTrinket1"
            pcall(function()
                if player[fn] then t = player[fn](player) end
            end)
        end
        if type(t) == "number" and t ~= 0 then list[#list + 1] = t end
    end
    if not trinketProbed then
        trinketProbed = true
        log("饰品读取：" .. (#list > 0 and ("共 " .. #list .. " 个") or "当前没有"))
    end
    return list
end

-- ---------------------------------------------------------------- 玩家快照

local function detectForm(player)
    local function has(id)
        if id == nil then return false end
        local ok, res = pcall(function() return player:HasCollectible(id) end)
        return ok and res or false
    end
    if has(CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE) then return "ludovico" end
    if has(CollectibleType.COLLECTIBLE_BRIMSTONE)         then return "brimstone" end
    if has(CollectibleType.COLLECTIBLE_TECH_X)            then return "techx" end
    if has(CollectibleType.COLLECTIBLE_TECHNOLOGY_2)      then return "tech" end
    if has(CollectibleType.COLLECTIBLE_TECHNOLOGY)        then return "tech" end
    if has(CollectibleType.COLLECTIBLE_CHOCOLATE_MILK)    then return "choco" end
    return "tears"
end

local function readMultiShot(player)
    local ok, n = pcall(function()
        local params = player:GetMultiShotParams()
        if params and params.GetNumTears then return params:GetNumTears() end
        return nil
    end)
    if ok and type(n) == "number" and n >= 1 and n <= 64 then return math.floor(n + 0.5) end
    return 1
end

local function snapshot(player)
    local s = { form = "tears", damage = 0, maxFireDelay = 10, multiShot = 1,
                red = 0, soul = 0, bone = 0, survival = 0, power = 0 }
    if not player then return s end

    pcall(function()
        s.damage       = player.Damage or 0
        s.maxFireDelay = player.MaxFireDelay or 10
    end)
    s.form      = detectForm(player)
    s.multiShot = readMultiShot(player)

    pcall(function()
        s.red  = player:GetHearts()     or 0   -- 半心
        s.soul = player:GetSoulHearts() or 0   -- 半心（魂心+黑心）
        s.bone = player:GetBoneHearts() or 0   -- 颗
        s.maxhp = player:GetMaxHearts() or 0   -- 半心
        s.black   = player:GetBlackHearts()   or 0
        s.gold    = player:GetGoldenHearts()  or 0
        s.eternal = player:GetEternalHearts() or 0
        s.rotten  = player:GetRottenHearts()  or 0
        s.shotspeed = player.ShotSpeed or 0
        s.rangeStat = player.TearRange or 0
        s.movespeed = player.MoveSpeed or 0
        s.luck      = player.Luck or 0
    end)
    s.tears = 30 / ((s.maxFireDelay or 10) + 1)
    s.survival = power.survival({ red = s.red, soul = s.soul, bone = s.bone })
    s.power = power.output({
        damage = s.damage, maxFireDelay = s.maxFireDelay,
        multiShot = s.multiShot, form = s.form, chargeFactor = 1.0,
    })
    return s
end

-- ---------------------------------------------------------------- 进房瞬间读一次：是否首次访问 / BossID
local function firstVisitNow()
    local v = false
    pcall(function() v = Game():GetRoom():IsFirstVisit() end)
    return v
end

local function bossIdNow()
    local v = 0
    pcall(function() v = num(Game():GetRoom():GetBossID()) end)
    return v
end

--- 房间身份

local function num(v) if type(v) == "number" and v == v then return v end return 0 end

local function readRoomIdentity()
    local ident = { type = 0, shape = 0, doors = 0, stageId = 0, variant = 0,
                    listIndex = -1, peds = {} }
    local ok, e = pcall(function()
        local desc = Game():GetLevel():GetCurrentRoomDesc()
        if not desc then return end
        local data = desc.OverrideData or desc.Data
        if data then
            ident.type    = num(data.Type)
            ident.shape   = num(data.Shape)
            ident.stageId = num(data.StageID)
            ident.variant = num(data.Variant)
            if config.capturePeds and data.Spawns then
                local n = num(data.Spawns.Size)
                for i = 0, math.min(n, 16) - 1 do
                    local sp = data.Spawns:Get(i)
                    if sp then ident.peds[#ident.peds + 1] = { x = num(sp.X), y = num(sp.Y) } end
                end
            end
        end
        local doors = nil
        pcall(function()
            if type(desc.AllowedDoors) == "number" then doors = desc.AllowedDoors end
        end)
        if doors == nil and data then doors = num(data.Doors) end
        ident.doors = num(doors)
        pcall(function() ident.listIndex = num(desc.ListIndex) end)
    end)
    if not ok then err("房间身份读取失败：" .. safeToString(e)) end
    return ident
end

local function currentStageKey()
    local ok, k = pcall(function()
        local lv = Game():GetLevel()
        return tostring(lv:GetStage()) .. "_" .. tostring(lv:GetStageType())
    end)
    if ok then return k end
    return nil
end

-- ---------------------------------------------------------------- 局

local function computeRunId(player)
    local seed, char = 0, 0
    pcall(function() seed = Game():GetSeeds():GetStartSeed() end)
    pcall(function() char = player:GetPlayerType() end)
    seed = math.floor(seed % 4294967296)
    return string.format("%08X-%d", seed, char), seed, char
end

local function beginRun(player)
    local id, seed, char = computeRunId(player)
    state.lastStageKey = nil
    state.floorDepth   = 0
    state.roomInFloor  = 0

    -- 续接：只有"最新那一局 + 未完成 + 同 runId"才认
    local entry = fmt.findUnfinished(state.store)
    if entry and entry.id == id then
        state.current = fmt.detachRun(state.store, entry)
        state.currentEntry = nil
        state.floorDepth = state.current.max or 1
        log(string.format("续接未完成的局 %s（已有 %d 间房）", id, #(state.current.rooms or {})))
        return
    end

    state.current = {
        seq = fmt.nextSeq(state.store),
        id = id, seed = seed, char = char,
        base = 0, final = 0, max = 1, res = 2, t0 = nowSec(), hl = 0,
        floors = {}, rooms = {},
    }
    log(string.format("开局 %s（seed=%d char=%d，历史 %d 局）", id, seed, char, #state.store.index))
end

--- 把"正在进行的局"刷进 store 并落盘。换层是天然检查点，崩溃最多丢一层。
local function flushCurrentRun(reason)
    local run = state.current
    if not run or not state.store then return end
    if state.currentEntry then fmt.removeEntry(state.store, state.currentEntry) end
    state.currentEntry = fmt.appendRun(state.store, run)
    saveData()
    log("检查点落盘（" .. tostring(reason) .. "）：" .. #(run.rooms or {}) .. " 房 / " ..
        #(run.floors or {}) .. " 层")
end

local function ensureFloor(run)
    local key = currentStageKey()
    if key == nil then key = "unknown" end

    if state.lastStageKey == nil then
        -- 本次会话第一次拿到楼层 key
        state.lastStageKey = key
        if (state.floorDepth or 0) == 0 then
            state.floorDepth = 1                      -- 新局：第一层
        else
            -- 续接：当前层在存档里已经有了，只恢复房间计数，不新增 F 记录
            local n = 0
            for i = 1, #(run.rooms or {}) do
                if run.rooms[i].f == state.floorDepth then n = n + 1 end
            end
            state.roomInFloor = n
            log("续接回第 " .. state.floorDepth .. " 层（本层已有 " .. n .. " 间房）")
        end
        state.floorTIn = nowMs()
        return
    end

    if key == state.lastStageKey then return end

    -- 真的下一层了
    state.lastStageKey = key
    state.floorDepth = (state.floorDepth or 0) + 1
    state.roomInFloor = 0

    local stage, stype, curses = 0, 0, 0
    pcall(function()
        local lv = Game():GetLevel()
        stage  = num(lv:GetStage())
        stype  = num(lv:GetStageType())
        curses = num(lv:GetCurses())
    end)

    local prev = run.floors[#run.floors]
    if prev and state.floorTIn then prev.ms = math.floor(nowMs() - state.floorTIn) end
    state.floorTIn = nowMs()

    local stageSeed = 0
    pcall(function() stageSeed = math.floor(Game():GetSeeds():GetStageSeed() % 4294967296) end)

    run.floors[#run.floors + 1] = {
        r = run.seq, i = state.floorDepth,
        stage = stage, type = stype, seed = stageSeed,
        curse = curses, alt = 0, t = nowSec(), ms = 0,
    }
    if state.floorDepth > (run.max or 0) then run.max = state.floorDepth end

    flushCurrentRun("换层")
end

local function beginRoom(player)
    local run = state.current
    if not run then return end
    ensureFloor(run)

    local ident = readRoomIdentity()
    local snap  = snapshot(player)
    state.roomInFloor = state.roomInFloor + 1

    state.pending = {
        idx = state.roomInFloor,
        ident = ident,
        hp = snap.red, hs = snap.soul, hb = snap.bone,
        p = snap.power,
        itemsIn = toSet(readCollectibles(player)),
        trIn    = readTrinkets(player),
        trOut   = readTrinkets(player),
        mxhpIn  = snap.maxhp or 0,
        pockets = readPockets(player),
        foes    = countFoes(),
        hblIn   = snap.black, hgoIn = snap.gold, hetIn = snap.eternal, hrtIn = snap.rotten,
        firstIn = firstVisitNow(),
        bossIn  = bossIdNow(),
        dmgIn   = snap.damage, muIn = snap.multiShot, fmIn = snap.form,
        tIn = nowMs(),
        dmg = 0,
        cleared = false,
    }

    if run.base == nil or run.base <= 0 then
        run.base = snap.power
        log(string.format("基线战力补记 %.2f（形态 %s，伤害 %.2f，攻速 %.3f，弹幕 %d）",
            snap.power, snap.form, snap.damage, 30 / ((snap.maxFireDelay or 10) + 1), snap.multiShot))
    end
end

local function settleRoom(player)
    local p = state.pending
    if not p then return end
    state.pending = nil

    local run = state.current
    if not run then return end

    local snap  = snapshot(player)
    local items = readCollectibles(player)

    local gained, seen = {}, {}
    for i = 1, #items do
        local id = items[i]
        seen[id] = (seen[id] or 0) + 1
        if seen[id] > (p.itemsIn[id] or 0) then gained[#gained + 1] = id end
    end
    -- 第一间房不记"获得"类字段：那多半是角色自带/初始化顺序造成的假阳性
    local firstRoom = (#run.rooms == 0)
    if firstRoom then gained = {} end

    -- 与 gained 平行的品质列表（用于识别 4 级起飞 / 0 级封盘）
    local gainedQ = {}
    for k = 1, #gained do gainedQ[k] = qualityOf(gained[k]) end

    local pok = readPockets(player)
    local bossId = p.bossIn or 0
    local firstVisit = p.firstIn or false

    local rec = {
        r = run.seq, f = p.idx and state.floorDepth or state.floorDepth, i = p.idx,
        t = p.ident.type, s = p.ident.shape, d = p.ident.doors,
        st = p.ident.stageId, v = p.ident.variant, list = p.ident.listIndex,
        hp = p.hp, hs = p.hs, hb = p.hb,
        hpo = snap.red, hso = snap.soul, hbo = snap.bone,
        hblo = snap.black, hgoo = snap.gold, heto = snap.eternal, hrto = snap.rotten,
        ts = snap.tears, ss = snap.shotspeed, rg = snap.rangeStat,
        mv = snap.movespeed, lk = snap.luck,
        p = p.p, po = snap.power,
        ms = math.floor(nowMs() - p.tIn),
        dmg = math.floor(p.dmg + 0.5),
        clr = p.cleared,
        it = gained,
        iq = gainedQ,
        dv = p.dmgIn or 0, mu = p.muIn or 1, fm = p.fmIn or "tears",
        foes = p.foes or 0,
        mxhp = p.mxhpIn or 0, mxhpo = snap.maxhp or 0,
        c = p.pockets and p.pockets.c or 0, co = pok.c,
        bmb = p.pockets and p.pockets.b or 0, bmbo = pok.b,
        key = p.pockets and p.pockets.k or 0, keyo = pok.k,
        boss = bossId, first = firstVisit,
        tri = firstRoom and (p.trOut or {}) or (p.trIn or {}),
        tro = p.trOut or {},
        pd = "",
    }
    run.rooms[#run.rooms + 1] = rec
    run.final = snap.power

    local delta = rec.po - rec.p
    local pct = rec.p > 0 and (delta / rec.p * 100) or 0
    log(string.format(
        "F%d-%02d 型%02d 形%d  %7.2f -> %7.2f  d%+7.2f (%+6.1f%%)  红%d→%d 魂%d→%d 骨%d→%d  道具%d  %5.1fs  伤%d  [%s 伤害%.2f 弹幕%d]",
        rec.f, rec.i, rec.t, rec.s, rec.p, rec.po, delta, pct,
        rec.hp, rec.hpo, rec.hs, rec.hso, rec.hb, rec.hbo,
        #rec.it, rec.ms / 1000, rec.dmg, snap.form, snap.damage, snap.multiShot) ..
        (#(rec.tri) + #(rec.tro) > 0 and string.format("  饰品%d→%d", #rec.tri, #rec.tro) or ""))
end

local function finishRun(result, player)
    settleRoom(player)
    local run = state.current
    if not run then return end
    run.res = result
    if player then run.final = snapshot(player).power end
    state.current = nil
    fmt.appendRun(state.store, run)
    state.currentEntry = nil
    log(string.format("收局 %s  res=%d  层=%d  房间=%d  终战力=%.2f",
        run.id, result, run.max, #run.rooms, run.final))
    saveData()
end

-- ---------------------------------------------------------------- 存档

local lastBlob = nil

saveData = function()
    if not state.store then return end
    local removed = fmt.trimToCount(state.store, config.maxRuns)
    if removed > 0 then
        log(string.format("超出局数上限 %d，淘汰了最旧的 %d 局", config.maxRuns, removed))
    end
    removed = fmt.trimToBudget(state.store, config.maxBlobBytes)
    if removed > 0 then
        log(string.format("超出字节预算，又淘汰了 %d 局", removed))
    end
    local blob = fmt.buildBlob(state.store)
    if blob == lastBlob then
        log("落盘跳过：内容未变（" .. #blob .. " 字节）")
        return
    end
    local ok, e = pcall(function() mod:SaveData(blob) end)
    if ok then
        lastBlob = blob
        log(string.format("落盘 OK：%d 局 / %d 字节", #state.store.index, #blob))
    else
        err("落盘失败：" .. tostring(e))
    end
end

loadData = function()
    if state.loaded then return end
    state.loaded = true

    local ok, blob = pcall(function()
        if mod:HasData() then return mod:LoadData() end
        return nil
    end)
    if not ok then err("读档失败：" .. safeToString(blob)); state.store = { lines = {}, index = {} }; return end
    if not blob or blob == "" then
        log("无历史存档")
        state.store = { lines = {}, index = {} }
        return
    end
    local store, warns = fmt.splitBlob(blob)
    state.store = store
    state.store.bytes = nil
    log(string.format("载入 %d 局 / %d 行 / %d 字节（未解析房间体）",
        #store.index, #store.lines, #blob))
    for i = 1, math.min(#warns, 5) do log("  警告：" .. warns[i]) end
end

-- ---------------------------------------------------------------- 自检

do
    local ok, msg = fmt.selftest()
    if ok then emit(LOG_PREFIX .. "fmt 自检通过：" .. tostring(msg))
    else emit(LOG_PREFIX .. "!!! fmt 自检失败：" .. tostring(msg)) end
    if not state.hasRP then emit(LOG_PREFIX .. "!!! 未检测到 REPENTOGON") end
end

-- ---------------------------------------------------------------- 回调

local function add(event, fn)
    if event == nil then return end
    mod:AddCallback(event, fn)
end

add(ModCallbacks.MC_POST_PLAYER_INIT, function(player)
    state.store = nil
    state.loaded = false
    loadData()
    if isMainPlayer(player) then beginRun(player) end
end)

add(ModCallbacks.MC_POST_NEW_LEVEL, function()
    -- 楼层判定交给 ensureFloor（按 stage key 变化），这里只记日志
    log("换层")
end)

add(ModCallbacks.MC_POST_NEW_ROOM, function()
    local player = getPlayer()
    if not state.current and player then beginRun(player) end
    settleRoom(player)
    if state.current then beginRoom(player) end

    if dump and config.dumpOnce and not state.dumped then
        state.dumped = true
        log("开始导出数据面板…")
        local n = dump.items(log)
        dump.itemNames(log)
        dump.room(log)
        log("数据面板完成，道具 " .. tostring(n) .. " 条")
    end
end)

add(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, function()
    if state.pending then state.pending.cleared = true end
end)

local dmgProbed, dmgLogged = false, false

add(ModCallbacks.MC_ENTITY_TAKE_DMG, function(...)
    local nargs = select("#", ...)
    if not dmgProbed then
        dmgProbed = true
        local parts = {}
        for i = 1, math.min(nargs, 8) do
            parts[#parts + 1] = i .. "=" .. type(select(i, ...))
        end
        log("受伤回调探针：" .. table.concat(parts, " "))
    end

    local player = getPlayer()
    if not (state.pending and player) then return nil end

    local hit, amt = false, nil
    for i = 1, nargs do
        local v = select(i, ...)
        if type(v) == "number" and amt == nil then
            amt = v
        elseif type(v) == "userdata" and not hit then
            local ok, res = pcall(function() return v:ToPlayer() end)
            if ok and res ~= nil then hit = true end
        end
    end

    if hit then
        if not dmgLogged then
            dmgLogged = true
            log("受伤计数已生效（首次金额=" .. tostring(amt) .. "）")
        end
        state.pending.dmg = state.pending.dmg + (amt or 0)
    end
    return nil
end)

add(ModCallbacks.MC_POST_GAME_END, function(isGameOver)
    finishRun(isGameOver and 0 or 1, getPlayer())
end)

add(ModCallbacks.MC_PRE_GAME_EXIT, function()
    if state.current then
        settleRoom(getPlayer())
        state.current.res = 2
        fmt.appendRun(state.store, state.current)
        state.current = nil
    end
    saveData()
end)

emit(LOG_PREFIX .. "loaded v2 (REPENTOGON=" .. tostring(state.hasRP) .. ")")
