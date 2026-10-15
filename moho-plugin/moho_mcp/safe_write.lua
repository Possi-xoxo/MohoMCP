-- Deliberately narrow first-write gate: one approved bone-angle channel only.
local safe = {}
local blocked = {}
function safe.finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
function safe.integer(v) return safe.finite(v) and v>=0 and v%1==0 and v<=2147483647 end
function safe.validate(params)
    if type(params)~='table' then return false,'Parameters must be an object' end
    for _,k in ipairs({'layerId','boneId','frame'}) do
        if not safe.integer(params[k]) then return false,k..' must be a nonnegative integer' end
    end
    for _,k in ipairs({'angle','posX','posY','scale'}) do
        if params[k]~=nil and not safe.finite(params[k]) then return false,k..' must be finite' end
    end
    if not safe.finite(params.angle) or math.abs(params.angle)>4*math.pi then return false,'Angle must be within +/- 4 pi radians' end
    for k in pairs(params) do
        if k~='layerId' and k~='boneId' and k~='frame' and k~='angle' then
            return false,'First-write mode supports angle only; unsupported parameter: '..tostring(k)
        end
    end
    return true
end
local function normalized(p)
    if type(p)~='string' or not p:match('^%a:[/\\]') then return nil end
    return p:gsub('\\','/'):lower()
end
local function readJson(path)
    local f=io.open(path,'rb');if not f then error('Write approval or ownership file missing') end
    local raw=f:read(16385);f:close()
    if not raw or #raw>16384 then error('Write approval too large') end
    local value=json.decode(raw);if type(value)~='table' then error('Invalid write approval') end
    return value
end
-- Pure validation entry point, shared with focused regression fixtures.
function safe.checkApproval(plan, owner, info, documentPath, params, now)
    if type(plan)~='table' or plan.version~=1 or type(plan.approvalId)~='string' or #plan.approvalId<16
        or plan.session~=owner.session or plan.serverId~=info.serverId or not info.running
        or type(plan.session)~='string' or not safe.finite(plan.expiresAt)
        or plan.expiresAt<=now or plan.expiresAt>now+1800 then return false,'Write approval expired or belongs to another session' end
    if not normalized(documentPath) or normalized(plan.documentPath)~=normalized(documentPath) then return false,'Active document is not the approved disposable project' end
    if type(plan.operations)~='table' or #plan.operations~=3 then return false,'Expected exactly three approved poses' end
    local frames={0,12,24}
    local found=false
    for i,op in ipairs(plan.operations) do
        local ok=safe.validate(op)
        if not ok or op.frame~=frames[i] or op.layerId~=params.layerId or op.boneId~=params.boneId then return false,'Invalid approved pose plan' end
        if op.frame==params.frame and op.angle==params.angle then found=true end
    end
    if plan.operations[1].angle~=plan.operations[3].angle
        or math.abs(plan.operations[2].angle-plan.operations[1].angle-math.pi/6)>0.000001 then return false,'Plan must be neutral, +30 degrees, neutral' end
    if not found then return false,'Request is not an approved pose' end
    return true
end
function safe.authorize(moho,params,layer,bone)
    local info=require('moho_mcp.server').getInfo()
    local plan=readJson(info.ipcDir..'write-approval.json')
    local owner=readJson(info.ipcDir..'bridge-owner.json')
    local ok,err=safe.checkApproval(plan,owner,info,moho.document:Path(),params,os.time())
    if not ok then error(err) end
    if blocked[plan.approvalId] then error('This approval was blocked after a failed write; inspect and approve again') end
    if layer:Name()~=plan.layerName or bone:Name()~=plan.boneName then error('Approved layer/bone identity changed') end
    if moho.document:LayerAbsoluteID(moho.layer)~=params.layerId then error('Select the approved bone layer before writing') end
    local layerAction=layer:CurrentAction()
    local timingOffset=layer:TotalTimingOffset()
    local channelAction=bone.fAnimAngle:CurrentAction()
    -- Moho 14.5 returns nil for this channel on the main timeline (live verified).
    -- The layer must still explicitly report Mainline and zero timing offset.
    if layerAction~='' or timingOffset~=0 or (channelAction~=nil and channelAction~='') then
        local function describe(value) return type(value)..':'..string.format('%q',tostring(value)) end
        error('Only main timeline with zero timing offset is supported; layerAction='..describe(layerAction)
            ..'; timingOffset='..describe(timingOffset)..'; channelAction='..describe(channelAction))
    end
    if layer:IsLocked() then error('Approved layer is locked') end
    if bone.fConstraints or bone.fFixedAngle or (type(bone.fAngleControl)=='number' and bone.fAngleControl>=0) then error('Constrained or controlled bones are not supported for the first write') end
    if bone.fAnimAngle:GetValue(0)~=plan.operations[1].angle then error('Neutral pose changed since approval') end
    return plan.approvalId
end
function safe.setAngle(moho,params,layer,bone)
    local valid,err=safe.validate(params);if not valid then return nil,err end
    local ok,prepared=pcall(function()
        if params.frame>moho.document:EndFrame() then error('Frame is outside the document range') end
        local approval=safe.authorize(moho,params,layer,bone)
        local ch=bone.fAnimAngle
        if type(ch.SetValue)~='function' or type(ch.DeleteKey)~='function' then error('Required channel API unavailable') end
        local hadKey=ch:HasKey(params.frame);if type(hadKey)~='boolean' then error('Cannot establish previous key state') end
        local previous=ch:GetValue(params.frame);if not safe.finite(previous) then error('Cannot snapshot previous angle') end
        if params.frame==0 and (not hadKey or previous~=params.angle) then error('Frame 0 must retain the existing neutral setup key') end
        if hadKey and previous~=params.angle then error('Refusing to overwrite an existing key') end
        return {approval=approval,ch=ch,previous=previous,hadKey=hadKey}
    end)
    if not ok then return nil,tostring(prepared) end
    if prepared.hadKey then return {success=true,unchanged=true,frame=params.frame,angle=params.angle} end
    -- All validation and rollback snapshots precede PrepUndo/SetDirty/SetValue.
    local undoOK,undoErr=pcall(function() moho.document:PrepUndo(layer,true);moho.document:SetDirty() end)
    if not undoOK then blocked[prepared.approval]=true;return nil,'Undo preparation failed; no key written: '..tostring(undoErr) end
    local changed,changeErr=pcall(function()
        prepared.ch:SetValue(params.frame,params.angle)
        if not prepared.ch:HasKey(params.frame) or math.abs(prepared.ch:GetValue(params.frame)-params.angle)>0.000001 then error('Key readback failed') end
    end)
    if not changed then
        blocked[prepared.approval]=true
        local restored,restoreErr=pcall(function()
            prepared.ch:DeleteKey(params.frame)
            if prepared.ch:HasKey(params.frame) then error('Key remains after rollback') end
        end)
        return nil,'Write failed: '..tostring(changeErr)..(restored and '; inserted key rolled back; approval blocked' or '; ROLLBACK FAILED, use Moho Undo and inspect: '..tostring(restoreErr))
    end
    return {success=true,layerId=params.layerId,boneId=params.boneId,frame=params.frame,changed={angle=params.angle},verified=true}
end
return safe
