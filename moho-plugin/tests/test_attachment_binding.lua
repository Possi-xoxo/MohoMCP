local A=require('moho_mcp.attachment_binding')
local R=require('moho_mcp.coordinated_write')
local function fixture(fn)
 local oldSnap=R.bindingSnapshot;local server=require('moho_mcp.server');local oldInfo=server.getInfo;local oldM=MOHO
 MOHO={LT_VECTOR=1,LT_GROUP=2};local info={serverId='test',running=true};server.getInfo=function()return info end
 local bones={{id=0,name='Torso',controllersVerified=true},{id=1,name='Arm_Right',controllersVerified=true},{id=2,name='Arm_Left',controllersVerified=true}}
 local skeleton={CountBones=function()return #bones end}
 local function ch(v)return {CountKeys=function()return 1 end,GetKeyWhen=function()return 0 end,GetValue=function()return v end}end
 local function layer(name,id)
  return {name=name,id=id,binding=-1,Name=function(s)return s.name end,Parent=function(s)return s.parent end,IsGroupType=function(s)return s.children~=nil end,
   LayerType=function(s)return s.children and 2 or 1 end,IsBoneType=function(s)return s.isBone==true end,IsLocked=function()return false end,IsVisible=function()return true end,
   CurrentAction=function()return '' end,TotalTimingOffset=function()return 0 end,LayerParentBone=function(s)return s.binding end,
   SetLayerParentBone=function(s,v)s.binding=v end,ControllingBoneLayer=function(s)return s.parent end,ControllingSkeleton=function()return skeleton end,
   CountLayers=function(s)return #s.children end,Layer=function(s,i)return s.children[i+1] end,Skeleton=function()return skeleton end,
   fTranslation=ch({x=0,y=0,z=0}),fScale=ch({x=1,y=1,z=1}),fRotationZ=ch(0)}
 end
 local l=layer('Character Rig',0);l.isBone=true;l.children={}
 local art={layer('Sweater',1),layer('Right Arm',2),layer('Left Arm',3)};art[1].children={}
 for _,c in ipairs(art)do c.parent=l;l.children[#l.children+1]=c end
 local undo=0;local doc={children={l},Path=function()return 'E:/disposable.moho' end,CurrentFrame=function()return 0 end,
  CountLayers=function(s)return #s.children end,Layer=function(s,i)return s.children[i+1]end,LayerAbsoluteID=function(_,c)return c.id end,
  PrepMultiUndo=function()undo=undo+1 end,SetDirty=function()end}
 local m={frame=0,document=doc,LayerAsGroup=function(_,c)return c end,LayerAsBone=function(_,c)return c end}
 R.bindingSnapshot=function()local out={};for i,b in ipairs(bones)do out[i]={id=b.id,name=b.name,controllersVerified=b.controllersVerified}end;return {identity=tostring(m.document),bones=out,layerId=0}end
 local p={rigLayerName='Character Rig',mappings={{layerName='Sweater',boneName='Torso',expectedBinding=-1},{layerName='Right Arm',boneName='Arm_Right',expectedBinding=-1},{layerName='Left Arm',boneName='Arm_Left',expectedBinding=-1}}}
 local f={m=m,art=art,l=l,bones=bones,p=p,info=info,undo=function()return undo end}
 function f.refresh()local r,e=A.inspect(m,p);assert(r,e);f.token=r.token;f.plan={version=1,kind='rigid-binding',token=r.token,session='session',serverId='test',expiresAt=r.expiresAt,documentPath=r.documentPath,operations=r.operations}end
 function f.apply()return A.applyApproved(m,{token=f.token},f.plan,{session='session'},info)end
 f.refresh();local ok,e=pcall(fn,f);R.bindingSnapshot=oldSnap;server.getInfo=oldInfo;MOHO=oldM;if not ok then error(e)end
end
local function case(n,fn)test(n,function()fixture(fn)end)end
case('three bindings one undo and consumed token',function(f)local r=f.apply();assert_true(r.verified);assert_eq(f.undo(),1);for i,a in ipairs(f.art)do assert_eq(a.binding,i-1)end;assert_eq(f.apply(),nil)end)
case('missing artwork rejected before mutation',function(f)f.art[2].name='Other';assert_eq(f.apply(),nil);assert_eq(f.undo(),0)end)
case('missing bone rejected',function(f)f.bones[2].name='Other';assert_eq(f.apply(),nil);assert_eq(f.undo(),0)end)
case('duplicate direct child rejected',function(f)f.art[3].name='Right Arm';assert_eq(f.apply(),nil);assert_eq(f.undo(),0)end)
case('existing binding conflict rejected',function(f)f.art[1].binding=2;assert_eq(f.apply(),nil);assert_eq(f.undo(),0)end)
case('changed native document rejected',function(f)local d={};for k,v in pairs(f.m.document)do d[k]=v end;f.m.document=d;assert_eq(f.apply(),nil)end)
case('changed path rejected',function(f)f.m.document.Path=function()return 'E:/original.moho'end;assert_eq(f.apply(),nil)end)
case('wrong parent rejected',function(f)f.art[2].parent={};assert_eq(f.apply(),nil);assert_eq(f.undo(),0)end)
case('unsupported controller rejected',function(f)f.bones[3].controllersVerified=false;assert_eq(f.apply(),nil)end)
case('changed transform rejected',function(f)f.art[2].fRotationZ.GetValue=function()return 1 end;assert_eq(f.apply(),nil);assert_eq(f.undo(),0)end)
case('wrong approval session rejected',function(f)f.plan.session='other';assert_eq(f.apply(),nil)end)
case('expired approval rejected',function(f)f.plan.expiresAt=1;assert_eq(f.apply(),nil)end)
case('altered mapping approval rejected',function(f)f.plan.operations={{layerId=1,boneId=2}};assert_eq(f.apply(),nil)end)
case('nonzero frame rejected',function(f)f.m.frame=1;assert_eq(f.apply(),nil)end)
case('missing script frame fails closed',function(f)f.m.frame=nil;assert_eq(f.apply(),nil);assert_eq(f.undo(),0)end)
case('document CurrentFrame is not required by Moho 14.5',function(f)f.m.document.CurrentFrame=nil;assert_true(f.apply().success)end)
case('setter mutates then throws and all bindings roll back',function(f)
 f.art[2].SetLayerParentBone=function(s,v)s.binding=v;if v==1 then error('fixture')end end
 local r,e=f.apply();assert_eq(r,nil);assert_true(e:find('bindings rolled back')~=nil);for _,a in ipairs(f.art)do assert_eq(a.binding,-1)end;assert_eq(f.undo(),1)
end)
case('silent readback mismatch rolls back',function(f)f.art[2].SetLayerParentBone=function()end;local r,e=f.apply();assert_eq(r,nil);assert_true(e:find('rolled back')~=nil);assert_eq(f.art[1].binding,-1)end)
case('rollback failure explicitly reported',function(f)
 f.art[2].SetLayerParentBone=function(s,v)if v==-1 then error('cannot restore')end;s.binding=v;error('after mutation')end
 local r,e=f.apply();assert_eq(r,nil);assert_true(e:find('ROLLBACK FAILED')~=nil)
end)
case('undo preparation failure makes no writes',function(f)f.m.document.PrepMultiUndo=function()error('fixture')end;assert_eq(f.apply(),nil);assert_eq(f.art[1].binding,-1)end)
case('one mapping correction preserves other attachments',function(f)
 assert_true(f.apply().success);f.p.mappings={{layerName='Right Arm',boneName='Arm_Left',expectedBinding=1}};f.refresh();assert_true(f.apply().success);assert_eq(f.art[1].binding,0);assert_eq(f.art[2].binding,2);assert_eq(f.art[3].binding,2)
end)
case('unchanged mapping creates no additional undo',function(f)
 assert_true(f.apply().success);f.p.mappings={{layerName='Sweater',boneName='Torso',expectedBinding=0}};f.refresh();assert_true(f.apply().unchanged);assert_eq(f.undo(),1)
end)
