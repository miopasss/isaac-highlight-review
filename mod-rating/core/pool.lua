-- ============================================================================
-- pool.lua —— 按"权重倍数"影响道具出现频率
--
-- 设计约束（见 CHANGELOG / DESIGN.md E31）：
--   · 原版权重是"每池各一份"，所以我们的覆盖是**倍数**，不是绝对值
--   · 不删除任何池子条目，不调用 RemoveCollectible
--   · 只用 MC_POST_GET_COLLECTIBLE 做"抽完重掷"，照抄 Revelations 的成熟做法
--   · 随机数必须从回调给的 seed 派生，否则破坏种子可复现性
--
-- v1 只实现"降低/禁用"（mul < 1）。"提高"留到 v2：
--   提高需要改变抽签分布，POST 阶段只能靠"没抽中时强行替换"，
--   会绕过 NO!/神圣宝珠等内建逻辑，风险高，先不做。
-- ============================================================================
local P = {}

P.snap      = {}     -- [poolType] = { [id] = weight }   局开头快照
P.hasSnap   = false
P.inCallback = false
P.maxRetry  = 16    -- 2026-10-29：4 次太少（小池子反复抽到同一件），提到 16
P.warnedUp  = false  -- "提高权重未实现"只警告一次
P.stats     = { reRolled = 0, banned = 0, gaveUp = 0 }

--- 读一个池子的全部条目（每个条目带 itemID / weight）
local function readPool(poolType)
    local ok, list = pcall(function()
        return Game():GetItemPool():GetCollectiblesFromPool(poolType)
    end)
    if ok and type(list) == "table" then return list end
    return nil
end

--- 局开头快照：把每个池子的初始权重存下来，供编辑器显示
--- 返回成功快照的池子数量
function P.snapshot(poolTypes)
    P.snap, P.hasSnap = {}, false
    local n = 0
    for _, t in ipairs(poolTypes or {}) do
        local list = readPool(t)
        if list then
            local m = {}
            for i = 1, #list do
                local e = list[i]
                local id, w = tonumber(e.itemID), tonumber(e.weight)
                if id and w and w > 0 then m[id] = w end
            end
            if next(m) then P.snap[t] = m; n = n + 1 end
        end
    end
    P.hasSnap = (n > 0)
    return n
end

