-- ============================================================================
-- ui/lang.lua —— Item Weight Editor 的中英文案
--
-- 语言存在 settings 的 lang 键（"zh" / "en"），局外可解析：
--   C={"f6":295,"lang":"en"}
--
-- 只有**权重 mod** 做双语；Highlight Review 保持中文。
-- ============================================================================
local L = {}

--- 语言状态放在 _G 上：main / editor / config 三处各 include 一次这个文件，
--- 如果状态是本模块的 local，init() 只改到其中一份，另外两份还是默认 zh。
--- （实测就是这样：标题变了、标签没变。）
local STATE = rawget(_G, "IWE_LANG_STATE")
if not STATE then
    STATE = { code = "zh" }
    rawset(_G, "IWE_LANG_STATE", STATE)
end
L._state = STATE

local STR = {
    zh = {
        -- 窗口
        win_title       = "Item Weight Editor · 道具权重编辑器",
        tab_edit        = "编辑",
        tab_list        = "已修改",

        -- 三个入口
        search_label    = "搜索（数字按 id，字母按英文名）",
        result_label    = "搜索结果",
        result_hint     = "（输入关键字）",
        result_empty    = "（无结果）",
        owned_label     = "已获得道具",
        owned_empty     = "（还没有道具）",
        edited_label    = "已修改",
        edited_empty    = "（还没有修改）",

        -- 详情
        info_none       = "先在下面选一个道具",
        info_official   = "官方",
        info_rating     = "评级",
        info_weight     = "权重",
        info_unset      = "未设置",
        info_up_warn    = "权重 > 1 暂不生效（v1 只能降低出现率）",

        -- 输入
        rating_label    = "评级（0.00 ~ 4.99）",
        weight_label    = "权重（0 不出 / 1 不变 / >1 暂不生效）",

        -- 按钮
        btn_save        = "保存修改",
        btn_save_dirty  = "保存修改 *",
        btn_disable     = "停用此条",
        btn_enable      = "启用此条",
        btn_delete      = "删除此条（回退官方）",

        -- 已修改页
        list_empty      = "还没有任何修改。",

        -- 设置
        menu_name       = "Item Weight",
        menu_settings   = "设置",
        menu_editor     = "道具权重编辑器",
        set_title       = "Item Weight · 设置",
        set_hotkey_hint = "热键（点右边的框，再按你想绑的键）",
        set_open_editor = "打开编辑器",
        set_lang_label  = "语言 / Language",
        set_lang_note   = "切换后立即生效",
        set_current     = "当前：打开编辑器 = ",
    },
    en = {
        win_title       = "Item Weight Editor",
        tab_edit        = "Edit",
        tab_list        = "Modified",

        search_label    = "Search (id or name)",
        result_label    = "Results",
        result_hint     = "(search)",
        result_empty    = "(no match)",
        owned_label     = "Owned",
        owned_empty     = "(none)",
        edited_label    = "Modified",
        edited_empty    = "(nothing yet)",

        info_none       = "Pick an item below",
        info_official   = "vanilla",
        info_rating     = "Rating",
        info_weight     = "Weight",
        info_unset      = "not set",
        info_up_warn    = "Weight > 1: not supported yet",

        rating_label    = "Rating 0-4.99",
        weight_label    = "Weight 0-1",

        btn_save        = "Save",
        btn_save_dirty  = "Save *",
        btn_disable     = "Disable",
        btn_enable      = "Enable",
        btn_delete      = "Delete (vanilla)",

        list_empty      = "Nothing modified yet.",

        menu_name       = "Item Weight",
        menu_settings   = "Settings",
        menu_editor     = "Weight Editor",
        set_title       = "Item Weight - Settings",
        set_hotkey_hint = "Hotkey (click the box, then press the key)",
        set_open_editor = "Open editor",
        set_lang_label  = "Language / 语言",
        set_lang_note   = "Applied immediately",
        set_current     = "Current: open editor = ",
    },
}

--- 当前语言代码
function L.code() return STATE.code end

--- 是否中文
function L.isZh() return STATE.code ~= "en" end

--- 按指定语言取词（不改全局状态；建双窗口时用）
function L.tFor(code, key)
    local set = STR[code] or STR.zh
    return set[key] or STR.zh[key] or tostring(key)
end

--- 取文案
function L.t(key)
    local set = STR[STATE.code] or STR.zh
    return set[key] or (STR.zh[key]) or tostring(key)
end

--- 切语言后提示（ImGui 窗口不能在运行时重建，需要重启游戏）
function L.needRestart()
    if STATE.code == "en" then
        return "Saved. Restart the game to apply."
    end
    return "已保存，重启游戏后生效"
end

--- 从 settings 读语言（settings 可为 nil，此时用中文）
function L.init(settings)
    local code = "zh"
    if settings then
        local ok, v = pcall(function() return settings.get("lang") end)
        if ok and type(v) == "string" then code = v end
    end
    STATE.code = (code == "en") and "en" or "zh"
end

--- 切换语言并写回 settings
--- 只改内存状态，不写盘（建窗口时临时切用）
function L.setCode(code)
    STATE.code = (code == "en") and "en" or "zh"
end

function L.set(settings, code)
    STATE.code = (code == "en") and "en" or "zh"
    if settings then
        local ok = pcall(function() settings.set("lang", STATE.code) end)
        return ok
    end
    return false
end

return L
