import { describe, it, expect, beforeEach, afterEach } from "vitest";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { Ownership, type Probe } from "../ownership.js";
let dir: string;
const identity = {birth:"123456",executable:process.execPath};
const file = (n: string) => path.join(dir,n);
const alive: Probe = async () => identity;
beforeEach(async()=>{dir=await fs.mkdtemp(path.join(os.tmpdir(),"moho owner "));});
afterEach(async()=>{await fs.rm(dir,{recursive:true,force:true});});
async function abandoned() {
  const session=randomUUID(); await new Ownership(dir,alive).acquire(session,"epoch");
  return {session,raw:await fs.readFile(file("bridge-owner.json"),"utf8")};
}
describe.skipIf(process.platform!=="win32")("verified ownership recovery",()=>{
  it("recovers complete dead-owner state, rotates session and discards only correlated mail",async()=>{
    const old=await abandoned();
    await fs.writeFile(file("response.json"),JSON.stringify({ipcVersion:2,session:old.session,serverId:"epoch",id:"old",result:1}));
    let calls=0;const probe: Probe=async()=>++calls===1?identity:null;
    const session=randomUUID();await new Ownership(dir,probe).acquire(session,"new-epoch");
    expect(JSON.parse(await fs.readFile(file("bridge-owner.json"),"utf8")).session).toBe(session);
    await expect(fs.stat(file("response.json"))).rejects.toThrow();
    expect(calls).toBe(3);
  });
  it.each([identity,{birth:"999",executable:process.execPath}])("never takes a live PID including PID reuse",async current=>{
    const old=await abandoned();await expect(new Ownership(dir,async()=>current).acquire(randomUUID(),"epoch")).rejects.toThrow(/ownership conflict/);
    expect(await fs.readFile(file("bridge-owner.json"),"utf8")).toBe(old.raw);
  });
  it("fails closed when process inspection is denied",async()=>{
    const old=await abandoned();let calls=0;
    await expect(new Ownership(dir,async()=>{if(++calls===1)return identity;throw Error("access denied");}).acquire(randomUUID(),"epoch")).rejects.toThrow(/access denied/);
    expect(await fs.readFile(file("bridge-owner.json"),"utf8")).toBe(old.raw);
  });
  it.each(["receipt","mailbox","legacy","partial"])("does not recover ambiguous %s",async kind=>{
    const old=await abandoned();
    if(kind==="receipt")await fs.unlink(file(`owner-session-${old.session}.json`));
    if(kind==="mailbox")await fs.writeFile(file("request.json"),JSON.stringify({session:randomUUID(),serverId:"epoch",ipcVersion:2}));
    if(kind==="legacy")await fs.writeFile(file("bridge-owner.json"),JSON.stringify({pid:123,session:old.session}));
    if(kind==="partial")await fs.writeFile(file("bridge-owner.json"),"{");
    let calls=0;await expect(new Ownership(dir,async()=>++calls===1?identity:null).acquire(randomUUID(),"epoch")).rejects.toThrow(/ownership conflict/);
    expect(await fs.stat(file("bridge-owner.json"))).toBeTruthy();
  });
  it("rechecks liveness before removal",async()=>{
    const old=await abandoned();let calls=0;
    await expect(new Ownership(dir,async()=>++calls===2?null:identity).acquire(randomUUID(),"epoch")).rejects.toThrow();
    expect(await fs.readFile(file("bridge-owner.json"),"utf8")).toBe(old.raw);
  });
  it("serializes competing acquisitions so exactly one wins",async()=>{
    const sessions=[randomUUID(),randomUUID()];
    const results=await Promise.allSettled(sessions.map(s=>new Ownership(dir,alive).acquire(s,"epoch")));
    expect(results.filter(r=>r.status==="fulfilled")).toHaveLength(1);
  });
  it("a foreign release cannot remove another session",async()=>{
    const old=await abandoned();await new Ownership(dir,alive).release(randomUUID());
    expect(await fs.readFile(file("bridge-owner.json"),"utf8")).toBe(old.raw);
  });
  it("interrupted transition fails closed and never steals the guard",async()=>{
    await fs.mkdir(file("ownership-transition"));
    await expect(new Ownership(dir,alive).acquire(randomUUID(),"epoch")).rejects.toThrow(/transition/);
    expect((await fs.stat(file("ownership-transition"))).isDirectory()).toBe(true);
  });
});
