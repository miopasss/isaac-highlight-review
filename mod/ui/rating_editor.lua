-- ============================================================================
-- ui/rating_editor.lua —— 道具评级/权重编辑器（ImGui + 鼠标）
--
-- 入口：F6 热键 + ImGui 菜单「Highlight Review → 道具评级」，两个入口共用同一开关状态
--
-- 实测限制（不是猜测，是跑出来的）：
--   · 没有 ImGui.SetSize（要用 SetWindowSize / SetWindowPosition）
--   · 没有 AddImage / AddChild / ListBox / AddSeparator
--   · ImGui.Show() 会接管键盘，关闭时要 Hide()
--   · 控件回调参数个数不统一：有的给 (id, value)，有的只给 (value) → 用 pickNum 兼容
--   · 作者要求两位小数 → 评级和权重都用数字输入框，不用滑条
-- ============================================================================
local E = {}
local floor = math.floor

local MENU      = "highlight_review_menu"      -- 与 ui/config.lua 共用同一个菜单
local MENU_ITEM = "hlr_rating_menuitem"
local WIN       = "hlr_rating_win"
local TAB_EDIT  = "hlr_tab_edit"
local TAB_LIST  = "hlr_tab_list"

local C_SEARCH = "hlr_search"
local C_RESULT = "hlr_result"
local C_OWNED  = "hlr_owned"
local C_EDITED = "hlr_edited"
local S_INFO   = "hlr_info"
local S_RATING = "hlr_rating"
local S_WEIGHT = "hlr_weight"
local B_ENABLE = "hlr_btn_enable"
local B_DELETE = "hlr_btn_delete"
local S_LIST   = "hlr_list_text"

local READY  = false
local opened = false
local deps   = nil
local curId  = nil

local searchResults = {}
local ownedList     = {}
local editedList    = {}

-- ── 小工具 ──────────────────────────────────────────────────────────────────

--- 回调参数兼容：有的控件给 (id, value)，有的只给 (value)
local function pickNum(a, b)
    local v = tonumber(b)
    if v then return v end
    return tonumber(a)
end

--- 取整数下标（控件可能给 0 基或 1 基，这里统一按 0 基处理）
local function pickIndex(a, b)
    local v = pickNum(a, b)
    if not v then return 0 end
    return floor(v)
end

--- 道具英文名：去掉未本地化 key 的 # 前缀与 _NAME 后缀
local function rawName(id)
    local ok, cfg = pcall(function() return Isaac.GetItemConfig():GetCollectible(id) end)
    if ok and cfg and cfg.Name then
        local n = tostring(cfg.Name)
        n = n:gsub("^#", ""):gsub("_NAME$", ""):gsub("_", " ")
        n = n:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b:lower() end)
        return n
    end
    return "?"
end

--- 显示名：优先本地化（中文），否则英文
local function shownName(id)
    local ok, s = pcall(function()
        local cfg = Isaac.GetItemConfig():GetCollectible(id)
        if cfg and cfg.Localized and cfg.Localized ~= "" then return cfg.Localized end
    end)
    if ok and s then return s end
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

