-- ============================================================================
-- ui/rating_editor.lua —— 道具权重编辑器（ImGui + 鼠标）
--
-- 入口：F6 热键 + ImGui 菜单「Item Weight → 设置」，两个入口共用同一开关状态
-- 双语：所有文案走 ui/lang.lua，切语言后 rebuild() 重建窗口
--
-- 实测限制（不是猜测，是跑出来的）：
--   · 没有 ImGui.SetSize（要用 SetWindowSize / SetWindowPosition）
--   · 没有 AddImage / AddChild / ListBox / AddSeparator / AddTextWrapped
--   · ImGui.Show() 会接管键盘，关闭时要 Hide()
--   · 控件回调参数个数不统一 → pickNum 兼容
-- ============================================================================
local E = {}
local floor = math.floor

local lang = nil
do
    local ok, m = pcall(function() return include("ui.lang") end)
    if ok then lang = m end
end
local function T(k)
    if lang then return lang.t(k) end
    return tostring(k)
end

local MENU      = "item_weight_menu"
local MENU_ITEM = "iwe_menu_editor"
local WIN       = "iwe_editor_win"
local TAB_EDIT  = "iwe_tab_edit"
local TAB_LIST  = "iwe_tab_list"

local C_SEARCH = "iwe_search"
local C_RESULT = "iwe_result"
local C_OWNED  = "iwe_owned"
local C_EDITED = "iwe_edited"
local S_INFO   = "iwe_info"
local S_RATING = "iwe_rating"
local S_WEIGHT = "iwe_weight"
local B_SAVE   = "iwe_btn_save"
local B_ENABLE = "iwe_btn_enable"
local B_DELETE = "iwe_btn_delete"
local S_LIST   = "iwe_list_text"

local READY  = false
local opened = false
local deps   = nil
local curId  = nil
local dirty  = false
local lastVisible = false

local searchResults = {}
local ownedList     = {}
local editedList    = {}

-- ── 小工具 ──────────────────────────────────────────────────────────────────

local function pickNum(a, b)
    local v = tonumber(b)
    if v then return v end
    return tonumber(a)
end

local function pickIndex(a, b)
    local v = pickNum(a, b)
    if not v then return 0 end
    return floor(v)
end

local function titleCase(s)
    s = s:gsub("^#", ""):gsub("_NAME$", ""):gsub("_", " ")
    return (s:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b:lower() end))
end

--- 道具英文名（去掉未本地化 key 的前后缀）
local function rawName(id)
    local ok, cfg = pcall(function() return Isaac.GetItemConfig():GetCollectible(id) end)
    if ok and cfg and cfg.Name then return titleCase(tostring(cfg.Name)) end
    return "?"
end

--- 显示名：中文模式优先本地化，英文模式一律英文名
local function shownName(id)
    if lang and lang.isZh() then
        local ok, s = pcall(function()
            local cfg = Isaac.GetItemConfig():GetCollectible(id)
            if cfg and cfg.Localized and cfg.Localized ~= "" then return cfg.Localized end
        end)
        if ok and s then return s end
    end
    return rawName(id)
end

local function officialQuality(id)
    local ok, q = pcall(function()
        local cfg = Isaac.GetItemConfig():GetCollectible(id)
        return cfg and cfg.Quality
    end)
    if ok and type(q) == "number" then return q end
    return -1
end

--- 当前持有的道具 id
local function heldIds()
    local out = {}
    local p = deps and deps.getPlayer and deps.getPlayer()
    if not p then return out end
    local ok, list = pcall(function() return p:GetCollectiblesList() end)
    if not ok or type(list) ~= "table" then return out end
    for id, count in pairs(list) do
        local n = tonumber(count) or 0
        if type(id) == "number" and id > 0 and n > 0 then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

local function label(id)
    return string.format("%d  %s", id, shownName(id))
end

