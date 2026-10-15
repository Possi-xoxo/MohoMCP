# Pass 6: coordinated bone animation

## Implementation status

Implemented and automated-tested, awaiting installation approval and live validation. The user's new disposable project is Two Bone Test in the Projects folder; its full extension, active document, hierarchy and pose must be verified after reconnect. Two attempted read-only queries timed out during preparation, suggesting polling was inactive; no live writes were attempted.

## Narrow transaction

The existing bone_getProperties output adds rigInspection for exactly two connected bones in one layer. It reports fresh identities, names, parents, lengths, rest positions/angles, neutral channel values, full rotation-key lists and interpolation modes. A five-minute inspection token binds the document, layer, skeleton, bones and channel snapshot. Any read of either bone refreshes this single token; always use the latest one.

A version-3 local write-approval.json binds the bridge session, Lua epoch, absolute saved document path, current token and an exact list of 2–16 angle-key operations. Each operation specifies layerId, boneId, frame, absolute angle and boolean replace. Both bones must be represented. The existing bone_setTransform call must match the first approved operation and triggers the entire bounded transaction. This is explicit sidecar transaction semantics; no arbitrary method dispatch, new MCP tool, or unrestricted batch is enabled. All existing tool names and input schemas remain unchanged. Tool descriptions now explain this behavior and no longer advise unrestricted batching.

Every operation is checked before PrepUndo or a channel mutation: finite values, integer IDs/frames, range, +/-4pi bound, positive bone lengths, a root/child hierarchy, unchanged neutral pose and full key snapshot, unlocked selected Mainline layer, zero timing offset, no supported controller/constraint flags, no duplicate targets and no frame-0 writes. Existing keys require replace=true in the explicitly approved plan; default first-animation plans set false. Other keyframes are retained. Angle values are computed relative to each verified neutral channel value, never assumed world-space angles.

One PrepUndo(layer,true) is called for the logical transaction. The eight requested keys use SetValue then SetKeyInterp(frame,MOHO.INTERP_SMOOTH,0.1,0.5), a signature found in shipped Moho scripts. Full frame/value/interpolation-mode readback verifies the result and unchanged other keys. Each affected prior key's interpolation settings are captured for rollback. On failure, every attempted operation is restored in reverse order; one restoration failure does not prevent subsequent restoration attempts. Both channels are verified afterward. Errors distinguish successful rollback from ROLLBACK FAILED. The token is consumed before undo/mutation, preventing automatic replay. No save is performed.

Limitations: a native crash cannot be caught; interpolation-mode readback does not compare every interpolation parameter; Lua identity strings do not absolutely prevent native address reuse after identical object replacement. Avoid manual edits/document switching during a transaction. Unexpected state fails closed. Exactly two connected bones are supported in this pass; extending to larger rigs is deferred.

## Undo and existing-key verification

Pass 5 verified creation/movement and user-visible playback, but the user pressed Undo more than once. It did not prove one logical edit per Undo or live replacement. Mock tests cannot settle these questions. Shipped lm_transform_bone.lua uses PrepUndo(layer,true); no speculative changes to its signature are made.

Before the coordinated animation, obtain explicit live-write approval and use one bone on the disposable arm rig:

1. Inspect and create a +20-degree key at frame 12 and a neutral sentinel at 48, using separate exact version-2 approvals.
2. Replace frame 12 with +25 degrees; confirm exactly the same key frames and unchanged sentinel/other bone.
3. User presses Undo exactly once; readback must restore +20 at 12 and retain 48. If it does not, stop and investigate.
4. Move frame 12 to 18; verify 12 absent, 18 present and 48/other bone unchanged.
5. User presses Undo exactly once; verify 12 restored and 18 absent.
6. User undoes the sentinel creation once, verify; user undoes the initial key once, verify. Do not infer stack position without each readback. If more than one edit is reverted, document the limitation and stop before coordinated writes.

No automated Undo/input tool is enabled. Only after the above succeeds, request approval for the complete motion below (or include that exact plan in a single explicit user approval). Maintain fresh inspections between logical edits.

## Motion plan and live procedure

New disposable rig: B1 upper arm/shoulder root, B2 forearm/elbow parented to B1. Both visible lengths, unconstrained, neutral keys only. User sets 24 FPS and end frame 48. Inspect lengths, parents, neutral angles and positions; do not infer that named B1 always has numeric ID 0. Stop on ambiguity.

