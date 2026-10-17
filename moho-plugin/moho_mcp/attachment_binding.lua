-- Narrow rigid attachment: inspect by names, approve exact snapshot, consume once.
local A={}
local safe=require('moho_mcp.safe_write')
local rig=require('moho_mcp.coordinated_write')
local latest=nil
local serial=0
local function eq(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~='table' then return a==b end
 for k,v in pairs(a) do if not eq(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
local function fields(t,allowed)
 if type(t)~='table' then error('Object required') end
 for k in pairs(t) do if not allowed[k] then error('Unexpected field: '..tostring(k)) end end
end
local function path(p)
 if type(p)~='string' or not p:match('^%a:[/\\]') then error('Saved absolute document required') end
 return p:gsub('\\','/'):lower()
end
local function channel(ch,vector)
 local n=ch:CountKeys();if not safe.integer(n) or n>4096 then error('Invalid channel size') end
 local out={}
 for i=0,n-1 do
  local f=ch:GetKeyWhen(i);local v=ch:GetValue(f)
  if not safe.integer(f) then error('Unsupported channel frame') end
  if vector then
   v={x=v.x,y=v.y,z=v.z}
   for _,x in pairs(v) do if not safe.finite(x) then error('Invalid vector') end end
  elseif not safe.finite(v) then error('Invalid scalar') end
  out[#out+1]={frame=f,value=v}
 end
 return out
end
local function snapshot(m,p)
 fields(p,{rigLayerName=true,mappings=true})
 if type(p.rigLayerName)~='string' or p.rigLayerName=='' or type(p.mappings)~='table' or #p.mappings<1 or #p.mappings>3 then error('Require named rig and 1 to 3 mappings') end
 if m.frame~=0 then error('Inspect and bind at frame 0 only; frame must be available and geometry is not changed') end
 local found={};local all={};local seen={}
 local function walk(container)
  local n=container:CountLayers();if not safe.integer(n) or n>256 then error('Layer count unsupported') end
  for i=0,n-1 do
   local l=container:Layer(i);local key=tostring(l)
   if seen[key] or #all>=256 then error('Repeated/excessive layer hierarchy') end
   seen[key]=true;all[#all+1]=l
   if l:Name()==p.rigLayerName then found[#found+1]=l end
   if l:IsGroupType() then walk(m:LayerAsGroup(l)) end
  end
 end
 walk(m.document)
 if #found~=1 or not found[1]:IsBoneType() then error('Missing or ambiguous bone layer') end
 local l=found[1];local s=m:LayerAsBone(l):Skeleton();local id=m.document:LayerAbsoluteID(l)
 if l:IsLocked() or l:CurrentAction()~='' or l:TotalTimingOffset()~=0 then error('Rig must be unlocked Mainline with zero timing offset') end
 local rs=rig.bindingSnapshot(m,{layerId=id},l,s)
 local boneNames={}
 for _,b in ipairs(rs.bones) do if not b.controllersVerified then error('Unsupported bone controller') end;boneNames[b.name]=b.id end
 local entries={};local objects={}
 for _,c in ipairs(all) do
  local cid=m.document:LayerAbsoluteID(c)
  if not safe.integer(cid) then error('Invalid layer ID') end
  objects[cid]=c
  entries[#entries+1]={id=cid,identity=tostring(c),name=c:Name(),parent=tostring(c:Parent()),binding=c:LayerParentBone(),
   visible=c:IsVisible(),locked=c:IsLocked(),translation=channel(c.fTranslation,true),scale=channel(c.fScale,true),rotation=channel(c.fRotationZ,false)}
 end
 local ops={};local used={}
 for _,map in ipairs(p.mappings) do
  fields(map,{layerName=true,boneName=true,expectedBinding=true})
  if type(map.layerName)~='string' or type(map.boneName)~='string' or not safe.integer(map.expectedBinding+1) then error('Invalid semantic mapping or previous binding') end
  local matches={}
  for _,c in ipairs(all) do if c:Name()==map.layerName and c:Parent()==l then matches[#matches+1]=c end end
  if #matches~=1 then error('Missing/ambiguous direct-child artwork: '..map.layerName) end
  local c=matches[1];local cid=m.document:LayerAbsoluteID(c);local bid=boneNames[map.boneName]
  if bid==nil or used[cid] then error('Missing bone or repeated artwork') end;used[cid]=true
  local typ=c:LayerType()
  if typ~=MOHO.LT_VECTOR and typ~=MOHO.LT_GROUP then error('Only vector or ordinary group artwork supported') end
  if c:IsLocked() or c:CurrentAction()~='' or c:TotalTimingOffset()~=0 or c:ControllingBoneLayer()~=l or c:ControllingSkeleton()~=s then error('Artwork ownership/action invalid') end
  if type(c.SetLayerParentBone)~='function' or c:LayerParentBone()~=map.expectedBinding then error('Existing binding conflict or missing setter') end
  if map.expectedBinding>=s:CountBones() then error('Invalid prior bone') end
  ops[#ops+1]={layerId=cid,layerName=map.layerName,boneId=bid,boneName=map.boneName,previous=map.expectedBinding}
 end
 return {document=path(m.document:Path()),rig=rs,layers=entries,operations=ops},objects
end
function A.inspect(m,p)
 local ok,snap=pcall(snapshot,m,p);if not ok then return nil,tostring(snap) end
 local info=require('moho_mcp.server').getInfo();serial=serial+1
 latest={snapshot=snap,params=p,token=info.serverId..':binding:'..serial,expiresAt=os.time()+300,serverId=info.serverId}
 return {token=latest.token,expiresAt=latest.expiresAt,documentPath=snap.document,rigLayerId=snap.rig.layerId,operations=snap.operations,mode='rigid-layer-binding',maxMappings=3}
end
function A.applyApproved(m,p,plan,owner,info)
 local ok,prepared=pcall(function()
  fields(p,{token=true})
  if not latest or p.token~=latest.token or latest.expiresAt<=os.time() then error('Stale attachment inspection') end
  if type(plan)~='table' or plan.version~=1 or plan.kind~='rigid-binding' or plan.token~=p.token or plan.session~=owner.session or type(owner.session)~='string' or plan.serverId~=info.serverId or info.serverId~=latest.serverId or not info.running then error('Approval/session mismatch') end
  if not safe.finite(plan.expiresAt) or plan.expiresAt<=os.time() or plan.expiresAt>latest.expiresAt or path(plan.documentPath)~=latest.snapshot.document or not eq(plan.operations,latest.snapshot.operations) then error('Approval differs from inspected mappings') end
  local now,objects=snapshot(m,latest.params)
  if not eq(now,latest.snapshot) then error('Document, hierarchy, transforms or channels changed') end
  return {before=now,objects=objects,params=latest.params}
 end)
 if not ok then return nil,tostring(prepared) end
 latest=nil
 local changed={}
 for _,op in ipairs(prepared.before.operations) do if op.previous~=op.boneId then changed[#changed+1]=op end end
 if #changed==0 then return {success=true,unchanged=true} end
 local undo,err=pcall(function()m.document:PrepMultiUndo(true);m.document:SetDirty()end)
 if not undo then return nil,'Undo preparation failed: '..tostring(err) end
 local attempted={}
 local expected=prepared.before
 -- Only binding fields may differ; snapshot parameters track approved new values.
 local newParams={rigLayerName=prepared.params.rigLayerName,mappings={}}
 for _,op in ipairs(expected.operations) do newParams.mappings[#newParams.mappings+1]={layerName=op.layerName,boneName=op.boneName,expectedBinding=op.boneId} end
 local function verify(after,bindings)
  if not eq(expected.rig,after.rig) or expected.document~=after.document or #expected.layers~=#after.layers then error('Rig or hierarchy changed') end
  for i,e in ipairs(expected.layers) do
   local a=after.layers[i];local want=bindings[e.id] or e.binding
   if a.binding~=want then error('Binding readback mismatch') end
   local old=a.binding;a.binding=e.binding;local same=eq(e,a);a.binding=old
   if not same then error('Layer metadata/transforms changed') end
  end
 end
 local success,writeErr=pcall(function()
  local bindings={}
  for _,op in ipairs(changed) do attempted[#attempted+1]=op;prepared.objects[op.layerId]:SetLayerParentBone(op.boneId);bindings[op.layerId]=op.boneId end
  verify(snapshot(m,newParams),bindings)
 end)
 if not success then
  local failures={}
  for i=#attempted,1,-1 do local op=attempted[i];local restored,re=pcall(function()prepared.objects[op.layerId]:SetLayerParentBone(op.previous)end);if not restored then failures[#failures+1]=tostring(re) end end
  local restored,re=pcall(function()verify(snapshot(m,prepared.params),{})end);if not restored then failures[#failures+1]=tostring(re) end
  return nil,'Binding failed: '..tostring(writeErr)..(#failures==0 and '; bindings rolled back; inspect again' or '; ROLLBACK FAILED; stop and inspect/manual Undo: '..table.concat(failures,'; '))
 end
 return {success=true,verified=true,changes=changed,undo='One PrepMultiUndo call; live UI Undo requires verification'}
end
function A.apply(m,p)
 local info=require('moho_mcp.server').getInfo()
 local function read(name)
  local f=assert(io.open(info.ipcDir..name,'rb'),'Approval/owner missing');local raw=f:read(16385);f:close()
  if not raw or #raw>16384 then error('Oversized approval/owner') end
  return json.decode(raw)
 end
 local ok,plan,owner=pcall(function()return read('binding-approval.json'),read('bridge-owner.json')end)
 if not ok then return nil,tostring(plan) end
 return A.applyApproved(m,p,plan,owner,info)
end
return A
