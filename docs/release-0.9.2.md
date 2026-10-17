# Release 0.9.2 — attachment inspection frame API

Live read-only attachment inspection on 0.9.1 failed before mutation because
Document:CurrentFrame() does not exist in Moho 14.5. The shipped
Tool/lm_transform_bone.lua uses ScriptInterface.frame. Attachment validation now
requires moho.frame == 0 and rejects absent/nonzero values. Document metadata also
uses moho.frame and reports unavailable rather than silently substituting zero.
The earlier metadata response of frame 0 alone was not reliable frame evidence.

Complete 0.9.2 release was installed through the unified updater after approval.
IPC remains v2. Installed-file verification and MCP discovery succeeded. New
regressions remove the fictional document accessor and cover missing/nonzero frame
handling. Lua: 364 passed. Node: 122 passed. Deployment: 18 passed. TypeScript
build passed.

Live attachment inspection and the separately approved three-binding transaction
succeeded on Moho Pro 14.5. The user confirmed alignment and responsiveness. A
separately approved Arm_Right +5-degree animation test succeeded, including artwork
following the bone. Three manual Undo actions removed its three test keys while
preserving all bindings and frame 0. The project was not saved. Binding-operation
Undo itself remains untested. Full evidence and limitations are documented in
[Pass 9.1](implementation-pass-9-1.md).

New installations should expose attachment inspection first and enable guarded
attachment writes only after explicit approval. Preserve existing tool restrictions,
private IPC permissions and the focus-retention fix. Use unified Update for a
complete matching release rather than copying individual modules.
