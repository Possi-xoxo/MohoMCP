local safe=require('moho_mcp.safe_write')
local function params() return {layerId=0,boneId=0,frame=12,angle=math.pi/6} end
local function plan()
    return {version=1,approvalId='test-approval-0001',session='session',serverId='server',expiresAt=1100,
        documentPath='E:/MOHO/Projects/Test.moho',layerName='Rig',boneName='Bone',operations={
        {layerId=0,boneId=0,frame=0,angle=0},params(),{layerId=0,boneId=0,frame=24,angle=0}}}
end
for _,field in ipairs({'layerId','boneId','frame'}) do
    for _,value in ipairs({-1,0.5,math.huge,0/0,'1'}) do
        test('write rejects invalid '..field..' '..tostring(value),function()
            local p=params();p[field]=value;assert_false(safe.validate(p))
        end)
    end
end
for _,value in ipairs({math.huge,-math.huge,0/0,'0',13}) do
    test('write rejects invalid angle '..tostring(value),function()
        local p=params();p.angle=value;assert_false(safe.validate(p))
    end)
end
test('write rejects missing transform and unsupported compound transforms',function()
    local p=params();p.angle=nil;assert_false(safe.validate(p))
    p=params();p.scale=1;assert_false(safe.validate(p))
    p=params();p.posX=0;assert_false(safe.validate(p))
end)
local function check(p,path,owner,info,request)
    return safe.checkApproval(p,owner or {session='session'},info or {serverId='server',running=true},path or 'E:/MOHO/Projects/Test.moho',request or params(),1000)
end
test('exact approved document/session/poses accepted',function() assert_true(check(plan())) end)
test('wrong project rejected',function() assert_false(check(plan(),'E:/MOHO/Projects/Other.moho')) end)
test('relative project path rejected',function() assert_false(check(plan(),'Test.moho')) end)
test('old bridge session rejected',function() assert_false(check(plan(),nil,{session='another'})) end)
test('old server epoch rejected',function() assert_false(check(plan(),nil,nil,{serverId='another',running=true})) end)
test('expired approval rejected',function() local p=plan();p.expiresAt=999;assert_false(check(p)) end)
test('unapproved angle rejected',function() local r=params();r.angle=0.4;assert_false(check(plan(),nil,nil,nil,r)) end)
test('unapproved bone rejected',function() local r=params();r.boneId=1;assert_false(check(plan(),nil,nil,nil,r)) end)
test('modified pose plan rejected',function() local p=plan();p.operations[3].angle=1;assert_false(check(p)) end)

