-- ============================================================================
-- dump.lua —— 数据面板：把"游戏实际能给我们的字段"全量打到日志里
--
-- 目的：不靠猜。跑一次就知道你这套 60+ mod 环境里到底能拿到什么。
-- 输出以 "[HIGHLIGHT][DUMP]" 开头，方便在 log.txt 里 grep。
-- ============================================================================
local dump = {}

--- 安全读字段：userdata 上的属性可能抛错或返回 userdata
local function f(obj, key)
    local ok, v = pcall(function() return obj[key] end)
    if not ok or v == nil then return "-" end
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return tostring(v) end
    local ok2, s = pcall(tostring, v)
    if ok2 and s and not string.find(s, "userdata") and not string.find(s, "table:") then
        return s
    end
    return "<" .. t .. ">"
end

-- ---------------------------------------------------------------- 道具全表

local ITEM_FIELDS = {
    "ID", "Name", "Description", "Quality", "Type", "CacheFlags",
    "Tags", "MaxCollectibles", "Gfx", "Hidden", "ModName",
}

--- 打印全部道具。返回实际导出条数。
function dump.items(log, limit)
    limit = limit or 2000
    local ic
    local ok = pcall(function() ic = Isaac.GetItemConfig() end)
    if not ok or not ic then
        log("[DUMP] 拿不到 ItemConfig")
        return 0
    end

    local header = {}
    for i = 1, #ITEM_FIELDS do header[i] = ITEM_FIELDS[i] end
    log("[DUMP] 道具表字段：" .. table.concat(header, " | "))

    local n = 0
    for id = 1, limit do
        local okc, cfg = pcall(function() return ic:GetCollectible(id) end)
        if okc and cfg then
            local parts = {}
            for i = 1, #ITEM_FIELDS do parts[i] = f(cfg, ITEM_FIELDS[i]) end
            log(string.format("[DUMP] ITEM\t%s", table.concat(parts, "\t")))
            n = n + 1
        end
    end
    log("[DUMP] 道具总数：" .. n)
    return n
end

--- 导出 id → 本地化名 / 品质 / 贴图文件名
--- 输出格式：[DUMP] NAME\t<id>\t<quality>\t<gfx>\t<localizedName>
function dump.itemNames(log, limit)
    limit = limit or 2000
    local ic
    local ok = pcall(function() ic = Isaac.GetItemConfig() end)
    if not ok or not ic then return 0 end

    -- 先探一次 GetLocalizedString 怎么调
    local probe = "不支持"
    do
        local okp, v = pcall(function() return Isaac.GetLocalizedString("#THE_D6_NAME") end)
        if okp and (type(v) == "string" or type(v) == "userdata") then
            probe = "单参数可用（返回 " .. type(v) .. "）"
        end
        -- 返回的可能是 userdata，用 tostring 看内容
        if okp then
            local okt, s = pcall(tostring, v)
            if okt and s then probe = probe .. " / tostring=" .. s end
        end
    end
    log("[DUMP] GetLocalizedString 探针：" .. probe)

    local n = 0
    for id = 1, limit do
        local okc, cfg = pcall(function() return ic:GetCollectible(id) end)
        if okc and cfg then
            local name, gfx, q, raw = "", "", "", ""
            pcall(function()
                q = tostring(cfg.Quality)
                gfx = tostring(cfg.Gfx or "")
                local key = cfg.Name
                if type(key) == "string" then raw = key end
                if type(key) == "string" then
                    local okl, loc = pcall(function() return Isaac.GetLocalizedString(key) end)
                    if okl and loc ~= nil then
                        local okt, s = pcall(tostring, loc)
                        name = (okt and s) or ""
                    end
                end
            end)
            -- 原始 Name 里若有制表符/换行会破坏格式，清掉
            raw = (raw:gsub("[\t\r\n]", " "))
            log(string.format("[DUMP] NAME\t%d\t%s\t%s\t%s\t%s", id, q, gfx, raw, name))
            n = n + 1
        end
    end
    log("[DUMP] 名字表导出完成：" .. n .. " 条")
    return n
