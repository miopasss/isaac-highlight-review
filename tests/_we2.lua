local ROOT = "D:/00000/aiStudy/issacmod/"
local DATA = "D:/LenovoSoftstore/Install/Steam/steamapps/common/The Binding of Isaac Rebirth/data/highlight-review/"
local schema = loadfile(ROOT .. "mod-review/core/schema.lua")()
local fmt    = loadfile(ROOT .. "mod-review/core/fmt.lua")()
fmt.setSchema(schema)
local f = io.open(DATA .. "save3.dat", "rb"); local blob = f:read("*a"); f:close()
local store = fmt.splitBlob(blob)
local out = { string.format("save3: %d 字节 / %d 局", #blob, #store.index) }
out[#out+1] = string.format("%-4s %-12s %-4s %-6s %-19s %-19s", "seq", "id", "res", "rooms", "开(ws)", "终(we)")
for i = 1, #store.index do
    local e = store.index[i]
    local run = fmt.decodeRun(store, e)
    out[#out+1] = string.format("%-4s %-12s %-4s %-6d %-19s %-19s",
        tostring(e.seq), tostring(run.id), tostring(run.res), #(run.rooms or {}),
        tostring(run.ws), tostring(run.we))
end
return table.concat(out, "\n")