local serial=0
local function fixture(callback)
    serial=serial+1
    local saved=safe.authorize
    safe.authorize=function() return 'fixture-approval-'..serial end
    local keys={[0]=0};local events={}
    local channel={HasKey=function(_,f) return keys[f]~=nil end,GetValue=function(_,f) return keys[f] or 0 end,
        SetValue=function(_,f,v) events[#events+1]='set';keys[f]=v end,
        DeleteKey=function(_,f) events[#events+1]='delete';keys[f]=nil end}
    local moho={document={EndFrame=function()return 24 end,
        PrepUndo=function()events[#events+1]='undo' end,SetDirty=function()events[#events+1]='dirty' end}}
    local ok,err=pcall(callback,moho,{}, {fAnimAngle=channel},keys,events)
    safe.authorize=saved
    if not ok then error(err) end
end
test('valid key preserves undo ordering and verifies readback',function() fixture(function(m,l,b,keys,events)
    local result=safe.setAngle(m,params(),l,b)
    assert_true(result.verified);assert_eq(keys[12],math.pi/6)
    assert_eq(table.concat(events,','),'undo,dirty,set')
end) end)
test('frame outside range performs no mutation or undo',function() fixture(function(m,l,b,keys,events)
    local p=params();p.frame=25;assert_eq(safe.setAngle(m,p,l,b),nil);assert_eq(#events,0)
end) end)
test('existing key cannot be overwritten',function() fixture(function(m,l,b,keys,events)
    keys[12]=0.2;assert_eq(safe.setAngle(m,params(),l,b),nil);assert_eq(keys[12],0.2);assert_eq(#events,0)
end) end)
test('neutral setup key is retained without a redundant undo entry',function() fixture(function(m,l,b,keys,events)
    local p=params();p.frame=0;p.angle=0;assert_true(safe.setAngle(m,p,l,b).unchanged);assert_eq(#events,0)
    p.angle=0.1;assert_eq(safe.setAngle(m,p,l,b),nil);assert_eq(keys[0],0)
end) end)
test('undo preparation failure prevents key write',function() fixture(function(m,l,b,keys)
    m.document.PrepUndo=function()error('undo unavailable')end
    assert_eq(safe.setAngle(m,params(),l,b),nil);assert_eq(keys[12],nil)
end) end)
test('setter that mutates then throws is rolled back and approval blocked',function() fixture(function(m,l,b,keys,events)
    b.fAnimAngle.SetValue=function(_,f,v)keys[f]=v;error('setter failed')end
    local value,err=safe.setAngle(m,params(),l,b);assert_eq(value,nil);assert_true(err:find('rolled back')~=nil);assert_eq(keys[12],nil)
end) end)
test('readback mismatch rolls back new key',function() fixture(function(m,l,b,keys)
    b.fAnimAngle.SetValue=function(_,f,v)keys[f]=99 end
    local value,err=safe.setAngle(m,params(),l,b);assert_eq(value,nil);assert_true(err:find('rolled back')~=nil);assert_eq(keys[12],nil)
end) end)
test('rollback failure is explicit, never reported as success',function() fixture(function(m,l,b,keys)
    b.fAnimAngle.SetValue=function(_,f,v)keys[f]=v;error('failed')end
    b.fAnimAngle.DeleteKey=function()error('rollback failed')end
    local value,err=safe.setAngle(m,params(),l,b);assert_eq(value,nil);assert_true(err:find('ROLLBACK FAILED')~=nil)
end) end)
test('missing snapshot API causes no mutation',function() fixture(function(m,l,b,keys,events)
    b.fAnimAngle.HasKey=nil;assert_eq(safe.setAngle(m,params(),l,b),nil);assert_eq(#events,0)
end) end)
test('generic keyframe tool fails closed without touching a document',function()
    local animation=require('moho_mcp.tools.animation')
    local value=animation.setKeyframe(nil,{layerId=0,frame=12,channel='rotation',value=1})
    assert_eq(value,nil)
end)

local function authorizedFixture(callback)
    local originalOpen=io.open
    local server= require('moho_mcp.server')
    local originalInfo=server.getInfo
    local p=plan();p.expiresAt=os.time()+600;p.approvalId='real-approval-'..tostring({})
    local l={Name=function()return 'Rig'end,CurrentAction=function()return ''end,
        TotalTimingOffset=function()return 0 end,IsLocked=function()return false end}
    local keys={[0]=0}
    local ch={CurrentAction=function()return ''end,GetValue=function(_,f)return keys[f] or 0 end,
        HasKey=function(_,f)return keys[f]~=nil end,SetValue=function(_,f,v)keys[f]=v end,
        DeleteKey=function(_,f)keys[f]=nil end}
    local b={Name=function()return 'Bone'end,fAnimAngle=ch,fConstraints=false,fFixedAngle=false,fAngleControl=-1}
    local m={layer=l,document={Path=function()return 'E:/MOHO/Projects/Test.moho'end,
        LayerAbsoluteID=function()return 0 end,EndFrame=function()return 24 end,
        PrepUndo=function()end,SetDirty=function()end}}
    server.getInfo=function()return {ipcDir='test/',serverId='server',running=true}end
    io.open=function(path)
        local value=path:find('write%-approval') and p or {session='session'}
        return {read=function()return json.encode(value)end,close=function()end}
    end
    local ok,err=pcall(callback,m,l,b,keys,p)
    io.open=originalOpen;server.getInfo=originalInfo
    if not ok then error(err)end
end
test('authorization is checked on every write and failed approval cannot resume',function() authorizedFixture(function(m,l,b,keys)
    b.fAnimAngle.SetValue=function(_,f,v)keys[f]=v;error('failed')end
    assert_eq(safe.setAngle(m,params(),l,b),nil)
    b.fAnimAngle.SetValue=function(_,f,v)keys[f]=v end
    local value,err=safe.setAngle(m,params(),l,b)
    assert_eq(value,nil);assert_true(err:find('blocked')~=nil);assert_eq(keys[12],nil)
end) end)
test('real approval refuses switched document',function() authorizedFixture(function(m,l,b,keys)
    m.document.Path=function()return 'E:/MOHO/Projects/Other.moho'end
    assert_eq(safe.setAngle(m,params(),l,b),nil);assert_eq(keys[12],nil)
end) end)
test('real approval refuses actions and time offsets',function() authorizedFixture(function(m,l,b,keys)
    l.CurrentAction=function()return 'Walk'end
    assert_eq(safe.setAngle(m,params(),l,b),nil)
    l.CurrentAction=function()return ''end;l.TotalTimingOffset=function()return 10 end
    assert_eq(safe.setAngle(m,params(),l,b),nil);assert_eq(keys[12],nil)
end) end)
test('real approval refuses renamed or locked layer and controlled bone',function() authorizedFixture(function(m,l,b,keys)
    l.Name=function()return 'Other'end;assert_eq(safe.setAngle(m,params(),l,b),nil)
    l.Name=function()return 'Rig'end;l.IsLocked=function()return true end;assert_eq(safe.setAngle(m,params(),l,b),nil)
    l.IsLocked=function()return false end;b.fFixedAngle=true;assert_eq(safe.setAngle(m,params(),l,b),nil)
    assert_eq(keys[12],nil)
end) end)
test('real approval permits only explicitly approved pose',function() authorizedFixture(function(m,l,b,keys)
    assert_true(safe.setAngle(m,params(),l,b).verified);assert_eq(keys[12],math.pi/6)
end) end)

test('timeline rejection identifies API values without preparing undo or writing',function() authorizedFixture(function(m,l,b,keys)
    m.document.PrepUndo=function()error('must not prepare undo')end
    b.fAnimAngle.CurrentAction=function()return false end
    local value,err=safe.setAngle(m,params(),l,b)
    assert_eq(value,nil);assert_eq(keys[12],nil)
    assert_true(err:find('layerAction=string:',1,true)~=nil)
    assert_true(err:find('timingOffset=number:',1,true)~=nil)
    assert_true(err:find('channelAction=boolean:',1,true)~=nil)
end) end)

test('Moho 14.5 nil channel action accepted only on explicit Mainline with zero offset',function() authorizedFixture(function(m,l,b,keys)
    b.fAnimAngle.CurrentAction=function()return nil end
    l.CurrentAction=function()return nil end
    assert_eq(safe.setAngle(m,params(),l,b),nil);assert_eq(keys[12],nil)
    l.CurrentAction=function()return 'Walk'end
    assert_eq(safe.setAngle(m,params(),l,b),nil);assert_eq(keys[12],nil)
    l.CurrentAction=function()return ''end;l.TotalTimingOffset=function()return 1 end
    assert_eq(safe.setAngle(m,params(),l,b),nil);assert_eq(keys[12],nil)
    l.TotalTimingOffset=function()return 0 end
    b.fAnimAngle.CurrentAction=function()return 'Walk'end
    assert_eq(safe.setAngle(m,params(),l,b),nil);assert_eq(keys[12],nil)
    b.fAnimAngle.CurrentAction=function()return nil end
    assert_true(safe.setAngle(m,params(),l,b).verified)
end) end)

test('approved thirty-degree pose may cross two pi without changing neutral',function()
    local p=plan();local neutral=6.27973747253418
    p.operations[1].angle=neutral;p.operations[2].angle=neutral+math.pi/6;p.operations[3].angle=neutral
    local r=params();r.angle=p.operations[2].angle
    assert_true(safe.validate(r));assert_true(check(p,nil,nil,nil,r))
end)
