/** Offline planning only. No IPC, file writes, UI activity, or implicit approval. */
import { createHash } from 'node:crypto';
import { z } from 'zod';

const finite = z.number().finite();
const frame = z.number().int().min(1).max(1000000);
const keySchema = z.object({frame:z.number().int().nonnegative(),angle:finite,interpolation:z.number().int()});
const boneSchema = z.object({id:z.number().int().nonnegative(),name:z.string().min(1),parentId:z.number().int().min(-1),length:finite.positive(),neutral:finite,setupAngle:finite,x:finite,y:finite,controllersVerified:z.literal(true),keys:z.array(keySchema).min(1).max(4096)});
const inspectionSchema = z.object({token:z.string().min(1),expiresAt:finite,layerId:z.number().int().nonnegative(),bones:z.array(boneSchema).min(2).max(32)});
const documentSchema = z.object({filePath:z.string().regex(/^[a-z]:[\\/]/i),fps:finite.positive(),startFrame:frame,endFrame:frame});
const bindingSchema = z.object({role:z.string().min(1),name:z.string().min(1),parent:z.string().nullable(),length:finite.positive(),neutral:finite,setupAngle:finite,x:finite,y:finite}).strict();
export const poseSchema = z.object({
  version:z.literal(1),name:z.string().min(1).max(100),frame,
  documentPath:z.string().regex(/^[a-z]:[\\/]/i),layerId:z.number().int().nonnegative(),
  rigFingerprint:z.string().regex(/^[a-f0-9]{64}$/),
  bindings:z.array(bindingSchema).min(2).max(32),
  rotations:z.array(z.object({role:z.string().min(1),offsetDegrees:finite.min(-90).max(90)}).strict()).min(2).max(32),
  units:z.literal('degrees-relative-to-neutral'),
}).strict();
export type Pose = z.infer<typeof poseSchema>;
export type Inspection = z.infer<typeof inspectionSchema>;
export type DocumentInfo = z.infer<typeof documentSchema>;
export type Operation = {layerId:number;boneId:number;frame:number;angle:number;replace:false};
export type Plan = {version:4;documentPath:string;token:string;expiresAt:number;fps:number;startFrame:number;endFrame:number;operations:Operation[]};
const canonicalPath = (s:string) => s.replaceAll('\\','/').toLowerCase();
const signature = (bindings:Pose['bindings']) => createHash('sha256').update(JSON.stringify([...bindings].sort((a,b)=>a.role.localeCompare(b.role)))).digest('hex');

function inspect(raw:unknown, now:number):Inspection {
  const r=inspectionSchema.parse(raw);
  if(r.expiresAt<=now) throw Error('Expired inspection; inspect the live rig again');
  const ids=new Map(r.bones.map(b=>[b.id,b]));
  if(ids.size!==r.bones.length || new Set(r.bones.map(b=>b.name)).size!==r.bones.length) throw Error('Ambiguous bone IDs or names');
  if(r.bones.filter(b=>b.parentId===-1).length!==1) throw Error('Expected one connected root');
  for(const b of r.bones){
    const seen=new Set<number>(); let id=b.id;
    while(id!==-1){if(seen.has(id)||!ids.has(id))throw Error('Invalid parent hierarchy');seen.add(id);id=ids.get(id)!.parentId;}
    if(new Set(b.keys.map(k=>k.frame)).size!==b.keys.length)throw Error('Duplicate channel keys');
    if(!b.keys.some(k=>k.frame===0&&k.angle===b.neutral))throw Error('Neutral setup key mismatch');
  }
  return r;
}

export function capturePose(docRaw:unknown,rigRaw:unknown,roles:Record<string,string>,name:string,atFrame:number,offsets:Record<string,number>,now:number):Pose {
  const doc=documentSchema.parse(docRaw),rig=inspect(rigRaw,now);
  const entries=Object.entries(roles);
  if(entries.length!==rig.bones.length||new Set(entries.map(([,n])=>n)).size!==entries.length)throw Error('Map each bone to one unique semantic role');
  const bindings=entries.map(([role,name])=>{
    const b=rig.bones.find(b=>b.name===name);if(!b)throw Error('Missing named bone: '+name);
    const parent=b.parentId===-1?null:rig.bones.find(p=>p.id===b.parentId)!.name;
    return {role,name,parent,length:b.length,neutral:b.neutral,setupAngle:b.setupAngle,x:b.x,y:b.y};
  });
  const pose=poseSchema.parse({version:1,name,frame:atFrame,documentPath:doc.filePath,layerId:rig.layerId,rigFingerprint:signature(bindings),bindings,rotations:entries.map(([role])=>({role,offsetDegrees:offsets[role]??0})),units:'degrees-relative-to-neutral'});
  for(const role of Object.keys(offsets))if(!roles[role])throw Error('Unknown offset role');
  resolve(pose,doc,rig,now);
  return pose;
}

