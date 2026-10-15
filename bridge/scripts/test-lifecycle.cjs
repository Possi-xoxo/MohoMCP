// Real bridge subprocesses and Windows identity probes; fake Lua only.
// Native keep-alive is replaced in a preload, never enabled in these tests.
const assert=require('node:assert/strict');
const fs=require('node:fs');const fsp=fs.promises;
const path=require('node:path');const os=require('node:os');
const {Client}=require('@modelcontextprotocol/sdk/client/index.js');
const {StdioClientTransport}=require('@modelcontextprotocol/sdk/client/stdio.js');
const {spawn}=require('node:child_process');
const {once}=require('node:events');
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const dist=path.resolve(__dirname,'../dist');
async function main(){
 const dir=await fsp.mkdtemp(path.join(os.tmpdir(),'moho lifecycle '));
 const file=n=>path.join(dir,n);const clients=[];let count=0;
 const preload=file('no-native.cjs');
 await fsp.writeFile(preload,`const k=require(${JSON.stringify(path.join(dist,'keep-alive.js'))});k.startKeepAlive=()=>{};k.stopKeepAlive=()=>{};`);
 await fsp.writeFile(file('status.json'),JSON.stringify({running:true,ipcVersion:2,serverId:'test-server',ipcDir:dir}));
 let seen=new Set(),hold=false;
 const timer=setInterval(()=>{
  try{
   const r=JSON.parse(fs.readFileSync(file('request.json'),'utf8'));
   if(seen.has(r.id)||(hold&&r.method!=='ipc.ping'))return;seen.add(r.id);
   fs.writeFileSync(file('response.json.tmp'),JSON.stringify({jsonrpc:'2.0',ipcVersion:2,serverId:r.serverId,session:r.session,id:r.id,result:{test:true}}));
   fs.renameSync(file('response.json.tmp'),file('response.json'));
  }catch(e){if(e.code!=='ENOENT')throw e;}
 },5);
 async function open(){
  const c=new Client({name:'isolated-lifecycle',version:'1'});
  const t=new StdioClientTransport({command:process.execPath,args:['-r',preload,path.join(dist,'index.js')],env:{...process.env,MOHO_MCP_IPC_DIR:dir},stderr:'pipe'});
  clients.push(c);await c.connect(t);return {c,t};
 }
 async function read(c){const r=await c.callTool({name:'document_getInfo',arguments:{}});assert(!r.isError,JSON.stringify(r));return r;}
 const owner=()=>JSON.parse(fs.readFileSync(file('bridge-owner.json'),'utf8'));
 const pass=s=>{count++;console.log('PASS: '+s);};
 try{
  let a=await open();await read(a.c);let first=owner();
  const competitor=await open();const conflict=await competitor.c.callTool({name:'document_getInfo',arguments:{}});
  assert(conflict.isError);assert.equal(owner().session,first.session);await competitor.c.close();pass('competing real bridge cannot take active ownership');
  // SDK close ends stdin first; this exercises the actual production EOF path.
  await a.c.close();assert(!fs.existsSync(file('bridge-owner.json')));assert(!fs.existsSync(file('ownership-transition')));pass('stdin EOF gracefully releases owner and transition guard');
  a=await open();await read(a.c);assert.notEqual(owner().session,first.session);pass('Codex-style close/reopen gets a fresh session');
  hold=true;const pending=a.c.callTool({name:'document_getInfo',arguments:{}}).catch(()=>{});
  await sleep(150);await a.c.close();await pending;assert(!fs.existsSync(file('bridge-owner.json')));hold=false;pass('EOF during in-flight read cancels work and releases ownership');
  a=await open();await read(a.c);first=owner();
  process.kill(first.pid,'SIGKILL'); // only the isolated child whose lock we just read
  await sleep(300);await a.c.close();assert(fs.existsSync(file('bridge-owner.json')));
  fs.writeFileSync(file('response.json'),JSON.stringify({ipcVersion:2,session:first.session,serverId:first.serverId,id:'old',result:'stale'}));
  a=await open();await read(a.c);assert.notEqual(owner().session,first.session);pass('abrupt termination recovers verified old session and rejects leftover reply');
  await a.c.close();assert(!fs.existsSync(file('bridge-owner.json')));
  // EOF before any MCP handshake must also exit without hanging or acquiring IPC.
  const child=spawn(process.execPath,['-r',preload,path.join(dist,'index.js')],{env:{...process.env,MOHO_MCP_IPC_DIR:dir},stdio:['pipe','pipe','pipe'],windowsHide:true});
  const ended=once(child,'exit');child.stdin.end();const timeout=setTimeout(()=>child.kill(),5000);
  const [code]=await ended;clearTimeout(timeout);assert.equal(code,0);assert(!fs.existsSync(file('bridge-owner.json')));pass('EOF during startup exits cleanly');
  for (const event of ['SIGINT','SIGTERM','SIGHUP','stdout-error','transport-close']) {
   const fixture=`const {Ownership}=require(${JSON.stringify(path.join(dist,'ownership.js'))});
const {installLifecycle}=require(${JSON.stringify(path.join(dist,'lifecycle.js'))});
(async()=>{const session=require('node:crypto').randomUUID();const o=new Ownership(${JSON.stringify(dir)});
await o.acquire(session,'test-server');const shutdown=installLifecycle(()=>o.release(session));
if(${JSON.stringify(event)}==='stdout-error')process.stdout.emit('error',new Error('broken pipe'));
else if(${JSON.stringify(event)}==='transport-close')void shutdown('MCP transport closed');
else process.emit(${JSON.stringify(event)});})().catch(e=>{console.error(e);process.exit(2)});`;
   const child=spawn(process.execPath,['-e',fixture],{stdio:['pipe','pipe','pipe'],windowsHide:true});
   const ended=once(child,'exit');const timeout=setTimeout(()=>child.kill(),10000);
   const [code]=await ended;clearTimeout(timeout);
   assert.equal(code,event==='stdout-error'?1:0);assert(!fs.existsSync(file('bridge-owner.json')));
   pass(`${event} lifecycle handler releases ownership (in-process event fixture)`);
  }
  console.log(`RESULT: ${count} subprocess lifecycle scenarios passed; no Moho or native helpers used.`);
 }finally{
  for(const c of clients)await c.close().catch(()=>{});
  clearInterval(timer);await fsp.rm(dir,{recursive:true,force:true}); // this test's mkdtemp only
 }
}
main().catch(e=>{console.error(e);process.exitCode=1;});
