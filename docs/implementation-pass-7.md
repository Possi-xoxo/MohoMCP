# Pass 7: multi-bone idle preparation

Status: implemented and automated-tested; NOT installed or live-tested yet. Pass 6's verified two-bone results remain valid. No live queries or writes were issued in this implementation turn. No global configuration, installed plugin or project was changed.

## Implementation

coordinated_write.lua now inspects a connected hierarchy of 2–12 bones. Exactly one root is required; every parent is an in-range integer, self-parenting and cycles are rejected. Parent IDs need not precede children; root IDs need not be zero. Names are labels only, never an ID lookup assumption. Full bone count, names, setup geometry, parents, identity strings, neutral keys and angle-key/interpolation-mode snapshots are compared immediately before writing. Full-rig readback includes untargeted branches. Read-only rigInspection on the existing bone_getProperties tool reports every bone and controller-check status/errors; no new MCP tool is needed.

Version-3 approvals preserve Pass 6 limits (two bones, up to 16 operations). Version 4 permits 2–72 exact angle-key operations across at least two bones in a rig of up to 12. Every intended edit is checked before a single PrepUndo(layer,true). Existing keys require replace=true. Frame 0 cannot be written. All previous value/range/session/expiry/document/selection checks remain. The first approved operation is the explicit bone_setTransform anchor for the transaction; no arbitrary batch method is exposed. Approval JSON is bounded to 32 KiB.

Version 4 also binds fps/startFrame/endFrame and strictly rejects controllers using Moho's fAngleControlParent, fPosControlParent, fScaleControlParent fields, targets (including animated target keys), dynamics, IK locks (including animated lock keys), fixed/ignored-IK/constraint flags, and animated reparenting. Those API names were verified in installed lm_manipulate_bones.lua, lm_reparent_bone.lua and lm_select_bone.lua. Missing/unknown controller APIs fail closed and may need live compatibility diagnosis. The older version-3 path retains existing behavior for compatibility; it does not gain all version-4 controller checks.

One logical transaction still has one Undo preparation. Each attempted write is recorded before calling its setter. On failure, all attempted keys are restored in reverse order, including interpolation snapshots for replaced keys; rollback continues after individual failures. Readback checks all rig angle channels, frames, values and interpolation modes. Token consumption prevents blind replay. No save occurs.

Identity strings and fresh snapshots are conservative stale-reference detection, not a mathematical guarantee against native address reuse. Do not switch documents or manually edit the rig during a write. Native crashes cannot be rolled back. Full interpolation-parameter fidelity beyond mode is not independently compared. Live multi-bone Undo and performance remain to be tested.

## User rig guide (no automatic rigging)

Create a NEW disposable project, one bone layer, frame 0. Arrange a simple front-facing stick-person skeleton, with visible nonzero lengths and a relaxed neutral pose. Do not add artwork, targets, constraints, controllers, dynamics, IK locks, smart-bone Actions, timing offsets or keys beyond frame 0. Suggested ten unique names and parents:

| Bone | Parent | Placement |
|---|---|---|
| Torso | none | Hip center toward shoulders |
| Head | Torso | Neck toward head |
| UpperArm_L | Torso | Left shoulder toward elbow |
| Forearm_L | UpperArm_L | Elbow toward wrist |
| UpperArm_R | Torso | Right shoulder toward elbow |
| Forearm_R | UpperArm_R | Elbow toward wrist |
| Thigh_L | Torso | Left hip toward knee |
| Shin_L | Thigh_L | Knee toward ankle |
| Thigh_R | Torso | Right hip toward knee |
| Shin_R | Thigh_R | Knee toward ankle |

Use Moho's normal bone tools to draw/reparent and check the parent arrows. The torso is the sole root; branching children may start at the anatomically appropriate location along it. Set 24 FPS, start frame 1, end frame 48. Save under a NEW disposable filename and provide its full path. We inspect the actual IDs, names, parents, lengths, neutral angles and all existing keys; this table does not substitute for inspection. Up to two additional connected bones may be left unanimated or mapped only after review.

## Proposed idle (requires exact live approval)

Use five samples per animated bone at frames 1/12/24/36/48, relative to each bone's measured neutral angle. Proposed degree offsets:

| Bone | 1 | 12 | 24 | 36 | 48 |
|---|---:|---:|---:|---:|---:|
| Torso | 0 | +1 | 0 | -1 | 0 |
| Head | 0 | -0.7 | 0 | +0.7 | 0 |
| UpperArm_L | 0 | +1.5 | 0 | -1.5 | 0 |
| Forearm_L | 0 | +1 | 0 | -1 | 0 |
| UpperArm_R | 0 | -1.5 | 0 | +1.5 | 0 |
| Forearm_R | 0 | -1 | 0 | +1 | 0 |
| Thigh_L | 0 | +0.25 | 0 | -0.25 | 0 |
| Shin_L | 0 | -0.25 | 0 | +0.25 | 0 |
| Thigh_R | 0 | -0.25 | 0 | +0.25 | 0 |
| Shin_R | 0 | +0.25 | 0 | -0.25 | 0 |

