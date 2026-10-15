local edit=require('moho_mcp.iterative_write')
local function fixture(fn)
    local server=require('moho_mcp.server');local old=server.getInfo;local oldMOHO=MOHO
    local info={serverId='epoch',running=true};server.getInfo=function()return info end
    MOHO={InterpSetting={new_local=function()return {}end}}
    local values={[0]=0,[12]=0.5,[24]=0};local interp={[0]='smooth',[12]='linear',[24]='smooth'};local undo=0
    local function frames()local f={};for k in pairs(values) do f[#f+1]=k end;table.sort(f);return f end
    local ch={CountKeys=function()return #frames()end,GetKeyWhen=function(_,i)return frames()[i+1]end,
        GetValue=function(_,f)return values[f] or 0 end,HasKey=function(_,f)return values[f]~=nil end,
        SetValue=function(_,f,v)values[f]=v end,DeleteKey=function(_,f)values[f]=nil;interp[f]=nil end,
        CurrentAction=function()return nil end,GetKeyInterp=function(_,f,i)i.value=interp[f]end,
        SetKeyInterp=function(_,f,i)interp[f]=i.value end,
        SetKeyWhen=function(_,i,f)local from=frames()[i+1];values[f]=values[from];interp[f]=interp[from];values[from]=nil;interp[from]=nil end}
    local l={Name=function()return 'Rig'end,CurrentAction=function()return ''end,TotalTimingOffset=function()return 0 end,IsLocked=function()return false end}
    local b={Name=function()return 'B'end,fAnimAngle=ch,fPos={x=0,y=0},fParent=-1,fLength=1,fAngle=0}
    local s={CountBones=function()return 1 end}
    local m={layer=l,document={Path=function()return 'E:/test.moho'end,EndFrame=function()return 48 end,LayerAbsoluteID=function()return 1 end,PrepUndo=function()undo=undo+1 end,SetDirty=function()end}}
    local p={layerId=1,boneId=0,frame=12,angle=0.75}
    local plan={version=2,session='session',serverId='epoch',documentPath='E:/test.moho',expiresAt=os.time()+600,operation={kind='set',layerId=1,boneId=0,frame=12,angle=0.75}}
    local function refresh()plan.token=edit.inspect(m,p,l,b,s).token end
    local function apply()return edit.apply(m,p,l,b,s,plan,{session='session'},info)end
    refresh()
    local ok,err=pcall(fn,{m=m,l=l,b=b,s=s,ch=ch,values=values,interp=interp,p=p,plan=plan,info=info,refresh=refresh,apply=apply,undo=function()return undo end})
    server.getInfo=old;MOHO=oldMOHO;if not ok then error(err)end
end
local function case(name,fn)test(name,function()fixture(fn)end)end
case('iterative replace preserves other keys and interpolation',function(f)
    local r=f.apply();assert_true(r.verified);assert_eq(f.values[12],0.75);assert_eq(f.values[24],0);assert_eq(f.interp[12],'linear');assert_eq(f.undo(),1)
    assert_eq(f.apply(),nil)
    f.refresh();f.p.angle=1;f.plan.operation.angle=1;assert_true(f.apply().verified);assert_eq(f.values[12],1)
end)
case('iterative native move retains value and interpolation',function(f)
    f.plan.operation.kind='move';f.plan.operation.fromFrame=12;f.plan.operation.frame=18;f.plan.operation.angle=0.5;f.p.frame=18;f.p.angle=0.5
    assert_true(f.apply().verified);assert_eq(f.values[12],nil);assert_eq(f.values[18],0.5);assert_eq(f.interp[18],'linear');assert_eq(f.values[24],0)
end)
case('iterative occupied move destination rejected',function(f)
    f.plan.operation.kind='move';f.plan.operation.fromFrame=24
    assert_eq(f.apply(),nil);assert_eq(f.undo(),0)
end)
for _,field in ipairs({'session','serverId','documentPath','token'}) do
    case('iterative rejects wrong '..field,function(f)f.plan[field]='wrong';assert_eq(f.apply(),nil);assert_eq(f.undo(),0)end)
end
case('iterative rejects expired approval',function(f)f.plan.expiresAt=0;assert_eq(f.apply(),nil)end)
case('iterative rejects stale key snapshot',function(f)f.values[24]=2;assert_eq(f.apply(),nil);assert_eq(f.undo(),0)end)
case('iterative rejects replaced same-name bone',function(f)local copy={};for k,v in pairs(f.b)do copy[k]=v end;f.b=copy;assert_eq(edit.apply(f.m,f.p,f.l,copy,f.s,f.plan,{session='session'},f.info),nil)end)
case('iterative rejects changed rig length',function(f)f.b.fLength=2;assert_eq(f.apply(),nil)end)
case('iterative protects frame zero',function(f)f.p.frame=0;f.plan.operation.frame=0;assert_eq(f.apply(),nil)end)
case('iterative rejects out of range frame',function(f)f.p.frame=49;f.plan.operation.frame=49;assert_eq(f.apply(),nil)end)
case('iterative rejects wrong pose',function(f)f.p.angle=1;assert_eq(f.apply(),nil)end)
case('iterative rejects locked or Action layer',function(f)f.l.IsLocked=function()return true end;assert_eq(f.apply(),nil);f.l.IsLocked=function()return false end;f.l.CurrentAction=function()return 'Walk'end;assert_eq(f.apply(),nil)end)
case('iterative setter failure restores prior key',function(f)local original=f.ch.SetValue;local first=true;f.ch.SetValue=function(c,k,v)original(c,k,v);if first then first=false;error('injected')end end;local r,e=f.apply();assert_eq(r,nil);assert_true(e:find('rolled back')~=nil);assert_eq(f.values[12],0.5);assert_eq(f.apply(),nil)end)
case('iterative move failure restores source and interpolation',function(f)
    f.plan.operation.kind='move';f.plan.operation.fromFrame=12;f.plan.operation.frame=18;f.plan.operation.angle=0.5;f.p.frame=18;f.p.angle=0.5
    local original=f.ch.SetKeyWhen;local first=true;f.ch.SetKeyWhen=function(c,i,k)original(c,i,k);if first then first=false;error('injected')end end
    local r,e=f.apply();assert_eq(r,nil);assert_true(e:find('rolled back')~=nil);assert_eq(f.values[12],0.5);assert_eq(f.values[18],nil);assert_eq(f.interp[12],'linear')
end)
case('iterative rollback failure explicit',function(f)f.ch.SetValue=function()error('injected')end;local r,e=f.apply();assert_eq(r,nil);assert_true(e:find('ROLLBACK FAILED')~=nil)end)
case('iterative undo failure leaves keys intact',function(f)f.m.document.PrepUndo=function()error('undo')end;assert_eq(f.apply(),nil);assert_eq(f.values[12],0.5)end)
case('iterative no-op does not prepare undo',function(f)f.p.angle=0.5;f.plan.operation.angle=0.5;assert_true(f.apply().unchanged);assert_eq(f.undo(),0)end)
