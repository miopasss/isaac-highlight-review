-- ============================================================================
-- ui/book.lua —— 游戏内册子（羊皮纸 · MCM 式结构）
--
-- F5 开关。页序：Overview → 亮点回顾（战力 Top3 / 四级 / 零级）→ 各层。
--
-- 三条硬规则（都是踩坑换来的）：
--   1. 界面上**只能出现 ASCII**。游戏位图字体没有中文，中文会变乱码。
--   2. 线段/图标的位置**按实际字宽算**，不要用硬编码坐标（字体一变就错位）。
--   3. 道具图标用 ReplaceSpritesheet(sheetId=1, png)，之后必须 LoadGraphics()。
-- ============================================================================
local book = {}

local deps = nil
local isOpen = false
local page = 1
local selRun = 1
local cache = {}
local paper, paperTried = nil, false
local iconCache = {}
local holdNext = 0

local RES_NAME = { [0] = "DEAD", [1] = "WIN", [2] = "UNFINISHED" }

local INK     = { 0.16, 0.12, 0.08 }   -- 主文字（更深）
local INK_DIM = { 0.33, 0.26, 0.17 }   -- 次要文字（原 0.45 太浅）
local INK_RED = { 0.46, 0.10, 0.06 }   -- 标题红
local INK_UP  = { 0.10, 0.32, 0.12 }   -- 上涨绿
local INK_DN  = { 0.50, 0.08, 0.05 }   -- 下跌红
local BAR_ON  = { 0.36, 0.52, 0.26 }
local BAR_OFF = { 0.62, 0.58, 0.50 }
local BAR_BASE = { 0.55, 0.36, 0.18 }   -- 原有属性（棕）
local BAR_GAIN = { 0.26, 0.60, 0.28 }
local BAR_DOWN = { 0.72, 0.24, 0.24 }   -- 属性下降的格子（红）

local bodyFont, titleFont, hudFont, fontTried = nil, nil, nil, false
local cjkFont, cjkTried = nil, false

-- 借用 EID 的中文字体（EID 没装就回退英文）
-- Font:Load 只认三种路径（实测 + 调研结论）：
--   ① mod 自己的 VFS 键      "font/xxx.fnt"
--   ② 游戏根相对             "mods/highlight-review/resources/font/xxx.fnt"
--   ③ 绝对 Windows 路径
-- "../mods/..." 一律无效（EID 里那段是死代码，从未执行过）
-- 实测结论（2026-10-20）：只有「游戏根相对」这种形式能加载成功
--   ✔ "mods/highlight-review/resources/font/eid_cn_alt.fnt"  ← IsLoaded=true, 汉字宽度 36
--   ✘ "font/eid_cn_alt.fnt"（VFS 键）        IsLoaded=false, lineHeight 是垃圾值
--   ✘ "../mods/..."（EID 里的死代码形式）      IsLoaded=false
local CJK_CANDIDATES = {
    "mods/highlight-review/resources/font/eid_cn_alt.fnt",
    "mods/highlight-review/resources/font/eid_cn_default.fnt",
    "font/eid_cn_alt.fnt",
}

--- 中文探针：游戏自带的 mplus 字体带日文汉字，可能覆盖部分中文
local function getCJK()
    if cjkTried then return cjkFont end
    cjkTried = true

    for i = 1, #CJK_CANDIDATES do
        local path = CJK_CANDIDATES[i]
        local ff = Font()
        local ok, loadRet = pcall(function()
            return ff:Load(path, "")
        end)
        pcall(function() ff:SetMissingCharacter(2) end)
        if not ok then
            if deps and deps.log then
                deps.log("[CJK] " .. path .. " → Load 抛错: " .. tostring(loadRet))
            end
        else
            local loaded, w, wA, lh = false, 0, 0, 0
            pcall(function() loaded = ff:IsLoaded() end)
            pcall(function() w = ff:GetStringWidth("伤害") or 0 end)
            pcall(function() wA = ff:GetStringWidth("AA") or 0 end)
            pcall(function() lh = ff:GetLineHeight() or 0 end)
            if deps and deps.log then
                deps.log(string.format("[CJK] probe %s | Load返回=%s | IsLoaded=%s | width(汉字)=%s | width(AA)=%s | lineHeight=%s",
                    path, tostring(loadRet), tostring(loaded), tostring(w), tostring(wA), tostring(lh)))
            end
            if loaded and w > 0 then
                cjkFont = ff
                if deps and deps.log then
                    deps.log(string.format("[CJK] OK %s  (lineWidth=%.1f)", path, w))
                end
                return cjkFont
            end
            if deps and deps.log then
                deps.log(string.format("[CJK] FAIL %s  IsLoaded=%s width=%s",
                    path, tostring(loaded), tostring(w)))
            end
        end
    end

    if deps and deps.log then deps.log("[CJK] 全部候选失败，回退英文") end
    return nil
end
--- 画一段中文（没有中文字体时返回 false）
local function txtCN(str, x, y, scale, col)
    local f = getCJK()
    if not f then return false end
    local k = scale * 1.45
    local ok = pcall(function()
        f:DrawStringUTF8(str, x, y, KColor(col[1], col[2], col[3], 1), 0, false)
    end)
    return ok
end

