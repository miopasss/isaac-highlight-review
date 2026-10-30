-- ============================================================================
-- settings_test.lua —— settings（热键 / 语言 + C0 一代备份）的离线单测
--
-- 覆盖分支：
--   · 读 C= 正常
--   · C= 缺失但 C0= 存在 → 用 C0 兜底
--   · C= 和 C0= 都没有 → 保持默认
--   · 保存时旧 C= 变成 C0=（一代备份）
--   · 重复保存不会累积多条 C0=
--   · S.only 只写指定键
--   · 字符串值（lang）与数字值（f6/f5）都能往返
-- ============================================================================

local ROOT = "D:/00000/aiStudy/issacmod/"
local S = loadfile(ROOT .. "shared/core/settings.lua")()

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1
    else fail = fail + 1; print("  FAIL: " .. tostring(msg)) end
end
local function eq(actual, expected, msg)
    ok(actual == expected, string.format("%s  期望=%s 实际=%s", msg, tostring(expected), tostring(actual)))
end

local function countPrefix(lines, prefix)
    local n = 0
    for _, l in ipairs(lines) do
        if l:sub(1, #prefix) == prefix then n = n + 1 end
    end
    return n
end

print("== 读取 ==")

-- 分支 1：C= 正常
S.init()
S.load({ lines = { 'C={"f5":294,"f6":295,"lang":"zh"}' } })
eq(S.get("f5"), 294, "读 C= 的 f5")
eq(S.get("f6"), 295, "读 C= 的 f6")
eq(S.get("lang"), "zh", "读 C= 的 lang（字符串值）")

-- 分支 2：C= 缺失，C0= 存在 → 兜底
S.init()
S.load({ lines = { 'C0={"f5":291,"lang":"en"}' } })
eq(S.get("f5"), 291, "C= 缺失时用 C0= 的 f5")
eq(S.get("lang"), "en", "C= 缺失时用 C0= 的 lang")

-- 分支 3：两者都没有 → 默认值
S.init()
S.load({ lines = {} })
eq(S.get("f6"), 295, "没有配置行时 f6 用默认 295")
eq(S.get("lang"), "zh", "没有配置行时 lang 用默认 zh")

-- 分支 4：坏数据不崩
S.init()
S.load({ lines = { 'C=乱码', 'C0=也乱码' } })
ok(type(S.get("f6")) == "number", "坏数据时 f6 仍是数字（回落默认）")

print("== 保存：一代备份 ==")

-- 分支 5：保存时旧 C= → C0=，且只有一条
S.init()
local store = { lines = { 'C={"f6":295,"lang":"zh"}', 'Q={"v":1,"e":{}}' } }
S.set("f6", 296)                 -- 先改值
S.save(store)
eq(countPrefix(store.lines, "C="), 1, "保存后 C= 只有 1 条")
eq(countPrefix(store.lines, "C0="), 1, "保存后 C0= 只有 1 条（一代备份）")
ok(table.concat(store.lines, "\n"):find('"f6":296') ~= nil, "新值写进了 C=")
ok(table.concat(store.lines, "\n"):find('"f6":295') ~= nil, "旧值留在 C0=")

-- 分支 6：重复保存不累积 C0=
S.set("f6", 297)
S.save(store)
S.set("f6", 298)
S.save(store)
eq(countPrefix(store.lines, "C0="), 1, "连续保存 3 次后 C0= 仍只有 1 条")
eq(countPrefix(store.lines, "C="), 1, "连续保存 3 次后 C= 仍只有 1 条")

-- 分支 7：保存不动别的行（Q= 还在）
ok(table.concat(store.lines, "\n"):find("Q=") ~= nil, "保存不影响其它行（Q= 保留）")

print("== S.only：只写自己的键 ==")

S.init()
S.only = { "f5" }
local store2 = { lines = { 'C={"f5":294,"f6":295,"lang":"zh"}' } }
S.set("f5", 300)
S.save(store2)
-- 只看**新的 C= 行**：C0= 里保存的是旧行，旧行本来就含 f6/lang（这是备份，不算违规）
local cLine = nil
for _, l in ipairs(store2.lines) do
    if l:sub(1, 2) == "C=" then cLine = l end
end
ok(cLine ~= nil, "有 C= 行")
ok(cLine and cLine:find('"f5":300') ~= nil, "only={f5} 时写入 f5")
ok(cLine and cLine:find('"f6"') == nil, "only={f5} 时新 C= 不写 f6")
ok(cLine and cLine:find('"lang"') == nil, "only={f5} 时新 C= 不写 lang")
ok(countPrefix(store2.lines, "C0=") == 1, "旧 C= 被完整备份到 C0=（含 f6/lang）")

S.only = nil   -- 复位，别影响后续
S.init()
S.load({ lines = {} })

print("== 往返（保存 → 重新读）==")

S.init()
S.only = nil
local store3 = { lines = {} }
S.set("f6", 301)
S.set("lang", "en")
S.save(store3)
S.init()
S.load(store3)
eq(S.get("f6"), 301, "往返后 f6 一致")
eq(S.get("lang"), "en", "往返后 lang 一致")

print("")
print(string.format("[settings_test] %d 通过 / %d 失败", pass, fail))
if fail > 0 then os.exit(1) end
