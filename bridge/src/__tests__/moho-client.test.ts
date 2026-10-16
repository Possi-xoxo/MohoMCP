import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { MohoClient } from "../moho-client.js";
vi.mock("../keep-alive.js", () => ({ startKeepAlive: vi.fn(), stopKeepAlive: vi.fn() }));
vi.mock("../ownership.js", async importOriginal => {
  const actual = await importOriginal<typeof import("../ownership.js")>();
  return { ...actual, Ownership: class extends actual.Ownership {
    constructor(dir: string) { super(dir, async () => ({birth:"123", executable:process.execPath})); }
  }};
});
let dir = "";
vi.mock("../config.js", () => ({ config: { moho: {
  get ipcDir() { return dir; }, pollInterval: 2, requestTimeout: 150,
} } }));
type Request = { id: string; session: string; serverId: string; method: string; params: Record<string, unknown> };
let timer: ReturnType<typeof setInterval>;
let clients: MohoClient[];
let epoch: string;
let requests: Request[];
let transform: (r: Request) => Record<string, unknown> | null;
const file = (name: string) => path.join(dir, name);
function status() { fs.writeFileSync(file("status.json"), JSON.stringify({running:true, ipcVersion:2, serverId:epoch})); }
function client() { const c = new MohoClient(); clients.push(c); return c; }
function poll() {
  if (!fs.existsSync(file("request.json"))) return;
  let r: Request;
  try { r = JSON.parse(fs.readFileSync(file("request.json"), "utf8")) as Request; }
  catch (error) {
    // Windows may observe unlink between exists/read, or a transient sharing violation.
    if (["ENOENT", "EPERM", "EACCES"].includes((error as NodeJS.ErrnoException).code ?? "")) return;
    throw error;
  }
  if (requests.some(p => p.id === r.id)) return;
  requests.push(r);
  const value = r.method === "ipc.ping" ? {result:{alive:true}} : transform(r);
  if (value) {
    fs.writeFileSync(file("response.json.tmp"), JSON.stringify({jsonrpc:"2.0",ipcVersion:2,session:r.session,serverId:epoch,id:r.id,...value}));
    fs.renameSync(file("response.json.tmp"),file("response.json"));
  }
}
beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), "moho ipc test "));
  clients=[]; epoch="server-one"; requests=[]; transform=r=>({result:r.params});
  status(); timer=setInterval(poll,1);
});
afterEach(async () => {
  for (const c of clients) await c.disconnect();
  clearInterval(timer);
  fs.rmSync(dir,{recursive:true,force:true}); // only this test's mkdtemp directory
});

