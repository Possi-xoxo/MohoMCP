local tx=require('moho_mcp.coordinated_write')
local function fixture(fn,count)
    count=count or 2
    local server=require('moho_mcp.server');local old=server.getInfo;local oldMOHO=MOHO
    local info={serverId='epoch',running=true};server.getInfo=function()return info end
    MOHO={INTERP_SMOOTH=1,InterpSetting={new_local=function()return {}end}}
    local values={{[0]=0,[6]=0.2},{[0]=1,[7]=1.2}}
    local modes={{[0]=1,[6]=2},{[0]=1,[7]=2}};local channels={};local bones={};local undo=0;local writes=0
    for i=3,count do values[i]={[0]=i-1,[7]=i-0.8};modes[i]={[0]=1,[7]=2} end
    for i=1,count do
        local v=values[i];local modes=modes[i]
        local function frames()local f={};for k in pairs(v)do f[#f+1]=k end;table.sort(f);return f end
        local ch={CountKeys=function()return #frames()end,GetKeyWhen=function(_,id)return frames()[id+1]end,GetValue=function(_,f)return v[f] or v[0]end,HasKey=function(_,f)return v[f]~=nil end,
            CurrentAction=function()return nil end,GetKeyInterpMode=function(_,f)return modes[f]end,
            GetKeyInterp=function(_,f,out)out.mode=modes[f]end,
            SetKeyInterp=function(_,f,setting)modes[f]=type(setting)=='table' and setting.mode or setting end,
            SetValue=function(_,f,value)writes=writes+1;v[f]=value;modes[f]=modes[f] or 1 end,
            DeleteKey=function(_,f)v[f]=nil;modes[f]=nil end}
        channels[i]=ch;bones[i]={Name=function()return 'B'..i end,fAnimAngle=ch,fLength=1,fParent=i==1 and -1 or math.floor((i-2)/2),fAngle=i-1,fPos={x=i-1,y=0}}
    end
    for _,b in ipairs(bones) do
        b.fAngleControlParent=-1;b.fPosControlParent=-1;b.fScaleControlParent=-1
        b.AreDynamicsActive=function()return false end
        b.fAnimParent={CountKeys=function()return 1 end,GetKeyWhen=function()return 0 end}
        b.fIKLock={GetValue=function()return false end,CountKeys=function()return 1 end,GetKeyWhen=function()return 0 end}
        b.fTargetBone={GetValue=function()return -1 end,CountKeys=function()return 1 end,GetKeyWhen=function()return 0 end}
    end
    local l={Name=function()return 'Arm'end,CurrentAction=function()return ''end,TotalTimingOffset=function()return 0 end,IsLocked=function()return false end}
    local s={CountBones=function()return count end,Bone=function(_,id)return bones[id+1]end}
    local m={layer=l,document={Path=function()return 'E:/arm.moho'end,LayerAbsoluteID=function()return 1 end,EndFrame=function()return 48 end,Fps=function()return 24 end,StartFrame=function()return 1 end,PrepUndo=function()undo=undo+1 end,SetDirty=function()end}}
    local p={layerId=1,boneId=0,frame=12,angle=0.3}
    local plan={version=count==2 and 3 or 4,fps=24,startFrame=1,endFrame=48,session='session',serverId='epoch',expiresAt=os.time()+600,documentPath='E:/arm.moho',operations={}}
    for id=0,count-1 do for _,f in ipairs({12,24,36,48})do plan.operations[#plan.operations+1]={layerId=1,boneId=id,frame=f,angle=id+0.3,replace=false}end end
    local function refresh()plan.token=tx.inspect(m,p,l,s).token end
    local function apply()return tx.apply(m,p,l,s,plan,{session='session'},info)end
    refresh()
    local ok,err=pcall(fn,{m=m,l=l,s=s,bones=bones,channels=channels,values=values,modes=modes,p=p,plan=plan,info=info,refresh=refresh,apply=apply,writes=function()return writes end,undo=function()return undo end})
    server.getInfo=old;MOHO=oldMOHO;if not ok then error(err)end
end
local function case(name,fn)test(name,function()fixture(fn)end)end
case('coordinated eight keys share one undo and preserve setup/unrelated keys',function(f)
    local r=f.apply();assert_true(r.verified);assert_eq(#r.changes,8);assert_eq(f.undo(),1)
    assert_eq(f.values[1][0],0);assert_eq(f.values[2][0],1);assert_eq(f.values[1][6],0.2);assert_eq(f.modes[1][6],2)
    assert_eq(f.values[2][24],1.3);assert_eq(f.modes[2][24],1);assert_eq(f.apply(),nil)
end)
case('coordinated replacement requires explicit approval and fresh snapshot',function(f)
    f.values[1][12]=0.1;f.modes[1][12]=2;f.refresh()
    assert_eq(f.apply(),nil);assert_eq(f.writes(),0)
    f.plan.operations[1].replace=true;assert_true(f.apply().verified);assert_eq(f.values[1][12],0.3)
end)
for _,key in ipairs({'session','serverId','token','documentPath'})do
    case('coordinated rejects wrong '..key,function(f)f.plan[key]='wrong';assert_eq(f.apply(),nil);assert_eq(f.undo(),0)end)
end
case('coordinated expires authorization',function(f)f.plan.expiresAt=0;assert_eq(f.apply(),nil)end)
case('coordinated validates late operation before any mutation',function(f)f.plan.operations[8].angle=math.huge;assert_eq(f.apply(),nil);assert_eq(f.writes(),0);assert_eq(f.undo(),0)end)
case('coordinated duplicate target rejected',function(f)f.plan.operations[2].frame=12;assert_eq(f.apply(),nil);assert_eq(f.writes(),0)end)
case('coordinated frame zero protected',function(f)f.plan.operations[8].frame=0;assert_eq(f.apply(),nil)end)
case('coordinated frame outside range rejected',function(f)f.plan.operations[8].frame=49;assert_eq(f.apply(),nil)end)
case('coordinated another layer rejected',function(f)f.plan.operations[8].layerId=2;assert_eq(f.apply(),nil)end)
case('coordinated too many operations rejected',function(f)for i=9,17 do f.plan.operations[i]=f.plan.operations[1]end;assert_eq(f.apply(),nil)end)
case('coordinated changed key interpolation invalidates inspection',function(f)f.modes[2][7]=3;assert_eq(f.apply(),nil);assert_eq(f.writes(),0)end)
case('coordinated changed hierarchy rejected',function(f)f.bones[2].fParent=-1;assert_eq(f.apply(),nil)end)
case('coordinated rejects zero length',function(f)f.bones[2].fLength=0;assert_eq(f.apply(),nil)end)
case('coordinated rejects constraints before any write',function(f)f.bones[2].fConstraints=true;assert_eq(f.apply(),nil);assert_eq(f.writes(),0)end)
case('coordinated action rejected',function(f)f.channels[2].CurrentAction=function()return 'Walk'end;assert_eq(f.apply(),nil)end)
case('coordinated undo failure writes nothing',function(f)f.m.document.PrepUndo=function()error('undo')end;assert_eq(f.apply(),nil);assert_eq(f.writes(),0)end)
case('coordinated second bone setter failure rolls back both bones',function(f)
    local setter=f.channels[2].SetValue;f.channels[2].SetValue=function(c,k,v)setter(c,k,v);error('mutated then failed')end
    local r,e=f.apply();assert_eq(r,nil);assert_true(e:find('all attempted keys rolled back',1,true)~=nil)
    for _,frame in ipairs({12,24,36,48})do assert_eq(f.values[1][frame],nil);assert_eq(f.values[2][frame],nil)end
    assert_eq(f.values[1][6],0.2);assert_eq(f.apply(),nil)
end)
case('coordinated replaced keys restore interpolation on later failure',function(f)
    f.values[1][12]=0.1;f.modes[1][12]=3;f.refresh();f.plan.operations[1].replace=true
    f.channels[2].SetValue=function()error('later failure')end
    assert_eq(f.apply(),nil);assert_eq(f.values[1][12],0.1);assert_eq(f.modes[1][12],3)
end)
case('coordinated interpolation readback failure rolls back',function(f)
    f.channels[2].SetKeyInterp=function(_,frame)f.modes[2][frame]=4 end
    local r,e=f.apply();assert_eq(r,nil);assert_true(e:find('rolled back',1,true)~=nil)
    assert_eq(f.values[1][12],nil)
end)
case('coordinated rollback continues after restoration failure',function(f)
    f.channels[2].SetValue=function()error('write failure')end
    f.channels[2].DeleteKey=function()error('restore failure')end
    local r,e=f.apply();assert_eq(r,nil);assert_true(e:find('ROLLBACK FAILED',1,true)~=nil)
    assert_eq(f.values[1][12],nil);assert_eq(f.values[1][48],nil)
end)
case('coordinated boolean angle controller rejected',function(f)f.bones[2].fAngleControl=true;assert_eq(f.apply(),nil);assert_eq(f.writes(),0)end)

local function multi(name,fn,n)test(name,function()fixture(fn,n or 10)end)end
multi('branched ten-bone transaction commits with one undo and preserves unrelated keys',function(f)
    local r=f.apply();assert_true(r.verified);assert_eq(#r.changes,40);assert_eq(#r.after,10);assert_eq(f.undo(),1)
    for i=1,10 do assert_eq(f.values[i][0],i-1);assert_eq(f.values[i][12],i-1+0.3) end
    assert_eq(f.values[10][7],9.2)
end)
multi('twelve-bone sixty-key idle-sized transaction fits bounds',function(f)
    for id=0,11 do f.plan.operations[#f.plan.operations+1]={layerId=1,boneId=id,frame=1,angle=id,replace=false} end
    local r=f.apply();assert_true(r.verified);assert_eq(#r.changes,60);assert_eq(f.undo(),1)
end,12)
multi('generalized rejects above thirty-two bones',function(f)f.s.CountBones=function()return 33 end;assert_eq(f.apply(),nil);assert_eq(f.writes(),0)end)
multi('generalized rejects disconnected roots',function(f)f.bones[10].fParent=-1;assert_eq(f.apply(),nil)end)
multi('generalized rejects disconnected cycle with a valid root elsewhere',function(f)f.bones[9].fParent=9;f.bones[10].fParent=8;assert_eq(f.apply(),nil);assert_eq(f.writes(),0)end)
multi('generalized rejects self parent',function(f)f.bones[8].fParent=7;assert_eq(f.apply(),nil)end)
multi('generalized rejects out of range parent',function(f)f.bones[8].fParent=10;assert_eq(f.apply(),nil)end)
multi('generalized rejects fractional parent',function(f)f.bones[8].fParent=0.5;assert_eq(f.apply(),nil)end)
multi('generalized accepts root at arbitrary numeric ID',function(f)
    for i=1,9 do f.bones[i].fParent=9 end;f.bones[10].fParent=-1;f.refresh();assert_true(f.apply().verified)
end)
multi('generalized rejects stale reparenting even if new tree valid',function(f)f.bones[10].fParent=0;assert_eq(f.apply(),nil)end)
multi('generalized validates final operation before writing',function(f)f.plan.operations[40].angle=0/0;assert_eq(f.apply(),nil);assert_eq(f.undo(),0)end)
multi('generalized playback change invalidates plan',function(f)f.m.document.Fps=function()return 30 end;assert_eq(f.apply(),nil)end)
multi('version three stays limited to two bones',function(f)f.plan.version=3;assert_eq(f.apply(),nil)end)
multi('generalized limits seventy-two operations',function(f)for i=41,73 do f.plan.operations[i]=f.plan.operations[1]end;assert_eq(f.apply(),nil);assert_eq(f.undo(),0)end)
for _,field in ipairs({'fAngleControlParent','fPosControlParent','fScaleControlParent'}) do
    multi('generalized rejects controller '..field,function(f)f.bones[10][field]=0;assert_eq(f.apply(),nil);assert_eq(f.writes(),0)end)
end
multi('generalized rejects unknown controller state',function(f)f.bones[10].fAngleControlParent=nil;assert_eq(f.apply(),nil)end)
multi('generalized rejects dynamics',function(f)f.bones[10].AreDynamicsActive=function()return true end;assert_eq(f.apply(),nil)end)
multi('generalized rejects animated target',function(f)f.bones[10].fTargetBone={GetValue=function(_,frame)return frame==0 and -1 or 2 end,CountKeys=function()return 2 end,GetKeyWhen=function(_,i)return i*12 end};assert_eq(f.apply(),nil)end)
multi('generalized late-bone failure restores every earlier bone',function(f)
    local set=f.channels[10].SetValue;f.channels[10].SetValue=function(c,k,v)set(c,k,v);error('last bone failure')end
    local r,e=f.apply();assert_eq(r,nil);assert_true(e:find('all attempted keys rolled back',1,true)~=nil)
    for i=1,10 do assert_eq(f.values[i][12],nil);assert_eq(f.values[i][0],i-1)end
end)
multi('generalized untargeted branches remain unchanged',function(f)
    while #f.plan.operations>8 do table.remove(f.plan.operations) end
    assert_true(f.apply().verified);assert_eq(f.values[10][12],nil);assert_eq(f.values[10][7],9.2)
end)

multi('generalized rejects animated reparenting',function(f)f.bones[10].fAnimParent.CountKeys=function()return 2 end;assert_eq(f.apply(),nil)end)
multi('generalized rejects IK lock',function(f)f.bones[10].fIKLock.GetValue=function()return true end;assert_eq(f.apply(),nil)end)

local function selectTwo(f,a,b)
    f.plan.operations={{layerId=1,boneId=a,frame=12,angle=0.3,replace=false},{layerId=1,boneId=b,frame=12,angle=0.4,replace=false}}
    f.p.boneId=a;f.p.angle=0.3
end
multi('twenty-bone inspection reports full hierarchy and unchanged operation bound',function(f)
    local r=tx.inspect(f.m,f.p,f.l,f.s);assert_eq(#r.bones,20);assert_eq(r.maxBones,32);assert_eq(r.maxOperations,72)
end,20)
multi('twenty-bone selective pose preserves eighteen untargeted channels with one undo',function(f)
    selectTwo(f,6,9);local r=f.apply();assert_true(r.verified);assert_eq(#r.after,20);assert_eq(#r.changes,2);assert_eq(f.undo(),1)
    for i=1,20 do assert_eq(f.values[i][0],i-1);if i~=7 and i~=10 then assert_eq(f.values[i][12],nil) end end
    assert_eq(f.values[20][7],19.2)
end,20)
multi('thirty-two-bone selective pose reaches final bone',function(f)
    selectTwo(f,0,31);assert_true(f.apply().verified);assert_eq(f.values[32][12],0.4);assert_eq(f.values[31][12],nil)
end,32)
multi('thirty-two bones accept exactly seventy-two operations',function(f)
    f.plan.operations={};for frame=12,47 do for id=0,1 do f.plan.operations[#f.plan.operations+1]={layerId=1,boneId=id,frame=frame,angle=0.3,replace=false} end end
    local r=f.apply();assert_true(r.verified);assert_eq(#r.changes,72);assert_eq(f.undo(),1)
end,32)
multi('larger rig does not increase operation limit',function(f)
    assert_eq(#f.plan.operations,80);assert_eq(f.apply(),nil);assert_eq(f.undo(),0);assert_eq(f.writes(),0)
end,20)
multi('untargeted final-bone controller prevents selective mutation',function(f)
    selectTwo(f,0,1);f.bones[32].fScaleControlParent=0;assert_eq(f.apply(),nil);assert_eq(f.undo(),0)
end,32)
multi('untargeted final-bone channel edits invalidate inspection',function(f)
    selectTwo(f,0,1);f.values[32][7]=0.2;assert_eq(f.apply(),nil);assert_eq(f.writes(),0)
end,32)
multi('untargeted final-bone reparenting invalidates inspection',function(f)
    selectTwo(f,0,1);f.bones[32].fParent=0;assert_eq(f.apply(),nil);assert_eq(f.writes(),0)
end,32)
multi('untargeted renamed bone invalidates inspection',function(f)
    selectTwo(f,0,1);f.bones[20].Name=function()return 'Renamed'end;assert_eq(f.apply(),nil);assert_eq(f.writes(),0)
end,20)
multi('duplicate bone names reject full rig before selected writes',function(f)
    selectTwo(f,0,1);f.bones[20].Name=function()return 'B1'end;assert_eq(f.apply(),nil);assert_eq(f.writes(),0)
end,20)
multi('empty bone name rejects full rig',function(f)
    selectTwo(f,0,1);f.bones[20].Name=function()return ' 'end;assert_eq(f.apply(),nil);assert_eq(f.writes(),0)
end,20)
multi('duplicate bone object is rejected',function(f)
    selectTwo(f,0,1);f.bones[20]=f.bones[19];assert_eq(f.apply(),nil);assert_eq(f.writes(),0)
end,20)
multi('last selected bone failure rolls back subset in thirty-two-bone rig',function(f)
    selectTwo(f,0,31);local setter=f.channels[32].SetValue
    f.channels[32].SetValue=function(c,k,v)setter(c,k,v);error('late failure')end
    local r,e=f.apply();assert_eq(r,nil);assert_true(e:find('all attempted keys rolled back',1,true)~=nil)
    for i=1,32 do assert_eq(f.values[i][12],nil);assert_eq(f.values[i][0],i-1) end
    assert_eq(f.values[31][7],30.2);assert_eq(f.undo(),1)
end,32)
multi('late invalid subset operation makes no changes',function(f)
    selectTwo(f,0,31);f.plan.operations[2].angle=math.huge;assert_eq(f.apply(),nil);assert_eq(f.writes(),0);assert_eq(f.undo(),0)
end,32)
multi('larger rig stale object identity rejected even with same geometry',function(f)
    selectTwo(f,0,1);local replacement={};for k,v in pairs(f.bones[20])do replacement[k]=v end;f.bones[20]=replacement
    assert_eq(f.apply(),nil);assert_eq(f.writes(),0)
end,20)
