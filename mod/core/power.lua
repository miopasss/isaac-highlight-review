-- ============================================================================
-- power.lua —— 战力纯函数（不碰游戏 API，输入是快照表，可离线测）
--
-- 核心原则（DESIGN.md §3.1）：战力 = 纯函数，无副作用，随时可算。
-- 面板 player.Damage 已经是 √ 曲线之后的值，**不要**再过一遍曲线。
--
-- s = {
--   damage       = 5.19,   -- 面板伤害
--   maxFireDelay = 10,     -- 帧数
--   multiShot    = 1,      -- 每发弹幕数（GetNumTears）
--   form         = "tears",-- 攻击形态
--   chargeFactor = 1.0,    -- 蓄力系数（仅 techx / choco 用）
-- }
-- ============================================================================
local power = {}

power.FORMS = {
    tears     = "普通泪弹",
    brimstone = "Brimstone",
    ludovico  = "Ludovico",
    techx     = "Tech X",
    choco     = "巧克力牛奶",
    tech      = "Technology",
}

--- 攻速（次/秒）。MaxFireDelay 是帧数，30fps。
function power.shotsPerSecond(maxFireDelay)
    local d = maxFireDelay
    if type(d) ~= "number" or d ~= d then d = 10 end
    if d < 0 then d = 0 end
    if d > 120 then d = 120 end
    return 30 / (d + 1)
end

local function clamp(v, lo, hi)
    if type(v) ~= "number" or v ~= v then return lo end
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

--- 输出战力（等效 DPS）。返回 number, 说明string
function power.output(s)
    if type(s) ~= "table" then return 0, "no-stats" end
    local dmg = clamp(tonumber(s.damage) or 0, 0, 1e6)
    local rate = power.shotsPerSecond(s.maxFireDelay)
    local multi = clamp(tonumber(s.multiShot) or 1, 1, 64)
    local form = s.form or "tears"

    if form == "brimstone" then
        -- 每 4 帧一跳；持续时 DPT = Damage × FireRate / 5（wiki 已查证）
        return dmg * rate / 5, "brimstone"
    elseif form == "ludovico" then
        -- 每秒 15 跳，完全不吃攻速
        return dmg * 15, "ludovico"
    elseif form == "techx" then
        -- 每秒 15 跳，伤害是面板的 25%~100%（随充能）
        return dmg * 15 * clamp(tonumber(s.chargeFactor) or 1, 0.25, 1.0), "techx"
    elseif form == "choco" then
        -- 近似：满蓄力 400%（待标定）
        return dmg * 4 * rate, "choco"
    elseif form == "tech" then
        -- 待标定：暂按 1/3 伤害 × 每秒 ~4 跳
        return dmg * 4 / 3, "tech"
    end

    -- 普通泪弹
    return dmg * rate * multi, "tears"
end

--- 生存值（半心为单位）。
--- @param parts table { red=number, soul=number, bone=number }
--- v1 口径：红心容器 + 魂心/黑心 + 骨心（骨心按 2 半心/颗）
function power.survival(parts)
    if type(parts) ~= "table" then return 0 end
    local red = clamp(tonumber(parts.red) or 0, 0, 999)
    local soul = clamp(tonumber(parts.soul) or 0, 0, 999)
    local bone = clamp(tonumber(parts.bone) or 0, 0, 99)
    return red + soul + bone * 2
end

return power
