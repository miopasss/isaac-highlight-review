-- =============================================================================
-- rating_test.lua —— 评级/权重数据层的离线自检
-- 运行：tools\luarun.ps1 tests\rating_test.lua
-- =============================================================================
local ROOT = (os and os.getenv and os.getenv("HLR_ROOT")) or "D:/00000/aiStudy/issacmod/"
if ROOT:sub(-1) ~= "/" then ROOT = ROOT .. "/" end
local function loadmod(p) return loadfile(ROOT .. p)() end

local J = loadmod("mod-rating/core/jsonmini.lua")
local R = loadmod("mod-rating/core/rating.lua")
local IM = loadmod("mod-rating/core/idmap.lua")

-- 假 ItemConfig：只放测试用的几件道具（id 与"现状"一致）
local FAKE_ITEMS = {
    [1]    = { Name = "The Sad Onion" },
    [118]  = { Name = "#BRIMSTONE_NAME" },
    [953]  = { Name = "Tooth of the Vampire" },
    [975]  = { Name = "Peerless Elixir" },
    [2000] = { Name = "字刀" },
}
_G.Isaac = {
    GetItemConfig = function()
        return { GetCollectible = function(_, id) return FAKE_ITEMS[id] end }
    end,
    -- 故意让它查不到：逼 idmap 用本地索引（线上那句也要能兜底）
    GetItemIdByName = function() return 0 end,
}

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
}, IM)
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

-- ⑤ 防丢失保护：没读过档时不允许写
local store0 = { lines = { "R\t1\ttest" } }
check("未 load 时 save 被拒绝", R.save(store0) == false, "save 返回了 true")
check("未 load 时不会动存档行", #store0.lines == 1, #store0.lines)

-- ⑤b 存盘 → 读盘
local store = { lines = { "R\t1\ttest", "M\t1\t1\t4" } }
R.load(store)          -- 模拟"已读档"（会清空 entries）
R.set(118, 3.5, 2.0)
R.set(1052, 4.0, 1.0)
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

-- ⑤c 已有 Q= 行时重新读档（模拟"重启游戏"）：必须还能写盘
-- 回归：R.load 找到 Q 行后直接 return，没置 loaded=true → save 永远被拒
local R2 = loadmod("mod-rating/core/rating.lua")
R2.init(J, {})
local store2 = { lines = { 'Q={"v":1,"e":{"118":{"q":3.5,"w":0.5}}}' } }
R2.load(store2)
check("已有 Q 行：load 后 loaded=true", R2.loaded == true, tostring(R2.loaded))
R2.set(118, 4.0, 0.5)
check("已有 Q 行：save 不被拒绝", R2.save(store2) == true, "save 返回 false")
local q2 = nil
for _, l in ipairs(store2.lines) do if l:sub(1, 2) == "Q=" then q2 = l end end
check("已有 Q 行：新值写回", q2 ~= nil and q2:find('"q":4') ~= nil, q2)

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

-- ⑧ 抗 id 漂移：名字优先，本地索引兜底，找不到的挂起（不准落到旧 id 上）
IM.invalidate()
local okIM, det = IM.selftest()
check("idmap 自检", okIM, det)

local R3 = loadmod("mod-rating/core/rating.lua")
R3.init(J, {}, IM)
local st3 = { lines = { [[Q={"v":1,"e":{"1074":{"q":3,"w":0.5,"n":"Peerless Elixir"},"1598":{"q":1,"w":0,"n":"亚波伦之翼"},"118":{"q":4,"w":1,"n":"#BRIMSTONE_NAME"},"2000":{"q":2,"w":1}}}]] } }
R3.load(st3)
check("漂移：1074 按名字迁到 975", R3.getWeightMul(975) == 0.5, tostring(R3.getWeightMul(975)))
check("漂移：旧 id 1074 不再生效", R3.getWeightMul(1074) == nil, tostring(R3.getWeightMul(1074)))
check("消失的道具被挂起（1598 不生效）", R3.getWeightMul(1598) == nil, "还在生效")
check("挂起计数 = 1", R3.parkedCount() == 1, R3.parkedCount())
check("本地化 key 归一化后对上 118", R3.getRating(118) == 4, R3.getRating(118))
check("没名字的条目被补名 2000=字刀", (R3.entries[2000] or {}).n == "字刀", (R3.entries[2000] or {}).n)
check("补名后仍然生效", R3.getRating(2000) == 2, R3.getRating(2000))

-- 挂起的条目必须写回存档（mod 回来时才能自动复活）
R3.save(st3)
local q3 = nil
for _, l in ipairs(st3.lines) do if l:sub(1, 2) == "Q=" then q3 = l end end
check("挂起条目写回存档", q3 ~= nil and q3:find("亚波伦之翼") ~= nil, q3)

print("")
print(string.format("结果：%d 通过 / %d 失败", pass, fail))
return pass .. "/" .. (pass + fail)