function resolve(raw:unknown,docRaw:unknown,rigRaw:unknown,now:number){
  const pose=poseSchema.parse(raw),doc=documentSchema.parse(docRaw),rig=inspect(rigRaw,now);
  if(canonicalPath(pose.documentPath)!==canonicalPath(doc.filePath)||pose.layerId!==rig.layerId)throw Error('Wrong document or layer');
  if(doc.endFrame<doc.startFrame||pose.frame<doc.startFrame||pose.frame>doc.endFrame)throw Error('Pose outside playback range');
  if(signature(pose.bindings)!==pose.rigFingerprint)throw Error('Pose binding fingerprint mismatch');
  if(pose.bindings.length!==rig.bones.length||new Set(pose.bindings.map(b=>b.role)).size!==pose.bindings.length||new Set(pose.bindings.map(b=>b.name)).size!==pose.bindings.length)throw Error('Ambiguous pose mapping');
  const mapped=new Map<string,Inspection['bones'][number]>();
  for(const b of pose.bindings){
    const live=rig.bones.find(x=>x.name===b.name);if(!live)throw Error('Missing bone '+b.name);
    const parent=live.parentId===-1?null:rig.bones.find(x=>x.id===live.parentId)!.name;
    if(parent!==b.parent)throw Error('Stale parent mapping');
    for(const field of ['length','neutral','setupAngle','x','y'] as const)if(live[field]!==b[field])throw Error('Stale rig geometry: '+b.name);
    mapped.set(b.role,live);
  }
  if(new Set(pose.rotations.map(r=>r.role)).size!==pose.rotations.length)throw Error('Duplicate rotation role');
  for(const r of pose.rotations)if(!mapped.has(r.role))throw Error('Unknown semantic role');
  return {pose,doc,rig,mapped};
}

function finish(c:ReturnType<typeof resolve>,samples:{role:string;frame:number;offset:number}[],now:number):Plan {
  const operations:Operation[]=[];const seen=new Set<string>();
  for(const s of samples){
    const b=c.mapped.get(s.role);if(!b)throw Error('Unknown role');
    if(!Number.isInteger(s.frame)||s.frame<c.doc.startFrame||s.frame>c.doc.endFrame||s.frame===0||!Number.isFinite(s.offset)||Math.abs(s.offset)>90)throw Error('Invalid pose sample');
    const angle=b.neutral+s.offset*Math.PI/180;
    if(Math.abs(angle)>4*Math.PI)throw Error('Target exceeds transaction angle bound');
    const id=b.id+':'+s.frame;if(seen.has(id))throw Error('Duplicate sample');seen.add(id);
    const existing=b.keys.find(k=>k.frame===s.frame);
    // Leave exact unchanged keys entirely alone, including their interpolation object.
    if(existing){if(Math.abs(existing.angle-angle)<1e-6)continue;throw Error('Existing key would change: full curve settings cannot be verified. Undo only the last owned transaction, verify baseline, then replan.');}
    operations.push({layerId:c.rig.layerId,boneId:b.id,frame:s.frame,angle,replace:false});
  }
  if(operations.length<2||operations.length>72||new Set(operations.map(o=>o.boneId)).size<2)throw Error('Transaction requires 2–72 keys across at least two bones');
  return {version:4,documentPath:c.doc.filePath,token:c.rig.token,expiresAt:Math.min(c.rig.expiresAt,now+300),fps:c.doc.fps,startFrame:c.doc.startFrame,endFrame:c.doc.endFrame,operations};
}

export function compilePose(pose:unknown,doc:unknown,rig:unknown,now:number):Plan {
  const c=resolve(pose,doc,rig,now);
  return finish(c,c.pose.rotations.map(r=>({role:r.role,frame:c.pose.frame,offset:r.offsetDegrees})),now);
}

export const cycleSchema=z.object({name:z.string().min(1),startFrame:frame,endFrame:frame,
  tracks:z.array(z.object({role:z.string().min(1),amplitudeDegrees:finite.min(-2).max(2),delayFrames:z.number().int().min(0).max(8)}).strict()).min(2).max(32),
}).strict();
export type Cycle=z.infer<typeof cycleSchema>;
/** Five samples per track; delayed peaks, independent amplitudes, identical endpoints. */
export function compileCycle(pose:unknown,cycleRaw:unknown,doc:unknown,rig:unknown,now:number):Plan {
  const c=resolve(pose,doc,rig,now),cycle=cycleSchema.parse(cycleRaw);
  if(cycle.startFrame!==c.pose.frame||cycle.endFrame<=cycle.startFrame||cycle.endFrame>c.doc.endFrame)throw Error('Invalid cycle range');
  if(new Set(cycle.tracks.map(t=>t.role)).size!==cycle.tracks.length)throw Error('Duplicate track');
  const duration=cycle.endFrame-cycle.startFrame;
  const samples=cycle.tracks.flatMap(t=>{
    const base=c.pose.rotations.find(r=>r.role===t.role);if(!base)throw Error('Track missing pose baseline');
    const frames=[cycle.startFrame,...[.25,.5,.75].map(f=>cycle.startFrame+Math.round(duration*f)+t.delayFrames),cycle.endFrame];
    if(frames.some((f,i)=>i>0&&f<=frames[i-1]))throw Error('Delay collapses cycle sample spacing');
    return frames.map((frame,i)=>({role:t.role,frame,offset:base.offsetDegrees+[0,1,0,-1,0][i]*t.amplitudeDegrees}));
  });
  return finish(c,samples,now);
}

export function verifyReadback(plan:Plan,before:Inspection,after:Inspection):void {
  if(before.bones.length!==after.bones.length||before.layerId!==after.layerId)throw Error('Rig changed');
  for(const b of before.bones){
    const a=after.bones.find(x=>x.id===b.id);if(!a)throw Error('Missing bone');
    for(const k of ['name','parentId','length','neutral','setupAngle','x','y'] as const)if(a[k]!==b[k])throw Error('Rig geometry changed');
    const ops=plan.operations.filter(o=>o.boneId===b.id);
    if(a.keys.length!==b.keys.length+ops.length)throw Error('Unexpected key count');
    for(const k of b.keys){const v=a.keys.find(v=>v.frame===k.frame);if(!v||v.angle!==k.angle||v.interpolation!==k.interpolation)throw Error('Unrelated key changed');}
    for(const op of ops){const v=a.keys.find(v=>v.frame===op.frame);if(!v||Math.abs(v.angle-op.angle)>1e-6||v.interpolation!==1)throw Error('Key readback mismatch');}
  }
}
