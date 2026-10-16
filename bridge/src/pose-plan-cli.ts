/** node dist/pose-plan-cli.js pose.json inspection.json [cycle.json]
 * inspection.json: {document: document_getInfo result, rig: rigInspection result}
 * Writes a REVIEW-ONLY plan to stdout, never to IPC. The session is deliberately absent.
 */
import {readFileSync} from 'node:fs';
import {compilePose,compileCycle} from './pose-planner.js';
try {
 const [posePath,inspectionPath,cyclePath,...extra]=process.argv.slice(2);
 if(!posePath||!inspectionPath||extra.length)throw Error('Usage: pose-plan-cli pose.json inspection.json [cycle.json]');
 const read=(p:string)=>{const text=readFileSync(p,'utf8');if(Buffer.byteLength(text)>262144)throw Error('Input too large');return JSON.parse(text);};
 const pose=read(posePath),{document,rig}=read(inspectionPath),now=Math.floor(Date.now()/1000);
 const plan=cyclePath?compileCycle(pose,read(cyclePath),document,rig,now):compilePose(pose,document,rig,now);
 process.stdout.write(JSON.stringify(plan,null,2)+'\n');
}catch(e){process.stderr.write(String(e)+'\n');process.exitCode=1;}
