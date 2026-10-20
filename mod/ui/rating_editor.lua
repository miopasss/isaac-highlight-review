-- ============================================================================
-- ui/rating_editor.lua —— 道具评级/权重编辑器（ImGui + 鼠标）
--
-- 为什么用 ImGui 而不是册子自绘：需要搜索框、滑条、数字输入，
-- 自绘成本高；而"已获得道具"只有 20~40 个，下拉点选即可，不需要方向键。
--
-- 已知限制（调研确认）：
--   · ImGui 没有 AddImage → 不显示道具图标，只显示名字
--   · ImGui 没有滚动列表 → 用 Combobox 过滤，而不是长列表
--   · ImGui 不持久化 → 值由本模块每次渲染时从 rating 表推回
--
-- 打开方式：主循环里按热键 → editor.toggle()
-- ============================================================================
local E = {}

local WIN      = "hlr_rating_win"
local TAB_EDIT = "hlr_rating_tab_edit"
local TAB_LIST = "hlr_rating_tab_list"

local SEL_COMBO   = "hlr_sel_combo"     -- 搜索结果下拉
local OWNED_COMBO = "hlr_owned_combo"   -- 已获得道具下拉
local S_QUERY     = "hlr_query"         -- 搜索框
local S_RATING    = "hlr_rating"        -- 评级滑条
local S_WEIGHT    = "hlr_weight"        -- 权重倍数
local S_ON        = "hlr_on"            -- 启用
local S_INFO      = "hlr_info"          -- 结果显示文本

local READY   = false
local opened  = false
local deps    = nil
local curId   = nil      -- 当前编辑的道具 id
local query   = ""
local candidates = {}    -- { {id=..., label=...}, ... }
local owned      = {}    -- 已获得道具候选
local listMode   = false

-- ── 工具 ────────────────────────────────────────────────────────────────────

local function itemName(id)
    local ok, cfg = pcall(function() return Isaac.GetItemConfig():GetCollectible(id) end)
    if ok and cfg then
        local n = tostring(cfg.Name)
        -- 未本地化的 key 形如 #OLD_BANDAGE_NAME，去掉井号看起来干净些
        n = n:gsub("^#", "")
        return n
    end
    return "?"
end

local function itemNameCN(id)
    -- 本地化名字；没有就回退英文
    local ok, s = pcall(function()
        local cfg = Isaac.GetItemConfig():GetCollectible(id)
        if not cfg then return nil end
        if cfg.Localized then return cfg.Localized end
        return nil
    end)
    if ok and s and s ~= "" then return s end
    return itemName(id)
end

--- 官方品质（用于对照显示）
local function officialQuality(id)
    local ok, q = pcall(function()
        local cfg = Isaac.GetItemConfig():GetCollectible(id)
        return cfg and cfg.Quality
    end)
    if ok and type(q) == "number" then return q end
    return -1
end

--- 构造搜索候选：先按 id，再按英文名（不区分大小写）
local function buildCandidates()
    candidates = {}
    local q = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if q == "" then return end

    -- 纯数字 → 直接当 id 塞到最前
    local asId = tonumber(q)
    if asId and asId > 0 then
        candidates[#candidates + 1] = {
            id = asId,
            label = string.format("%d  %s", asId, itemName(asId)),
        }
    end

    local maxId = 1800
    local limit = 40
    for id = 1, maxId do
        if #candidates >= limit then break end
        if id ~= asId then
            local nm = itemName(id):lower()
            if nm:find(q, 1, true) then
                candidates[#candidates + 1] = {
                    id = id,
                    label = string.format("%d  %s", id, itemName(id)),
                }
            end
        end
    end
end

--- 已获得道具（当前持有）
local function buildOwned()
    owned = {}
    local p = deps and deps.getPlayer and deps.getPlayer()
    if not p then return end
    local ok, list = pcall(function() return p:GetCollectiblesList() end)
    if not ok or type(list) ~= "table" then return end
    local ids = {}
    for id in pairs(list) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        owned[#owned + 1] = {
            id = id,
            label = string.format("%d  %s", id, itemNameCN(id)),
        }
    end
end

local function labelsOf(list)
    local out = {}
    for i = 1, #list do out[i] = list[i].label end
    if #out == 0 then out[1] = "（无）" end
    return out
end

