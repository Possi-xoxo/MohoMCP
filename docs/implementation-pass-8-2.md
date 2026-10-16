# Pass 8.2 — polling diagnosis, stage 1

Status: diagnostic implementation and automated validation complete; installation and live evidence pending. Reliable background polling is NOT yet established. No animation writes are authorized under this pass until fresh explicit approval after diagnosis/read-only validation. Previous pose approval is not carried forward.

## Confirmed findings

- Reads and writes traverse the same Node exchange, mailbox, Lua poll and dispatch path. The helper checks the IPC envelope, not the method type. No separate mutation wake-up mechanism exists.
- Lua is called from tool DrawMe and existing server callbacks; no independent timer drives server.poll. A selected Poller does not by itself prove callback execution while idle.
- Quiet refresh requires a matching pending request/owner/server, exactly one visible nonminimized Moho process, Moho not foreground, and 1.5 seconds without system input. A previous sample observed recent input, but inactivity alone did not resolve the issue. This does not establish a root cause.
- Existing code discarded helper stderr and swallowed helper state exceptions, preventing diagnosis of runtime/eligibility failures.
- Prior timed-out writes were followed by inspections showing no new keys. This rules out successful key creation at those inspection times, but does not distinguish nondiscovery, validation rejection, execution failure/rollback, or response failure.
- Shipped scripts inspected for timer/idle callbacks did not establish a supported timer API. No speculative timer is added.

Competing hypotheses remain callback starvation/paint not reaching DrawMe, suppressed or failing refresh, ownership/approval rejection, execution/serialization failure, or response delivery failure. A long handler blocks Moho's synchronous callback until it returns; mocks cannot prove live duration or responsiveness.

## Changes

- `bridge/src/ipc-trace.ts`: best-effort timestamped JSONL events, rotated at 1 MiB with one previous file.
- `bridge/src/moho-client.ts`: correlation-aware published/deadline, response_received, response_rejected, timeout, exchange_failed and cleanup events.
- `bridge/src/keep-alive.ts`: logs pending eligibility (at most once per second), process ambiguity, suppressed-state errors, paint failures and capped helper stderr. No new input, activation, redraw flags or scheduling policy.
- `moho-plugin/moho_mcp/server.lua`: callback heartbeat at most once per second, discovered, execution_started/completed, rejected_or_failed, response_write_failed/written and completion_abandoned events. Response cache and no-repeat behavior unchanged.
- Focused Node trace and Lua lifecycle tests; test filesystem supports append/size queries.

Traces live only in private IPC: bridge-trace.jsonl, helper-trace.jsonl, lua-trace.jsonl and their .previous generations. No approval payloads or request params are logged. Error messages can contain local paths and must remain private. Lua wall-clock timestamps have one-second resolution; cpuSeconds is CPU time, not elapsed UI time. Node/helper timestamps use milliseconds. Best-effort log failure cannot establish absence of a lifecycle event. Missing discovery evidence must be interpreted alongside heartbeat/helper/bridge evidence and log availability, not treated as mathematical proof.

The synchronous Lua trace uses constant-size file metadata checks, never directory scans, and a maximum of one idle heartbeat per second. Live overhead still requires measurement. Rotation failure cannot compromise request handling; filesystem failures remain diagnostic limitations.

## Evidence interpretation

| Observation | Interpretation |
|---|---|
| Published, helper eligibility/paint, no Lua callback/discovery | Investigate viewport callback starvation; verify trace health first |
| Discovered + rejection, no execution_started | Session/deadline/parameter/handler validation failed; inspect reason |
| execution_started + rejected_or_failed | Handler failure; inspect error/readback, never blind retry |
| execution_completed + response_write_failed | Result cached; write retries must not execute handler twice |
| response_written without response_received | Investigate correlation/bridge/timeout and cleanup timing |
| completion_abandoned | Mailbox changed/removed during execution; outcome still requires readback |

## Automated results

Isolated TypeScript build passed. Node: 117 passed. Lua: 328 passed. Existing 200-request, ownership/restart, correlation, timeout, reentrant polling, rollback, focus policy and 32-bone tests retained. New tests cover ordered lifecycle events, idle mailbox waiting for a callback, expiration before execution, failed-response retry without reexecution, a handler outliving its mailbox, alternating read/write dispatch and bounded/error-tolerant logs. Alternating writes are mocks only. No actual live animation writes, mouse events, or redraws were exercised by this validation. No claim that simulated idle proves Moho idle polling.

## Next approval-gated step

