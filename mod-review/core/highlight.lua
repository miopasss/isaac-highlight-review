-- ============================================================================
-- highlight.lua —— 册子的"内容层"（纯 Lua，不依赖游戏 API，也不含渲染）
--
-- 这是唯一真相：
--   离线册子  → tests/book_offline.lua → core/text_render.lua 出文本
--   游戏内册子 → ui/book.lua            → 画成羊皮纸界面
--
-- 页结构（v2）：
--   1. Overview
--   2. 亮点回顾：战力提升 Top3（按房间）+ 四级道具（时间顺序，同房合并，最多 3 页）
--                + 零级道具最早 1 个
--   3. 楼层页：每层一行汇总 + 诅咒 + 道具列表
-- ============================================================================
local highlight = {}

local DEFAULT_CFG = {
    powerTopN  = 3,      -- 战力提升收录几条
    q4MaxPages = 3,      -- 四级道具最多几页
    absDelta   = 0.5,    -- 战力变化的绝对门槛
    relPct     = 15,     -- 战力变化的相对门槛（百分比）
}

highlight.ROOM_NAMES = {
    [1] = "普通房", [2] = "商店", [4] = "宝箱房", [5] = "Boss房", [6] = "小Boss",
    [7] = "普通隐藏房", [8] = "超级隐藏房", [9] = "街机房", [10] = "诅咒房",
    [11] = "挑战房", [12] = "图书馆", [13] = "祭坛房", [14] = "恶魔房",
    [15] = "天使房", [16] = "地牢房", [17] = "BossRush", [18] = "以撒房",
    [20] = "星象房", [21] = "骰子房", [22] = "传送房", [23] = "洁净室",
}

function highlight.roomName(t)
    return highlight.ROOM_NAMES[t] or ("型" .. tostring(t))
end

-- 游戏内字体是 ASCII 位图字，中文会变乱码，所以另给一套英文名
highlight.ROOM_NAMES_EN = {
    [1] = "NORMAL", [2] = "SHOP", [4] = "TREASURE", [5] = "BOSS", [6] = "MINIBOSS",
    [7] = "SECRET", [8] = "SUPERSECRET", [9] = "ARCADE", [10] = "CURSE",
    [11] = "CHALLENGE", [12] = "LIBRARY", [13] = "SACRIFICE", [14] = "DEVIL",
    [15] = "ANGEL", [16] = "DUNGEON", [17] = "BOSSRUSH", [18] = "ISAAC",
    [20] = "STAR", [21] = "DICE", [22] = "TELEPORTER", [23] = "CLEAN",
}

function highlight.roomNameEn(t)
    return highlight.ROOM_NAMES_EN[t] or ("T" .. tostring(t))
end

--- 时长（ASCII 版）：3m48s / 48s
function highlight.durationEn(ms)
    local sec = math.floor((tonumber(ms) or 0) / 1000)
    local m, s = math.floor(sec / 60), sec % 60
    if m > 0 then return string.format("%dm%02ds", m, s) end
    return string.format("%ds", s)
end

highlight.CURSE_BITS_EN = {
    { bit = 1, name = "DARK" }, { bit = 2, name = "LABYRINTH" },
    { bit = 4, name = "LOST" }, { bit = 8, name = "UNKNOWN" },
    { bit = 16, name = "CURSED" }, { bit = 32, name = "MAZE" },
    { bit = 64, name = "BLIND" }, { bit = 128, name = "GIANT" },
}