--- 刷新信息文本（评级对象、官方值、各池权重）
local function refreshInfo()
    if not curId then
        ImGui.UpdateText(S_INFO, "先在下面选一个道具")
        return
    end
    local r = deps.rating
    local lines = {
        string.format("%s  #%d", itemNameCN(curId), curId),
        string.format("官方评级 %s   HL 评级 %s",
            tostring(officialQuality(curId)),
            (r.getRating(curId) and string.format("%.1f", r.getRating(curId))) or "未设置"),
    }
    local pools = deps.pool and deps.pool.poolsOf and deps.pool.poolsOf(curId) or {}
    if #pools == 0 then
        lines[#lines + 1] = "该道具不在任何已快照的池子里"
    else
        local parts = {}
        for i = 1, math.min(#pools, 4) do
            local pw = pools[i]
            local mul = r.getWeightMul(curId) or 1
            parts[#parts + 1] = string.format("池%d %.2f→%.2f", pw.pool, pw.weight, pw.weight * mul)
        end
        lines[#lines + 1] = "权重 " .. table.concat(parts, "  ")
    end
    if not deps.pool or not deps.pool.hasSnap then
        lines[#lines + 1] = "（权重快照未建立：需进一局）"
    end
    ImGui.UpdateText(S_INFO, table.concat(lines, "\n"))
end

--- 把评级表里的值推回控件（ImGui 不持久化，必须每次推）
local function pushValues()
    if not curId then return end
    local r = deps.rating
    local q = r.getRating(curId)
    ImGui.UpdateData(S_RATING, ImGuiData.Value, q or (officialQuality(curId) >= 0 and officialQuality(curId) or 0))
    ImGui.UpdateData(S_WEIGHT, ImGuiData.Value, r.getWeightMul(curId) or 1.0)
    local e = r.entries[curId]
    ImGui.UpdateData(S_ON, ImGuiData.Value, not (e and e.on == false))
end

--- 选中一个道具
local function selectId(id)
    if not id or id <= 0 then return end
    curId = id
    pushValues()
    refreshInfo()
end

-- ── 建界面 ──────────────────────────────────────────────────────────────────

local function build()
    ImGui.CreateWindow(WIN, "Highlight Review · 道具评级")
    ImGui.SetSize(WIN, 460, 380)
    ImGui.AddTabBar(WIN, "hlr_tabbar")
    ImGui.AddTab("hlr_tabbar", TAB_EDIT, "编辑")
    ImGui.AddTab("hlr_tabbar", TAB_LIST, "已修改")

    -- ── 编辑页 ──
    ImGui.AddInputText(TAB_EDIT, S_QUERY, "搜索（英文名 或 id）", function(_, val)
        query = tostring(val)
        buildCandidates()
        if #candidates > 0 then
            ImGui.UpdateData(SEL_COMBO, ImGuiData.ListValues, labelsOf(candidates))
            ImGui.UpdateData(SEL_COMBO, ImGuiData.Value, 0)
        end
    end, "")

    ImGui.AddCombobox(TAB_EDIT, SEL_COMBO, "搜索结果", function(idx)
        local c = candidates[(idx or 0) + 1]
        if c then selectId(c.id) end
    end, { "（输入关键字）" }, 0)

    ImGui.AddCombobox(TAB_EDIT, OWNED_COMBO, "已获得道具", function(idx)
        local c = owned[(idx or 0) + 1]
        if c then selectId(c.id) end
    end, { "（进一局后可用）" }, 0)

    ImGui.AddText(TAB_EDIT, "", false, S_INFO)

    ImGui.AddSliderFloat(TAB_EDIT, S_RATING, "评级", function(_, val)
        if not curId then return end
        deps.rating.set(curId, tonumber(val), nil, nil)
        refreshInfo()
    end, 0.0, 0.0, 4.0, "%.1f")

    ImGui.AddInputFloat(TAB_EDIT, S_WEIGHT, "权重倍数（1=不变, 0=不出）", function(_, val)
        if not curId then return end
        deps.rating.set(curId, nil, tonumber(val), nil)
        refreshInfo()
    end, 1.0, 0.1, 0.1, "%.2f")

    ImGui.AddCheckbox(TAB_EDIT, S_ON, "启用", function(checked)
        if not curId then return end
        deps.rating.set(curId, nil, nil, checked and true or false)
        refreshInfo()
    end, true)

    ImGui.AddButton(TAB_EDIT, "hlr_btn_clear", "删除此条（回退官方）", function()
        if not curId then return end
        deps.rating.clear(curId)
        pushValues()
        refreshInfo()
        if deps.onChanged then deps.onChanged() end
    end)

    -- ── 已修改页 ──
    ImGui.AddText(TAB_LIST, "（每次切到这一页时刷新）", false, "hlr_list_info")
    ImGui.AddCombobox(TAB_LIST, "hlr_list_combo", "覆盖条目", function(idx)
        local ids = deps.rating.list()
        local id = ids[(idx or 0) + 1]
        if id then
            curId = id
            pushValues()
            refreshInfo()
        end
    end, { "（无）" }, 0)

    READY = true
end

-- ── 对外 ────────────────────────────────────────────────────────────────────

function E.init(d)
    deps = d
    if READY then return true end
    if not ImGui or not ImGui.CreateWindow then return false end
    local ok = pcall(build)
    if not ok then
        READY = false
        if deps and deps.log then deps.log("[EDITOR] ImGui 建界面失败") end
        return false
    end
    ImGui.SetVisible(WIN, false)
    return true
end

function E.isReady() return READY end

--- 每次打开时刷新"已获得"和其他下拉
function E.refresh()
    if not READY then return end
    buildOwned()
    ImGui.UpdateData(OWNED_COMBO, ImGuiData.ListValues, labelsOf(owned))
    ImGui.UpdateData(OWNED_COMBO, ImGuiData.Value, 0)

    local ids = deps.rating.list()
    local labels = {}
    for i = 1, #ids do
        local e = deps.rating.entries[ids[i]]
        labels[i] = string.format("%d  %s  q=%.1f w=%.2f%s",
            ids[i], itemNameCN(ids[i]), e.q or 0, e.w or 1, (e and e.on == false) and "（停用）" or "")
    end
    if #labels == 0 then labels[1] = "（还没有任何覆盖）" end
    ImGui.UpdateData("hlr_list_combo", ImGuiData.ListValues, labels)
    ImGui.UpdateData("hlr_list_combo", ImGuiData.Value, 0)
    ImGui.UpdateText("hlr_list_info", string.format("共 %d 条覆盖", #ids))

    refreshInfo()
end

function E.toggle()
    if not READY then return false end
    opened = not opened
    ImGui.SetVisible(WIN, opened)
    if opened then
        E.refresh()
        pcall(function() ImGui.Show() end)
    end
    return opened
end

function E.close()
    if not READY then return end
    opened = false
    pcall(function() ImGui.SetVisible(WIN, false) end)
end

return E
