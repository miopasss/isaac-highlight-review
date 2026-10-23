-- =============================================================================
-- power_forms_test.lua —— 特殊形态 / 倍数合成 的离线单测（不启动游戏）
--   C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -NoProfile ^
--     -ExecutionPolicy Bypass -File tools\luarun.ps1 tests\power_forms_test.lua
-- =============================================================================
local ROOT = (os and os.getenv and os.getenv("HLR_ROOT")) or "D:/00000/aiStudy/issacmod/"
if ROOT:sub(-1) ~= "/" then ROOT = ROOT .. "/" end

local function loadmod(path)
    local chunk, err = loadfile(ROOT .. path)
    if not chunk then error("loadfile failed: " .. tostring(err)) end
    return chunk()
end

local pf    = loadmod("mod-review/core/power_forms.lua")
local power = loadmod("mod-review/core/power.lua")

local fails = 0
local function check(name, got, want, tol)
    tol = tol or 0.05
    local ok = type(got) == "number" and math.abs(got - want) <= tol
    print(string.format("  %-28s %8.3f  期望 %8.3f  %s",
        name, (type(got) == "number" and got) or -1, want, ok and "ok" or "<-- FAIL"))
    if not ok then fails = fails + 1 end
end

print("== 基线 ==")
check("空手", pf.output({ damage = 3.5, maxFireDelay = 10 }), 9.5455)

-- 与旧 power.lua 对齐（普通泪弹必须一模一样）
local s0 = { damage = 5.19, maxFireDelay = 7, numTearsAvg = 1 }
check("与 power.output 一致", pf.output(s0), power.output(s0), 0.001)

print("== 形态 ==")
check("硫磺火 A 档(delay32)", pf.output({ damage = 3.5, maxFireDelay = 32, form = "brimstone" }), 18.2)
check("硫磺火 ×2 光束",       pf.output({ damage = 3.5, maxFireDelay = 32, form = "brimstone", numTearsAvg = 2 }), 36.4)
check("妈刀(chargeFill .8)",   pf.output({ damage = 3.5, maxFireDelay = 10, form = "momsknife" }), 49.6)
check("妈刀(满蓄力)",          pf.output({ damage = 3.5, maxFireDelay = 10, form = "momsknife", chargeFill = 1.0 }), 57.3)
check("巧克力牛奶",            pf.output({ damage = 3.5, maxFireDelay = 10, form = "chocomilk" }), 30.7)
check("博士(delay26.5)",       pf.output({ damage = 3.5, maxFireDelay = 26.5, form = "drfetus" }), 38.2)
check("史诗婴儿",              pf.output({ damage = 3.5, maxFireDelay = 10, form = "epicfetus" }), 46.7)
check("Ludo",                  pf.output({ damage = 3.5, maxFireDelay = 10, form = "ludovico" }), 9.55)
check("Tech X",                pf.output({ damage = 3.5, maxFireDelay = 10, form = "techx" }), 20.2)
check("灵剑",                  pf.output({ damage = 3.5, maxFireDelay = 10, form = "spirsword" }), 38.2)

print("== 道具乘区 ==")
check("死眼 ×1.91",  pf.output({ damage = 3.5, maxFireDelay = 10, mult = 1.91 }), 18.2)
check("书虫 ×1.5",   pf.output({ damage = 3.5, maxFireDelay = 10, mult = 1.5 }), 14.3)
check("宝宝套 ×1.5", pf.output({ damage = 3.5, maxFireDelay = 10, mult = 1.5 }), 14.3)

print("== 宝宝倍数（只当倍率，不做加法）==")
check("Incubus 单独 1.75×",  pf.output({ damage = 3.5, maxFireDelay = 10, family = { "incubus" } }), 16.70)
check("双生宝单独 1.75×",     pf.output({ damage = 3.5, maxFireDelay = 10, family = { "twisted_pair" } }), 16.70)
check("Incubus+双生宝 2.5×",  pf.output({ damage = 3.5, maxFireDelay = 10, family = { "incubus", "twisted_pair" } }), 23.86)
check("Succubus 不再单独乘（面板已含）", pf.output({ damage = 3.5, maxFireDelay = 10, family = { "incubus", "succubus" } }), 16.70)
check("宝宝套 + 双宝宝 3.75×",  pf.output({ damage = 3.5, maxFireDelay = 10,
    mult = 1.5, family = { "incubus", "twisted_pair", "succubus" } }), 35.80)

print("== 附加固定 DPS ==")
check("Tech.5 +8.75", pf.output({ damage = 3.5, maxFireDelay = 10, addDps = 8.75 }), 18.30)

-- ── 幸运概率（公式锚点直接对 EID 的注释）──────────────────────────────
print("== 幸运公式锚点 ==")
check("安眠药 luck0 = 10%",  pf.luckP("knockout", 0) * 100, 10)
check("安眠药 luck9 = 100%", pf.luckP("knockout", 9) * 100, 100)
check("圣光 luck0 = 10%",    pf.luckP("holy_light", 0) * 100, 10)
check("圣光 luck9 = 50%",    pf.luckP("holy_light", 9) * 100, 50)
check("安乐死 luck0 = 3.33%", pf.luckP("euthanasia", 0) * 100, 3.333)
check("安乐死 luck13 = 25%",  pf.luckP("euthanasia", 13) * 100, 25)
check("小魔角 luck0 = 5%",    pf.luckP("little_horn", 0) * 100, 5)
check("小魔角 luck15 = 20%",  pf.luckP("little_horn", 15) * 100, 20)
check("严厉的爱 luck9 = 100%", pf.luckP("tough_love", 9) * 100, 100)
check("妈妈的眼睛 luck5 = 100%", pf.luckP("moms_eye", 5) * 100, 100)
    check("鸟眼椒 luck0 = 8.33%",  pf.luckP("birdseye", 0) * 100, 8.333)
    check("鸟眼椒 luck10 = 50%",   pf.luckP("birdseye", 10) * 100, 50)
    check("断魂椒 luck0 = 8.33%",  pf.luckP("ghostpepper", 0) * 100, 8.333)
    check("断魂椒 luck10 = 50%",   pf.luckP("ghostpepper", 10) * 100, 50)
