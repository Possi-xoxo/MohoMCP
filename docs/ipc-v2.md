# IPC v2 architecture and recovery

Codex MCP stdio → Node MohoClient → local JSON mailbox → Lua poll callback → existing handlers. All 26 public MCP names and input schemas are unchanged. `ipc.ping` is internal, not a new MCP tool.

## Files and lifecycle

| File | Writer | Purpose |
|---|---|---|
| status.json | Lua | running, ipcVersion=2, serverId, ipcDir |
| bridge-owner.json | Node, exclusive create | session UUID, server epoch, PID, OS birth identity, executable, host; one client per directory |
| owner-session-UUID.json | Node, immutable receipt | exact matching owner record; required for automatic recovery |
| ownership-transition/ | Node, exclusive mkdir | serializes ownership publication, recovery and release |
| request.json | Node | JSON-RPC request plus session, serverId, ipcVersion, expiresAt |
| response.json | Lua | JSON-RPC result/error plus matching id, session, serverId, ipcVersion |

Each connection gets a UUID session and each request gets a UUID ID. Lua creates a new server epoch on startup. Node exclusively creates the owner file, starts the existing native keep-alive, and completes an internal ping challenge. Status alone does not establish liveness. Concurrent calls serialize through one mailbox. Responses must match all correlation fields and contain exactly one result/error. Mismatches fail closed and require reconnect; stale replies cannot satisfy another request. Application errors with valid correlation leave the connection usable.

Both sides write a temporary file before renaming. Lua checks write, close and rename results. On Windows Lua removes the destination before rename; readers tolerate missing response files. This is complete-file publication, not a durable transaction or a guarantee across power loss. Node alone removes its request after completion. Lua never deletes it after publishing, which avoids deleting a subsequent request.

Polling reads a fixed number of files, never enumerates IDs or directories, and launches no shell processes. There is at most one handler per callback. A reentrancy guard prevents nested processing. A one-entry raw-request/reply cache is established before dispatch, preventing repeat execution while publication or serialization fails. Failed writes are logged with retained replies retried on later callbacks. Identical error logs are suppressed. Malformed data is rejected; a following valid request can progress. Lua reads at most 1 MiB per IPC input. The Node response reader is not size-bounded.

This cache is in memory and only covers the current mailbox. It is not a durable deduplication ledger. Server crashes, modified/replayed requests by another local process, or replacement of a pending mailbox cannot provide exactly-once execution. The supported bridge never automatically replays mutations. A deadline rejects expired requests before dispatch, with Lua wall-clock resolution of one second. It cannot cancel a handler already executing. Native handler crashes remain outside Lua pcall protection.

## Failures and restarts

| Condition | Behavior |
|---|---|
| Request 102, gaps, huge IDs | Fixed mailbox discovery is independent of ID; bounded numeric IDs or strings accepted |
| Old response | Cleared before posting; correlation mismatch rejected if one appears later |
| Malformed response / timeout | Request fails, connection becomes unready; reconnect explicitly |
| Response write/serialization failure | Lua retains cached response/fallback; mutation does not repeat in that instance |
| Graceful bridge shutdown | Cancels/drains queued work and removes owned mailbox/lock |
| Bridge crash | On Windows, complete verifiable dead-owner state can be recovered; ambiguous state requires manual recovery |
| Lua restart | New epoch; old requests rejected; client detects changed status and reconnects |
| Stale status / stopped polling | Ping or subsequent request times out; no continuous heartbeat |
| Another Lua server replaces status | Prior server stops on its next poll; require one Moho instance, not distributed locking |

Owner locks are never removed based on PID absence or age alone. Pass 3.1 requires a complete versioned owner record, exact immutable session receipt, matching host/platform, valid OS birth identity/executable, two successful absent-process checks, and matching session/server metadata for every existing mailbox file. Any live PID is protected, even if its birth identity differs (PID reuse). Inspection errors fail closed. An exclusive transition directory serializes competing new bridges. Follow the Windows guide for ambiguous or legacy state. Never infer a failed mutation did not execute.

## Configuration and compatibility

Both sides honor absolute `MOHO_MCP_IPC_DIR`. Windows defaults use TEMP then TMP, followed by `moho-mcp`; set an override if neither is valid. Spaces and shell metacharacters are literal filesystem path data in this IPC implementation. Lua requires the directory to exist; pre-create it with PowerShell. Node also creates it when connecting. Mismatch diagnostics report the expected path and compare a status file's advertised path when available; an absent file cannot reveal another process's actual environment.

IPC v2 deliberately requires a paired bridge/plugin upgrade. The old `req_N.json` / `res_N.json` protocol is not read or emitted. A new bridge rejects legacy status; an old bridge may time out against the new plugin. Tool-level compatibility is preserved, filesystem-protocol compatibility is not. Do not run both versions in one directory.

Session tokens are correlation data, not authentication against processes able to read/write the directory. No ACL, symlink/reparse-point confinement, multi-user isolation, or hostile-process protection has been added. Production keep-alive remains unchanged; tests disable it. Polling overhead is bounded but live UI responsiveness, Moho's embedded Lua environment, rename behavior under antivirus contention, and API compatibility still require Pass 3 validation.

## Pass 3.1 lifecycle details

Shutdown listeners are installed before MCP transport startup. stdin end/close/error, stdout error, signals, parent disconnect, transport close, and event-loop drain funnel through one idempotent cleanup. Cleanup cancels queued/in-flight client work, stops the existing helper, releases ownership, and closes MCP. A five-second bound prevents indefinite shutdown hangs. stderr identifies the shutdown reason and incomplete cleanup; stdout remains MCP-only.

Windows forced process termination can bypass JavaScript handlers. Automatic recovery is a restart fallback, not a promise that an exiting process always cleans up. Windows PowerShell process inspection uses a validated numeric PID in fixed code, no owner-controlled shell text, a five-second timeout, and no UI/input APIs. It runs at connect/recovery only, not per request. Process StartTime UTC ticks and executable path are stored with the session. A live process is never killed or displaced, including a reused PID. Unknown/access-denied identity is not absence. Other platforms retain exclusive ownership and graceful cleanup but do not automatically recover old locks.

The owner receipt is written before the owner file. Recovery requires exact receipt/owner bytes and matching session/server fields in pending request/response files (including temporary files). It discards abandoned mailbox data, never replays it, and creates a fresh session. The ping then proves current Lua liveness. Correlation still rejects late old Lua replies. The receipt is a consistency witness, not authentication against another process with directory write access.

All Pass 3.1 ownership operations hold `ownership-transition/`. A process killed in this short critical section can leave the guard behind: contenders wait up to two seconds, then fail explicitly. The guard is NEVER stolen automatically. Similarly, torn JSON, mixed-session mailbox data, missing receipts, legacy records, an active reused PID, or failed OS inspection require manual recovery. These deliberate limits avoid racing a delayed publisher/cleaner. A killed process before publication may leave an unused receipt; it cannot satisfy a later different UUID session.

Do not mix bridge versions in the same directory. Lua IPC v2 envelopes are unchanged and the existing Pass 2 Lua server accepts the additional owner metadata. Old bridges do not understand receipts or the transition guard. Stop all bridges before upgrading; legacy locks require the documented one-time manual recovery. No new dependencies, public tool names, input schemas, or networking were introduced.
