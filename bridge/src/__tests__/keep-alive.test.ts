import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import { EventEmitter } from 'node:events';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { startKeepAlive, stopKeepAlive, WINDOWS_API, WINDOWS_SCRIPT } from '../keep-alive.js';
const mocks = vi.hoisted(() => ({ spawn: vi.fn() }));
vi.mock('node:child_process', async original => ({ ...await original<typeof import('node:child_process')>(), spawn: mocks.spawn }));
let dir: string;
let children: any[];
function fakeChild() {
  const child: any = new EventEmitter();
  child.stdin = Object.assign(new EventEmitter(), { end: vi.fn() });
  child.stderr = new EventEmitter(); child.kill = vi.fn(); children.push(child); return child;
}
beforeEach(() => { dir = fs.mkdtempSync(path.join(os.tmpdir(), 'moho-quiet-test-')); children = []; mocks.spawn.mockImplementation(fakeChild); vi.spyOn(os, 'platform').mockReturnValue('win32'); });
afterEach(() => { stopKeepAlive(); for (const c of children) c.emit('exit', 0); vi.restoreAllMocks(); mocks.spawn.mockReset(); fs.rmSync(dir, {recursive:true,force:true}); });
describe('quiet Windows helper lifecycle', () => {
  it('uses private unique scripts, argument boundaries and stdin ownership pipe', () => {
    startKeepAlive(dir, 'session', 'epoch'); startKeepAlive(dir, 'session', 'epoch');
    expect(mocks.spawn).toHaveBeenCalledTimes(1);
    const [exe,args,options] = mocks.spawn.mock.calls[0];
    expect(exe).toBe('powershell.exe'); expect(args).toContain(dir); expect(args).toContain('-NoProfile');
    expect(options.windowsHide).toBe(true); expect(options.stdio[0]).toBe('pipe');
    const script = args[args.indexOf('-File')+1]; expect(path.dirname(path.dirname(script))).toBe(dir);
    expect(fs.readFileSync(script,'utf8')).toBe(WINDOWS_SCRIPT);
  });
  it('stop closes stdin and kills only its child', () => {
    startKeepAlive(dir,'s','e'); const child=children[0]; stopKeepAlive();
    expect(child.stdin.end).toHaveBeenCalledOnce();expect(child.kill).toHaveBeenCalledOnce();
    child.emit('exit',0);expect(fs.readdirSync(dir)).toEqual([]);
  });
  it('old exit cannot clear a newly started helper or delete its script', () => {
    startKeepAlive(dir,'s','e'); const old=children[0];stopKeepAlive();startKeepAlive(dir,'s2','e');
    old.emit('exit',0);startKeepAlive(dir,'s2','e');expect(mocks.spawn).toHaveBeenCalledTimes(2);expect(fs.readdirSync(dir)).toHaveLength(1);
  });
  it('spawn error releases state and files for a later retry', () => {
    startKeepAlive(dir,'s','e');children[0].emit('error',new Error('fixture'));expect(fs.readdirSync(dir)).toEqual([]);
    startKeepAlive(dir,'s','e');expect(mocks.spawn).toHaveBeenCalledTimes(2);
  });
  it('does not generate simulated input or app activation commands', () => {
    expect(WINDOWS_SCRIPT).not.toMatch(/PostMessage|SendInput|WM_MOUSEMOVE|SetForegroundWindow|SetFocus|AttachThreadInput/);
    expect(WINDOWS_SCRIPT).toContain('0x0081');expect(WINDOWS_SCRIPT).toContain('[MohoQuietRefresh]::ParentClosed');
  });
  it('non-Windows systems do not activate applications', () => {
    vi.mocked(os.platform).mockReturnValue('darwin');startKeepAlive(dir,'s','e');expect(mocks.spawn).not.toHaveBeenCalled();
  });
});
it.skipIf(process.platform !== 'win32')('compiles actual C# decision policy and parses helper without UI calls', () => {
  const api=path.join(dir,'api.cs');const helper=path.join(dir,'helper.ps1');const test=path.join(dir,'test.ps1');
  fs.writeFileSync(api,WINDOWS_API);fs.writeFileSync(helper,WINDOWS_SCRIPT);
  fs.writeFileSync(test,`param($Api,$Helper)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition ([IO.File]::ReadAllText($Api))
$tokens=$null;$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($Helper,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'PowerShell syntax error'}
foreach($pending in @($true,$false)){foreach($owned in @($true,$false)){foreach($visible in @($true,$false)){foreach($foreground in @($true,$false)){foreach($idle in @(0,1499,1500,5000)){
  $expected=$pending -and $owned -and $visible -and -not $foreground
  if([MohoQuietRefresh]::MayRefresh($pending,$owned,$visible,$foreground,$idle) -ne $expected){throw 'Policy mismatch'}
}}}}}
Write-Output 'PASS: 64 policy cases; no user32 functions invoked'
`);
  const out=execFileSync('powershell.exe',['-NoProfile','-NonInteractive','-File',test,api,helper],{encoding:'utf8',windowsHide:true,timeout:20000});
  expect(out).toContain('64 policy cases');
},25000);
it.skipIf(process.platform !== 'win32')('real helper exits on stdin EOF with an empty isolated mailbox and no UI calls', () => {
  const helper=path.join(dir,'helper.ps1');const runner=path.join(dir,'run.ps1');fs.writeFileSync(helper,WINDOWS_SCRIPT);
  fs.writeFileSync(runner,`param($Helper,$Ipc)
$ErrorActionPreference='Stop'
$start=New-Object Diagnostics.ProcessStartInfo
$start.FileName='powershell.exe'
$start.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$Helper+'" -IpcDir "'+$Ipc+'" -Session test -ServerId test'
$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardInput=$true
$p=[Diagnostics.Process]::Start($start)
try {
  Start-Sleep -Milliseconds 1200
  if($p.HasExited){throw 'Helper exited before EOF'}
  $p.StandardInput.Close()
  if(!$p.WaitForExit(8000)){throw 'Helper failed to exit on EOF'}
  if($p.ExitCode -ne 0){throw 'Helper failed'}
  Write-Output 'PASS EOF; no request, no UI calls'
} finally { if(!$p.HasExited){$p.Kill()} }
`);
  const out=execFileSync('powershell.exe',['-NoProfile','-NonInteractive','-File',runner,helper,dir],{encoding:'utf8',windowsHide:true,timeout:15000});
  expect(out).toContain('PASS EOF');
},20000);