end

-- ---------------------------------------------------------------- 房间全字段

local DESC_FIELDS = {
    "GridIndex", "SafeGridIndex", "ListIndex", "Flags", "Clear", "ClearCount",
    "DisplayFlags", "AllowedDoors", "VisitedCount", "SpawnSeed", "AwardSeed",
    "DecorationSeed", "PitsCount", "PoopCount", "HasWater", "NoReward",
    "SurpriseMiniboss", "PressurePlatesTriggered", "SacrificeDone",
    "ShopItemIdx", "ShopDiscountIdx", "DeliriumDistance",
}

local CFG_FIELDS = {
    "StageID", "Type", "Variant", "Subtype", "Shape", "Doors", "Difficulty",
    "Weight", "InitialWeight", "Width", "Height", "Name", "SpawnCount",
}

local ROOM_PROBES = {
    "GetType", "GetRoomShape", "GetBackdropType", "GetBossID", "GetSecondBossID",
    "GetShopLevel", "GetDevilRoomChance", "IsFirstVisit", "IsClear",
    "IsCurrentRoomLastBoss", "IsSacrificeDone", "IsAmbushActive", "IsMirrorWorld",
}

--- 打印当前房间的全部可得字段
function dump.room(log)
    local ok = pcall(function()
        local game = Game()
        local room = game:GetRoom()
        local desc = game:GetLevel():GetCurrentRoomDesc()

        log("[DUMP] ===== 当前房间 =====")

        -- Room 方法探针：哪些能用、返回什么
        for _, name in ipairs(ROOM_PROBES) do
            local okm, v = pcall(function() return room[name](room) end)
            if okm then
                log(string.format("[DUMP] room.%s() = %s", name, f({ v = v }, "v")))
            else
                log(string.format("[DUMP] room.%s() = <不可用>", name))
            end
        end

        -- RoomDescriptor 字段
        for _, key in ipairs(DESC_FIELDS) do
            log(string.format("[DUMP] desc.%s = %s", key, f(desc, key)))
        end

        -- RoomConfigRoom 字段（OverrideData 是 miniboss 之类的替换数据）
        local cfg = desc.OverrideData or desc.Data
        local src = desc.OverrideData and "OverrideData" or "Data"
        log("[DUMP] 配置来源：" .. src)
        for _, key in ipairs(CFG_FIELDS) do
            log(string.format("[DUMP] cfg.%s = %s", key, f(cfg, key)))
        end

        -- 道具座（静态坐标，13x7 配置网格）
        local okS, spawns = pcall(function() return cfg.Spawns end)
        if okS and spawns then
            local size = f(spawns, "Size")
            log("[DUMP] cfg.Spawns.Size = " .. size)
            local n = tonumber(size) or 0
            for i = 0, math.min(n, 19) - 1 do
                local okp, sp = pcall(function() return spawns:Get(i) end)
                if okp and sp then
                    log(string.format("[DUMP] spawn[%d] X=%s Y=%s entries=%s",
                        i, f(sp, "X"), f(sp, "Y"), f(sp, "EntryCount")))
                end
            end
        end

        -- 道具池：探针，看运行时能不能读
        log("[DUMP] ===== 道具池探针 =====")
        local okP, pool = pcall(function() return game:GetItemPool() end)
        if okP and pool then
            local probes = {
                "GetCollectible", "AddItem", "RemoveItem", "GetNumCollectibles",
                "GetCollectibleFromPool", "GetPoolForCollectible", "GetRemovedCollectibles",
            }
            for _, name in ipairs(probes) do
                local ok2 = pcall(function() return pool[name] end)
                log(string.format("[DUMP] pool.%s = %s", name, ok2 and "存在" or "无"))
            end
        else
            log("[DUMP] Game():GetItemPool() 不可用")
        end
    end)
    if not ok then log("[DUMP] 房间 dump 出错（已忽略）") end
end

return dump
