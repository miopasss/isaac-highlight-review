-- ============================================================================
-- fmt.lua —— v2 记录流编解码（纯 Lua，不依赖游戏 API，可离线单测）
--
-- 设计要点（见 FORMAT.md）：
--   1. 一条记录一行：R|…  F|…  M|…
--   2. 字段是 key=value（key 之间用 / 分隔），不是位置式
--   3. 字段名与类型来自 schema.lua —— 加需求只改 schema 一处
--   4. 旧局**只保留原始字符串**，不解码；只有被查看时才解那一局
--   5. 未知 key 原样保留在 rec.extra，不丢数据
-- ============================================================================
local fmt = {}

fmt.SEP_FIELD = "|"    -- 作用域 与 字段 之间
fmt.SEP_KV    = "/"    -- 键值对之间
fmt.SEP_EQ    = "="    -- 键 与 值
fmt.SEP_LIST  = "+"    -- 列表元素之间

local schema = nil

function fmt.setSchema(s)
    schema = s
    fmt.MAGIC = s.magic
    return fmt
end

local function need()
    assert(schema ~= nil, "fmt.setSchema() 必须先调用")
    return schema
end

-- ---------------------------------------------------------------- 值编解码

local function isFinite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

--- 字符串落盘前清洗：不能含结构性分隔符，否则会切错
--- 注意：`+` 不在清洗范围 —— 列表分隔符只在 l 类型里用，而列表元素都是整数，
--- 所以字符串（例如多个诅咒 "Hot+Blind"）里保留 `+` 是安全的。
local function clean(s)
    s = tostring(s or "")
    s = s:gsub("[\r\n]", " ")
    s = s:gsub("[|/=%%]", "_")   -- % 是 Lua 模式转义符，自身要写成 %%
    return s
end

