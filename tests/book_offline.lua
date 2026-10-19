-- =============================================================================
-- book_offline.lua —— 离线册子入口
--
-- 关键点：它调用的是**游戏内用的同一份** core/highlight.lua 和 core/text_render.lua。
-- 所以这里看到的取舍、排序、阈值，就是将来游戏内册子的行为。
--
-- 运行：tools\book.ps1
-- =============================================================================
local ROOT = (os and os.getenv and os.getenv("HLR_ROOT")) or "D:/00000/aiStudy/issacmod/"
if ROOT:sub(-1) ~= "/" then ROOT = ROOT .. "/" end
local DATA_DIR = (os and os.getenv and os.getenv("HLR_DATA")) or "data/highlight-review"
if DATA_DIR:sub(-1) ~= "/" and DATA_DIR:sub(-1) ~= "\\" then DATA_DIR = DATA_DIR .. "/" end

local function loadmod(path)
    local chunk, err = loadfile(ROOT .. path)
    if not chunk then error("loadfile failed: " .. tostring(err)) end
    return chunk()
end

-- 道具名表（由 tools\items-json.ps1 生成；没有就退回只显示 id）
local itemMap = nil
do
    local chunk = loadfile(ROOT .. "_logs/items.lua")
    if chunk then local ok, tbl = pcall(chunk); if ok and type(tbl) == "table" then itemMap = tbl end end
end
local function itemName(id)
    if not itemMap then return nil end
    local e = itemMap[id]
    if e and e.n and e.n ~= "" then return e.n end
    return nil
end

local schema = loadmod("mod/core/schema.lua")
local fmt     = loadmod("mod/core/fmt.lua")
local hl      = loadmod("mod/core/highlight.lua")
local text    = loadmod("mod/core/text_render.lua")
fmt.setSchema(schema)

-- 与 config.lua 的默认值保持一致
local CFG = { relPct = 15, absDelta = 0.5, perFloorMax = 3, topK = 5 }

local function readAll(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function listSaves()
    local out = {}
    -- 永久档案（归档脚本产出的合并文件）优先
    do
        local ap = ROOT .. "_archive/all.dat"
        local f = io.open(ap, "rb")
        if f then
            local size = f:seek("end")
            f:close()
            out[#out + 1] = { slot = 0, path = ap, size = size, label = "永久档案" }
            -- 档案是游戏存档的超集（book.ps1 会先归档），所以有档案就不再看游戏存档
            return out
        end
    end
    -- 离线环境有 io，直接列目录靠 io.popen 不稳，改用固定三个槽名探测
    for slot = 1, 3 do
        local p = DATA_DIR .. "save" .. slot .. ".dat"
        local f = io.open(p, "rb")
        if f then
            local size = f:seek("end")
            f:close()
            out[#out + 1] = { slot = slot, path = p, size = size }
        end
    end
    return out
end

local saves = listSaves()
if #saves == 0 then
    return "还没有存档：\n  " .. DATA_DIR .. "save1.dat 等文件都不存在。\n  先玩一局，或者确认 mod 的存档槽。"
end

local report = {}
local totalRuns, totalRooms = 0, 0

for _, s in ipairs(saves) do
    local blob = readAll(s.path)
    local store, warns = fmt.splitBlob(blob or "")
    totalRuns = totalRuns + #store.index

    report[#report + 1] = string.format(
        "\n########  %s  (%d 字节 / %d 局)  ########",
        s.label or ("存档槽 " .. s.slot), s.size, #store.index)
    if #warns > 0 then
        report[#report + 1] = "  警告 " .. #warns .. " 条：" .. table.concat(warns, "; ")
    end

    -- 先给一份索引摘要（不解房间体）
    report[#report + 1] = "\n── 历史局 ──"
    for i = 1, #store.index do
        local e = store.index[i]
        report[#report + 1] = string.format("  #%-3d %-12s %-8s %s层  %.2f → %.2f  %d 房",
            e.seq, e.id, (hl.resultName(e.res)), tostring(e.max), e.base, e.final, e.rooms)
        totalRooms = totalRooms + e.rooms
    end

    -- 完整册子：只解最近一局（演示"按需解码"）
    local last = store.index[#store.index]
    if last then
        local run = fmt.decodeRun(store, last)
        local book = hl.analyze(run, CFG)
        report[#report + 1] = "\n" .. text.book(book, {
            title = "高光回顾 · 最近一局",
            resultName = hl.resultName(book.result),
            roomName = hl.roomName,
            curseNames = hl.curseNames,
            duration = hl.duration,
            itemName = itemName,
        })
    end
end

report[#report + 1] = string.format(
    "\n合计 %d 局 / %d 个房间（只解码了每槽最近一局）", totalRuns, totalRooms)

-- 写文件再读，避开管道编码问题（也方便直接打开看）
local body = table.concat(report, "\n")
local outDir = ROOT .. "_logs/"
local stamp = os and os.date and os.date("%Y%m%d-%H%M%S") or "now"
local outPath = outDir .. "book-" .. stamp .. ".txt"
local f = io.open(outPath, "wb")
if f then f:write(body) f:close() end

return "OK 报告已写入: " .. outPath .. "  (" .. totalRuns .. " runs / " .. totalRooms .. " rooms)"
