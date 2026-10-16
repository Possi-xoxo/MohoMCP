# Pass 8.1 — extended humanoid rigs

Implementation and automated validation complete; installation and live 20-bone validation pending. No project mutation or installed-plugin change performed in this pass.

## Bounds and validation review

The existing coordinated module now accepts 2–32 bones. The distinct version-4 write cap remains 72 operations, at least two targeted bones, and a 32-KiB approval file. Version 3 remains limited to exactly two bones and 16 operations. No arbitrary dispatch or new public MCP tools/schemas were introduced.

Review confirmed inspection visits every bone, validates positive finite lengths/setup geometry and neutral keys, checks parent indices, one root and cycle-free connectivity, and records native object identities and all angle-channel keys/modes. Added explicit missing/duplicate bone identity and empty/duplicate exact-name rejection. Name matching is case-sensitive; pose bindings resolve exact names, never numeric IDs inferred from B-number labels. All version-4 controller checks run on every bone immediately before mutation, including unselected branches. Read inspection retains per-bone controller errors for diagnosis; mutations reject them.

Before writing, sameRig compares the entire native identity chain, names, parentage, setup geometry, neutral angles and angle-channel snapshots. Consequently a changed key or parent on an unselected bone also invalidates the plan. The target set is the unique bone IDs in approved operations; only those setters execute. The transaction validates every intended operation before one PrepUndo call, records setters before invocation, restores attempted writes in reverse order on failure, and checks all angle channels afterward. One-step Undo on 20/32 bones still needs live confirmation; previous ten-bone verification is not a substitute.

Full-rig validation is intentionally conservative: unsupported controllers on an otherwise untouched branch block a transaction. Existing position/scale channels are not modified by this angle-only workflow; this is not comprehensive arbitrary-channel editing support. Interpolation readback still exposes only modes. Pass 8's offline planner continues to reject differing existing keys rather than silently replace custom curves. Native crashes and rollback setter failures remain outside guaranteed recovery; inspect and use manual Undo if reported.

## Selective poses

Pose JSON keeps bindings for the entire rig (now up to 32), but `rotations` may contain only the selected semantic roles. The cycle track list may likewise be a subset. The planner resolves every binding and validates every bone before compiling numeric operation IDs from a fresh inspection. Two selected bones are still the minimum; do not pad a single-bone operation with unrelated edits. Larger rig size does not permit 32 five-key tracks in one transaction; that would exceed 72 writes and is rejected.

Use the Pass 8 review-only CLI from the isolated build for preparation. No session or live authorization is produced automatically. Bind explicit approval to the current session/document/inspection before the existing bone_setTransform anchor, then remove it and verify full-rig readback. Never reuse the old ten-bone pose bindings for the new humanoid.

## Tests and files

- Isolated TypeScript compilation: passed (`node_modules/.cache/pass81-build`); active bridge build untouched.
- Node: 115 passed (6 added cases, including parameterized 20/32-bone tests).
- Lua: 323 passed (15 additional cases); prior two-bone, ten-bone, IPC and focus tests retained.
- Tests cover 20/32-bone subset edits, final-bone targets, full unchanged-channel verification, exactly 72 accepted versus over-limit rejection, 33-bone rejection, duplicate names/objects, stale unselected names/parents/keys/identities, unselected controllers, late validation errors and last-selected-bone rollback. The former over-12 rejection test now enforces the new 32-bone boundary.

Changed: `moho-plugin/moho_mcp/coordinated_write.lua`, its Lua test file, `bridge/src/pose-planner.ts`, its TypeScript tests, descriptive text in `bridge/src/index.ts` and `bridge/src/tools.ts`, and this document. No changes to focus callbacks, helper behavior, IPC permissions, ownership or restart code.

## Approval-gated installation and live procedure

1. Obtain approval; user closes Moho normally. Back up and install only `moho_mcp/coordinated_write.lua`. Retain the verified Server/Poller focus-fix files and existing Lua bone handler.
2. One Moho restart is required for the cached module. The current bridge remains wire-compatible; a Codex restart is not needed just to load Lua changes. Its older description may still state the old limit until a later normal bridge update. Do not confuse that wording with live module validation.
3. User opens the new disposable humanoid, selects its bone layer, starts the server and selects Poller. Reinspect the actual file path, all bones/keys/controllers and hierarchy; require maxBones=32. Previously observed B1–B20 chains are only hypotheses until fresh readback.
4. Ask user to confirm which screen-side branch is anatomical left/right. Use screen-side labels until confirmed. Check shoulder/hip positions and limb lengths, and explain structural or controller blockers before preparing rotations.
5. Present a fresh selective relaxed pose (normally upper arms and forearms; shoulders, hips and feet untouched), calculated from inspected local orientations. Obtain explicit write approval. Apply on a nonzero frame and verify all changed and unchanged angle keys plus geometry.
6. Ask for visual review, responsiveness and text-focus confirmation. Check one-step Undo when appropriate. No save, idle animation, rig edits, screenshots or native input. Stop after relaxed-pose demonstration.

The previous ten-bone relaxed pose was rejected visually because its arms collapsed toward the torso. Do not characterize that pose as successful or carry its numeric targets into this rig. This pass's live pose suitability remains unverified.

## Resumed approved pose — October 16, 2026

Following successful Pass 8.2 diagnostic write/Undo and fresh explicit authorization, live full-rig validation matched the twenty-bone baseline. Applied one version-4 transaction containing four frame-1 arm keys (Left Bicep −40.3048447°, Right Bicep +47.0763648°, Left Forearm −8°, Right Forearm +8°, all relative to neutral). One attempt succeeded without timeout. Independent full-rig readback verified all four values and smooth interpolation, every original key, names, parent relationships and setup geometry. Unselected sixteen angle channels preserved. Shoulder and hip transforms were not keyed. Ephemeral approval removed; no save or idle animation. Visual review and twenty-bone coordinated Undo remain pending; historical polling timeout cause remains unproven.

Final status: the user subsequently approved the relaxed stance visually. Pass 8.3
added and verified the breathing cycle around that baseline; see
implementation-pass-8-3.md. No twenty-bone Undo was performed in that cycle.
