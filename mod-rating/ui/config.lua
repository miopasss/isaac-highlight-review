-- ============================================================================
-- ui/config.lua —— Item Weight Editor 的设置界面（只有热键）
--
-- 菜单：Item Weight → 设置 / 道具权重编辑器
-- 热键改动即时写盘（走 deps.onChanged）
-- ============================================================================
local config = {}

local MENU = "item_weight_menu"
local ITEM = "item_weight_settings_item"
local WIN  = "item_weight_settings_win"

local K_F6 = "iwe_key_f6"
local T_TIP = "iwe_key_tip"

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
        ImGui.UpdateData(K_F6, ImGuiData.Value, deps.settings.get("f6"))
        ImGui.UpdateText(T_TIP, "当前：打开编辑器 = " .. keyName(deps.settings.get("f6")))
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
        pcall(function() ImGui.CreateMenu(MENU, "Item Weight") end)
        ImGui.AddElement(MENU, ITEM, ImGuiElement.MenuItem, "设置")

        ImGui.CreateWindow(WIN, "Item Weight · 设置")
        if ImGui.SetWindowSize then ImGui.SetWindowSize(WIN, 520, 220) end
        if ImGui.SetWindowPosition then ImGui.SetWindowPosition(WIN, 540, 330) end
        ImGui.LinkWindowToElement(WIN, ITEM)

        ImGui.AddText(WIN, "热键（点右边的框，再按你想绑的键）", false, T_TIP)
        ImGui.AddInputKeyboard(WIN, K_F6, "打开编辑器", function(a, b)
            local v = tonumber(b) or tonumber(a)
            if v and deps.settings then
                deps.settings.set("f6", v)
                changed()
            end
        end, deps.settings and deps.settings.get("f6") or 295)
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
