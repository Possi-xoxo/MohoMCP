/** Demand-driven Windows repaint helper. Never sends synthetic input. */
import { spawn, ChildProcess } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { ipcTrace } from './ipc-trace.js';

export const WINDOWS_API = `
using System;
using System.Runtime.InteropServices;
public class MohoQuietRefresh {
    public static volatile bool ParentClosed = false;
    public static void WatchParent() {
        var watcher = new System.Threading.Thread(() => {
            try { while (Console.In.Read() != -1) {} } finally { ParentClosed = true; }
        });
        watcher.IsBackground = true;
        watcher.Start();
    }
    [StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool RedrawWindow(IntPtr hwnd, IntPtr rect, IntPtr region, uint flags);
    public static bool MayRefresh(bool pending, bool owned, bool visible, bool foreground, uint idleMs) {
        // Global idle includes typing in other applications. Foreground ownership,
        // not unrelated input, protects Moho's text controls from artificial paint.
        return pending && owned && visible && !foreground;
    }
    public static uint IdleMs() {
        var info = new LASTINPUTINFO(); info.cbSize = (uint)Marshal.SizeOf(info);
        if (!GetLastInputInfo(ref info)) return 0;
        return unchecked((uint)Environment.TickCount - info.dwTime);
    }
    public static bool ForegroundIs(uint pid) {
        uint active; var hwnd = GetForegroundWindow();
        if (hwnd == IntPtr.Zero || GetWindowThreadProcessId(hwnd, out active) == 0) return true;
        return active == pid;
    }
}
`;
export const WINDOWS_SCRIPT = `
param([string]$IpcDir,[string]$Session,[string]$ServerId)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
${WINDOWS_API}
"@
# The owning Node process holds stdin open. EOF on graceful or abrupt parent exit
# ends the helper without trusting a potentially recycled PID.
[MohoQuietRefresh]::WatchParent()
$lastTrace = 0L
function Trace-State($eventName,$data) {
    try {
        $file = Join-Path $IpcDir 'helper-trace.jsonl'
        if ((Test-Path -LiteralPath $file) -and (Get-Item -LiteralPath $file).Length -ge 1048576) {
            Move-Item -LiteralPath $file -Destination ($file+'.previous') -Force
        }
        $row = @{timeMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();source='helper';event=$eventName;session=$Session;serverId=$ServerId;data=$data}
        [IO.File]::AppendAllText($file,($row | ConvertTo-Json -Compress -Depth 4)+[Environment]::NewLine)
    } catch { }
}
Trace-State 'started' @{}
while (-not [MohoQuietRefresh]::ParentClosed) {
    try {
        $requestPath = Join-Path $IpcDir 'request.json'
        if (Test-Path -LiteralPath $requestPath) {
            $request = Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
            $owner = Get-Content -LiteralPath (Join-Path $IpcDir 'bridge-owner.json') -Raw | ConvertFrom-Json
            $status = Get-Content -LiteralPath (Join-Path $IpcDir 'status.json') -Raw | ConvertFrom-Json
            $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $pending = $request.ipcVersion -eq 2 -and $request.session -eq $Session -and $request.serverId -eq $ServerId -and $request.expiresAt -gt $now
            $owned = $owner.session -eq $Session -and $owner.serverId -eq $ServerId -and $status.running -eq $true -and $status.serverId -eq $ServerId
            $procs = @(Get-Process -Name 'Moho' -ErrorAction SilentlyContinue)
            # Refuse ambiguous targets. Never repaint every Moho instance.
            if ($procs.Count -eq 1 -and -not [MohoQuietRefresh]::ParentClosed) {
                $p = $procs[0]; $hwnd = $p.MainWindowHandle
                $visible = $hwnd -ne [IntPtr]::Zero -and [MohoQuietRefresh]::IsWindowVisible($hwnd) -and -not [MohoQuietRefresh]::IsIconic($hwnd)
                $active = [MohoQuietRefresh]::ForegroundIs([uint32]$p.Id)
                $idle = [MohoQuietRefresh]::IdleMs()
                if ($now - $lastTrace -ge 1000) {
                    Trace-State 'pending_state' @{id=$request.id;method=$request.method;pending=$pending;owned=$owned;visible=$visible;foreground=$active;idleMs=$idle;expiresAt=$request.expiresAt}
                    $lastTrace=$now
                }
                if ([MohoQuietRefresh]::MayRefresh($pending,$owned,$visible,$active,$idle)) {
                    # Recheck after diagnostic IO: the user may have switched to Moho.
                    # INVALIDATE | ALLCHILDREN: ordinary asynchronous paint only.
                    # No UPDATENOW, mouse messages, focus changes, or activation.
                    if (-not [MohoQuietRefresh]::ParentClosed -and -not [MohoQuietRefresh]::ForegroundIs([uint32]$p.Id)) {
                        $paintOK=[MohoQuietRefresh]::RedrawWindow($hwnd,[IntPtr]::Zero,[IntPtr]::Zero,0x0081)
                        if (-not $paintOK) { Trace-State 'paint_failed' @{id=$request.id} }
                    }
                }
            } elseif ($now - $lastTrace -ge 1000) {
                Trace-State 'ambiguous_or_missing_process' @{count=$procs.Count};$lastTrace=$now
            }
        }
    } catch {
        # Missing/malformed state or unreadable UI state suppresses repaint.
        $errorTime=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        if ($errorTime - $lastTrace -ge 1000) { Trace-State 'state_error' @{message=$_.Exception.Message};$lastTrace=$errorTime }
    }
    Start-Sleep -Milliseconds 250
}
`;
let active: { child: ChildProcess; dir: string } | null = null;

export function startKeepAlive(ipcDir: string, session: string, serverId: string): void {
    if (active) return;
    // Other platforms use natural viewport repaint; no focus-stealing activation.
    if (os.platform() !== "win32") return;
    const dir = fs.mkdtempSync(path.join(ipcDir, "keep-alive-"));
    const script = path.join(dir, "refresh.ps1");
    try {
        fs.writeFileSync(script, WINDOWS_SCRIPT, "utf8");
        const child = spawn("powershell.exe", ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", script, "-IpcDir", ipcDir, "-Session", session, "-ServerId", serverId], {
            stdio: ["pipe", "ignore", "pipe"], detached: false, windowsHide: true,
        });
        const entry = { child, dir }; active = entry;
        const clean = () => {
            if (active === entry) active = null;
            try { fs.rmSync(dir, { recursive: true, force: true }); } catch { /* best-effort script cleanup */ }
        };
        child.once("exit", clean);
        child.once("error", error => { process.stderr.write(`[moho-mcp] Quiet refresh unavailable: ${error.message}\n`); clean(); });
        child.stdin?.on("error", () => {});
        let errorBytes=0;
        child.stderr?.on("data", data => { if(errorBytes<4096){ipcTrace(ipcDir,'helper_stderr',{message:String(data).slice(0,512)});errorBytes+=Buffer.byteLength(data);} });
        process.stderr.write("[moho-mcp] Quiet refresh started; suppressed during foreground Moho interaction\n");
    } catch (error) {
        fs.rmSync(dir, { recursive: true, force: true });
        throw error;
    }
}
export function stopKeepAlive(): void {
    const entry = active;
    if (!entry) return;
    active = null;
    entry.child.stdin?.end();
    // Kill only our exact child; no name-based cleanup. Exit callback removes files.
    entry.child.kill();
}