| Frame | B1 relative to neutral | B2 relative to neutral |
|---|---:|---:|
| 0 | 0 degrees (preserved) | 0 degrees (preserved) |
| 12 | +20 degrees | +35 degrees |
| 24 | +45 degrees | +70 degrees |
| 36 | +20 degrees | +35 degrees |
| 48 | 0 degrees | 0 degrees |

Create eight keys in one approved version-3 transaction. Read back both full channels. Ask user to play/scrub and confirm recognizable bending and responsiveness. Then test exactly one manual Undo and verify all eight keys are reverted together while setup/unrelated animation remains. Restore only with approval after fresh inspection if the user wants to keep the motion. No automatic save. Stop after this articulated test; no full-character work.

## Installation and startup

Approval required before installing moho_mcp/coordinated_write.lua (new) and tools/bone.lua (updated); back up existing files and hash-verify. One normal Moho restart is required for cached Lua modules. Ordinary subsequent edits do not restart Moho. Existing bridge code remains protocol-compatible; rebuilt metadata descriptions appear on next normal Codex restart but no reload is required for the transaction itself. Keep the shared launcher, private IPC ACLs, exclusive ownership, eleven-tool filter and Poller. Screenshots, input and unrestricted batch remain disabled. No installer was executed or global settings changed.

## Files changed in Pass 6

- moho-plugin/moho_mcp/coordinated_write.lua (new)
- moho-plugin/moho_mcp/tools/bone.lua
- moho-plugin/tests/test_coordinated_write.lua (new)
- moho-plugin/tests/run_tests.lua
- bridge/src/index.ts and bridge/src/tools.ts (accurate tool instructions/descriptions only)
- install-plugin.bat and install-plugin.sh (module copy lists)
- docs/implementation-pass-6.md and docs/windows-codex-setup.md

Prior uncommitted Pass 3–5 work is preserved. No commits/pushes or machine-specific config changes.

## Automated results

- Lua: 282 passed, 0 failed; 24 new coordinated tests.
- TypeScript: 77 passed, 0 failed; build passed.
- MCP smoke: 26 tools, two resource reads and expected missing-server error passed without Moho/native helpers.
- Lifecycle: all 11 subprocess scenarios passed.
- git diff --check passed.

Tests cover successful eight-key transactions, one mock undo preparation, unrelated-key/setup preservation, explicit replacements, stale session/document/token/hierarchy/interpolation, bad values/ranges/duplicate targets, constraints, undo-preparation failure, partial second-bone writes, prior-interpolation restoration, readback failure and continuing rollback after a restoration failure.

Live replacement, Undo granularity, two-bone playback and responsiveness: PENDING. Remaining generic mutation, screenshot confinement and input/batch risks from earlier audits are not resolved by this pass and stay outside the enabled workflow.

## Completed live validation

The matching Lua files were installed with backups and SHA-256 verification after user approval. After one installation restart, the shared IPC connection worked; the earlier read timeout did not recur with the server and Poller active. The exact cause of that earlier timeout was not proven.

Verified Two Bone Test.moho at 24 FPS and end frame 48: B1 root length approximately 0.684566, B2 child of B1 length approximately 0.666716, both unconstrained with neutral keys only. Neutral rotations were read from the actual channels rather than assumed zero.

Single-edit checks passed live: created B1 +20 degrees at frame 12 and a neutral sentinel at 48; replaced 12 with +25 without extra keys or changes to B2/sentinel; exactly one manual Undo restored +20. Moved 12 to 18 with angle/interpolation mode and sentinel preserved; exactly one Undo restored 12 and removed 18. Individually undid the sentinel and initial key with readback after each step. Float readback differences after Undo stayed within 1e-6 radians.

The approved coordinated transaction then created eight smooth keys: B1 relative rotations +20/+45/+20/0 and B2 +35/+70/+35/0 at frames 12/24/36/48. Both full channels and interpolation modes were read back successfully. User confirmed correct arm bending and continued responsiveness. Exactly one manual Ctrl+Z removed all eight keys together, preserving both neutral keys, bone lengths and hierarchy. No restart occurred between ordinary edits. No automatic save, production-project mutation or prohibited tool use occurred. Temporary write authorization was removed.

Pass 6 live success criteria are met for this two-bone disposable rig. Current in-memory state is neutral only because the user undid the animation. This does not establish universal Undo behavior across all Moho layer/channel types or complete interpolation-parameter fidelity. Native-crash recovery and larger/constrained rigs remain outside validation.

Recommended next step: review and package the tested changes and repeat a controlled two-bone regression on a copy before expanding scope. Full-character animation requires separate approval; it was not started.
