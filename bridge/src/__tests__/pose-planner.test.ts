import {describe,it,expect} from 'vitest';
import {capturePose,compilePose,compileCycle,verifyReadback,poseSchema} from '../pose-planner.js';
function fixture(count=10){
 const doc={filePath:'E:/test.moho',fps:24,startFrame:1,endFrame:48};
 const rig={token:'epoch:arm:1',expiresAt:1000,layerId:1,bones:Array.from({length:count},(_,id)=>({id,name:'B'+id,parentId:id===0?-1:Math.floor((id-1)/2),length:1,neutral:0,setupAngle:0,x:id,y:0,controllersVerified:true as const,keys:[{frame:0,angle:0,interpolation:1}]}))};
 const roles=Object.fromEntries(rig.bones.map(b=>['role'+b.id,b.name]));
 const pose=capturePose(doc,rig,roles,'Relaxed',1,{role2:-60,role4:60},100);
 const cycle={name:'Breathing',startFrame:1,endFrame:48,tracks:rig.bones.map(b=>({role:'role'+b.id,amplitudeDegrees:b.id===0?.4:.2,delayFrames:b.id%3}))};
 return {doc,rig,roles,pose,cycle};
}
describe('offline pose planner',()=>{
 it.each([20,32])('supports complete bindings with selective poses on %i bones',count=>{const f=fixture(count);f.pose.rotations=f.pose.rotations.filter(r=>['role6','role9'].includes(r.role));const p=compilePose(f.pose,f.doc,f.rig,100);expect(p.operations.map(o=>o.boneId)).toEqual([6,9]);expect(f.pose.bindings).toHaveLength(count);});
 it('rejects 33 bones',()=>{expect(()=>fixture(33)).toThrow();});
 it('keeps the 72-operation cap independent of rig count',()=>{const f=fixture(32);expect(()=>compileCycle(f.pose,f.cycle,f.doc,f.rig,100)).toThrow('72');f.cycle.tracks=f.cycle.tracks.slice(0,12);expect(compileCycle(f.pose,f.cycle,f.doc,f.rig,100).operations).toHaveLength(60);});
 it('detects untargeted stale geometry and controllers',()=>{const f=fixture(32);f.pose.rotations=f.pose.rotations.slice(0,2);f.rig.bones[31].length=2;expect(()=>compilePose(f.pose,f.doc,f.rig,100)).toThrow('geometry');f.rig.bones[31].length=1;(f.rig.bones[31] as any).controllersVerified=false;expect(()=>compilePose(f.pose,f.doc,f.rig,100)).toThrow();});
 it('full-rig readback rejects a changed unselected channel',()=>{const f=fixture(32);f.pose.rotations=f.pose.rotations.slice(0,2);const p=compilePose(f.pose,f.doc,f.rig,100),a=structuredClone(f.rig);for(const o of p.operations)a.bones[o.boneId].keys.push({frame:o.frame,angle:o.angle,interpolation:1});expect(()=>verifyReadback(p,f.rig,a)).not.toThrow();a.bones[31].keys[0].angle=.1;expect(()=>verifyReadback(p,f.rig,a)).toThrow('Unrelated');});
 it('round trips portable JSON without storing numeric bone IDs',()=>{const f=fixture();expect(poseSchema.parse(JSON.parse(JSON.stringify(f.pose)))).toEqual(f.pose);expect(f.pose.bindings[0]).not.toHaveProperty('id');});
 it('compiles a complete pose without mutating inputs or frame zero',()=>{const f=fixture(),s=JSON.stringify(f);const p=compilePose(f.pose,f.doc,f.rig,100);expect(p.operations).toHaveLength(10);expect(p.operations.every(o=>o.frame===1&&!o.replace)).toBe(true);expect(JSON.stringify(f)).toBe(s);});
 it('resolves reordered numeric IDs by fresh names and parents',()=>{const f=fixture();f.rig.bones.forEach(b=>{b.id=9-b.id;b.parentId=b.parentId===-1?-1:9-b.parentId;});const p=compilePose(f.pose,f.doc,f.rig,100);expect(p.operations[0].boneId).toBe(9);});
 it('rejects duplicate names',()=>{const f=fixture();f.rig.bones[2].name='B1';expect(()=>compilePose(f.pose,f.doc,f.rig,100)).toThrow('Ambiguous');});
 it('rejects changed hierarchy',()=>{const f=fixture();f.rig.bones[3].parentId=0;expect(()=>compilePose(f.pose,f.doc,f.rig,100)).toThrow('parent');});
 it('rejects cycles before planning',()=>{const f=fixture();f.rig.bones[1].parentId=3;expect(()=>compilePose(f.pose,f.doc,f.rig,100)).toThrow('hierarchy');});
 it.each(['length','neutral','setupAngle','x','y'] as const)('rejects changed %s',field=>{const f=fixture();f.rig.bones[2][field]+=.1;expect(()=>compilePose(f.pose,f.doc,f.rig,100)).toThrow();});
 it('rejects wrong document',()=>{const f=fixture();f.doc.filePath='E:/production.moho';expect(()=>compilePose(f.pose,f.doc,f.rig,100)).toThrow('document');});
 it('rejects expired inspection',()=>{const f=fixture();expect(()=>compilePose(f.pose,f.doc,f.rig,1001)).toThrow('Expired');});
 it('rejects unsupported translations',()=>{const f=fixture();expect(()=>compilePose({...f.pose,translation:{x:1}},f.doc,f.rig,100)).toThrow();});
 it('rejects invalid frames and nonfinite angles',()=>{const f=fixture();expect(()=>compilePose({...f.pose,frame:0},f.doc,f.rig,100)).toThrow();f.pose.rotations[0].offsetDegrees=NaN;expect(()=>compilePose(f.pose,f.doc,f.rig,100)).toThrow();});
 it('rejects corrupt binding fingerprint',()=>{const f=fixture();f.pose.bindings[0].name='Other';expect(()=>compilePose(f.pose,f.doc,f.rig,100)).toThrow('fingerprint');});
 it('rejects unsupported controllers',()=>{const f=fixture();(f.rig.bones[9] as any).controllersVerified=false;expect(()=>compilePose(f.pose,f.doc,f.rig,100)).toThrow();});
 it('creates independent delayed tracks with matching endpoints',()=>{const f=fixture(),p=compileCycle(f.pose,f.cycle,f.doc,f.rig,100);expect(p.operations).toHaveLength(50);for(let id=0;id<10;id++){const o=p.operations.filter(o=>o.boneId===id);expect(o[0].angle).toBe(o[4].angle);}expect(p.operations[1].frame).not.toBe(p.operations[6].frame);});
 it('leaves the existing baseline keys and their curves untouched',()=>{const f=fixture();for(const o of compilePose(f.pose,f.doc,f.rig,100).operations)f.rig.bones[o.boneId].keys.push({frame:o.frame,angle:o.angle,interpolation:3});expect(compileCycle(f.pose,f.cycle,f.doc,f.rig,100).operations).toHaveLength(40);});
 it('fails closed on replacement even for smooth curves',()=>{const f=fixture();f.rig.bones[0].keys.push({frame:1,angle:.5,interpolation:1});expect(()=>compilePose(f.pose,f.doc,f.rig,100)).toThrow('full curve');});
 it('allows amplitude refinement after verified undo without a new pose',()=>{const f=fixture(),first=compileCycle(f.pose,f.cycle,f.doc,f.rig,100);f.cycle.tracks.forEach(t=>t.amplitudeDegrees*=.5);const revised=compileCycle(f.pose,f.cycle,f.doc,f.rig,100);expect(revised.operations[1].angle).toBeCloseTo(first.operations[1].angle*.5);});
 it('rejects delay overlap and unknown tracks',()=>{const f=fixture();f.cycle.endFrame=8;expect(()=>compileCycle(f.pose,f.cycle,f.doc,f.rig,100)).toThrow();f.cycle.endFrame=48;f.cycle.tracks[0].role='absent';expect(()=>compileCycle(f.pose,f.cycle,f.doc,f.rig,100)).toThrow();});
 it('supports slower cycles only inside explicitly configured playback range',()=>{const f=fixture();f.cycle.endFrame=96;expect(()=>compileCycle(f.pose,f.cycle,f.doc,f.rig,100)).toThrow();f.doc.endFrame=96;expect(compileCycle(f.pose,f.cycle,f.doc,f.rig,100).endFrame).toBe(96);});
 it('verifies every new and preserved key and catches corruption',()=>{const f=fixture(),p=compilePose(f.pose,f.doc,f.rig,100),after=structuredClone(f.rig);for(const o of p.operations)after.bones[o.boneId].keys.push({frame:o.frame,angle:o.angle,interpolation:1});expect(()=>verifyReadback(p,f.rig,after)).not.toThrow();after.bones[9].keys[0].angle=.1;expect(()=>verifyReadback(p,f.rig,after)).toThrow('Unrelated');});
});