function highlight.curseNamesEn(mask)
    mask = tonumber(mask) or 0
    local out = {}
    for _, c in ipairs(highlight.CURSE_BITS_EN) do
        if math.floor(mask / c.bit) % 2 == 1 then out[#out + 1] = c.name end
    end
    return out
end

-- 终极 Boss（采集端写入的 ub 代码 → 显示名，作者指定）
highlight.ULTIMATE_BOSS = {
    [1] = { cn = "Hush",       en = "Hush" },
    [2] = { cn = "Boss Rush",  en = "Boss Rush" },
    [3] = { cn = "超级撒旦",   en = "Mega Satan" },
    [4] = { cn = "老干妈",     en = "Mother" },
    [5] = { cn = "祸兽",       en = "The Beast" },
    [6] = { cn = "百变怪",     en = "Delirium" },
}

function highlight.bossName(code, useEn)
    local e = highlight.ULTIMATE_BOSS[code]
    if not e then return nil end
    return useEn and e.en or e.cn
end

highlight.RESULT_NAMES = { [0] = "死亡", [1] = "通关", [2] = "未完成" }

function highlight.resultName(r)
    return highlight.RESULT_NAMES[r] or ("res" .. tostring(r))
end

local function fmtDuration(ms)
    local sec = math.floor((ms or 0) / 1000)
    local m, s = math.floor(sec / 60), sec % 60
    if m > 0 then return string.format("%d分%02d秒", m, s) end
    return string.format("%d秒", s)
end
highlight.duration = fmtDuration

highlight.CURSE_BITS = {
    { bit = 1,   name = "黑暗" }, { bit = 2,   name = "迷宫" },
    { bit = 4,   name = "迷失" }, { bit = 8,   name = "未知" },
    { bit = 16,  name = "诅咒" }, { bit = 32,  name = "迷阵" },
    { bit = 64,  name = "失明" }, { bit = 128, name = "巨大" },
}

function highlight.curseNames(mask)
    mask = tonumber(mask) or 0
    if mask == 0 then return {} end
    local out = {}
    for i = 1, #highlight.CURSE_BITS do
        local c = highlight.CURSE_BITS[i]
        if math.floor(mask / c.bit) % 2 == 1 then out[#out + 1] = c.name end
    end
    return out
end

-- 六维定义：进房 / 出房字段名 + 显示缩放
highlight.STATS = {
    { key = "dv", label = "伤害", labelEn = "DMG",  inKey = "dv",  outKey = "dvo", scale = 1.0    },
    { key = "ts", label = "攻速", labelEn = "TEAR", inKey = "tso", outKey = "ts",  scale = 1.0    },
    { key = "ss", label = "弹速", labelEn = "SHOT", inKey = "sso", outKey = "ss",  scale = 1.0    },
    { key = "rg", label = "射程", labelEn = "RNG",  inKey = "rgo", outKey = "rg",  scale = 1 / 40 },
    { key = "mv", label = "移速", labelEn = "SPD",  inKey = "mvo", outKey = "mv",  scale = 1.0    },
    { key = "lk", label = "幸运", labelEn = "LUCK", inKey = "lko", outKey = "lk",  scale = 1.0    },
}

-- ---------------------------------------------------------------- 核心分析

local function num(v) return tonumber(v) or 0 end

--- 把一局分析成册子结构
function highlight.analyze(run, cfg)
    cfg = cfg or {}
    for k, v in pairs(DEFAULT_CFG) do
        if cfg[k] == nil then cfg[k] = v end
    end
    local book = {
        runId = run.id or "?", result = run.res or 2,
        maxFloor = run.max or 0, base = run.base or 0, final = run.final or 0,
        floors = {}, rooms = {}, pages = {},
        statMax = {}, statMin = {}, curve = {},
        w0 = tonumber(run.w0) or nil,
    }

    -- 1) 展平房间 + 六维进出
    local rooms = {}
    for i = 1, #(run.rooms or {}) do
        local r = run.rooms[i]
        local delta = num(r.po) - num(r.p)
        local pct = (num(r.p) > 0) and (delta / num(r.p) * 100) or 0

        local stats = {}
        for _, sd in ipairs(highlight.STATS) do
            local vin  = num(r[sd.inKey])  * sd.scale
            local vout = num(r[sd.outKey]) * sd.scale
            stats[#stats + 1] = {
                key = sd.key, label = sd.label, labelEn = sd.labelEn,
                inV = vin, outV = vout, delta = vout - vin,
            }
            local mx = book.statMax[sd.key] or 0
            if vout > mx then mx = vout end
            if vin > mx then mx = vin end
            book.statMax[sd.key] = mx
            local mn = book.statMin[sd.key]
            if mn == nil then mn = math.min(vin, vout) end
            if vin < mn then mn = vin end
            if vout < mn then mn = vout end
            book.statMin[sd.key] = mn
        end

        rooms[#rooms + 1] = {
            floor = num(r.f), idx = num(r.i),
            type = num(r.t), shape = num(r.s),
            p = num(r.p), po = num(r.po), delta = delta, pct = pct,
            ms = num(r.ms), dmg = num(r.dmg), foes = num(r.foes),
            first = r.first and true or false,
            hp = num(r.hp), hpo = num(r.hpo), mxhp = num(r.mxhp), mxhpo = num(r.mxhpo),
            hs = num(r.hs), hso = num(r.hso), hb = num(r.hb), hbo = num(r.hbo),
            it = r.it or {}, iq = r.iq or {},
            ub = num(r.ub), cleared = r.clr and true or false,
            stats = stats,
        }
    end
    book.rooms = rooms

    -- 2) 楼层汇总
    local map = {}
    for i = 1, #(run.floors or {}) do
        local f = run.floors[i]
        map[num(f.i)] = {
            i = num(f.i), stage = f.stage, curse = num(f.curse),
            rooms = 0, firstRooms = 0, items = {}, ms = 0, dmg = 0,
            powerIn = nil, powerOut = 0, gain = 0,
        }
    end
    for i = 1, #rooms do
        local r = rooms[i]
        local f = map[r.floor]
        if not f then
            f = { i = r.floor, curse = 0, rooms = 0, firstRooms = 0,
                  items = {}, itemsQ = {}, ms = 0, dmg = 0, gain = 0 }
            map[r.floor] = f
        end
        f.rooms = f.rooms + 1
        f.ms = f.ms + r.ms
        f.dmg = f.dmg + r.dmg
        if r.first then f.firstRooms = f.firstRooms + 1 end
        if f.powerIn == nil then f.powerIn = r.p end
        f.powerOut = r.po
        for k = 1, #r.it do f.items[#f.items + 1] = r.it[k] end
    end
    local order = {}
    for i in pairs(map) do order[#order + 1] = i end
    table.sort(order)
    for k = 1, #order do
        local f = map[order[k]]
        f.powerIn = f.powerIn or 0
        f.gain = f.powerOut - f.powerIn
        -- 楼层六维：取本层最后一间房的出房值，增量相对本层第一间的进房值
        local firstR, lastR
        for ri = 1, #rooms do
            if rooms[ri].floor == f.i then
                if not firstR then firstR = rooms[ri] end
                lastR = rooms[ri]
            end
        end
        if lastR then
            f.stats = {}
            for si = 1, #lastR.stats do
                local outS = lastR.stats[si]
                local inV = firstR and firstR.stats[si].inV or outS.inV
                f.stats[si] = {
                    key = outS.key, label = outS.label, labelEn = outS.labelEn,
                    inV = inV, outV = outS.outV, delta = outS.outV - inV,
                }
            end
        end
        book.floors[#book.floors + 1] = f
        book.curve[#book.curve + 1] = { floor = f.i, power = f.powerOut }
    end

    -- 2.5) 终极 Boss（只收"已清房"的；最多 4 个）
    book.finalBosses = {}
    for i = 1, #rooms do
        local r = rooms[i]
        if r.ub ~= 0 and r.cleared then
            book.finalBosses[#book.finalBosses + 1] = r
        end
    end
    book.bossSummary = {}
    for i = 1, #book.finalBosses do
        local b = book.finalBosses[i]
        local nm = highlight.bossName(b.ub, false)
        if nm then book.bossSummary[#book.bossSummary + 1] = nm end
    end

    -- 3) 亮点 ①：战力提升 Top3（按房间进出差值）
    local pool = {}
    for i = 1, #rooms do
        if rooms[i].delta > 0 then pool[#pool + 1] = rooms[i] end
    end
    table.sort(pool, function(a, b) return a.delta > b.delta end)
    for i = 1, math.min(cfg.powerTopN, #pool) do
        book.pages[#book.pages + 1] = {
            kind = "power", rank = i, room = pool[i], title = "战力提升",
        }
    end

    -- 3.5) 页序：整页「终极Boss与终极道具」放最前（总是存在，内容可为空），再接战力 Top3
    local q4Items, q0Items = {}, {}
    for i = 1, #rooms do
        local r = rooms[i]
        for k = 1, #r.it do
            local q = num(r.iq[k])
            -- 只统计"离开房间时还持有"的：临时塞进来的（如被 mod 短暂给的斗篷）不算
            local kept = (r.ik == nil) or (num(r.ik[k]) ~= 0)
            if q >= 4 and kept then q4Items[#q4Items + 1] = r.it[k] end
            if q == 0 and kept and #q0Items == 0 then q0Items[#q0Items + 1] = r.it[k] end
        end
    end

    local finale = {
        kind = "finale",
        title = "终极Boss与终极道具",
        bosses = book.finalBosses,   -- 已清房的终极 Boss（最多显示 4 个）
        q4 = q4Items,
        q0 = q0Items,
    }
    table.insert(book.pages, 1, finale)


    book.pageCount = 1 + #book.pages + #book.floors
    return book
end

return highlight
