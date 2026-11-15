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
-- 存盘形态（v2，2026-11-16 起）：
--   Q={"v":2,"e":{"Peerless Elixir":{"q":3,"w":0.5}}}
--   键 = 道具内部名 → mod 增删不再漂移，不需要追 id。
-- 兼容 v1（数字 id 键 + n）：读进来后立刻按名字迁移，下次保存升级为 v2。
--
-- 运行时仍然是 [id] 表（池子每帧要查，不能每次查名字）：
--   读档时 名字 → 当前 id；查不到的进 orphans（挂起：不生效但写回存档）。
-- ============================================================================
local J = ...   -- 由 init 注入（避免依赖 require 路径）
local idmap = nil   -- 由 init 注入：core/idmap.lua，道具 id ↔ 名字 的双向索引

local R = {}

R.PREFIX = "Q="

--- 一代备份行：保存前把上一版 Q= 存成 Q0=。误清空时 load 会用它兜底。
R.BAK = "Q0="
R.VERSION = 2

R.entries  = {}   -- [id]      = { q = number, w = number, on = boolean, n = name }
R.orphans  = {}   -- [name]    = { q, w, on }   名字还在、道具当前不在
R.defaults = {}   -- [id]      = { q, w, on }   来自 rating_data
R.loaded   = false   -- 是否已经从存档里读过（没读过就不允许写，防止把已有配置清掉）
R.dirty    = false
R.format   = nil     -- 上一次读到的版本（1 / 2）
R.lastFix  = { moved = 0, parked = 0, stamped = 0, resolved = 0, version = nil }

-- ── 取值 ────────────────────────────────────────────────────────────────────

local function find(id)
    local e = R.entries[id]
    if e and not e.dead then return e, "user" end
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

--- 当前所有"生效中"的 id（已排序；挂起的不算）
function R.list()
    local ids = {}
    for id, e in pairs(R.entries) do
        if type(e) ~= "table" or not e.dead then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

--- 生效条数（挂起的不算）
function R.count()
    local n = 0
    for _, e in pairs(R.entries) do
        if type(e) ~= "table" or not e.dead then n = n + 1 end
    end
    return n
end

--- 挂起条数（道具当前不存在：mod 被关/删，数据仍留在存档里等它回来）
function R.parkedCount()
    local n = 0
    for _ in pairs(R.orphans) do n = n + 1 end
    for _, e in pairs(R.entries) do
        if type(e) == "table" and e.dead then n = n + 1 end
    end
    return n
end

-- ── 修改 ────────────────────────────────────────────────────────────────────

