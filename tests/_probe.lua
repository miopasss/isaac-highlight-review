local ROOT = (os and os.getenv and os.getenv("HLR_ROOT")) or "D:/00000/aiStudy/issacmod/"
if ROOT:sub(-1) ~= "/" then ROOT = ROOT .. "/" end
local schema = loadfile(ROOT.."mod/core/schema.lua")()
local fmt = loadfile(ROOT.."mod/core/fmt.lua")()
fmt.setSchema(schema)
local ok, msg = fmt.selftest()
local out = "selftest: " .. tostring(ok) .. " / " .. tostring(msg) .. "\n"
local _, rec3 = fmt.decodeRecord("M|t=5")
out = out .. string.format("hp=%s p=%s it=%s clr=%s\n", tostring(rec3.hp), tostring(rec3.p),
    tostring(type(rec3.it)), tostring(rec3.clr))
local f = io.open(ROOT.."_logs/probe.txt","wb"); f:write(out); f:close()
return out