local ROOT = (os and os.getenv and os.getenv("HLR_ROOT")) or "D:/00000/aiStudy/issacmod/"
if ROOT:sub(-1) ~= "/" then ROOT = ROOT .. "/" end
local schema = loadfile(ROOT.."mod-review/core/schema.lua")()
local fmt = loadfile(ROOT.."mod-review/core/fmt.lua")()
fmt.setSchema(schema)
local r = {
  r=1,f=1,i=3,t=4,s=1,d=15,st=30,v=12,list=7,
  hp=6,hs=2,hb=0,hpo=4,hso=1,hbo=1, mxhp=6,mxhpo=6,
  p=12.89,po=13.99,ms=7800,dmg=0,clr=true,
  it={34,385}, tri={41}, tro={41},
  foes=6, c=12, co=18, bmb=2, bmbo=1, key=1, keyo=1, boss=0, first=false,
  dv=4.20, mu=1, fm="tears", pd="",
}
local line = fmt.encodeRecord("M", r)
local f = io.open(ROOT.."_logs/size-probe.txt","wb")
f:write(string.format("单房 %d 字节\n", #line))
f:write(string.format("一局 40 房 ≈ %d 字节\n", #line*40 + 60))
f:write(string.format("500 局 ≈ %.2f MB\n", (#line*40+60)*500/1024/1024))
f:write("\n样例行：\n"..line.."\n")
f:close()
return "单房 "..#line.." 字节"