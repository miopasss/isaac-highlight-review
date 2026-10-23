-- ============================================================================
-- power_forms.lua —— 特殊形态 + 倍数合成（纯函数，不碰游戏 API，可离线单测）
--
-- 口径（docs/special-attack-power.md）：
--     POWER = 射速 × 攻击力 × 倍数
--           = D × FR × 形态系数 × 道具乘区 × 宝宝倍数
--
-- 设计原则：
--   1) 只有"面板没体现"的形态才进 FORMS；A 类（三眼/四眼/20-20/豆浆/吐根…）走 tears。
--   2) 宝宝不当 DPS 累加，只当倍数：1 + Σbonus，再乘 Πmult（两个 +0.75 = 2.5×，不是 3.06×）。
--   3) 拿不准的系数都写在表里，改一个数就完事，不要改逻辑。
--
-- 入参 s（快照）：
--   damage, maxFireDelay     面板值（必填）
--   form                     形态 key（缺省 tears）
--   numTearsAvg              期望弹幕数（概率多发用期望，不要用单次采样）
--   chargeFill               蓄力完成度，缺省 TABLE.chargeFill
--   mult                     道具乘区（死眼 1.91 / 书虫 1.5 / 宝宝套 1.5）
--   family                   宝宝 key 列表 {"incubus","twisted_pair"}
--   luck                     幸运值；luckItems 为该局生效的幸运道具 key 列表
--   addDps                   附加固定 DPS（Tech.5 之类）
-- ============================================================================
local power_forms = {}

power_forms.chargeFill = 0.8       -- 蓄力默认折扣（作者已接受）

--- 攻速（次/秒）。MaxFireDelay 是帧数，30fps。
local function shotsPerSecond(delay)
    local d = tonumber(delay) or 10
    if d < 0 then d = 0 end
    if d > 120 then d = 120 end
    return 30 / (d + 1)
end
power_forms.shotsPerSecond = shotsPerSecond

-- ── 形态表 ──────────────────────────────────────────────────────────────
-- kind = rate      : D × hitMult × FR × n        （普通泪弹、科技、博士、灵剑）
-- kind = beam      : D × ticks × tickMult /(1/FR + beamSec)   （硫磺火）
-- kind = charge    : D × (mMin→mMax) × FR        （妈刀、巧克力牛奶）
-- kind = fixed     : D × hitMult / cycleSec      （史诗婴儿）
-- kind = contact   : D × FR × tickMult × duty    （Ludo）
-- kind = ring      : D × tickMult × ticksPerRing / chargeSec  （Tech X）
power_forms.FORMS = {
    tears      = { kind = "rate" },
    -- A 类全部走这里（面板已含）：三眼 2 / 四眼 153 / 20-20 245 / 豆浆 330
    --                        杏仁奶 561 / 吐根 149 / 肿肺 229

    brimstone  = { kind = "beam", ticks = 9, tickMult = 1.0, beamSec = 0.63 },   -- 118
    momsknife  = { kind = "charge", mMin = 2.0, mMax = 6.0 },                    -- 114
    chocomilk  = { kind = "charge", mMin = 0.1, mMax = 4.0 },                    -- 69
    drfetus    = { kind = "rate", hitMult = 10.0 },                              -- 52
    epicfetus  = { kind = "fixed", hitMult = 20.0, cycleSec = 1.5 },             -- 168
    ludovico   = { kind = "contact", tickMult = 1.0, duty = 1.0 },               -- 329
    technology = { kind = "rate" },                                              -- 68
    techx      = { kind = "ring", ticksPerRing = 7, chargeSec = 1.03, tickMult = 0.85 }, -- 395
    spirsword  = { kind = "rate", hitMult = 3.0, flat = 3.5 },                   -- 579
}

-- ── 宝宝：只当倍数 ──────────────────────────────────────────────────────
-- bonus = 加在主人身上（合并成 1 + Σbonus）；mult = 真倍率（相乘）
-- bonusLilith = 莉莉丝/双生莉莉丝本人时的加成（Incubus 不减 25%）
power_forms.FAMILY = {
    incubus      = { bonus = 0.75, bonusLilith = 1.00 },   -- 360：EID {75,150,100,200}
    twisted_pair = { bonus = 0.75, bonusLilith = 1.00 },   -- 698：2 只 × 0.375（莉莉丝 0.5×2）
    succubus     = { mult = 1.50 },                        -- 417：待确认是否已在面板
}

--- 宝宝倍数。空表 → 1
--- @param bffs boolean  有 BFFS!(247) 时，加成型宝宝的加成翻倍（EID repBFFSSynergies 实测 75→150）
--- @param lilith boolean 莉莉丝/双生莉莉丝：Incubus 与双生宝的 0.75 变 1.0
function power_forms.familyMult(list, bffs, lilith)
    local bonus, mult = 0, 1
    if type(list) == "table" then
        for i = 1, #list do
            local e = power_forms.FAMILY[list[i]]
            if e then
                local b = e.bonus or 0
                if lilith and e.bonusLilith then b = e.bonusLilith end
                if bffs and b > 0 then b = b * 2 end
                bonus = bonus + b
                mult = mult * (e.mult or 1)
            end
        end
    end
    return (1 + bonus) * mult
