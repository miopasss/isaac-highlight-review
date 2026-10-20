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
P.maxRetry  = 4
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
function P.onPostGet(ratings, itemID, poolType, decrease, seed, log)
    if not itemID or itemID <= 0 then return nil end
    local mul = ratings.getWeightMul(itemID)
    if mul == nil then return nil end          -- 没配置：完全不动
    if mul >= 1 then
        if mul > 1 and not P.warnedUp and log then
            P.warnedUp = true
            log("[POOL] 权重 > 1（提高出现率）v1 未实现，只有 < 1 生效")
        end
        return nil
    end
    if mul <= 0 then
        -- 禁用：必重掷
    end

    -- POST 阶段：以 (1 - mul) 的概率重掷
    local rng = RNG()
    rng:SetSeed(seed or 0, 35)

    local chance = 1 - math.max(0, math.min(1, mul))
    if rng:NextFloat() >= chance then return nil end   -- 这次保留原结果

    -- 重掷：换成同池子的别的道具，最多试几次
    local pool = Game():GetItemPool()
    for i = 1, P.maxRetry do
        local newSeed = (seed + i * 7919) % 2147483647
        local ok, alt = pcall(function()
            return pool:GetCollectible(poolType, false, newSeed)
        end)
        if ok and alt and alt > 0 and alt ~= itemID then
            local altMul = ratings.getWeightMul(alt)
            -- 新抽到的道具如果也被配置成极小权重，别换过去（否则降权失效）
            if altMul == nil or altMul >= mul then
                P.stats.reRolled = P.stats.reRolled + 1
                if mul <= 0 then P.stats.banned = P.stats.banned + 1 end
                return alt
            end
        end
    end

    P.stats.gaveUp = P.stats.gaveUp + 1
    return nil
end

-- Isaac 的物品池枚举：0..NUM_ITEMPOOLS-1。这里给一份常用池子
-- （快照用；数量随版本变化，多给几个无碍）
P.COMMON_POOLS = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
    20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
}

return P
