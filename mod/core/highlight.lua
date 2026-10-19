-- ============================================================================
-- highlight.lua —— 册子的“内容层”（纯 Lua，不依赖游戏 API，也不含任何渲染）
--
-- 这是**唯一的一处真相**：
--   离线册子  → tests/book_offline.lua 调用它 → core/text_render.lua 出文本
--   游戏内册子 → ui/*.lua 调用它           → 画成图形
-- 两边拿到的是同一个结构，所以离线验证过的排版，游戏内不会走样。
--
-- 输入：一局（fmt.decodeRun 的输出：floors[] + rooms[]）
-- 输出：册子结构（见文件末尾说明）
-- ============================================================================
local highlight = {}

local DEFAULT_CFG = {
    relPct      = 15,    -- 相对涨幅阈值 %
    absDelta    = 0.5,   -- 绝对增幅阈值
    perFloorMax = 3,     -- 每层最多收录几条
    topK        = 5,     -- 全局强制收录 Top-K
}

-- 房型名字（只在文本渲染里用得更多，这里给个通用表）
highlight.ROOM_NAMES = {
    [1] = "普通", [2] = "商店", [4] = "宝箱", [5] = "Boss", [6] = "小Boss",
    [7] = "密室", [8] = "超密", [9] = "街机", [10] = "诅咒", [11] = "挑战",
    [12] = "图书馆", [13] = "祭坛", [14] = "恶魔", [15] = "天使", [16] = "地牢",
    [17] = "BossRush", [18] = "以撒房", [20] = "宝箱房", [21] = "骰子房",
}

function highlight.roomName(t)
    return highlight.ROOM_NAMES[t] or ("型" .. tostring(t))
end

-- 结局
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

--- 层诅咒位掩码 → 名字列表
highlight.CURSE_BITS = {
    { bit = 1,   name = "黑暗" },
    { bit = 2,   name = "迷宫" },
    { bit = 4,   name = "迷失" },
    { bit = 8,   name = "未知" },
    { bit = 16,  name = "诅咒" },
    { bit = 32,  name = "迷阵" },
    { bit = 64,  name = "失明" },
    { bit = 128, name = "巨大" },
}

function highlight.curseNames(mask)
    mask = tonumber(mask) or 0
    if mask == 0 then return {} end
    local out = {}
    for i = 1, #highlight.CURSE_BITS do
        local c = highlight.CURSE_BITS[i]
        -- 位与：Lua 5.3+ 有 // 但为了兼容直接用取模拆位
        if math.floor(mask / c.bit) % 2 == 1 then out[#out + 1] = c.name end
    end
    return out
end

-- ---------------------------------------------------------------- 核心分析

--- 把一局分析成册子结构。cfg 可选（默认见 DEFAULT_CFG）
function highlight.analyze(run, cfg)
    cfg = cfg or DEFAULT_CFG
    local book = {
        runId   = run.id or "?",
        result  = run.res or 2,
        maxFloor= run.max or 0,
        base    = run.base or 0,
        final   = run.final or 0,
        floors  = {},
        highlights = {},
        curve   = {},      -- 每层末的战力，给折线用
        rooms   = {},      -- 展平后的房间（带计算好的 delta）
    }

    -- 1) 展平房间 + 计算派生值
    local rooms = {}
    for i = 1, #(run.rooms or {}) do
        local r = run.rooms[i]
        local delta = (r.po or 0) - (r.p or 0)
        local pct = (r.p and r.p > 0) and (delta / r.p * 100) or 0
        rooms[#rooms + 1] = {
            floor = r.f or 1, idx = r.i or 0,
            type  = r.t or 0, shape = r.s or 0,
            p     = r.p or 0, po = r.po or 0,
            delta = delta, pct = pct,
            hp    = r.hp, hs = r.hs, hb = r.hb,
            hbl   = r.hbl, hgo = r.hgo, het = r.het, hrt = r.hrt,
            hpo   = r.hpo, hso = r.hso, hbo = r.hbo,
            hblo  = r.hblo, hgoo = r.hgoo, heto = r.heto, hrto = r.hrto,
            mxhp  = r.mxhp, mxhpo = r.mxhpo,
            ts    = r.ts, ss = r.ss, rg = r.rg, mv = r.mv, lk = r.lk,
            dv    = r.dv, mu = r.mu, fm = r.fm,
            ms    = r.ms or 0, dmg = r.dmg or 0, first = r.first,
            foes  = r.foes or 0,
            c     = r.c or 0, co = r.co or 0,
            bmb   = r.bmb or 0, bmbo = r.bmbo or 0,
            key   = r.key or 0, keyo = r.keyo or 0,
            boss  = r.boss or 0, cleared = r.clr,
            it    = r.it or {}, iq = r.iq or {},
            tri   = r.tri or {}, tro = r.tro or {},
            clr   = r.clr,
        }
    end
    -- 品质信号：只标注"这间房拿到了 Q4 / Q0"，不直接判定起飞或封盘。
    -- 真正的性质由实际战力变化决定（见 tag）。
    for i = 1, #rooms do
        local r = rooms[i]
        local q4, q0 = 0, 0
        for k = 1, #r.iq do
            local q = r.iq[k]
            if q >= 4 then q4 = q4 + 1 end
            if q == 0 then q0 = q0 + 1 end
        end
        r.q4, r.q0 = q4, q0
        if q4 > 0 then r.qtag = "Q4" elseif q0 > 0 then r.qtag = "Q0" end
        -- 性质：只看战力变化
        if r.delta >= cfg.absDelta then r.tag = "up"
        elseif r.delta <= -cfg.absDelta then r.tag = "down" end
    end

    book.rooms = rooms

    -- 2) 层汇总
    local floorMap = {}
    for i = 1, #(run.floors or {}) do
        local f = run.floors[i]
        floorMap[f.i] = {
            i = f.i, stage = f.stage, stageType = f.type,
            curse = f.curse or 0, alt = f.alt or 0,
            rooms = 0, firstRooms = 0, items = {}, trinkets = {},
            powerIn = nil, powerOut = 0, gain = 0, ms = 0, dmg = 0,
        }
    end
    for i = 1, #rooms do
        local r = rooms[i]
        local fs = floorMap[r.floor]
        if not fs then
            fs = { i = r.floor, rooms = 0, firstRooms = 0, items = {}, trinkets = {}, gain = 0, ms = 0, dmg = 0 }
            floorMap[r.floor] = fs
        end
        fs.rooms = fs.rooms + 1
        if r.first then fs.firstRooms = (fs.firstRooms or 0) + 1 end
        fs.ms = fs.ms + r.ms
        fs.dmg = fs.dmg + r.dmg
        if fs.powerIn == nil then fs.powerIn = r.p end
        fs.powerOut = r.po
        for k = 1, #r.it do fs.items[#fs.items + 1] = r.it[k] end
        for k = 1, #r.tro do
            local seen = false
            for j = 1, #fs.trinkets do if fs.trinkets[j] == r.tro[k] then seen = true end end
            if not seen then fs.trinkets[#fs.trinkets + 1] = r.tro[k] end
        end
    end

    -- 排序 + 算 gain + 曲线
    local floorOrder = {}
    for i in pairs(floorMap) do floorOrder[#floorOrder + 1] = i end
    table.sort(floorOrder)
    for k = 1, #floorOrder do
        local fs = floorMap[floorOrder[k]]
        fs.powerIn = fs.powerIn or 0
        fs.gain = fs.powerOut - fs.powerIn
        book.floors[#book.floors + 1] = fs
        book.curve[#book.curve + 1] = { floor = fs.i, power = fs.powerOut }
    end

    -- 3) 高光判定：绝对 + 相对双门槛
    local cand = {}
    for i = 1, #rooms do
        local r = rooms[i]
        if r.delta >= cfg.absDelta and r.pct >= cfg.relPct then
            cand[#cand + 1] = r
        end
    end

    -- 每层最多 perFloorMax 条（按 delta 降序取）
    table.sort(cand, function(a, b) return a.delta > b.delta end)
    local perFloor, picked = {}, {}
    for i = 1, #cand do
        local r = cand[i]
        local n = perFloor[r.floor] or 0
        if n < cfg.perFloorMax then
            perFloor[r.floor] = n + 1
            picked[#picked + 1] = r
        end
    end

    -- 全局按时间序排（册子正文按时间读）
    table.sort(picked, function(a, b)
        if a.floor ~= b.floor then return a.floor < b.floor end
        return a.idx < b.idx
    end)
    book.highlights = picked
    book.topK = {}
    for i = 1, math.min(cfg.topK, #cand) do book.topK[i] = cand[i] end

    -- 品质信号房：不看阈值，全部强制收录（Q4 / Q0）
    book.mustSee = {}
    for i = 1, #rooms do
        if rooms[i].qtag then book.mustSee[#book.mustSee + 1] = rooms[i] end
    end

    return book
end

return highlight
