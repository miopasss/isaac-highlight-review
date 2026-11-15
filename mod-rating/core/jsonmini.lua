-- ============================================================================
-- jsonmini.lua —— 只服务"评级表"的最小 JSON 编解码
--
-- v1（旧）：{"v":1,"e":{"1074":{"q":3,"w":2,"n":"Peerless Elixir"}}}
--         键是数字 id —— mod 一变就漂移，靠 n 事后补救。
-- v2（新）：{"v":2,"e":{"Peerless Elixir":{"q":3,"w":2}}}
--         键就是道具内部名 —— 根本不存在"漂移"，不需要追 id。
--
-- 为什么不用 require("json")：
--   游戏内有 json 模块，但离线单测（tools/luarun.ps1）没有，
--   两套实现会让同一个文件出现两种行为。
--
-- 为什么自己做扫描器：
--   道具名里可能有空格/中文/引号/反斜杠，正则 `[^}]*` 会被名字里的花括号打断。
--   这里按字符扫描（跳过字符串里的括号），只处理我们自己的形状，fail-safe。
-- ============================================================================
local J = {}

--- 数字转 JSON 字面量。%g 对 3.5 / 2 / 0.5 都给出干净结果。
local function num(v)
    if type(v) ~= "number" or v ~= v then return "0" end
    if v == math.floor(v) and math.abs(v) < 1e15 then
        return string.format("%d", math.floor(v))
    end
    return string.format("%.4g", v)
end
J.num = num

