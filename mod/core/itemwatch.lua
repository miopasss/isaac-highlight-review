-- ============================================================================
-- itemwatch.lua —— 每帧监视"玩家身上道具的变化"
--
-- 解决现有采集器的三个盲区：
--   1. 第一间房被强制清空 → 起始/开局立即获得的道具丢失
--   2. 同一间房里"获得又失去" → 进出差分净变化为 0，漏记（例：小麦种子→小麦苗→成熟小麦）
--   3. 跨房间/换层瞬间获得 → 落进新房间的基线，永远不算"获得"
--
-- 做法：每帧读 player:GetCollectiblesList()（REPENTOGON，返回 { [id] = 数量 }），
--       和上一帧比对，增加的进 pending，由主循环在"离开房间"时取走。
--
-- 为什么不用 MC_POST_PICKUP_INIT：直接 AddCollectible 塞进身上的道具
-- 根本不生成拾取物实体，那个回调钩不到。
-- ============================================================================
local W = {}

W.last    = {}      -- [id] = 上次观测到的数量
W.pending = {}      -- [id] = true，已获得但还没被取走
W.inited  = false
W.broken  = false   -- GetCollectiblesList 不可用时降级
W.ticks   = 0

--- 读当前持有的道具表；不可用返回 nil
local function readList(player)
    local ok, list = pcall(function() return player:GetCollectiblesList() end)
    if ok and type(list) == "table" then return list end
    return nil
end

--- 用 HasCollectible 全扫一遍（降级路径，慢）
local function scanList(player, maxId)
    local out = {}
    for id = 1, maxId do
        local ok, has = pcall(function() return player:HasCollectible(id) end)
        if ok and has then out[id] = 1 end
    end
    return out
end

--- 建立基线（进游戏 / 重新开始一局时调用）
function W.reset(player, maxId)
    W.last, W.pending, W.inited = {}, {}, false
    if not player then return end
    local list = readList(player)
    if not list then
        W.broken = true
        list = scanList(player, maxId or 1800)
    end
    W.last = list
    W.inited = true
end

--- 每帧调用。返回本帧新增的道具数量（0 表示没变化）
function W.tick(player, maxId)
    if not W.inited then
        W.reset(player, maxId)
        return 0
    end
    if not player then return 0 end
    W.ticks = W.ticks + 1

    local list = readList(player)
    if not list then
        -- 降级：每 12 帧扫一次全量，避免每帧开销
        W.broken = true
        if W.ticks % 12 ~= 0 then return 0 end
        list = scanList(player, maxId or 1800)
    end

    local added = 0
    for id, n in pairs(list) do
        local prev = W.last[id] or 0
        if n > prev then
            W.pending[id] = true
            added = added + (n - prev)
        end
    end
    W.last = list
    return added
end

--- 取走 pending（返回排好序的 id 列表）。主循环在离开房间时调用。
function W.drain()
    local out = {}
    for id in pairs(W.pending) do out[#out + 1] = id end
    table.sort(out)
    W.pending = {}
    return out
end

--- pending 里还有多少条（不取走）
function W.peek()
    local n = 0
    for _ in pairs(W.pending) do n = n + 1 end
    return n
end

return W