local function encodeValue(t, v)
    if t == "i" then
        if not isFinite(v) then return "0" end
        return string.format("%d", math.floor(v + 0.5))
    elseif t == "f" then
        if not isFinite(v) then return "0.00" end
        if v > 1e6 then v = 1e6 elseif v < -1e6 then v = -1e6 end
        return string.format("%.2f", v)
    elseif t == "b" then
        return v and "1" or "0"
    elseif t == "l" then
        local out = {}
        for k = 1, #v do
            if isFinite(v[k]) then
                local x = v[k]
                if x == math.floor(x) then
                    out[#out + 1] = string.format("%d", math.floor(x + 0.5))   -- 整数：保持旧格式
                else
                    if x > 1e6 then x = 1e6 elseif x < -1e6 then x = -1e6 end
                    out[#out + 1] = string.format("%.4f", x)                     -- 小数：ie 的战力增量
                end
            end
        end
        return table.concat(out, fmt.SEP_LIST)
    elseif t == "h" then
        return clean(v)
    end
    return clean(v)
end

local function decodeValue(t, s)
    if t == "i" then
        local n = tonumber(s)
        if not n or not isFinite(n) then return 0 end
        return math.floor(n + 0.5)
    elseif t == "f" then
        local n = tonumber(s)
        if not n or not isFinite(n) then return 0 end
        return n
    elseif t == "b" then
        return s == "1" or s == "true"
    elseif t == "l" then
        local out = {}
        for piece in s:gmatch("[^" .. fmt.SEP_LIST .. "]+") do
            local n = tonumber(piece)
            if n and isFinite(n) then out[#out + 1] = n end
        end
        return out
    end
    return s or ""
end

-- ---------------------------------------------------------------- 单条记录

--- 是否等于该类型的默认值（相等就可以不落盘 —— 稀疏编码）
local function isDefault(t, v)
    if t == "l" then return v == nil or #v == 0 end
    if t == "h" or t == "s" then return v == nil or v == "" end
    if t == "b" then return not v end
    if t == "i" or t == "f" then return v == nil or v == 0 end
    return v == nil
end

--- rec: 普通表；scope: "R" / "F" / "M"
function fmt.encodeRecord(scope, rec)
    need()
    local fields = schema.scopes[scope]
    local parts, keys = {}, schema.keys(scope)
    for i = 1, #keys do
        local k = keys[i]
        local v = rec[k]
        -- 空列表 / 空十六进制串不落盘（省字节）；其余一律写，保证可读
        local skip = false
        -- 稀疏：等于默认值就不写（省字节）。required 里的键强制写。
        local required = false
        local reqList = schema.required and schema.required[scope]
        if reqList then
            for ri = 1, #reqList do if reqList[ri] == k then required = true end end
        end
        if not required and isDefault(fields[k], v) then skip = true end
        if not skip then
            parts[#parts + 1] = k .. fmt.SEP_EQ .. encodeValue(fields[k], v)
        end
    end
    return scope .. fmt.SEP_FIELD .. table.concat(parts, fmt.SEP_KV)
end

--- 返回 scope, rec, extra（未知 key）
function fmt.decodeRecord(line)
    need()
    local scope, rest = line:match("^(%u)" .. fmt.SEP_FIELD .. "(.*)$")
    if not scope then return nil, nil, nil, "bad line" end
    local fields = schema.scopes[scope]
    if not fields then return nil, nil, nil, "unknown scope " .. scope end

    local rec, extra = {}, {}
    for pair in rest:gmatch("[^" .. fmt.SEP_KV .. "]+") do
        local k, v = pair:match("^([^=]+)=(.*)$")
        if k then
            local t = fields[k]
            if t then
                rec[k] = decodeValue(t, v)
            else
                extra[k] = v     -- 不认识的键：原样留着，别丢
            end
        end
    end
    -- 补默认值
    for k, t in pairs(fields) do
        if rec[k] == nil then
            local d = schema.defaults[t]
            rec[k] = (type(d) == "table") and {} or d
        end
    end
    rec.extra = next(extra) and extra or nil
    return scope, rec, extra
end

-- ---------------------------------------------------------------- 一局

--- 把一个 run 表编码成若干行（R + 若干 F + 若干 M）
function fmt.encodeRun(run)
    local lines = {}
    lines[#lines + 1] = fmt.encodeRecord("R", run)
    for i = 1, #(run.floors or {}) do
        lines[#lines + 1] = fmt.encodeRecord("F", run.floors[i])
    end
    for i = 1, #(run.rooms or {}) do
        lines[#lines + 1] = fmt.encodeRecord("M", run.rooms[i])
    end
    for i = 1, #(run.pills or {}) do
        lines[#lines + 1] = fmt.encodeRecord("P", run.pills[i])
    end
    return lines
end

--- 从 store 里解出**单独一局**（这是"按需解码"的入口）
function fmt.decodeRun(store, entry)
    need()
    local run = { floors = {}, rooms = {}, pills = {} }
    for idx = entry.start, entry.start + entry.count - 1 do
        local line = store.lines[idx]
        if line then
            local scope, rec = fmt.decodeRecord(line)
            if scope == "R" then
                for k, v in pairs(rec) do run[k] = v end
            elseif scope == "F" then
                run.floors[#run.floors + 1] = rec
            elseif scope == "M" then
                run.rooms[#run.rooms + 1] = rec
            elseif scope == "P" then
                run.pills[#run.pills + 1] = rec
            end
        end
    end
    return run
end

-- ---------------------------------------------------------------- 整份存档

local function newEntry(run, start, count)
    return {
        seq   = run.seq or 0,
        id    = run.id or "?",
        res   = run.res or 2,
        max   = run.max or 0,
        base  = run.base or 0,
        final = run.final or 0,
        hl    = run.hl or 0,
        t0    = run.t0 or 0,
        rooms = #(run.rooms or {}),
        start = start,
        count = count,
    }
end

--- 切行 + 建轻量索引。**不解析房间体**（只有 R 行读头部）
function fmt.splitBlob(blob)
    need()
    local store = { lines = {}, index = {} }
    local warnings = {}
    if not blob or blob == "" then return store, warnings end

    local magicSeen = false
    local cur = nil
    for line in blob:gmatch("[^\n]+") do
        line = line:gsub("\r$", "")   -- 容忍 CRLF
        if not magicSeen then
            magicSeen = true
            if line ~= schema.magic then
                warnings[#warnings + 1] = "魔数不符（期望 " .. schema.magic .. "，实际 " .. line .. "）"
            end
        elseif #line > 0 then
            store.lines[#store.lines + 1] = line
            local scope = line:sub(1, 1)
            if scope == "R" then
                local _, rec = fmt.decodeRecord(line)   -- 只解 R 行，便宜
                if rec then
                    cur = newEntry(rec, #store.lines, 1)
                    store.index[#store.index + 1] = cur
                else
                    warnings[#warnings + 1] = "无法解析的局头"
                end
            elseif scope == "Q" or scope == "C" then
                -- 评级/设置行：保留在 lines 里，但不计入任何一局的记录数
            elseif cur then
                cur.count = cur.count + 1
                if scope == "M" then cur.rooms = cur.rooms + 1 end
                -- P（药丸）行：count 照常 +1，但不算房间
            else
                warnings[#warnings + 1] = "游离记录（前面没有局头）"
            end
        end
    end
    return store, warnings
end

--- 追加一局（原地修改 store）
function fmt.appendRun(store, run)
    need()
    local lines = fmt.encodeRun(run)
    local start = #store.lines + 1
    for i = 1, #lines do store.lines[#store.lines + 1] = lines[i] end
    store.index[#store.index + 1] = newEntry(run, start, #lines)
    store.bytes = nil      -- 失效缓存，下次按需重算
    return store.index[#store.index]
end

function fmt.buildBlob(store)
    need()
    local lines = store.lines or {}
    return schema.magic .. "\n" .. table.concat(lines, "\n")
end

--- 重新计算并缓存字节数（避免每次都 concat 一遍 1.5MB 字符串）
function fmt.recomputeSize(store)
    local lines = store.lines or {}
    local n = 0
    for i = 1, #lines do n = n + #lines[i] end
    store.bytes = #schema.magic + 1 + n + math.max(0, #lines - 1)
    return store.bytes
end

function fmt.blobSize(store)
    need()
    if store.bytes then return store.bytes end
    return fmt.recomputeSize(store)
end

--- 超出预算时从最旧的局开始整局删除。返回删除的局数。
function fmt.trimToBudget(store, maxBytes)
    need()
    if not maxBytes or maxBytes <= 0 then return 0 end
    local removed = 0

    while #store.index > 1 and fmt.blobSize(store) > maxBytes do
        -- 找 seq 最小的一局
        local victim = 1
        for i = 2, #store.index do
            if (store.index[i].seq or 0) < (store.index[victim].seq or 0) then victim = i end
        end
        local e = store.index[victim]
        for _ = 1, e.count do table.remove(store.lines, e.start) end

        -- 重算后面各局的起始行号
        for i = 1, #store.index do
            if i ~= victim and store.index[i].start > e.start then
                store.index[i].start = store.index[i].start - e.count
            end
        end
        table.remove(store.index, victim)
        store.bytes = nil          -- 缓存的字节数已失效
        removed = removed + 1
    end
    return removed
end

--- 按局数裁剪（保留 seq 最大的 maxRuns 局）。返回删除的局数。
function fmt.trimToCount(store, maxRuns)
    need()
    if not maxRuns or maxRuns <= 0 then return 0 end
    local removed = 0
    while #store.index > maxRuns do
        local victim = 1
        for i = 2, #store.index do
            if (store.index[i].seq or 0) < (store.index[victim].seq or 0) then victim = i end
        end
        local e = store.index[victim]
        for _ = 1, e.count do table.remove(store.lines, e.start) end
        for i = 1, #store.index do
            if i ~= victim and store.index[i].start > e.start then
                store.index[i].start = store.index[i].start - e.count
            end
        end
        table.remove(store.index, victim)
        store.bytes = nil
        removed = removed + 1
    end
    return removed
end

function fmt.nextSeq(store)
    local max = 0
    for i = 1, #(store and store.index or {}) do
        local s = store.index[i].seq or 0
        if s > max then max = s end
    end
    return max + 1
end

--- 找"最近一局且未完成"（Save & Quit 续接用）
function fmt.findUnfinished(store)
    if not store or not store.index then return nil end   -- 空存档：没有未完成的局
    local best = nil
    for i = 1, #store.index do
        local e = store.index[i]
        if e.res == 2 then
            if not best or (e.seq or 0) > (best.seq or 0) then best = e end
        end
    end
    return best
end

--- 只把某一局从 store 里删掉（不解码）。用于"换层落盘"时先撤掉旧版本再重新追加。
function fmt.removeEntry(store, entry)
    need()
    if not entry then return end
    for _ = 1, entry.count do table.remove(store.lines, entry.start) end
    for i = 1, #store.index do
        if store.index[i] ~= entry and store.index[i].start > entry.start then
            store.index[i].start = store.index[i].start - entry.count
        end
    end
    for i = #store.index, 1, -1 do
        if store.index[i] == entry then table.remove(store.index, i) end
    end
    store.bytes = nil
end

--- 同一个局 id 只保留**最完整**的那一份（行数最多），其余删掉。
--- 为什么需要：小退续接时偶尔会多写一条"只有局头、0 房间"的空记录，
--- 平板上它会显示成一局空数据，还会让"最新一局"错位。读档时清一次最省事。
--- 返回：删掉的条数
function fmt.dedupe(store)
    need()
    if not store or not store.index then return 0 end
    local best, doomed = {}, {}
    for i = 1, #store.index do
        local e = store.index[i]
        local prev = best[e.id]
        if not prev then
            best[e.id] = e
        elseif e.count > prev.count then
            doomed[#doomed + 1] = prev
            best[e.id] = e
        else
            doomed[#doomed + 1] = e
        end
    end
    if #doomed == 0 then return 0 end
    -- 从后往前删，避免前面的 start 偏移失效
    table.sort(doomed, function(a, b) return a.start > b.start end)
    for _, e in ipairs(doomed) do fmt.removeEntry(store, e) end
    return #doomed
end

--- 把某一局从 store 里摘出来并解码（续接 Save & Quit 用：摘出来继续写，结束时再追加回去）
function fmt.detachRun(store, entry)
    need()
    local run = fmt.decodeRun(store, entry)
    for _ = 1, entry.count do table.remove(store.lines, entry.start) end
    for i = 1, #store.index do
        if store.index[i] ~= entry and store.index[i].start > entry.start then
            store.index[i].start = store.index[i].start - entry.count
        end
    end
    for i = #store.index, 1, -1 do
        if store.index[i] == entry then table.remove(store.index, i) end
    end
    store.bytes = nil
    return run
end

-- ---------------------------------------------------------------- 自检

local function room(over)
    local r = {
        r = 1, f = 1, i = 1, t = 4, s = 1, d = 15, st = 30, v = 12, list = 7,
        hp = 6, hs = 2, hb = 0, hpo = 4, hso = 1, hbo = 1,
        p = 12.89, po = 13.99, ms = 7800, dmg = 0, clr = true,
        it = { 34, 385 }, pd = "",
    }
    for k, v in pairs(over or {}) do r[k] = v end
    return r
end

function fmt.selftest()
    local fails = {}
    local function check(name, cond, detail)
        if not cond then fails[#fails + 1] = name .. (detail and (" : " .. tostring(detail)) or "") end
    end

    -- 1) 单条记录往返
    local line = fmt.encodeRecord("M", room())
    local scope, rec = fmt.decodeRecord(line)
    check("scope", scope == "M", scope)
    check("t", rec.t == 4, rec.t)
    check("p", math.abs(rec.p - 12.89) < 0.005, rec.p)
    check("clr", rec.clr == true)
    check("items", #rec.it == 2 and rec.it[1] == 34 and rec.it[2] == 385)
    check("health 全 6 个分量", rec.hpo == 4 and rec.hso == 1 and rec.hbo == 1)

    -- 2) 未知 key 必须保留，不能丢
    local _, rec2, extra = fmt.decodeRecord("M|t=4/xx=hello/yy=42")
    check("未知 key 进 extra", extra and extra.xx == "hello" and extra.yy == "42")
    check("已知 key 正常", rec2.t == 4)

    -- 3) 缺失 key → 默认值
    local _, rec3 = fmt.decodeRecord("M|t=5")
    check("缺失补默认", rec3.hp == 0 and rec3.p == 0 and #rec3.it == 0 and rec3.clr == false)

    -- 4) 整局往返 + 按需解码
    local run = {
        seq = 3, id = "DEADBEEF-0", seed = 123, char = 5, base = 12.89,
        final = 13.99, max = 2, res = 0, t0 = 1700000000, hl = 0,
        floors = {
            { r = 3, i = 1, stage = 1, type = 0, curse = 21, alt = 0, t = 1700, ms = 600000 },
            { r = 3, i = 2, stage = 2, type = 0, curse = "", alt = 1, t = 2300, ms = 300000 },
        },
        rooms = { room(), room({ i = 2, t = 5, po = 15.5 }) },
    }
    local store, warns = fmt.splitBlob(fmt.buildBlob({}))
    check("空存档无警告", #warns == 0, table.concat(warns, ","))
    local entry = fmt.appendRun(store, run)
    check("索引 seq", entry.seq == 3, entry.seq)
    check("索引房间数", entry.rooms == 2, entry.rooms)
    check("索引行数", entry.count == 5, entry.count)  -- 1 R + 2 F + 2 M

    -- 重新切一份，验证"只建索引不解码"
    local store2, w2 = fmt.splitBlob(fmt.buildBlob(store))
    check("重新切分无警告", #w2 == 0, table.concat(w2, ","))
    check("切分后索引 1 局", #store2.index == 1, #store2.index)
    check("切分后行数 5", #store2.lines == 5, #store2.lines)

    local back = fmt.decodeRun(store2, store2.index[1])
    check("往返 seq", back.seq == 3, back.seq)
    check("往返 res", back.res == 0, back.res)
    check("往返 层数", #back.floors == 2, #back.floors)
    check("往返 房间数", #back.rooms == 2, #back.rooms)
    check("往返 诅咒", back.floors[1].curse == 21, back.floors[1].curse)
    check("往返 房间2 战力", math.abs(back.rooms[2].po - 15.5) < 0.005, back.rooms[2].po)

    -- 5) 多局 + FIFO 预算裁剪
    local s3 = fmt.splitBlob(fmt.buildBlob({}))
    for i = 1, 6 do
        fmt.appendRun(s3, {
            seq = i, id = "R" .. i, res = (i == 5) and 2 or (i % 2), max = i, base = 1, final = i,
            t0 = 0, hl = 0, floors = {}, rooms = { room({ r = i, i = 1 }) },
        })
    end
    check("6 局", #s3.index == 6, #s3.index)
    local before = fmt.blobSize(s3)
    local removed = fmt.trimToBudget(s3, math.floor(before * 0.5))
    check("裁剪删了局", removed > 0, removed)
    check("裁剪后仍在预算内", fmt.blobSize(s3) <= math.floor(before * 0.5),
          fmt.blobSize(s3) .. " > " .. math.floor(before * 0.5))
    check("裁剪保留了最新的", s3.index[#s3.index].seq == 6, s3.index[#s3.index].seq)
    -- 裁剪后行号必须还对得上
    local lastRun = fmt.decodeRun(s3, s3.index[#s3.index])
    check("裁剪后仍能解出最后一局", lastRun.seq == 6, lastRun.seq)
    check("裁剪后房间数正确", #lastRun.rooms == 1, #lastRun.rooms)

    -- 6) nextSeq / findUnfinished
    check("nextSeq", fmt.nextSeq(s3) == 7, fmt.nextSeq(s3))
    local uf = fmt.findUnfinished(s3)
    check("findUnfinished 拿到未完成局", uf ~= nil and uf.res == 2, uf and uf.res)

    if #fails == 0 then
        return true, string.format("ok（单房 %d 字节）", #fmt.encodeRecord("M", room()))
    end
    return false, table.concat(fails, "; ")
end

return fmt
