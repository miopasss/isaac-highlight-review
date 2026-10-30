-- ============================================================================
-- pool_test.lua —— 权重拦截决策的离线单测
--
-- 测的是**纯函数**（不碰引擎）：
--   P.decide(mul, roll)     → "skip" / "keep" / "reroll"
--   P.fallbackRoll(seed)    → [0,1) 的伪随机，同 seed 可复现
--
-- 为什么单独抽出来：2026-10-30 发现「权重从未生效」的 bug 是因为
-- rng:NextFloat() 这个方法根本不存在，而失败被 pcall 静默吞掉。
-- 决策逻辑本身可以离线验证，引擎调用只能靠开局自检（POOL_SELFTEST）。
-- ============================================================================

local ROOT = "D:/00000/aiStudy/issacmod/"
local pool = loadfile(ROOT .. "mod-rating/core/pool.lua")()

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then
        pass = pass + 1
    else
        fail = fail + 1
        print("  FAIL: " .. tostring(msg))
    end
end
local function eq(actual, expected, msg)
    ok(actual == expected, string.format("%s  期望=%s 实际=%s", msg, tostring(expected), tostring(actual)))
end

print("== P.decide ==")

-- 分支 1：没配置 → 不干预
eq(pool.decide(nil, 0.0), "skip", "没配置(mul=nil) → skip")
eq(pool.decide(nil, 0.99), "skip", "没配置时掷点无关 → skip")

-- 分支 2：权重 >= 1 → 不干预（提高出现率 v1 未实现）
eq(pool.decide(1.0, 0.0), "skip", "mul=1 → skip")
eq(pool.decide(1.0, 0.99), "skip", "mul=1 掷点无关 → skip")
eq(pool.decide(2.0, 0.0), "skip", "mul=2（>1 未实现）→ skip")
eq(pool.decide(999, 0.5), "skip", "mul=999 → skip")

-- 分支 3：权重 0 → 必定重掷（chance=1，roll<1 恒成立）
eq(pool.decide(0.0, 0.0), "reroll", "mul=0 掷点 0 → reroll")
eq(pool.decide(0.0, 0.5), "reroll", "mul=0 掷点 0.5 → reroll")
eq(pool.decide(0.0, 0.999), "reroll", "mul=0 掷点 0.999 → reroll")

-- 分支 4：权重 0.1 → chance=0.9，掷点 < 0.9 重掷、>= 0.9 保留
eq(pool.decide(0.1, 0.0), "reroll", "mul=0.1 掷点 0.0 → reroll")
eq(pool.decide(0.1, 0.5), "reroll", "mul=0.1 掷点 0.5 → reroll")
eq(pool.decide(0.1, 0.899), "reroll", "mul=0.1 掷点 0.899（边界内侧）→ reroll")
eq(pool.decide(0.1, 0.9), "keep", "mul=0.1 掷点 0.9（边界）→ keep")
eq(pool.decide(0.1, 0.99), "keep", "mul=0.1 掷点 0.99 → keep")

-- 分支 5：权重 0.5 → chance=0.5
eq(pool.decide(0.5, 0.49), "reroll", "mul=0.5 掷点 0.49 → reroll")
eq(pool.decide(0.5, 0.5), "keep", "mul=0.5 掷点 0.5（边界）→ keep")
eq(pool.decide(0.5, 0.51), "keep", "mul=0.5 掷点 0.51 → keep")

-- 分支 6：负权重按 0 处理（不该出现，但不能崩）
eq(pool.decide(-1, 0.5), "reroll", "mul=-1 按 0 处理 → reroll")

-- 分支 7：roll 为 nil 时按 0 处理（防御）
eq(pool.decide(0.1, nil), "reroll", "roll=nil 按 0 → reroll")
eq(pool.decide(0.0, nil), "reroll", "roll=nil mul=0 → reroll")

print("== P.fallbackRoll ==")

-- 分支 8：范围 [0,1)
local bad = 0
for seed = 1, 500 do
    local r = pool.fallbackRoll(seed)
    if type(r) ~= "number" or r < 0 or r >= 1 then bad = bad + 1 end
end
eq(bad, 0, "fallbackRoll(1..500) 全部落在 [0,1)")

-- 分支 9：同 seed 可复现
eq(pool.fallbackRoll(12345), pool.fallbackRoll(12345), "同 seed 结果一致")
ok(pool.fallbackRoll(12345) ~= pool.fallbackRoll(54321), "不同 seed 结果不同")

-- 分支 10：分布大致均匀（1000 个 seed，均值应在 0.5 附近）
local sum = 0
for seed = 1, 1000 do sum = sum + pool.fallbackRoll(seed) end
local mean = sum / 1000
ok(mean > 0.35 and mean < 0.65, string.format("fallbackRoll 均值 %.3f 在 0.35~0.65 之间", mean))

-- 分支 11：极端 seed 不崩
ok(type(pool.fallbackRoll(0)) == "number", "seed=0 有返回值")
ok(type(pool.fallbackRoll(2147483647)) == "number", "seed=INT_MAX 有返回值")

print("== P.rollFor ==")

-- 分支 12：范围与来源（现在固定走纯 Lua）
local srcBad, rangeBad = 0, 0
for seed = 1, 300 do
    local v, src = pool.rollFor(seed)
    if src ~= "lua" then srcBad = srcBad + 1 end
    if type(v) ~= "number" or v < 0 or v >= 1 then rangeBad = rangeBad + 1 end
end
eq(srcBad, 0, "rollFor 来源固定为 lua（引擎 RNG 实测不可用）")
eq(rangeBad, 0, "rollFor(1..300) 全部落在 [0,1)")

-- 分支 13：同 seed 复现、不同 seed 不同
eq(pool.rollFor(11111), pool.rollFor(11111), "rollFor 同 seed 可复现")
ok(pool.rollFor(11111) ~= pool.rollFor(22222), "rollFor 不同 seed 不同")

-- 分支 14：相邻种子不该单调（引擎 RNG 的毛病就是随 seed 单调）
local mono = 0
local prev = pool.rollFor(1)
for seed = 2, 100 do
    local cur = pool.rollFor(seed)
    if cur > prev then mono = mono + 1 end
    prev = cur
end
ok(mono > 20 and mono < 80, string.format("相邻种子非单调（上升 %d/99 次，应大致一半）", mono))

-- 分支 15：分布均匀（300 个种子的均值）
local s2 = 0
for seed = 1, 300 do s2 = s2 + pool.rollFor(seed) end
local m2 = s2 / 300
ok(m2 > 0.4 and m2 < 0.6, string.format("rollFor 均值 %.3f 在 0.4~0.6 之间", m2))

print("")
print(string.format("[pool_test] %d 通过 / %d 失败", pass, fail))
if fail > 0 then os.exit(1) end
