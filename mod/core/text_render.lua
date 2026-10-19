-- ============================================================================
-- text_render.lua —— 把 highlight 产出的册子结构渲染成**纯文本**
--
-- 这是"离线册子"的渲染器。游戏内的渲染器（以后 ui/*.lua）消费**同一个结构**，
-- 所以这里验证过的排版、顺序、取舍，游戏内不会走样。
--
-- 纯字符串拼接，不依赖游戏 API，也不依赖 io。
-- ============================================================================
local text = {}

local W = 62

local function line(ch) return string.rep(ch or "─", W) end

local function center(s)
    local pad = math.max(0, math.floor((W - #s) / 2))
    return string.rep(" ", pad) .. s
end

local function pad(s, n)
    s = tostring(s)
    if #s >= n then return s end
    return s .. string.rep(" ", n - #s)
end

local function padLeft(s, n)
    s = tostring(s)
    if #s >= n then return s end
    return string.rep(" ", n - #s) .. s
end

local function pctStr(p)
    if p >= 0 then return string.format("+%.1f%%", p) end
    return string.format("%.1f%%", p)
end

local function deltaStr(d)
    if d >= 0 then return string.format("+%.2f", d) end
    return string.format("%.2f", d)
end

--- book: highlight.analyze 的输出；opts: { title=... }
--- id → 显示文本：有名字用"名字(id)"，没名字就只写 id
local function label(id, opts)
    local nm = opts and opts.itemName and opts.itemName(id)
    if nm then return string.format("%s(%d)", nm, id) end
    return tostring(id)
end

function text.book(book, opts)
    opts = opts or {}
    local out = {}
    local function w(s) out[#out + 1] = s end

    -- 封面
    w(line("═"))
    w(center(opts.title or "高光回顾"))
    w("")
    local total = 0
    for i = 1, #book.floors do total = total + book.floors[i].ms end
    local growth = (book.base and book.base > 0) and ((book.final - book.base) / book.base * 100) or 0

    w(string.format("  %s   ·   %s   ·   %d 层   ·   总用时 %s",
        book.runId, opts.resultName or ("res" .. tostring(book.result)),
        book.maxFloor, opts.duration and opts.duration(total) or ""))
    w(string.format("  战力  %.2f → %.2f   （%s，%s）",
        book.base, book.final, deltaStr(book.final - book.base), pctStr(growth)))
    w(line("═"))

    -- 品质信号房：房间明细卡（Q4 / Q0 不看阈值，全部列出）
    if book.mustSee and #book.mustSee > 0 then
        w("")
        w("【品质信号 · 房间明细】")
        for i = 1, #book.mustSee do
            local h = book.mustSee[i]
            local dir = "持平"
            if h.delta >= 0.5 then dir = "↑ 起飞"
            elseif h.delta <= -0.5 then dir = "↓ 下跌" end

            w("")
            w(string.format("  ── F%d-%02d %s房  ·  %s",
                h.floor, h.idx,
                opts.roomName and opts.roomName(h.type) or ("型" .. h.type),
                h.first and "首次访问" or "回访"))
            w(string.format("     战力  %.2f → %.2f   %s %s (%s)",
                h.p, h.po, deltaStr(h.delta), dir, pctStr(h.pct)))
            w(string.format("     停留  %s   受伤 %d   进门敌人 %d   %s",
                opts.duration and opts.duration(h.ms) or "", h.dmg, h.foes,
                (h.foes or 0) == 0 and "无敌人" or (h.cleared and "已清房" or "未清房")))
            local mx1, mx2 = h.mxhp or 0, h.mxhpo or 0
            w(string.format("     血量  红 %d/%d → %d/%d   魂 %d→%d   黑 %d→%d   骨 %d→%d   金 %d→%d",
                h.hp or 0, mx1, h.hpo or 0, mx2,
                h.hs or 0, h.hso or 0, h.hbl or 0, h.hblo or 0,
                h.hb or 0, h.hbo or 0,
                (h.hgo or 0) + (h.het or 0), (h.hgoo or 0) + (h.heto or 0)))
            if h.ts then
                w(string.format("     六维  伤害 %.2f   攻速 %.2f   弹速 %.2f   射程 %.1f   移速 %.2f   幸运 %.0f",
                    h.dv or 0, h.ts or 0, h.ss or 0, (h.rg or 0) / 40, h.mv or 0, h.lk or 0))
            end
            w(string.format("     口袋  金 %d→%d   弹 %d→%d   钥 %d→%d",
                h.c or 0, h.co or 0, h.bmb or 0, h.bmbo or 0, h.key or 0, h.keyo or 0))


            local items = {}
            for k = 1, #h.it do
                local nm = opts.itemName and opts.itemName(h.it[k]) or nil
                if nm then
                    items[#items + 1] = string.format("%s(%s, Q%s)", nm, tostring(h.it[k]), tostring(h.iq[k] or "?"))
                else
                    items[#items + 1] = string.format("%d(Q%s)", h.it[k], tostring(h.iq[k] or "?"))
                end
            end
            if #items > 0 then
                w("     道具  " .. table.concat(items, "  "))
            end
            if (h.type == 5 or h.type == 6) and h.boss and h.boss > 0 then
                w("     Boss  id " .. tostring(h.boss))
            end
        end
    end
    -- 全局 Top-N
    if book.topK and #book.topK > 0 then
        w("")
        w("【本局最强跳变】")
        for i = 1, #book.topK do
            local h = book.topK[i]
            w(string.format("  #%d  F%d-%02d %-6s  %7.2f → %7.2f   %s (%s)",
                i, h.floor, h.idx, opts.roomName and opts.roomName(h.type) or ("型" .. h.type),
                h.p, h.po, deltaStr(h.delta), pctStr(h.pct)))
        end
    end

    -- 按层分章
    for fi = 1, #book.floors do
        local f = book.floors[fi]
        w("")
        w(string.format("【层 %d】  %s", f.i, (opts.stageName and opts.stageName(f) or "")))
        if f.curse and f.curse ~= 0 and opts.curseNames then
            local names = opts.curseNames(f.curse)
            if #names > 0 then w("  诅咒：" .. table.concat(names, "、")) end
        end
        w(string.format("  %d 间房（首次 %d）  ·  %s  ·  受伤 %d  ·  战力 %.2f → %.2f  (%s)",
            f.rooms, f.firstRooms or 0, opts.duration and opts.duration(f.ms) or "",
            f.dmg, f.powerIn, f.powerOut, deltaStr(f.gain)))
        if #f.items > 0 then
            local ids = {}
            for i = 1, #f.items do ids[i] = label(f.items[i], opts) end
            w("  道具：" .. table.concat(ids, ", "))
        end
        if #f.trinkets > 0 then
            local ids = {}
            for i = 1, #f.trinkets do ids[i] = tostring(f.trinkets[i]) end
            w("  饰品：" .. table.concat(ids, ", "))
        end

        -- 本层高光（正文按时间序）
        local hits = {}
        for i = 1, #book.highlights do
            if book.highlights[i].floor == f.i then hits[#hits + 1] = book.highlights[i] end
        end
        if #hits > 0 then
            w("")
            for i = 1, #hits do
                local h = hits[i]
                w(string.format("  ★ %02d %-6s %7.2f → %7.2f  %s (%s)  %s  %s%s",
                    h.idx,
                    opts.roomName and opts.roomName(h.type) or ("型" .. h.type),
                    h.p, h.po, deltaStr(h.delta), pctStr(h.pct),
                    opts.duration and opts.duration(h.ms) or "",
                    (#h.it > 0) and ("道具 " .. (function()
                        local t2 = {}
                        for k = 1, #h.it do t2[k] = label(h.it[k], opts) end
                        return table.concat(t2, ", ")
                    end)() .. "  ") or "",
                    (#h.tro > #h.tri) and "饰品+" or ""))
            end
        end
    end

    -- 战力曲线（文本版）
    if book.curve and #book.curve > 0 then
        w("")
        w(line("─"))
        w("战力曲线（每层末）")
        local maxP = 0
        for i = 1, #book.curve do
            if book.curve[i].power > maxP then maxP = book.curve[i].power end
        end
        for i = 1, #book.curve do
            local c = book.curve[i]
            local bars = (maxP > 0) and math.floor(c.power / maxP * 40 + 0.5) or 0
            w(string.format("  层%-2d %7.2f %s", c.floor, c.power, string.rep("█", bars)))
        end
    end

    w("")
    w(line("═"))
    return table.concat(out, "\n")
end

text.WIDTH = W
return text
