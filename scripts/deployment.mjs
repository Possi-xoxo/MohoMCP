import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
export const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const read=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
const save=(p,v)=>{fs.mkdirSync(path.dirname(p),{recursive:true});fs.writeFileSync(p,JSON.stringify(v,null,2));};
export const LUA_MODULES=['attachment_binding','attachment_inspection','coordinated_write','iterative_write','protocol','safe_write','server','validator','version','tools/animation','tools/batch','tools/bone','tools/document','tools/layer','tools/mesh'];
export function safePath(root,rel){
 if(typeof rel!=='string'||!rel||rel.includes('\\')||rel.includes(':')||rel.split('/').some(s=>s==='..'||s===''||s==='.')||path.isAbsolute(rel))throw Error('Unsafe manifest path');
 const result=path.resolve(root,rel);let current=path.resolve(root);
 for(const part of [null,...rel.split('/')]){if(part)current=path.join(current,part);if(fs.existsSync(current)&&fs.lstatSync(current).isSymbolicLink())throw Error('Links/reparse points are unsupported');}
 return result;
}
export function files(root){
 const out=[];
 function walk(dir,rel=''){for(const ent of fs.readdirSync(dir,{withFileTypes:true})){const r=rel?rel+'/'+ent.name:ent.name;if(ent.isSymbolicLink())throw Error('Package contains a link');if(ent.isDirectory())walk(path.join(dir,ent.name),r);else if(ent.isFile())out.push(r);else throw Error('Unsupported package entry');}}
 walk(root);return out.sort();
}
export function validatePackage(pkg){
 const m=read(path.join(pkg,'manifest.json'));
 if(m.format!==1||m.version.ipc!==2||m.version.release!==m.version.lua||m.version.release!==m.version.bridge||m.version.supportedMoho!=='14.5')throw Error('Incompatible package metadata');
 const seen=new Set();
 for(const f of m.files){if(!['scripts','bridge'].includes(f.area)||seen.has(f.area+'/'+f.target))throw Error('Duplicate/invalid destination');seen.add(f.area+'/'+f.target);
  if(f.area==='scripts'&&!(f.target==='Tool/MohoMCP_Poller.lua'||f.target.startsWith('Menu/MohoMCP/')))throw Error('Unrelated script destination');
  safePath(pkg,f.target);const p=safePath(pkg,f.source);if(!fs.existsSync(p)||sha(p)!==f.sha256)throw Error('Missing/corrupted package: '+f.source);
 }
 for(const required of ['scripts/Tool/MohoMCP_Poller.lua','scripts/Menu/MohoMCP/MohoMCP_Server.lua','scripts/Menu/MohoMCP/json.lua','scripts/Menu/MohoMCP/moho_mcp/tools/batch.lua','scripts/Menu/MohoMCP/moho_mcp/attachment_binding.lua','scripts/Menu/MohoMCP/moho_mcp/version.lua','bridge/dist/index.js','bridge/dist/compatibility.js','bridge/package-lock.json'])if(!seen.has(required))throw Error('Incomplete package: '+required);
 for(const module of LUA_MODULES)if(!seen.has('scripts/Menu/MohoMCP/moho_mcp/'+module+'.lua'))throw Error('Incomplete Lua module: '+module);
 const lua=fs.readFileSync(safePath(pkg,m.files.find(f=>f.target.endsWith('moho_mcp/version.lua')).source),'utf8');
 for(const f of m.files.filter(f=>f.area==='scripts'&&f.target.endsWith('.lua'))){
  const content=fs.readFileSync(safePath(pkg,f.source),'utf8');
  for(const match of content.matchAll(/require\s*\(?\s*['"](moho_mcp\.[\w.]+|json)['"]/g)){
   const dependency='scripts/Menu/MohoMCP/'+match[1].replaceAll('.','/')+'.lua';
   if(!seen.has(dependency))throw Error('Missing Lua dependency: '+dependency);
  }
 }
 const js=fs.readFileSync(safePath(pkg,m.files.find(f=>f.target==='dist/compatibility.js').source),'utf8');
 if(!lua.includes("release='"+m.version.release+"'")||!js.includes("'"+m.version.release+"'"))throw Error('Compiled version mismatch');
 // Exact file inventory prevents hidden unverified payloads.
 const listed=new Set(m.files.map(f=>f.source));
 for(const p of files(pkg))if(p!=='manifest.json'&&!listed.has(p))throw Error('Unmanifested payload: '+p);
 return m;
}
export function validateProfile(c){
 for(const k of ['scriptsRoot','bridgeRoot','stateRoot']){
  if(!path.isAbsolute(c[k]||''))throw Error('Absolute '+k+' required');
  let p=path.resolve(c[k]);while(true){if(fs.existsSync(p)&&fs.lstatSync(p).isSymbolicLink())throw Error('Linked target');const parent=path.dirname(p);if(parent===p)break;p=parent;}
 }
 const roots=['scriptsRoot','bridgeRoot','stateRoot'].map(k=>path.resolve(c[k]).toLowerCase());
 for(let i=0;i<roots.length;i++)for(let j=i+1;j<roots.length;j++)if(roots[i]===roots[j]||roots[i].startsWith(roots[j]+path.sep)||roots[j].startsWith(roots[i]+path.sep))throw Error('Deployment roots must not overlap');
 if(!fs.statSync(c.scriptsRoot).isDirectory())throw Error('Scripts directory missing');
}
const dest=(c,f)=>safePath(f.area==='scripts'?c.scriptsRoot:c.bridgeRoot,f.target);
export function preview(pkg,c){validateProfile(c);const m=validatePackage(pkg);return {version:m.version,files:m.files.map(f=>({source:safePath(pkg,f.source),destination:dest(c,f),sha256:f.sha256,existing:fs.existsSync(dest(c,f))})),configurationChanged:false,projectsChanged:false};}
export function verify(c){
 validateProfile(c);if(fs.existsSync(path.join(c.stateRoot,'journal.json'))||fs.existsSync(path.join(c.stateRoot,'operation.lock')))throw Error('Incomplete or active deployment; writes must remain disabled');
 const m=read(path.join(c.stateRoot,'installed.json'));
 if(JSON.stringify(m.roots)!==JSON.stringify({scriptsRoot:c.scriptsRoot,bridgeRoot:c.bridgeRoot}))throw Error('Installation roots changed');
 for(const f of m.files){const p=dest(c,f);if(!fs.existsSync(p)||sha(p)!==f.sha256)throw Error('Installed hash mismatch: '+p);}
 return {verified:true,version:m.version,files:m.files.length};
}
function restore(c,b){
 for(const f of b.files)if(f.previous){const p=safePath(b.directory,f.backup);if(sha(p)!==f.previous)throw Error('Backup integrity failure');}
 for(const f of [...b.files].reverse()){
  const p=dest(c,f);if(f.previous){fs.mkdirSync(path.dirname(p),{recursive:true});fs.copyFileSync(safePath(b.directory,f.backup),p);if(sha(p)!==f.previous)throw Error('Restore verification failed');}
  else if(fs.existsSync(p))fs.unlinkSync(p);
 }
 const installed=path.join(c.stateRoot,'installed.json');if(b.installedBefore)save(installed,b.installedBefore);else if(fs.existsSync(installed))fs.unlinkSync(installed);
}
export function deploy(pkg,c,{fault=()=>{}}={}){
 const m=validatePackage(pkg);validateProfile(c);fs.mkdirSync(c.stateRoot,{recursive:true});
 const lock=path.join(c.stateRoot,'operation.lock'),journal=path.join(c.stateRoot,'journal.json');
 if(fs.existsSync(journal))throw Error('Previous incomplete deployment requires recovery');
 const fd=fs.openSync(lock,'wx');fs.closeSync(fd);let started=false;let b;
 try{
  const old=fs.existsSync(path.join(c.stateRoot,'installed.json'))?read(path.join(c.stateRoot,'installed.json')):null;
  const directory=path.join(c.stateRoot,'backups',new Date().toISOString().replace(/[:.]/g,'-')+'-'+crypto.randomUUID());fs.mkdirSync(directory,{recursive:true});
  const union=new Map();for(const f of [...(old?.files||[]),...m.files])union.set(f.area+'/'+f.target,f);
  b={directory,installedBefore:old,files:[]};let i=0;
  for(const f of union.values()){
   const p=dest(c,f);let previous=null;const backup='files/'+i++;
   if(fs.existsSync(p)){if(!fs.statSync(p).isFile())throw Error('Destination not a regular file');previous=sha(p);const to=safePath(directory,backup);fs.mkdirSync(path.dirname(to),{recursive:true});fs.copyFileSync(p,to);if(sha(to)!==previous)throw Error('Backup verification failed');}
   b.files.push({area:f.area,target:f.target,previous,backup,newHash:f.sha256});
  }
  // Preserve the entire old plugin tree in addition to the per-file rollback set.
  const plugin=path.join(c.scriptsRoot,'Menu/MohoMCP');if(fs.existsSync(plugin))for(const rel of files(plugin)){const to=safePath(directory,'plugin-tree/'+rel);fs.mkdirSync(path.dirname(to),{recursive:true});fs.copyFileSync(safePath(plugin,rel),to);if(sha(to)!==sha(safePath(plugin,rel)))throw Error('Plugin backup mismatch');}
  save(path.join(directory,'backup.json'),b);save(journal,{backup:directory});started=true;
  let n=0;
  for(const f of m.files){const p=dest(c,f);fs.mkdirSync(path.dirname(p),{recursive:true});fs.copyFileSync(safePath(pkg,f.source),p);if(sha(p)!==f.sha256)throw Error('Install verification failed');fault(++n);}
  // Keep obsolete files: never delete unknown/custom files during migration/update.
  save(path.join(c.stateRoot,'installed.json'),{...m,roots:{scriptsRoot:c.scriptsRoot,bridgeRoot:c.bridgeRoot},backup:directory});
  fs.unlinkSync(journal);return {installed:true,backup:directory,files:m.files.length};
 }catch(e){if(started){try{restore(c,b);fs.unlinkSync(journal);}catch(re){throw Error(e.message+'; ROLLBACK FAILED: '+re.message+'; preserve journal and backups');}}throw e;
 }finally{fs.unlinkSync(lock);}
}
export function rollback(c,backup){
 validateProfile(c);const b=read(path.join(backup,'backup.json'));
 if(path.resolve(b.directory)!==path.resolve(backup)||!path.resolve(backup).startsWith(path.resolve(c.stateRoot,'backups')+path.sep))throw Error('Backup must belong to this deployment');
 const journal=path.join(c.stateRoot,'journal.json');
 if(fs.existsSync(journal)){
  if(read(journal).backup!==backup)throw Error('Recovery backup differs from journal');
  for(const f of b.files){const p=dest(c,f);if(fs.existsSync(p)&&![f.previous,f.newHash].includes(sha(p)))throw Error('Recovery would overwrite an unrecognized edit');}
 }else{
  verify(c);const current=read(path.join(c.stateRoot,'installed.json'));if(current.backup!==backup)throw Error('Only immediate previous deployment may be rolled back');
 }
 const lock=path.join(c.stateRoot,'operation.lock');fs.closeSync(fs.openSync(lock,'wx'));
 try{save(path.join(c.stateRoot,'journal.json'),{backup});restore(c,b);fs.unlinkSync(path.join(c.stateRoot,'journal.json'));return {rolledBack:true};}finally{fs.unlinkSync(lock);}
}
export function uninstall(c){
 verify(c);const m=read(path.join(c.stateRoot,'installed.json'));
 // Restore the immediate predecessor instead of destructively removing a migrated installation.
 if(m.backup){const b=read(path.join(m.backup,'backup.json'));if(b.installedBefore||b.files.some(f=>f.previous))throw Error('Migration/update detected. Rollback first; uninstall only a fresh managed installation.');}
 const lock=path.join(c.stateRoot,'operation.lock');fs.closeSync(fs.openSync(lock,'wx'));
 try{save(path.join(c.stateRoot,'journal.json'),{uninstall:true});for(const f of m.files)fs.unlinkSync(dest(c,f));fs.renameSync(path.join(c.stateRoot,'installed.json'),path.join(c.stateRoot,'uninstalled-'+Date.now()+'.json'));fs.unlinkSync(path.join(c.stateRoot,'journal.json'));return {uninstalled:true,backupsPreserved:true};}finally{fs.unlinkSync(lock);}
}
