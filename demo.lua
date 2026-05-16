S=math.sin
R=math.random
A=math.atan
F=math.floor
t=0
s={}
for i=1,80 do s[i]={(R()-.5)*200,(R()-.5)*200,R()*99+1}end
f={}
function TIC()
t=t+1
local n=t//360%4
if n==0 then
for y=0,33 do for x=0,59 do
rect(x*4,y*4,4,4,F((S(x/8+t/30)+S(y/6-t/40)+S((x+y)/10+t/50)+3)*2.5)%16)
end end
elseif n==1 then
cls()
for i=1,80 do local q=s[i]
q[3]=q[3]-1.5
if q[3]<1 then q[1]=(R()-.5)*200 q[2]=(R()-.5)*200 q[3]=99 end
pix(120+q[1]/q[3]*80,68+q[2]/q[3]*80,12+F((99-q[3])/25)%4)
end
elseif n==2 then
for y=0,16 do for x=0,29 do
rect(x*8,y*8,8,8,F(24/(((x-14.5)^2+(y-8)^2)^.5+.1)+A(y-8,x-14.5)*3+t/4)%6+9)
end end
else
cls()
for x=0,59 do f[2100+x]=R(30,36)end
for y=0,34 do for x=0,59 do
f[y*60+x]=math.max(0,(f[(y+1)*60+x]or 0)-R(0,2))
end end
for y=0,35 do for x=0,59 do
local h=f[y*60+x]or 0
if h>0 then rect(x*4,y*4-8,4,4,h<10 and 2 or h<20 and 4 or h<30 and 14 or 12)end
end end
end
end
