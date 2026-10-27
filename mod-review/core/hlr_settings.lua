-- ============================================================================
-- settings.lua —— 模组设置（热键 / 语言）
--
-- 存盘形态：saveN.dat 里一行
--   C={"f5":294,"f6":295,"lang":"en"}
-- 数字不带引号、字符串带引号，局外同样可以用 PowerShell 解析。
--
-- 与评级表（Q= 行）分开存，互不影响。
-- ============================================================================
local S = {}

S.PREFIX = "C="
S.PREFIX_BAK = "C0="   -- 一代备份行：保存前把上一版 C= 存成 C0=（2026-10-26）

S.defaults = {
    f5   = 294,     -- Keyboard.KEY_F5
    f6   = 295,     -- Keyboard.KEY_F6
    lang = "zh",    -- "zh" 中文 / "en" 纯英文
}

--- 每个 mod 只写自己用到的键（例：{"f6","lang"}）。nil 表示全写。
S.only = nil
S.values = {}

function S.init()
    S.values = {}
    for k, v in pairs(S.defaults) do S.values[k] = v end
end

function S.get(k)
    local v = S.values[k]
    local t = type(v)
    if t == "number" or t == "string" then return v end
    return S.defaults[k]
end

function S.set(k, v)
    local t = type(v)
    if t ~= "number" and t ~= "string" then return end
    S.values[k] = v
end

--- 从 store.lines 读 C= 行
function S.load(store)
    S.init()
    if not store or not store.lines then return end

    local function parseBody(body)
        for k, v in body:gmatch('"([%w_]+)"%s*:%s*"([^"]*)"') do
            if S.defaults[k] then S.values[k] = v end
        end
        for k, v in body:gmatch('"([%w_]+)"%s*:%s*(%-?%d+%.?%d*)') do
            if S.defaults[k] and type(S.defaults[k]) == "number" then
                S.values[k] = tonumber(v)
            end
        end
    end

    local function findLine(prefix)
        for i = 1, #store.lines do
            local line = store.lines[i]
            if line:sub(1, #prefix) == prefix then return line:sub(#prefix + 1) end
        end
        return nil
    end

    local body = findLine(S.PREFIX)
    if body then parseBody(body); return end

    -- C= 丢了 → 用一代备份 C0=（配置被清空时能自愈）
    body = findLine(S.PREFIX_BAK)
    if body then parseBody(body) end
end

local function encodeValue(k)
    local v = S.get(k)
    if type(v) == "number" then return string.format('"%s":%d', k, v) end
    return string.format('"%s":"%s"', k, tostring(v))
end

--- 写回 store.lines（先删旧的 C= 行）。返回是否变化
function S.save(store)
    if not store or not store.lines then return false end
    local kept, before, beforeBak = {}, nil, nil
    for i = 1, #store.lines do
        local line = store.lines[i]
        if line:sub(1, #S.PREFIX_BAK) == S.PREFIX_BAK then
            beforeBak = line
        elseif line:sub(1, #S.PREFIX) == S.PREFIX then
            before = line
        else
            kept[#kept + 1] = line
        end
    end

    local parts = {}
    local keys = {}
    local allow = nil
    if S.only then
        allow = {}
        for _, k in ipairs(S.only) do allow[k] = true end
    end
    for k in pairs(S.defaults) do
        if not allow or allow[k] then keys[#keys + 1] = k end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        parts[#parts + 1] = encodeValue(k)
    end
    local after = S.PREFIX .. "{" .. table.concat(parts, ",") .. "}"

    -- 一代备份：上一版 C= 存成 C0=（只留一条）
    if before and before ~= after then
        kept[#kept + 1] = S.PREFIX_BAK .. before:sub(#S.PREFIX + 1)
    elseif beforeBak then
        kept[#kept + 1] = beforeBak
    end
    store.lines = kept
    store.lines[#store.lines + 1] = after
    return before ~= after
end

return S
