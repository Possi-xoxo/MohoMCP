import fs from 'node:fs';
import path from 'node:path';
/** Best-effort, bounded diagnostics. No request parameters or approval contents. */
export function ipcTrace(dir:string,event:string,fields:Record<string,unknown>={}):void {
  try {
    const file=path.join(dir,'bridge-trace.jsonl');
    if(fs.existsSync(file)&&fs.statSync(file).size>=1048576){
      const previous=file+'.previous';
      if(fs.existsSync(previous))fs.unlinkSync(previous);
      fs.renameSync(file,previous);
    }
    fs.appendFileSync(file,JSON.stringify({timeMs:Date.now(),source:'bridge',event,...fields})+'\n');
  }catch{/* Diagnostics must not change request semantics. */}
}
