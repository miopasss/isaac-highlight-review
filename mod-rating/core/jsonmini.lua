-- ============================================================================
-- jsonmini.lua —— 只服务"评级表"的最小 JSON 编解码
--
-- 为什么不用 require("json")：
--   游戏内有 json 模块，但离线单测（tools/luarun.ps1）没有，
--   两套实现会让同一个文件出现两种行为。
--
-- 为什么不做成通用 JSON：
--   我们只需要一种形状，写死解析反而更稳：
--     {"v":1,"e":{"118":{"q":3.5,"w":2},"1052":{"q":2,"w":0.5,"on":false}}}
--   规则：
--     · 顶层只有 v 和 e
--     · e 的键是道具 id（数字字符串）
--     · 每条只有 q / w / on 三个键，on 省略即 true
--   手改坏了就整体当空表（fail-safe），不带崩游戏。
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

--- entries: { [id] = { q=number, w=number, on=boolean } }  →  JSON 字符串
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
        parts[#parts + 1] = '"' .. tostring(id) .. '":{' .. table.concat(fields, ",") .. '}'
    end
    return '{"v":1,"e":{' .. table.concat(parts, ",") .. '}}'
end

--- JSON 字符串 → { [id] = { q, w, on } }，解析失败返回空表
function J.decode(s)
    local out = {}
    if type(s) ~= "string" or #s == 0 then return out end
    -- 版本号；不是 1 就当作不可读
    local v = tonumber(s:match('"v"%s*:%s*(%-?%d+)'))
    if v ~= 1 then return out end

    -- 每条： "118":{"q":3.5,"w":2}      或带 "on":false
    for idStr, body in s:gmatch('"(%-?%d+)"%s*:%s*{([^}]*)}') do
        local id = tonumber(idStr)
        if id then
            local q = tonumber(body:match('"q"%s*:%s*(%-?[%d%.eE%+]+)')) or 0
            local w = tonumber(body:match('"w"%s*:%s*(%-?[%d%.eE%+]+)')) or 1
            local on = body:match('"on"%s*:%s*false') == nil
            out[id] = { q = q, w = w, on = on }
        end
    end
    return out
end

--- 自检：编码→解码→比对
function J.selftest()
    local src = {
        [118] = { q = 3.5, w = 2.0 },
        [1052] = { q = 2, w = 0.5, on = false },
    }
    local enc = J.encode(src)
    local back = J.decode(enc)
    if not back[118] or math.abs(back[118].q - 3.5) > 1e-9 then return false, "q 不一致" end
    if not back[1052] or back[1052].on ~= false then return false, "on 不一致" end
    if back[118].on ~= true then return false, "on 默认应为 true" end
    return true, enc
end

return J
