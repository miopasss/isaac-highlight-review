-- =============================================================================
-- fmt_test.lua —— v2 格式的离线单测（不启动游戏）
--   tools\luarun.ps1 tests\fmt_test.lua
-- =============================================================================
local ROOT = (os and os.getenv and os.getenv("HLR_ROOT")) or "D:/00000/aiStudy/issacmod/"
if ROOT:sub(-1) ~= "/" then ROOT = ROOT .. "/" end

local function loadmod(path)
    local chunk, err = loadfile(ROOT .. path)
    if not chunk then error("loadfile failed: " .. tostring(err)) end
    return chunk()
end

local schema = loadmod("mod-review/core/schema.lua")
local fmt = loadmod("mod-review/core/fmt.lua")
local power = loadmod("mod-review/core/power.lua")
fmt.setSchema(schema)

local fails = {}
local function check(name, cond, detail)
    if not cond then fails[#fails + 1] = name .. (detail and (" : " .. tostring(detail)) or "") end
end

-- 1) 模块自检
local ok, msg = fmt.selftest()
check("fmt.selftest", ok, msg)

-- 2) schema 驱动：验证"加一个 key 就自动生效"
local extraSchema = { version = 2, magic = "MRV2",
    defaults = schema.defaults, required = schema.required,
    scopes = {}, keys = schema.keys, typeOf = schema.typeOf, defaultFor = schema.defaultFor }
for sc, fields in pairs(schema.scopes) do
    extraSchema.scopes[sc] = {}
    for k, v in pairs(fields) do extraSchema.scopes[sc][k] = v end
end
extraSchema.scopes.M.spd = "i"      -- 模拟"以后想记速度"
extraSchema.keys = function(sc)
    local l = {}
    for k in pairs(extraSchema.scopes[sc]) do l[#l + 1] = k end
    table.sort(l)
    return l
end
fmt.setSchema(extraSchema)
local line = fmt.encodeRecord("M", { t = 1, spd = 37 })
local _, rec = fmt.decodeRecord(line)
check("新 key 自动编码", line:find("spd=37", 1, true) ~= nil, line)
check("新 key 自动解码", rec.spd == 37, rec.spd)
fmt.setSchema(schema)   -- 还原

-- 3) 未知 key 保留
local _, _, extra = fmt.decodeRecord("M|t=2/future_gizmo=7")
check("未知 key 保留", extra and extra.future_gizmo == "7")

-- 4) 字符串里的分隔符被清洗
local l2 = fmt.encodeRecord("F", { r = 1, i = 1, curse = 21 })
check("诅咒是整数", l2:find("curse=21", 1, true) ~= nil, l2)
local _, f2 = fmt.decodeRecord(l2)
check("诅咒可解回", f2.curse == 21, f2.curse)

-- 5) 体积：单房、整局、500 局投影
local sampleRoom = {
    r = 1, f = 1, i = 1, t = 4, s = 1, d = 15, st = 30, v = 12, list = 7,
    hp = 6, hs = 2, hb = 0, hpo = 4, hso = 1, hbo = 1,
    p = 12.89, po = 13.99, ms = 7800, dmg = 0, clr = true, it = { 34, 385 }, pd = "",
}
local roomBytes = #fmt.encodeRecord("M", sampleRoom)

local store = fmt.splitBlob("MRV2\n")
for i = 1, 100 do
    fmt.appendRun(store, {
        seq = i, id = "SEED-" .. i, seed = 1000 + i, char = 0,
        base = 12.89, final = 30.5, max = 6, res = (i == 100) and 2 or 1, t0 = 1700000000 + i, hl = 0,
        floors = { { r = i, i = 1, stage = 1, type = 0, t = 0, ms = 600000 } },
        rooms = {},
    })
    local run = store.index[#store.index]
    for j = 1, 40 do
        store.lines[#store.lines + 1] = fmt.encodeRecord("M", sampleRoom)
        run.count = run.count + 1
    end
end
store.bytes = nil
local total = fmt.blobSize(store)
check("100 局 4000 房", #store.index == 100 and #store.lines == 100 * 42, #store.lines)  -- 每局 1 R + 1 F + 40 M
check("单房 ≤ 200 字节", roomBytes <= 200, roomBytes)

-- 6) 预算裁剪后行号仍然正确
local beforeIdx = #store.index
local removed = fmt.trimToBudget(store, math.floor(total * 0.3))
check("裁剪触发了", removed > 0, removed)
check("裁剪后不超预算", fmt.blobSize(store) <= math.floor(total * 0.3), fmt.blobSize(store))
local lastEntry = store.index[#store.index]
local lastRun = fmt.decodeRun(store, lastEntry)
check("裁剪后最后局可解", lastRun.seq == 100, lastRun.seq)
check("裁剪后最后局房间数", #lastRun.rooms == 40, #lastRun.rooms)
check("裁剪只从旧局删", removed < beforeIdx, removed)

-- 7) 战力公式回归（v1 已验证，别改坏）
check("初始战力", math.abs(power.output({ damage = 3.5, maxFireDelay = 10 }) - 9.5455) < 0.01)
check("Ludo 不吃攻速",
    power.output({ damage = 5, maxFireDelay = 10, form = "ludovico" }) ==
    power.output({ damage = 5, maxFireDelay = 3,  form = "ludovico" }))
check("生存 6+4", power.survival({ red = 6, soul = 4, bone = 0 }) == 10)

-- 8) 投影：500 局 × 40 房
local perRun = total / 100
local proj500 = perRun * 500

if #fails == 0 then
    return string.format(
        "PASS  单房=%d B  单局≈%d B  500 局≈%.2f MB  裁剪删了 %d 局",
        roomBytes, math.floor(perRun), proj500 / 1024 / 1024, removed)
end
return "FAIL " .. #fails .. " 项：\n  - " .. table.concat(fails, "\n  - ")
