-- Bounded, same-layer, two-bone angle transaction. No arbitrary method dispatch.
local tx={}
local last=nil
local serial=0
local safe=require('moho_mcp.safe_write')
local function path(p)
    if type(p)~='string' or not p:match('^%a:[/\\]') then error('Saved absolute document path required') end
    return p:gsub('\\','/'):lower()
end
local function channelKeys(ch)
    local n=ch:CountKeys();if not safe.integer(n) or n>4096 then error('Invalid key count') end
    local entries={}
    for i=0,n-1 do
        local frame=ch:GetKeyWhen(i);local value=ch:GetValue(frame);local mode=ch:GetKeyInterpMode(frame)
        if not safe.integer(frame) or not safe.finite(value) or not safe.integer(mode) then error('Invalid key data/interpolation') end
        entries[#entries+1]={frame=frame,angle=value,interpolation=mode}
    end
    table.sort(entries,function(a,b)return a.frame<b.frame end)
    for i=2,#entries do if entries[i].frame==entries[i-1].frame then error('Duplicate keys') end end
    return entries
end
local function equal(a,b,tolerance)
    if #a~=#b then return false end
    for i,v in ipairs(a) do local w=b[i];if v.frame~=w.frame or math.abs(v.angle-w.angle)>(tolerance or 0) or v.interpolation~=w.interpolation then return false end end
    return true
end
local function inspect(m,p,l,s)
    if s:CountBones()~=2 then error('Coordinated mode requires exactly two bones') end
    local result={documentPath=path(m.document:Path()),layerId=p.layerId,layerName=l:Name(),bones={}}
    local identities={tostring(m.document),tostring(l),tostring(s)}
    for id=0,1 do
        local b=s:Bone(id)
        if not safe.finite(b.fLength) or b.fLength<=0 or not safe.finite(b.fAngle) or not safe.finite(b.fPos.x) or not safe.finite(b.fPos.y) then error('Invalid setup geometry') end
        local parent=b.fParent
        if parent~=-1 and parent~=1-id then error('Invalid hierarchy') end
        if not b.fAnimAngle:HasKey(0) then error('Missing neutral key') end
        local entry={id=id,name=b:Name(),parentId=parent,length=b.fLength,setupAngle=b.fAngle,x=b.fPos.x,y=b.fPos.y,keys=channelKeys(b.fAnimAngle),neutral=b.fAnimAngle:GetValue(0)}
        result.bones[#result.bones+1]=entry
        identities[#identities+1]=tostring(b)
    end
    local a,b=result.bones[1],result.bones[2]
    if not ((a.parentId==-1 and b.parentId==0) or (b.parentId==-1 and a.parentId==1)) then error('Expected a root and its child') end
    result.identity=table.concat(identities,'|')
    return result
end
local function sameRig(a,b)
    if a.identity~=b.identity or a.documentPath~=b.documentPath or a.layerId~=b.layerId or a.layerName~=b.layerName then return false end
    for i,v in ipairs(a.bones) do
        local w=b.bones[i]
        for _,k in ipairs({'id','name','parentId','length','setupAngle','x','y','neutral'}) do if v[k]~=w[k] then return false end end
        if not equal(v.keys,w.keys) then return false end
    end
    return true
end
function tx.inspect(m,p,l,s)
    local result=inspect(m,p,l,s)
    local info=require('moho_mcp.server').getInfo()
    serial=serial+1
    last={snapshot=result,token=info.serverId..':arm:'..serial,serverId=info.serverId,expires=os.time()+300}
    return {token=last.token,expiresAt=last.expires,layerId=result.layerId,bones=result.bones,mode='two-bone-angle-transaction',units='radians'}
end
function tx.apply(m,p,l,s,plan,owner,info)
    local ok,prepared=pcall(function()
        if type(plan)~='table' or plan.version~=3 or type(owner)~='table' or type(owner.session)~='string' or plan.session~=owner.session or plan.serverId~=info.serverId or not info.running then error('Invalid session') end
        if not last or last.serverId~=info.serverId or last.token~=plan.token or last.expires<=os.time() then error('Stale rig inspection') end
        if not safe.finite(plan.expiresAt) or plan.expiresAt<=os.time() or plan.expiresAt>os.time()+1800 then error('Expired approval') end
        if path(plan.documentPath)~=path(m.document:Path()) or not sameRig(last.snapshot,inspect(m,p,l,s)) then error('Document/rig/channel changed') end
        if m.document:LayerAbsoluteID(m.layer)~=p.layerId or l:IsLocked() or l:CurrentAction()~='' or l:TotalTimingOffset()~=0 then error('Select unlocked Mainline layer with zero offset') end
        if type(plan.operations)~='table' or #plan.operations<2 or #plan.operations>16 then error('Expected 2 to 16 angle operations') end
        local anchor=plan.operations[1]
        if type(anchor)~='table' or anchor.boneId~=p.boneId or anchor.frame~=p.frame or anchor.angle~=p.angle or anchor.layerId~=p.layerId then error('Request differs from transaction anchor') end
        local channels={};local expected={}
        for id=0,1 do
            local b=s:Bone(id);local ch=b.fAnimAngle;local action=ch:CurrentAction()
            if b.fConstraints or b.fFixedAngle or b.fAngleControl==true or (type(b.fAngleControl)=='number' and b.fAngleControl>=0) or (action~=nil and action~='') then error('Controlled bone or Action unsupported') end
            if type(ch.SetValue)~='function' or type(ch.DeleteKey)~='function' or type(ch.GetKeyInterp)~='function' or type(ch.SetKeyInterp)~='function' then error('Required channel API missing') end
            channels[id]=ch;expected[id]=channelKeys(ch)
        end
        if not safe.integer(MOHO.INTERP_SMOOTH) then error('Smooth interpolation API unavailable') end
        local operations={};local seen={};local bones={}
        for _,op in ipairs(plan.operations) do
            if type(op)~='table' then error('Malformed operation') end
            for k in pairs(op) do if k~='layerId' and k~='boneId' and k~='frame' and k~='angle' and k~='replace' then error('Unsupported operation field') end end
            if op.layerId~=p.layerId or not safe.integer(op.boneId) or op.boneId>1 or not safe.integer(op.frame) or op.frame==0 or op.frame>m.document:EndFrame() or not safe.finite(op.angle) or math.abs(op.angle)>4*math.pi or type(op.replace)~='boolean' then error('Invalid operation') end
            local key=op.boneId..':'..op.frame;if seen[key] then error('Duplicate operation') end;seen[key]=true;bones[op.boneId]=true
            local ch=channels[op.boneId];local had=ch:HasKey(op.frame)
            if type(had)~='boolean' then error('Cannot establish previous key state') end
            if had and not op.replace then error('Existing key requires explicit replacement approval') end
            local old=ch:GetValue(op.frame);if not safe.finite(old) then error('Invalid previous angle') end
            local interp=nil
            if had then interp=MOHO.InterpSetting:new_local();ch:GetKeyInterp(op.frame,interp) end
            operations[#operations+1]={boneId=op.boneId,frame=op.frame,angle=op.angle,ch=ch,had=had,previous=old,interp=interp}
            local found=false
            for _,v in ipairs(expected[op.boneId]) do if v.frame==op.frame then v.angle=op.angle;v.interpolation=MOHO.INTERP_SMOOTH;found=true end end
            if not found then expected[op.boneId][#expected[op.boneId]+1]={frame=op.frame,angle=op.angle,interpolation=MOHO.INTERP_SMOOTH} end
        end
        if not bones[0] or not bones[1] then error('Transaction must target both bones') end
        for id=0,1 do table.sort(expected[id],function(a,b)return a.frame<b.frame end) end
        return {operations=operations,channels=channels,expected=expected,before=last.snapshot.bones}
    end)
    if not ok then return nil,tostring(prepared) end
    last=nil
    local undo,err=pcall(function()m.document:PrepUndo(l,true);m.document:SetDirty()end)
    if not undo then return nil,'Undo preparation failed before mutation: '..tostring(err) end
    local attempted={}
    local success,writeErr=pcall(function()
        for _,op in ipairs(prepared.operations) do
            attempted[#attempted+1]=op -- include setters that mutate then throw
            op.ch:SetValue(op.frame,op.angle)
            op.ch:SetKeyInterp(op.frame,MOHO.INTERP_SMOOTH,0.1,0.5)
        end
        for id=0,1 do if not equal(channelKeys(prepared.channels[id]),prepared.expected[id],0.000001) then error('Full channel readback failed') end end
    end)
    if not success then
        local failures={}
        -- Try every restoration, even if an earlier restoration fails.
        for i=#attempted,1,-1 do
            local op=attempted[i]
            local restored,re=pcall(function()
                if op.had then op.ch:SetValue(op.frame,op.previous);op.ch:SetKeyInterp(op.frame,op.interp)
                else op.ch:DeleteKey(op.frame) end
            end)
            if not restored then failures[#failures+1]=tostring(re) end
        end
        for id=0,1 do
            local verified,re=pcall(function()if not equal(channelKeys(prepared.channels[id]),prepared.before[id+1].keys,0.000001) then error('Rollback channel mismatch') end end)
            if not verified then failures[#failures+1]=tostring(re) end
        end
        return nil,'Transaction failed: '..tostring(writeErr)..(#failures==0 and '; all attempted keys rolled back; inspect again' or '; ROLLBACK FAILED; stop and use manual Undo: '..table.concat(failures,'; '))
    end
    local changes={}
    for _,op in ipairs(prepared.operations) do changes[#changes+1]={boneId=op.boneId,frame=op.frame,angle=op.ch:GetValue(op.frame),replaced=op.had,interpolation='smooth'} end
    return {success=true,verified=true,operation='coordinatedAngles',changes=changes,after={channelKeys(prepared.channels[0]),channelKeys(prepared.channels[1])},undo='one PrepUndo call; UI granularity requires live verification'}
end
function tx.tryApply(m,p,l,s)
    local info=require('moho_mcp.server').getInfo()
    local function read(name)
        local f=assert(io.open(info.ipcDir..name,'rb'),'Approval/owner missing');local raw=f:read(16385);f:close()
        if not raw or #raw>16384 then error('Approval/owner too large') end
        return json.decode(raw)
    end
    local ok,plan=pcall(read,'write-approval.json')
    if not ok or type(plan)~='table' or plan.version~=3 then return false end
    local ownOK,owner=pcall(read,'bridge-owner.json')
    if not ownOK then return true,nil,'Ownership unavailable' end
    local result,err=tx.apply(m,p,l,s,plan,owner,info)
    return true,result,err
end
return tx