--- 当前持有的道具 id（兼容 GetCollectiblesList 返回数组或映射两种形状）
local function heldIds()
    local out = {}
    local p = deps and deps.getPlayer and deps.getPlayer()
    if not p then return out end
    local ok, list = pcall(function() return p:GetCollectiblesList() end)
    if not ok or type(list) ~= "table" then return out end

    -- 实测：GetCollectiblesList() 返回 { [道具id] = 持有数量 }，包含全部 1763 个道具，
    -- 数量为 0 表示没有。所以必须按数量过滤，不能把所有键都当成已获得。
    for id, count in pairs(list) do
        local n = tonumber(count) or 0
        if type(id) == "number" and id > 0 and n > 0 then
            out[#out + 1] = id
        end
    end
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

-- ── 详情与列表刷新 ──────────────────────────────────────────────────────────

local function refreshInfo()
    if not S_INFO then return end
    if not curId then
        pcall(function() ImGui.UpdateText(S_INFO, "先在下面选一个道具") end)
        return
    end
    local r = deps.rating
    local q = r.getRating(curId)
    local w = r.getWeightMul(curId)
    local lines = {
        string.format("%s    官方 %s", label(curId), tostring(officialQuality(curId))),
        string.format("评级 %s     权重 %s",
            q and string.format("%.2f", q) or "未设置",
            w and string.format("%.2f", w) or "未设置"),
    }
    if w and w > 1.0 then
        lines[#lines + 1] = "权重 > 1 暂不生效（v1 只能降低出现率）"
    end
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
            ImGui.UpdateText(B_ENABLE, on and "状态：启用（点击停用）" or "状态：停用（点击启用）")
        end
    end)
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
        ImGui.UpdateData(C_OWNED, ImGuiData.ListValues, listLabels(ownedList, "（还没有道具）"))
        ImGui.UpdateData(C_OWNED, ImGuiData.Value, 0)
    end)

    local edited = deps.rating.list()
    editedList = {}
    local textLines = {}
    for i = 1, #edited do
        local id = edited[i]
        local e = deps.rating.entries[id]
        local tag = (e.on == false) and "  （停用）" or ""
        editedList[i] = {
            id = id,
            label = string.format("%s   评级 %.2f   权重 %.2f%s", label(id), e.q or 0, e.w or 1, tag),
        }
        textLines[i] = string.format("%s   评级 %.2f   权重 %.2f%s", label(id), e.q or 0, e.w or 1, tag)
    end
    pcall(function()
        ImGui.UpdateData(C_EDITED, ImGuiData.ListValues, listLabels(editedList, "（还没有修改）"))
        ImGui.UpdateData(C_EDITED, ImGuiData.Value, 0)
    end)

    if #textLines == 0 then textLines[1] = "还没有任何修改。" end
    pcall(function() ImGui.UpdateText(S_LIST, table.concat(textLines, "\n")) end)
end

-- ── 建界面 ──────────────────────────────────────────────────────────────────

local function tryStep(name, fn)
    local ok, err = pcall(fn)
    if not ok and deps and deps.log then
        deps.log("[EDITOR] " .. name .. " 失败: " .. tostring(err))
    end
    return ok
end

