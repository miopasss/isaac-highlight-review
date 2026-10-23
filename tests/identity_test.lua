-- =============================================================================
-- identity_test.lua —— 字段映射自检：构造一局已知数据，逐项断言"谁该出现在哪"
--
-- 目的：回答"高光页/楼层页显示的东西，对应的都是对的那个房间吗"
-- 运行：tools\luarun.ps1 tests\identity_test.lua
-- =============================================================================
local ROOT = (os and os.getenv and os.getenv("HLR_ROOT")) or "D:/00000/aiStudy/issacmod/"
if ROOT:sub(-1) ~= "/" then ROOT = ROOT .. "/" end
local function loadmod(p) return loadfile(ROOT .. p)() end

local hl = loadmod("mod-review/core/highlight.lua")

-- 构造：2 层 6 间房
--   层1：r1 普通(无道具) → r2 宝箱(拿 Q4 道具1，战力 10→20) → r3 Boss(拿 Q0 道具2，20→25)
--   层2：r4 普通 → r5 恶魔(拿 Q4 道具3，25→40) → r6 普通(拿 Q4 道具4，40→40)
local function room(f, i, t, p, po, dvIn, dvOut, it, iq, first, ub, clr, ie)
    return {
        f = f, i = i, t = t, s = 1, p = p, po = po,
        dv = dvIn, dvo = dvOut,
        tso = 2.70, ts = 3.50, sso = 1.0, ss = 1.0,
        rgo = 6.4 * 40, rg = 6.4 * 40, mvo = 1.0, mv = 1.0, lko = 0, lk = 0,
        ms = 10000, dmg = 0, foes = 3, first = first,
        it = it or {}, iq = iq or {}, ie = ie or {},
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
        room(2 - 1, 2, 4, 10, 20, 3.0, 6.0, { 1 }, { 4 }, true, nil, nil, { 10.0 }),
        room(1, 3, 5, 20, 25, 6.0, 6.0, { 2 }, { 0 }, true, 1, true),   -- Hush，已清房
        room(2, 1, 1, 25, 25, 6.0, 6.0, {}, {}, true),
        room(2, 2, 14, 25, 40, 6.0, 10.0, { 3 }, { 4 }, true),
        room(2, 3, 1, 40, 40, 10.0, 10.0, { 4 }, { 4 }, true, 3, false), -- 超级撒旦，没打完
    },
}

local testCfg = { powerTopN = 3, q4MaxPages = 3, jumpMin = 0.30, jumpTopN = 50, pagesPower = true }
local bk = hl.analyze(run, testCfg)

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
        print(string.format("  #%d  kind=%-6s rank=%s", i, tostring(p.kind), tostring(p.rank or "-")))
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

print("== 战力跃迁 ==")
check("跃迁页存在", (function()
    for i = 1, #bk.pages do if bk.pages[i].kind == "jumps" then return true end end
    return false
end)(), "no jumps page")
local jp
for i = 1, #bk.pages do if bk.pages[i].kind == "jumps" then jp = bk.pages[i] end end
check("跃迁事件数 = 1（只有那件 +10 的道具）", jp and #(jp.events or {}) == 1, jp and #(jp.events or {}))
check("跃迁事件 id 正确", jp and jp.events[1] and jp.events[1].id == 1, jp and jp.events[1] and jp.events[1].id)
check("跃迁增量 = 10.0", jp and jp.events[1] and math.abs(jp.events[1].delta - 10.0) < 0.01,
    jp and jp.events[1] and jp.events[1].delta)
print("")

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
print("== 飞行/防爆：必须'带得进下一间'才算拿到 ==")
-- 第 1 间踩白火飞了一下 → 下一间进门没飞 → 不算
-- 第 3 间拿到真飞行 → 第 4 间进门还在飞 → 确认为第 3 间
local rs = {
    { f = 1, i = 1, fli = false, fl = true  },
    { f = 1, i = 2, fli = false, fl = false },
    { f = 1, i = 3, fli = false, fl = true  },
    { f = 1, i = 4, fli = true,  fl = true  },
}
local gp = hl.gainPoint(rs, "fli", "fl")
check("临时飞行被丢掉，确认第 3 间", gp and gp.i == 3, gp and gp.i)
check("确认的层号正确", gp and gp.f == 1, gp and gp.f)

-- 最后一间没有"下一间"可确认 → 宁可漏记
check("最后一间不确认", hl.gainPoint({ { f = 2, i = 1, fli = false, fl = true } }, "fli", "fl") == nil)

-- 开局自带（第 1 间进门就会飞）不算"获得"
local rs3 = {
    { f = 1, i = 1, fli = true, fl = true },
    { f = 1, i = 2, fli = true, fl = true },
}
check("开局自带 → 无获得点", hl.gainPoint(rs3, "fli", "fl") == nil)

-- 防爆走同一套逻辑
local rs4 = {
    { f = 3, i = 1, exi = false, ex = false },
    { f = 3, i = 2, exi = false, ex = true  },
    { f = 3, i = 3, exi = true,  ex = true  },
}
local ge = hl.gainPoint(rs4, "exi", "ex")
check("防爆确认第 2 间", ge and ge.i == 2, ge and ge.i)

print("")
print(string.format("结果：%d 通过 / %d 失败", pass, fail))
return pass .. "/" .. (pass + fail)
