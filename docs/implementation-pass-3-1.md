# Pass 3.1 — bridge lifecycle and restart recovery

Implemented and automatically validated on Windows, October 15, 2026. No live Moho calls, plugin installation, project changes, global Codex changes, or IPC permission changes occurred. The installed Lua plugin still contains the previous metadata handler. No commit or push was performed.

## Root-cause findings

The recorded live failure established that the old Node process exited while its owner file survived, with the same Moho process and server epoch. It did not establish which termination event Codex used. An OS-level termination or a cleanup interrupted by host teardown remains plausible, not proven.

Pass 2 already listened for SIGINT, SIGTERM, SIGHUP and stdin end. Missing EOF handling was therefore not the demonstrated original cause. However, listeners were attached after transport startup, stdin close/error and stdout failure were not covered, and MCP transport closure was not wired to cleanup. The locked SDK's StdioServerTransport listens for data/error but does not translate stdin EOF to onclose. Its client transport attempts stdin closure, then escalates to process termination after a bounded wait. This is SDK behavior, not proof of Codex desktop's exact shutdown implementation.

Windows does not provide Unix-style graceful termination semantics for every process kill. JavaScript handlers cannot guarantee cleanup after forced termination. See [Node signal documentation](https://nodejs.org/api/process.html#signal-events). Async work cannot be safely deferred to the exit event. The correct defense is both orderly cleanup and verified recovery by the next process.

## Implementation

- `lifecycle.ts` installs early, idempotent shutdown handling for EOF, stdin close/error, stdout error, signals, parent disconnect, transport close and event-loop drain. It drains/cancels client work, stops the existing helper, releases ownership and closes MCP, with a five-second shutdown bound and stderr reason diagnostics.
- `ownership.ts` records an OS process birth identity, executable, host/platform, session UUID and server epoch. An immutable matching receipt proves complete owner publication. Exclusive directory creation serializes ownership transitions.
- Windows recovery requires complete matching owner/receipt records, two positive absent-process results, and matching session/server fields in all existing mailbox files. It refuses active PIDs even when their birth identity differs, protecting PID reuse. Permission errors and unknown identity fail closed. It never terminates an owner or automatically retries an operation.
- Legacy records, interrupted transitions, torn records, missing receipts and mixed mailbox state remain explicit manual-recovery cases. A process killed while holding the transition guard leaves that guard deliberately unreclaimed. This is a documented safety limit, not universal unattended crash recovery.
- `totalLayers` now counts the existing hierarchy traversal rather than silently treating an unavailable TotalLayerCount accessor as zero. No new Moho API signature was guessed. Flat/nested/empty/error fixtures pass; actual nested Moho behavior and the updated metadata handler still need live validation. Other traversal fallbacks remain as before.

The Lua IPC v2 envelope is unchanged. Extra owner metadata is compatible with the existing v2 server, but all Node bridges sharing a directory should be upgraded together. All 26 public names/input schemas are exactly unchanged. No networking or new packages were introduced. Non-Windows hosts retain conservative manual stale-lock recovery.

## Validation results

| Check | Result |
|---|---|
| TypeScript build | PASS |
| Complete Vitest suite | 77 passed, 5 files |
| Real Node subprocess lifecycle harness | 11 scenarios passed |
| Complete standalone Lua 5.4 suite | 190 passed, 0 failed |
| Real-file Node/Lua integration | 400 requests across two separate Node processes, all passed |
| MCP stdio smoke | 26 tools, two resources, expected missing-server error |
| Tool inventory comparison | Exact equality with Pass 1 inventory |
| Whitespace/diff check | PASS |

The subprocess harness uses the production bridge entry point for EOF, active conflicts, reopen, in-flight cancellation, startup EOF and abrupt termination. Native helpers are replaced with no-ops by a test-only preload. Five additional subprocess fixtures dispatch signal/stdio/transport events directly to exercise cleanup; these are not claims that native Windows signals are delivered gracefully. Abrupt termination targets only an isolated spawned test bridge. The real-file Lua test uses mocked document handlers, never Moho.

Commands: `npm.cmd run build`, `npm.cmd test`, `node scripts/test-lifecycle.cjs`, and `node scripts/smoke-test.cjs` from bridge; `lua moho-plugin/tests/run_tests.lua` and `python scripts/test-ipc.py --lua-module-dir PATH_TO_ISOLATED_LUPA` from the repository root. This run used Node 24.14.0, npm 11.9.0, and workspace-isolated Lupa 2.8/Lua 5.4. Dependencies and lockfile were unchanged.

## Changed files

- bridge/src/ownership.ts
- bridge/src/lifecycle.ts
- bridge/src/moho-client.ts
- bridge/src/index.ts
- bridge/src/__tests__/ownership.test.ts
- bridge/src/__tests__/moho-client.test.ts
- bridge/scripts/test-lifecycle.cjs
- moho-plugin/moho_mcp/tools/document.lua
- moho-plugin/tests/test_document.lua
- moho-plugin/tests/run_tests.lua
- docs/ipc-v2.md
- docs/windows-codex-setup.md
- docs/implementation-pass-3-1.md

## Before repeating the live test

1. Obtain explicit approval for another live run. Disconnect the old Codex bridge before activating the new build. Do not silently delete legacy or ambiguous state.
2. If validating totalLayers, close Moho and back up/update only the installed document.lua from this checkout, then restart Moho. This pass did not update installed files.
3. Launch Moho manually from the shared desktop launcher, open the disposable document, start the Lua server, confirm the shared IPC path, and select the poller. Keep only the ten query tools enabled.
4. Verify metadata and hierarchy counts, then repeat 200 sequential reads on the final shared directory. Confirm user-visible responsiveness and console errors.
5. Close/reopen Codex normally while Moho stays running. Check the shutdown reason if available, ownership release or verified recovery, fresh session, and successful reads. The actual desktop shutdown failure has not yet been retested with these changes.

Do not proceed to animation writes yet. Screenshot path confinement, unsafe input/native helper behavior, comprehensive mutation/batch validation, undo integrity, dependency advisories, and remaining Moho API assumptions are not resolved by this pass. Same-user directory writers remain trusted; session receipts are not authentication. Orphan helper behavior under forced host termination remains a separate limitation; automated tests do not exercise native keep-alive.