function book.init(d)
    deps = d
    -- 字体必须在**初始化阶段**加载：EID 也是在 main.lua 顶部加载的，
    -- 渲染回调里加载资源可能被引擎拒绝。
    pcall(function() getCJK() end)
end

-- ---------------------------------------------------------------- 基础设施

local function scr()
    return Isaac.GetScreenWidth(), Isaac.GetScreenHeight(), (Isaac.GetScreenHeight() / 270)
end

local function loadFonts()
    if fontTried then return end
    fontTried = true
    pcall(function() local f = Font(); f:Load("font/teammeatfont12.fnt"); bodyFont = f end)
    -- HUD 那行用星象房同款描边字（原生字太小看不清，作者 2026-10-22）
    pcall(function() local f = Font(); f:Load("font/luaminioutlined.fnt"); hudFont = f end)
    pcall(function() local f = Font(); f:Load("font/teammeatfontextended16bold.fnt"); titleFont = f end)
end

local function getPaper()
    if paperTried then return paper end
    paperTried = true
    local ok, sp = pcall(function()
        local s = Sprite(); s:Load("gfx/ui/hl_paper.anm2"); s:Play("Idle"); return s
    end)
    if ok and sp then paper = sp end
    return paper
end

--- 预加载：**必须在 mod 加载阶段**调用（main.lua 顶层），不要等到 POST_RENDER。
--- 在渲染回调里首次做 Font:Load / Sprite:Load 会在渲染上下文里申请资源，
--- 实测会留下不平衡的 render target，之后每帧刷
--- "[ASSERT] - PushRenderTarget: stack overflow!"，而且关掉册子也不停。
function book.preload()
    loadFonts()
    getPaper()
    getCJK()
end

local function rect(x, y, w, h, r, g, b, a)
    local p = getPaper()
    if not p or w <= 0 or h <= 0 then return end
    p.Scale = Vector(w / 256.0, h / 256.0)
    p.Color = Color(r or 1, g or 1, b or 1, a or 1, 0, 0, 0)
    p:Render(Vector(x, y))
end

local cjkErrLogged = false
local function hasNonAscii(str) return str:find("[\128-\255]") ~= nil end

--- 统一文字出口：
---   纯 ASCII → 游戏位图字体（teammeat）
---   含非 ASCII → 中文位图字体（借 EID 的），没有就降级成 ?
local function txt(s, x, y, scale, col, isTitle)
    loadFonts()
    col = col or INK
    local k = scale * 1.45
    local k1 = k
    local str = tostring(s)

    if hasNonAscii(str) then
        local cf = getCJK()
        if cf then
            -- EID 用的就是这个带缩放的 UTF8 版本（eid_api.lua 里大量出现）
            local ok, err = pcall(function()
                cf:DrawStringScaledUTF8(str, x, y, k1, k1, KColor(col[1], col[2], col[3], 1), 0, false)
            end)
            if ok then return end
            if deps and deps.log and not cjkErrLogged then
                cjkErrLogged = true
                deps.log("[CJK] DrawStringScaledUTF8 失败：" .. tostring(err))
            end
        end
        str = str:gsub("[\128-\255]+", "?")
    end

    local f = isTitle and titleFont or bodyFont
    if f then
        f:DrawStringScaled(str, x, y, k, k, KColor(col[1], col[2], col[3], 1), 0, false)
    else
        Isaac.RenderScaledText(str, x, y, col[1], col[2], col[3], 1, k, k)
    end
end

--- 一段文字的像素宽度（用于动态排版）
local function textW(str, scale)
    loadFonts()
    local k = scale * 1.45
    str = tostring(str)
    local f
    if hasNonAscii(str) then
        f = getCJK() or bodyFont
    else
        f = bodyFont
    end
    if f then
        local ok, w = pcall(function() return f:GetStringWidth(str) end)
        if ok and w then return w * k end
    end
    return #str * 6 * k
end

--- 道具图标（32×32）。sheetId=1 是实测可用的写法。
local iconDbg = 0
local function dbg(msg)
    iconDbg = iconDbg + 1
    if iconDbg <= 8 and deps and deps.log then deps.log("[ICON] " .. msg) end
end

--- 道具图标：字段名是 GfxFileName（不是 Gfx），sheet id 用 1
local function itemIcon(id)
    local e = iconCache[id]
    if e ~= nil then return e or nil end

    local cfg
    local okc = pcall(function() cfg = Isaac.GetItemConfig():GetCollectible(id) end)
    if not okc or not cfg then dbg(tostring(id) .. " GetCollectible 失败"); iconCache[id] = false; return nil end

    local path = cfg.GfxFileName
    if not path or path == "" then
        dbg(tostring(id) .. " GfxFileName 为空")
        iconCache[id] = false
        return nil
    end

    -- GfxFileName 可能是 "collectibles_xxx.png"，也可能已经带目录
    local candidates = { path }
    if not path:find("/") then
        candidates[2] = "gfx/items/collectibles/" .. path
    end

    for ci = 1, #candidates do
        local ok, sp = pcall(function()
            local s = Sprite()
            s:Load("gfx/ui/hl_icon.anm2", true)
            s:ReplaceSpritesheet(1, candidates[ci])
            s:LoadGraphics()
            s:Play("Idle")
            return s
        end)
        if ok and sp then
            dbg(string.format("%d OK  %s", id, candidates[ci]))
            iconCache[id] = sp
            return sp
        end
        dbg(string.format("%d FAIL %s", id, candidates[ci]))
    end

    iconCache[id] = false
    return nil