check("洛基之角 luck15 = 100%", pf.luckP("loki_horns", 15) * 100, 100)

print("== 幸运对战力 ==")
-- 圣光 luck0：p=0.1，3x → ×(1+0.1×2)=1.2
check("圣光 luck0 ×1.2",  pf.output({ damage = 3.5, maxFireDelay = 10, luck = 0, luckItems = { "holy_light" } }), 11.45)
-- 圣光 luck9：p=0.5 → ×2.0
check("圣光 luck9 ×2.0",  pf.output({ damage = 3.5, maxFireDelay = 10, luck = 9, luckItems = { "holy_light" } }), 19.09)
-- 小魔角 luck0：p=0.05，+36 固定 → +0.05×36×2.727 = +4.91
check("小魔角 luck0 +4.91", pf.output({ damage = 3.5, maxFireDelay = 10, luck = 0, luckItems = { "little_horn" } }), 14.45)
-- 安眠药：flat=0，不影响
check("安眠药 不影响 DPS",  pf.output({ damage = 3.5, maxFireDelay = 10, luck = 9, luckItems = { "knockout" } }), 9.5455)
-- 多个幸运道具叠乘
check("圣光+安乐死 luck0",  pf.output({ damage = 3.5, maxFireDelay = 10, luck = 0,
    luckItems = { "holy_light", "euthanasia" } }), 9.5455 * 1.2 * (1 + 0.03333 * 2))

print("== 幸运随 run 变化（不是常数）==")
-- 同一件道具，luck 变了战力就该变（这是合法跳变，不是噪声）
local p0 = pf.output({ damage = 3.5, maxFireDelay = 10, luck = 0, luckItems = { "holy_light" } })
local p9 = pf.output({ damage = 3.5, maxFireDelay = 10, luck = 9, luckItems = { "holy_light" } })
check("圣光 luck0→9 涨 1.667 倍", p9 / p0, 19.091 / 11.455)
-- 负幸运：概率降，但不会变负
check("圣光 luck-5 = 6.67%",   pf.luckP("holy_light", -5) * 100, 6.667)
check("妈妈的眼睛 luck-2 = 30%", pf.luckP("moms_eye", -2) * 100, 30)
check("妈妈的眼睛 luck-10 钳 0", pf.luckP("moms_eye", -10) * 100, 0)
-- 没有吃幸运的道具时，luck 怎么变都不该动
check("无幸运道具 luck99 = 不变",
    pf.output({ damage = 3.5, maxFireDelay = 10, luck = 99 }), 9.5455)

print("== BFFS!（247）：家人伤害 ×2 ==")
check("Incubus + BFFS = 2.50×", pf.output({ damage = 3.5, maxFireDelay = 10,
    family = { "incubus" }, bffs = true }), 23.86)
check("双生宝 + BFFS = 2.50×", pf.output({ damage = 3.5, maxFireDelay = 10,
    family = { "twisted_pair" }, bffs = true }), 23.86)
check("两件 + BFFS = 4.00×", pf.output({ damage = 3.5, maxFireDelay = 10,
    family = { "incubus", "twisted_pair" }, bffs = true }), 38.18)
check("Succubus 不影响宝宝倍数（不吃 BFFS）", pf.output({ damage = 3.5, maxFireDelay = 10,
    family = { "succubus" }, bffs = true }), 9.5455)
check("无宝宝时 BFFS 无效", pf.output({ damage = 3.5, maxFireDelay = 10, bffs = true }), 9.5455)

print("== 莉莉丝特判（Incubus/双生宝 0.75 → 1.00）==")
check("莉莉丝 Incubus = 2.00×", pf.output({ damage = 3.5, maxFireDelay = 10,
    family = { "incubus" }, lilith = true }), 19.09)
check("莉莉丝 双生宝 = 2.00×", pf.output({ damage = 3.5, maxFireDelay = 10,
    family = { "twisted_pair" }, lilith = true }), 19.09)
check("莉莉丝 + BFFS = 3.00×", pf.output({ damage = 3.5, maxFireDelay = 10,
    family = { "incubus" }, lilith = true, bffs = true }), 28.64)
check("莉莉丝 Succubus 也不变", pf.output({ damage = 3.5, maxFireDelay = 10,
    family = { "succubus" }, lilith = true }), 9.5455)

print("== 边界 ==")
check("空表 → 0",        pf.output({}), 0)
check("未知形态回落 tears", pf.output({ damage = 3.5, maxFireDelay = 10, form = "???" }), 9.5455)
check("宝宝表为空 → ×1",  pf.familyMult(nil), 1)
check("未知宝宝 → 不计",  pf.familyMult({ "nope" }), 1)

print("")
if fails == 0 then print("全部通过 ✓") else print(fails .. " 项失败") end
os.exit(fails == 0 and 0 or 1)