local function esc(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\n", " ")
    s = s:gsub("\r", " ")
    return s
end
J.esc = esc

--- 读一个 JSON 字符串（s[i] 必须是引号），返回 字符串, 下一个位置
local function readString(s, i)
    if s:sub(i, i) ~= '"' then return nil, i end
    local buf = {}
    i = i + 1
    while i <= #s do
        local c = s:sub(i, i)
        if c == "\\" then
            buf[#buf + 1] = s:sub(i + 1, i + 1)
            i = i + 2
        elseif c == '"' then
            return table.concat(buf), i + 1
        else
            buf[#buf + 1] = c
            i = i + 1
        end
    end
    return nil, i
end

--- 从 s 里取出 "key":{ ... } 的 {...} 内部文本（跳过字符串，按括号深度匹配）
local function findBlock(s, key)
    local _, e = s:find('"' .. key .. '"%s*:%s*{')
    if not e then return nil end
    local i = e + 1          -- e 指向 '{'
    local depth = 1
    local start = i
    while i <= #s do
        local c = s:sub(i, i)
        if c == '"' then
            local _, ni = readString(s, i)
            if not ni then return nil end
            i = ni
        elseif c == "{" then
            depth = depth + 1; i = i + 1
        elseif c == "}" then
            depth = depth - 1
            if depth == 0 then return s:sub(start, i - 1), i end
            i = i + 1
        else
            i = i + 1
        end
    end
    return nil
end

--- 解析一条 { "q":3,"w":2,"on":false,"n":"..." } 的内部文本
local function parseFields(body)
    local q = tonumber(body:match('"q"%s*:%s*(%-?[%d%.eE%+]+)')) or 0
    local w = tonumber(body:match('"w"%s*:%s*(%-?[%d%.eE%+]+)')) or 1
    local on = body:match('"on"%s*:%s*false') == nil
    local nm = body:match('"n"%s*:%s*"([^"]*)"')
    return { q = q, w = w, on = on, n = nm }
end

--- 解析 "aaa":{...},"bbb":{...} 这样的一层映射
local function parsePairs(block)
    local out = {}
    local i = 1
    while i <= #block do
        if block:sub(i, i) == '"' then
            local key, ni = readString(block, i)
            if not key then break end
            local _, brace = block:find("^%s*:%s*{", ni)
            if not brace then break end
            -- 找到这个值的结束 }
            local j = brace + 1
            local depth = 1
            local start = j
            while j <= #block do
                local c = block:sub(j, j)
                if c == '"' then
                    local _, nj = readString(block, j)
                    if not nj then break end
                    j = nj
                elseif c == "{" then
                    depth = depth + 1; j = j + 1
                elseif c == "}" then
                    depth = depth - 1
                    if depth == 0 then break end
                    j = j + 1
                else
                    j = j + 1
                end
            end
            if depth ~= 0 then break end
            out[key] = parseFields(block:sub(start, j - 1))
            i = j + 1
        else
            i = i + 1
        end
    end
    return out
end

--- v1 编码（数字 id 键，带 n）。只在"没有名字可用"时兜底。
function J.encode(entries)
    local ids = {}
    for id in pairs(entries or {}) do ids[#ids + 1] = id end
    table.sort(ids)

    local parts = {}
    for i = 1, #ids do
        local id = ids[i]
        local e = entries[id]
        local fields = { '"q":' .. num(e.q or 0), '"w":' .. num(e.w or 1) }
        if e.on == false then fields[#fields + 1] = '"on":false' end
        if type(e.n) == "string" and #e.n > 0 then
            fields[#fields + 1] = '"n":"' .. esc(e.n) .. '"'
        end
        parts[#parts + 1] = '"' .. tostring(id) .. '":{' .. table.concat(fields, ",") .. '}'
    end
    return '{"v":1,"e":{' .. table.concat(parts, ",") .. '}}'
end

--- v2 编码：键 = 道具内部名。items / orphans 都是 [name] = { q, w, on }
function J.encodeV2(items, orphans)
    local all, keys = {}, {}
    local function add(name, e)
        if type(name) ~= "string" or name == "" then return end
        if all[name] == nil then keys[#keys + 1] = name end
        all[name] = e
    end
    for name, e in pairs(orphans or {}) do add(name, e) end   -- 挂起的先放（会被 items 覆盖）
    for name, e in pairs(items or {}) do add(name, e) end

    table.sort(keys)
    local parts = {}
    for i = 1, #keys do
        local name = keys[i]
        local e = all[name]
        local fields = { '"q":' .. num(e.q or 0), '"w":' .. num(e.w or 1) }
        if e.on == false then fields[#fields + 1] = '"on":false' end
        parts[#parts + 1] = '"' .. esc(name) .. '":{' .. table.concat(fields, ",") .. '}'
    end
    return '{"v":2,"e":{' .. table.concat(parts, ",") .. '}}'
end

--- v1 解码：{[id] = { q, w, on, n }}
local function decodeV1(s)
    local out = {}
    for idStr, body in s:gmatch('"(%-?%d+)"%s*:%s*{([^}]*)}') do
        local id = tonumber(idStr)
        if id then out[id] = parseFields(body) end
    end
    return out
end

--- 解码。返回 map, version
---   v1: map[id]  = { q, w, on, n }
---   v2: map[name] = { q, w, on }
function J.decode(s)
    if type(s) ~= "string" or #s == 0 then return {}, nil end
    local v = tonumber(s:match('"v"%s*:%s*(%-?%d+)'))
    if v == 1 then return decodeV1(s), 1 end
    if v == 2 then
        local block = findBlock(s, "e")
        if not block then return {}, 2 end
        return parsePairs(block), 2
    end
    return {}, nil
end

--- 自检：v1 编解码 + v2 编解码（含中文/空格/引号名字）
function J.selftest()
    local src = {
        [118]  = { q = 3.5, w = 2.0 },
        [1052] = { q = 2, w = 0.5, on = false, n = "Peerless Elixir" },
    }
    local enc = J.encode(src)
    local back, v1 = J.decode(enc)
    if v1 ~= 1 then return false, "v1 版本号不对" end
    if not back[118] or math.abs(back[118].q - 3.5) > 1e-9 then return false, "v1 q 不一致" end
    if not back[1052] or back[1052].on ~= false then return false, "v1 on 不一致" end

    local items = {
        ["Peerless Elixir"] = { q = 3, w = 0.5 },
        ['字刀 "quoted"'] = { q = 1, w = 0, on = false },
    }
    local orphans = { ["亚波伦之翼"] = { q = 2, w = 1 } }
    local enc2 = J.encodeV2(items, orphans)
    local back2, v2 = J.decode(enc2)
    if v2 ~= 2 then return false, "v2 版本号不对" end
    if not back2["Peerless Elixir"] or back2["Peerless Elixir"].w ~= 0.5 then return false, "v2 数值不一致" end
    if not back2['字刀 "quoted"'] or back2['字刀 "quoted"'].on ~= false then return false, "v2 转义/键不一致" end
    if not back2["亚波伦之翼"] then return false, "v2 挂起项丢失" end
    return true, enc2
end

return J
