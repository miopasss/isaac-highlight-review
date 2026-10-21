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
local settings = tryRequire("core.settings", "core/settings")
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
        lang.init(settings)
        -- 语言可能和启动时不同：重建两个窗口的文字
        if configui and configui.rebuild then configui.rebuild() end
        if editor and editor.rebuild then editor.rebuild() end
    end
    rating.load(state.store)
    log(string.format("载入 %d 条评级配置 / %d 行", rating.count(), #state.store.lines))
end

local function saveData()
    if not state.store then return false end
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
    loadData()
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
end)

-- ── 界面 ────────────────────────────────────────────────────────────────────

local function onChanged()
    saveData()
end

if editor and editor.init then
    local ok = editor.init({
        rating = rating,
        lang = lang,
        settings = settings,
        getPlayer = getPlayer,
        log = log,
        onChanged = onChanged,
    })
    if ok then log("道具权重编辑器已就绪（F6 打开）") else err("编辑器初始化失败") end
end

if configui and configui.init then
    local ok = configui.init({
        settings = settings, log = log, onChanged = onChanged,
        onRebuildEditor = function() if editor and editor.rebuild then editor.rebuild() end end,
    })
    if ok then log("设置菜单已挂上") end
end

log("loaded v0.1.0 (REPENTOGON=" .. tostring(REPENTOGON ~= nil) .. ")")
