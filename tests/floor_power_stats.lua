-- =============================================================================
-- floor_power_stats.lua —— 「每层怪物血量 / 每房怪数 / 通关所需战力」的离线统计
--
-- 用途：把回顾 mod 的真实存档（<游戏>/data/highlight-review/save*.dat）+ 本机现成的
--       entities2.xml（mod 的 + 游戏根 content/ 的）统计成一张分析底稿，供
--       docs/FLOOR_POWER.md 引用。**只读**：不写存档、不碰 mod 代码、不启动游戏。
--
-- 运行：
--   C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -NoProfile ^
--     -ExecutionPolicy Bypass -File tools\luarun.ps1 tests\floor_power_stats.lua
--
-- 输出：_logs/floor-power-<时间戳>.txt（UTF-8，无 BOM）
--
-- 设计纪律（对应 docs/FLOOR_POWER.md §5 的「局限」）：
--   1. 所有数字都从文件算出来；算不出来的一律写「样本不足」，不猜。
--   2. foes 没有非零样本就明确标 0 样本，绝不把 0 当「这间房没怪」。
--   3. baseHP 只统计文件里真有 baseHP>0 的实体，并标注它来自哪个 mod。
--   4. 均值会被极端值带偏（游戏中挂机/暂停、mod 怪血量 9999999），所以均值/中位/
--      截尾均值/分位数一起给，报告里以中位为主。
-- =============================================================================

local ROOT = "D:/00000/aiStudy/issacmod/"
local DATA = nil
do
    local f = io.open(ROOT .. "_logs/.hlr_paths.lua", "rb")
    if f then
        local s = f:read("*a"); f:close()
        local chunk = load(s)
        local t = chunk and chunk()
        if t and t.root then ROOT = t.root end
        if t and t.data then DATA = t.data end
    end
end
if ROOT:sub(-1) ~= "/" then ROOT = ROOT .. "/" end
if not DATA then
    return "ERR: 读不到 _logs/.hlr_paths.lua，请用 tools/luarun.ps1 运行"
end
if DATA:sub(-1) ~= "/" then DATA = DATA .. "/" end

-- 游戏根目录：<game>/data/highlight-review/ -> <game>/
local GAME = DATA:match("^(.-)/data/highlight%-review/?$")
if not GAME then return "ERR: 无法从 DATA 反推游戏目录：" .. DATA end

local schema = loadfile(ROOT .. "mod-review/core/schema.lua")()
local fmt    = loadfile(ROOT .. "mod-review/core/fmt.lua")()
fmt.setSchema(schema)

