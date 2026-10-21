-- ============================================================================
-- ui/config.lua —— Item Weight Editor 的设置界面（热键 + 语言）
--
-- 菜单：Item Weight → 设置 / Settings
-- 双语：文案走 ui/lang.lua；切换语言后自己和编辑器都会重建
-- ============================================================================
local config = {}

local lang = nil
do
    local ok, m = pcall(function() return include("ui.lang") end)
    if ok then lang = m end
end
local function T(k)
    if lang then return lang.t(k) end
    return tostring(k)
end

local MENU = "item_weight_menu"
local ITEM = "iwe_menu_settings"
local WIN  = "iwe_settings_win"

local K_F6  = "iwe_key_f6"
local T_TIP = "iwe_key_tip"
local B_ZH  = "iwe_lang_zh"
local B_EN  = "iwe_lang_en"
local T_LANG = "iwe_lang_label"

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
        ImGui.UpdateText(T_TIP, T("set_current") .. keyName(deps.settings.get("f6")))
        ImGui.UpdateText(T_LANG, T("set_lang_label"))
    end)
end

local function changed()
    if deps and deps.onChanged then deps.onChanged() end
    pushValues()
end

local switchLang

local function rebuildSelf()
    READY = false
    pcall(function() if ImGui.RemoveWindow then ImGui.RemoveWindow(WIN) end end)
    config.init(deps)
end

switchLang = function(code)
    if not lang then return end
    lang.set(deps and deps.settings, code)
    rebuildSelf()
    if deps and deps.onRebuildEditor then deps.onRebuildEditor() end
    if deps and deps.onChanged then deps.onChanged() end
end

function config.init(d)
    if d then deps = d end
    if READY then return true end
    if not ImGui then return false end
    if not (ImGui.CreateMenu and ImGui.AddElement and ImGui.CreateWindow) then return false end

    local ok = pcall(function()
        pcall(function() ImGui.CreateMenu(MENU, T("menu_name")) end)
        ImGui.AddElement(MENU, ITEM, ImGuiElement.MenuItem, T("menu_settings"))

        ImGui.CreateWindow(WIN, T("set_title"))
        if ImGui.SetWindowSize then ImGui.SetWindowSize(WIN, 540, 260) end
        if ImGui.SetWindowPosition then ImGui.SetWindowPosition(WIN, 530, 300) end
        ImGui.LinkWindowToElement(WIN, ITEM)

        ImGui.AddText(WIN, T("set_hotkey_hint"), false, T_TIP)
        ImGui.AddInputKeyboard(WIN, K_F6, T("set_open_editor"), function(a, b)
            local v = tonumber(b) or tonumber(a)
            if v and deps.settings then
                deps.settings.set("f6", v)
                changed()
            end
        end, deps.settings and deps.settings.get("f6") or 295)

        ImGui.AddText(WIN, T("set_lang_label"), false, T_LANG)
        ImGui.AddButton(WIN, B_ZH, "中文", function() switchLang("zh") end)
        ImGui.AddButton(WIN, B_EN, "English", function() switchLang("en") end)
        ImGui.AddText(WIN, T("set_lang_note"))
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