Request approval to back up/install only server.lua plus the compiled bridge files (including ipc-trace.js). Keep Server/Poller focus-fix files and coordinated_write.lua unchanged. One normal Moho restart loads the cached server module; a normal Codex restart loads the bridge. Do not launch Moho as a Codex-owned child. Capture idle read-only traces and typing feedback first, then identify the smallest evidence-supported scheduling/processing correction and test it. Do not increase timeout or restore synthetic mouse movement as a substitute for diagnosis. Any subsequent installation needs approval. After reliable read-only operation, request fresh approval for one small write; the full relaxed pose remains out of scope until separately authorized.

## First live diagnostic session — October 16, 2026

Installed diagnostic bridge/server confirmed active after user restarts. Ten read-only calls succeeded (nine document metadata, one full 20-bone inspection), plus the connection ping: 11/11 correlated IPC exchanges, zero timeouts. Bridge publication-to-receipt latency was 212–323 ms for metadata, 437 ms for ping, and 1959 ms for full-rig properties. These exclude MCP/client overhead.

Helper traces captured both background-idle eligibility and foreground Moho with recent input (31/125 ms): repaint was suppressed during interaction, while natural callbacks still completed reads. No response-write, ownership, correlation or execution failure was established. Earlier write timeouts have NOT been reproduced or diagnosed; no write was attempted in this session. User confirmation of focus/responsiveness remains pending. Metadata changed from end frame 240 to 24 during manual interaction; Codex issued no document-setting writes.

Found and corrected a diagnostic-only false positive in repository server.lua: preconstructing the cached fallback error response incorrectly emitted rejected_or_failed for every request, including successful ones. Added an assertion to the lifecycle regression; all 328 Lua tests pass. Installed server still has the old diagnostic behavior; ignore only the pre-execution fallback message when followed by successful execution/receipt. Do not silently install the correction. No extra restart is justified solely for that known log artifact.

Recommendation: retain traces and avoid speculative scheduling changes. Confirm UI usability, then separately approve one minimal disposable-project write if desired to capture the formerly failing path. A failing traced request is needed to identify a targeted runtime fix. The complete pose remains unauthorized under Pass 8.2. Private per-request results are in task outputs/pass82-read-diagnostics.json; do not commit runtime identifiers.

## Controlled diagnostic write and Undo

User confirmed stable text focus and responsiveness. With fresh explicit approval, applied only +1 degree from neutral to Left Forearm at frame 1 through the existing version-2 single-edit gate. Request discovery, execution completion, response write and correlated receipt all succeeded; no timeout or retry. Independent full-rig readback verified exactly one new key, preserved every setup key, and unchanged names, hierarchy and geometry for all twenty bones. Removed ephemeral approval immediately afterward. Nothing saved.

User performed Edit > Undo exactly once. Independent readback matched all twenty pre-write bone snapshots and angle keys. No full pose or breathing animation followed. Communication succeeded in this controlled session, but historical timeouts remain unexplained, not claimed fixed. Recommend retaining traces and capturing the next naturally occurring failure before altering polling policy. The known fallback-error trace artifact is corrected in repository source, not yet installed; no restart required solely for that cosmetic diagnostic correction.

### Background input starvation reproduced during Pass 8.3 preparation

Two read-only exchanges timed out before any breathing-animation write was issued.
The helper repeatedly logged valid, owned, visible requests with Moho in the
background, but global input idle remained below 1500 ms. Lua logged no discovery
for those exchanges. This identifies a concrete starvation path in the helper;
it does not establish the cause of every historical timeout.

The prepared bridge-only correction removes global input idle from the background
paint decision. Typing in another application must not prevent a pending request
from reaching Moho. Foreground Moho still suppresses artificial painting, with an
additional foreground check immediately before asynchronous paint. Session,
expiry, ownership, visibility, single-process targeting, and the 250 ms loop remain.
There are no synthetic input messages or unconditional idle refreshes.

Validation: TypeScript compilation and all 117 Node tests pass, including 64
compiled C# policy combinations and isolated helper EOF cleanup. Initial sandbox
PowerShell tests were blocked by AuthorizationManager; the full isolated suite
passed outside that sandbox. No live helper change has been installed yet.
Installation requires approval and a bridge/Codex restart, not a Lua/Moho restart.
Live foreground focus and background delivery remain to be verified.

Inspection caveat: rig `setupAngle` currently reports the displayed bone fAngle.
Inspect at frame 0 when comparing it to the neutral baseline; this field alone
must not be interpreted as evidence of changed setup geometry at another frame.

## Final follow-up

The bridge-only correction was subsequently approved, backed up, installed and
activated by normal Codex restart with Moho left open. Background reads with
recent input, one authorized 26-key write, and full-rig readback succeeded without
timeouts. The user confirmed playback and responsiveness. See
[Pass 8.3](implementation-pass-8-3.md). Earlier pending-status notes above describe
historical checkpoints, not the final release state.
