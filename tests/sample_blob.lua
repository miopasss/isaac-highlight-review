-- =============================================================================
-- sample_blob.lua —— 生成一份"假想存档"，用来直观展示落盘后文件长什么样
-- 运行：tools\luarun.ps1 tests\sample_blob.lua
-- =============================================================================
local ROOT = (os and os.getenv and os.getenv("HLR_ROOT")) or "D:/00000/aiStudy/issacmod/"
if ROOT:sub(-1) ~= "/" then ROOT = ROOT .. "/" end

local fmt = loadfile(ROOT .. "mod/core/fmt.lua")()

-- 一局打 4 个房间的样子（数值取自"初始以撒 3.5 伤害 / 2.73 攻速"）
local run = {
    seq = 17,
    id = "A1B2C3D4-0",
    startedAt = 1760889600,
    char = 0,
    result = 0,
    maxFloor = 2,
    basePower = 3.50,     -- 9.55 DPS 的等价（这里直接存面板战力）
    finalPower = 22.80,
    hlCount = 0,
    rooms = {
        -- 1 层 · 普通房：没变化
        { floor = 1, type = 1, shape = 1, doors = 10, stageId = 1, variant = 5,
          hpIn = 6, hpOut = 6, pIn = 9.55, pOut = 9.55, ms = 3800, dmg = 0,
          peds = {}, items = {} },
        -- 1 层 · 宝箱房：拿了道具 118（Brimstone）→ 战力跳变
        { floor = 1, type = 4, shape = 1, doors = 3, stageId = 1, variant = 12,
          hpIn = 6, hpOut = 6, pIn = 9.55, pOut = 22.80, ms = 900, dmg = 0,
          peds = { { x = 6, y = 3 } }, items = { 118 } },
        -- 1 层 · Boss 房：受伤
        { floor = 1, type = 5, shape = 1, doors = 1, stageId = 1, variant = 200,
          hpIn = 6, hpOut = 4, pIn = 22.80, pOut = 22.80, ms = 15200, dmg = 1,
          peds = {}, items = {} },
        -- 2 层 · 恶魔房：道具座在角落
        { floor = 2, type = 14, shape = 1, doors = 2, stageId = 2, variant = 9,
          hpIn = 4, hpOut = 4, pIn = 22.80, pOut = 22.80, ms = 2100, dmg = 0,
          peds = { { x = 3, y = 2 }, { x = 9, y = 2 } }, items = {} },
    },
}

local old = {
    seq = 16, id = "FFFF0000-5", startedAt = 1760803200, char = 5, result = 1,
    maxFloor = 3, basePower = 3.50, finalPower = 11.20, hlCount = 0,
    rooms = {
        { floor = 1, type = 1, shape = 1, doors = 5, stageId = 1, variant = 77,
          hpIn = 6, hpOut = 6, pIn = 9.55, pOut = 11.20, ms = 6400, dmg = 0,
          peds = {}, items = { 1 } },
    },
}

local blob = fmt.encodeBlob({ old, run })
return string.format("=== data/highlight-review/save1.dat（共 %d 字节）===\n%s\n=== EOF ===", #blob, blob)
