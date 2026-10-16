import {it,expect} from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {ipcTrace} from '../ipc-trace.js';
it('records timestamped correlation without request payloads and rotates bounded logs',()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'moho-trace-'));
 try{
  ipcTrace(dir,'published',{id:'one',session:'session',method:'bone.setTransform'});
  const file=path.join(dir,'bridge-trace.jsonl');const row=JSON.parse(fs.readFileSync(file,'utf8'));
  expect(row.timeMs).toBeGreaterThan(0);expect(row.id).toBe('one');expect(row.params).toBeUndefined();
  fs.writeFileSync(file,'x'.repeat(1048576));ipcTrace(dir,'timeout',{id:'one'});
  expect(fs.statSync(file+'.previous').size).toBe(1048576);expect(fs.statSync(file).size).toBeLessThan(1000);
 }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
it('diagnostic failure does not throw into request lifecycle',()=>{expect(()=>ipcTrace(path.join(os.tmpdir(),'missing-parent-'+Date.now(),'child'),'published')).not.toThrow();});
