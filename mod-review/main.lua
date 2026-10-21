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
local highlight = include("core.highlight")
local bookui = include("ui.book")
local configui = include("ui.config")
local dump   = tryRequire("core.dump", "core/dump")

-- ── 与外部评级 mod 的兼容（Item Weight Editor 会发布 _G.HLR）──
local itemwatch = tryRequire("core.itemwatch", "core/itemwatch")
local settings  = tryRequire("core.settings", "core/settings")

--- 读外部评级：读不到就返回 nil，调用方回退官方品质。加载顺序无关。
local function externalQuality(id)
    local ok, q = pcall(function()
        local hlr = rawget(_G, "HLR")
        if hlr and hlr.getQuality then return hlr.getQuality(id) end
    end)
    if ok and type(q) == "number" then return q end
    return nil
end

if not schema or not fmt or not power or not config then
    emit("[CHRONICLE] FATAL: module load failed (schema=" .. tostring(schema ~= nil) ..
         " fmt=" .. tostring(fmt ~= nil) .. " power=" .. tostring(power ~= nil) ..
         " config=" .. tostring(config ~= nil) .. ")")
    return
end
fmt.setSchema(schema)

if settings then settings.init() end

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
    -- 外部评级 mod 优先；读不到就回退官方品质
    local rq = externalQuality(id)
    if rq then return rq end
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

--- 六维原始值（吃药丸前后各读一次，算增减）
local function statNow(player)
    local s = { dm = 0, ts = 0, ss = 0, rg = 0, mv = 0, lk = 0 }
    if not player then return s end
    pcall(function()
        s.dm = player.Damage or 0
        s.ts = 30 / (((player.MaxFireDelay or 10)) + 1)
        s.ss = player.ShotSpeed or 0
        s.rg = player.TearRange or 0
        s.mv = player.MoveSpeed or 0
        s.lk = player.Luck or 0
    end)
    return s
end

--- 药丸观察：MC_USE_PILL 触发时记下"吃之前"，几帧后再读一次算差
local pillWatch = nil

-- ---------------------------------------------------------------- 进房瞬间读一次：是否首次访问 / BossID
local function firstVisitNow()
    local v = false
    pcall(function() v = Game():GetRoom():IsFirstVisit() end)
    return v
end

-- 终极 Boss 识别（调研确认的号码，见 CHANGELOG）
--   房间 GetBossID() 返回的是"房间 subtype"，不是实体类型：
--     Hush 63 / 超级撒旦 55 / 老干妈 88 / 百变怪 70
--   两个特例必须靠实体类型认：
--     祸兽（The Beast）房间返回 0，实体 Type 951
--     Boss Rush 没有 bossID，靠房型 17
local UB = { HUSH = 1, BOSSRUSH = 2, MEGASATAN = 3, MOTHER = 4, BEAST = 5, DELIRIUM = 6 }

local function num(v) if type(v) == "number" and v == v then return v end return 0 end
local function ultimateBossNow()
    local code = 0
    pcall(function()
        local room = Game():GetRoom()
        if num(room:GetType()) == 17 then code = UB.BOSSRUSH; return end

        local bid = num(room:GetBossID())
        if bid == 63 then code = UB.HUSH
        elseif bid == 55 then code = UB.MEGASATAN
        elseif bid == 88 then code = UB.MOTHER
        elseif bid == 70 then code = UB.DELIRIUM end

        if code == 0 then
            local es = room:GetEntities()
            for i = 1, #es do
                local t = num(es[i].Type)
                if t == 407 then code = UB.HUSH
                elseif t == 951 then code = UB.BEAST
                elseif t == 912 then code = UB.MOTHER
                elseif t == 274 then code = UB.MEGASATAN
                elseif t == 412 then code = UB.DELIRIUM end
                if code ~= 0 then break end
            end
        end
    end)
    return code
end

