# Pass 5: iterative live bone editing

## Scope and status

Implemented and mock-tested; not installed or live-tested in this pass. Pass 4 created B2 angle keys at 12 and 24, retained frame 0, verified readback, and the user confirmed playback. Pass 5 does not change any production project or automatically save a file.

## Workflow

Keep the existing private IPC directory, shared launcher, exclusive bridge ownership, and tool filter (ten queries plus bone_setTransform). Start Moho with the shared launcher, open the disposable project, select its bone layer, start the server once, dismiss the dialog, and select the Poller. No repeated configuration or restart is needed for ordinary edits.

1. Call bone_getProperties. Its new editInspection contains a short-lived token and complete angle-key snapshot. Inspection errors are explicit, never presented as an empty channel.
2. For an authorized exact edit, atomically write a version-2 write-approval.json into the private IPC directory. Bind the current bridge session, server epoch, absolute documentPath, expiry within 30 minutes, and inspection token (valid for five minutes). Read/compare ownership immediately before publication. Never commit this file.
3. Call the existing bone_setTransform with layerId, boneId, destination frame and absolute angle in radians. No public tool schema changes. A move is explicitly declared in the local approval operation, not inferred from the tool call.
4. Read bone_getProperties again and remove the completed approval file. A new inspection/approval is needed for each subsequent exact edit; Codex handles these files within the user's approved scope without another app restart. Token use is consumed before undo/mutation, including failures and no-ops. Never blindly retry a timed-out write: inspect first.

Example approval (placeholders, never an active authorization):

```json
{
  "version": 2,
  "session": "CURRENT_BRIDGE_SESSION",
  "serverId": "CURRENT_SERVER_EPOCH",
  "documentPath": "E:/disposable.moho",
  "expiresAt": 0,
  "token": "FROM_EDIT_INSPECTION",
  "operation": {"kind":"set", "layerId":1, "boneId":0, "frame":12, "angle":0.7853981633974483}
}
```

For a move, use kind=move and fromFrame=12, frame=18, angle equal to the current source key. Destination must be empty. Angles are absolute: a request for 45 degrees relative to neutral means neutral + pi/4, not necessarily pi/4. Version-1 Pass 4 plans remain supported.

## Validation and undo

Only angle edits on unlocked, selected, unconstrained bones on Mainline with zero timing offset are supported. Frame 0 is protected. IDs and frames must be nonnegative finite integers, target within document range, angles finite within +/-4pi. Position/scale, generic animation writes, screenshot, batch, and input remain restricted.

Inspection binds document path, document/layer/bone Lua identity strings, names, skeleton bone count, parent, rest position/length/angle, layer and bone IDs, server epoch and full angle key values. Replaced objects, changed geometry, changed keys, stale sessions or expired tokens fail before undo. Identity-string stability in Moho 14.5 still needs live validation; instability fails closed. These checks are conservative stale-reference detection, not an absolute guarantee against native pointer reuse after identical object replacement. Do not close/reopen documents or manually edit the rig between inspection and write.

One PrepUndo(layer,true) precedes each successful edit. Existing-key interpolation is snapshotted and restored with MOHO.InterpSetting, GetKeyInterp and SetKeyInterp. Moves use native SetKeyWhen(index,frame), preserving the existing key rather than deleting/recreating it. Before/after full channel values are checked; other key values/frames must remain unchanged. Failures attempt exact affected-key restoration, verify values, and consume the token. Rollback failure explicitly requires manual Undo/inspection. Interpolation APIs and native key movement still require live validation; automated readback currently verifies values/frames, not all interpolation fields. Native crashes cannot be rolled back. No auto-save, automated Undo, or hidden document switch occurs.

## Loading and reconnect evidence

MohoMCP_Server.lua retains isLoaded and server references and require caches modules. Installed DrawMe closures retain original callbacks. Reloading tool globals can replace those callbacks while _hooksInstalled remains true. Therefore a generic script reload is NOT a verified safe MohoMCP hot-reload mechanism. This pass deliberately adds no cache-clearing/reload workaround. Use one normal Moho restart after installing changed Lua files; ordinary edits and approval updates need none.

