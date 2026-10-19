-- =============================================================================
-- book_demo.lua —— 用手造的"有跳变"的数据验证 highlight + text_render
-- 目的：验证 ★ 高光段、Top-N、战力曲线在有数据时的排版
-- 运行：tools\luarun.ps1 tests\book_demo.lua
-- =============================================================================
local ROOT = (os and os.getenv and os.getenv("HLR_ROOT")) or "D:/00000/aiStudy/issacmod/"
if ROOT:sub(-1) ~= "/" then ROOT = ROOT .. "/" end
local function loadmod(p) return loadfile(ROOT .. p)() end

local hl = loadmod("mod/core/highlight.lua")
local text = loadmod("mod/core/text_render.lua")

-- 造一局：3 层，其中有 3 次明显跳变
local run = {
    seq = 7, id = "DEMO1234-0", res = 1, max = 3, base = 11.45, final = 48.20,
    floors = {
        { i = 1, stage = 1, type = 0, curse = 0 },
        { i = 2, stage = 2, type = 0, curse = 16 + 1 },   -- 诅咒 + 黑暗
        { i = 3, stage = 3, type = 0, curse = 64 },        -- 失明
    },
    rooms = {
        -- 层 1
        { r = 7, f = 1, i = 1, t = 1, s = 1, p = 11.45, po = 11.45, ms = 40000, dmg = 0, it = {}, tri = {}, tro = {} },
        { r = 7, f = 1, i = 2, t = 4, s = 1, p = 11.45, po = 18.90, ms = 9000,  dmg = 0, it = { 118 }, iq = { 4 }, tri = {}, tro = {}, hp = 6, mxhp = 10, hpo = 4, mxhpo = 10, hs = 2, hso = 5, hbl = 1, hblo = 3, ts = 3.10, ss = 1.0, rg = 6.5, mv = 1.0, lk = 2, dv = 6.23 },   -- Q4 起飞
        { r = 7, f = 1, i = 3, t = 1, s = 1, p = 18.90, po = 18.90, ms = 50000, dmg = 2, it = {}, tri = {}, tro = { 41 } },
        { r = 7, f = 1, i = 4, t = 5, s = 1, p = 18.90, po = 18.90, ms = 60000, dmg = 3, it = { 1532 }, iq = { 2 }, tri = { 41 }, tro = { 41 } },
        -- 层 2
        { r = 7, f = 2, i = 1, t = 1, s = 1, p = 18.90, po = 18.90, ms = 30000, dmg = 0, it = {}, tri = { 41 }, tro = { 41 } },
        { r = 7, f = 2, i = 2, t = 14, s = 1, p = 18.90, po = 29.40, ms = 8000, dmg = 0, it = { 331 }, iq = { 3 }, tri = { 41 }, tro = { 41 } },
        { r = 7, f = 2, i = 3, t = 5, s = 1, p = 29.40, po = 29.40, ms = 70000, dmg = 4, it = {}, tri = { 41 }, tro = { 41 } },
        -- 层 3
        { r = 7, f = 3, i = 1, t = 1, s = 1, p = 29.40, po = 29.40, ms = 20000, dmg = 1, it = {}, tri = { 41 }, tro = { 41 } },
        { r = 7, f = 3, i = 2, t = 4, s = 1, p = 29.40, po = 48.20, ms = 6000,  dmg = 0, it = { 1286 }, iq = { 0 }, tri = { 41 }, tro = { 41 } },  -- Q0 封盘
        { r = 7, f = 3, i = 3, t = 1, s = 1, p = 48.20, po = 48.20, ms = 90000, dmg = 5, it = {}, tri = { 41 }, tro = { 41 } },
    },
}

local book = hl.analyze(run, { relPct = 15, absDelta = 0.5, perFloorMax = 3, topK = 5 })
local body = text.book(book, {
    title = "高光回顾 · 样例",
    resultName = hl.resultName(book.result),
    roomName = hl.roomName,
    curseNames = hl.curseNames,
    duration = hl.duration,
})

local outPath = ROOT .. "_logs/demo-book.txt"
local f = io.open(outPath, "wb")
if f then f:write(body) f:close() end

return string.format("OK 样例已写入 _logs/demo-book.txt  高光 %d 条 / TopK %d 条 / 层 %d 个",
    #book.highlights, #book.topK, #book.floors)
