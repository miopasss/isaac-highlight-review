-- ============================================================================
-- main.lua —— Item Weight Editor（道具权重编辑器）
--
-- 职责只有一件事：**改道具的出现率和评级**。
--   · 不采集、不做界面书页、不碰玩家属性，卸掉之后游戏完全恢复原样
--   · 只会「降低」出现率（0 <= 倍数 <= 1）；提高要绕过抽取逻辑，留到以后
--
-- 对外契约（给 Highlight Review 之类的外部 mod 读）：
--   _G.HLR = { version = 1, isReady, getQuality, getWeightMul, has, count }
--   读不到就是 nil，调用方自己回退官方值。加载顺序无关。
--
-- 硬规则：
--   1. 日志必须走 Isaac.DebugString（print 不进 log.txt）
--   2. 回调里再抽池会重入，pool.lua 里有 inCallback 保护
-- ============================================================================
local mod = RegisterMod("Item Weight Editor", 1)

local LOG_PREFIX = "[WEIGHT] "

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

local jsonmini = tryRequire("core.jsonmini", "core/jsonmini")
local rating   = tryRequire("core.rating", "core/rating")
local ratedata = tryRequire("core.rating_data", "core/rating_data")
local poolmod  = tryRequire("core.pool", "core/pool")
local POOL_SELFTEST = true   -- 临时（2026-10-30）：开局自检权重拦截链路，验证完改 false
local settings = tryRequire("core.iwe_settings", "core/iwe_settings")
local storemod = tryRequire("core.store", "core/store")
local rates    = rating

local editor, configui
pcall(function() editor = include("ui.rating_editor") end)
pcall(function() configui = include("ui.config") end)
local lang
pcall(function() lang = include("ui.lang") end)

local function log(msg) emit(LOG_PREFIX .. tostring(msg)) end
local function err(msg) emit(LOG_PREFIX .. "ERROR: " .. tostring(msg)) end


if not (rating and jsonmini and storemod) then
    err("模块载入失败（rating=" .. tostring(rating ~= nil) ..
        " jsonmini=" .. tostring(jsonmini ~= nil) ..
        " store=" .. tostring(storemod ~= nil) .. "）")
    return
end

-- ── 引擎 API 自检（2026-10-30）──────────────────────────────────────────────
-- 为什么需要：`rng:NextFloat()` 在这个构建里根本不存在，而 pcall 把失败静默吞了，
-- 导致"权重从未生效"藏了好几天。离线单测抓不到这种**环境缺失**，只能在运行时断言。
-- 任何一项缺失都会打 [API] 缺失: …，方便一眼定位。
do
    local checks = {
        { "RNG",                 function() return RNG end },
        { "RNG(1).RandomFloat",  function() return RNG(1).RandomFloat end },
        { "Isaac.GetEntityTypeByName", function() return Isaac.GetEntityTypeByName end },
        { "Isaac.GetItemIdByName",     function() return Isaac.GetItemIdByName end },
        { "Game():GetItemPool",        function() return Game():GetItemPool() end },
    }
    local missing = {}
    for _, c in ipairs(checks) do
        local okc, v = pcall(c[2])
        if not okc or v == nil then missing[#missing + 1] = c[1] end
    end
    if #missing == 0 then
        log("[API] 依赖自检通过（" .. #checks .. " 项）")
    else
        log("[API] 缺失: " .. table.concat(missing, ", ") .. " —— 对应功能会降级，请上报")
    end
end

-- ── 状态 ────────────────────────────────────────────────────────────────────

local state = { store = nil, loaded = false }

local function getPlayer()
    local ok, p = pcall(function() return Isaac.GetPlayer(0) end)
    if ok and p then return p end
    local ok2, p2 = pcall(function() return Game():GetPlayer(0) end)
    if ok2 then return p2 end
    return nil
end

-- ── 存档 ────────────────────────────────────────────────────────────────────

local saveData   -- 前置声明：initUI 里的闭包要用，Lua 的 local 只往后可见

--- 建界面必须在**读完档 + 定好语言之后**做：
---   1) ImGui 的控件标签只能在创建时给定，语言晚了就只能是中文
---   2) 绝不能用 ImGui.RemoveWindow 重建 —— 实测会让游戏直接崩（minidump）
local function initUI()
    if editor and editor.init and not editor.isReady() then
        local ok = editor.init({
            rating = rating,
            lang = lang,
            settings = settings,
            getPlayer = getPlayer,
            log = log,
            onChanged = function() saveData() end,
        })
        if ok then log("编辑器已就绪（F6 打开）") else err("编辑器初始化失败") end
    end
    if configui and configui.init and not configui.isReady() then
        local ok = configui.init({
            settings = settings,
            log = log,
            onChanged = function() saveData() end,
        })
        if ok then log("设置菜单已挂上") end
    end
end