local function listLabels(items, emptyText)
    local out = {}
    for i = 1, #items do out[i] = items[i].label end
    if #out == 0 then out[1] = emptyText end
    return out
end

-- ── 搜索 ────────────────────────────────────────────────────────────────────

local function doSearch(text)
    searchResults = {}
    local q = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if q == "" then return end

    local isNumeric = q:match("^%d+$") ~= nil
    local asId = isNumeric and tonumber(q) or nil
    local limit = 40

    if isNumeric then
        if asId and asId > 0 then
            searchResults[#searchResults + 1] = { id = asId, label = label(asId) }
        end
        for id = 1, 1800 do
            if #searchResults >= limit then break end
            if id ~= asId and tostring(id):sub(1, #q) == q then
                searchResults[#searchResults + 1] = { id = id, label = label(id) }
            end
        end
        return
    end

    for id = 1, 1800 do
        if #searchResults >= limit then break end
        local en = rawName(id):lower()
        local cn = shownName(id):lower()
        if en:find(q, 1, true) or cn:find(q, 1, true) then
            searchResults[#searchResults + 1] = { id = id, label = label(id) }
        end
    end
end

-- ── 详情与列表 ──────────────────────────────────────────────────────────────

local function refreshSaveBtn()
    if not B_SAVE or not ImGui.UpdateText then return end
    pcall(function()
        ImGui.UpdateText(B_SAVE, dirty and T("btn_save_dirty") or T("btn_save"))
    end)
end

local function refreshInfo()
    if not S_INFO then return end
    if not curId then
        pcall(function() ImGui.UpdateText(S_INFO, T("info_none")) end)
        return
    end
    local r = deps.rating
    local q = r.getRating(curId)
    local w = r.getWeightMul(curId)
    local lines = {
        string.format("%s    %s %s", label(curId), T("info_official"), tostring(officialQuality(curId))),
        string.format("%s %s     %s %s",
            T("info_rating"), q and string.format("%.2f", q) or T("info_unset"),
            T("info_weight"), w and string.format("%.2f", w) or T("info_unset")),
    }
    if w and w > 1.0 then lines[#lines + 1] = T("info_up_warn") end
    pcall(function() ImGui.UpdateText(S_INFO, table.concat(lines, "\n")) end)
end

local function pushValues()
    if not curId then return end
    local r = deps.rating
    local e = r.entries[curId]
    local q = r.getRating(curId)
    local w = r.getWeightMul(curId)
    local on = not (e and e.on == false)
    pcall(function()
        ImGui.UpdateData(S_RATING, ImGuiData.Value, q or math.max(0, officialQuality(curId)))
        ImGui.UpdateData(S_WEIGHT, ImGuiData.Value, w or 1.0)
        if ImGui.UpdateText then
            ImGui.UpdateText(B_ENABLE, on and T("btn_disable") or T("btn_enable"))
        end
    end)
    refreshSaveBtn()
end

local function selectId(id)
    if not id or id <= 0 then return end
    curId = id
    pushValues()
    refreshInfo()
end

local function refreshLists()
    local ids = heldIds()
    ownedList = {}
    for i = 1, #ids do ownedList[i] = { id = ids[i], label = label(ids[i]) } end
    pcall(function()
        ImGui.UpdateData(C_OWNED, ImGuiData.ListValues, listLabels(ownedList, T("owned_empty")))
        ImGui.UpdateData(C_OWNED, ImGuiData.Value, 0)
    end)

    local edited = deps.rating.list()
    editedList = {}
    local textLines = {}
    for i = 1, #edited do
        local id = edited[i]
        local e = deps.rating.entries[id]
        local tag = ""
        if e.on == false then
            tag = (lang and lang.isZh()) and "   （停用）" or "   (disabled)"
        end
        local line = string.format("%s   %s %.2f   %s %.2f%s",
            label(id), T("info_rating"), e.q or 0, T("info_weight"), e.w or 1, tag)
        editedList[i] = { id = id, label = line }
        textLines[i] = line
    end
    pcall(function()
        ImGui.UpdateData(C_EDITED, ImGuiData.ListValues, listLabels(editedList, T("edited_empty")))
        ImGui.UpdateData(C_EDITED, ImGuiData.Value, 0)
    end)

    if #textLines == 0 then textLines[1] = T("list_empty") end
    pcall(function() ImGui.UpdateText(S_LIST, table.concat(textLines, "\n")) end)
end

-- ── 建界面 ──────────────────────────────────────────────────────────────────

local function tryStep(name, fn)
    local ok, err = pcall(fn)
    if not ok and deps and deps.log then
        deps.log("[EDITOR] " .. name .. " failed: " .. tostring(err))
    end
    return ok
end

local function buildUI()
    tryStep("CreateWindow", function()
        ImGui.CreateWindow(WIN, T("win_title"))
        if ImGui.SetWindowSize then ImGui.SetWindowSize(WIN, 620, 560) end
        if ImGui.SetWindowPosition then ImGui.SetWindowPosition(WIN, 490, 170) end
    end)

    tryStep("menu", function()
        if not ImGui.CreateMenu then return end
        pcall(function() ImGui.CreateMenu(MENU, T("menu_name")) end)
        ImGui.AddElement(MENU, MENU_ITEM, ImGuiElement.MenuItem, T("menu_settings"))
        if ImGui.LinkWindowToElement then ImGui.LinkWindowToElement(WIN, MENU_ITEM) end
    end)

    tryStep("TabBar", function()
        ImGui.AddTabBar(WIN, "iwe_tabbar")
        ImGui.AddTab("iwe_tabbar", TAB_EDIT, T("tab_edit"))
        ImGui.AddTab("iwe_tabbar", TAB_LIST, T("tab_list"))
    end)

    tryStep("search", function()
        ImGui.AddInputText(TAB_EDIT, C_SEARCH, T("search_label"), function(a, b)
            local text = (type(b) == "string") and b or tostring(a or "")
            doSearch(text)
            if #searchResults > 0 then
                ImGui.UpdateData(C_RESULT, ImGuiData.ListValues, listLabels(searchResults, T("result_empty")))
                ImGui.UpdateData(C_RESULT, ImGuiData.Value, 0)
                -- 搜索出结果就自动选中第一个
                if searchResults[1] then selectId(searchResults[1].id) end
            end
        end, "")
    end)

    tryStep("result", function()
        ImGui.AddCombobox(TAB_EDIT, C_RESULT, T("result_label"), function(a, b)
            local c = searchResults[pickIndex(a, b) + 1]
            if c then selectId(c.id) end
        end, { T("result_hint") }, 0)
    end)

    tryStep("owned", function()
        ImGui.AddCombobox(TAB_EDIT, C_OWNED, T("owned_label"), function(a, b)
            local c = ownedList[pickIndex(a, b) + 1]
            if c then selectId(c.id) end
        end, { T("owned_empty") }, 0)
    end)

    tryStep("edited", function()
        ImGui.AddCombobox(TAB_EDIT, C_EDITED, T("edited_label"), function(a, b)
            local c = editedList[pickIndex(a, b) + 1]
            if c then selectId(c.id) end
        end, { T("edited_empty") }, 0)
    end)

    tryStep("info", function() ImGui.AddText(TAB_EDIT, "", false, S_INFO) end)

    tryStep("rating", function()
        ImGui.AddInputFloat(TAB_EDIT, S_RATING, T("rating_label"), function(a, b)
            local v = pickNum(a, b)
            if not curId or not v then return end
            if v < 0 then v = 0 elseif v > 4.99 then v = 4.99 end
            deps.rating.set(curId, v, nil, nil)
            dirty = true
            pushValues(); refreshInfo(); refreshLists()
        end, 0.0, 0.01, 0.05, "%.2f")
    end)

    tryStep("weight", function()
        ImGui.AddInputFloat(TAB_EDIT, S_WEIGHT, T("weight_label"), function(a, b)
            local v = pickNum(a, b)
            if not curId or not v then return end
            if v < 0 then v = 0 elseif v > 5 then v = 5 end
            deps.rating.set(curId, nil, v, nil)
            dirty = true
            pushValues(); refreshInfo(); refreshLists()
        end, 1.0, 0.05, 0.1, "%.2f")
    end)

    tryStep("save", function()
        ImGui.AddButton(TAB_EDIT, B_SAVE, T("btn_save"), function()
            if deps.onChanged then deps.onChanged() end
            dirty = false
            refreshSaveBtn()
            refreshLists()
            if deps.log then
                deps.log(string.format("[EDITOR] saved, %d entries", deps.rating.count()))
            end
        end)
    end)

    tryStep("enable", function()
        ImGui.AddButton(TAB_EDIT, B_ENABLE, T("btn_disable"), function()
            if not curId then return end
            local e = deps.rating.entries[curId]
            local on = not (e and e.on == false)
            deps.rating.set(curId, nil, nil, not on)
            pushValues(); refreshInfo(); refreshLists()
            if deps.onChanged then deps.onChanged() end
        end)
    end)

    tryStep("delete", function()
        ImGui.AddButton(TAB_EDIT, B_DELETE, T("btn_delete"), function()
            if not curId then return end
            deps.rating.clear(curId)
            pushValues(); refreshInfo(); refreshLists()
            if deps.onChanged then deps.onChanged() end
        end)
    end)

    tryStep("list page", function()
        ImGui.AddText(TAB_LIST, "", true, S_LIST)
    end)

    READY = true
end

-- ── 对外 ────────────────────────────────────────────────────────────────────

function E.init(d)
    deps = d
    if READY then return true end
    if not ImGui or not ImGui.CreateWindow then return false end
    local ok, err = pcall(buildUI)
    if not ok then
        if deps and deps.log then deps.log("[EDITOR] build failed: " .. tostring(err)) end
        READY = false
        return false
    end
    pcall(function() ImGui.SetVisible(WIN, false) end)
    return READY
end

--- 切语言后重建窗口（ImGui 的控件标签只能在创建时给定）
function E.rebuild()
    if not deps then return false end
    local wasOpen = opened
    READY = false
    pcall(function()
        if ImGui.RemoveWindow then ImGui.RemoveWindow(WIN) end
    end)
    local ok = pcall(buildUI)
    pcall(function() ImGui.SetVisible(WIN, wasOpen) end)
    opened = wasOpen
    if ok and READY then
        refreshLists()
        refreshInfo()
        pushValues()
    end
    return READY
end

function E.isReady() return READY end
function E.isOpen() return opened end

function E.refresh()
    if not READY then return end
    refreshLists()
    refreshInfo()
end

function E.toggle()
    if not READY then return false end
    opened = not opened
    pcall(function() ImGui.SetVisible(WIN, opened) end)
    if opened then
        E.refresh()
        pcall(function() ImGui.Show() end)
        if deps and deps.log then deps.log("[EDITOR] open") end
    else
        pcall(function() ImGui.Hide() end)
        if deps and deps.log then deps.log("[EDITOR] close") end
    end
    return opened
end

function E.open()
    if not READY or opened then return end
    E.toggle()
end

function E.close()
    if not READY then return end
    opened = false
    pcall(function() ImGui.SetVisible(WIN, false) end)
    pcall(function() ImGui.Hide() end)
end

--- 每帧调用：窗口从"不可见"变"可见"时刷一次列表
function E.watch()
    if not READY then return end
    local vis = false
    pcall(function() vis = ImGui.IsVisible(WIN) end)
    if vis and not lastVisible then
        opened = true
        E.refresh()
    elseif not vis then
        opened = false
    end
    lastVisible = vis
end

return E
