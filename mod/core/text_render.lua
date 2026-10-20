-- ============================================================================
-- text_render.lua —— 离线册子的文本渲染（与 ui/book.lua 结构保持一致）
--
-- 两边的页序完全相同：Overview → 亮点回顾 → 各层。
-- 内容层都来自 core/highlight.lua，所以离线验证过的取舍，游戏内不会走样。
-- ============================================================================
local text = {}

local W = 64

local function line(ch) return string.rep(ch or "─", W) end
local function center(s)
    local pad = math.max(0, math.floor((W - #s) / 2))
    return string.rep(" ", pad) .. s
end
local function pctStr(p)
    if p >= 0 then return string.format("+%.1f%%", p) end
    return string.format("%.1f%%", p)
end
local function deltaStr(d)
    if d >= 0 then return string.format("+%.2f", d) end
    return string.format("%.2f", d)
end
local function bar(frac, n)
    n = n or 16
    local f = math.floor(frac * n + 0.5)
    if f < 0 then f = 0 end
    if f > n then f = n end
    return string.rep("█", f) .. string.rep("░", n - f)
end

--- 道具：优先名字，其次 id
local function itemLabel(id, opts)
    local nm = opts and opts.itemName and opts.itemName(id)
    if nm then return string.format("%s(%d)", nm, id) end
    return tostring(id)
end

local function title(text, right)
    local pad = math.max(1, W - #text - #(right or "") - 1)
    return "  " .. text .. string.rep(" ", pad) .. (right or "")
end

--- book: highlight.analyze 的输出
function text.book(book, opts)
    opts = opts or {}
    local out = {}
    local function w(s) out[#out + 1] = s end

    -- ── Overview ───────────────────────────────────────────────
    w(line("═"))
    w(center(opts.title or "高光回顾"))
    w("")
    w(title("Overview", string.format("1/%d", book.pageCount)))
    local rn = opts.resultName
    local rtext = (type(rn) == "function") and rn(book.result) or (rn or tostring(book.result))
    w(string.format("  %s   %s   %dF   %d rooms",
        book.runId, rtext, book.maxFloor, #book.rooms))
    local growth = (book.base > 0) and ((book.final - book.base) / book.base * 100) or 0
    w(string.format("  POWER  %.2f > %.2f    %+.2f   (%s)",
        book.base, book.final, book.final - book.base, pctStr(growth)))
    w("")

    local maxP = 0
    for i = 1, #book.floors do if book.floors[i].powerOut > maxP then maxP = book.floors[i].powerOut end end
    if maxP <= 0 then maxP = 1 end
    for i = 1, #book.floors do
        local f = book.floors[i]
        w(string.format("  Floor%-2d %8.2f  %s  %+.2f %s",
            f.i, f.powerOut, bar(f.powerOut / maxP, 16), f.gain,
            opts.duration and opts.duration(f.ms) or ""))
    end
    w(line("═"))

    -- ── 亮点回顾 ───────────────────────────────────────────────
    for pi = 1, #book.pages do
        local p = book.pages[pi]
        local r = p.room
        local label = string.format("%s  #%d",
            (p.kind == "power" and "战力提升") or (p.kind == "q4" and "四级道具") or "零级道具",
            p.rank)

        w("")
        w(title(label, string.format("%d/%d", 1 + pi, book.pageCount)))
        w(string.format("  Floor %d   第 %.0f 间   %s%s", r.floor, r.idx,
            (opts.roomName and opts.roomName(r.type)) or tostring(r.type),
            r.first and "" or "（回访）"))
        w(string.format("  战力  %.2f > %.2f   %s  (%s)",
            r.p, r.po, deltaStr(r.delta), pctStr(r.pct)))
        w(string.format("  停留 %s   受伤 %d   进门敌人 %d",
            (opts.duration and opts.duration(r.ms)) or "", r.dmg, r.foes))

        for si = 1, #r.stats do
            local st = r.stats[si]
            local mx = book.statMax[st.key] or 0
            local frac = (mx > 0) and (st.outV / mx) or 0
            w(string.format("  %-3s %7.2f  %s  %s",
                st.label, st.outV, bar(frac, 12), deltaStr(st.delta)))
        end

        if #r.it > 0 then
            local items = {}
            for k = 1, #r.it do
                items[k] = string.format("%s(Q%s)", itemLabel(r.it[k], opts), tostring(r.iq[k] or "?"))
            end
            w("  道具  " .. table.concat(items, "  "))
        end
    end

    -- ── 楼层页 ────────────────────────────────────────────────
    for fi = 1, #book.floors do
        local f = book.floors[fi]
        w("")
        w(title(string.format("Floor %d", f.i),
            string.format("%d/%d", 1 + #book.pages + fi, book.pageCount)))
        w(string.format("  %s   ·   受伤 %d   ·   战力 %.2f > %.2f  (%s)",
            (opts.duration and opts.duration(f.ms)) or "", f.dmg, f.powerIn, f.powerOut,
            deltaStr(f.gain)))
        local curses = opts.curseNames and opts.curseNames(f.curse) or {}
        if #curses > 0 then w("  诅咒：" .. table.concat(curses, "、")) end
        if #f.items > 0 then
            local items = {}
            local n = math.min(#f.items, 16)
            for k = 1, n do items[k] = itemLabel(f.items[k], opts) end
            local more = (#f.items > 16) and string.format("  +%d", #f.items - 16) or ""
            w(string.format("  道具（%d）：%s%s", #f.items, table.concat(items, ", "), more))
        end
    end

    w("")
    w(line("═"))
    return table.concat(out, "\n")
end

text.WIDTH = W
return text
