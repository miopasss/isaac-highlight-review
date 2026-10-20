-- =============================================================================
-- identity_test.lua —— 字段映射自检：构造一局已知数据，逐项断言"谁该出现在哪"
--
-- 目的：回答"高光页/楼层页显示的东西，对应的都是对的那个房间吗"
-- 运行：tools\luarun.ps1 tests\identity_test.lua
-- =============================================================================
local ROOT = (os and os.getenv and os.getenv("HLR_ROOT")) or "D:/00000/aiStudy/issacmod/"
if ROOT:sub(-1) ~= "/" then ROOT = ROOT .. "/" end
local function loadmod(p) return loadfile(ROOT .. p)() end

local hl = loadmod("mod/core/highlight.lua")

-- 构造：2 层 6 间房
--   层1：r1 普通(无道具) → r2 宝箱(拿 Q4 道具1，战力 10→20) → r3 Boss(拿 Q0 道具2，20→25)
--   层2：r4 普通 → r5 恶魔(拿 Q4 道具3，25→40) → r6 普通(拿 Q4 道具4，40→40)
local function room(f, i, t, p, po, dvIn, dvOut, it, iq, first, ub, clr)
    return {
        f = f, i = i, t = t, s = 1, p = p, po = po,
        dv = dvIn, dvo = dvOut,
        tso = 2.70, ts = 3.50, sso = 1.0, ss = 1.0,
        rgo = 6.4 * 40, rg = 6.4 * 40, mvo = 1.0, mv = 1.0, lko = 0, lk = 0,
        ms = 10000, dmg = 0, foes = 3, first = first,
        it = it or {}, iq = iq or {},
        ub = ub or 0, clr = clr and true or false,
    }
end

local run = {
    id = "TESTRUN-0", res = 0, max = 2, base = 10.0, final = 40.0,
    floors = {
        { i = 1, stage = 1, curse = 32 },   -- MAZE
        { i = 2, stage = 2, curse = 0 },
    },
    rooms = {
        room(1, 1, 1, 10, 10, 3.0, 3.0, {}, {}, true),
        room(2 - 1, 2, 4, 10, 20, 3.0, 6.0, { 1 }, { 4 }, true),
        room(1, 3, 5, 20, 25, 6.0, 6.0, { 2 }, { 0 }, true, 1, true),   -- Hush，已清房
        room(2, 1, 1, 25, 25, 6.0, 6.0, {}, {}, true),
        room(2, 2, 14, 25, 40, 6.0, 10.0, { 3 }, { 4 }, true),
        room(2, 3, 1, 40, 40, 10.0, 10.0, { 4 }, { 4 }, true, 3, false), -- 超级撒旦，没打完
    },
}

local bk = hl.analyze(run, { powerTopN = 3, q4MaxPages = 3 })

local pass, fail = 0, 0
local function check(name, cond, detail)
    if cond then pass = pass + 1
    else fail = fail + 1; print(string.format("  FAIL  %-42s  %s", name, tostring(detail))) end
end

print("== 亮点页 ==")
print("== 页面列表 ==")
for i, p in ipairs(bk.pages) do
    if p.kind == "finale" then
        print(string.format("  #%d  kind=finale  bosses=%d  q4=%d  q0=%d",
            i, #(p.bosses or {}), #(p.q4 or {}), #(p.q0 or {})))
    else
        print(string.format("  #%d  kind=%-6s rank=%d  Floor %d room %d  delta=%.2f",
            i, p.kind, p.rank, p.room.floor, p.room.idx, p.room.delta))
    end
end
print("")
print("")

-- 战力 Top3 必须按 delta 降序：r5(+15) > r2(+10) > r3(+5)
-- 页 1：终局页（总是第一页）
check("第1页是终局页", bk.pages[1].kind == "finale", bk.pages[1].kind)
check("终局页只有 1 个已清房的 Boss（Hush）", #bk.pages[1].bosses == 1, #bk.pages[1].bosses)
check("终局页 Boss 是 Hush(ub=1)", bk.pages[1].bosses[1] and bk.pages[1].bosses[1].ub == 1, "")
check("没打完的超级撒旦不收录", (bk.pages[1].bosses[1] and bk.pages[1].bosses[1].ub == 3) == false, "")
check("终局页四级道具 = {1,3,4}", #bk.pages[1].q4 == 3, #bk.pages[1].q4)
check("终局页零级道具 = {2}", #bk.pages[1].q0 == 1 and bk.pages[1].q0[1] == 2, #bk.pages[1].q0)

-- 页 2..4：战力 Top3（按 delta 降序 r5>r2>r3）
check("战力 Top1 = 层2第2间(恶魔房)", bk.pages[2].kind == "power" and bk.pages[2].room.floor == 2 and bk.pages[2].room.idx == 2, "")
check("战力 Top1 delta = 15", math.abs(bk.pages[2].room.delta - 15) < 1e-6, bk.pages[2].room.delta)
check("战力 Top2 = 层1第2间(宝箱房)", bk.pages[3].room.floor == 1 and bk.pages[3].room.idx == 2, "")
check("战力 Top3 = 层1第3间(Boss房)", bk.pages[4].room.floor == 1 and bk.pages[4].room.idx == 3, "")

print("== 楼层页 ==")
for _, f in ipairs(bk.floors) do
    local st = f.stats or {}
    print(string.format("  层%d  战力 %.2f > %.2f (%+.2f)  房间 %d  道具 %d  诅咒 %d  伤害 %.2f>%.2f",
        f.i, f.powerIn, f.powerOut, f.gain, f.rooms, #f.items, f.curse,
        st[1] and st[1].inV or -1, st[1] and st[1].outV or -1))
end
print("")

check("层1 战力进 = 10", math.abs(bk.floors[1].powerIn - 10) < 1e-6, bk.floors[1].powerIn)
check("层1 战力出 = 25", math.abs(bk.floors[1].powerOut - 25) < 1e-6, bk.floors[1].powerOut)
check("层1 增益 = +15", math.abs(bk.floors[1].gain - 15) < 1e-6, bk.floors[1].gain)
check("层1 诅咒 = 迷阵(32)", bk.floors[1].curse == 32, bk.floors[1].curse)
check("层1 道具 = {1,2}", #bk.floors[1].items == 2 and bk.floors[1].items[2] == 2, table.concat(bk.floors[1].items, ","))

-- 层六维：进 = 本层第一间的进房值(3.0)，出 = 本层最后一间的出房值(6.0)
check("层1 六维伤害 进 = 3.0", math.abs(bk.floors[1].stats[1].inV - 3.0) < 1e-6, bk.floors[1].stats[1].inV)
check("层1 六维伤害 出 = 6.0", math.abs(bk.floors[1].stats[1].outV - 6.0) < 1e-6, bk.floors[1].stats[1].outV)
check("层2 六维伤害 进 = 6.0", math.abs(bk.floors[2].stats[1].inV - 6.0) < 1e-6, bk.floors[2].stats[1].inV)
check("层2 六维伤害 出 = 10.0", math.abs(bk.floors[2].stats[1].outV - 10.0) < 1e-6, bk.floors[2].stats[1].outV)

-- 六维：射程有 1/40 缩放
check("射程按 /40 缩放（6.4 而不是 256）", math.abs(bk.floors[1].stats[4].outV - 6.4) < 1e-6, bk.floors[1].stats[4].outV)

print("")
print(string.format("结果：%d 通过 / %d 失败", pass, fail))
return pass .. "/" .. (pass + fail)