--- 写一条覆盖（改什么传什么，其余保持不变）。
--- 注意："停用"不是"删除"——停用保留数值只关掉生效，删除请用 R.clear。
--- 三个参数全为 nil 时才当作删除。
function R.set(id, q, w, on, name)
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

    -- 名字也要存：即使 v2 直接按名字存盘，运行时还要靠它知道"这条是哪个道具"
    local nm = cur.n
    if name ~= nil and #tostring(name) > 0 then nm = tostring(name) end
    R.entries[id] = {
        q  = q or cur.q or 0,
        w  = w or cur.w or 1,
        on = (on == nil) and (cur.on ~= false) or (on and true or false),
        n  = nm,
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

function R.init(jsonmini, defaults, idmapRef)
    J = jsonmini
    R.defaults = defaults or {}
    idmap = idmapRef
end

local function ensureIndex()
    if idmap and type(idmap.build) == "function" then pcall(idmap.build) end
    return (idmap ~= nil) and type(idmap.byId) == "table" and next(idmap.byId) ~= nil
end

--- 名字 → 当前 id。本地索引优先；引擎反查只作兜底。
local function resolveName(name)
    if type(name) ~= "string" or #name == 0 then return nil end
    local target = nil
    if idmap then target = idmap.idOf(name) end
    if not target and type(Isaac) == "table" and type(Isaac.GetItemIdByName) == "function" then
        local ok, v = pcall(function() return Isaac.GetItemIdByName(name) end)
        if ok and type(v) == "number" and v > 0 then target = v end
    end
    return target
end

--- v2：键就是名字 → 直接对到当前 id；对不上的进 orphans
local function applyV2(map)
    local fix = R.lastFix
    ensureIndex()
    for name, e in pairs(map) do
        local target = resolveName(name)
        if target and R.entries[target] == nil then
            e.n = name
            R.entries[target] = e
            fix.resolved = fix.resolved + 1
        elseif target then
            R.orphans[name] = e            -- 同名撞车：留一条在挂起里，别覆盖
            fix.parked = fix.parked + 1
        else
            R.orphans[name] = e            -- 道具当前不在：挂起
            fix.parked = fix.parked + 1
        end
    end
end

--- v1：数字 id 键 → 用名字迁移；没名字的按当前 id 补名；查不到的挂起
local function resolveV1()
    local fix = R.lastFix
    local haveIndex = ensureIndex()
    local list = {}
    for id, e in pairs(R.entries) do list[#list + 1] = { id = id, e = e } end
    for i = 1, #list do
        local id, e = list[i].id, list[i].e
        if type(e) == "table" and not e.dead then
            -- ① 没名字：按当前 id 补一个，把现状冻结住（往后就能靠名字追踪）
            local nm = e.n
            if (type(nm) ~= "string" or #nm == 0) and haveIndex then
                local cur = idmap.nameOf(id)
                if cur then e.n = cur; nm = cur; fix.stamped = fix.stamped + 1 end
            end

            local target = nil
            if type(nm) == "string" and #nm > 0 then target = resolveName(nm) end

            if type(nm) == "string" and #nm > 0 and target == nil then
                if haveIndex then
                    e.dead = true                  -- 道具不在：挂起，不生效
                    fix.parked = fix.parked + 1
                end
            elseif target and target ~= id then
                if R.entries[target] == nil then
                    R.entries[target] = e
                    if R.entries[id] == e then R.entries[id] = nil end
                    fix.moved = fix.moved + 1
                else
                    e.dead = true                  -- 撞车：后来的挂起
                    fix.parked = fix.parked + 1
                end
            end
        end
    end
end

--- 从 store.lines 里读 Q= 行
function R.load(store)
    R.entries, R.orphans = {}, {}
    R.format = nil
    R.lastFix = { moved = 0, parked = 0, stamped = 0, resolved = 0, version = nil }
    if not store or not store.lines then return end

    local function tryPrefix(prefix)
        for i = 1, #store.lines do
            local line = store.lines[i]
            if line:sub(1, #prefix) == prefix then
                local decoded, ver = J.decode(line:sub(#prefix + 1))
                if decoded ~= nil and ver ~= nil then return decoded, ver, true end
                return nil, nil, false          -- 解码失败：坏数据，别标记 loaded
            end
        end
        return nil, nil, nil
    end

    local function apply(decoded, ver)
        R.format = ver
        R.lastFix.version = ver
        if ver == 2 then
            applyV2(decoded)
        else
            R.entries = decoded
            resolveV1()
            R.dirty = true                      -- 读的是 v1：下次保存顺手升级成 v2
        end
        R.loaded = true
    end

    local cur, curVer, curOk = tryPrefix(R.PREFIX)
    if curOk and cur and next(cur) ~= nil then apply(cur, curVer); return end

    -- 当前 Q= 丢了或空了 → 用一代备份 Q0= 兜底（2026-10-24：作者评级被清空两次）
    local bak, bakVer, bakOk = tryPrefix(R.BAK)
    if bakOk and bak and next(bak) ~= nil then apply(bak, bakVer); return end

    if curOk == false or bakOk == false then return end   -- 有坏数据：不置 loaded，拒绝写盘
    R.loaded = true
end

--- 把当前 entries 写回 store.lines（先删旧的 Q= 行）
--- 返回 true 表示内容有变化
function R.save(store)
    if not R.loaded then return false end   -- 还没读过档：原样保留，绝不覆盖
    if not store or not store.lines then return false end
    local lines, kept = store.lines, {}
    local before, oldBak = nil, nil
    for i = 1, #lines do
        local line = lines[i]
        if line:sub(1, #R.BAK) == R.BAK then
            -- 旧的 Q0 先记下；本次内容变了就换成新的，没变就原样保留
            -- （以前无条件丢弃 → 一次空转 save 就把备份吃掉了）
            oldBak = line
        elseif line:sub(1, #R.PREFIX) == R.PREFIX then
            before = line
        else
            kept[#kept + 1] = line
        end
    end

    -- 优先 v2（按名字存）；有任何一条拿不到名字就退回 v1，避免丢条目
    local items, canV2 = {}, true
    for id, e in pairs(R.entries) do
        local nm = e.n
        if (type(nm) ~= "string" or #nm == 0) and idmap then nm = idmap.nameOf(id) end
        if type(nm) == "string" and #nm > 0 then
            items[nm] = { q = e.q, w = e.w, on = e.on }
        else
            canV2 = false
        end
    end

    local after = nil
    if next(R.entries) ~= nil or next(R.orphans) ~= nil then
        if canV2 then
            after = R.PREFIX .. J.encodeV2(items, R.orphans)
        else
            after = R.PREFIX .. J.encode(R.entries)
        end
    end

    -- 一代备份：把上一版 Q= 存成 Q0=；**旧的 Q0 先全部删掉**（否则每保存一次多一行）
    if before and before ~= after then
        kept[#kept + 1] = R.BAK .. before:sub(#R.PREFIX + 1)
    elseif oldBak then
        kept[#kept + 1] = oldBak          -- 内容没变：保留上一代备份
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