describe("IPC v2 MohoClient", () => {
  it("requires a live challenge, connects idempotently and disconnects", async () => {
    const c=client(); expect(c.isConnected()).toBe(false);
    await Promise.all([c.connect(),c.connect()]);
    expect(requests.filter(r=>r.method==="ipc.ping")).toHaveLength(1);
    expect(c.isConnected()).toBe(true); await c.disconnect(); expect(c.isConnected()).toBe(false);
    expect(fs.existsSync(file("bridge-owner.json"))).toBe(false);
  });
  it("passes 200 sequential requests with unique IDs", async () => {
    const c=client(); await c.connect();
    for(let n=0;n<200;n++) expect(await c.sendRequest("document.getInfo",{n})).toEqual({n});
    expect(new Set(requests.map(r=>r.id)).size).toBe(201);
  });
  it("serializes concurrent requests",async()=>{
    const c=client(); await c.connect();
    expect(await Promise.all(Array.from({length:20},(_,n)=>c.sendRequest("read",{n})))).toEqual(Array.from({length:20},(_,n)=>({n})));
  });
  it("rejects missing status with resolved path/configuration guidance",async()=>{
    fs.unlinkSync(file("status.json")); await expect(client().connect()).rejects.toThrow(/MOHO_MCP_IPC_DIR/);
  });
  it("rejects a legacy plugin without acquiring ownership",async()=>{
    fs.writeFileSync(file("status.json"),JSON.stringify({running:true}));
    await expect(client().connect()).rejects.toThrow(/incompatible IPC/);
    expect(fs.existsSync(file("bridge-owner.json"))).toBe(false);
  });
  it("detects stale status through handshake timeout and releases lock",async()=>{
    clearInterval(timer); await expect(client().connect()).rejects.toThrow(/timed out/);
    expect(fs.existsSync(file("bridge-owner.json"))).toBe(false);
  });
  it("rejects a second live client without removing first ownership",async()=>{
    const a=client(),b=client(); await a.connect();
    const owner=fs.readFileSync(file("bridge-owner.json"),"utf8");
    await expect(b.connect()).rejects.toThrow(/ownership conflict/);
    await b.disconnect(); expect(fs.readFileSync(file("bridge-owner.json"),"utf8")).toBe(owner);
    expect(await a.sendRequest("read",{ok:true})).toEqual({ok:true});
  });
  it("does not steal a crashed or malformed owner's lock",async()=>{
    fs.writeFileSync(file("bridge-owner.json"),"partial owner");
    await expect(client().connect()).rejects.toThrow(/crashed bridge/);
    expect(fs.readFileSync(file("bridge-owner.json"),"utf8")).toBe("partial owner");
  });
  it("bridge restart creates fresh session and ignores leftover response",async()=>{
    const a=client(); await a.connect(); const old=requests[0]; await a.disconnect();
    fs.writeFileSync(file("response.json"),JSON.stringify({jsonrpc:"2.0",...old,result:"stale"}));
    const b=client(); await b.connect(); expect(requests.at(-1)!.session).not.toBe(old.session);
    expect(await b.sendRequest("read",{fresh:true})).toEqual({fresh:true});
  });
  it("reconnect on same object rotates session",async()=>{
    const c=client(); await c.connect(); const s=requests[0].session;
    await c.disconnect(); await c.connect(); expect(requests.at(-1)!.session).not.toBe(s);
  });
  it("server restart is detected and explicit reconnect succeeds",async()=>{
    const c=client(); await c.connect(); epoch="server-two"; status();
    await expect(c.sendRequest("read")).rejects.toThrow(/restarted/);
    expect(c.isConnected()).toBe(false); await c.connect(); expect(await c.sendRequest("read")).toEqual({});
  });
  it.each(["id","session","serverId"])("rejects mismatched %s",async key=>{
    const c=client(); await c.connect(); transform=()=>({result:"wrong",[key]:"stale"});
    await expect(c.sendRequest("read")).rejects.toThrow(/Mismatched/);
  });
  it("rejects ambiguous result/error envelopes",async()=>{
    const c=client(); await c.connect(); transform=()=>({result:1,error:{code:1,message:"bad"}});
    await expect(c.sendRequest("read")).rejects.toThrow(/Invalid IPC response/);
  });
  it("propagates application errors",async()=>{
    const c=client(); await c.connect(); transform=()=>({error:{code:-32602,message:"bad params"}});
    await expect(c.sendRequest("read")).rejects.toThrow(/bad params/);
  });
  it("times out and removes request without automatic replay",async()=>{
    const c=client(); await c.connect(); transform=()=>null;
    await expect(c.sendRequest("write",{},{timeout:30})).rejects.toThrow(/Outcome unknown/);
    expect(requests.filter(r=>r.method==="write")).toHaveLength(1);
    expect(fs.existsSync(file("request.json"))).toBe(false);
  });
  it("disconnect cancels in-flight and queued requests before releasing ownership",async()=>{
    const c=client(); await c.connect(); transform=()=>null;
    const results=Promise.allSettled([c.sendRequest("first"),c.sendRequest("second")]);
    await new Promise(r=>setTimeout(r,10)); await c.disconnect();
    expect((await results).every(r=>r.status==="rejected")).toBe(true);
    expect(fs.existsSync(file("bridge-owner.json"))).toBe(false);
  });
  it("rejects calls before connection",async()=>{await expect(client().sendRequest("read")).rejects.toThrow(/Not connected/);});
  it("disconnect during handshake cancels connection and cleans ownership",async()=>{
    clearInterval(timer); const c=client();
    const opening=c.connect(); const rejected=expect(opening).rejects.toThrow(/cancelled/);
    await new Promise(r=>setTimeout(r,15)); await c.disconnect(); await rejected;
    expect(c.isConnected()).toBe(false); expect(fs.existsSync(file("bridge-owner.json"))).toBe(false);
  });
  it("reports a plugin directory mismatch",async()=>{
    fs.writeFileSync(file("status.json"),JSON.stringify({running:true,ipcVersion:2,serverId:epoch,ipcDir:path.join(dir,'wrong')}));
    await expect(client().connect()).rejects.toThrow(/directory mismatch/);
  });
  it("rejects malformed response JSON and requires reconnect",async()=>{
    const c=client(); await c.connect(); clearInterval(timer);
    const pending=c.sendRequest("read");const rejected=expect(pending).rejects.toThrow();
    await new Promise(r=>setTimeout(r,10));fs.writeFileSync(file("response.json"),"{broken");
    await rejected;expect(c.isConnected()).toBe(false);
  });
});