local function loadData()
    if state.loaded then return end
    state.loaded = true

    local ok, blob = pcall(function()
        if mod:HasData() then return mod:LoadData() end
        return nil
    end)
    if not ok then
        err("读档失败：" .. tostring(blob))
        state.store = storemod.new()
        return
    end

    state.store = storemod.split(blob)
    if settings then settings.load(state.store) end

    -- 语言必须在**读过存档之后**才能确定（settings 在 init 时全是默认值）
    if lang then
        log(string.format("[I18N] settings=%s rawLang=%s", tostring(settings ~= nil),
            tostring(settings and settings.get("lang") or "n/a")))
        lang.init(settings)
        log("[I18N] lang=" .. tostring(lang.code and lang.code() or "?"))
        -- 语言可能和启动时不同：重建两个窗口的文字
        initUI()
    end
    rating.load(state.store)
    log(string.format("载入 %d 条评级配置 / %d 行", rating.count(), #state.store.lines))
end

saveData = function()
    if not state.store then return false end
    -- 本会话没进过局（只是在菜单里切了存档槽）→ 绝不写盘
    -- 2026-10-24 实测：1 号档启动 → 菜单切 3 号档 → 直接退出，会把 1 号档的数据写进 save3
    if not state.runActive then return false end
    if rating and not rating.loaded then
        err("评级还没读档，拒绝写盘（防止覆盖旧数据）")
    end
    if settings then settings.save(state.store) end
    rating.save(state.store)
    local blob = storemod.build(state.store)
    local ok, e = pcall(function() mod:SaveData(blob) end)
    if not ok then
        err("落盘失败：" .. tostring(e))
        return false
    end
    return true
end

-- ── 初始化 ──────────────────────────────────────────────────────────────────

rating.init(jsonmini, ratedata or {})
if settings then
    settings.init()
    settings.only = { "f6", "lang" }
end
rating.publish()

if poolmod then poolmod.snapshot(poolmod.COMMON_POOLS) end

local function add(event, fn, priority)
    if event == nil then return end
    if priority ~= nil then
        local ok, res = pcall(function() return mod:AddPriorityCallback(event, priority, fn) end)
        if ok and res ~= nil then return end
    end
    mod:AddCallback(event, fn)
end

-- ── 回调 ────────────────────────────────────────────────────────────────────

add(ModCallbacks.MC_POST_PLAYER_INIT, function()
    -- 每次进局都重读**当前存档槽**：mod:LoadData() 是按槽返回的，
    -- 只在进程里读一次的话，"1 号档 → 3 号档"会把 1 号档的配置写进 3 号档。
    -- 回顾 mod 用的就是这个写法（main.lua 的 MC_POST_PLAYER_INIT）。
    state.runActive = true   -- 真的进过局：只有这时才允许写盘（防止菜单里切槽后退出把 A 档写进 B 档）
    if editor and editor.resetOrder then editor.resetOrder() end   -- 每局重置"已获得"的顺序
    state.store = nil
    state.loaded = false
    if rating then rating.loaded = false end
    loadData()

        -- 自检（作者 2026-10-30 要求）：必须放在 loadData() 之后 —— 之前评级表是空的，
        -- getWeightMul 一律返回 nil，自检会全部"返回 nil"且没有判定日志。
        if POOL_SELFTEST and poolmod then
            -- 先打一组掷点样本，直接看分布是否均匀（0.001/0.003 这种就是坏的）
            do
                local parts = {}
                for _, sd in ipairs({ 11111, 22222, 33333, 44444, 55555, 66666, 77777, 88888, 99999, 123456 }) do
                    local v, src = poolmod.rollFor(sd)
                    parts[#parts + 1] = string.format("%.3f(%s)", v, src == "engine" and "E" or "L")
                end
                log("[SELFTEST] 掷点样本: " .. table.concat(parts, " "))
            end
            for _, tid in ipairs({ 1570, 1565, 118 }) do
                for _, sd in ipairs({ 11111, 22222, 33333 }) do
                    local ok, err = pcall(function()
                        local r = poolmod.onPostGet(rating, tid, 0, false, sd, log)
                        log(string.format("[SELFTEST] id=%d seed=%d 权重=%.2f → 返回 %s",
                            tid, sd, rating.getWeightMul(tid) or -1, tostring(r)))
                    end)
                    if not ok then log("[SELFTEST] 抛错: " .. tostring(err)) end
                end
            end
        end
end)

-- 每出一间房比对一次持有列表：给新拿到的道具编号（顺序只在本局内有效）
add(ModCallbacks.MC_POST_NEW_ROOM, function()
    if editor and editor.touch then editor.touch() end
end)

add(ModCallbacks.MC_POST_GAME_STARTED, function()
    loadData()
    if poolmod then poolmod.snapshot(poolmod.COMMON_POOLS) end
end)

-- 抽道具时改出现率
add(ModCallbacks.MC_POST_GET_COLLECTIBLE, function(_, itemID, poolType, decrease, seed)
    if not poolmod then return nil end
    return poolmod.onPostGet(rating, itemID, poolType, decrease, seed, log)
end, CallbackPriority and CallbackPriority.LATE or nil)

-- 热键：打开编辑器
add(ModCallbacks.MC_POST_RENDER, function()
    if editor and editor.isReady() then
        local key = (settings and settings.get("f6")) or Keyboard.KEY_F6
        if Input.IsButtonTriggered(key, 0) then
            editor.toggle()
        end
        if editor.watch then editor.watch() end
    end
end)

add(ModCallbacks.MC_PRE_GAME_EXIT, function()
    saveData()
    state.runActive = false
end)

-- ── 界面 ────────────────────────────────────────────────────────────────────

local function onChanged()
    saveData()
end



log("loaded v0.1.3 (REPENTOGON=" .. tostring(REPENTOGON ~= nil) .. ")")
