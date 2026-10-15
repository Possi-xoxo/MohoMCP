# IPC v2 architecture and recovery

Codex MCP stdio → Node MohoClient → local JSON mailbox → Lua poll callback → existing handlers. All 26 public MCP names and input schemas are unchanged. `ipc.ping` is internal, not a new MCP tool.

## Files and lifecycle

| File | Writer | Purpose |
|---|---|---|
| status.json | Lua | running, ipcVersion=2, serverId, ipcDir |
| bridge-owner.json | Node, exclusive create | session UUID, PID, start time; one client per directory |
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
| Bridge crash | Lock remains; second client fails clearly; manual recovery required |
| Lua restart | New epoch; old requests rejected; client detects changed status and reconnects |
| Stale status / stopped polling | Ping or subsequent request times out; no continuous heartbeat |
| Another Lua server replaces status | Prior server stops on its next poll; require one Moho instance, not distributed locking |

Owner locks are not stolen based on PID or age. This sacrifices automatic crash recovery to avoid conflicting live clients and PID-reuse races. Follow the Windows guide's stop-both-sides cleanup procedure. Never infer a failed mutation did not execute.

## Configuration and compatibility

Both sides honor absolute `MOHO_MCP_IPC_DIR`. Windows defaults use TEMP then TMP, followed by `moho-mcp`; set an override if neither is valid. Spaces and shell metacharacters are literal filesystem path data in this IPC implementation. Lua requires the directory to exist; pre-create it with PowerShell. Node also creates it when connecting. Mismatch diagnostics report the expected path and compare a status file's advertised path when available; an absent file cannot reveal another process's actual environment.

IPC v2 deliberately requires a paired bridge/plugin upgrade. The old `req_N.json` / `res_N.json` protocol is not read or emitted. A new bridge rejects legacy status; an old bridge may time out against the new plugin. Tool-level compatibility is preserved, filesystem-protocol compatibility is not. Do not run both versions in one directory.

Session tokens are correlation data, not authentication against processes able to read/write the directory. No ACL, symlink/reparse-point confinement, multi-user isolation, or hostile-process protection has been added. Production keep-alive remains unchanged; tests disable it. Polling overhead is bounded but live UI responsiveness, Moho's embedded Lua environment, rename behavior under antivirus contention, and API compatibility still require Pass 3 validation.