-- ============================================================== 通用小工具
local function readAll(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end

local function sortedCopy(a)
    local b = {}
    for i = 1, #a do b[i] = a[i] end
    table.sort(b)
    return b
end

--- 线性插值分位数（sorted 必须是已排序数组）
local function pct(sorted, q)
    local n = #sorted
    if n == 0 then return nil end
    if n == 1 then return sorted[1] end
    local x = (n - 1) * q + 1
    local i = math.floor(x)
    local frac = x - i
    if i >= n then return sorted[n] end
    return sorted[i] + (sorted[i + 1] - sorted[i]) * frac
end

--- 一组数的常用统计量。均值被极端值带偏时用 tmean（去掉上下各 1%）
local function statsOf(vals)
    local n = #vals
    if n == 0 then return { n = 0 } end
    local sum = 0
    for i = 1, n do sum = sum + vals[i] end
    local sorted = sortedCopy(vals)
    local lo = math.floor(n * 0.01) + 1
    local hi = n - math.floor(n * 0.01)
    if hi < lo then lo, hi = 1, n end
    local tsum, tn = 0, 0
    for i = lo, hi do tsum = tsum + sorted[i]; tn = tn + 1 end
    return {
        n = n, mean = sum / n, tmean = tsum / math.max(1, tn),
        min = sorted[1], max = sorted[n],
        p10 = pct(sorted, 0.10), p25 = pct(sorted, 0.25),
        med = pct(sorted, 0.50),
        p75 = pct(sorted, 0.75), p90 = pct(sorted, 0.90), p95 = pct(sorted, 0.95),
        p99 = pct(sorted, 0.99),
    }
end

local function f1(v) if v == nil then return "  -  " end return string.format("%5.1f", v) end
local function f2(v) if v == nil then return "  -  " end return string.format("%6.2f", v) end

--- 只保留「首次进房」的记录（回访房间会把 dmg/ms 拉低、把房间数放大）。
--- 万一这一批记录没有 first 标记（老存档），退回用全部，避免整层变空。
local function firstOnly(list)
    local out = {}
    for _, r in ipairs(list) do if r.first then out[#out + 1] = r end end
    if #out == 0 then return list end
    return out
end

-- ============================================================== 输出缓冲
local out = {}
local function w(s) out[#out + 1] = tostring(s) end
local function wf(fmtstr, ...) out[#out + 1] = string.format(fmtstr, ...) end
local function head(title) w(""); w(string.rep("=", 112)); w(title); w(string.rep("=", 112)) end

-- ============================================================== 枚举（真文件）
-- 名字直接从游戏 resources/scripts/enums.lua 里抠，避免手写枚举写错。
-- 坑：LevelStage 表里后面有 STAGE1_GREED=1 这类**别名**，同值会覆盖前面的正经名字
--     （第一版就踩了，f=2 显示成 STAGE2_GREED）。所以：同名值只认第一次出现，
--     并且跳过 _GREED / NUM_ / _NULL 这些非楼层名。
local roomTypeName, levelStageName, stageTypeName = {}, {}, {}
do
    local txt = readAll(GAME .. "/resources/scripts/enums.lua")
    if txt then
        local function grab(tableName, skipPat)
            local body = txt:match("\n" .. tableName .. "%s*=%s*(%b{})")
            local map = {}
            if body then
                for k, v in body:gmatch("([%u_%d]+)%s*=%s*([%-%d]+)") do
                    local num = tonumber(v)
                    local skip = (skipPat and k:find(skipPat)) or false
                    if num and not skip and map[num] == nil then map[num] = k end
                end
            end
            return map
        end
        roomTypeName   = grab("RoomType",   "NUM_")
        levelStageName = grab("LevelStage", "_GREED")   -- NUM_/STAGE_NULL 见下
        stageTypeName  = grab("StageType",  "NUM_")
        for k, v in pairs(levelStageName) do
            if v:find("NUM_") or v == "STAGE_NULL" then levelStageName[k] = nil end
        end
    end
end
local function roomTypeLabel(t)
    local n = roomTypeName[t]
    return n and (n:gsub("^ROOM_", "")) or ("?" .. tostring(t))
end
local function stageLabel(st)
    local n = levelStageName[st]
    return n and (n:gsub("^STAGE_?[%w]*_?", "")) or ("?" .. tostring(st))
end
local function stageTypeLabel(st)
    local n = stageTypeName[st]
    return n and (n:gsub("^STAGETYPE_", "")) or ("?" .. tostring(st))
end

-- ============================================================== 1) 读存档
local SOURCES = {
    { key = "save1",   path = DATA .. "save1.dat",        primary = true,  label = "save1.dat" },
    { key = "save3",   path = DATA .. "save3.dat",        primary = true,  label = "save3.dat" },
    { key = "archive", path = ROOT .. "_archive/all.dat", primary = false, label = "_archive/all.dat" },
}

head("A) 数据源与规模")
wf("游戏目录 : %s", GAME)
wf("存档目录 : %s", DATA)
wf("枚举文件 : %s %s", GAME .. "/resources/scripts/enums.lua",
   (next(roomTypeName) and "（读到）" or "（读不到）"))
w("")
wf("%-18s %9s %7s %7s %6s %6s %7s %7s", "来源", "字节", "原始局", "去重局", "通关", "死亡", "未完成", "M 行")
local srcInfo = {}
for _, s in ipairs(SOURCES) do
    local blob = readAll(s.path)
    local info = { key = s.key, label = s.label, path = s.path, primary = s.primary }
    if not blob then
        info.exists = false
        wf("%-18s %9s %7s %7s %6s %6s %7s %7s", s.label, "-", "-", "-", "-", "-", "-", "-")
    else
        info.exists = true
        info.bytes = #blob
        local store, warns = fmt.splitBlob(blob)
        info.store = store
        info.warnCount = #(warns or {})
        -- 按种子去重（与 fmt.dedupe 同口径：种子优先，无种子按 id）
        local best, order = {}, {}
        for i = 1, #store.index do
            local e = store.index[i]
            local seed = tonumber(e.seed) or 0
            local key = (seed ~= 0) and ("s" .. seed) or ("i" .. tostring(e.id))
            local prev = best[key]
            if not prev then
                best[key] = e; order[#order + 1] = key
            elseif e.count > prev.count then
                best[key] = e
            end
        end
        info.uniqueRuns = #order
        info.rawRuns = #store.index
        local res = { [0] = 0, [1] = 0, [2] = 0 }
        for _, key in ipairs(order) do
            local r = tonumber(best[key].res) or 2
            res[r] = (res[r] or 0) + 1
        end
        info.res = res
        info.entries = best
        info.order = order
        local mlines = 0
        for i = 1, #store.lines do
            if store.lines[i]:sub(1, 2) == "M|" then mlines = mlines + 1 end
        end
        info.mlines = mlines
        wf("%-18s %9d %7d %7d %6d %6d %7d %7d",
            s.label, info.bytes, info.rawRuns, info.uniqueRuns,
            res[1] or 0, res[0] or 0, res[2] or 0, mlines)
    end
    srcInfo[#srcInfo + 1] = info
end

-- ============================================================== 2) 汇总
local function collect(sources, pred)
    local acc = {
        runs = 0, rooms = 0, roomsPerRun = {},
        byFloor = {},        -- [f] = { {p,po,dmg,ms,foes,t,clr,dv,ts,mu} ... }
        runFloors = {},      -- 每个 (局,层) 一条
        stageByFloor = {},   -- [f][ "stage/type" ] = 计数
        roomTypeCount = {},
        foesNonZero = 0,
        clearedRooms = 0,
        runMax = {}, resMax = {},
        ratios = {},         -- [f] = { minp/base ... }
        basePowers = {},
        slowRooms = 0,       -- ms > 300000 的房间数
        hugePower = {},      -- 战力 > 200 的房间（诊断用）
    }
    for _, info in ipairs(sources) do
        if info.exists then
            for _, key in ipairs(info.order) do
                local entry = info.entries[key]
                if pred(entry) then
                    local run = fmt.decodeRun(info.store, entry)
                    local rooms = run.rooms or {}
                    acc.runs = acc.runs + 1
                    acc.roomsPerRun[#acc.roomsPerRun + 1] = #rooms
                    acc.runMax[#acc.runMax + 1] = tonumber(run.max) or 0
                    local maxv = tonumber(run.max) or 0
                    acc.resMax[#acc.resMax + 1] = { res = tonumber(run.res) or 2, max = maxv, rooms = #rooms }
                    local base = tonumber(run.base) or 0
                    if base > 0 then acc.basePowers[#acc.basePowers + 1] = base end

                    local floorMeta = {}
                    local runSeq = tonumber(entry.seq) or 0
                    acc.runList = acc.runList or {}
                    acc.runList[#acc.runList + 1] = {
                        seq = runSeq, res = tonumber(run.res) or 2,
                        max = tonumber(run.max) or 0, rooms = #rooms,
                        base = tonumber(run.base) or 0, final = tonumber(run.final) or 0,
                        floors = #(run.floors or {}),
                    }
                    for fi, fl in ipairs(run.floors or {}) do
                        local depth = tonumber(fl.i) or fi
                        floorMeta[depth] = fl
                        acc.stageByFloor[depth] = acc.stageByFloor[depth] or {}
                        local stKey = string.format("%d/%d", tonumber(fl.stage) or 0, tonumber(fl.type) or 0)
                        acc.stageByFloor[depth][stKey] = (acc.stageByFloor[depth][stKey] or 0) + 1
                    end

                    local perFloor = {}
                    for _, r in ipairs(rooms) do
                        local f = tonumber(r.f) or 0
                        if f >= 1 then
                            acc.rooms = acc.rooms + 1
                            local foes = tonumber(r.foes) or 0
                            if foes > 0 then acc.foesNonZero = acc.foesNonZero + 1 end
                            local ms = tonumber(r.ms) or 0
                            if ms > 300000 then acc.slowRooms = acc.slowRooms + 1 end
                            local rec = {
                                p = tonumber(r.p) or 0, po = tonumber(r.po) or 0,
                                dmg = tonumber(r.dmg) or 0, ms = ms,
                                foes = foes, t = tonumber(r.t) or 0, f = f,
                                s = tonumber(r.s) or 0, d = tonumber(r.d) or 0,
                                st = tonumber(r.st) or 0, v = tonumber(r.v) or 0,
                                list = tonumber(r.list) or 0,
                                seq = runSeq,
                                first = r.first and true or false,
                                clr = r.clr and true or false,
                                dv = tonumber(r.dv) or 0, ts = tonumber(r.ts) or 0,
                                mu = tonumber(r.mu) or 1,
                                fm = tostring(r.fm or ""),
                            }
                            if rec.clr then acc.clearedRooms = acc.clearedRooms + 1 end
                            acc.byFloor[f] = acc.byFloor[f] or {}
                            table.insert(acc.byFloor[f], rec)
                            perFloor[f] = perFloor[f] or {}
                            table.insert(perFloor[f], rec)
                            acc.roomTypeCount[rec.t] = (acc.roomTypeCount[rec.t] or 0) + 1
                            if rec.p > 200 then acc.hugePower[#acc.hugePower + 1] = rec end
                        end
                    end

                    for f, list in pairs(perFloor) do
                        -- 只统计「首次进房」：回访房间基本是清完再走一遍（无战斗、无伤害），
                        -- 会把 dmg/ms 拉低，还会把「每层房间数」放大 2~3 倍。
                        local firsts = {}
                        local keys, nUniq = {}, 0
                        local minp, maxpo, summs, sumdmg = math.huge, -math.huge, 0, 0
                        local nClear, nBossFirst = 0, 0
                        for _, r in ipairs(list) do
                            if r.first then
                                firsts[#firsts + 1] = r
                                if r.p < minp then minp = r.p end
                                if r.po > maxpo then maxpo = r.po end
                                summs = summs + r.ms
                                sumdmg = sumdmg + r.dmg
                                if r.clr then nClear = nClear + 1 end
                                if r.t == 5 then nBossFirst = nBossFirst + 1 end
                            end
                        end
                        for _, r in ipairs(firsts) do
                            -- 房间身份：房型/形状/门位/StageID/Variant/ListIndex
                            local key = string.format("%d/%d/%d/%d/%d/%d",
                                r.t, r.s, r.d, r.st, r.v, r.list)
                            if not keys[key] then keys[key] = true; nUniq = nUniq + 1 end
                        end
                        local fm = floorMeta[f]
                        acc.runFloors[#acc.runFloors + 1] = {
                            f = f, seq = runSeq,
                            minp = (minp == math.huge) and 0 or minp,
                            maxpo = (maxpo == -math.huge) and 0 or maxpo,
                            nrooms = #list, nFirst = #firsts, nUniq = nUniq, nClear = nClear,
                            nBossFirst = nBossFirst,
                            ms = summs, dmg = sumdmg,
                            stage = fm and (tonumber(fm.stage) or 0) or 0,
                            stype = fm and (tonumber(fm.type) or 0) or 0,
                            floorMs = fm and (tonumber(fm.ms) or 0) or 0,
                        }
                        if base > 0 and minp ~= math.huge then
                            acc.ratios[f] = acc.ratios[f] or {}
                            table.insert(acc.ratios[f], minp / base)
                        end
                    end
                end
            end
        end
    end
    return acc
end

local primarySources = {}
for _, info in ipairs(srcInfo) do if info.primary then primarySources[#primarySources + 1] = info end end
-- 三套口径：
--   ALL   = 一切记录（含 12 局「只进了 1 层就退出」的短局）
--   CLEAR = res==1 通关局（其中仍有 4 局是短局，会稀释 f=1/2）
--   LONG  = res==1 且到达 ≥5 层的「真长局」—— 每层统计以这套为主
local ALL   = collect(primarySources, function() return true end)
local CLEAR = collect(primarySources, function(e) return tonumber(e.res) == 1 end)
local LONG  = collect(primarySources, function(e)
    return tonumber(e.res) == 1 and (tonumber(e.max) or 0) >= 5
end)

local function maxFloor(acc)
    local m = 0
    for f in pairs(acc.byFloor) do if f > m then m = f end end
    return m
end

head("B) 数据概览（主口径 = save1 + save3，按种子去重）")
wf("全部局：%d 局 / %d 间房", ALL.runs, ALL.rooms)
wf("通关局（res==1）：%d 局 / %d 间房（占全部房间 %.1f%%）",
   CLEAR.runs, CLEAR.rooms, ALL.rooms > 0 and (100 * CLEAR.rooms / ALL.rooms) or 0)
wf("长局（res==1 且 max>=5）：%d 局 / %d 间房  ← 每层统计的推荐口径",
   LONG.runs, LONG.rooms)
wf("清过房的房间数（clr=true）：全部 %d / %d（%.1f%%）",
   ALL.clearedRooms, ALL.rooms, ALL.rooms > 0 and (100 * ALL.clearedRooms / ALL.rooms) or 0)
wf("foes 非零样本：全部局 %d / %d（%.2f%%），通关局 %d / %d  → %s",
   ALL.foesNonZero, ALL.rooms, ALL.rooms > 0 and (100 * ALL.foesNonZero / ALL.rooms) or 0,
   CLEAR.foesNonZero, CLEAR.rooms,
   (ALL.foesNonZero == 0) and "**字段不可用（0 样本）**" or "可用")
wf("最大层序数 f：全部局 %d，通关局 %d", maxFloor(ALL), maxFloor(CLEAR))
wf("慢房（单房 ms>300s，疑似挂机/暂停）：%d 间", ALL.slowRooms)

w("")
w("res × max 交叉表（全部局）：")
wf("  %-14s %s", "res\\max", " 1   2   3   4   5   6   7   8   9  10")
for _, res in ipairs({ 1, 0, 2 }) do
    local row = {}
    for f = 1, 10 do row[f] = 0 end
    for _, t in ipairs(ALL.resMax) do
        if t.res == res and t.max >= 1 and t.max <= 10 then row[t.max] = row[t.max] + 1 end
    end
    local cells = {}
    for f = 1, 10 do cells[#cells + 1] = string.format("%2d", row[f]) end
    local name = (res == 1) and "通关" or (res == 0 and "死亡" or "未完成")
    wf("  %-14s %s", string.format("res=%d(%s)", res, name), table.concat(cells, "  "))
end

local rpr = statsOf(ALL.roomsPerRun)
wf("每局房间数：n=%d 中位=%.0f P25=%.0f P75=%.0f 最大=%.0f",
   rpr.n, rpr.med or 0, rpr.p25 or 0, rpr.p75 or 0, rpr.max or 0)
local bp = statsOf(ALL.basePowers)
wf("开局战力 base：n=%d 中位=%.2f 区间 %.2f~%.2f", bp.n, bp.med or 0, bp.min or 0, bp.max or 0)

-- ============================================================== 3) 每层主表
head("C) 每层统计表（f = 局内层序数，与 mod 册子上的 Floor N 同源）")
w("列：n=房间数 foesNZ=foes>0 样本 ms=停留毫秒（清房即停，含非战斗房） dmg=本房受伤（半心）")
w("    p中位=该层所有房间的进房战力中位 p_in=每「局·层」min(p) 的中位（近似进层战力）")
w("    p_out=每「局·层」max(po) 的中位（近似出层战力） 倍率=p_in/该局 base 的中位")
w("")
local function floorTable(acc, title)
    w("── " .. title)
    wf("%3s %6s %6s %6s %8s %8s %8s %7s %6s %7s %7s %7s %7s %7s %6s %-16s",
       "f", "进房n", "首访n", "慢房", "ms中位", "ms_P90", "dmg均值", "dmg中位",
       "零伤%", "p_P25", "p中位", "p_P75", "p_in中位", "p_out中位", "倍率", "stage/type")
    for f = 1, maxFloor(acc) do
        local all = acc.byFloor[f] or {}
        local n = #all
        local list = firstOnly(all)
        if n == 0 then
            wf("%3d %6d   （无样本）", f, 0)
        else
            local msv, dmgv, pv = {}, {}, {}
            local zero, foesNZ, slow = 0, 0, 0
            for _, r in ipairs(list) do
                msv[#msv + 1] = r.ms
                dmgv[#dmgv + 1] = r.dmg
                pv[#pv + 1] = r.p
                if r.dmg == 0 then zero = zero + 1 end
                if r.foes > 0 then foesNZ = foesNZ + 1 end
                if r.ms > 300000 then slow = slow + 1 end
            end
            local msS, dmgS, pS = statsOf(msv), statsOf(dmgv), statsOf(pv)
            local inps, outps = {}, {}
            for _, rf in ipairs(acc.runFloors) do
                if rf.f == f then
                    inps[#inps + 1] = rf.minp
                    outps[#outps + 1] = rf.maxpo
                end
            end
            local inS, outS = statsOf(inps), statsOf(outps)
            local ratioS = statsOf(acc.ratios[f] or {})
            -- 记录到的 stage/type 前 2 名
            local hist = acc.stageByFloor[f] or {}
            local arr = {}
            for k, c in pairs(hist) do arr[#arr + 1] = { k = k, c = c } end
            table.sort(arr, function(a, b) return a.c > b.c end)
            local sp = {}
            for i = 1, math.min(2, #arr) do sp[#sp + 1] = string.format("%s x%d", arr[i].k, arr[i].c) end
            wf("%3d %6d %6d %6d %8.0f %8.0f %8.2f %7.1f %5.0f%% %7s %7s %7s %7s %7s %6s %-16s",
                f, n, #list, slow, msS.med, msS.p90, dmgS.mean, dmgS.med,
                100 * zero / #list, f2(pS.p25), f2(pS.med), f2(pS.p75), f2(inS.med), f2(outS.med),
                ratioS.med and string.format("%.1fx", ratioS.med) or "-",
                table.concat(sp, " "))
        end
    end
    w("")
end
floorTable(ALL, "全部局（含死亡 / 未完成 / 短局）")
floorTable(CLEAR, "只通关局（res==1）")
floorTable(LONG, "只长局（res==1 且 max>=5）← 推荐口径")

-- 层段完整性：一个真实楼层只会有一个「首访 Boss 房」。若某段里首访 Boss 房 ≥2，
-- 说明这段 f 其实卷了 ≥2 个真实楼层（mod 的层计数器在模组环境下会漏记换层）。
head("C2) 层段完整性诊断（每层是否真的是「一层」）")
w("判据：一个真实楼层只有一个 Boss 房 → 同一段 f 里出现 ≥2 个「首访 Boss 房」= 这一段卷了多层。")
wf("%3s %6s %8s %8s %10s %12s", "f", "段数", "并段数", "占比", "首访房中位", "干净段首访房")
for f = 1, maxFloor(LONG) do
    local segs, merged, firstN, cleanN = 0, 0, {}, {}
    for _, rf in ipairs(LONG.runFloors) do
        if rf.f == f then
            segs = segs + 1
            firstN[#firstN + 1] = rf.nFirst
            if (rf.nBossFirst or 0) >= 2 then
                merged = merged + 1
            else
                cleanN[#cleanN + 1] = rf.nFirst
            end
        end
    end
    local aS, cS = statsOf(firstN), statsOf(cleanN)
    wf("%3d %6d %8d %7.0f%% %10.1f %12s", f, segs, merged,
       segs > 0 and (100 * merged / segs) or 0, aS.med or 0, f1(cS.med))
end
local totSeg, totMerged = 0, 0
for _, rf in ipairs(LONG.runFloors) do
    totSeg = totSeg + 1
    if (rf.nBossFirst or 0) >= 2 then totMerged = totMerged + 1 end
end
wf("合计：%d 段，其中并段 %d（%.0f%%）", totSeg, totMerged, totSeg > 0 and 100 * totMerged / totSeg or 0)

-- ============================================================== 4) 口径 A 原料
head("D) 口径 A 原料：每层按「进房战力 p」三分位后的受伤/时长（长局）")
w("读法：如果高战力组受伤更低、时长更短，说明存在「够用」的战力门槛。")
w("")
wf("%3s %-4s %5s %8s %8s %7s %8s %-22s", "f", "组", "n", "dmg均值", "零伤%", "ms中位", "ms_P25", "p 区间")
for f = 1, maxFloor(LONG) do
    local list = firstOnly(LONG.byFloor[f] or {})
    local n = #list
    if n >= 12 then
        local copy = {}
        for i = 1, n do copy[i] = list[i] end
        table.sort(copy, function(a, b) return a.p < b.p end)
        local cut1, cut2 = math.floor(n / 3), math.floor(2 * n / 3)
        for gi, g in ipairs({ { "低", 1, cut1 }, { "中", cut1 + 1, cut2 }, { "高", cut2 + 1, n } }) do
            local dm, msv, zero = {}, {}, 0
            local pmin, pmax = math.huge, -math.huge
            for i = g[2], g[3] do
                dm[#dm + 1] = copy[i].dmg
                msv[#msv + 1] = copy[i].ms
                if copy[i].dmg == 0 then zero = zero + 1 end
                if copy[i].p < pmin then pmin = copy[i].p end
                if copy[i].p > pmax then pmax = copy[i].p end
            end
            local dS, mS = statsOf(dm), statsOf(msv)
            wf("%3d %-4s %5d %8.2f %7.0f%% %8.0f %8.0f %7.2f ~ %-7.2f",
                f, g[1], #dm, dS.mean, 100 * zero / #dm, mS.med, mS.p25, pmin, pmax)
        end
    else
        wf("%3d %-4s %5d   （样本不足 n<12）", f, "-", n)
    end
end

w("")
w("零伤房 vs 受伤房（进房战力对比）：")
wf("%3s %7s %8s %8s %8s %8s %8s %8s", "f", "零伤n", "零伤p中位", "受伤n", "受伤p中位",
   "零伤ms中位", "受伤ms中位", "受伤房占%")
for f = 1, maxFloor(LONG) do
    local list = firstOnly(LONG.byFloor[f] or {})
    local zp, dp, zms, dms = {}, {}, {}, {}
    for _, r in ipairs(list) do
        if r.dmg == 0 then
            zp[#zp + 1] = r.p; zms[#zms + 1] = r.ms
        else
            dp[#dp + 1] = r.p; dms[#dms + 1] = r.ms
        end
    end
    local zS, dS, zmS, dmS = statsOf(zp), statsOf(dp), statsOf(zms), statsOf(dms)
    local share = (#zp + #dp) > 0 and (100 * #dp / (#zp + #dp)) or 0
    wf("%3d %7d %9s %8d %9s %9s %9s %7.0f%%", f, #zp, f2(zS.med), #dp, f2(dS.med),
       f1(zmS.med), f1(dmS.med), share)
end

w("")
w("口径 A 舒适战力带：只看「真清过房且零伤」（dmg==0 且 clr）的房间 —— 这是玩家在实战里")
w("                 没挨打的战力区间；同时给该层全部房间的 p 分位做对照。")
wf("%3s %8s %8s %8s %8s %8s %10s %8s %-22s", "f", "零伤清房n", "p_P10", "p_P25", "p中位",
   "p_P75", "受伤房p中位", "全部房n", "舒适带（P25~P75）")
local comfortRows = {}
for f = 1, maxFloor(LONG) do
    local list = firstOnly(LONG.byFloor[f] or {})
    local n = #list
    local zeroSafe, hurt, allpv = {}, {}, {}
    for _, r in ipairs(list) do
        allpv[#allpv + 1] = r.p
        if r.dmg == 0 and r.clr then
            zeroSafe[#zeroSafe + 1] = r.p
        elseif r.dmg > 0 then
            hurt[#hurt + 1] = r.p
        end
    end
    local zS, hS, aS = statsOf(zeroSafe), statsOf(hurt), statsOf(allpv)
    if zS.n >= 20 then
        wf("%3d %8d %8s %8s %8s %8s %10s %8d %-22s", f, zS.n,
           f2(zS.p10), f2(zS.p25), f2(zS.med), f2(zS.p75),
           hS.n > 0 and f2(hS.med) or "-", n,
           string.format("%.1f ~ %.1f", zS.p25 or 0, zS.p75 or 0))
        comfortRows[f] = { lo = zS.p25, p50 = zS.med, hi = zS.p75, p90 = aS.p90, n = zS.n }
    else
        wf("%3d %8d   （零伤清房样本不足 n<20）", f, zS.n)
        comfortRows[f] = nil
    end
end
w("")
w("（舒适带含义：样本里「清房且没挨打」的房间，其进房战力有 50% 落在 P25~P75 之间。")
w("  它是**观测区间**，不是「低于这个就必伤」的物理门槛 —— 数据里受伤与战力没有单调关系，见上表。）")


w("")
w("每「局·层」的整层数据（中位）：房间ms合计=该层所有房间的 ms 之和；层计时=mod 记的整层 ms（首层缺层记录，故为 0）")
wf("%3s %6s %12s %10s %10s %10s %10s", "f", "局层n", "房间ms合计s", "层计时s", "整层受伤", "整层房间数", "清房数")
for f = 1, maxFloor(LONG) do
    local ms, fms, dm, nr, nc = {}, {}, {}, {}, {}
    for _, rf in ipairs(LONG.runFloors) do
        if rf.f == f then
            ms[#ms + 1] = rf.ms
            if rf.floorMs > 0 then fms[#fms + 1] = rf.floorMs end
            dm[#dm + 1] = rf.dmg
            nr[#nr + 1] = rf.nrooms
            nc[#nc + 1] = rf.nClear
        end
    end
    local msS, fmsS, dmS, nrS, ncS = statsOf(ms), statsOf(fms), statsOf(dm), statsOf(nr), statsOf(nc)
    wf("%3d %6d %12.0f %10s %10.1f %10.1f %10.1f", f, msS.n,
       (msS.med or 0) / 1000, fmsS.med and string.format("%.0f", fmsS.med / 1000) or "-",
       dmS.med or 0, nrS.med or 0, ncS.med or 0)
end

-- ============================================================== 5) 战力尺度诊断
head("E) 战力口径核对（战力 ≠ 单发面板 DPS，它含乘区/宝宝/附加）")
w("采集用的是 core/power_forms.lua 的新口径：POWER = 伤害 × 射速 × 形态系数 × 道具乘区 × 宝宝倍数")
w("（乘区按满命中假设，例如死眼 1.91、书虫 1.5、宝宝套 1.5），失败才退回 power.lua 的旧口径。")
w("所以「战力」= 整队等效 DPS，会明显大于 dv×ts（单发面板 DPS）。")
w("")
local allP = {}
for f = 1, maxFloor(LONG) do
    for _, r in ipairs(firstOnly(LONG.byFloor[f] or {})) do allP[#allP + 1] = r.p end
end
local pS = statsOf(allP)
wf("长局房间进房战力：n=%d 中位=%.2f P10=%.2f P25=%.2f P75=%.2f P90=%.2f P99=%.2f 最大=%.2f",
   pS.n, pS.med, pS.p10, pS.p25, pS.p75, pS.p90, pS.p99, pS.max)
w("")
local formCount = {}
for f = 1, maxFloor(LONG) do
    for _, r in ipairs(firstOnly(LONG.byFloor[f] or {})) do
        formCount[r.fm] = (formCount[r.fm] or 0) + 1
    end
end
local fc = {}
for k, c in pairs(formCount) do fc[#fc + 1] = { k = k, c = c } end
table.sort(fc, function(a, b) return a.c > b.c end)
local fparts = {}
for i = 1, math.min(8, #fc) do
    fparts[#fparts + 1] = string.format("%s=%d", (fc[i].k == "") and "?" or fc[i].k, fc[i].c)
end
w("攻击形态分布：" .. table.concat(fparts, "  "))
w("")
w("战力 > 200 的房间抽样（dv=面板伤害 ts=30/(延迟+1) mu=弹幕数 p=战力）：")
local cnt = 0
for _, r in ipairs(LONG.hugePower) do
    if cnt >= 10 then break end
    cnt = cnt + 1
    wf("   f=%-2d %-10s dv=%7.2f ts=%5.2f mu=%2d p=%8.2f  dv*ts=%7.2f  p/(dv*ts)=%5.2fx",
       r.f, (r.fm == "") and "?" or r.fm, r.dv, r.ts, r.mu, r.p, r.dv * r.ts,
       (r.dv * r.ts > 0) and (r.p / (r.dv * r.ts)) or 0)
end
-- 按层统计 dv/ts
w("")
wf("%3s %8s %8s %8s %8s %8s %8s", "f", "dv中位", "ts中位", "mu中位", "p中位", "dv*ts中位", "p/(dv*ts)")
for f = 1, maxFloor(LONG) do
    local dv, ts, mu, pp, chk = {}, {}, {}, {}, {}
    for _, r in ipairs(firstOnly(LONG.byFloor[f] or {})) do
        dv[#dv + 1] = r.dv; ts[#ts + 1] = r.ts; mu[#mu + 1] = r.mu
        pp[#pp + 1] = r.p; chk[#chk + 1] = r.dv * r.ts
    end
    local a, b, c, d, e = statsOf(dv), statsOf(ts), statsOf(mu), statsOf(pp), statsOf(chk)
    wf("%3d %8.2f %8.2f %8.1f %8.2f %8.2f %8.2fx", f, a.med or 0, b.med or 0, c.med or 0,
       d.med or 0, e.med or 0, (e.med and e.med > 0) and ((d.med or 0) / e.med) or 0)
end

-- ============================================================== 6) entities2.xml
head("F) 敌人血量：本机所有可读的 entities2.xml")
w("原版 resources/entities2.xml 被打包进 resources/packed/*.a（压缩/加密），本地不可读；")
w("这里统计的是 **mod 目录** 里的明文 entities2.xml（+ 游戏根 content/entities2.xml）。")
w("")
local xmlPaths = {}
do
    local function popenLines(cmd)
        if not io.popen then return {} end
        local p = io.popen(cmd)
        if not p then return {} end
        local s = p:read("*a"); p:close()
        local list = {}
        for line in tostring(s):gmatch("[^\r\n]+") do
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if #line > 0 then list[#list + 1] = line end
        end
        return list
    end
    local modsDir = GAME:gsub("/", "\\") .. "\\mods"
    for _, p in ipairs(popenLines('dir /b /s "' .. modsDir .. '\\entities2.xml" 2>nul')) do
        xmlPaths[#xmlPaths + 1] = { path = (p:gsub("\\", "/")), kind = "mod" }
    end
    local rootXml = GAME .. "/content/entities2.xml"
    if readAll(rootXml) then xmlPaths[#xmlPaths + 1] = { path = rootXml, kind = "game-content" } end
end

local function parseEntities(text)
    local list = {}
    for attrText in text:gmatch("<entity%s([^>]*)>") do
        local e = {}
        for k, v in attrText:gmatch('([%w_]+)%s*=%s*"([^"]*)"') do e[k] = v end
        e.hp = tonumber(e.baseHP or "")
        list[#list + 1] = e
    end
    return list
end

local allHP, normalHP, bossHP = {}, {}, {}
local perFile, entsTotal, idLowHits = {}, 0, 0
for _, x in ipairs(xmlPaths) do
    local txt = readAll(x.path)
    if txt then
        local ents = parseEntities(txt)
        entsTotal = entsTotal + #ents
        local withHP, bosses = 0, 0
        local shortName = x.path:match("([^/]+)/content/entities2%.[Xx][Mm][Ll]$") or x.path
        for _, e in ipairs(ents) do
            local isBoss = (e.boss == "1")
            if isBoss then bosses = bosses + 1 end
            if e.hp and e.hp > 0 then
                withHP = withHP + 1
                allHP[#allHP + 1] = e.hp
                if isBoss then bossHP[#bossHP + 1] = e.hp else normalHP[#normalHP + 1] = e.hp end
                local idn = tonumber(e.id or "")
                if idn and idn >= 10 and idn <= 799 then idLowHits = idLowHits + 1 end
            end
        end
        perFile[#perFile + 1] = { name = shortName, ents = #ents, withHP = withHP, bosses = bosses }
    end
end

wf("扫到 %d 个 entities2.xml；实体合计 %d 个，其中 baseHP>0 的 %d 个（普通 %d / boss %d）",
   #xmlPaths, entsTotal, #allHP, #normalHP, #bossHP)
wf("id 落在原版 id 段（10~799）的 baseHP>0 实体：%d 个（值是 mod 改写的，不等于原版数值）", idLowHits)
w("")
wf("%-42s %6s %8s %8s", "文件", "实体", "baseHP>0", "boss=1")
for _, pf in ipairs(perFile) do
    wf("%-42s %6d %8d %8d", pf.name, pf.ents, pf.withHP, pf.bosses)
end
w("")
local function hpDist(list, label)
    local S = statsOf(list)
    if S.n == 0 then wf("%-8s 样本不足", label); return end
    wf("%-8s n=%-5d 均值=%.1f 截尾均值=%.1f 中位=%.1f P25=%.1f P75=%.1f P90=%.1f P99=%.0f 最大=%.0f",
        label, S.n, S.mean, S.tmean, S.med, S.p25, S.p75, S.p90, S.p99, S.max)
    -- 区间是 (lo, hi]：hp 可能是 6 这种整数值，用 v>=lo 会把边界值算重
    local bins = {
        { 0, 5, "≤5" }, { 5, 10, "6-10" }, { 10, 20, "11-20" }, { 20, 30, "21-30" },
        { 30, 50, "31-50" }, { 50, 80, "51-80" }, { 80, 150, "81-150" },
        { 150, 300, "151-300" }, { 300, 1000, "301-1000" }, { 1000, math.huge, ">1000" },
    }
    local parts = {}
    for _, b in ipairs(bins) do
        local c = 0
        for _, v in ipairs(list) do if v > b[1] and v <= b[2] then c = c + 1 end end
        parts[#parts + 1] = string.format("%s:%d", b[3], c)
    end
    w("         直方图 " .. table.concat(parts, "  "))
end
hpDist(allHP, "全体")
hpDist(normalHP, "普通怪")
hpDist(bossHP, "Boss")

w("")
w("哨兵值说明：mod 文件里存在 9999 / 999999 / 9999999 这种「不可杀/占位」血量，会把均值彻底带偏。")
w("下面把 hp ≥ 1000 的当哨兵剔除，只看「可杀」的那部分：")
local function filterHP(list, limit)
    local t = {}
    for _, v in ipairs(list) do if v < limit then t[#t + 1] = v end end
    return t
end
local saneAll, saneNormal, saneBoss = filterHP(allHP, 1000), filterHP(normalHP, 1000), filterHP(bossHP, 1000)
wf("%-8s n=%-5d 均值=%.1f 中位=%.1f P25=%.1f P75=%.1f P90=%.1f 最大=%.0f  （剔掉 %d 个）",
   "全体", #saneAll, (statsOf(saneAll).mean or 0), (statsOf(saneAll).med or 0),
   (statsOf(saneAll).p25 or 0), (statsOf(saneAll).p75 or 0), (statsOf(saneAll).p90 or 0),
   (statsOf(saneAll).max or 0), #allHP - #saneAll)
wf("%-8s n=%-5d 均值=%.1f 中位=%.1f P25=%.1f P75=%.1f P90=%.1f 最大=%.0f  （剔掉 %d 个）",
   "普通怪", #saneNormal, (statsOf(saneNormal).mean or 0), (statsOf(saneNormal).med or 0),
   (statsOf(saneNormal).p25 or 0), (statsOf(saneNormal).p75 or 0), (statsOf(saneNormal).p90 or 0),
   (statsOf(saneNormal).max or 0), #normalHP - #saneNormal)
wf("%-8s n=%-5d 均值=%.1f 中位=%.1f P25=%.1f P75=%.1f P90=%.1f 最大=%.0f  （剔掉 %d 个）",
   "Boss", #saneBoss, (statsOf(saneBoss).mean or 0), (statsOf(saneBoss).med or 0),
   (statsOf(saneBoss).p25 or 0), (statsOf(saneBoss).p75 or 0), (statsOf(saneBoss).p90 or 0),
   (statsOf(saneBoss).max or 0), #bossHP - #saneBoss)

-- ============================================================== 7) 口径 B 原料
head("G) 口径 B 原料：每层「零伤清房时长」+ 反推的每房总血量")
w("口径 B 公式：需要战力 ≈ 每房怪数 × 平均怪血 ÷ 每房击杀时间（战力≈DPS）。")
w("「每房怪数」存档里没有（foes 全 0），这里给两样**算得出来**的东西：")
w("  1) 零伤且清房（dmg==0 且 clr）的时长分布 —— 作为「每房击杀时间」的实测值")
w("  2) 隐含每房总血量 = 该层 p 中位 × 该层零伤清房时长（假设 100% 命中/无走位，是上界）")
w("")
wf("%3s %8s %10s %10s %10s %10s %12s", "f", "零伤清房n", "ms中位", "ms_P25", "ms_P75",
   "p中位", "隐含每房血量")
local fastByFloor = {}
for f = 1, maxFloor(LONG) do
    local fast, pv = {}, {}
    for _, r in ipairs(firstOnly(LONG.byFloor[f] or {})) do
        pv[#pv + 1] = r.p
        if r.dmg == 0 and r.clr and r.ms > 0 then fast[#fast + 1] = r.ms end
    end
    local fS, pS2 = statsOf(fast), statsOf(pv)
    fastByFloor[f] = { n = fS.n, med = fS.med, p25 = fS.p25, p75 = fS.p75, pmed = pS2.med }
    local implied = (fS.med and pS2.med) and (pS2.med * fS.med / 1000) or nil
    wf("%3d %8d %10s %10s %10s %10s %12s", f, fS.n, f1(fS.med), f1(fS.p25), f1(fS.p75),
       f2(pS2.med), implied and string.format("%.0f HP", implied) or "-")
end
w("")
w("敏感性表：需要多少战力（=DPS）才能在「零伤清房时长」内打掉 N 只怪 / 每只 H 血（N、H 是假设值，非数据）")
wf("%3s %8s %12s %12s %12s %12s", "f", "清房时长s",
   "N=3,H=20", "N=5,H=20", "N=5,H=35", "N=7,H=60")
for f = 1, maxFloor(LONG) do
    local x = fastByFloor[f]
    if x and x.med then
        local t = x.med / 1000
        wf("%3d %8.1f %12.1f %12.1f %12.1f %12.1f", f, t,
           3 * 20 / t, 5 * 20 / t, 5 * 35 / t, 7 * 60 / t)
    else
        wf("%3d   （样本不足）", f)
    end
end

-- ============================================================== 8) 房间类型
head("H) 房间类型构成（全部局）")
local tk = {}
for t, c in pairs(ALL.roomTypeCount) do tk[#tk + 1] = { t = t, c = c } end
table.sort(tk, function(a, b) return a.c > b.c end)
for _, x in ipairs(tk) do
    wf("%-16s (%2d) %6d 间 %5.1f%%", roomTypeLabel(x.t), x.t, x.c,
        ALL.rooms > 0 and (100 * x.c / ALL.rooms) or 0)
end

-- ============================================================== 9) 明细
head("I) 明细：长局的每一局（解释 f=9/f=10 的样本为什么那么薄）")
wf("%5s %5s %5s %6s %6s %9s %9s", "seq", "res", "max", "房间", "层记录", "base", "final")
for _, r in ipairs(LONG.runList or {}) do
    wf("%5d %5d %5d %6d %6d %9.2f %9.2f", r.seq, r.res, r.max, r.rooms, r.floors, r.base, r.final)
end
w("")
w("只列 f>=8 的 (局·层) 明细：")
wf("%3s %5s %6s %9s %9s %8s %8s %8s", "f", "seq", "房间", "min(p)", "max(po)", "清房", "受伤", "房间ms合计s")
for f = 8, maxFloor(LONG) do
    for _, rf in ipairs(LONG.runFloors) do
        if rf.f == f then
            wf("%3d %5d %6d %9.2f %9.2f %8d %8.0f %8.0f", f, rf.seq, rf.nrooms,
               rf.minp, rf.maxpo, rf.nClear, rf.dmg, rf.ms / 1000)
        end
    end
end

-- ============================================================== 落盘
local body = table.concat(out, "\n")
local stamp = (os and os.date and os.date("%Y%m%d-%H%M%S")) or "now"
local path = ROOT .. "_logs/floor-power-" .. stamp .. ".txt"
local fh = io.open(path, "wb")
if not fh then return "ERR: 写不出 " .. path end
fh:write(body)
fh:close()

return string.format(
    "OK runs(clear)=%d/%d rooms(clear)=%d/%d foesNZ=%d hpEntities=%d boss=%d -> %s",
    CLEAR.runs, ALL.runs, CLEAR.rooms, ALL.rooms, ALL.foesNonZero, #allHP, #bossHP, path)
