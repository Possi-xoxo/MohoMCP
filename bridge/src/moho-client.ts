/** IPC v2: one exclusively owned mailbox, serialized calls, correlated replies. */
import fs from "node:fs";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { config } from "./config.js";
import { Ownership } from "./ownership.js";
import { parseResponse } from "./protocol.js";
import { startKeepAlive, stopKeepAlive } from "./keep-alive.js";
import { ipcTrace } from "./ipc-trace.js";
import { TOOLKIT_VERSION, assertWriteCompatibility } from './compatibility.js';

export class MohoClient {
  private session: string | null = null;
  private serverId = "";
  private ready = false;
  private connecting: Promise<void> | null = null;
  private closing: Promise<void> | null = null;
  private queue: Promise<unknown> = Promise.resolve();
  private ipcDir = "";
  private generation = 0;
  private file(name: string): string { return path.join(this.ipcDir, name); }

  isConnected(): boolean { return this.ready; }

  async connect(): Promise<void> {
    if (this.closing) await this.closing;
    if (this.ready) return;
    if (this.connecting) return this.connecting;
    // Retire ownership left by a detected server restart before reconnecting.
    if (this.session) await this.disconnect();
    if (this.connecting) return this.connecting;
    this.connecting = this.open(this.generation);
    try { await this.connecting; } finally { this.connecting = null; }
  }

