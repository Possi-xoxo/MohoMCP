# Pass 8 — pose planning

Status: offline planner implemented and tested; relaxed pose and breathing playback await separate live approvals. No Pass 8 document writes, installed plugin changes, or saves have occurred.

## Representation and application

`bridge/src/pose-planner.ts` exports strict JSON validation, capturePose, compilePose, compileCycle and verifyReadback. Pose version 1 stores a descriptive name, designated animation frame, document path, layer identity, semantic roles, unique actual bone names, named parents, neutral/setup geometry and a SHA-256 binding fingerprint. Rotations are degrees relative to neutral. Numeric bone IDs are resolved from each fresh inspection rather than persisted in pose bindings. Renames, ambiguous names, changed parentage or geometry require explicit remapping; do not silently rebind a different character. Layer ID and document path remain part of this conservative binding. Persistent bindings are not proof against a document replacement with identical geometry; the Lua transaction additionally binds the fresh session, inspection and native object identities.

The planner emits review-only version-4 coordinated plans (2–72 operations across at least two bones). No IPC session or ownership is added by the planner, and neither the library nor CLI publishes an approval or calls Moho. Application requires explicit user approval, fresh document/rig readback, a session-bound ephemeral approval in private IPC, and the existing bone_setTransform anchor. Remove authorization after the one attempt; read back before any retry. Preserve all existing MCP tool schemas and filters. No batch, screenshots or input automation is required.

Only finite rotation offsets within ±90 degrees are accepted. Translation is deliberately unsupported and unknown pose fields are rejected. Frame zero, unsupported controllers, bad hierarchies and wrong playback ranges fail before planning. One coordinated transaction gives the existing one-Undo behavior; Pass 8 itself still needs live verification. Existing keys whose angle already matches are left completely untouched. Other existing keys are rejected, including smooth keys: the current inspection does not expose every interpolation parameter. No existing curve is silently reset.

## Files and usage

- `bridge/src/pose-planner.ts`: offline library.
- `bridge/src/pose-plan-cli.ts`: read pose and live inspection JSON, emit review-only plan to stdout.
- `bridge/src/__tests__/pose-planner.test.ts`: focused regressions.
- This document.

Compile normally with `npm run build`, or to an isolated output while the bridge is active. Run `node <build>/pose-plan-cli.js pose.json inspection.json [cycle.json]`. Inspection JSON has `{document: <document_getInfo result>, rig: <rigInspection result>}`. Inspect again after expiration. JSON output may be saved beside a project; it never saves or modifies the `.moho` file. Machine-specific prepared poses and snapshots are kept outside the repository in the task's outputs folder, not committed.

Six prepared examples are Neutral, Relaxed Standing, Breathing In, Breathing Out, Weight Shift Left and Weight Shift Right. Weight shifts are rotation-only previews, not planted-foot or center-of-mass solutions; they have not been approved or visually validated. Left/right labels follow the user's bone names, not assumed screen-side conventions.

## Live plan prepared from the disposable rig

The ten-bone rig has one torso root, head, two upper-arm/forearm branches, and two thigh/shin branches. All controller checks passed; all channels had only frame-zero angle keys after Pass 7 Undo. 24 FPS, frames 1–48. The proposed relaxed stance uses ten frame-1 keys and leaves setup untouched:

- Left Bicep: −65.7536447606° relative to its inspected neutral.
- Right bicep: +60.4957581071°.
- Left Forearm: −8°; Right Forarm: +8°.
- Torso, head, thighs and shins: neutral (0° offsets).

Forward-angle sums from the inspected local hierarchy place the upper arms at approximately −78° and −103° in the layer plane. This is a geometric proposal, not a claim of visual approval or collision-free character artwork. The neutral torso/head/legs are already upright/downward as appropriate. Verify the lowering directions visually before proceeding to idle.

After visual acceptance, the breathing-cycle definition proposes torso ±0.35°, head ∓0.25° delayed one frame, asymmetric arms up to 0.45° delayed 2–4 frames, and legs no more than 0.05°. Peaks use different frames; each track returns to the exact baseline at 48. The frame-1 pose keys are reused unchanged; forty new keys are expected. Smooth mode is verified, but endpoint equality does not prove a seamless velocity curve. User playback review is required. No torso translation/scaling or anatomically modeled respiration is implied.

## Refinement and curve safety

Amplitude, per-role phase delay, baseline offsets and cycle length are editable JSON inputs. For a slower cycle, the user first sets the desired playback end; the planner never changes document settings. A subset of at least two tracks can be planned without targeting other channels. A single-track transaction is unsupported by the existing coordinated guard and is rejected rather than padded with unrelated edits.

Automatic in-place replacement is intentionally blocked pending full interpolation introspection. Supported safe live refinement procedure:

1. Stop playback and confirm the immediately preceding edit is our cycle, with no intervening document edits.
2. User performs Undo exactly once. Never blindly Undo after unrelated edits.
3. Read back every bone and verify the exact baseline from before that transaction, including all unrelated keys/geometry. If it differs, stop; do not overwrite it.
4. Adjust only requested cycle parameters; recompile from a fresh inspection; obtain approval and apply the revised transaction. No Moho restart is required.

This is a manual Undo-assisted revision workflow, not completed automatic selective replacement support. If unrelated edits intervene, preserve them and defer revision until curve-safe replacement is available. Keep the accepted relaxed stance as its own transaction so Undo of the cycle preserves it.

## Validation

Isolated TypeScript build passed. Node: 109 passed, including 24 new planner tests. Lua: 308 passed. An initial sandboxed Node run encountered EPERM temporary-mailbox rename failures; the complete rerun outside that sandbox passed with no test or production IPC modifications. No live helper/UI activity was exercised by automated tests.

New tests cover semantic mapping with reordered numeric IDs, duplicate names, stale geometry/parents, cycles, expired inspections, wrong documents, unsupported translations/controllers, corrupt fingerprints, zero frames/nonfinite values, preserved baseline curves, fail-closed replacements, delayed/asymmetric endpoints, refinement after baseline restoration, range limits and full key readback corruption detection.

During preparation two read-only heartbeat requests timed out; subsequent bone and document reads recovered without a restart. Cause was not established. No mutation was attempted during those timeouts. Preserve the quiet-refresh behavior; do not reintroduce synthetic mouse movement to avoid deferred reads.

No Lua update or app restart is required for this planner. The live bridge retains the verified focus fix and Pass 7 transaction implementation. Live pose acceptance, idle quality, Pass 8 Undo and refinement remain pending.
