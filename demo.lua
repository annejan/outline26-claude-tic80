-- title:  multi-scene demo
-- author: annejan
-- desc:   plasma / starfield / tunnel / rotozoomer / fire + scroller, fade transitions, sfx
-- script: lua

-- ===== globals & timing =====
t=0
scene=0          -- 0 = title, 1 = awakening, 2..10 = effects, 11 = outro
scene_t=0
SCENE_LEN=420
INTRO_LEN=300
AWAKEN_LEN=420
OUTRO_LEN=1500   -- placeholder; recomputed once credits is defined
OUTRO_SCROLL=0.22
OUTRO_LINE_H=9
FADE=40
N_SCENES=11
beat=0           -- decays 1→0 between kick hits, drives global pulse

-- ===== memory pokes: palette, waveforms, sfx =====
-- hide the system cursor (0x3FFB = MOUSE_CURSOR sprite id; 0 = none)
poke(0x3FFB,0)

-- save original palette so we can attenuate it for fades
orig_pal={}
for i=0,47 do orig_pal[i]=peek(0x03FC0+i) end

-- waveforms (16 waves × 16 bytes at 0x0FFE4). each byte holds 2 4-bit samples.
-- wave 0: triangle (0→F→0 over 32 samples)
for i=0,15 do
 local a=2*i
 local b=2*i+1
 local va=a<16 and a or 31-a
 local vb=b<16 and b or 31-b
 poke(0x0FFE4+i,va*16+vb)
end
-- wave 1: square
for i=0,7 do poke(0x0FFE4+16+i,0xFF) end
for i=8,15 do poke(0x0FFE4+16+i,0x00) end
-- wave 2: sawtooth (ramp 0→F over 32 samples)
for i=0,15 do poke(0x0FFE4+32+i,i*16+i) end
-- wave 3: noise (for percussion)
for i=0,15 do poke(0x0FFE4+48+i,math.random(0,255)) end

-- build SFX entry: 66 bytes [15 wave-nibbles, 15 vol-nibbles, 15 chord, 15 pitch, 6 trailing]
function mkSFX(slot,wave,vols,trail)
 local base=0x100E4+slot*66
 for i=0,65 do poke(base+i,0) end
 local wbyte=wave*16+wave
 for i=0,14 do poke(base+i,wbyte) end
 for i=0,14 do
  local v1=vols[i*2+1]or 0
  local v2=vols[i*2+2]or 0
  poke(base+15+i,v1*16+v2)
 end
 for i=0,5 do poke(base+60+i,trail and trail[i+1]or 0) end
end

