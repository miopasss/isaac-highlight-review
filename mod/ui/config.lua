-- ============================================================================
-- ui/config.lua —— ImGui 设置界面（热键等）
--
-- 菜单：Highlight Review → 设置 / 道具评级（两个入口同级）
-- 热键改动即时写盘（走 deps.onChanged → saveData）
--
-- 注意：ImGui 没有窗口尺寸查询 API，居中只能按 1600×900 估。
-- ============================================================================
local config = {}

local MENU = "highlight_review_menu"
local ITEM = "highlight_review_settings_item"
local WIN  = "highlight_review_window"

local K_F5 = "hlr_key_f5"
local K_F6 = "hlr_key_f6"
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
        ImGui.UpdateData(K_F6, ImGuiData.Value, deps.settings.get("f6"))
        ImGui.UpdateText(T_TIP, string.format("当前：打开册子 = %s     道具评级 = %s",
            keyName(deps.settings.get("f5")),
            keyName(deps.settings.get("f6"))))
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
        -- 菜单（ui/rating_editor.lua 会往同一个菜单里加"道具评级"）
        pcall(function() ImGui.CreateMenu(MENU, "Highlight Review") end)
        ImGui.AddElement(MENU, ITEM, ImGuiElement.MenuItem, "设置")

        ImGui.CreateWindow(WIN, "Highlight Review · 设置")
        if ImGui.SetWindowSize then ImGui.SetWindowSize(WIN, 560, 260) end
        if ImGui.SetWindowPosition then ImGui.SetWindowPosition(WIN, 520, 300) end
        ImGui.LinkWindowToElement(WIN, ITEM)

        ImGui.AddText(WIN, "热键（点右边的框再按你想绑的键）", false, T_TIP)
        ImGui.AddInputKeyboard(WIN, K_F5, "打开册子", function(a, b)
            local v = tonumber(b) or tonumber(a)
            if v and deps.settings then deps.settings.set("f5", v); changed() end
        end, deps.settings and deps.settings.get("f5") or 294)

        ImGui.AddInputKeyboard(WIN, K_F6, "道具评级", function(a, b)
            local v = tonumber(b) or tonumber(a)
            if v and deps.settings then deps.settings.set("f6", v); changed() end
        end, deps.settings and deps.settings.get("f6") or 295)

        ImGui.AddText(WIN, "")
    end)

    if ok then
        READY = true
        pushValues()
        return true
    end
    return false
end

function config.isReady() return READY end
function config.pushValues() if READY then pushValues() end end

return config
