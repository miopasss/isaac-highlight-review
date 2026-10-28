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
--   4. 道具读不到就用 HasCollectible 扫 1..2000（GetCollectible 这个版本不存在；
--      本机 player:GetCollectiblesList 也没有 → 只探测/报一次，之后静默走退化路径）
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
local powerForms = tryRequire("core.power_forms", "core/power_forms")
local config = tryRequire("config")
local highlight = include("core.highlight")
local bookui = include("ui.book")
local configui = include("ui.config")
local dump   = tryRequire("core.dump", "core/dump")

-- ── 与外部评级 mod 的兼容（Item Weight Editor 会发布 _G.HLR）──
local itemwatch = tryRequire("core.itemwatch", "core/itemwatch")
local settings  = tryRequire("core.hlr_settings", "core/hlr_settings")
local pillmod   = tryRequire("core.pills", "core/pills")
if pillmod then pcall(pillmod.init) end

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
--- 游戏内时间（毫秒）。REPENTOGON 的 Isaac.GetTime 可能不可靠，
--- 这里只用于对照探针，取不到就返回 0。
local function gameTimeMs()
    local ok, t = pcall(function() return Isaac.GetTime() end)
    if ok and type(t) == "number" and t >= 0 then return t end
    return 0
end


--- 墙钟时间文本（"2026/10/22 14:36"）。
--- 实测：os.time() 被沙盒换成返回 0，但 os.date()（不传时间戳）拿到的是**真实系统时间**
--- （明日方舟 mod 也这么用：os.date("%Y%m%d") 判每日）。年份合理才认，否则返回 nil。
local function wallText()
    local ok, t = pcall(function() return os.date("%Y-%m-%d %H:%M") end)
    if not ok or type(t) ~= "string" then return nil end
    local y = tonumber(t:sub(1, 4))
    if not y or y < 2001 then return nil end
    return t
end

-- ---------------------------------------------------------------- 道具读取

-- GetCollectiblesList 的可用性只判定一次（作者 2026-10-23 要求）：
--   · player 上没有这个方法 → 记死"本版本无"，之后既不再 pcall、也不再刷日志
--   · 有方法、这次却没返回表 → 只当临时故障，下次再试，日志仍然只报一条
-- 退化路径（HasCollectible 扫 1..SCAN_MAX_ID）的结果必须与旧实现逐字一致。
local listApiMissing = false   -- 本版本无 GetCollectiblesList（记死后不再探测）
local listFailLogged = false   -- 探测失败只报一条
local itemsProbed2   = false   -- 列表法可用只报一条
local SCAN_MAX_ID    = 2000    -- 同版本最大道具 id = 1763（READABLE-DATA.md），留余量

