import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
const exec = promisify(execFile);
export type Identity = { birth: string; executable: string };
export type Probe = (pid: number) => Promise<Identity | null>;

// null means positively absent; access failures and unsupported hosts throw.
// Never execute text from an owner record as shell code.
export const probeProcess: Probe = async pid => {
  if (!Number.isSafeInteger(pid) || pid <= 0) throw new Error("Invalid owner PID");
  if (process.platform !== "win32") throw new Error("Automatic owner recovery requires Windows process identity support");
  const command = `$ErrorActionPreference='Stop'; try { $p=[Diagnostics.Process]::GetProcessById(${pid}) } catch [ArgumentException] { Write-Output 'null'; exit 0 }; @{birth=$p.StartTime.ToUniversalTime().Ticks.ToString();executable=$p.MainModule.FileName} | ConvertTo-Json -Compress`;
  const { stdout } = await exec(path.join(process.env.SystemRoot || "C:\\Windows", "System32/WindowsPowerShell/v1.0/powershell.exe"),
    ["-NoProfile", "-NonInteractive", "-Command", command], { windowsHide: true, timeout: 5000, maxBuffer: 16384 });
  const value = JSON.parse(stdout.trim());
  if (value === null) return null;
  if (typeof value.birth !== "string" || !/^\d+$/.test(value.birth) || typeof value.executable !== "string" || !path.isAbsolute(value.executable)) throw new Error("Unverifiable process identity");
  return value;
};

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const mailbox = ["request.json", "request.json.tmp", "response.json", "response.json.tmp"];
const absent = (e: unknown) => (e as NodeJS.ErrnoException).code === "ENOENT";
export class Ownership {
  constructor(private dir: string, private probe: Probe = probeProcess) {}
  private file(name: string) { return path.join(this.dir, name); }
  private async read(name: string): Promise<string | null> {
    try {
      const stat = await fs.lstat(this.file(name));
      if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 1024 * 1024) throw new Error("Unsafe ownership file");
      return await fs.readFile(this.file(name), "utf8");
    } catch (e) { if (absent(e)) return null; throw e; }
  }
  private async guarded<T>(action: () => Promise<T>): Promise<T> {
    const guard = this.file("ownership-transition");
    const deadline = Date.now() + 2000;
    while (true) {
      try { await fs.mkdir(guard); break; }
      catch (e) {
        if ((e as NodeJS.ErrnoException).code !== "EEXIST") throw e;
        if (Date.now() >= deadline) throw new Error("IPC ownership transition busy or interrupted; explicit recovery required");
        await new Promise(r => setTimeout(r, 25));
      }
    }
    try { return await action(); } finally { await fs.rmdir(guard); }
  }
  async acquire(session: string, serverId: string): Promise<void> {
    if (!uuid.test(session)) throw new Error("Invalid session");
    // Outside the guard: slow OS inspection must not lengthen transition windows.
    const identity = process.platform === "win32" ? await this.probe(process.pid) : null;
    if (process.platform === "win32" && !identity) throw new Error("Cannot identify current bridge process");
    await this.guarded(async () => {
      const previous = await this.read("bridge-owner.json");
      if (previous !== null) await this.recover(previous);
      const owner = JSON.stringify({ ownerVersion: 1, session, serverId, pid: process.pid,
        identity, hostname: os.hostname(), platform: process.platform, startedAt: Date.now() });
      // Immutable matching receipt proves complete publication; partial/legacy locks fail closed.
      await fs.writeFile(this.file(`owner-session-${session}.json`), owner, { flag: "wx" });
      await fs.writeFile(this.file("bridge-owner.json"), owner, { flag: "wx" });
    });
  }
  private async recover(raw: string): Promise<void> {
    const conflict = () => new Error("IPC ownership conflict: active, unverifiable, legacy, or crashed bridge state requires explicit recovery");
    let owner;
    try { owner = JSON.parse(raw); } catch { throw conflict(); }
    if (owner.ownerVersion !== 1 || !uuid.test(owner.session) || !Number.isSafeInteger(owner.pid) || owner.pid <= 0 ||
        owner.platform !== "win32" || process.platform !== "win32" || owner.hostname !== os.hostname() ||
        typeof owner.serverId !== "string" || !owner.serverId || !owner.identity ||
        typeof owner.identity.birth !== "string" || !/^\d+$/.test(owner.identity.birth) ||
        typeof owner.identity.executable !== "string" || !path.isAbsolute(owner.identity.executable)) throw conflict();
    if (await this.read(`owner-session-${owner.session}.json`) !== raw) throw conflict();
    // Any live PID is protected, even a reused PID with a different birth identity.
    // We never terminate processes or take locks from a live/uninspectable process.
    if (await this.probe(owner.pid) !== null) throw conflict();
    for (const name of mailbox) {
      const text = await this.read(name);
      if (text === null) continue;
      let value;
      try { value = JSON.parse(text); } catch { throw conflict(); }
      if (value.session !== owner.session || value.serverId !== owner.serverId || value.ipcVersion !== 2) throw conflict();
    }
    if (await this.read("bridge-owner.json") !== raw || await this.probe(owner.pid) !== null) throw conflict();
    for (const name of mailbox) await fs.unlink(this.file(name)).catch(e => { if (!absent(e)) throw e; });
    await fs.unlink(this.file("bridge-owner.json"));
    await fs.unlink(this.file(`owner-session-${owner.session}.json`));
    process.stderr.write("[moho-mcp] Recovered verified exited-owner session; previous operation outcome may be unknown\n");
  }
  async release(session: string): Promise<void> {
    await this.guarded(async () => {
      const raw = await this.read("bridge-owner.json");
      if (raw === null) return;
      const owner = JSON.parse(raw);
      if (owner.session !== session || owner.pid !== process.pid) return;
      for (const name of mailbox) await fs.unlink(this.file(name)).catch(e => { if (!absent(e)) throw e; });
      await fs.unlink(this.file("bridge-owner.json"));
      await fs.unlink(this.file(`owner-session-${session}.json`)).catch(e => { if (!absent(e)) throw e; });
    });
  }
}
