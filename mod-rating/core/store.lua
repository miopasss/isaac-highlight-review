-- ============================================================================
-- store.lua —— 评级 mod 自己的存档容器
--
-- 格式（纯文本，一行一条，局外可用 PowerShell 解析）：
--   IWE1                     ← 魔数
--   Q={"v":1,"e":{...}}      ← 道具评级/权重
--   C={"f6":295}             ← 热键等设置
--
-- 为什么不复用回顾那边的 fmt：两个 mod 是独立发布的，
-- 任何一方改格式都不该牵连另一方。这里故意保持极简。
-- ============================================================================
local S = {}

S.MAGIC = "IWE1"

function S.new()
    return { lines = {} }
end

--- 把存档字符串拆成 { lines = {...} }（第一行是魔数，丢弃）
function S.split(blob)
    local st = { lines = {} }
    if not blob or blob == "" then return st end
    local first = true
    for line in blob:gmatch("[^\n]+") do
        line = line:gsub("\r$", "")
        if first then
            first = false
            if line ~= S.MAGIC then
                -- 魔数不符：仍然尽量读内容，不丢弃数据
                if #line > 0 then st.lines[#st.lines + 1] = line end
            end
        elseif #line > 0 then
            st.lines[#st.lines + 1] = line
        end
    end
    return st
end

--- 组回存档字符串
function S.build(st)
    local lines = (st and st.lines) or {}
    if #lines == 0 then return S.MAGIC end
    return S.MAGIC .. "\n" .. table.concat(lines, "\n")
end

return S
