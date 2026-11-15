-- ============================================================================
-- idmap.lua —— 道具 id ↔ 内部名 的双向索引（评级配置抗 mod 漂移的地基）
--
-- 为什么不用 Isaac.GetItemIdByName：
--   ① 它只认 items.xml 里的 name；有些道具（尤其原版）的 ItemConfig.Name 是
--      "#BRIMSTONE_NAME" 这种本地化 key，喂回去查不到 → 漂移时静默失败。
--   ② 我们要的是"和写盘时同一套名字"。写盘用的是 ItemConfig.Name，
--      查回来也用 ItemConfig.Name，两边自洽，不依赖引擎的反查实现。
--
-- 归一化：去掉开头的 #、结尾的 _NAME、转小写、去首尾空格。
--   "Brimstone" / "#BRIMSTONE_NAME" / "brimstone" 视为同一个键。
--
-- 懒加载：第一次用到才扫 ItemConfig（约 2800 次 C 调用，一次性几毫秒）。
-- ============================================================================
local M = {}

-- 原版到 ~732；实测作者档里 mod 道具最远到 ~2600，留点余量
M.SCAN_MAX = 2800

M.ready  = false
M.byId   = nil   -- [id]   = 原始名（ItemConfig.Name）
M.byName = nil   -- [norm] = id（同名取第一个）

local function norm(s)
    s = tostring(s or "")
    s = s:lower()
    s = s:gsub("^#", "")
    s = s:gsub("_name$", "")
    s = s:gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    return s
end
M.norm = norm

function M.invalidate()
    M.ready, M.byId, M.byName = false, nil, nil
end

function M.build()
    if M.ready then return M end
    M.byId, M.byName = {}, {}

    local ok, cfgRoot = pcall(function() return Isaac.GetItemConfig() end)
    if not ok or not cfgRoot then
        -- 离线单测/接口缺失：标记 ready，但两个表都是空的
        M.ready = true
        return M
    end

    for id = 1, M.SCAN_MAX do
        local ok2, cfg = pcall(function() return cfgRoot:GetCollectible(id) end)
        local nm = ok2 and cfg and cfg.Name
        if type(nm) == "string" and nm ~= "" then
            M.byId[id] = nm
            local k = norm(nm)
            if k ~= "" and M.byName[k] == nil then M.byName[k] = id end
        end
    end
    M.ready = true
    return M
end

--- id → 名字（拿不到返回 nil）
function M.nameOf(id)
    M.build()
    if type(id) ~= "number" then return nil end
    return M.byId[id]
end

--- 名字 → 当前 id（拿不到返回 nil）
function M.idOf(name)
    M.build()
    if type(name) ~= "string" or name == "" then return nil end
    local direct = M.byName[norm(name)]
    if direct then return direct end
    return nil
end

--- 自检：返回 true, 说明
function M.selftest()
    local saved = { ready = M.ready, byId = M.byId, byName = M.byName }
    M.byId = { [1] = "The Sad Onion", [118] = "#BRIMSTONE_NAME" }
    M.byName = { ["the sad onion"] = 1, ["brimstone"] = 118 }
    M.ready = true

    local ok1 = (M.idOf("Brimstone") == 118 and M.idOf("#BRIMSTONE_NAME") == 118)
    local ok2 = (M.nameOf(1) == "The Sad Onion")
    local ok3 = (M.idOf("不存在的东西") == nil)

    M.ready, M.byId, M.byName = saved.ready, saved.byId, saved.byName
    return (ok1 and ok2 and ok3), string.format("brimstone=%s sad=%s miss=%s",
        tostring(ok1), tostring(ok2), tostring(ok3))
end

return M
