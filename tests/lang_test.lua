-- ============================================================================
-- lang_test.lua —— 权重 mod 双语文案的离线单测
--
-- 测什么：
--   1. zh / en 两套文案的**键完全一致**（少一条就会在英文界面露出 key 名）
--   2. 没有空串
--   3. 占位符（%s / %d / %.2f）数量两边一致（否则 format 会报错或串位）
--   4. L.t / L.tFor / L.init / L.set / L.needRestart 的每个分支
-- ============================================================================

local ROOT = "D:/00000/aiStudy/issacmod/"
local L = loadfile(ROOT .. "mod-rating/ui/lang.lua")()

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1
    else fail = fail + 1; print("  FAIL: " .. tostring(msg)) end
end
local function eq(actual, expected, msg)
    ok(actual == expected, string.format("%s  期望=%s 实际=%s", msg, tostring(expected), tostring(actual)))
end

--- 数占位符个数（%s %d %i %.2f 之类）
local function countPh(s)
    local n = 0
    for _ in tostring(s):gmatch("%%[-%d%.]*[sdifqx%%]") do n = n + 1 end
    return n
end

print("== 文案完整性 ==")

local keys = L.keys()
ok(#keys > 30, string.format("文案键数 %d 应 > 30", #keys))

local missingZh, missingEn, emptyZh, emptyEn, phMismatch = {}, {}, {}, {}, {}
for _, k in ipairs(keys) do
    local zh, en = L.rawFor("zh", k), L.rawFor("en", k)
    if zh == nil then missingZh[#missingZh + 1] = k end
    if en == nil then missingEn[#missingEn + 1] = k end
    if zh == "" then emptyZh[#emptyZh + 1] = k end
    if en == "" then emptyEn[#emptyEn + 1] = k end
    if zh and en and countPh(zh) ~= countPh(en) then phMismatch[#phMismatch + 1] = k end
end
eq(#missingZh, 0, "zh 缺键: " .. table.concat(missingZh, ","))
eq(#missingEn, 0, "en 缺键: " .. table.concat(missingEn, ","))
eq(#emptyZh, 0, "zh 空串: " .. table.concat(emptyZh, ","))
eq(#emptyEn, 0, "en 空串: " .. table.concat(emptyEn, ","))
eq(#phMismatch, 0, "占位符数量不一致: " .. table.concat(phMismatch, ","))

print("== L.t ==")

L.setCode("zh")
eq(L.code(), "zh", "setCode(zh) → code=zh")
ok(L.isZh(), "zh 时 isZh()=true")
local zhTitle = L.t("win_title")
ok(type(zhTitle) == "string" and #zhTitle > 0, "zh 取到标题")

L.setCode("en")
eq(L.code(), "en", "setCode(en) → code=en")
ok(not L.isZh(), "en 时 isZh()=false")
local enTitle = L.t("win_title")
ok(zhTitle ~= enTitle, "中英文案不同（真的切了）")

-- 未知 key → 返回 key 本身（不返回 nil，避免界面炸）
eq(L.t("__不存在的键__"), "__不存在的键__", "未知 key 回落为 key 名")

print("== L.tFor（不改全局状态）==")

L.setCode("zh")
eq(L.tFor("en", "win_title"), enTitle, "tFor(en) 取英文")
eq(L.tFor("zh", "win_title"), zhTitle, "tFor(zh) 取中文")
eq(L.tFor("xx", "win_title"), zhTitle, "tFor(未知语言) 回落中文")
eq(L.code(), "zh", "tFor 不改全局状态")

print("== L.init ==")

L.init(nil)
eq(L.code(), "zh", "init(nil) → zh")

L.init({ get = function() return "en" end })
eq(L.code(), "en", "init(lang=en) → en")

L.init({ get = function() return "fr" end })
eq(L.code(), "zh", "init(未知语言) → 回落 zh")

L.init({ get = function() error("boom") end })
eq(L.code(), "zh", "init(get 抛错) → 回落 zh 不崩")

L.init({ get = function() return 123 end })
eq(L.code(), "zh", "init(get 返回非字符串) → 回落 zh")

print("== L.set ==")

local saved = nil
-- 注意：L.set 用的是 settings.set("lang", code)（点调用，不是冒号），所以第一个参数是 key
local fake = { set = function(k, v) saved = { k = k, v = v } end, get = function() return "zh" end }
L.setCode("zh")
local r1 = L.set(fake, "en")
ok(r1 == true, "set(fake,en) 返回 true")
eq(L.code(), "en", "set 后状态变 en")
ok(saved and saved.k == "lang" and saved.v == "en", "set 写回了 settings.lang=en")

local r2 = L.set(nil, "zh")
ok(r2 == false, "set(nil) 返回 false（没有 settings）")
eq(L.code(), "zh", "set(nil,zh) 状态仍生效")

local r3 = L.set({ set = function() error("boom") end }, "en")
ok(r3 == false, "set 写盘抛错 → 返回 false")
eq(L.code(), "en", "写盘失败但内存状态已变")

print("== L.needRestart ==")

L.setCode("en")
ok(L.needRestart():find("Restart") ~= nil, "en 提示英文重启文案")
L.setCode("zh")
ok(L.needRestart():find("重启") ~= nil, "zh 提示中文重启文案")

print("")
print(string.format("[lang_test] %d 通过 / %d 失败", pass, fail))
if fail > 0 then os.exit(1) end
