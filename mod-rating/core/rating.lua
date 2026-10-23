-- ============================================================================
-- rating.lua —— 自定义道具评级与权重（数据层，唯一的"拆出去"边界）
--
-- 职责：只拥有数据与读写。不碰游戏 API、不碰 UI、不碰池子。
-- 其它模块一律通过本文件或 _G.HLR 访问，不直接读 entries。
--
-- 数据来源优先级（高 → 低）：
--   1. saveN.dat 里的 Q= 行   （当前存档槽的用户覆盖）
--   2. rating_data.lua 默认表（写在代码里，真全局）
--   3. 原版 ItemConfig.Quality（调用方自己回退）
--
-- 存盘形态：saveN.dat 里一行
--   Q={"v":1,"e":{"118":{"q":3.5,"w":2}}}
-- 局外可用 PowerShell ConvertFrom-Json 直接解析。
-- ============================================================================
local J = ...   -- 由 init 注入（避免依赖 require 路径）

local R = {}

R.PREFIX = "Q="

--- 一代备份行：保存前把上一版 Q= 存成 Q0=。误清空时 load 会用它兜底。
R.BAK = "Q0="
R.VERSION = 1

R.entries  = {}   -- [id] = { q = number, w = number, on = boolean }
R.defaults = {}   -- [id] = { q, w, on }   来自 rating_data
R.loaded = false   -- 是否已经从存档里读过（没读过就不允许写，防止把已有配置清掉）
R.dirty    = false

-- ── 取值 ────────────────────────────────────────────────────────────────────

local function find(id)
    local e = R.entries[id]
    if e then return e, "user" end
    local d = R.defaults[id]
    if d then return d, "default" end
    return nil, nil
end

--- 小数评级（0.0~4.0），无配置返回 nil
function R.getRating(id)
    local e = find(id)
    if not e then return nil end
    if e.on == false then return nil end
    return e.q
end

--- 整数评级（向下取整，作者定的规则：3.5 → 3，不算四级），无配置返回 nil
function R.getQuality(id)
    local q = R.getRating(id)
    if not q then return nil end
    return math.floor(q + 1e-9)
end

--- 权重倍数（1.0 = 不变），无配置返回 nil
function R.getWeightMul(id)
    local e = find(id)
    if not e then return nil end
    if e.on == false then return nil end
    return e.w
end

--- 是否有生效中的自定义（任意来源）
function R.has(id)
    return R.getRating(id) ~= nil
end

--- 当前所有"用户覆盖"的 id（已排序）
function R.list()
    local ids = {}
    for id in pairs(R.entries) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

function R.count()
    local n = 0
    for _ in pairs(R.entries) do n = n + 1 end
    return n
end

-- ── 修改 ────────────────────────────────────────────────────────────────────

--- 写一条覆盖（改什么传什么，其余保持不变）。
--- 注意："停用"不是"删除"——停用保留数值只关掉生效，删除请用 R.clear。
--- 三个参数全为 nil 时才当作删除。
function R.set(id, q, w, on)
    if not id then return end

    local cur = R.entries[id]
    if q == nil and w == nil and on == nil then
        if cur then R.entries[id] = nil; R.dirty = true end
        return
    end

    -- 只改启用状态、且还没有覆盖时，从默认表（或 0/1）起一条
    if cur == nil and q == nil and w == nil then
        local d = R.defaults[id]
        cur = { q = (d and d.q) or 0, w = (d and d.w) or 1 }
    end
    cur = cur or {}

    R.entries[id] = {
        q  = q or cur.q or 0,
        w  = w or cur.w or 1,
        on = (on == nil) and (cur.on ~= false) or (on and true or false),
    }
    R.dirty = true
end

--- 删掉一条覆盖（回退到默认表 / 原版）
function R.clear(id)
    if R.entries[id] then
        R.entries[id] = nil
        R.dirty = true
    end
end

-- ── 存档 ────────────────────────────────────────────────────────────────────

function R.init(jsonmini, defaults)
    J = jsonmini
    R.defaults = defaults or {}
end

--- 从 store.lines 里读 Q= 行
function R.load(store)
    R.entries = {}
    if not store or not store.lines then return end

    local function tryPrefix(prefix)
        for i = 1, #store.lines do
            local line = store.lines[i]
            if line:sub(1, #prefix) == prefix then
                local decoded = J.decode(line:sub(#prefix + 1))
                if decoded ~= nil then return decoded, true end
                return nil, false          -- 解码失败：坏数据，别标记 loaded
            end
        end
        return nil, nil
    end

    local cur, curOk = tryPrefix(R.PREFIX)
    if curOk and cur and next(cur) ~= nil then
        R.entries = cur
        R.loaded = true
        return
    end

    -- 当前 Q= 丢了或空了 → 用一代备份 Q0= 兜底（2026-10-24：作者评级被清空两次）
    local bak, bakOk = tryPrefix(R.BAK)
    if bakOk and bak and next(bak) ~= nil then
        R.entries = bak
        R.loaded = true
        return
    end

    if curOk == false or bakOk == false then return end   -- 有坏数据：不置 loaded，拒绝写盘
    R.loaded = true
end

--- 把当前 entries 写回 store.lines（先删旧的 Q= 行）
--- 返回 true 表示内容有变化
function R.save(store)
    if not R.loaded then return false end   -- 还没读过档：原样保留，绝不覆盖
    if not store or not store.lines then return false end
    local lines, kept = store.lines, {}
    local before = nil
    for i = 1, #lines do
        if lines[i]:sub(1, #R.PREFIX) == R.PREFIX then
            before = lines[i]
        else
            kept[#kept + 1] = lines[i]
        end
    end

    local after = nil
    if next(R.entries) ~= nil then
        after = R.PREFIX .. J.encode(R.entries)
    end

    -- 一代备份：把这一版 Q= 变成 Q0=，再写新的 Q=
    if before and before ~= after then
        kept[#kept + 1] = R.BAK .. before:sub(#R.PREFIX + 1)
    end
    store.lines = kept
    if after then store.lines[#store.lines + 1] = after end
    return before ~= after
end

-- ── 对外接口（未来拆 mod 的边界）─────────────────────────────────────────────

--- 其它模块只应通过这个表访问评级。
function R.publish()
    _G.HLR = {
        version      = R.VERSION,
        getRating    = R.getRating,
        getQuality   = R.getQuality,
        getWeightMul = R.getWeightMul,
        has          = R.has,
        list         = R.list,
        isReady      = function() return true end,
    }
end

return R
