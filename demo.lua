-- title:  multi-scene demo
-- author: annejan
-- desc:   plasma / starfield / tunnel / rotozoomer / fire + scroller, fade transitions, sfx
-- script: lua

t=0
scene=1
scene_t=0
SCENE_LEN=420
FADE=40
N_SCENES=5

-- save original palette so we can attenuate it for fades
orig_pal={}
for i=0,47 do orig_pal[i]=peek(0x03FC0+i) end

-- poke a square wave into waveform 0 (16 bytes at 0x0FFE4)
-- each byte = two 4-bit samples; first half full (0xFF), second half silent (0x00)
for i=0,7 do poke(0x0FFE4+i,0xFF) end
for i=8,15 do poke(0x0FFE4+i,0x00) end

-- poke a basic SFX 0: wave 0, volume ramps down across 30 frames
-- layout per SFX (66 bytes): 15 wave-nibbles, 15 vol-nibbles, 15 chord, 15 pitch, 6 trailing
local sfx0=0x100E4
for i=0,65 do poke(sfx0+i,0) end -- clear waves, chord, pitch
-- volumes: pack two nibbles per byte, descending F,F,E,E,...
for i=0,14 do
 local a=math.max(0,15-i)
 local b=math.max(0,15-i-1)
 poke(sfx0+15+i,a*16+b)
end

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
for i=1,80 do
 stars[i]={
  x=(math.random()-0.5)*200,
  y=(math.random()-0.5)*200,
  z=math.random()*100+1
 }
end

-- fire buffer
FW,FH=60,36
fire={}
for i=0,FW*FH-1 do fire[i]=0 end

function plasma()
 cls(0)
 for cy=0,33 do
  for cx=0,59 do
   local v=math.sin(cx/8+t/30)+math.sin(cy/6-t/40)+math.sin((cx+cy)/10+t/50)
   local c=math.floor((v+3)*2.5)%16
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

scroll_text="  GREETINGS FROM TIC-80 LUA  ***  MULTI-SCENE DEMO  ***  PLASMA / STARFIELD / TUNNEL / ROTOZOOM / FIRE  ***  ENJOY THE SHOW!     "

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

names={"plasma","starfield","tunnel","rotozoomer","fire"}

-- apply palette attenuation for fade (1.0 = full, 0.0 = black)
function apply_fade(k)
 for i=0,47 do
  poke(0x03FC0+i,math.floor(orig_pal[i]*k))
 end
end

-- simple chiptune: bass notes on the beat, scene-change blip
notes={"C-3","E-3","G-3","A-3","G-3","E-3","C-3","D-3"}

function TIC()
 -- restore palette every frame, then we re-attenuate if fading
 for i=0,47 do poke(0x03FC0+i,orig_pal[i]) end

 if scene==1 then plasma()
 elseif scene==2 then starfield()
 elseif scene==3 then tunnel()
 elseif scene==4 then rotozoomer()
 elseif scene==5 then fire_effect()
 end

 scroller()
 print(names[scene],4,4,15,false,1,true)

 -- fade in/out
 local k=1
 if scene_t<FADE then k=scene_t/FADE end
 if scene_t>SCENE_LEN-FADE then k=(SCENE_LEN-scene_t)/FADE end
 if k<1 then apply_fade(k) end

 -- music: beat every 30 frames
 if scene_t%30==0 then
  sfx(0,notes[(scene_t//30)%#notes+1],28,0,8)
 end
 -- scene-change blip
 if scene_t==0 then sfx(0,"C-5",10,1,12) end

 t=t+1
 scene_t=scene_t+1
 if scene_t>=SCENE_LEN then
  scene_t=0
  scene=scene%N_SCENES+1
 end
end