This is 50 bounded smooth-interpolation keys, preserving setup frame 0 and matching playback endpoints 1 and 48. Playback has 48 samples at 24 FPS; endpoints are 47 frame intervals apart with the repeated pose at the wrap. Smooth interpolation uses the signature already verified in Pass 6. Matching endpoints does not prove seam velocity quality: inspect the loop in Moho. This rotation-only demo may have small foot drift; no IK or translation solution is implied. Inspect orientations first and adjust sign mapping only within an explicitly approved exact plan.

Version-4 sidecar fields: version=4, current session/serverId, documentPath, latest rigInspection.token, expiresAt, fps=24, startFrame=1, endFrame=48, operations=[{layerId,boneId,frame,angle,replace:false},...]. Angles are absolute radians computed from neutral plus requested offsets. The file is ephemeral private runtime state; never commit it. Remove it after success/failure. Refresh the inspection before an ordinary revision; no restart is needed between edits.

## Installation and live demonstration

1. Obtain installation approval. Back up and install only the updated moho_mcp/coordinated_write.lua. The installed Pass 6 bone handler already calls it. One normal Moho restart is needed for the cached Lua module; do not use an unverified hot reload.
2. User opens the new disposable humanoid project via the shared launcher, starts the server, dismisses dialogs, selects the bone layer/Poller. Verify metadata and every bone, including controller status. Stop for unsupported rig state or missing API.
3. Present the actual mapped rig and exact idle plan; request explicit live-write approval. Never transfer approval from the older two-bone project.
4. Publish fresh version-4 approval and execute one bounded transaction. Read back every channel/pose/interpolation mode; remove authorization. Ask user to loop playback and report seam quality, movement and responsiveness.
5. User presses Undo exactly once. Read back all neutral and unrelated keys. Do not assume success from mocks or Pass 6.
6. If user wants the cycle restored or adjusted, obtain that instruction, use a fresh inspection/approval and perform an ordinary revision without restarting Moho. Verify again. No automatic save. Stop after the demonstration; artwork and exports remain out of scope.

## Automated verification

- Lua: 306 passed, 0 failed (24 new generalized-rig cases; old two-bone tests retained).
- TypeScript: 77 passed, 0 failed; build passed.
- Non-GUI MCP smoke: all 26 tools and two resources present, expected missing-server error, no Moho/native helper used.
- Tests cover 10-bone branches, 12 bones/60 keys, arbitrary root ID, over-limit rejection, invalid/disconnected/cyclic hierarchies, stale parenting, controller/dynamics/target/IK/parent-animation rejection, late invalid operations, unchanged unanimated branches and last-bone failure rollback.
- Live idle playback, single-step multi-bone Undo and ordinary revision: pending.

## Changed files

- moho-plugin/moho_mcp/coordinated_write.lua
- moho-plugin/tests/test_coordinated_write.lua
- bridge/src/index.ts and bridge/src/tools.ts (descriptions only; public schemas unchanged)
- docs/implementation-pass-7.md and docs/windows-codex-setup.md

No installation, live write, commit or push has been performed in this pass. Screenshot confinement, generic mutation APIs and native input/batch risks remain outside this validated workflow and disabled.

## Live verification — October 15, 2026

Installed only the coordinated animation module, retaining the verified focus fix. Reconnected after normal Codex restart. All ten live bones passed hierarchy and controller checks. Applied one explicitly approved 50-key transaction at frames 1/12/24/36/48, with smooth interpolation and neutral-relative offsets. Independent readback verified every key (maximum angular error 2.17e-7 radians), preserved setup pose and hierarchy, and matching endpoints. Ephemeral write approval was removed; no automatic save occurred.

User confirmed visible movement, responsiveness and retained text-entry focus. The T-pose motion was not judged a natural idle; artistic acceptance remains incomplete. After exactly one manual Undo, readback verified all 50 new keys absent and all ten setup keys, geometry and parents identical to baseline. The project is now back to its pre-animation pose. Live ordinary revision on this ten-bone rig remains untested; Pass 5/6 iterative results do not substitute for that test. Next proposed step is an explicitly approved relaxed animation pose, preserving frame 0, before assessing idle quality again. No restoration or additional writes were performed.

Combined regression suite at installation: 308 Lua tests passed; focus-fix Node suite previously passed 85 tests. No commit or push performed.
