-- ============================================================================
-- pills.lua —— 药丸效果 → 属性白名单（作者 2026-10-21 定的做法）
--
-- 为什么查表而不是"吃前吃后回读属性"：
--   回读会抓到临时/中间值，还会被「大药丸」「金药丸」这类倍数搞乱，
--   算出来的数字看着精确其实是错的。
--
-- 为什么只给**次数**不给**数值**：
--   同一颗药丸在不同状态下涨的绝对量不同（Tears Up 受当前攻速影响），
--   写成 "+0.15" 就是编数字。次数是确定的。
--
-- 枚举名来自 `PillEffect.PILLEFFECT_*`（别的 mod 也这么用），
-- 每个都做存在性检查 —— 版本不同、某些枚举没了也不会炸。
-- ============================================================================
local P = {}

--- stat 键：rg=射程 mv=移速 ts=攻速 lk=幸运 hp=红心容器
--- dir：1 上升 / -1 下降
local defs = {
    { "PILLEFFECT_RANGE_UP",   "rg",  1, "射程" },
    { "PILLEFFECT_RANGE_DOWN", "rg", -1, "射程" },
    { "PILLEFFECT_SPEED_UP",   "mv",  1, "移速" },
    { "PILLEFFECT_SPEED_DOWN", "mv", -1, "移速" },
    { "PILLEFFECT_TEARS_UP",   "ts",  1, "攻速" },
    { "PILLEFFECT_TEARS_DOWN", "ts", -1, "攻速" },
    { "PILLEFFECT_LUCK_UP",    "lk",  1, "幸运" },
    { "PILLEFFECT_LUCK_DOWN",  "lk", -1, "幸运" },
    { "PILLEFFECT_HEALTH_UP",  "hp",  1, "红心" },
    { "PILLEFFECT_HEALTH_DOWN", "hp", -1, "红心" },
}

--- effectId -> { stat, dir, name }；不在表里返回 nil
local MAP = {}

--- 建立映射（需要在游戏环境里调用；纯离线时会是空表）
function P.init()
    MAP = {}
    if type(PillEffect) ~= "table" then return 0 end
    local n = 0
    for i = 1, #defs do
        local d = defs[i]
        local id = PillEffect[d[1]]
        if type(id) == "number" then
            MAP[id] = { stat = d[2], dir = d[3], name = d[4] }
            n = n + 1
        end
    end
    return n
end

--- 查一颗药丸的影响；不在白名单返回 nil
function P.info(effectId)
    return MAP[tonumber(effectId) or -1]
end

--- 白名单条目数（诊断用）
function P.count()
    local n = 0
    for _ in pairs(MAP) do n = n + 1 end
    return n
end

P.STAT_ORDER = { "rg", "ts", "mv", "lk", "hp" }
P.STAT_NAME = {
    rg = { zh = "射程", en = "Range" },
    ts = { zh = "攻速", en = "Tears" },
    mv = { zh = "移速", en = "Speed" },
    lk = { zh = "幸运", en = "Luck" },
    hp = { zh = "红心", en = "HP" },
}

return P
