-- =============================================================================
-- rooms_dump.lua —— 把一局的所有房间导出成可读文本（调试/核对用）
--
-- 用途：核对"这局到底拿了几个四级道具""结局判定对不对""六维/口袋有没有值"
-- 运行：tools\luarun.ps1 tests\rooms_dump.lua
-- 输出：_logs\rooms-<时间>.txt
-- =============================================================================
local ROOT = (os and os.getenv and os.getenv("HLR_ROOT")) or "D:/00000/aiStudy/issacmod/"
if ROOT:sub(-1) ~= "/" then ROOT = ROOT .. "/" end
local DATA = (os and os.getenv and os.getenv("HLR_DATA")) or "data/highlight-review"
if DATA:sub(-1) ~= "/" and DATA:sub(-1) ~= "\\" then DATA = DATA .. "/" end

local function loadmod(p) return loadfile(ROOT .. p)() end
local schema = loadmod("mod/core/schema.lua")
local fmt    = loadmod("mod/core/fmt.lua")
local hl     = loadmod("mod/core/highlight.lua")
fmt.setSchema(schema)

local function readAll(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end

local stores = {}
local archive = ROOT .. "_archive/all.dat"
local blob = readAll(archive)
if blob then stores[#stores + 1] = { label = "永久档案", blob = blob } end
for slot = 1, 3 do
    local p = DATA .. "save" .. slot .. ".dat"
    local b = readAll(p)
    if b then stores[#stores + 1] = { label = "save" .. slot, blob = b } end
end

if #stores == 0 then return "没有存档" end

local out = {}
local function w(s) out[#out + 1] = s end

for _, st in ipairs(stores) do
    local store = fmt.splitBlob(st.blob)
    w("")
    w(string.rep("=", 100))
    w(string.format("%s  %d 局 / %d 行", st.label, #store.index, #store.lines))
    w(string.rep("=", 100))

    for ri = 1, #store.index do
        local run = fmt.decodeRun(store, store.index[ri])
        local rooms = run.rooms or {}
        local q4, q0 = 0, 0
        for _, r in ipairs(rooms) do
            for _, q in ipairs(r.iq or {}) do
                if (tonumber(q) or -1) >= 4 then q4 = q4 + 1 end
                if (tonumber(q) or -1) == 0 then q0 = q0 + 1 end
            end
        end

        w("")
        w(string.format("── 局 #%d  id=%s  res=%s  base=%.2f final=%.2f  floors=%d rooms=%d  Q4=%d Q0=%d",
            store.index[ri].seq or ri, tostring(run.id), hl.resultName(run.res),
            tonumber(run.base) or 0, tonumber(run.final) or 0,
            #(run.floors or {}), #rooms, q4, q0))
        w(string.format("   %s",
            "F/idx 型 形  战力进→出  Δ          停留   受伤 敌 清 首  药 金弹钥(进→出)      六维(伤/攻/弹/程/移/运 进→出)                        道具(Q)"))

        for _, r in ipairs(rooms) do
            local itxt = {}
            for k = 1, #(r.it or {}) do
                itxt[#itxt + 1] = string.format("%d(Q%s)", r.it[k], tostring((r.iq or {})[k] or "?"))
            end
            w(string.format(
                "  F%-2d %-3d %-2d %-2d %7.2f→%7.2f %+8.2f %6.1fs %3d %2d %s %s  %d/%d/%d→%d/%d/%d  %5.2f/%4.2f/%4.2f/%4.2f/%4.2f/%5.2f → %5.2f/%4.2f/%4.2f/%4.2f/%4.2f/%5.2f  %s%s",
                tonumber(r.f) or 0, tonumber(r.i) or 0, tonumber(r.t) or 0, tonumber(r.s) or 0,
                tonumber(r.p) or 0, tonumber(r.po) or 0, (tonumber(r.po) or 0) - (tonumber(r.p) or 0),
                (tonumber(r.ms) or 0) / 1000, tonumber(r.dmg) or 0, tonumber(r.foes) or 0,
                (r.clr and "清" or "  "), (r.first and "首" or "  "),
                tonumber(r.c) or 0, tonumber(r.bmb) or 0, tonumber(r.key) or 0,
                tonumber(r.co) or 0, tonumber(r.bmbo) or 0, tonumber(r.keyo) or 0,
                tonumber(r.dv) or 0, tonumber(r.tso) or 0, tonumber(r.sso) or 0,
                (tonumber(r.rgo) or 0) / 40, tonumber(r.mvo) or 0, tonumber(r.lko) or 0,
                tonumber(r.dvo) or 0, tonumber(r.ts) or 0, tonumber(r.ss) or 0,
                (tonumber(r.rg) or 0) / 40, tonumber(r.mv) or 0, tonumber(r.lk) or 0,
                (#itxt > 0) and table.concat(itxt, ",") or "",
                (tonumber(r.ub) or 0) ~= 0 and (" UB=" .. r.ub) or ""))
        end
    end
end

local body = table.concat(out, "\n")
local stamp = (os and os.date and os.date("%Y%m%d-%H%M%S")) or "now"
local path = ROOT .. "_logs/rooms-" .. stamp .. ".txt"
local f = io.open(path, "wb")
if f then f:write(body); f:close() end
return "OK 写出 " .. path
