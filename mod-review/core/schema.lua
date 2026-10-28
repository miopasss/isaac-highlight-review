-- ============================================================================
-- schema.lua —— 数据字段的**唯一真相**
--
-- 加一个新需求 = 在这里加一行 + 在采集处赋值。编码器/解码器/解析脚本全都不用改。
--
-- 类型标记：
--   i = 整数          f = 小数（保留 2 位）      s = 字符串
--   l = 整数列表(+)   h = 十六进制串             b = 布尔(1/0)
--
-- 作用域：
--   R = 一局（run）    F = 一层（floor）    M = 一个房间（room）
-- ============================================================================
local schema = {}

schema.version = 2
schema.magic   = "MRV2"

-- 每种类型缺省值（解码时缺键 → 用这个）
schema.defaults = {
    i = 0, f = 0, s = "", l = {}, h = "", b = false,
}

-- 每种作用域必须出现的键（其余可以省略，解码时补默认）
schema.required = {
    R = { "seq" },
    F = { "r", "i" },
    M = { "t" },
}

schema.scopes = {
    -- 一局
    R = {
        seq   = "i",   -- 局序号，单调递增
        id    = "s",   -- runId：种子-角色
        seed  = "i",   -- 原始种子（排查用）
        char  = "i",   -- 角色 id
        base  = "f",   -- 起点战力
        final = "f",   -- 终点战力
        max   = "i",   -- 到达的最深层
        res   = "i",   -- 0 死 / 1 通关 / 2 未完成
        t0    = "i",   -- 开始时间戳（秒，游戏内计时）
        ws    = "s",   -- 开始墙钟时间文本（"2026/10/22 14:36"；os.date 取不到就是空）
        we    = "s",   -- 结束墙钟时间文本（作者 2026-10-28 要求；未完成则空）
        hl    = "i",   -- 高光条数（v0.1 恒为 0）
    },

    -- 一层
    F = {
        r     = "i",   -- 属于哪一局（局序号）
        i     = "i",   -- 本局内第几层（从 1 起）
        stage = "i",   -- LevelStage
        type  = "i",   -- StageType
        seed  = "i",   -- 该层的 stage seed
        curse = "i",   -- 诅咒位掩码（Level:GetCurses()）：1黑暗 2迷宫 4迷失 8未知 16诅咒 32迷阵 64失明 128巨大
        alt   = "i",   -- 是否富裕/镜像路线
        t     = "i",   -- 进入该层的时间戳（秒）
        ms    = "i",   -- 在该层停留毫秒
    },

    -- 一个房间
    M = {
        r     = "i",   -- 属于哪一局
        f     = "i",   -- 第几层
        i     = "i",   -- 本层内第几间
        t     = "i",   -- 房型 RoomType
        s     = "i",   -- 形状 RoomShape
        d     = "i",   -- 门位掩码
        st    = "i",   -- 房间配置 StageID
        v     = "i",   -- 房间配置 Variant
        list  = "i",   -- desc.ListIndex

        hbl   = "i",   -- 进房：黑心（半心）
        hgo   = "i",   -- 进房：金心（半心）
        het   = "i",   -- 进房：永恒心（半心）
        hrt   = "i",   -- 进房：腐烂心（半心）
        dvo   = "f",   -- 六维：伤害（出房）
        tso   = "f",   -- 六维：攻速（进房）
        sso   = "f",   -- 六维：弹速（进房）
        rgo   = "f",   -- 六维：射程（进房）
        mvo   = "f",   -- 六维：移速（进房）
        lko   = "f",   -- 六维：幸运（进房）
        ts    = "f",   -- 六维：攻速（出房，次/秒）
        ss    = "f",   -- 六维：弹速
        rg    = "f",   -- 六维：射程
        mv    = "f",   -- 六维：移速
        lk    = "f",   -- 六维：幸运
        hp    = "i",   -- 进房：红心（半心，不含容器）
        hs    = "i",   -- 进房：魂心（半心）
        hb    = "i",   -- 进房：骨心（颗）
        hpo   = "i",   -- 出房：红心
        hso   = "i",   -- 出房：魂心
        hbo   = "i",   -- 出房：骨心

        p     = "f",   -- 进房战力
        po    = "f",   -- 出房战力
        ms    = "i",   -- 停留毫秒
        dmg   = "i",   -- 受伤量
        clr   = "b",   -- 是否清房
        it    = "l",   -- 本房获得的道具 id
        iq    = "l",   -- 与 it 平行的品质（0~4）→ 用来识别 4 级起飞 / 0 级封盘
        ie    = "l",   -- 与 it 平行：本房每件道具带来的战力增量（小数用 %.4f 存，负数=掉战力）
    ik    = "l",   -- 与 it 平行：离开房间时是否仍持有（1=还在，0=临时塞进来的）
        foes  = "i",   -- 进房时敌人数量（房间强度代理）
        mxhp  = "i",   -- 进房最大血量（半心）
        mxhpo = "i",   -- 出房最大血量（半心）
        c     = "i",   -- 进房金币
        co    = "i",   -- 出房金币
        lc    = "i",   -- 本房捡到的幸运币数（CoinSubType.COIN_LUCKYPENNY）
        bmb   = "i",   -- 进房炸弹
        bmbo  = "i",   -- 出房炸弹
        key   = "i",   -- 进房钥匙
        keyo  = "i",   -- 出房钥匙
        boss  = "i",   -- 房间 subtype（GetBossID，boss 房才有）
        ub    = "i",   -- 终极 Boss 代码：1Hush 2BossRush 3超级撒旦 4老干妈 5祸兽 6百变怪（0=无）
        first = "b",   -- 是否首次访问该房间
        fli   = "b",   -- 进房：是否会飞（player.CanFly）
        fl    = "b",   -- 出房：是否会飞
        exi   = "b",   -- 进房：是否防爆（Pyromaniac 223 / Host Hat 375）
        ex    = "b",   -- 出房：是否防爆
        dv    = "f",   -- 诊断：快照时的面板伤害
        mu    = "i",   -- 诊断：快照时的弹幕数
        fm    = "s",   -- 诊断：快照时的攻击形态
        tri   = "l",   -- 进房时手上的饰品
        tro   = "l",   -- 出房时手上的饰品
        pd    = "h",   -- 道具座坐标（默认关）
    },

    -- 一颗药丸（作者 2026-10-21 需求；2026-10-25 从 feature/pill-ledger-v0.3.2 恢复）
    -- 只记 id + 层/房；属性影响靠 core/pills.lua 白名单查表
    -- （回读属性会抓到临时值，还会被大药丸/金药丸的倍数搞乱）
    P = {
        r    = "i",   -- 属于哪一局
        f    = "i",   -- 第几层
        i    = "i",   -- 本层内第几间
        e    = "i",   -- PillEffect id
    },
}

--- 该作用域的键列表（顺序稳定，便于对比 diff）
function schema.keys(scope)
    local list = {}
    for k in pairs(schema.scopes[scope]) do list[#list + 1] = k end
    table.sort(list)
    return list
end

function schema.typeOf(scope, key)
    local s = schema.scopes[scope]
    if not s then return nil end
    return s[key]
end

function schema.defaultFor(scope, key)
    local t = schema.typeOf(scope, key)
    if not t then return nil end
    local d = schema.defaults[t]
    if type(d) == "table" then return {} end   -- 每次给新表，避免共享
    return d
end

--- 导出成 JSON 友好的结构，供 PowerShell 解析脚本读取
function schema.export()
    return {
        version = schema.version,
        magic   = schema.magic,
        scopes  = schema.scopes,
    }
end

return schema
