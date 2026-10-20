-- ============================================================================
-- ui/config.lua —— ImGui 配置界面（空壳）
--
-- REPENTOGON 内置了 ImGui 全局，不需要任何额外 mod。
-- 这里只验证"能挂上菜单 + 打开窗口"，配置项后续再加。
-- 参考：mods\benighted soul_3290493485\ibs_scripts\ibs_imgui.lua
-- ============================================================================
local config = {}

local MENU = "highlight_review_menu"
local ITEM = "highlight_review_settings"
local WIN  = "highlight_review_window"
local READY = false

--- 返回是否成功挂上（ImGui 不存在时静默返回 false）
function config.init(deps)
    if READY then return true end
    if not ImGui then return false end
    if not (ImGui.CreateMenu and ImGui.AddElement and ImGui.CreateWindow) then return false end

    local ok = pcall(function()
        ImGui.CreateMenu(MENU, "Highlight Review")
        ImGui.AddElement(MENU, ITEM, ImGuiElement.MenuItem, "Settings")
        ImGui.CreateWindow(WIN, "Highlight Review · Settings")
        ImGui.LinkWindowToElement(WIN, ITEM)
        ImGui.AddText(WIN, "placeholder: thresholds / topN / display toggles")
    end)

    if ok then
        READY = true
        return true
    end
    return false
end

config.isReady = function() return READY end

return config
