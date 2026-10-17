import fs from 'node:fs';import path from 'node:path';import {execFileSync} from 'node:child_process';import {fileURLToPath} from 'node:url';
import {files,sha,validatePackage,preview,verify,deploy,rollback,uninstall} from './deployment.mjs';
const repo=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const [action,...args]=process.argv.slice(2);const opts={};for(let i=0;i<args.length;i+=2){if(!args[i].startsWith('--')||args[i+1]===undefined)throw Error('Use --name value');opts[args[i].slice(2)]=args[i+1];}
const read=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
function command(exe,args,cwd){execFileSync(exe,args,{cwd,stdio:'inherit',windowsHide:true});}
function npm(args,cwd){if(process.platform==='win32'){if(args.some(s=>!/^[\w./=-]+$/.test(s)))throw Error('Unsafe npm argument');command('cmd.exe',['/d','/s','/c','npm '+args.join(' ')],cwd);}else command('npm',args,cwd);}
function stopped(c){
 if(process.platform!=='win32')throw Error('Live deployment is Windows-only');
 if(!fs.existsSync(c.mohoExecutable)||path.basename(c.mohoExecutable).toLowerCase()!=='moho.exe')throw Error('Moho executable missing');
 const ps="$ErrorActionPreference='Stop'; Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne "+process.pid+" -and ($_.Name -eq 'Moho.exe' -or ($_.Name -eq 'node.exe' -and $_.CommandLine -match 'dist[\\\\/]+index[.]js|launch-installed[.]mjs')) } | Select-Object Name,ProcessId,CommandLine | ConvertTo-Json -Compress";
 const running=execFileSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',ps],{encoding:'utf8',windowsHide:true}).trim();if(running)throw Error('Close Moho and the MohoMCP bridge/Codex normally before deployment: '+running);
}
function checkMoho(c){
 if(process.platform!=='win32')throw Error('Preview is for Windows Moho 14.5');
 const v=execFileSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',"$ErrorActionPreference='Stop'; (Get-Item -LiteralPath $env:MOHOMCP_VERSION_EXE).VersionInfo.ProductVersion"],{encoding:'utf8',windowsHide:true,env:{...process.env,MOHOMCP_VERSION_EXE:c.mohoExecutable}}).trim();
 if(!/^14\.5(?:\.|$)/.test(v))throw Error('Expected Moho 14.5, found '+v);
 const list=path.join(c.scriptsRoot,'Tool/_tool_list.txt');
 if(fs.existsSync(list)&&!/^tool\s+MohoMCP_Poller\s/m.test(fs.readFileSync(list,'utf8')))throw Error('Custom tool list omits MohoMCP_Poller. Add its tool entry with approval before deployment; the installer will not replace your custom tool list.');
}
if(action==='Prepare'){
 const out=path.resolve(opts.package||path.join(repo,'release-package'));if(fs.existsSync(out))throw Error('Use a new empty package path');
 fs.mkdirSync(out,{recursive:true});const bridge=path.join(out,'bridge');fs.mkdirSync(bridge);
 for(const name of ['package.json','package-lock.json','tsconfig.json'])fs.copyFileSync(path.join(repo,'bridge',name),path.join(bridge,name));
 fs.cpSync(path.join(repo,'bridge/src'),path.join(bridge,'src'),{recursive:true});
 npm(['ci','--ignore-scripts','--no-audit','--no-fund'],bridge);
 command(process.execPath,[path.join(bridge,'node_modules/typescript/bin/tsc')],bridge);
 npm(['prune','--omit=dev','--ignore-scripts','--no-audit','--no-fund'],bridge);
 // Remove only staging paths verified beneath the new package.
 for(const rel of ['src','tsconfig.json','dist/__tests__']){const p=path.resolve(bridge,rel);if(!p.startsWith(bridge+path.sep))throw Error('Unsafe staging path');fs.rmSync(p,{recursive:true,force:true});}
 const plugin=path.join(repo,'moho-plugin');
 for(const rel of files(plugin).filter(p=>p.endsWith('.lua')&&!p.startsWith('tests/'))){
  const target=rel==='MohoMCP_Poller.lua'?'Tool/'+rel:'Menu/MohoMCP/'+rel;
  const to=path.join(out,'scripts',target);fs.mkdirSync(path.dirname(to),{recursive:true});fs.copyFileSync(path.join(plugin,rel),to);
 }
 const version=read(path.join(repo,'release.json'));
 const manifest={format:1,version,files:files(out).map(source=>({source,area:source.split('/')[0],target:source.split('/').slice(1).join('/'),sha256:sha(path.join(out,source))}))};
 fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify(manifest,null,2));validatePackage(out);console.log(JSON.stringify({prepared:out,version,files:manifest.files.length}));
}else{
 const c=read(opts.profile);let result;
 if(action==='Preview'){checkMoho(c);result=preview(opts.package,c);if(opts.output)fs.writeFileSync(opts.output,JSON.stringify(result,null,2));}
 else if(action==='Verify')result=verify(c);
 else {checkMoho(c);stopped(c);if(action==='Install'||action==='Update'){if(action==='Install'&&fs.existsSync(path.join(c.stateRoot,'installed.json')))throw Error('Already installed; use Update');if(action==='Update')verify(c);result=deploy(opts.package,c);}
 else if(action==='Rollback')result=rollback(c,opts.backup);
 else if(action==='Uninstall')result=uninstall(c);
 else throw Error('Unknown action');}
 console.log(JSON.stringify(result,null,2));
}
