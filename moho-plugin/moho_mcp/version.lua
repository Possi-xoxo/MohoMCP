local V={release='0.9.2',lua='0.9.2',bridge='0.9.2',ipc=2,supportedMoho='14.5'}
local reads={['ipc.ping']=true,['document.getInfo']=true,['document.getLayers']=true,['layer.getProperties']=true,['layer.getChildren']=true,['layer.getBones']=true,['bone.getProperties']=true,['animation.getKeyframes']=true,['animation.getFrameState']=true,['mesh.getPoints']=true,['mesh.getShapes']=true,['attachment.inspect']=true}
function V.compatible(method,version) return reads[method]==true or version==V.release end
return V
