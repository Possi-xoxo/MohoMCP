import {test,expect} from 'vitest';
import {assertWriteCompatibility,TOOLKIT_VERSION} from '../compatibility.js';
test('legacy/mismatched Lua allows diagnostics but refuses all mutation categories',()=>{
 for(const v of [undefined,'old']){
  expect(()=>assertWriteCompatibility('document.getInfo',v)).not.toThrow();
  for(const method of ['bone.setTransform','attachment.apply','batch.execute','document.setFrame'])expect(()=>assertWriteCompatibility(method,v)).toThrow('Toolkit mismatch');
 }
});
test('matching release permits guarded methods to reach their own approval checks',()=>{expect(()=>assertWriteCompatibility('attachment.apply',TOOLKIT_VERSION)).not.toThrow();});
