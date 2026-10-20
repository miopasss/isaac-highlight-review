-- 临时探针：核对 Boss 房的 stage / 房型 / boss 字段，验证 Hush(63) 与百变怪(70)
local ROOT = (os and os.getenv and os.getenv("HLR_ROOT")) or "D:/00000/aiStudy/issacmod/"
if ROOT:sub(-1) ~= "/" then ROOT = ROOT .. "/" end
local DATA = (os and os.getenv and os.getenv("HLR_DATA")) or "data/highlight-review"
if DATA:sub(-1) ~= "/" then DATA = DATA .. "/" end

local function loadmod(p) return loadfile(ROOT .. p)() end
local schema = loadmod("mod/core/schema.lua")
local fmt    = loadmod("mod/core/fmt.lua")
fmt.setSchema(schema)

local STAGE = {
  [0]="NULL",[1]="Basement1",[2]="Basement2",[3]="Caves1",[4]="Caves2",
  [5]="Depths1",[6]="Depths2",[7]="Womb1",[8]="Womb2",[9]="BlueWomb(???)",
  [10]="Sheol/Cathedral",[11]="DarkRoom/Chest",[12]="Void",[13]="Home",
}

local out = {}
local function w(s) out[#out+1] = s end

local function readAll(p)
  local f = io.open(p, "rb"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end

local blob = readAll(ROOT .. "_archive/all.dat")
if not blob then return "没有归档" end
local store = fmt.splitBlob(blob)

for ri = 1, #store.index do
  local run = fmt.decodeRun(store, store.index[ri])
  w("")
  w(string.format("── 局 %s  res=%d  层数=%d", tostring(run.id), tonumber(run.res) or -1, #(run.floors or {})))
  -- 楼层 stage
  for _, f in ipairs(run.floors or {}) do
    w(string.format("   层%-2d stage=%-2d %-18s curse=%-3d 时长=%.1f分",
      tonumber(f.i) or 0, tonumber(f.stage) or -1,
      STAGE[tonumber(f.stage) or -1] or "?",
      tonumber(f.curse) or 0, (tonumber(f.ms) or 0) / 60000))
  end
  -- 所有 boss 房
  w("   --- Boss 房（型=5 或 型=17）---")
  for _, r in ipairs(run.rooms or {}) do
    local t = tonumber(r.t) or 0
    if t == 5 or t == 17 then
      w(string.format("   F%-2d 第%-3d间 型%-2d 形%-2d  boss=%-3d  停留%6.1fs 受伤%-3d 战力%7.2f→%7.2f  ub=%d",
        tonumber(r.f) or 0, tonumber(r.i) or 0, t, tonumber(r.s) or 0,
        tonumber(r.boss) or 0, (tonumber(r.ms) or 0)/1000,
        tonumber(r.dmg) or 0, tonumber(r.p) or 0, tonumber(r.po) or 0,
        tonumber(r.ub) or 0))
    end
  end
end

local body = table.concat(out, "\n")
local path = ROOT .. "_logs/bossprobe.txt"
local f = io.open(path, "wb"); f:write(body); f:close()
return body
