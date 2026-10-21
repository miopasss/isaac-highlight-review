-- ============================================================================
-- ui/config.lua —— Highlight Review 的设置界面（只有册子热键）
--
-- 菜单：Highlight Review → 设置
-- 热键改动即时写盘（走 deps.onChanged）
--
-- 注意：ImGui 没有窗口尺寸查询 API，居中只能按 1600×900 估。
-- ============================================================================
local config = {}

local MENU = "highlight_review_menu"
local ITEM = "highlight_review_settings_item"
local WIN  = "highlight_review_window"

local K_F5 = "hlr_key_f5"
local T_TIP = "hlr_key_tip"

local READY = false
local deps  = nil

local function keyName(k)
    local ok, s = pcall(function()
        for name, v in pairs(Keyboard) do
            if type(v) == "number" and v == k then return tostring(name) end
        end
    end)
    if ok and s then return s end
    return tostring(k)
end

local function pushValues()
    if not deps or not deps.settings then return end
    pcall(function()
        ImGui.UpdateData(K_F5, ImGuiData.Value, deps.settings.get("f5"))
        ImGui.UpdateText(T_TIP, "当前：打开册子 = " .. keyName(deps.settings.get("f5")))
    end)
end

local function changed()
    if deps and deps.onChanged then deps.onChanged() end
    pushValues()
end

function config.init(d)
    deps = d or {}
    if READY then return true end
    if not ImGui then return false end
    if not (ImGui.CreateMenu and ImGui.AddElement and ImGui.CreateWindow) then return false end

    local ok = pcall(function()
        pcall(function() ImGui.CreateMenu(MENU, "Highlight Review") end)
        ImGui.AddElement(MENU, ITEM, ImGuiElement.MenuItem, "设置")

        ImGui.CreateWindow(WIN, "Highlight Review · 设置")
        if ImGui.SetWindowSize then ImGui.SetWindowSize(WIN, 520, 220) end
        if ImGui.SetWindowPosition then ImGui.SetWindowPosition(WIN, 540, 330) end
        ImGui.LinkWindowToElement(WIN, ITEM)

        ImGui.AddText(WIN, "热键（点右边的框，再按你想绑的键）", false, T_TIP)
        ImGui.AddInputKeyboard(WIN, K_F5, "打开册子", function(a, b)
            local v = tonumber(b) or tonumber(a)
            if v and deps.settings then
                deps.settings.set("f5", v)
                changed()
            end
        end, deps.settings and deps.settings.get("f5") or 294)
    end)

    if ok then
        READY = true
        pushValues()
        return true
    end
    return false
end

function config.isReady() return READY end

return config