end

-- ── 幸运概率类（公式抄自 EID 的 EID.LuckFormulas）────────────────────────
-- kind = "inv"    : p% = 100 / max(cap, bottom − ⌊luck × factor⌋)
-- kind = "linear" : p% = base + per × luck                    （忏悔覆盖版）
-- mult  = 触发时伤害是面板的几倍（按期望折：1 + p×(mult−1)）
-- flat  = 触发时是一笔固定伤害（按 p × flat × 射速 折）
power_forms.LUCK = {
    tough_love  = { id = 150, kind = "inv", bottom = 10, factor = 1,   cap = 1, mult = 3.2 }, -- ⚠️ 牙齿 3.2x
    holy_light  = { id = 374, kind = "inv", bottom = 10, factor = 0.9, cap = 2, mult = 3.0 },
    euthanasia  = { id = 496, kind = "inv", bottom = 30, factor = 2,   cap = 4, mult = 3.0 },
    little_horn = { id = 503, kind = "inv", bottom = 20, factor = 1,   cap = 5, flat = 36 },
    knockout    = { id = 637, kind = "inv", bottom = 10, factor = 1,   cap = 1, flat = 0 },  -- ⚠️ 无伤害数值
    moms_eye    = { id = 55,  kind = "linear", base = 50, per = 10 },                        -- 只记概率
    loki_horns  = { id = 87,  kind = "linear", base = 25, per = 5 },                         -- 只记概率
}

--- 单个道具的触发概率（0~1）。未知 key → 0
function power_forms.luckP(key, luck)
    local e = power_forms.LUCK[key]
    if not e then return 0 end
    luck = tonumber(luck) or 0
    local pct
    if e.kind == "linear" then
        pct = e.base + e.per * luck
    else
        local d = e.bottom - math.floor(luck * e.factor)
        if d < e.cap then d = e.cap end
        pct = 100 / d
    end
    if pct > 100 then pct = 100 elseif pct < 0 then pct = 0 end
    return pct / 100
end

--- 一组幸运道具的期望影响：返回 乘区, 附加DPS
function power_forms.luckEffects(keys, luck, fr)
    local mult, add = 1, 0
    if type(keys) == "table" then
        for i = 1, #keys do
            local e = power_forms.LUCK[keys[i]]
            if e then
                local p = power_forms.luckP(keys[i], luck)
                if e.mult then
                    mult = mult * (1 + p * (e.mult - 1))
                elseif e.flat then
                    add = add + p * e.flat * (fr or 0)
                end
            end
        end
    end
    return mult, add
end

--- 主人自己的等效 DPS（不含宝宝、不含道具乘区）
function power_forms.formPower(s)
    if type(s) ~= "table" then return 0 end
    local dmg = tonumber(s.damage) or 0
    if dmg < 0 then dmg = 0 end
    local fr = shotsPerSecond(s.maxFireDelay)
    local n = tonumber(s.numTearsAvg) or 1
    if n < 1 then n = 1 end

    local f = power_forms.FORMS[s.form or "tears"] or power_forms.FORMS.tears
    local fill = tonumber(s.chargeFill) or power_forms.chargeFill
    if fill < 0 then fill = 0 elseif fill > 1 then fill = 1 end

    if f.kind == "beam" then
        return dmg * f.ticks * f.tickMult * n / (1 / fr + f.beamSec)
    elseif f.kind == "charge" then
        local m = f.mMin + (f.mMax - f.mMin) * fill
        return dmg * m * fr * n
    elseif f.kind == "fixed" then
        return dmg * f.hitMult / f.cycleSec * n
    elseif f.kind == "contact" then
        return dmg * fr * f.tickMult * f.duty * n
    elseif f.kind == "ring" then
        return dmg * f.tickMult * f.ticksPerRing / f.chargeSec * n
    end
    -- rate
    local hm = f.hitMult or 1
    return dmg * hm * fr * n + (f.flat or 0) * fr
end

--- 总战力：形态 × 道具乘区 × 幸运期望 × 宝宝倍数 + 附加固定 DPS
function power_forms.output(s)
    if type(s) ~= "table" then return 0 end
    local base = power_forms.formPower(s)
    local mult = tonumber(s.mult) or 1
    local add  = tonumber(s.addDps) or 0
    local fr = shotsPerSecond(s.maxFireDelay)

    local luckMult, luckAdd = power_forms.luckEffects(s.luckItems, s.luck or 0, fr)
    return base * mult * luckMult * power_forms.familyMult(s.family, s.bffs, s.lilith) + add + luckAdd
end

return power_forms