end
--- 分段条
--- 双色分段条：棕色 = 原有属性，绿色 = 本房增加
local function segBar2(x, y, w, h, fracBase, fracTotal, n)
    n = n or 20
    local gap = 0.9
    local bw = (w - gap * (n - 1)) / n
    if bw <= 0 then return end
    -- 上升/下降都要能画：取出两端的较小/较大值，中间那段按方向着色
    local inc = (fracTotal >= fracBase)
    local lo  = inc and fracBase or fracTotal
    local hi  = inc and fracTotal or fracBase
    for i = 1, n do
        local mid = ((i - 1) / n + i / n) / 2
        local col, a
        if mid <= lo then col, a = BAR_BASE, 0.85
        elseif mid <= hi then
            if inc then col, a = BAR_GAIN, 0.95 else col, a = BAR_DOWN, 1.0 end
        else col, a = BAR_OFF, 0.25 end
        rect(x + (i - 1) * (bw + gap), y, bw, h, col[1], col[2], col[3], a)
    end
end

local function segBar(x, y, w, h, frac, onCol, offCol, n)
    n = n or 20               -- 段数翻倍 = 每格宽度减半
    local gap = 0.9
    local bw = (w - gap * (n - 1)) / n
    if bw <= 0 then return end
    local filled = math.floor((frac or 0) * n + 0.5)
    if filled < 0 then filled = 0 elseif filled > n then filled = n end
    for i = 1, n do
        local on = (i <= filled)
        local c = on and onCol or offCol
        rect(x + (i - 1) * (bw + gap), y, bw, h, c[1], c[2], c[3], on and 0.9 or 0.26)
    end
end

--- 游戏是否暂停。Lua 侧只有只读的 Game():IsPaused()，没有 SetPaused，
--- 所以"打开册子就暂停时间"做不到；只能提示玩家按 ESC（原生暂停，时间会停）。
local function isGamePaused()
    local ok, v = pcall(function() return Game():IsPaused() end)
    return (ok and v) and true or false
end

local function sortedRuns()
    local store = deps.getStore()
    local list = {}
    if not store then return list end
    for i = 1, #store.index do list[#list + 1] = store.index[i] end
    table.sort(list, function(a, b) return (a.seq or 0) > (b.seq or 0) end)
    return list
end

local function analyzed(entry)
    if not entry then return nil end
    local key = entry.seq or 0
    if cache[key] ~= nil then return cache[key] or nil end
    local ok, res = pcall(function()
        local run = deps.fmt.decodeRun(deps.getStore(), entry)
        return deps.hl.analyze(run, deps.config)
    end)
    cache[key] = ok and res or false
    if not ok then return nil end
    return res
end

-- ---------------------------------------------------------------- 输入

local function trig(k) return Input.IsButtonTriggered(k, 0) end
local function held(k) return Input.IsButtonPressed(k, 0) end

local function navStep(down)
    local k = down and Keyboard.KEY_DOWN or Keyboard.KEY_UP
    if trig(k) then holdNext = holdNext + 1; return 1 end
    if held(k) then
        holdNext = holdNext + 1
        if holdNext > 14 and holdNext % 3 == 0 then return 1 end
    end
    return 0
end

