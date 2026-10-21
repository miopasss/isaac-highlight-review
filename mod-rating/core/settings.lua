-- ============================================================================
-- settings.lua —— 模组设置（热键等）
--
-- 存盘形态：saveN.dat 里一行
--   C={"f5":294,"f6":295}
-- 局外同样可以用 PowerShell 解析。
--
-- 与评级表（Q= 行）分开存，互不影响。
-- ============================================================================
local S = {}

S.PREFIX = "C="

S.defaults = {
    f5 = 294,   -- Keyboard.KEY_F5
    f6 = 295,   -- Keyboard.KEY_F6
}

--- 每个 mod 只写自己用到的键（例：{"f6"}）。nil 表示全写。
S.only = nil
S.values = {}

function S.init()
    S.values = {}
    for k, v in pairs(S.defaults) do S.values[k] = v end
end

function S.get(k)
    local v = S.values[k]
    if type(v) == "number" then return v end
    return S.defaults[k]
end

function S.set(k, v)
    if type(v) ~= "number" then return end
    S.values[k] = v
end

--- 从 store.lines 读 C= 行
function S.load(store)
    S.init()
    if not store or not store.lines then return end
    for i = 1, #store.lines do
        local line = store.lines[i]
        if line:sub(1, #S.PREFIX) == S.PREFIX then
            local body = line:sub(#S.PREFIX + 1)
            for k, v in body:gmatch('"(%a+)"%s*:%s*(%-?%d+)') do
                if S.defaults[k] then S.values[k] = tonumber(v) end
            end
            return
        end
    end
end

--- 写回 store.lines（先删旧的 C= 行）。返回是否变化
function S.save(store)
    if not store or not store.lines then return false end
    local kept, before = {}, nil
    for i = 1, #store.lines do
        local line = store.lines[i]
        if line:sub(1, #S.PREFIX) == S.PREFIX then
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
        parts[#parts + 1] = string.format('"%s":%d', k, S.get(k))
    end
    local after = S.PREFIX .. "{" .. table.concat(parts, ",") .. "}"

    store.lines = kept
    store.lines[#store.lines + 1] = after
    return before ~= after
end

return S
