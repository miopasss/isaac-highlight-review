-- =============================================================================
-- rating_test.lua —— 评级/权重数据层的离线自检
-- 运行：tools\luarun.ps1 tests\rating_test.lua
-- =============================================================================
local ROOT = (os and os.getenv and os.getenv("HLR_ROOT")) or "D:/00000/aiStudy/issacmod/"
if ROOT:sub(-1) ~= "/" then ROOT = ROOT .. "/" end
local function loadmod(p) return loadfile(ROOT .. p)() end

local J = loadmod("mod/core/jsonmini.lua")
local R = loadmod("mod/core/rating.lua")

local pass, fail = 0, 0
local function check(name, cond, detail)
    if cond then pass = pass + 1
    else fail = fail + 1; print(string.format("  FAIL  %-46s  %s", name, tostring(detail))) end
end

-- ① JSON 编解码
local ok, enc = J.selftest()
check("jsonmini 自检", ok, enc)
print("  编码结果: " .. tostring(enc))

-- ② 装默认表
R.init(J, {
    [1052] = { q = 2.0, w = 0.5 },   -- 默认：官方 4 级，这里 2
})
R.publish()

check("默认表生效：getRating(1052)=2.0", R.getRating(1052) == 2.0, R.getRating(1052))
check("默认表生效：getQuality(1052)=2", R.getQuality(1052) == 2, R.getQuality(1052))
check("未配置道具返回 nil", R.getRating(118) == nil, R.getRating(118))

-- ③ 写覆盖
R.set(118, 3.5, 2.0)
check("覆盖后 getRating(118)=3.5", R.getRating(118) == 3.5, R.getRating(118))
check("向下取整：3.5 → 3（不算四级）", R.getQuality(118) == 3, R.getQuality(118))
check("覆盖优先于默认", R.getRating(1052) == 2.0, R.getRating(1052))
R.set(1052, 4.0, 1.0)
check("覆盖掉默认后 = 4.0", R.getRating(1052) == 4.0, R.getRating(1052))

-- ④ 启用开关
R.set(118, nil, nil, false)
check("停用后 getRating 返回 nil", R.getRating(118) == nil, R.getRating(118))
check("停用后 getWeightMul 返回 nil", R.getWeightMul(118) == nil, R.getWeightMul(118))
R.set(118, nil, nil, true)
check("重新启用后恢复 3.5", R.getRating(118) == 3.5, R.getRating(118))

-- ⑤ 存盘 → 读盘
local store = { lines = { "R\t1\ttest", "M\t1\t1\t4" } }
R.save(store)
local qLine = nil
for _, l in ipairs(store.lines) do if l:sub(1, 2) == "Q=" then qLine = l end end
check("Q= 行已写入", qLine ~= nil, qLine)
check("其他行没被破坏", #store.lines == 3, #store.lines)
print("  存档行: " .. tostring(qLine))

R.entries = {}
R.load(store)
check("读盘后 118 恢复", R.getRating(118) == 3.5, R.getRating(118))
check("读盘后 1052 恢复", R.getRating(1052) == 4.0, R.getRating(1052))

-- ⑥ 清除
R.clear(118)
check("清除后回退（118 无配置）", R.getRating(118) == nil, R.getRating(118))
check("清除后 1052 仍在", R.getRating(1052) == 4.0, R.getRating(1052))

-- ⑦ 坏数据容错
R.entries = J.decode('{"v":1,"e":{"abc":{"q":1}}}') or {}
check("非数字 id 被忽略", next(R.entries) == nil, next(R.entries))
R.entries = J.decode("这不是 json") or {}
check("乱码返回空表", next(R.entries) == nil, next(R.entries))
check("版本号缺失返回空表", next(J.decode('{"e":{"118":{"q":3}}}')) == nil, "ok")

print("")
print(string.format("结果：%d 通过 / %d 失败", pass, fail))
return pass .. "/" .. (pass + fail)