  private async open(generation: number): Promise<void> {
    this.ipcDir = config.moho.ipcDir;
    await fs.promises.mkdir(this.ipcDir, { recursive: true });
    let status;
    try { status = JSON.parse(await fs.promises.readFile(this.file("status.json"), "utf8")); }
    catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") {
        throw new Error(`No status file found at ${this.file("status.json")}. Start the MohoMCP server; verify MOHO_MCP_IPC_DIR/TEMP in both processes.`);
      }
      throw error;
    }
    if (status.running !== true || status.ipcVersion !== 2 || typeof status.serverId !== "string" || !status.serverId) {
      throw new Error("MOHO server is stopped or uses incompatible IPC. Install both Pass 2 bridge and plugin (IPC v2).");
    }
    if (typeof status.ipcDir === "string") {
      const normalize = (p: string) => process.platform === "win32" ? path.resolve(p).toLowerCase() : path.resolve(p);
      if (normalize(status.ipcDir) !== normalize(this.ipcDir)) throw new Error(`IPC directory mismatch: plugin reports ${status.ipcDir}, bridge uses ${this.ipcDir}`);
    }
    if (generation !== this.generation) throw new Error("Connection cancelled");
    const session = randomUUID();
    await new Ownership(this.ipcDir).acquire(session, status.serverId);
    this.session = session;
    this.serverId = status.serverId;
    try {
      if (generation !== this.generation) throw new Error("Connection cancelled");
      startKeepAlive(this.ipcDir, session, this.serverId);
      // A challenge establishes liveness; status.json alone cannot do so.
      await this.enqueue("ipc.ping", {}, config.moho.requestTimeout, session);
      if (this.session !== session) throw new Error("Connection cancelled");
      this.ready = true;
    } catch (error) {
      this.ready = false;
      if (this.session === session) this.session = null;
      await this.release(session);
      throw error;
    }
  }

  disconnect(): Promise<void> {
    if (this.closing) return this.closing;
    this.ready = false;
    this.generation++;
    const session = this.session;
    this.session = null;
    this.closing = (async () => {
      await this.connecting?.catch(() => {});
      await this.queue.catch(() => {});
      if (!session) return;
      await this.release(session);
    })().finally(() => { this.closing = null; });
    return this.closing;
  }

  private async release(session: string): Promise<void> {
      stopKeepAlive();
      await new Ownership(this.ipcDir).release(session);
  }

  async sendRequest(method: string, params: Record<string, unknown> = {}, options?: { timeout?: number }): Promise<unknown> {
    if (!this.ready || !this.session) throw new Error("Not connected to MOHO");
    return this.enqueue(method, params, options?.timeout ?? config.moho.requestTimeout, this.session);
  }

  private enqueue(method: string, params: Record<string, unknown>, timeout: number, session: string): Promise<unknown> {
    const result = this.queue.then(() => this.exchange(method, params, timeout, session));
    this.queue = result.catch(() => {});
    return result;
  }

  private async exchange(method: string, params: Record<string, unknown>, timeout: number, session: string): Promise<unknown> {
    const id = randomUUID();
    const deadline = Date.now() + timeout;
    const trace=(event:string,extra:Record<string,unknown>={})=>ipcTrace(this.ipcDir,event,{id,method,session,serverId:this.serverId,...extra});
    const check = async () => {
      if (this.session !== session) throw new Error("IPC request cancelled by disconnect");
      let status;
      try { status = JSON.parse(await fs.promises.readFile(this.file("status.json"), "utf8")); }
      catch { this.ready = false; throw new Error(`MOHO status missing or invalid at ${this.ipcDir}; server stopped/restarted or IPC directory changed`); }
      if (status.running !== true || status.serverId !== this.serverId || status.ipcVersion !== 2) {
        this.ready = false;
        throw new Error("MOHO server restarted or stopped. Disconnect and reconnect; mutation outcome may be unknown.");
      }
      let owner;
      assertWriteCompatibility(method, status.toolkitVersion);
      try { owner = JSON.parse(await fs.promises.readFile(this.file("bridge-owner.json"), "utf8")); }
      catch { this.ready = false; throw new Error("IPC ownership missing or invalid; disconnect and recover explicitly"); }
      if (owner.session !== session) { this.ready = false; throw new Error("IPC ownership changed"); }
    };
    await check();
    await fs.promises.unlink(this.file("response.json")).catch(error => { if (error.code !== "ENOENT") throw error; });
    const request = { jsonrpc: "2.0", ipcVersion: 2, toolkitVersion: TOOLKIT_VERSION, serverId: this.serverId, session, id, method, params, expiresAt: deadline };
    await fs.promises.writeFile(this.file("request.json.tmp"), JSON.stringify(request));
    await fs.promises.rename(this.file("request.json.tmp"), this.file("request.json"));
    trace('published',{deadline});
    let validResponse = false;
    try {
      while (true) {
        await check();
        let raw: string | undefined;
        try { raw = await fs.promises.readFile(this.file("response.json"), "utf8"); }
        catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
        if (raw !== undefined) {
          const envelope = JSON.parse(raw);
          if (envelope.session !== session || envelope.serverId !== this.serverId || envelope.id !== id || envelope.ipcVersion !== 2) {
            trace('response_rejected');
            throw new Error("Mismatched IPC response ID, session, or server instance; response rejected");
          }
          const response = parseResponse(raw);
          const hasResult = Object.hasOwn(envelope, "result");
          const hasError = Object.hasOwn(envelope, "error");
          if (hasResult === hasError || (hasError && (!response.error || typeof response.error.code !== "number" || typeof response.error.message !== "string"))) {
            throw new Error("Invalid IPC response result/error envelope");
          }
          validResponse = true;
          trace('response_received',{errorCode:response.error?.code});
          if (response.error) throw new Error(`MOHO error [${response.error.code}]: ${response.error.message}`);
          return response.result;
        }
        if (Date.now() >= deadline) { trace('timeout'); throw new Error(`Request ${method} timed out after ${timeout}ms at ${this.ipcDir}. Server status may be stale or polling stopped. Outcome unknown; do not retry writes automatically.`); }
        await new Promise(resolve => setTimeout(resolve, config.moho.pollInterval));
      }
    } catch(error) {
      trace('exchange_failed',{message:String(error).slice(0,400)});
      throw error;
    } finally {
      if (!validResponse) this.ready = false;
      await fs.promises.unlink(this.file("request.json")).catch(() => {});
      await fs.promises.unlink(this.file("response.json")).catch(() => {});
      trace('cleanup',{validResponse});
    }
  }
}