The vendor's older manual describes Lua scripts loaded through the Scripts menu: https://www.lostmarble.com/moho/manual/scriptsmenu.html . It does not establish safe 14.5 module hot reload. Local 14.5 shipped lm_scatterbrush.lua uses SetKeyWhen(index,frame); lm_pantilt_camera.lua uses GetKeyInterp/SetKeyInterp with MOHO.InterpSetting. These are implementation evidence, not a claim that our new operations have been live-tested.

Node's stdio EOF/transport lifecycle and verified ownership recovery already allow bridge restart independently of Moho. New bridge ownership invalidates old write approvals; reconnect, inspect, and generate a fresh plan. Do not launch competing bridges or delete ambiguous ownership files. An initial read after a Lua restart may report the epoch change; a subsequent read reconnects. Never use mutation retries to reconnect.

Polling remains repaint-driven. Existing hooks wrap common editing tools and may permit normal tool selection, but only the selected Poller was live-proven. The Poller itself is not a drawing tool. Confirm hook behavior on Transform Bone in the live demonstration; fall back to Poller if queries time out. Keep Moho visible, dismiss modal dialogs, and do not drag/edit while a remote write is in flight. No new background process, GUI automation, or polling workaround was added.

## Validation

- Lua suite: 258 passed (20 new iterative-edit cases).
- TypeScript: 77 passed, including simulated 200-request test; build passed.
- Lifecycle subprocess suite: all 11 scenarios passed; no Moho or native helpers used.
- Tests exercise replace/repeat/no-op, interpolation retention in mocks, native move, occupied destinations, frame-zero/range protection, stale document/session/token/rig/key data, undo preparation failure, mutate-then-throw rollback and rollback failure.
- No live queries or writes were issued in Pass 5.

## Files changed in Pass 5

- moho-plugin/moho_mcp/iterative_write.lua (new)
- moho-plugin/moho_mcp/tools/bone.lua (inspection, dispatch, actual moho.frame feedback)
- moho-plugin/tests/test_iterative_write.lua (new)
- moho-plugin/tests/run_tests.lua
- install-plugin.bat and install-plugin.sh (module copy lists only; not executed)
- docs/implementation-pass-5.md and docs/windows-codex-setup.md

Earlier Pass 3/4 uncommitted changes are retained. No machine-specific configuration is committed or pushed.

## Proposed live demonstration: approval required

Approve backup/install of iterative_write.lua and tools/bone.lua, followed by a controlled test on the existing Disposable_Bone_test.moho only. Save the disposable animation manually if desired before closing Moho. Perform one restart for these code changes, then keep Moho open.

Inspect B2/Layer 2 and existing 0/12/24 keys; request live write approval for changing frame 12 from neutral+30 to neutral+45, then moving that key to 18. Run each edit with a fresh snapshot, read back full keys, and stop on errors. User plays/scrubs, checks responsiveness, and invokes Undo once to restore the move (12 back, 18 absent); read back. A second user Undo should restore +30 at 12; read back again. Do not automate input or Undo. This demonstrates repeated edits and undo in one Moho session. End by deleting only this test's approval file.

Remaining blockers: live identity stability, interpolation preservation and Undo verification; repaint/tool-switch limitations; generic mutation validation, screenshot path confinement, native input and batch vulnerabilities remain unresolved and disabled. New layers/circle drawing, rigging, exporting, production-project writes and arbitrary transform support are outside this pass.

## Live demonstration results

Pass 5 was installed with backups and tested on the existing disposable bone project after one installation restart. The saved project contained only its neutral frame-0 key, so the user approved creating a +45-degree key at 12 and moving it to 18. Both operations succeeded in the same Moho session. Full channel readback confirmed frames 0/18 and no frame-12 key. The user confirmed correct animation playback and continued responsiveness. No automatic save occurred.

A local approval-file replacement failed once; the old consumed approval caused a write rejection before mutation. Publishing the intended move approval resolved it. Temporary live authorization was removed after the test.

After manual Undo, readback contained frame 0 only. The user reported probably pressing Undo multiple times, so reversal is confirmed but one-edit-per-Undo granularity is not established. Live replacement of an existing key and detailed interpolation preservation remain additional validation items; this demonstration created and moved a key. No production projects or prohibited tools were used.