local function update()
        local k5 = (deps and deps.hotkeyF5 and deps.hotkeyF5()) or Keyboard.KEY_F5
        if trig(k5) then
        isOpen = not isOpen
            if deps and deps.log then deps.log(string.format("[UI] F5 → isOpen=%s", tostring(isOpen))) end
        if isOpen then
            page, cache, holdNext, lastDiag = 1, {}, 0, ""
            local l0 = sortedRuns()
            if #l0 == 0 then
                isOpen = false
            elseif deps and deps.log then
                deps.log(string.format("[UI] 打开册子：%d 局  cjk=%s", #l0, (getCJK() and "yes" or "no")))
            end
        end
        return
    end
    if not isOpen then holdNext = 0; return end
    if not (held(Keyboard.KEY_UP) or held(Keyboard.KEY_DOWN)) then holdNext = 0 end

    local list = sortedRuns()
    local bk = analyzed(list[selRun])
    local total = bk and bk.pageCount or 1

    -- 第 1 页：↑↓ 换局；→/Enter 进书；← 也进书（避免"右边没反应"的错觉）
    if page == 1 then
        local d, u = navStep(true), navStep(false)
        if d > 0 and selRun < #list then selRun = selRun + 1 end
        if u > 0 and selRun > 1 then selRun = selRun - 1 end
        if (trig(Keyboard.KEY_ENTER) or trig(Keyboard.KEY_RIGHT)) and #list > 0 then page = 2 end
        if trig(Keyboard.KEY_ESCAPE) then isOpen = false end
    else
        if trig(Keyboard.KEY_RIGHT) and page < total then page = page + 1 end
        if trig(Keyboard.KEY_LEFT)  and page > 1 then page = page - 1 end
        if trig(Keyboard.KEY_ESCAPE) then page = 1 end
    end
end

-- ---------------------------------------------------------------- 版面

local PADW, PADH, FOOTH = 360, 200, 20
local PADX, PADY, FOOTY = 60, 24, 230

local function layout(s)
    local sw = Isaac.GetScreenWidth() / s
    local sh = Isaac.GetScreenHeight() / s
    PADX = (sw - PADW) / 2
    PADY = math.max(6, (sh - (PADH + FOOTH + 6)) / 2)
    FOOTY = PADY + PADH + 6
end

local function drawPaper(s)
    rect((PADX + 1.5) * s, (PADY + 2) * s, PADW * s, PADH * s, 0.05, 0.03, 0.02, 0.42)
    rect(PADX * s, PADY * s, PADW * s, PADH * s)
    local b = 0.32
    rect((PADX + 3) * s, (PADY + 3) * s, (PADW - 6) * s, 1.1 * s, 0.45, 0.36, 0.20, b)
    rect((PADX + 3) * s, (PADY + PADH - 4) * s, (PADW - 6) * s, 1.1 * s, 0.45, 0.36, 0.20, b)
    rect((PADX + 3) * s, (PADY + 3) * s, 1.1 * s, (PADH - 6) * s, 0.45, 0.36, 0.20, b)
    rect((PADX + PADW - 4) * s, (PADY + 3) * s, 1.1 * s, (PADH - 6) * s, 0.45, 0.36, 0.20, b)
    rect((PADX + 1.5) * s, (FOOTY + 1.5) * s, PADW * s, FOOTH * s, 0.05, 0.03, 0.02, 0.38)
    rect(PADX * s, FOOTY * s, PADW * s, FOOTH * s, 0.96, 0.93, 0.85, 1)
end

local function title(s, text, right)
    txt(text, (PADX + 12) * s, (PADY + 8) * s, s * 0.72, INK_RED, true)
    rect((PADX + 12) * s, (PADY + 21) * s, 170 * s, 1.4 * s, 0.50, 0.16, 0.12, 0.5)
    if right then
        txt(right, (PADX + PADW - 22) * s, (PADY + 9) * s, s * 0.62, INK_DIM, true)
    end
end

local function footer(s, text)
    local avail = (PADW - 20) * s          -- 纸内可用宽度（像素）
    local sc = s * 0.54
    local wpx = textW(text, sc)
    if wpx > avail and wpx > 0 then
        sc = sc * (avail / wpx)            -- 按比例缩到刚好放得下
    end
    txt(text, (PADX + 8) * s, (FOOTY + 4.5) * s, sc, INK_DIM)
end

--- 六维行（标签 + 数值 + 分段条 + 增量），返回下一行的 y（单位：480 空间）
--- 位置全部按字宽算，避免条压字
--- 画一行六维。区间规则集中在这里（唯一一处）：
---   幸运可能为负 → [本局最小值, 本局最大值]
---   其它维度     → [0, 本局最大值]
local function statRow(s, y, st, bk, x0, colWidth)
    local k = st.key
    local mx = bk.statMax[k] or 0
    local mn = (k == "lk") and (bk.statMin[k] or 0) or 0   -- 唯一一处区间规则
    local sc = s * 0.56
    local label = (getCJK() and st.label) or st.labelEn or st.label
    txt(label, x0 * s, y * s, sc, INK)
    local wLab = textW(label, sc) / s

    -- 数值 + 百分比都要（作者 2026-10-22）：有变化时显示 旧>新，让"增加后的数值"也看得见
    local valStr
    if st.inV and math.abs((st.outV or 0) - (st.inV or 0)) > 0.005 then
        valStr = string.format("%.2f>%.2f", st.inV, st.outV)
    else
        valStr = string.format("%.2f", st.outV)
    end
    local xVal = x0 + wLab + 5
    txt(valStr, xVal * s, y * s, sc, INK)
    local wVal = textW(valStr, sc) / s

    local xBar = xVal + wVal + 5
    local barW = math.max(30, colWidth - (xBar - x0) - 42)
    local span = (mx or 0) - (mn or 0)
    if span <= 0 then span = 1 end
    local fb = ((st.inV or 0) - (mn or 0)) / span
    local ft = ((st.outV or 0) - (mn or 0)) / span
    segBar2(xBar * s, (y + 2.2) * s, barW * s, 5.5 * s, fb, ft, 20)

    local dStr
    if st.inV and math.abs(st.inV) > 0.005 then
        dStr = string.format("%+.1f%%", st.delta / st.inV * 100)
    else
        dStr = "0%"          -- 进房值为 0 时比例无意义，统一显示 0%
    end
    txt(dStr, (xBar + barW + 5) * s, y * s, sc,
        st.delta > 0.005 and INK_UP or (st.delta < -0.005 and INK_DN or INK_DIM))
    return y + 11
end

-- ---------------------------------------------------------------- 各页

--- 终极 Boss 评级（作者 2026-10-22）：按击杀用时，30 秒一档
--- S+ <=30s, S <=60s, A <=90s, B <=120s, C <=150s, D <=180s, E 更慢
--- 没打终极 Boss 直接记 D
local function bossGrade(bk)
    local sum, n = 0, 0
    for i = 1, #bk.rooms do
        local r = bk.rooms[i]
        if (r.ub or 0) > 0 then
            sum = sum + (r.ms or 0)
            n = n + 1
        end
    end
    if n == 0 then return "D" end          -- 没打终极 Boss：直接 D
    local sec = (sum / n) / 1000           -- 多个终极 Boss 取平均
    if sec <= 30 then return "S+" end
    if sec <= 60 then return "S" end
    if sec <= 120 then return "A" end
    if sec <= 200 then return "B" end
    if sec <= 300 then return "C" end
    return "E"
end

--- 墙钟时间文本：2026/10/22 14:36。取不到（os.date 不可用或旧记录没 w0）就返回 nil
local function whenText(ws)
    if type(ws) ~= "string" then return nil end
    ws = ws:gsub("^%s+", ""):gsub("%s+$", "")
    if ws == "" then return nil end
    if ws:find("^1970") then return nil end
    return ws
end

local function drawOverview(s, bk, entry)
    title(s, (getCJK() and "总览") or "Overview", string.format("1/%d", bk.pageCount))
    local y = PADY + 27
    -- 评级放在 WIN 右边、楼层数前面（作者 2026-10-22）
    txt(string.format("%s   %s   %s   %dF   %d rooms",
        tostring(entry.id), RES_NAME[bk.result] or "?", bossGrade(bk), bk.maxFloor, #bk.rooms),
        (PADX + 12) * s, y * s, s * 0.64, INK_DIM)
    y = y + 11
    local whenStr = whenText(bk.ws)
    if whenStr then
        txt(whenStr, (PADX + 14) * s, y * s, s * 0.52, INK_DIM)
        y = y + 10
    end

    -- 本局四级道具（最多 8 个一行）
    local fin = bk.pages and bk.pages[1]
    local q4 = (fin and fin.q4) or {}
    if #q4 > 0 then
        local lab = ((getCJK() and "四级道具") or "Q4") .. " " .. #q4
        txt(lab, (PADX + 12) * s, y * s, s * 0.54, INK_DIM)
        local wL = textW(lab, s * 0.54) / s
        for k = 1, math.min(#q4, 8) do
            local sp = itemIcon(q4[k])
            if sp then
                sp.Scale = Vector(s * 0.62, s * 0.62)
                sp:Render(Vector((PADX + 16 + wL + (k - 1) * 26) * s, (y - 2) * s))
            end
        end
        if #q4 > 8 then
            txt(string.format("+%d", #q4 - 8),
                (PADX + 16 + wL + 8 * 26) * s, y * s, s * 0.52, INK_DIM)
        end
        y = y + 12
    end

    -- 终极 Boss 总结
    local bs = bk.bossSummary or {}
    if #bs > 0 then
        txt(((getCJK() and "终极Boss  ") or "BOSS  ") .. table.concat(bs, " · "),
            (PADX + 12) * s, y * s, s * 0.54, INK_RED)
        y = y + 12
    end

    local growth = (bk.base > 0) and ((bk.final - bk.base) / bk.base * 100) or 0
    txt(string.format("POWER  %.2f > %.2f    %+.2f   (%+.1f%%)",
        bk.base, bk.final, bk.final - bk.base, growth),
        (PADX + 12) * s, y * s, s * 0.68, INK_UP)

    local maxP = 0
    for i = 1, #bk.floors do if bk.floors[i].powerOut > maxP then maxP = bk.floors[i].powerOut end end
    if maxP <= 0 then maxP = 1 end

    local x0 = PADX + 12
    local colW = PADW - 40
    y = y + 14
    -- 楼层可能很多（作者反馈总览写不下）：改双栏，最多 24 层，超出显示 +N
    local nF = #bk.floors
    local MAXF = 24
    local shown = math.min(nF, MAXF)
    local perCol = math.min(12, math.ceil(shown / 2))
    local colGap = 16
    local colW2 = (colW - colGap) / 2
    for i = 1, shown do
        local f = bk.floors[i]
        local col = (i <= perCol) and 0 or 1
        local row = (i <= perCol) and (i - 1) or (i - perCol - 1)
        local xx = x0 + col * (colW2 + colGap)
        local yy = y + row * 12.5
        local sc = s * 0.54

        local lab = string.format("%dF", f.i)
        txt(lab, xx * s, yy * s, sc, INK)
        local wLab = textW(lab, sc) / s

        local valStr = string.format("%.2f", f.powerOut)
        local xVal = xx + wLab + 5
        txt(valStr, xVal * s, yy * s, sc, INK)
        local wVal = textW(valStr, sc) / s

        local gainStr
        if f.powerIn and math.abs(f.powerIn) > 0.005 then
            gainStr = string.format("%+.0f%%", f.gain / f.powerIn * 100)
        else
            gainStr = "0%"
        end
        local wGain = textW(gainStr, sc) / s
        local gainX = xx + colW2 - wGain - 1
        local xBar = xVal + wVal + 5
        local barW = math.max(16, gainX - 4 - xBar)
        segBar2(xBar * s, (yy + 2) * s, barW * s, 5 * s,
            f.powerIn / maxP, f.powerOut / maxP, 24)

        txt(gainStr, gainX * s, yy * s, sc, f.gain >= 0 and INK_UP or INK_DN)
    end
    y = y + perCol * 12.5
    if nF > shown then
        txt(string.format("+%d floors", nF - shown), (PADX + 12) * s, y * s, s * 0.5, INK_DIM)
        y = y + 10
    end
    footer(s, isGamePaused() and "TIME PAUSED    U/D RUN    ENTER OPEN    L/R PAGE    F5 CLOSE"
        or "U/D RUN    ENTER OPEN    L/R PAGE    F5 CLOSE   (ESC pauses time)")
end

--- 「终极Boss与终极道具」页：Boss 战斗时间 + 四级图标 + 零级图标
local function drawFinale(s, bk, idx)
    local p = bk.pages[idx]
    if not p then footer(s, "empty"); return end

    title(s, p.title or "终极Boss与终极道具", string.format("%d/%d", 1 + idx, bk.pageCount))

    local y = PADY + 27
    local boseCn = getCJK()

    -- 终极 Boss（最多 4 行）
    txt(boseCn and "终极BOSS" or "FINAL BOSS", (PADX + 12) * s, y * s, s * 0.58, INK_DIM)
    y = y + 12
    local n = math.min(#(p.bosses or {}), 4)
    for i = 1, n do
        local b = p.bosses[i]
        local nm = deps.hl.bossName(b.ub, not boseCn) or ("?" .. tostring(b.ub))
        txt(string.format("%-10s %8s   %s %d",
            nm, deps.hl.durationEn(b.ms),
            boseCn and "受伤" or "DMG", b.dmg or 0),
            (PADX + 14) * s, y * s, s * 0.6, INK)
        y = y + 12
    end
    if #(p.bosses or {}) > 4 then
        txt(string.format("+%d", #p.bosses - 4), (PADX + 14) * s, y * s, s * 0.55, INK_DIM)
        y = y + 12
    end
    if n == 0 then
        txt(boseCn and "（本局未击败终极Boss）" or "(no final boss)", (PADX + 14) * s, y * s, s * 0.55, INK_DIM)
        y = y + 12
    end

    -- 四级道具
    y = y + 6
    txt(string.format("%s %d", boseCn and "四级道具" or "QUALITY 4", #(p.q4 or {})),
        (PADX + 12) * s, y * s, s * 0.58, INK_DIM)
    y = y + 13
    local perRow = 8
    for k = 1, math.min(#(p.q4 or {}), 8) do
        local sp = itemIcon(p.q4[k])
        if sp then
            sp.Scale = Vector(s * 0.7, s * 0.7)
            sp:Render(Vector((PADX + 14 + (k - 1) * 30) * s, (y - 3) * s))
        end
    end
    if #(p.q4 or {}) > 8 then
        txt(string.format("+%d", #p.q4 - 8), (PADX + 14 + 8 * 30) * s, y * s, s * 0.55, INK_DIM)
    end
    y = y + 16

    -- 零级道具
    txt(string.format("%s %d", boseCn and "零级道具" or "QUALITY 0", #(p.q0 or {})),
        (PADX + 12) * s, y * s, s * 0.58, INK_DIM)
    y = y + 13
    for k = 1, math.min(#(p.q0 or {}), 8) do
        local sp = itemIcon(p.q0[k])
        if sp then
            sp.Scale = Vector(s * 0.7, s * 0.7)
            sp:Render(Vector((PADX + 14 + (k - 1) * 30) * s, (y - 3) * s))
        end
    end

    footer(s, "L/R PAGE    ESC BACK    F5 CLOSE")
end

local function drawHighlight(s, bk, idx)
    local p = bk.pages[idx]
    if not p then footer(s, "empty"); return end
    local r = p.room

    local kindName
    if getCJK() then
        kindName = (p.kind == "power" and "战力提升") or (p.kind == "q4" and "四级道具") or "零级道具"
    else
        kindName = (p.kind == "power" and "POWER UP") or (p.kind == "q4" and "QUALITY 4") or "QUALITY 0"
    end
    local label = string.format("%s  #%d", kindName, p.rank)
    title(s, label, string.format("%d/%d", 1 + idx, bk.pageCount))

    local y = PADY + 26
    txt(string.format("Floor %d   room %.0f   %s%s", r.floor, r.idx,
        (getCJK() and deps.hl.roomName(r.type)) or deps.hl.roomNameEn(r.type),
        r.first and "" or "   (revisit)"),
        (PADX + 12) * s, y * s, s * 0.6, INK_DIM)
    y = y + 12

    txt(string.format("%.2f > %.2f     %+.2f   (%+.1f%%)", r.p, r.po, r.delta, r.pct),
        (PADX + 12) * s, y * s, s * 0.66, r.delta >= 0 and INK_UP or INK_DN)
    y = y + 12

    txt(string.format("%s   damage %d   enemies %d",
        deps.hl.durationEn(r.ms), r.dmg, r.foes), (PADX + 12) * s, y * s, s * 0.58, INK_DIM)
    y = y + 15

    for i = 1, #r.stats do
        local k = r.stats[i].key
y = statRow(s, y, r.stats[i], bk, PADX + 12, PADW - 40)
    end

    if #r.it > 0 then
        y = y + 4
        txt("ITEMS", (PADX + 12) * s, y * s, s * 0.54, INK_DIM)
        local wLab = textW("ITEMS", s * 0.54) / s
        local xIcon = PADX + 12 + wLab + 8
        for k = 1, math.min(#r.it, 10) do
            local sp = itemIcon(r.it[k])
            if sp then
                sp.Scale = Vector(s * 0.7, s * 0.7)
                sp:Render(Vector((xIcon + (k - 1) * 30) * s, (y - 3) * s))
            else
                txt(tostring(r.it[k]), (xIcon + (k - 1) * 30) * s, y * s, s * 0.5, INK_DIM)
            end
        end
    end
    footer(s, isGamePaused() and "TIME PAUSED    L/R PAGE    ESC BACK    F5 CLOSE"
        or "L/R PAGE    ESC BACK    F5 CLOSE   (ESC pauses time)")
end

--- 「战力跃迁」页（作者 2026-10-22）
--- 只列「拿到道具」造成的战力跳变：图标 + 提升百分比，按时间顺序，2 排 × 12
local function drawJumps(s, bk, idx)
    local p = bk.pages[idx]
    if not p then footer(s, "empty"); return end
    local evs = p.events or {}

    title(s, (getCJK() and "战力跃迁") or "POWER JUMPS",
        string.format("%d/%d", 1 + idx, bk.pageCount))

    local y = PADY + 27
    txt(string.format("%s  %d/%d", (getCJK() and "只算拿到道具造成的跳变" or "item-driven only"),
        p.shown or 0, p.total or 0), (PADX + 12) * s, y * s, s * 0.52, INK_DIM)
    y = y + 16

    local x0 = PADX + 14
    local PERROW = 12
    local CELLW = 27
    local shown = math.min(#evs, p.shown or 24)
    for k = 1, shown do
        local ev = evs[k]
        local row = math.floor((k - 1) / PERROW)
        local col = (k - 1) % PERROW
        local cx = x0 + col * CELLW
        local cy = y + row * 42
        local sp = itemIcon(ev.id)
        if sp then
            sp.Scale = Vector(s * 0.62, s * 0.62)
            sp:Render(Vector(cx * s, cy * s))
        else
            txt(tostring(ev.id), cx * s, (cy + 4) * s, s * 0.42, INK_DIM)
        end
        -- 百分比（负值红色）与层/房号
        local txtPct = string.format("+%.0f%%", (ev.pct or 0) * 100)
        txt(txtPct, cx * s, (cy + 18) * s, s * 0.40, (ev.delta or 0) >= 0 and INK_UP or INK_DN)
        txt(string.format("F%d", ev.floor or 0), cx * s, (cy + 26) * s, s * 0.36, INK_DIM)
    end

    if (p.rest or 0) > 0 then
        txt(string.format("+%d", p.rest), (PADX + PADW - 40) * s, (PADY + PADH - 24) * s, s * 0.54, INK_DIM)
    end
    footer(s, isGamePaused() and "TIME PAUSED    L/R PAGE    ESC BACK    F5 CLOSE"
        or "L/R PAGE    ESC BACK    F5 CLOSE   (ESC pauses time)")
end

local function drawFloor(s, bk, idx)
    local f = bk.floors[idx]
    if not f then footer(s, "empty"); return end

    title(s, string.format((getCJK() and "第 %d 层") or "Floor %d", f.i),
        string.format("%d/%d", 1 + #bk.pages + idx, bk.pageCount))

    local y = PADY + 26
    txt(string.format("%s   damage %d   %.2f > %.2f  (%+.2f)",
        deps.hl.durationEn(f.ms), f.dmg, f.powerIn, f.powerOut, f.gain),
        (PADX + 12) * s, y * s, s * 0.62, INK)

    local curses = getCJK() and deps.hl.curseNames(f.curse) or deps.hl.curseNamesEn(f.curse)
    if #curses > 0 then
        y = y + 12
        txt((getCJK() and "诅咒  " or "CURSE  ") .. table.concat(curses, " "),
            (PADX + 12) * s, y * s, s * 0.56, INK_RED)
    end

    -- 六维
    y = y + 15
    if f.stats then
        for i = 1, #f.stats do
            local k = f.stats[i].key
y = statRow(s, y, f.stats[i], bk, PADX + 12, PADW - 40)
        end
    end

    -- 道具按品质分行（作者 2026-10-22）：Q0~Q5 每个等级一行，每行 8 个，多的用 +N
    y = y + 4
    local PERROW = 8
    local groups, total = {}, 0
    for k = 1, #f.items do
        local q = (f.itemsQ and f.itemsQ[k]) or 0
        q = math.floor(tonumber(q) or 0)
        if q < 0 then q = 0 end
        if q > 5 then q = 5 end
        groups[q] = groups[q] or {}
        groups[q][#groups[q] + 1] = f.items[k]
        total = total + 1
    end

    txt(string.format("ITEMS  %d", total), (PADX + 12) * s, y * s, s * 0.54, INK_DIM)
    y = y + 12

    for q = 5, 0, -1 do
        local g = groups[q]
        if g and #g > 0 then
            txt(string.format("Q%d", q), (PADX + 12) * s, (y + 3) * s, s * 0.5, INK_DIM)
            local xIcon = PADX + 12 + 22
            local n = math.min(#g, PERROW)
            for k = 1, n do
                local sp = itemIcon(g[k])
                if sp then
                    sp.Scale = Vector(s * 0.62, s * 0.62)
                    sp:Render(Vector((xIcon + (k - 1) * 24) * s, y * s))
                else
                    txt(tostring(g[k]), (xIcon + (k - 1) * 24) * s, (y + 3) * s, s * 0.46, INK_DIM)
                end
            end
            if #g > n then
                txt(string.format("+%d", #g - n),
                    (xIcon + n * 24) * s, (y + 3) * s, s * 0.5, INK_DIM)
            end
            y = y + 15
        end
    end
    -- 本层战力跃迁（作者 2026-10-22）：最多 8 条，按时间顺序，超出 +N
    local fJumps = {}
    if bk.jumps then
        for i = 1, #bk.jumps do
            if bk.jumps[i].floor == f.i then fJumps[#fJumps + 1] = bk.jumps[i] end
        end
    end
    if #fJumps > 0 then
        y = y + 5
        txt(string.format("JUMPS  %d", #fJumps), (PADX + 12) * s, y * s, s * 0.54, INK_DIM)
        y = y + 11
        for i = 1, math.min(#fJumps, 8) do
            local e = fJumps[i]
            local sp = itemIcon(e.id)
            if sp then
                sp.Scale = Vector(s * 0.5, s * 0.5)
                sp:Render(Vector((PADX + 12) * s, y * s))
            end
            txt(string.format("#%d  %.2f>%.2f  %+.1f%%",
                e.room or 0, e.pIn or 0, e.pOut or 0, (e.pct or 0) * 100),
                (PADX + 28) * s, (y + 1) * s, s * 0.5,
                (e.delta or 0) >= 0 and INK_UP or INK_DN)
            y = y + 11
        end
        if #fJumps > 8 then
            txt(string.format("+%d", #fJumps - 8), (PADX + 12) * s, y * s, s * 0.5, INK_DIM)
        end
    end

    footer(s, isGamePaused() and "TIME PAUSED    L/R PAGE    ESC BACK    F5 CLOSE"
        or "L/R PAGE    ESC BACK    F5 CLOSE   (ESC pauses time)")
end

-- ---------------------------------------------------------------- 主渲染

local lastDiag = ""
local function diag(bk, entry)
    local key = tostring(selRun) .. ":" .. tostring(page)
    if key == lastDiag then return end
    lastDiag = key
    if not (deps and deps.log) then return end
    local nIcon, nFail = 0, 0
    for _, v in pairs(iconCache) do
        if v == false then nFail = nFail + 1 else nIcon = nIcon + 1 end
    end
    local sw, sh, sc = scr()
    deps.log(string.format("[UI] page=%d/%d pages=%d floors=%d cjk=%s icons=%d fail=%d screen=%dx%d scale=%.2f",
        page, bk.pageCount, #bk.pages, #bk.floors,
        (getCJK() and "yes" or "no"), nIcon, nFail, sw, sh, sc))
end

local function render()
    if not isOpen then return end
    local _, _, s = scr()
    local list = sortedRuns()
    if #list == 0 then isOpen = false; return end
    if selRun > #list then selRun = #list end

    layout(s)
    drawPaper(s)

    local bk = analyzed(list[selRun])
    if not bk then isOpen = false; return end
    if page > bk.pageCount then page = bk.pageCount end
    diag(bk, list[selRun])

    if page == 1 then
        drawOverview(s, bk, list[selRun])
    elseif page <= 1 + #bk.pages then
        local pg = bk.pages[page - 1]
        if pg and pg.kind == "finale" then
            drawFinale(s, bk, page - 1)
            elseif pg and pg.kind == "jumps" then
                drawJumps(s, bk, page - 1)
        else
            drawHighlight(s, bk, page - 1)
        end
    else
        drawFloor(s, bk, page - 1 - #bk.pages)
    end
end

-- ── 局内 HUD：六维下面一行战力（作者 2026-10-22）────────────────────────
-- 数据由 main 每帧写入（power 当前战力、delta 最近一次增量、untilFrame 过期帧）
book.hud = { power = 0, delta = 0, untilFrame = 0 }

function book.renderHud()
    local cfg = (deps and deps.config) or {}
    if cfg.hudPower == false then return end
    local hud = book.hud
    if not hud or not hud.power or hud.power <= 0 then return end
    loadFonts()
    if not hudFont then return end

    local _, _, s = scr()
    local plus = rawget(_G, "REPENTANCE_PLUS") or rawget(_G, "REPENTOGON_PLUS")
    local hx = 16
    local hy = (plus and 170 or 168) + (cfg.hudPowerOffsetY or 0)

    -- 描边字：白色数值 + 3 秒内的增量（绿涨红跌），和星象房那条并排同款
    hudFont:DrawString(string.format("%.2f", hud.power), hx + 14, hy + 1,
        KColor(1, 1, 1, 0.95), 0, false)
    local fc = 0
    pcall(function() fc = Isaac.GetFrameCount() end)
    if hud.delta and math.abs(hud.delta) > 0.005 and fc < (hud.untilFrame or 0) then
        local d = hud.delta
        hudFont:DrawString(string.format("%+.2f", d), hx + 42, hy + 1,
            d >= 0 and KColor(0.35, 1, 0.35, 0.95) or KColor(1, 0.35, 0.35, 0.95), 0, false)
    end
    -- 小方块当图标
    -- 图标与文字必须用同一个坐标系（DrawString 用的是 480x270 的 HUD 空间）
    hudFont:DrawString("[]", hx, hy + 1, KColor(0.9, 0.3, 0.25, 0.95), 0, false)
end

book.update = update
book.render = render
book.isOpen = function() return isOpen end

return book
