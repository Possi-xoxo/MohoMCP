-- One fresh inspection, one exact approved edit. No persistent object dereferences.
local edit={}
local latest=nil
local sequence=0
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function integer(v) return finite(v) and v>=0 and v%1==0 and v<=2147483647 end
local function path(v) if type(v)~='string' or not v:match('^%a:[/\\]') then error('Absolute saved document required') end return v:gsub('\\','/'):lower() end
local function keys(ch)
    local n=ch:CountKeys();if not integer(n) or n>4096 then error('Invalid/excessive key count') end
    local out={}
    for i=0,n-1 do
        local f=ch:GetKeyWhen(i);local v=ch:GetValue(f)
        if not integer(f) or not finite(v) then error('Invalid channel data') end
        out[#out+1]={frame=f,angle=v}
    end
    table.sort(out,function(a,b)return a.frame<b.frame end)
    for i=2,#out do if out[i].frame==out[i-1].frame then error('Duplicate keys') end end
    return out
end
local function equal(a,b)
    if #a~=#b then return false end
    for i,v in ipairs(a) do if v.frame~=b[i].frame or math.abs(v.angle-b[i].angle)>0.000001 then return false end end
    return true
end
local function identity(m,l,b,s)
    -- tostring identities are compared only; stale userdata is never dereferenced.
    return table.concat({path(m.document:Path()),tostring(m.document),tostring(l),tostring(b),l:Name(),b:Name(),tostring(s:CountBones()),tostring(b.fParent),tostring(b.fLength),tostring(b.fAngle),tostring(b.fPos.x),tostring(b.fPos.y)},'|')
end
function edit.inspect(m,p,l,b,s)
    local info=require('moho_mcp.server').getInfo()
    sequence=sequence+1
    local token=info.serverId..':'..sequence
    latest={token=token,identity=identity(m,l,b,s),layerId=p.layerId,boneId=p.boneId,keys=keys(b.fAnimAngle),expires=os.time()+300,serverId=info.serverId}
    return {token=token,expiresAt=latest.expires,keys=latest.keys,units='radians',mode='single-edit'}
end
local function read(file)
    local f=assert(io.open(file,'rb'),'Approval missing');local raw=f:read(16385);f:close()
    if not raw or #raw>16384 then error('Invalid approval size') end
    return json.decode(raw)
end
local function keyid(ch,frame)
    for i=0,ch:CountKeys()-1 do if ch:GetKeyWhen(i)==frame then return i end end
    error('Key not found')
end
function edit.apply(m,p,l,b,s,plan,owner,info)
    local ok,prep=pcall(function()
        local snap=latest
        if not snap or snap.expires<=os.time() or plan.token~=snap.token then error('Stale inspection; inspect again') end
        if plan.version~=2 or plan.session~=owner.session or type(owner.session)~='string' or plan.serverId~=info.serverId or snap.serverId~=info.serverId or not info.running then error('Session mismatch') end
        if not finite(plan.expiresAt) or plan.expiresAt<=os.time() or plan.expiresAt>os.time()+1800 then error('Approval expired') end
        if path(plan.documentPath)~=path(m.document:Path()) or snap.identity~=identity(m,l,b,s) or p.layerId~=snap.layerId or p.boneId~=snap.boneId then error('Document or rig changed') end
        local op=plan.operation
        if type(op)~='table' or (op.kind~='set' and op.kind~='move') or op.frame~=p.frame or op.angle~=p.angle or op.layerId~=p.layerId or op.boneId~=p.boneId then error('Request differs from approval') end
        if not integer(p.frame) or p.frame==0 or p.frame>m.document:EndFrame() or not finite(p.angle) or math.abs(p.angle)>4*math.pi then error('Invalid frame or angle') end
        if m.document:LayerAbsoluteID(m.layer)~=p.layerId or l:IsLocked() or l:CurrentAction()~='' or l:TotalTimingOffset()~=0 then error('Select unlocked Mainline layer with zero offset') end
        local ch=b.fAnimAngle;local action=ch:CurrentAction()
        if (action~=nil and action~='') or b.fConstraints or b.fFixedAngle or (type(b.fAngleControl)=='number' and b.fAngleControl>=0) then error('Unsupported controlled channel') end
        local before=keys(ch)
        if not equal(before,snap.keys) then error('Channel changed since inspection') end
        local had=ch:HasKey(p.frame);if type(had)~='boolean' then error('Invalid key presence') end
        local source=op.fromFrame
        if op.kind=='move' then
            if not integer(source) or source==0 or source==p.frame or source>m.document:EndFrame() or had or not ch:HasKey(source) or ch:GetValue(source)~=p.angle then error('Invalid source or occupied destination') end
            if type(ch.SetKeyWhen)~='function' then error('Native key movement unavailable') end
        end
        local interp=nil
        if op.kind=='set' and had then
            interp=MOHO.InterpSetting:new_local();ch:GetKeyInterp(p.frame,interp)
            if type(ch.SetKeyInterp)~='function' then error('Interpolation restore unavailable') end
        end
        local expected={};for _,v in ipairs(before) do expected[#expected+1]={frame=v.frame,angle=v.angle} end
        if op.kind=='move' then for _,v in ipairs(expected) do if v.frame==source then v.frame=p.frame end end
        elseif had then for _,v in ipairs(expected) do if v.frame==p.frame then v.angle=p.angle end end
        else expected[#expected+1]={frame=p.frame,angle=p.angle} end
        table.sort(expected,function(a,b)return a.frame<b.frame end)
        return {ch=ch,before=before,expected=expected,had=had,previous=ch:GetValue(p.frame),interp=interp,kind=op.kind,source=source}
    end)
    if not ok then return nil,tostring(prep) end
    latest=nil -- consumed even if undo preparation or mutation fails
    if equal(prep.before,prep.expected) then return {success=true,unchanged=true,keys=prep.before} end
    local undo,err=pcall(function()m.document:PrepUndo(l,true);m.document:SetDirty()end)
    if not undo then return nil,'Undo preparation failed: '..tostring(err) end
    local changed,changeErr=pcall(function()
        if prep.kind=='move' then prep.ch:SetKeyWhen(keyid(prep.ch,prep.source),p.frame)
        else prep.ch:SetValue(p.frame,p.angle);if prep.interp then prep.ch:SetKeyInterp(p.frame,prep.interp) end end
        if not equal(keys(prep.ch),prep.expected) then error('Full channel readback mismatch') end
    end)
    if not changed then
        local restored,restoreErr=pcall(function()
            if prep.kind=='move' then
                if not prep.ch:HasKey(prep.source) then prep.ch:SetKeyWhen(keyid(prep.ch,p.frame),prep.source) end
            elseif prep.had then prep.ch:SetValue(p.frame,prep.previous);prep.ch:SetKeyInterp(p.frame,prep.interp)
            else prep.ch:DeleteKey(p.frame) end
            if not equal(keys(prep.ch),prep.before) then error('Rollback readback mismatch') end
        end)
        return nil,'Edit failed: '..tostring(changeErr)..(restored and '; rolled back; inspect again' or '; ROLLBACK FAILED, use Undo: '..tostring(restoreErr))
    end
    return {success=true,verified=true,operation=prep.kind,frame=p.frame,fromFrame=prep.source,angle=prep.ch:GetValue(p.frame),before=prep.before,after=keys(prep.ch)}
end
function edit.tryApply(m,p,l,b,s)
    local info=require('moho_mcp.server').getInfo()
    local ok,plan=pcall(read,info.ipcDir..'write-approval.json')
    if not ok then return false end
    if type(plan)~='table' or plan.version~=2 then return false end
    local ownerOK,owner=pcall(read,info.ipcDir..'bridge-owner.json')
    if not ownerOK then return true,nil,'Ownership unavailable' end
    local result,err=edit.apply(m,p,l,b,s,plan,owner,info)
    return true,result,err
end
return edit