--- 全量扫描：升序 id 列表，每件一次（HasCollectible 只回答"有没有"）
local function scanCollectibles(player)
    -- 2026-10-24 实测：本 REPENTOGON 版本没有 GetCollectiblesList()，
    -- 而 HasCollectible 会多报（图鉴语义）→ 用 GetCollectibleNum 才算准确。
    -- 注意：方法引用提到循环外，避免每次 pcall 新建闭包（2000 次/房 → 内存压力）
    local list = {}
    local numFn = player.GetCollectibleNum
    local hasFn = player.HasCollectible

    if numFn then
        for id = 1, SCAN_MAX_ID do
            local ok, n = pcall(numFn, player, id)
            if ok and type(n) == "number" and n > 0 then
                for _ = 1, n do list[#list + 1] = id end
            end
        end
        scanCount = (scanCount or 0) + 1
        if scanCount <= 3 then
            log(string.format("[SCAN] GetCollectibleNum 扫描：%d 件", #list))
        end
        if scanCount == 1 then itemsProbed2 = true end
        return list
    end

    if hasFn then
        for id = 1, SCAN_MAX_ID do
            local ok, has = pcall(hasFn, player, id)
            if ok and has then list[#list + 1] = id end
        end
    end
    return list
end

local function readCollectibles(player)
    local list = {}
    if not player then return list end

    -- 首选 GetCollectiblesList()（{ id = 数量 }）。
    -- 2026-10-24 实测：**不同来源的 player 对象能力不同** ——
    --   MC_POST_PLAYER_INIT 传进来的对象没有这个方法，getPlayer() 有。
    -- 所以先试传入的，再试 getPlayer()，都失败才退化扫描。
    local candidates = { player }
    local p0 = getPlayer()
    if p0 and p0 ~= player then candidates[2] = p0 end

    for ci = 1, #candidates do
        local p = candidates[ci]
        local okCall, m = pcall(function() return p:GetCollectiblesList() end)
        if okCall and type(m) == "table" then
            for id, cnt in pairs(m) do
                local c = tonumber(cnt) or 0
                if c > 0 then
                    for _ = 1, c do list[#list + 1] = id end
                end
            end
            table.sort(list)
            if not itemsProbed2 and #list > 0 then
                itemsProbed2 = true
                log(string.format("道具读取正常（列表法）：共 %d 件，首件 id=%s（来源 %s）",
                    #list, tostring(list[1]), ci == 1 and "回调参数" or "getPlayer"))
            end
            return list
        end
        if ci == #candidates and not listFailLogged then
            listFailLogged = true
            log("GetCollectiblesList 两个对象都不可用（" .. safeToString(m) .. "）→ 退化为全量扫描")
        end
    end

    return scanCollectibles(player)
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
    -- 数字 id 是 EID 的表里核对过的（docs/special-attack-power.md §4.6）
    if has(CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE) then return "ludovico" end
    if has(CollectibleType.COLLECTIBLE_BRIMSTONE)         then return "brimstone" end
    if has(CollectibleType.COLLECTIBLE_TECH_X)            then return "techx" end
    if has(114) then return "momsknife" end   -- 妈刀
    if has(52)  then return "drfetus"  end    -- 婴儿博士
    if has(168) then return "epicfetus" end   -- 史诗婴儿
    if has(579) then return "spirsword" end   -- 灵剑
    if has(CollectibleType.COLLECTIBLE_TECHNOLOGY_2)      then return "technology" end
    if has(CollectibleType.COLLECTIBLE_TECHNOLOGY)        then return "technology" end
    if has(CollectibleType.COLLECTIBLE_CHOCOLATE_MILK)    then return "chocomilk" end
    return "tears"
end

-- 宝宝 / 幸运 / 乘区（口径见 docs/special-attack-power.md §4.9 / §4.11）
local FAMILY_BY_ID = { [360] = "incubus", [698] = "twisted_pair" }   -- Succubus(417) 不单独乘：面板已含且只在光环内生效
local LUCK_BY_ID = {
    [150] = "tough_love", [374] = "holy_light", [496] = "euthanasia",
    [503] = "little_horn", [637] = "knockout", [55] = "moms_eye", [87] = "loki_horns", [616] = "birdseye", [495] = "ghostpepper",
}
local B_FORM = { brimstone = true, momsknife = true, drfetus = true,
                 epicfetus = true, techx = true, ludovico = true }

local function readKit(player, form, damage)
    local kit = { family = {}, luckItems = {}, bffs = false, lilith = false,
                  mult = 1, addDps = 0 }
    if not player then return kit end
    local function has(id)
        local ok, res = pcall(function() return player:HasCollectible(id) end)
        return ok and res or false
    end

    local fk = {}
    for id, key in pairs(FAMILY_BY_ID) do
        if has(id) then fk[#fk + 1] = key end
    end
    table.sort(fk)
    kit.family = fk

    local lk = {}
    for id, key in pairs(LUCK_BY_ID) do
        if has(id) then lk[#lk + 1] = key end
    end
    table.sort(lk)
    kit.luckItems = lk

    kit.bffs = has(247)
    pcall(function()
        local t = player:GetPlayerType()
        kit.lilith = (t == PlayerType.PLAYER_LILITH) or (t == PlayerType.PLAYER_TAINTED_LILITH)
    end)

    -- 死眼：与 B 类形态共存时冻结为 1（wiki 明示）
    if has(373) and not B_FORM[form] then kit.mult = kit.mult * 1.91 end
    pcall(function()
        if player:HasPlayerForm(PlayerForm.PLAYER_FORM_BOOKWORM)  then kit.mult = kit.mult * 1.5 end
        if player:HasPlayerForm(PlayerForm.PLAYER_FORM_CONJOINED) then kit.mult = kit.mult * 1.5 end
    end)
    -- Tech.5：额外激光 2.5 次/秒 × 面板伤害（加法）
    if has(244) then kit.addDps = 2.5 * (damage or 0) end
    return kit
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

-- 防爆：Repentance 只有这两件给"免疫爆炸"（223 纵火狂 / 375 宿主之帽）。
-- REPENTOGON 没有现成的 bool，只能按白名单判定；以后发现别的就加进来。
local EXPLODE_IMMUNE = { 223, 375 }
local function hasExplosionImmunity(player)
    for i = 1, #EXPLODE_IMMUNE do
        local ok, has = pcall(function() return player:HasCollectible(EXPLODE_IMMUNE[i]) end)
        if ok and has then return true end
    end
    return false
end

local function snapshot(player)
    local s = { form = "tears", damage = 0, maxFireDelay = 10, multiShot = 1,
                red = 0, soul = 0, bone = 0, survival = 0, power = 0,
                canFly = false, explode = false }
    if not player then return s end

    pcall(function()
        s.damage       = player.Damage or 0
        s.maxFireDelay = player.MaxFireDelay or 10
        -- 飞行：CanFly 可能是字段也可能是方法（REPENTOGON 版本差异），自适应 + 一次性探针
        do
            local ft = type(player.CanFly)
            local fv = nil
            if ft == "function" then
                local ok, r = pcall(function() return player:CanFly() end)
                fv = ok and r or false
            else
                fv = player.CanFly
            end
            s.canFly = (fv == true)
        end
    end)
    s.explode   = hasExplosionImmunity(player)
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

    -- 战力：优先新公式（查表 + 宝宝 + 幸运），模块缺失时退回旧口径
    -- 整段包 pcall：新路径任何一处抛错都退回旧公式，绝不能把采集打断
    -- （snapshot 被 beginRoom/settleRoom 直接调用，抛错会让整间房记不下来）
    local kit
    local okNew, newPower = pcall(function()
        kit = readKit(player, s.form, s.damage)
        return powerForms.output({
            damage = s.damage, maxFireDelay = s.maxFireDelay,
            form = s.form, numTearsAvg = s.multiShot,
            luck = s.luck, luckItems = kit.luckItems,
            family = kit.family, bffs = kit.bffs, lilith = kit.lilith,
            mult = kit.mult, addDps = kit.addDps,
        })
    end)
    if okNew and type(newPower) == "number" then
        s.power = newPower
        s.kit = kit
    else
        s.power = power.output({
            damage = s.damage, maxFireDelay = s.maxFireDelay,
            multiShot = s.multiShot, form = s.form, chargeFactor = 1.0,
        })
        if powerForms and not state.pwrWarned then
            state.pwrWarned = true
            log("新战力公式失败，已退回旧口径：" .. safeToString(newPower))
        end
    end

    -- 调试：战力变化时打一行，方便用控制台批量实测（作者 2026-10-23）
    kit = kit or { family = {}, luckItems = {}, bffs = false, mult = 1, addDps = 0 }
    if config.debug and math.abs((s.power or 0) - (state.lastPower or -1)) > 0.05 then
        state.lastPower = s.power
        log(string.format("[PWR] %s D=%.2f FR=%.3f n=%d luck=%.0f fam=%s bffs=%s mult=%.2f add=%.2f -> %.2f",
            s.form, s.damage, 30 / ((s.maxFireDelay or 10) + 1), s.multiShot,
            s.luck or 0, table.concat(kit.family, "+"), tostring(kit.bffs),
            kit.mult, kit.addDps, s.power))
    end
    return s
end

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
    if not state.store then return end   -- 空存档保护（2026-10-24 删档后崩过）
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
        base = 0, final = 0, max = 1, res = 2, t0 = nowSec(), ws = wallText(), hl = 0,
        floors = {}, rooms = {}, pills = {},
    }
    -- 开局自带道具也算"获得"（角色初始道具、伊甸的随机道具、start with 类 mod 给的东西）
    state.startItems = readCollectibles(player)
    log(string.format("开局 %s（seed=%d char=%d，历史 %d 局）", id, seed, char, #state.store.index))
end

--- 把"正在进行的局"刷进 store 并落盘。换层是天然检查点，崩溃最多丢一层。
local function flushCurrentRun(reason)
    local run = state.current
        if not run or not state.store then return end
    -- 按**种子**替换旧条目：不再只依赖 state.currentEntry（读档/切槽后会失效，2026-10-26 实测存出 5 个同局空壳）
    local old = fmt.findBySeed(state.store, run.seed)
    if old then fmt.removeEntry(state.store, old) end
    state.currentEntry = fmt.appendRun(state.store, run)
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
        canFlyIn = snap.canFly or false, explodeIn = snap.explode or false,
        firstIn = firstVisitNow(),
        bossIn  = bossIdNow(),
        ubIn    = ultimateBossNow(),
        dmgIn   = snap.damage, muIn = snap.multiShot, fmIn = snap.form,
        stIn    = { dv = snap.damage, ts = snap.tears, ss = snap.shotspeed,
                    rg = snap.rangeStat, mv = snap.movespeed, lk = snap.luck },
        tIn = nowMs(),
        tInGame = gameTimeMs(),   -- 游戏内时间（探针：和帧数对照）
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
    -- 探针：持有数一次性暴涨时打上下文（2026-10-24 定位幽灵 id 用）
    do
        local n = #items
        local prev = state.lastItemCount or 0
        if n - prev >= 20 then
        end
        state.lastItemCount = n
    end

    local gained, seen = {}, {}
    for i = 1, #items do
        local id = items[i]
        seen[id] = (seen[id] or 0) + 1
        if seen[id] > (p.itemsIn[id] or 0) then gained[#gained + 1] = id end
    end
    -- 第一间房：把开局自带道具记成"获得"（作者 2026-10-22 要求：初始道具也算获得）
    -- 以前这里直接清空，因为初始化顺序会造出假阳性；现在改成用 beginRun 时拍下的快照
    local firstRoom = (#run.rooms == 0)
    if firstRoom then
        gained = {}
        local st = state.startItems or {}
        -- 兜底：beginRun 那一刻玩家还没拿到起始道具（D6 / mod 初始道具都在这之后挂上），
        -- 所以 startItems 往往是空的。出第一间房时用当前持有补一次（2026-10-26）
        if #st == 0 then st = items end
        for k = 1, #st do gained[k] = st[k] end
    end
    -- 扫描降级路径：HasCollectible 会误报（见 docs/PERFORMANCE.md §1.1）
    -- 一旦走扫描，本房不记「获得」——宁可漏，不可脏
    if itemAccessBroken then
        if itemwatch then itemwatch.drain() end
        gained = {}
    end

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
    -- 兜底：一房新增超过 12 件基本可以判定是扫描伪影（真实房间最多 3~4 件）
    if #gained > 12 then
        log(string.format("[FILTER] 本房新增 %d 件，超过上限 → 判定为伪影，全部丢弃", #gained))
        gained = {}
    end


    -- 黑名单过滤：某些道具会被别的 mod 反复挂到身上，属于误记（见 config.itemBlacklist）
    -- 过滤放在这里 → 四个字段（it / iq / ik）都拿不到它，四级/零级列表自然也不会有
    if config.itemBlacklist and #gained > 0 then
        local keep = {}
        for k = 1, #gained do
            if not config.itemBlacklist[gained[k]] then keep[#keep + 1] = gained[k] end
        end
        gained = keep
    end

    -- 品质 < 0 = 我们的道具表里没有这个 id（多半是 mod 把整份道具表塞给玩家）。
    -- 这类条目会灌满 Q0（作者 2026-10-22 反馈「Q0 又 400+」），采集层直接丢掉。
    do
        local keep2, dropped = {}, 0
        for k = 1, #gained do
            local okQ, q = pcall(qualityOf, gained[k])
            if okQ and type(q) == "number" and q >= 0 then
                keep2[#keep2 + 1] = gained[k]
            else
                dropped = dropped + 1
            end
        end
        if dropped > 0 then
            log(string.format("[FILTER] 丢弃 %d 个无品质道具（mod 整表写入的脏 id），保留 %d 个",
                dropped, #keep2))
            gained = keep2
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

    -- 与 it 平行：这件道具带来的战力增量（作者 2026-10-22 要的「跃迁」依据）
    -- 房间进/出战力的差是准确值，但没有单件归因，所以：
    --   · 本房只有 1 件有效道具 → 增量 = 出战 - 进战（精确）
    --   · 多件 → 均摊，并打日志标记（罕见）
    --   · iq < 0（mod 道具整表写入的脏 id）→ 记 0，不参与跃迁排序
    local gainedE = {}
    local validN, dirtyN = 0, 0
    for k = 1, #gained do
        if (gainedQ[k] or -1) < 0 then dirtyN = dirtyN + 1 else validN = validN + 1 end
    end
    local dPower = (snap.power or 0) - (tonumber(p.p) or 0)   -- 进房 p.p → 出房 snap.power
    for k = 1, #gained do
        if (gainedQ[k] or -1) < 0 then
            gainedE[k] = 0
        elseif validN > 0 then
            gainedE[k] = dPower / validN
        else
            gainedE[k] = 0
        end
    end
    -- 局内 HUD 数据（作者 2026-10-22）：当前战力 + 本次增量，3 秒后增量消失
    if bookui and bookui.hud then
        bookui.hud.power = snap.power
        bookui.hud.delta = dPower
        local fc = 0
        pcall(function() fc = Isaac.GetFrameCount() end)
        bookui.hud.untilFrame = fc + math.floor((config.hudPowerFadeMs or 3000) / 1000 * 30)
    end

    if validN > 1 then
        log(string.format("[ATTR] 同房 %d 件有效道具（脏 %d），战力差 %.2f 均摊",
            validN, dirtyN, dPower))
    end

    local pok = readPockets(player)
    local bossId = p.bossIn or 0
    local firstVisit = p.firstIn or false

    -- 时长：清房即停（有清房时间戳就用它），并打出两种时钟的对照
    local tOutFx  = nowMs()
    local tOutGm  = gameTimeMs()
    local msExitFx = tOutFx - (p.tIn or tOutFx)
    local msClearFx = p.tClear and (p.tClear - (p.tIn or p.tClear)) or nil
    local msExitGm = tOutGm - (p.tInGame or tOutGm)
    local msClearGm = p.tClearGame and (p.tClearGame - (p.tInGame or p.tClearGame)) or nil
    local msFinal = math.floor((msClearFx or msExitFx) + 0.5)   -- 取整：GetTime 可能返回小数，%d 会炸
    -- Boss 房窄探针（作者 2026-10-28）：验证"清房即停"是否生效，其余房间不输出
    if config.bossProbe ~= false then
        local rt = tonumber(p.ident and p.ident.type) or 0
        local isBossRoom = (rt == 5) or (rt == 17) or ((p.ubIn or 0) > 0)
        if isBossRoom then
            log(string.format("[BT] 帧: 清房=%s 出房=%.1fs | 采用=%dms",
                msClearFx and string.format("%.1fs", msClearFx / 1000) or "-",
                msExitFx / 1000, msFinal))
        end
    end
    if config.timeProbe then
        log(string.format("[TIME] 帧: 清房=%s 出房=%s | 游戏: 清房=%s 出房=%s | 采用=%dms",
            msClearFx and string.format("%.1fs", msClearFx / 1000) or "-",
            string.format("%.1fs", msExitFx / 1000),
            msClearGm and string.format("%.1fs", msClearGm / 1000) or "-",
            string.format("%.1fs", msExitGm / 1000),
            msFinal))
    end

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
        ms = msFinal,   -- 清房即停（没有清房时间戳时退回出房时间）
        dmg = math.floor(p.dmg + 0.5),
        clr = p.cleared,
        it = gained,
        iq = gainedQ,
        ik = gainedK,
        ie = gainedE,
        dv = p.dmgIn or 0, mu = p.muIn or 1, fm = p.fmIn or "tears",
        foes = p.foes or 0,
        mxhp = p.mxhpIn or 0, mxhpo = snap.maxhp or 0,
        c = p.pockets and p.pockets.c or 0, co = pok.c,
        bmb = p.pockets and p.pockets.b or 0, bmbo = pok.b,
        key = p.pockets and p.pockets.k or 0, keyo = pok.k,
        boss = bossId, ub = p.ubIn or 0, first = firstVisit,
        fli = p.canFlyIn or false, fl = snap.canFly or false,
        exi = p.explodeIn or false, ex = snap.explode or false,
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
      run.we = wallText()   -- 结束墙钟时间（作者 2026-10-28 要求，显示在总览）
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
    -- 本会话没进过局（只在菜单里切了存档槽）→ 不写盘，避免把 A 档数据写进 B 档
    if not state.runActive then return end
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
    -- 解析失败也要有个空 store，否则后面 findUnfinished 会拿到 nil 崩掉
    local okSplit, store, warns = pcall(fmt.splitBlob, blob)
    if not okSplit or not store then
        err("存档解析失败：" .. safeToString(store))
        state.store = { lines = {}, index = {} }
        return
    end
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
    -- 合并：硬编码默认值 + config.lua（config.lua 优先）
    config = (function()
        local c = { powerTopN = 3, q4MaxPages = 3, absDelta = 0.5, relPct = 15 }
        if type(config) == "table" then
            for k, v in pairs(config) do c[k] = v end
        end
        return c
    end)(),
    fmt      = fmt,
    hl       = highlight,
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
    -- HUD 战力定期刷新（每 20 帧）：开局/换层的快照可能太早，数值会不准
    do
        local fcOk, fc = pcall(function() return Isaac.GetFrameCount() end)
        if fcOk and fc and (fc % 20) == 0 and bookui and bookui.hud then
            local okp, p0 = pcall(function() return Isaac.GetPlayer(0) end)
            if okp and p0 then
                local okS, s0 = pcall(snapshot, p0)
                if okS and s0 and s0.power then bookui.hud.power = s0.power end
            end
        end
    end
    if bookui and bookui.renderHud then uiGuard("renderHud", bookui.renderHud) end
end)

configui.init({ settings = settings, log = log, onChanged = function() pcall(saveData) end })

-- 每帧监视道具变化；局开始时快照权重并重建基线
add(ModCallbacks.MC_POST_GAME_STARTED, function()
    local p = getPlayer()
    if itemwatch then itemwatch.reset(p, 1800) end
end)

if configui.isReady() then log("ImGui 配置菜单已挂上") else log("ImGui 不可用（或挂载失败），跳过配置菜单") end

add(ModCallbacks.MC_POST_PLAYER_INIT, function(player)
    -- 一次性：导出 700~2600 的 id→名字 对照，用来修被 mod 漂移弄乱的评级配置
    if config.dumpItemIds then
        local cfg0 = Isaac.GetItemConfig()
        if cfg0 then
            for id = 700, 2600 do
                local ok, c = pcall(function() return cfg0:GetCollectible(id) end)
                if ok and c and c.Name and c.Name ~= "" then
                    log(string.format("[IDS] %d\t%s\t%s", id, tostring(c.Name), tostring(c.ModName or "")))
                end
            end
            log("[IDS] 导出结束")
        end
    end
    state.store = nil
    state.runActive = true
    state.loaded = false
    loadData()   -- ← 上一轮修重复行时被误删，导致 store 一直 nil

    if isMainPlayer(player) then beginRun(player) end
    if state.current then flushCurrentRun("开局") end   -- 第一层没换层前也有记录（2026-10-24）
end)

-- 吃药丸（作者 2026-10-21 定的做法，2026-10-25 恢复）：
-- 只记 id + 层/房；属性影响靠 core/pills.lua 白名单查表。
-- 不在这里回读属性——回读会抓到临时/中间值，还会被大药丸/金药丸的倍数搞乱。
add(ModCallbacks.MC_USE_PILL, function(_, pillEffect, _player, _flags)
    if not state.current then return end
    local p = state.pending or {}
    state.current.pills = state.current.pills or {}
    state.current.pills[#state.current.pills + 1] = {
        f = p.f or state.floorDepth or 0,
        i = p.i or 0,
        e = pillEffect or -1,
    }
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

-- 自测：config.selfTest=true 时，进局后自动逐件给道具 → 记战力 → 移除。
-- 为什么不用控制台：盲按 ~ 打字在控制台没打开时会变成游戏操作（作者 2026-10-23 提）。
local TEST_IDS = {
    -- 先测形态（互斥，按 detectForm 的优先级**从低到高**给，后给的覆盖先给的）
    69, 68, 579, 168, 52, 114, 395, 118, 329,
    -- 再测宝宝 / 幸运 / 乘区（不影响形态）
    360, 698, 374, 244, 373, 150,
}
local testState = { i = 0, phase = 0, tick = 0, done = false }

local function selftestTick(player)
    if not config.selfTest or not player or testState.done then return end
    testState.tick = testState.tick + 1
    if testState.tick % 15 ~= 0 then return end

    if testState.phase == 0 then
        testState.i = testState.i + 1
        local id = TEST_IDS[testState.i]
        if not id then testState.done = true; log("[TEST] 全部完成"); return end
        local ok = pcall(function() player:AddCollectible(id, 0, false) end)
        if not ok then log("[TEST] AddCollectible 失败 id=" .. id) end
        testState.phase = 1
    else
        local id = TEST_IDS[testState.i]
        local s = snapshot(player)
        log(string.format("[TEST] id=%d ok form=%s pwr=%.2f D=%.2f FR=%.3f n=%d fam=%s bffs=%s mult=%.2f add=%.2f",
            id, s.form, s.power, s.damage, 30 / ((s.maxFireDelay or 10) + 1), s.multiShot,
            table.concat((s.kit and s.kit.family) or {}, "+"),
            tostring(s.kit and s.kit.bffs), (s.kit and s.kit.mult) or 1,
            (s.kit and s.kit.addDps) or 0))
        pcall(function() player:RemoveCollectible(id) end)
        testState.phase = 0
    end
end

add(ModCallbacks.MC_POST_UPDATE, function()
    -- itemwatch 每帧比对已移除（作者 2026-10-24）：改回"只按房间边界比对"。
    -- 同房拿了又丢会漏记（作者接受）；跨房瞬间获得由下一房对比补上。
    selftestTick(getPlayer())
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
        -- 清房即停：记下这一刻，结算时用它代替出房时间（作者 2026-10-26）
        if state.pending and not state.pending.tClear then
            state.pending.tClear = nowMs()
            state.pending.tClearGame = gameTimeMs()
        end
        -- Boss 房：清房这一刻 GetBossID() 才可靠（cuerlib / antibirth music 都是死后才读）
        if state.pending then
            local t = 0
            pcall(function() t = num(Game():GetRoom():GetType()) end)
            if t == 5 or t == 17 then
                local b = bossIdNow()
                if b and b ~= 0 then state.pending.bossIn = b end   -- 只在取到非 0 时覆盖（清房瞬间可能返回 0）
                local u = ultimateBossNow()
                if u and u ~= 0 then state.pending.ubIn = u end
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
-- 启动自检：确认游戏加载的是"接了新战力公式"的那份代码（[PWR] 批量实测要靠它）
emit(LOG_PREFIX .. "[PWR] wired=" .. tostring(powerForms ~= nil) .. " build=2")
