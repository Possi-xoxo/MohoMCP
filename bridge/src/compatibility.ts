export const TOOLKIT_VERSION = '0.9.2';
export const READ_METHODS = new Set(['ipc.ping','document.getInfo','document.getLayers','layer.getProperties','layer.getChildren','layer.getBones','bone.getProperties','animation.getKeyframes','animation.getFrameState','mesh.getPoints','mesh.getShapes','attachment.inspect']);
export function assertWriteCompatibility(method:string, plugin:unknown):void {
 if (!READ_METHODS.has(method) && plugin !== TOOLKIT_VERSION) throw new Error(`Toolkit mismatch: bridge ${TOOLKIT_VERSION}, Lua ${String(plugin)}. Install a complete matching release and restart both before writes.`);
}
