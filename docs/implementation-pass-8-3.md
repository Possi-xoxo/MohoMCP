# Pass 8.3 — first humanoid breathing idle

Completed October 16, 2026. The user visually confirmed the animation succeeded
and Moho remained responsive. This is a controlled disposable-rig demonstration,
not certification of arbitrary rigs or production projects.

## Toolkit through this pass

- Connected branching skeleton validation supports 2–32 bones. Full-rig identity,
  hierarchy, geometry and controller validation applies even to selective edits.
- Coordinated version-4 transactions retain the independent 72-operation limit,
  prevalidation, rollback and single PrepUndo call. Version-3 two-bone workflows
  remain compatible. Live one-step Undo was verified in earlier demonstrations;
  Undo was deliberately not performed for this breathing cycle.
- Offline pose/cycle planning resolves semantic names against fresh inspections,
  preserves matching keys and rejects conflicting replacements. Plans do not
  themselves grant write approval or publish IPC requests.
- Private bounded lifecycle traces distinguish discovery, execution and delivery.
- Demand-driven background refresh uses no synthetic input or activation. Global
  input activity no longer starves requests while Moho is in the background.
  Foreground Moho still suppresses artificial paint, including a second check
  immediately before painting. No request means no artificial refresh.

## Live result

After a normal Codex restart, the updated bridge connected to the same running
Moho session. Read-only queries succeeded with recent global input while Moho
was in the background, the condition previously suppressing the helper. Fresh
inspection at frame 0 matched all 20 bones and existing relaxed-pose keys.

One explicitly approved transaction added 26 smooth angle keys to six bones:

| Track | Amplitude about relaxed pose | Delay in interior samples |
|---|---:|---:|
| Chest | 0.35 degrees | 0 frames |
| Head | -0.25 degrees | 1 frame |
| Left upper arm | 0.30 degrees | 2 frames |
| Left forearm | 0.15 degrees | 3 frames |
| Right upper arm | -0.24 degrees | 3 frames |
| Right forearm | -0.12 degrees | 4 frames |

Playback range: frames 1–48 at 24 FPS. Existing four frame-1 relaxed arm keys
were reused unchanged. The write succeeded on its first attempt; bridge
publication-to-receipt was 112 ms. Independent readback verified all new angles
and smooth interpolation, unchanged existing keys, hierarchy and setup geometry,
and exactly matching frame-1/frame-48 angles. Legs and feet were untouched.
The user confirmed successful playback and continued responsiveness. Nothing was
automatically saved or undone. No screenshot, input or unrestricted batch tools
were enabled. Session identifiers, actual paths, approval files and traces remain
private and are intentionally omitted from this report.

## Release validation

Fresh pre-commit validation on Windows:

- TypeScript compilation: passed into isolated build output.
- Node/Vitest: 117 passed, 0 failed, across 8 files.
- Lua 5.4 isolated harness: 328 passed, 0 failed.
- Includes 200 simulated sequential requests, restart/ownership/correlation,
  expiry, failed delivery, rollback, full 32-bone validation, selective edits,
  pose planning, lifecycle logs and 64 compiled C# refresh-policy combinations.
- Tests do not operate the live Moho UI. Live results above are separate evidence.

## Limits and next use

The rotation-only cycle is not anatomical respiration, IK or planted-foot solving.
Equal endpoints do not guarantee equal seam velocities; playback quality remains
subject to user review. Foreground callback starvation is still possible if Moho
stops naturally painting; the helper intentionally does not force foreground UI
refreshes. This fix explains the observed background starvation, not every
historical timeout. Inspect traces and document state before retrying any timeout.

The inspector's `setupAngle` currently reflects displayed `fAngle`; inspect at
frame 0 when comparing neutral geometry. Full curve-preserving conflicting-key
replacement remains unsupported by the planner. Generic mutation validation,
screenshot confinement and unrestricted input/batch risks remain outside this
approved workflow and those tools remain disabled.

Ordinary approved edits need no Moho restart. Bridge-only updates require a
normal bridge/Codex restart; cached Lua updates require installation approval,
backups and one normal Moho restart. Do not automatically save projects, repeat
writes, or use Undo without the user's direction.
