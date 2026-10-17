# Pass 9.1: guarded rigid artwork binding

Status: implemented, deployed as toolkit 0.9.2, and live-verified on Moho Pro
14.5 after explicit installation, binding and animation approvals. See the live
results below. No project was automatically saved.

## Scope and plan

Existing tool schemas remain intact. Two tools are added: `attachment_inspect`
and `attachment_apply`. Inspection accepts a bone-layer name and 1–3 mappings
with layerName, boneName and expectedBinding. Names resolve afresh; artwork must
be an unambiguous direct child. The intended first mapping is Sweater to Torso,
Right Arm to Arm_Right and Left Arm to Arm_Left. Left/right is anatomical.
Use the actual live rig name (previously `Character Rig`), not a guessed spelling.

Bind the ordinary Sweater group as a unit, retaining its five vector children.
Arms remain whole rigid parts; no elbow deformation or point binding is introduced.
Do not rotate the torso in the first motion test: the head, hair and legs are
outside the initial mapping and would not follow it. Use a small arm rotation.

## API evidence and safety

Installed Moho 14.5 `Tool/lm_bind_layer.lua` uses `PrepMultiUndo(true)` and
`SetLayerParentBone(id)`. `lm_bind_points.lua` reads `LayerParentBone()`.
The installed read-only inspector successfully resolved controlling layer and
parent for all three targets, each reporting -1 (no explicit layer bone).
No synthetic input, recurring refresh, IPC lifecycle or focus changes are made.

The guard requires frame 0 but does not set a frame, origin, transform, geometry,
style or animation key. It checks native document/rig/layer identities, full
connected-rig validation, controllers, unique names, direct parents, ownership,
Mainline/unlocked/zero-offset targets, prior binding and all enumerated layer
transform values and visibility. Existing special binding states are refused.
The full document is bounded to 256 layers, rig to 32 bones and transaction to
three artwork mappings. Conflicting replacements require a new inspection with
an explicit expected previous binding and new approval. One-part corrections are
supported without reattaching other parts.

Inspection returns a short-lived single-use token. Application additionally
requires private `binding-approval.json` with:

    {version:1, kind:"rigid-binding", token, session, serverId,
     expiresAt, documentPath, operations}

Use exactly the resolved operations returned by inspection (including previous
binding), the current owner session/server, and an expiry no later than inspection.
This file is local authorization, never a tracked artifact. Remove it after the
attempt. A consumed token cannot execute again, including after failed mutation.
No automatic retry of timed-out writes is permitted.

All checks precede undo preparation and mutation. Setter attempts are recorded
before invocation. Failure restores prior bindings in reverse order, attempts
every restoration, and verifies the full captured state. Rollback failure is
explicitly reported; stop and inspect before any user-directed Undo. Successful
binding reads back every mapped value plus captured hierarchy, transforms and rig.
No-op mappings do not add undo entries. Group alignment, pixel appearance, full
art/style integrity and one-step UI Undo cannot be certified by these mocks;
visual and manual Undo verification are mandatory. The operation never invokes
artwork/style setters. Transform snapshots compare values, not every interpolation
parameter; the binding operation never edits those channels.

## Validation

Lua: 359 passed, including 20 new transaction tests and 11 read-only inspection
cases. Coverage includes successful group/vector bindings, missing names, duplicate
art names, existing conflicts, stale path/native document, invalid parents,
controllers, transforms, session/expiry/approval mismatch, nonzero frame, setters
that mutate then throw, silent readback failures, rollback failure, undo-preparation
failure, corrections and no-op/replay behavior. Existing rig tests cover duplicate
bones and invalid full hierarchies. TypeScript build passes; final Node results
are recorded below. Automated tests use isolated mocks, not live Moho writes.

## Installation and demonstration

Use the unified deployment workflow to back up and install the complete matching
Lua and managed bridge release; do not deploy individual modules. Expose only
attachment_inspect initially; separately approve attachment_apply before the
first live write. No screenshot/input/batch filter entries are needed. One normal
Moho restart loads Lua; one Codex restart loads bridge tool discovery. Keep the
existing focus-safe Poller and quiet helper unchanged.

Reinspect the disposable working copy at frame 0. Verify exact mappings and
request live approval. Apply once and read back all bindings. Ask the user to
check alignment before any animation. Then obtain separate approval for a small
arm motion, verify channels and playback, and test manual Undo under user control.
Never save automatically or touch the original tutorial project. Keep backups,
private paths, approvals and runtime traces out of version control.

Final Node suite: 119 passed, 0 failed across 8 test files.

## Live verification — 2026-10-16

Tested on the disposable `Disposable_Character_Rig_Test.moho` at frame 0 with
release 0.9.2 and IPC v2. Machine-specific paths, ownership identifiers, approval
tokens, traces and configuration are intentionally excluded from this report.

Fresh inspection resolved the three direct-child targets under `Character Rig`.
All initially had no explicit layer binding (-1). One approved guarded transaction
bound the Sweater group to Torso, Right Arm to Arm_Right and Left Arm to Arm_Left.
Readback verified all three bindings and preserved captured layer transforms,
hierarchy and rig state. The user confirmed correct visual alignment and normal
responsiveness. Sweater retained its five children. Left/right names refer to
character anatomy. No artwork replacement or project save occurred.

After separate approval, fresh inspection found only frame-0 angle keys on the
three-bone rig. Three individually guarded single-edit operations added Arm_Right
keys at frame 1 (neutral), frame 12 (neutral +5 degrees) and frame 24 (neutral).
The neutral local angle was approximately 2.977258921 radians; frame 12 read back
approximately 3.064525366 radians. Every write and complete affected angle channel
was read back. Other bones and frame-0 setup remained unchanged. The right-arm
binding remained intact. The user played/scrubbed the animation and confirmed the
illustrated arm followed the bone correctly and Moho stayed responsive.

Manual Undo was then tested one action at a time with read-only verification:

| Undo action | Removed key | Remaining Arm_Right angle keys | Bindings |
| --- | --- | --- | --- |
| 1 | Frame 24 | 0, 1, 12 | All three intact |
| 2 | Frame 12 | 0, 1 | All three intact |
| 3 | Frame 1 | 0 | All three intact |

Final inspection confirmed the original frame-0 angles, other bones' angle keys,
and all three bindings and artwork transforms. The project remains unsaved with
the bound-artwork baseline restored. No automatic Undo, input automation,
screenshot or unrestricted batch operation was used. Approval sidecars were
removed after each attempted write.

This verifies one Undo per single-key animation edit, not one Undo for the whole
three-key test. The binding transaction's own Undo was deliberately not exercised,
to preserve the bindings, so its live Undo granularity remains unverified. The
coordinated transaction currently requires at least two targeted bones; this
single-bone test used the existing single-edit workflow without expanding scope.
Rigid whole-arm attachment does not demonstrate elbow deformation or full-character
rigging. Further animation requires approval; nothing was saved automatically.

Automated release validation: TypeScript build passed; 122 Node tests, 364 Lua
tests and 18 deployment tests passed. See also release-0.9.2.md and
unified-deployment.md for complete-release installation and recovery.