-- SFX 0: bass (triangle, slow decay)
do local v={} for i=1,30 do v[i]=math.max(0,14-(i-1)//3) end mkSFX(0,0,v) end
-- SFX 1: lead (square, fast attack/decay)
do local v={15,14,13,11,9,7,5,3,2,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0} mkSFX(1,1,v) end
-- SFX 2: hihat (noise, very short)
do local v={10,7,4,2,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0} mkSFX(2,3,v) end
-- SFX 3: kick (saw, deep thump)
do local v={15,15,14,12,10,8,6,4,2,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0} mkSFX(3,2,v) end
-- SFX 4: pad/chord (saw, gentle attack + long sustain)
do local v={3,5,7,8,9,9,9,9,9,9,9,9,8,8,8,8,7,7,7,6,6,6,5,5,4,3,2,1,0,0} mkSFX(4,2,v) end
-- SFX 5: snare (noise, longer than hihat)
do local v={14,12,10,8,6,4,3,2,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0} mkSFX(5,3,v) end

-- ===== runtime state: textures, particles, terrain =====
-- pre-built rotozoomer texture (16×16, indexed)
tex={}
for y=0,15 do
 tex[y]={}
 for x=0,15 do
  tex[y][x]=((x~y)%6+(x+y)//4)%14+2
 end
end

-- starfield state
stars={}
for i=1,220 do
 stars[i]={
  x=(math.random()-0.5)*220,
  y=(math.random()-0.5)*220,
  z=math.random()*100+1
 }
end

-- fire buffer
FW,FH=60,36
fire={}
for i=0,FW*FH-1 do fire[i]=0 end

-- metaballs
mballs={}
for i=1,4 do
 mballs[i]={
  ax=math.random()*60+40,
  ay=math.random()*30+20,
  px=math.random()*6,
  py=math.random()*6,
  sx=math.random()*0.04+0.02,
  sy=math.random()*0.04+0.02
 }
end

-- cube vertices, edges, and faces
cube_v={
 {-1,-1,-1},{1,-1,-1},{1,1,-1},{-1,1,-1},
 {-1,-1, 1},{1,-1, 1},{1,1, 1},{-1,1, 1}
}
cube_e={
 {1,2},{2,3},{3,4},{4,1},
 {5,6},{6,7},{7,8},{8,5},
 {1,5},{2,6},{3,7},{4,8}
}
cube_f={
 {1,2,3,4, 2},  -- back
 {5,6,7,8, 4},  -- front
 {1,2,6,5, 9},  -- bottom
 {4,3,7,8,10},  -- top
 {1,5,8,4,14},  -- left
 {2,6,7,3,12}   -- right
}

-- voxel heightmap (128x128) — dramatic: ridges, canyons, snow peaks
HM=128
hmap={}
for x=0,HM-1 do hmap[x]={}
 for z=0,HM-1 do
  local h=math.sin(x/16)*6+math.cos(z/14)*6
    +math.abs(math.sin(x/9+z/11))*5      -- ridges
    +math.sin((x+z)/8)*3.5
    +math.cos((x-z)/10)*3
    +math.sin(x/5)*1.5+math.cos(z/6)*1.5
  hmap[x][z]=math.floor(h+10)
 end
end

-- ===== effect scenes (sorted by story order in dispatch below) =====
function plasma()
 cls(0)
 local pulse=1+beat*0.4
 for cy=0,33 do
  for cx=0,59 do
   local dx=cx-30
   local dy=cy-17
   local r=math.sqrt(dx*dx+dy*dy)
   local v=math.sin(cx/8+t/30)+math.sin(cy/6-t/40)
        +math.sin((cx+cy)/10+t/50)+math.sin(r/4-t/35)*pulse
   local c=math.floor((v+4)*2)%16
   rect(cx*4,cy*4,4,4,c)
  end
 end
end

function starfield()
 cls(0)
 for _,s in ipairs(stars) do
  s.z=s.z-1.5
  if s.z<1 then
   s.x=(math.random()-0.5)*200
   s.y=(math.random()-0.5)*200
   s.z=100
  end
  local sx=120+s.x/s.z*80
  local sy=68+s.y/s.z*80
  local b=math.floor((100-s.z)/25)
  local cols={13,14,12,15}
  if sx>=0 and sx<240 and sy>=0 and sy<136 then
   pix(sx,sy,cols[math.min(b+1,4)])
  end
 end
end

function tunnel()
 cls(0)
 for cy=0,16 do
  for cx=0,29 do
   local dx=cx-14.5
   local dy=cy-8
   local d=math.sqrt(dx*dx+dy*dy)
   local a=math.atan(dy,dx)
   local v=math.floor(24/(d+0.1)+a*3+t/4)
   local c=(v%6)+9
   rect(cx*8,cy*8,8,8,c)
  end
 end
end

function rotozoomer()
 cls(0)
 local cs=math.cos(t/40)
 local sn=math.sin(t/40)
 local zoom=0.6+math.sin(t/60)*0.4
 for cy=0,33 do
  for cx=0,59 do
   local x=(cx-30)*zoom
   local y=(cy-17)*zoom
   local tx=math.floor(x*cs-y*sn)%16
   local ty=math.floor(x*sn+y*cs)%16
   rect(cx*4,cy*4,4,4,tex[ty][tx])
  end
 end
end

function fcol(h)
 if h<=0 then return 0
 elseif h<5 then return 1
 elseif h<10 then return 2
 elseif h<15 then return 6
 elseif h<20 then return 4
 elseif h<25 then return 14
 elseif h<32 then return 12
 else return 15 end
end

function fire_effect()
 cls(0)
 for x=0,FW-1 do
  fire[(FH-1)*FW+x]=math.random(30,36)
 end
 for y=0,FH-2 do
  for x=0,FW-1 do
   local below=fire[(y+1)*FW+x] or 0
   local decay=math.random(0,2)
   fire[y*FW+x]=math.max(0,below-decay)
  end
 end
 for y=0,FH-1 do
  for x=0,FW-1 do
   local h=fire[y*FW+x]
   if h>0 then
    rect(x*4,y*4-8,4,4,fcol(h))
   end
  end
 end
end

function metaballs_fx()
 cls(0)
 local pos={}
 for i,b in ipairs(mballs) do
  pos[i]={
   x=120+math.sin(t*b.sx+b.px)*b.ax,
   y=68+math.cos(t*b.sy+b.py)*b.ay
  }
 end
 for cy=0,33 do
  for cx=0,59 do
   local px=cx*4+2
   local py=cy*4+2
   local f=0
   for _,p in ipairs(pos) do
    local dx=px-p.x
    local dy=py-p.y
    f=f+900/(dx*dx+dy*dy+1)
   end
   local c
   if f<1 then c=0
   elseif f<2 then c=2
   elseif f<3 then c=8
   elseif f<5 then c=14
   else c=15 end
   if c>0 then rect(cx*4,cy*4,4,4,c) end
  end
 end
end

function cube3d()
 cls(0)
 local a,b=t/50,t/35
 local sa,ca=math.sin(a),math.cos(a)
 local sb,cb=math.sin(b),math.cos(b)
 local scale=1.4+beat*0.2
 local pts={}
 local zs={}
 for i,v in ipairs(cube_v) do
  local x,y,z=v[1]*scale,v[2]*scale,v[3]*scale
  local x1=x*ca-z*sa
  local z1=x*sa+z*ca
  local y1=y*cb-z1*sb
  local z2=y*sb+z1*cb
  local sc=80/(z2+5)
  pts[i]={120+x1*sc,68+y1*sc,z2}
  zs[i]=z2
 end
 -- depth-sort faces by avg z, paint farthest first
 local order={}
 for i=1,6 do order[i]=i end
 table.sort(order,function(a,b)
  local fa=cube_f[a]
  local fb=cube_f[b]
  local za=(zs[fa[1]]+zs[fa[2]]+zs[fa[3]]+zs[fa[4]])/4
  local zb=(zs[fb[1]]+zs[fb[2]]+zs[fb[3]]+zs[fb[4]])/4
  return za>zb
 end)
 for _,fi in ipairs(order) do
  local f=cube_f[fi]
  local p1,p2,p3,p4=pts[f[1]],pts[f[2]],pts[f[3]],pts[f[4]]
  tri(p1[1],p1[2],p2[1],p2[2],p3[1],p3[2],f[5])
  tri(p1[1],p1[2],p3[1],p3[2],p4[1],p4[2],f[5])
 end
 -- outline edges on top
 for _,e in ipairs(cube_e) do
  local p1,p2=pts[e[1]],pts[e[2]]
  line(p1[1],p1[2],p2[1],p2[2],15)
 end
end

function copper()
 cls(0)
 for y=0,135 do
  local v=math.sin(y/12+t/25)+math.sin(y/9-t/35)
  local c=math.floor((v+2)*4)%16
  line(0,y,239,y,c)
 end
 -- three bars, different speeds and palettes
 local bars={
  {y=68+math.sin(t/20)*45,        cols={2,4,14,12,15,12,14,4,2}},
  {y=68+math.sin(t/27+1.7)*50,    cols={1,9,10,11,15,11,10,9,1}},
  {y=68+math.sin(t/15-0.9)*40,    cols={5,6,7,15,15,15,7,6,5}}
 }
 for _,bar in ipairs(bars) do
  for i,c in ipairs(bar.cols) do
   line(0,bar.y+i-5,239,bar.y+i-5,c)
  end
 end
end

-- distance fog: blends color index toward sky horizon (14)
function fogcol(base,fog)
 if fog<0.3 then return base end
 if fog<0.55 then
  local mid={[1]=4,[3]=4,[4]=9,[6]=9,[11]=10,[12]=10,[15]=10}
  return mid[base] or base
 end
 if fog<0.8 then return 10 end
 return 14
end

function voxel()
 -- sky gradient
 for y=0,71 do
  local c
  if y<10 then c=2
  elseif y<25 then c=1
  elseif y<40 then c=9
  elseif y<55 then c=10
  else c=14 end
  line(0,y,239,y,c)
 end
 -- horizon fallback
 rect(0,72,240,64,9)

 -- camera flies a banking S-curve through the landscape
 local cam_x=math.sin(t/280)*55
 local cam_z=t*1.0
 local cam_h=22+math.sin(t/130)*5+math.cos(t/200)*2.5   -- multi-freq altitude
 local yaw=math.cos(t/280)*0.45                          -- bank into the turn
 local cs,sn=math.cos(yaw),math.sin(yaw)

 -- sun (track yaw so it stays at horizon)
 local sun_x=120-yaw*120
 circ(sun_x,46,9,15)
 circb(sun_x,46,11,14)

 for col=0,119 do
  local maxy=125
  for dist=2,65 do
   local rx=(col-60)*dist*0.035
   local rz=dist
   local wx=cam_x+rx*cs-rz*sn
   local wz=cam_z+rx*sn+rz*cs
   local hx=math.floor(wx)%HM
   local hz=math.floor(wz)%HM
   if hx<0 then hx=hx+HM end
   if hz<0 then hz=hz+HM end
   local h=hmap[hx][hz]
   local sy=72-(h-cam_h)*19/dist
   if sy<maxy then
    local drawy=sy<0 and 0 or sy
    local base
    if h<3 then base=1                 -- deep valley
    elseif h<7 then base=4             -- dirt
    elseif h<11 then base=3            -- dark forest
    elseif h<15 then base=11           -- light green slope
    elseif h<19 then base=12           -- alpine green
    elseif h<23 then base=6            -- gray rock
    elseif h<27 then base=7            -- light rock
    else base=15 end                   -- snow cap
    rect(col*2,drawy,2,maxy-drawy,fogcol(base,(dist-2)/60))
    maxy=sy
   end
  end
 end
end

scroll_text="    CLAUDE LEARNS TIC-80  ***  AWAKENING / PLASMA / STARFIELD / TUNNEL / METABALLS / ROTOZOOM / CUBE / COPPER / VOXEL / FIRE  ***  A LITTLE STORY IN 16 COLORS  ***  THANKS FOR WATCHING       "

-- ===== story content + on-screen text =====
function scroller()
 local sx=240-(t*2)%(240+#scroll_text*8)
 for i=1,#scroll_text do
  local ch=scroll_text:sub(i,i)
  local x=sx+(i-1)*8
  local y=118+math.sin((t+i*10)/12)*6
  if x>-8 and x<240 then
   print(ch,x,y,12,false,1,false)
  end
 end
end

-- story-ordered scenes (index = scene number)
names={[1]="awakening",[2]="plasma",[3]="starfield",[4]="tunnel",
       [5]="metaballs",[6]="rotozoom",[7]="cube",[8]="copper",
       [9]="voxel",[10]="fire",[11]="fin"}

-- captions are Claude's POV thoughts during each scene
captions={
 [1]="...wait, I can draw?",
 [2]="what if I layer some sines together?",
 [3]="stars - just perspective on points",
 [4]="deeper into the math",
 [5]="distance fields - organic shapes",
 [6]="textures can spin and zoom",
 [7]="depth! 8 points, 6 faces, 1 cube",
 [8]="copper bars - homage to the amiga",
 [9]="and now... a whole world",
 [10]="burning bright at the end"
}

-- ===== story-frame scenes: awakening, outro, intro =====
function awakening()
 cls(0)
 local p=scene_t
 -- center pixel always
 pix(120,68,15)
 -- pixels spiraling out (frames 0+)
 for i=1,math.min(p,100) do
  local a=i*0.5+t/120
  local r=4+i*0.4+math.sin(t/30+i)*2
  pix(120+math.cos(a)*r,68+math.sin(a)*r,12+(i%4))
 end
 -- lines radiating (after 90 frames)
 if p>90 then
  for i=1,math.min((p-90)//5,18) do
   local a=i*math.pi/9+t/45
   local r=30+math.sin(t/25+i)*12
   line(120,68,120+math.cos(a)*r,68+math.sin(a)*r,9+(i%6))
  end
 end
 -- circles blooming (after 200 frames)
 if p>200 then
  for i=1,math.min((p-200)//12,7) do
   local r=10+i*8+math.sin(t/18+i*0.7)*3
   circb(120,68,r,12+(i%4))
  end
 end
 -- ghostly api hints
 if p<90 then
  print("pix()",100,96,12,false,1,true)
 elseif p<200 then
  print("pix() + line()",80,96,12,false,1,true)
 elseif p<320 then
  print("pix() + line() + circ()",60,96,14,false,1,true)
 else
  print("...this is fun",90,96,15,false,1,true)
 end
end

credits={
 "TIC-80 DEMO",
 "",
 " claude's first attempt",
 " at a fantasy console",
 "",
 "         2026",
 "",
 "",
 " --- scenes ---",
 "",
 "  awakening",
 "  plasma",
 "  starfield",
 "  tunnel",
 "  metaballs",
 "  rotozoom",
 "  cube3d",
 "  copper bars",
 "  voxel landscape",
 "  fire",
 "",
 "",
 " --- under the hood ---",
 "",
 " 4 waveforms",
 " 6 sfx slots",
 " 4 audio channels",
 "",
 " pokes to 0x0FFE4",
 " (waveform memory)",
 "",
 " pokes to 0x100E4",
 " (sfx memory)",
 "",
 " palette fade via",
 " 0x03FC0",
 "",
 "",
 " --- greetings ---",
 "",
 " to annejan,",
 " who watched this first",
 "",
 " to the demoscene,",
 " for inspiring us all",
 "",
 " to everyone at",
 " tic80.com",
 "",
 " to nesbox,",
 " for making tic-80",
 "",
 " to anthropic,",
 " for making claude",
 "",
 " to all chiptune nerds,",
 " all pixel artists,",
 " all fantasy console fans,",
 " all sceners past and",
 " present, and to",
 " everyone watching",
 " this right now",
 "",
 "",
 " --- thanks ---",
 "",
 " lua devs",
 " sdl + opengl",
 " 16 colors of sweetie16",
 "",
 "",
 "",
 "",
 " thank you",
 " for watching",
 "",
 "         <3",
 "",
 "",
 "  see you in the next",
 "      demo, maybe",
 "",
 ""
}

-- length needed so last line passes top of screen (y < -15) before restart
OUTRO_LEN=math.ceil((140+15+(#credits-1)*OUTRO_LINE_H)/OUTRO_SCROLL)+60

function outro()
 cls(0)
 local p=scene_t
 -- soft starfield drifting in the background
 for i=1,80 do
  local x=(i*53+p//2)%240
  local y=(i*97)%136
  pix(x,y,1+(i%3))
 end
 -- subtle moving aurora bands
 for y=0,135 do
  local v=math.sin(y/22+p/60)+math.sin(y/15-p/45)
  if v>1.4 then pix((p+y*3)%240,y,9) end
  if v<-1.4 then pix((p*2+y*5)%240,y,2) end
 end
 -- credits scroll
 local scroll_y=140-p*OUTRO_SCROLL
 for i,l in ipairs(credits) do
  local y=math.floor(scroll_y+(i-1)*OUTRO_LINE_H)
  if y>-10 and y<140 then
   if i==1 then
    print_big(l,72,y,15,true,2)
   elseif l~="" then
    local x=(240-#l*6)/2
    local col=14
    if l:sub(1,4)=="--- " then col=12       -- section headers
    elseif l:sub(1,4)=="    " then col=15
    elseif y<28 or y>108 then col=10 end
    print(l,x+1,y+1,0,false,1,false)
    print(l,x,y,col,false,1,false)
   end
  end
 end
end

function intro()
 cls(0)
 -- background: a calmer plasma so the text reads
 for cy=0,33 do
  for cx=0,59 do
   local v=math.sin(cx/10+t/40)+math.sin(cy/8-t/60)+math.sin((cx-cy)/12+t/55)
   rect(cx*4,cy*4,4,4,math.floor((v+3)*1.5)%8+1)
  end
 end
 -- starbursts on beat
 if beat>0.5 then
  for i=1,12 do
   local a=i*math.pi/6+t/30
   local r=20+beat*40
   line(120,68,120+math.cos(a)*r,68+math.sin(a)*r,15)
  end
 end
 -- big title with sine bounce and shadow
 local title="TIC-80 DEMO"
 local cw=24
 local startx=120-(#title*cw)/2
 for i=1,#title do
  local ch=title:sub(i,i)
  local x=startx+(i-1)*cw
  local y=50+math.sin((t+i*8)/12)*8
  print(ch,x+2,y+2,0,false,3,false)  -- shadow
  print(ch,x,y,15,false,3,false)
 end
 print("claude's first attempt",66,108,12,false,1,true)
 print("a tiny journey through 16 colors",46,118,14,false,1,true)
end

-- ===== ui helpers =====
function print_big(s,x,y,col,shadow,sc)
 if shadow then print(s,x+1,y+1,0,false,sc,false) end
 print(s,x,y,col,false,sc,false)
end

-- apply palette attenuation for fade (1.0 = full, 0.0 = black)
function apply_fade(k)
 for i=0,47 do
  poke(0x03FC0+i,math.floor(orig_pal[i]*k))
 end
end

-- ===== music sequencer: patterns & tempo =====
-- multi-track chiptune: bass (chan 0), lead (chan 1), kick (chan 2), hihat (chan 3)
-- 16-bar bass pattern, 32-bar lead pattern (twice the rate)
bass={"C-2","C-2","G-2","E-2","F-2","F-2","C-3","G-2",
      "A-2","A-2","E-3","C-3","F-2","G-2","A-2","E-2"}
lead={"C-5","E-5","G-5","E-5","C-5","E-5","G-5","B-5",
      "F-4","A-4","C-5","A-4","F-4","A-4","C-5","E-5",
      "A-4","C-5","E-5","C-5","A-4","C-5","E-5","G-5",
      "F-4","A-4","C-5","E-5","F-4","G-4","A-4","C-5"}
-- 16-step drum patterns: 1 = play
kick_p={1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0}
hat_p ={0,0,1,0,0,0,1,1,0,0,1,0,0,0,1,1}
-- scale tempo: 1 beat = 15 frames (4 beats/sec → 240 bpm sixteenth)

-- ===== main loop: dispatch + fade + music + scene advance =====
function TIC()
 -- restore palette every frame, then we re-attenuate if fading
 for i=0,47 do poke(0x03FC0+i,orig_pal[i]) end

 if scene==0 then intro()
 elseif scene==1 then awakening()
 elseif scene==2 then plasma()
 elseif scene==3 then starfield()
 elseif scene==4 then tunnel()
 elseif scene==5 then metaballs_fx()
 elseif scene==6 then rotozoomer()
 elseif scene==7 then cube3d()
 elseif scene==8 then copper()
 elseif scene==9 then voxel()
 elseif scene==10 then fire_effect()
 elseif scene==11 then outro()
 end

 if scene>=1 and scene<=10 then
  scroller()
  local slide=math.max(0,1-scene_t/30)
  local nx=8-slide*100
  print_big(names[scene]:upper(),nx,6,15,true,2)
  -- caption (Claude's POV) fades in 0-30, holds, fades 150-180
  local cap=captions[scene]
  if cap and scene_t<180 then
   local x=(240-#cap*6)/2
   print(cap,x+1,103,0,false,1,false)
   print(cap,x,102,14,false,1,false)
  end
 end

 -- fade in/out
 local k=1
 if scene_t<FADE then k=scene_t/FADE end
 if scene_t>SCENE_LEN-FADE then k=(SCENE_LEN-scene_t)/FADE end
 if k<1 then apply_fade(k) end

 -- music intensity rises with the story
 -- 1=pad only, 2=+bass, 3=+lead, 4=+hat, 5=+kick+snare (full)
 local intens
 if scene==0 then intens=1
 elseif scene==1 then intens=2
 elseif scene<=4 then intens=3
 elseif scene<=7 then intens=4
 elseif scene<=10 then intens=5
 else intens=1 end
 -- outro: fade volume as it scrolls
 local outro_atten=1
 if scene==11 then
  outro_atten=math.max(0,1-scene_t/OUTRO_LEN)
 end

 local step=t//15
 if t%15==0 then
  -- pad: always (intensity 1+)
  if step%8==0 then
   local chords={"C-4","F-4","A-4","G-4"}
   sfx(4,chords[(step//8)%4+1],56,1,math.floor(5*outro_atten))
  end
  -- bass (intensity 2+)
  if intens>=2 and step%2==0 then
   sfx(0,bass[(step//2)%16+1],28,0,math.floor(10*outro_atten))
  end
  -- lead (intensity 3+)
  if intens>=3 then
   sfx(1,lead[step%32+1],14,1,math.floor(8*outro_atten))
  end
  -- hihat (intensity 4+)
  if intens>=4 and hat_p[step%16+1]==1 then
   sfx(2,"C-6",4,3,6)
  end
  -- kick + snare (intensity 5)
  if intens>=5 then
   if kick_p[step%16+1]==1 then
    sfx(3,"C-4",8,2,12)
    beat=1
   end
   local sub=step%16
   if sub==4 or sub==12 then sfx(5,"G-4",10,2,10) end
  end
 end
 beat=math.max(0,beat-0.08)
 -- scene transition blip (skip for outro)
 if scene_t==0 and scene>0 and scene<11 then sfx(1,"C-6",16,1,11) end

 t=t+1
 scene_t=scene_t+1
 local len=SCENE_LEN
 if scene==0 then len=INTRO_LEN
 elseif scene==1 then len=AWAKEN_LEN
 elseif scene==11 then len=OUTRO_LEN end
 if scene_t>=len then
  scene_t=0
  scene=scene+1
  if scene>N_SCENES then scene=0 end
 end
end