local function build()
    tryStep("CreateWindow", function()
        ImGui.CreateWindow(WIN, "Highlight Review · 道具评级")
        if ImGui.SetWindowSize then ImGui.SetWindowSize(WIN, 620, 560) end
        if ImGui.SetWindowPosition then ImGui.SetWindowPosition(WIN, 490, 170) end
    end)

    tryStep("菜单入口", function()
        if not ImGui.CreateMenu then return end
        pcall(function() ImGui.CreateMenu(MENU, "Highlight Review") end)
        ImGui.AddElement(MENU, MENU_ITEM, ImGuiElement.MenuItem, "道具评级")
        if ImGui.LinkWindowToElement then ImGui.LinkWindowToElement(WIN, MENU_ITEM) end
    end)

    tryStep("TabBar", function()
        ImGui.AddTabBar(WIN, "hlr_tabbar")
        ImGui.AddTab("hlr_tabbar", TAB_EDIT, "编辑")
        ImGui.AddTab("hlr_tabbar", TAB_LIST, "已修改")
    end)

    tryStep("搜索框", function()
        ImGui.AddInputText(TAB_EDIT, C_SEARCH, "搜索（数字按 id，字母按英文名）", function(a, b)
            local text = (type(b) == "string") and b or tostring(a or "")
            doSearch(text)
            if #searchResults > 0 then
                ImGui.UpdateData(C_RESULT, ImGuiData.ListValues, listLabels(searchResults, "（无结果）"))
                ImGui.UpdateData(C_RESULT, ImGuiData.Value, 0)
            end
        end, "")
    end)

    tryStep("搜索结果", function()
        ImGui.AddCombobox(TAB_EDIT, C_RESULT, "搜索结果", function(a, b)
            local c = searchResults[pickIndex(a, b) + 1]
            if c then selectId(c.id) end
        end, { "（输入关键字）" }, 0)
    end)

    tryStep("已获得", function()
        ImGui.AddCombobox(TAB_EDIT, C_OWNED, "已获得道具", function(a, b)
            local c = ownedList[pickIndex(a, b) + 1]
            if c then selectId(c.id) end
        end, { "（还没有道具）" }, 0)
    end)

    tryStep("已修改", function()
        ImGui.AddCombobox(TAB_EDIT, C_EDITED, "已修改", function(a, b)
            local c = editedList[pickIndex(a, b) + 1]
            if c then selectId(c.id) end
        end, { "（还没有修改）" }, 0)
    end)

    tryStep("信息", function() ImGui.AddText(TAB_EDIT, "", false, S_INFO) end)

    tryStep("评级输入", function()
        ImGui.AddInputFloat(TAB_EDIT, S_RATING, "评级（0.00 ~ 4.99）", function(a, b)
            local v = pickNum(a, b)
            if not curId or not v then return end
            if v < 0 then v = 0 elseif v > 4.99 then v = 4.99 end
            deps.rating.set(curId, v, nil, nil)
            pushValues(); refreshInfo(); refreshLists()
        end, 0.0, 0.01, 0.05, "%.2f")
    end)

    tryStep("权重输入", function()
        ImGui.AddInputFloat(TAB_EDIT, S_WEIGHT, "权重（0 不出 / 1 不变 / >1 暂不生效）", function(a, b)
            local v = pickNum(a, b)
            if not curId or not v then return end
            if v < 0 then v = 0 elseif v > 5 then v = 5 end
            deps.rating.set(curId, nil, v, nil)
            pushValues(); refreshInfo(); refreshLists()
        end, 1.0, 0.05, 0.1, "%.2f")
    end)

    tryStep("启用按钮", function()
        ImGui.AddButton(TAB_EDIT, B_ENABLE, "状态：启用（点击停用）", function()
            if not curId then return end
            local e = deps.rating.entries[curId]
            local on = not (e and e.on == false)
            deps.rating.set(curId, nil, nil, not on)
            pushValues(); refreshInfo(); refreshLists()
            if deps.onChanged then deps.onChanged() end
        end)
    end)

    tryStep("删除按钮", function()
        ImGui.AddButton(TAB_EDIT, B_DELETE, "删除此条（回退官方）", function()
            if not curId then return end
            deps.rating.clear(curId)
            pushValues(); refreshInfo(); refreshLists()
            if deps.onChanged then deps.onChanged() end
        end)
    end)

    tryStep("已修改页", function()
        ImGui.AddText(TAB_LIST, "", true, S_LIST)
    end)

    READY = true
end

-- ── 对外 ────────────────────────────────────────────────────────────────────

function E.init(d)
    deps = d
    if READY then return true end
    if not ImGui or not ImGui.CreateWindow then return false end
    local ok, err = pcall(build)
    if not ok then
        if deps and deps.log then deps.log("[EDITOR] 建界面失败: " .. tostring(err)) end
        READY = false
        return false
    end
    pcall(function() ImGui.SetVisible(WIN, false) end)
    return READY
end

function E.isReady() return READY end
function E.isOpen() return opened end

--- 打开状态下由主循环每帧调用：低频刷新"已获得道具"
--- 为什么需要：列表只在打开时刷新，若在进局前打开就一直是空的
--- 每帧调用：窗口从"不可见"变成"可见"时刷一次列表。
--- 为什么需要：从菜单 Highlight Review → 道具评级 打开窗口时，不走 F6 那条路，
--- 列表就一直是空的（作者报的 bug）。这里用可见性变化来补刷新，不做周期刷新。
local lastVisible = false
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
        if deps and deps.log then deps.log("[EDITOR] 打开") end
    else
        pcall(function() ImGui.Hide() end)
        if deps and deps.log then deps.log("[EDITOR] 关闭") end
    end
    return opened
end

--- 菜单入口点击后也要能打开（状态与 F6 共用）
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

return E
