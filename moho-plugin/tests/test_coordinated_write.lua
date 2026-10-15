local tx=require('moho_mcp.coordinated_write')
local function fixture(fn)
    local server=require('moho_mcp.server');local old=server.getInfo;local oldMOHO=MOHO
    local info={serverId='epoch',running=true};server.getInfo=function()return info end
    MOHO={INTERP_SMOOTH=1,InterpSetting={new_local=function()return {}end}}
    local values={{[0]=0,[6]=0.2},{[0]=1,[7]=1.2}}
    local modes={{[0]=1,[6]=2},{[0]=1,[7]=2}};local channels={};local bones={};local undo=0;local writes=0
    for i=1,2 do
        local v=values[i];local modes=modes[i]
        local function frames()local f={};for k in pairs(v)do f[#f+1]=k end;table.sort(f);return f end
        local ch={CountKeys=function()return #frames()end,GetKeyWhen=function(_,id)return frames()[id+1]end,GetValue=function(_,f)return v[f] or v[0]end,HasKey=function(_,f)return v[f]~=nil end,
            CurrentAction=function()return nil end,GetKeyInterpMode=function(_,f)return modes[f]end,
            GetKeyInterp=function(_,f,out)out.mode=modes[f]end,
            SetKeyInterp=function(_,f,setting)modes[f]=type(setting)=='table' and setting.mode or setting end,
            SetValue=function(_,f,value)writes=writes+1;v[f]=value;modes[f]=modes[f] or 1 end,
            DeleteKey=function(_,f)v[f]=nil;modes[f]=nil end}
        channels[i]=ch;bones[i]={Name=function()return 'B'..i end,fAnimAngle=ch,fLength=1,fParent=i==1 and -1 or 0,fAngle=i-1,fPos={x=i-1,y=0}}
    end
    local l={Name=function()return 'Arm'end,CurrentAction=function()return ''end,TotalTimingOffset=function()return 0 end,IsLocked=function()return false end}
    local s={CountBones=function()return 2 end,Bone=function(_,id)return bones[id+1]end}
    local m={layer=l,document={Path=function()return 'E:/arm.moho'end,LayerAbsoluteID=function()return 1 end,EndFrame=function()return 48 end,PrepUndo=function()undo=undo+1 end,SetDirty=function()end}}
    local p={layerId=1,boneId=0,frame=12,angle=0.3}
    local plan={version=3,session='session',serverId='epoch',expiresAt=os.time()+600,documentPath='E:/arm.moho',operations={}}
    for id=0,1 do for _,f in ipairs({12,24,36,48})do plan.operations[#plan.operations+1]={layerId=1,boneId=id,frame=f,angle=id+0.3,replace=false}end end
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
