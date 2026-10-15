# Pass 4 first-write preparation

Historical preparation notes. Live writes subsequently passed; see implementation-pass-5.md and implementation-pass-6.md for verified outcomes and current limitations.

## Restart verification

The normal Codex restart left the old complete owner record (PID 30296), but that process was absent. The updated bridge automatically recovered it and connected with PID 23692 and a fresh session. Moho PID 7860 and its server epoch remained unchanged. Metadata read succeeded with totalLayers=1. No manual deletion or repeated 200-request run was needed. Moho reported responsive; subjective slowdown/error confirmation remains requested.

## Restricted first-write mode

No live write has been approved or performed. Only bone_setTransform will be enabled after inspecting a dedicated saved disposable rig and receiving explicit approval for the concrete three-pose plan. Other mutation, screenshot, input and batch tools remain disabled. Public MCP names and schemas are unchanged, but Lua now deliberately rejects unsupported bone position/scale/compound writes and generic animation.setKeyframe calls. This is a compatibility restriction for the controlled first demonstration, not a general validation fix for all animation capabilities.

The new safe_write.lua module requires a local write-approval.json in the shared IPC directory. It must bind the exact project path, current bridge session, Lua server epoch, layer/bone IDs and names, an expiry no more than 30 minutes away, and exactly three poses at frames 0/12/24 (neutral, +pi/6, neutral). No approval file is created until the user's explicit first-write approval. It is private machine/session configuration and must not be committed. A restart invalidates the approval.

Every write rechecks project path, selected layer, layer/bone names, lock state, main timeline, zero layer timing offset, absence of angle constraints/control, and unchanged neutral pose. Parameters must be finite, IDs/frames nonnegative integers, frame within the document range, angle within +/-4pi, and exactly match the approved plan. Frame 0 must retain the existing neutral key. Existing nonmatching keys are never overwritten. Matching existing keys are no-ops.

Validation and channel snapshots complete before PrepUndo(layer,true), SetDirty and SetValue. These APIs and action/offset/HasKey accessors were checked against the installed Moho 14.5 scripts, including lm_transform_bone.lua and shipped menu scripts. Immediate HasKey/GetValue readback verifies each new key. Failed writes attempt to delete only the newly inserted key; failed readback/rollback is explicit and blocks further use of that approval. Native crashes cannot be rolled back by Lua. Successfully completed earlier frame calls remain separate undoable edits if a later call fails; there is no three-call transaction or automatic retry.

bone_getProperties now includes bounded angleKeyframes readback (or an explicit angleKeyframesError). It does not move the timeline. The existing animated-current-frame fallback is not relied on to verify this demonstration. Live undo UI behavior, animation playback and all guards still need validation on the disposable rig.

## Automated checks

- Complete Lua suite: 236 passed (46 new safety cases).
- Complete TypeScript suite: 77 passed.
- TypeScript no-emit compilation and diff whitespace checks: passed.
- Tests cover invalid/missing/unsupported values; wrong project, session, epoch and expiry; unexpected poses; selected context, names, actions/offsets/constraints; existing keys; frame-0 protection; undo failure; mutate-then-throw setters; readback failure; rollback failure; and blocked approvals.

## Pending installation and user steps

Create a new saved disposable project with one simple unconstrained bone, no Actions, no layer timing offset, and no animation keys beyond frame 0. Keep frames 0â€“24 available. Save it under a distinct filename. Close Moho normally so safe_write.lua, tools/bone.lua and tools/animation.lua can be installed together with backups. The installer source file lists were updated but no installer was executed.

Relaunch using the shared desktop shortcut, open that rig, start the Lua server and select the poller. Inspect document/layer/bone/key data read-only. Present the exact path, layer, bone, baseline angle and proposed key values to the user. Only after explicit approval should a short-lived session-bound approval file be written and bone_setTransform added to Codex's existing ten-query filter. A Codex reload may change ownership session: create the approval against the final reconnected session, not a prior one.

After approved writes, verify keys 0/12/24 via bone_getProperties and ask the user to play the timeline and inspect undo behavior. Stop on any failure. No other project may be touched. Remaining input/capture, generic transforms, mutation/batch, dependency and document-integrity issues are not declared resolved.