--- 反查：某道具在各池子里的（快照）权重 —— 编辑器用
--- 返回 { {pool = t, weight = w}, ... }
function P.poolsOf(id)
    local out = {}
    for t, m in pairs(P.snap) do
        if m[id] then out[#out + 1] = { pool = t, weight = m[id] } end
    end
    table.sort(out, function(a, b) return a.pool < b.pool end)
    return out
end

--- 某道具是否在任何池子里
function P.inAnyPool(id)
    if not P.hasSnap then return nil end   -- 未知
    for _, m in pairs(P.snap) do
        if m[id] then return true end
    end
    return false
end

--- MC_POST_GET_COLLECTIBLE 的处理函数。
--- 参数与回调一致：(itemID, poolType, decrease, seed)
--- 返回：替换后的 id，或 nil 表示不改。
--- 纯决策函数（无引擎依赖，可离线单测）
--- @param mul number|nil  配置的权重倍数（nil = 没配置）
--- @param roll number    [0,1) 的掷点
--- @return string "skip"（不干预）/ "keep"（保留原道具）/ "reroll"（重掷）
function P.decide(mul, roll)
    if mul == nil then return "skip" end
    if mul >= 1 then return "skip" end          -- 只有 < 1 生效（> 1 的加权 v1 未实现）
    local m = math.max(0, math.min(1, mul))
    local chance = 1 - m                        -- 进入重掷的概率
    if (roll or 0) >= chance then return "keep" end
    return "reroll"
end

--- 纯函数：兜底伪随机（同 seed 可复现）
function P.fallbackRoll(seed)
    local x = (seed * 1103515245 + 12345) % 2147483648
    return (x % 10000) / 10000
end

function P.onPostGet(ratings, itemID, poolType, decrease, seed, log)
    -- 防重入：下面会再调一次 pool:GetCollectible()，那会再次触发本回调
    if P.inCallback then return nil end

    if not itemID or itemID <= 0 then return nil end
    -- 探针：只记录"被配置过"的道具被抽到的时刻（这类才是我们真正会干预的）
    do
        local m0 = ratings.getWeightMul(itemID)
        if m0 ~= nil and log then
            log(string.format("[POOL] 抽到受控道具 id=%d pool=%s 倍数=%.2f", itemID, tostring(poolType), m0))
        end
    end
    local mul = ratings.getWeightMul(itemID)
    if mul == nil then return nil end              -- 没配置：完全不动
    -- 埋点（2026-10-28）：权重 <= 0 = 该道具应被完全禁掉。每次抽到都打一行，
    -- 后面无论重掷成功还是放弃，都能从日志定性"池子给的"还是"别处给的"。
    if mul <= 0 and log then
        log(string.format("[BAN] 抽到禁止道具 id=%d pool=%s → 尝试重掷", itemID, tostring(poolType)))
    end

    if mul >= 1 then
        if mul > 1 and not P.warnedUp and log then
            P.warnedUp = true
            log("[POOL] 权重 > 1（提高出现率）v1 未实现，只有 < 1 生效")
        end
        return nil
    end

    local s = tonumber(seed) or 0

    -- 随机数用回调给的 seed 派生，保证种子可复现
    local rng
    local fallbackRoll = P.fallbackRoll   -- 纯 Lua 兜底（可单测）

    local okRng, r = pcall(function() return RNG(s) end)
    if not okRng or not r then
        if log then log(string.format("[POOL] RNG 不可用 id=%d seed=%s → 用纯 Lua 兜底随机", itemID, tostring(s))) end
        r = nil
    end
    rng = r
    pcall(function() rng:SetSeed(s, 35) end)

    local chance = 1 - math.max(0, math.min(1, mul))
    -- 2026-10-30：这个构建里 RNG 的浮点方法是 RandomFloat()，不是 NextFloat()！
    -- 之前只调 NextFloat → pcall 失败 → 静默 return nil → 权重从未生效过。
    local okRoll, roll = false, nil
    if rng then
        okRoll, roll = pcall(function() return rng:RandomFloat() end)
        if not okRoll or not roll then
            okRoll, roll = pcall(function() return rng:NextFloat() end)
        end
    end
    if not okRoll or not roll then
        roll = fallbackRoll(s)
        if log then log(string.format("[POOL] 引擎 RNG 取数失败，用兜底随机 id=%d 掷出=%.3f", itemID, roll)) end
    end
    if log then
        log(string.format("[POOL] 判定 id=%d pool=%s 倍数=%.2f 掷出=%.3f 阈值=%.3f（掷出≥阈值=保留）",
            itemID, tostring(poolType), mul, roll, chance))
    end
    -- 判定交给纯函数（离线单测覆盖 "skip"/"keep"/"reroll" 三个分支）
    if P.decide(mul, roll) == "keep" then
        -- 埋点（2026-10-29）：明确记录"保留了原道具"。没有这行时，权重 0.1 的道具被保留后
        -- 日志一片空白，分不清是"保留"还是"根本没进回调"。
        if log then
            log(string.format("[POOL] 保留 id=%d pool=%s（倍数 %.2f，保留概率 %.0f%%，掷出 %.2f）",
                itemID, tostring(poolType), mul, (1 - chance) * 100, roll))
        end
        return nil                                  -- 这次保留原结果
    end

    -- 重掷：换成同池子的别的道具，最多试几次
    local pool = Game():GetItemPool()
    P.inCallback = true
    local result = nil
    for i = 1, P.maxRetry do
        -- 2026-10-29：原来的 s + i*7919 步长固定，容易反复命中同一个 id。
          -- 改成 LCG 混合（仍完全由 s 决定 → 种子可复现），每次落点更散。
            local newSeed = (s * 1103515245 + i * 12345 + 7919) % 2147483647
        local ok, alt = pcall(function()
            return pool:GetCollectible(poolType, false, newSeed)
        end)
        if ok and alt and alt > 0 and alt ~= itemID then
            local altMul = ratings.getWeightMul(alt)
            -- 新抽到的道具如果也被配置成更小的权重，别换过去
            if altMul == nil or altMul >= mul then
                result = alt
                break
            end
        end
    end
    P.inCallback = false

    if result then
        -- 验证用日志：权重是否真的在改抽签结果（每局最多 30 行，避免刷屏）
        P.logged = (P.logged or 0) + 1
        if log and P.logged <= 30 then
            log(string.format("[POOL] 重掷成功 %d -> %d  （倍数 %.2f）", itemID, result, mul))
        end
        P.stats.reRolled = P.stats.reRolled + 1
        if mul <= 0 then P.stats.banned = P.stats.banned + 1 end
        return result
    end
    P.stats.gaveUp = P.stats.gaveUp + 1
    -- 埋点（2026-10-28）：重掷失败 = 原道具会照样发出，必须留证据
    if log then
        log(string.format("[BAN] 重掷失败 id=%d pool=%s（试了 %d 次没换到）→ 原道具保留",
            itemID, tostring(poolType), P.maxRetry))
    end
    return nil
end

-- Isaac 的物品池枚举：0..NUM_ITEMPOOLS-1。这里给一份常用池子
-- （快照用；数量随版本变化，多给几个无碍）
P.COMMON_POOLS = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
    20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
}

return P