local function bossIdNow()
    local v = 0
    -- ① Room:GetBossID()：文档说返回"房间里第一个 Boss 实体"的 id
    pcall(function() v = num(Game():GetRoom():GetBossID()) end)
    -- ② 退路：房间 description 的 Subtype 按文档就等于 bossID，不依赖实体是否已生成
    if v == 0 then
        pcall(function()
            local desc = Game():GetLevel():GetCurrentRoomDesc()
            if desc and desc.Data then v = num(desc.Data.Subtype) end
        end)
    end
    -- ③ 退路：XL 楼层的第二间 Boss 房
    if v == 0 then
        pcall(function() v = num(Game():GetRoom():GetSecondBossID()) end)
    end
    return v
end

--- 房间身份


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
        floors = {}, rooms = {}, pills = {},
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
        ubIn    = ultimateBossNow(),
        dmgIn   = snap.damage, muIn = snap.multiShot, fmIn = snap.form,
        stIn    = { dv = snap.damage, ts = snap.tears, ss = snap.shotspeed,
                    rg = snap.rangeStat, mv = snap.movespeed, lk = snap.luck },
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
    -- 实时监视补采：修掉"同房获得又失去""跨房瞬间获得"两个盲区
    if itemwatch then
        local extra = itemwatch.drain()
        for i = 1, #extra do
            local id = extra[i]
            local dup = false
            for j = 1, #gained do if gained[j] == id then dup = true break end end
            if not dup then gained[#gained + 1] = id end
        end
    end

    -- 与 gained 平行的品质列表（用于识别 4 级起飞 / 0 级封盘）
    local gainedQ = {}
    for k = 1, #gained do gainedQ[k] = qualityOf(gained[k]) end
    -- 与 it 平行：离开房间这一刻还持有吗？0=临时(已消失) 1=还在
    local gainedK = {}
    for k = 1, #gained do
        local kept = false
        if player then pcall(function() kept = player:HasCollectible(gained[k]) end) end
        gainedK[k] = kept and 1 or 0
    end

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
        dvo = snap.damage,
        tso = (p.stIn and p.stIn.ts) or 0, sso = (p.stIn and p.stIn.ss) or 0,
        rgo = (p.stIn and p.stIn.rg) or 0, mvo = (p.stIn and p.stIn.mv) or 0,
        lko = (p.stIn and p.stIn.lk) or 0,
        p = p.p, po = snap.power,
        ms = math.floor(nowMs() - p.tIn),
        dmg = math.floor(p.dmg + 0.5),
        clr = p.cleared,
        it = gained,
        iq = gainedQ,
        ik = gainedK,
        dv = p.dmgIn or 0, mu = p.muIn or 1, fm = p.fmIn or "tears",
        foes = p.foes or 0,
        mxhp = p.mxhpIn or 0, mxhpo = snap.maxhp or 0,
        c = p.pockets and p.pockets.c or 0, co = pok.c,
        bmb = p.pockets and p.pockets.b or 0, bmbo = pok.b,
        key = p.pockets and p.pockets.k or 0, keyo = pok.k,
        boss = bossId, ub = p.ubIn or 0, first = firstVisit,
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
    -- 换层检查点已经把这局写进去过一份，先撤掉，否则同一局会存两条
    -- （旧那条 res=2 会被 UI 当成"未完成"，正是"死亡却显示 UNFINISHED"的原因）
    if state.currentEntry then
        fmt.removeEntry(state.store, state.currentEntry)
        state.currentEntry = nil
    end
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
    if settings then settings.save(state.store) end
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
    local dups = fmt.dedupe(store)
    if dups > 0 then log(string.format("清理重复记录 %d 条（同一局存了多份）", dups)) end
    if settings then settings.load(store) end
    if rating then
    end
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
local function add(event, fn, priority)
    if event == nil then return end
    if priority ~= nil then
        local ok = pcall(function() mod:AddCallback(event, fn, priority) end)
        if ok then return end
    end
    mod:AddCallback(event, fn)
end

-- ---------------------------------------------------------------- 册子 UI
bookui.init({
    hotkeyF5 = function() return (settings and settings.get("f5")) or Keyboard.KEY_F5 end,
    getStore = function() return state.store end,
    fmt      = fmt,
    hl       = highlight,
    config   = { powerTopN = 3, q4MaxPages = 3, absDelta = 0.5, relPct = 15 },
    log      = log,
})

-- 字体/纸背景在这里预加载（mod 加载阶段），不能留到 POST_RENDER 里懒加载：
-- 渲染回调里首次加载资源会留下不平衡的 render target，
-- 之后每帧刷 "[ASSERT] - PushRenderTarget: stack overflow!"（详见 CHANGELOG 第 15 轮）
if bookui.preload then
    local okPre, ePre = pcall(bookui.preload)
    if not okPre then err("册子预加载失败：" .. safeToString(ePre)) end
end

local uiErrs = 0
local function uiGuard(what, fn)
    local ok, e = pcall(fn)
    if not ok and uiErrs < 3 then
        uiErrs = uiErrs + 1
        err("册子 UI " .. what .. " 出错：" .. safeToString(e))
    end
end

-- 输入必须在 POST_RENDER 里读：POST_UPDATE 里读 IsButtonTriggered 会漏触发
add(ModCallbacks.MC_POST_RENDER, function()
    uiGuard("update", bookui.update)
    uiGuard("render", bookui.render)
end)

configui.init({ settings = settings, log = log, onChanged = function() pcall(saveData) end })

-- 每帧监视道具变化；局开始时快照权重并重建基线
add(ModCallbacks.MC_POST_GAME_STARTED, function()
    local p = getPlayer()
    if itemwatch then itemwatch.reset(p, 1800) end
end)

if configui.isReady() then log("ImGui 配置菜单已挂上") else log("ImGui 不可用（或挂载失败），跳过配置菜单") end

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

-- Boss 房补采：进房瞬间 Boss 还没生成，GetBossID() 会返回 0。
-- 每帧检查一次，读到非 0 就停（只在 Boss 房 / Boss Rush 房做）。

-- 吃药丸：记下"吃之前"的六维，3 帧后再读一次算增减（作者 2026-10-21 需求）
add(ModCallbacks.MC_USE_PILL, function(_, pillEffect, player, _flags)
    if not state.current then return end
    local p = state.pending or {}
    pillWatch = {
        effect = pillEffect or 0,
        before = statNow(player or getPlayer()),
        frames = 0,
        f = p.f or state.floorDepth or 0,
        i = p.i or 0,
    }
end)

add(ModCallbacks.MC_POST_UPDATE, function()
    if itemwatch then itemwatch.tick(getPlayer(), 1800) end

    -- 药丸：吃下 3 帧后读一次属性，算出增减；只有真变了才记
    if pillWatch then
        pillWatch.frames = pillWatch.frames + 1
        if pillWatch.frames >= 3 then
            local after = statNow(getPlayer())
            local d, changed = {}, false
            for k, v in pairs(after) do
                local delta = v - (pillWatch.before[k] or v)
                d[k] = delta
                if math.abs(delta) > 0.001 then changed = true end
            end
            if state.current then   -- 全部记（要算"改了属性的占比"，就得知道总数）
                state.current.pills = state.current.pills or {}
                state.current.pills[#state.current.pills + 1] = {
                    f = pillWatch.f, i = pillWatch.i, e = pillWatch.effect,
                    dm = d.dm or 0, ts = d.ts or 0, ss = d.ss or 0,
                    rg = d.rg or 0, mv = d.mv or 0, lk = d.lk or 0,
                }
                log(string.format("[PILL] effect=%d dm=%+.2f ts=%+.2f ss=%+.2f rg=%+.0f mv=%+.2f lk=%+.2f",
                    pillWatch.effect, d.dm or 0, d.ts or 0, d.ss or 0, d.rg or 0, d.mv or 0, d.lk or 0))
            end
            pillWatch = nil
        end
    end
    local p = state.pending
    if not p then return end

    -- 敌人数量：进房瞬间还没生成，这里补到第一次非 0
    if (p.foes or 0) == 0 then
        pcall(function() p.foes = countFoes() end)
    end

    -- Boss id / 终极 Boss：同理，Boss 生成之后才读得到
    if (p.bossIn or 0) ~= 0 and (p.ubIn or 0) ~= 0 then return end
    pcall(function()
        local room = Game():GetRoom()
        local t = num(room:GetType())
        if t ~= 5 and t ~= 17 then return end
            if not p.bossDiag then
                p.bossDiag = true
                local g1, r1 = pcall(function() return Game():GetRoom():GetBossID() end)
                local g2, r2 = pcall(function() return Game():GetLevel():GetCurrentRoomDesc().Data.Subtype end)
                local g3, r3 = pcall(function() return Game():GetRoom():GetSecondBossID() end)
                log(string.format("[BOSSDIAG] type=%d  GetBossID=(%s)%s  descSub=(%s)%s  2nd=(%s)%s",
                    t, tostring(g1), tostring(r1), tostring(g2), tostring(r2), tostring(g3), tostring(r3)))
            end
        if (p.bossIn or 0) == 0 then p.bossIn = bossIdNow() end
        if (p.ubIn or 0) == 0 then p.ubIn = ultimateBossNow() end
    end)
end)

add(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, function()
    if state.pending then state.pending.cleared = true end
        -- Boss 房：清房这一刻 GetBossID() 才可靠（cuerlib / antibirth music 都是死后才读）
        if state.pending then
            local t = 0
            pcall(function() t = num(Game():GetRoom():GetType()) end)
            if t == 5 or t == 17 then
                local b = bossIdNow()
                if b and b ~= 0 then state.pending.bossIn = b end   -- 只在取到非 0 时覆盖（清房瞬间可能返回 0）
                local u = ultimateBossNow()
                if u and u ~= 0 then state.pending.ubIn = u end
                log(string.format("[BOSSCLEAR] type=%d boss=%d ub=%d", t, state.pending.bossIn, state.pending.ubIn))
            end
        end
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

add(ModCallbacks.MC_POST_GAME_END, function(_, isGameOver)   -- 第一个参数是 mod，不是 isGameOver
    -- 收局诊断：isGameOver 到底靠不靠得住，靠这几个值判断
    local p = getPlayer()
    local info = "?"
    pcall(function()
        info = string.format("victoryLap=%s hearts=%s soul=%s stage=%s roomType=%s hpRef=%s",
            tostring(Game():GetVictoryLap()),
            tostring(p and p:GetHearts() or -1),
            tostring(p and p:GetSoulHearts() or -1),
            tostring(Game():GetLevel():GetStage()),
            tostring(Game():GetRoom():GetType()),
            tostring(p and p:GetMaxHearts() or -1))
    end)
    log("收局诊断 isGameOver=" .. tostring(isGameOver) .. "  " .. info)
    finishRun(isGameOver and 0 or 1, p)
end)

add(ModCallbacks.MC_PRE_GAME_EXIT, function()
    if state.current then
        settleRoom(getPlayer())
        state.current.res = 2
        -- 撤掉换层检查点写进去的那一份，否则每小退一次就多一条（作者实测存了 3 份）
        if state.currentEntry then
            fmt.removeEntry(state.store, state.currentEntry)
            state.currentEntry = nil
        end
        fmt.appendRun(state.store, state.current)
        state.current = nil
    end
    saveData()
end)

emit(LOG_PREFIX .. "loaded v2 (REPENTOGON=" .. tostring(state.hasRP) .. ")")
