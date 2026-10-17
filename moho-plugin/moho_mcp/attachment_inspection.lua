-- Read-only binding metadata. Unknown states never masquerade as unbound.
local inspection={}
function inspection.read(m,layer)
    local ok,result=pcall(function()
        local id=layer:LayerParentBone()
        if type(id)~='number' or id~=id or id%1~=0 or id < -3 then error('Invalid binding value') end
        local parent=layer:Parent()
        local controller=layer:ControllingBoneLayer()
        local function absolute(l)
            if not l then return -1 end
            local n=m.document:LayerAbsoluteID(l)
            if type(n)~='number' or n<0 or n%1~=0 then error('Invalid layer identity') end
            return n
        end
        local out={available=true,parentLayerId=absolute(parent),controllingBoneLayerId=absolute(controller),rawParentBone=id}
        if id>=0 then
            local skel=layer:ControllingSkeleton()
            if not skel or id>=skel:CountBones() then error('Binding references missing bone') end
            local bone=skel:Bone(id)
            if not bone then error('Missing bound bone') end
            out.boundBoneName=bone:Name()
            out.mode='rigid'
        elseif id==-1 then out.mode='no-explicit-layer-bone'
        else out.mode='special-binding-state' end
        return out
    end)
    if not ok then return {available=false,error=tostring(result)} end
    return result
end
return inspection
