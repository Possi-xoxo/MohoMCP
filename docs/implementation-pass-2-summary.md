# Implementation Pass 2 — results

The bridge now passes 200 sequential simulated requests without stalling, rejects mismatched sessions/responses, and supports graceful process restart. No plugin was installed, no GUI automation was exercised, and no Moho project or global Codex setting was modified. Live Moho Pro 14.5 compatibility remains unverified.

## Implemented

- Replaced the bounded numeric file scan with one serialized mailbox and reentrancy guard. Regression tests reproduce the old request-102 discovery failure, then validate the replacement through 200 requests, gaps, and large/string IDs.
- Added exclusive bridge ownership, UUID sessions/request IDs, server epochs, ping liveness, strict response correlation, explicit conflict/restart errors, timeout cleanup and orderly shutdown. Crashed-owner locks require explicit manual recovery, never automatic stealing.
- Added paired absolute IPC-directory configuration and path diagnostics. Lua IPC uses no shell processes; directory creation is a documented preparation step.
- Preserved false from the layer visibility accessor in animation frame-state reporting. Three focused tests cover hidden, visible and fallback cases. No new Moho API signature was introduced.
- Reviewed screenshot dimensions: width/height remain metadata rather than actual resizing. No rendering change was made; live capture sizing and relevant API behavior require later validation.

## Verification

| Check | Result |
|---|---|
| TypeScript compilation (`npm.cmd run build`) | PASS |
| Vitest (`npm.cmd test`) | 65 passed across 4 files |
| Lua suite (Lupa 2.8, Lua 5.4) | 186 passed, 0 failed |
| Actual Node ↔ Lua filesystem integration | 400 requests: 200 in each of two separate Node processes against one Lua server |
| MCP stdio smoke | 26 tools, 2 resources; missing-Moho error verified |
| Public tool inventory comparison with Pass 1 | Exact JSON tool inventory equality, including schemas |

Tests use mocks or isolated temporary directories, including a path containing spaces. Native helpers are disabled. Coverage includes stale/mismatched replies, malformed requests/responses, expired requests, write/open/rename/serialization failures, reentrant polling, concurrent callers, ownership conflicts, crash-lock refusal, graceful restart, server epoch changes, timeouts and disconnect during handshake. Filesystem integration uses real Lua server code with a mocked document handler; it does not validate Moho callbacks or document APIs. Node 24.14.0/npm 11.9.0 and TypeScript 5.9.3 were used. Existing dependencies/lockfile were retained from Pass 1.

To reproduce the cross-language integration with an isolated installation of Lupa 2.8:

```powershell
python scripts/test-ipc.py --lua-module-dir C:\path\to\isolated-lupa
```

Run after building bridge/dist. Standalone Lua tests can also run with `lua moho-plugin/tests/run_tests.lua`. Python/Lupa is test-only, not a production dependency.

## Remaining security blockers and limitations

- **High:** screenshot response `filePath` is still not confined; the bridge can read/delete a path supplied through IPC. Do not enable screenshots until fixed.
- **High:** mouse/keyboard automation remains unrestricted and native helper script/path construction remains unhardened. Predictable helper files and shell handling are separate from the now shell-free Lua IPC path.
- **High:** mutation validation, destructive operations, batch partial failure/undo behavior and document integrity protections remain incomplete. Keep writes and batch disabled for initial integration.
- **High in a hostile/shared-directory setting:** session tokens do not authenticate local peers. Directory ACLs, reparse points, tampering, oversized responses and multiple Moho instances remain outside this pass. Use one account, one local private directory, one Moho instance.
- **Dependency blocker:** Pass 1 npm audit reported 21 affected packages (3 critical, 13 high, 3 moderate, 2 low); no dependency remediation was performed. Reachability varies; do not treat these as resolved.
- **Reliability limitation:** no exactly-once guarantee across crashes; unknown mutation outcomes require inspection. Crash recovery is manual. No continuous heartbeat or live polling/performance guarantee. The installer still has hard-coded paths and weak error handling; use manual copying when authorized.

## Pass 3 manual procedure

1. Review these blockers and the updated Windows guide. Choose a permanent checkout and a private local IPC directory, pre-create it, and align the environments of Moho and Node.
2. With Moho closed, back up existing plugin files/tool list and manually install the complete matched Pass 2 Lua plugin. Rebuild the matching bridge. Do not mix IPC versions.
3. Open a disposable document, start the Lua server, select the poller, and verify IPC v2 status and module registration in the console.
4. Manually merge the disabled example Codex configuration with corrected absolute paths. Enable only its ten query tools when ready. Codex starts the bridge; do not start a second owner. Production connection starts the existing native keep-alive, so this is the first live UI-affecting step.
5. Verify the ping and compare read results to the actual document. Run 200 sequential reads, including 101–103; verify hidden-layer reporting. Record exact Moho build, console output and responsiveness while changing tools.
6. Test graceful bridge restart, Lua restart/reconnect and stopped polling. On a disposable session test crash-lock refusal and follow the explicit stop-both-sides recovery steps. Never blindly repeat a timed-out write.
7. Address capture/input/mutation blockers before broadening tools or testing write/undo/API behavior on disposable content.

## Files changed in Pass 2

- `bridge/src/moho-client.ts`
- `bridge/src/config.ts`
- `bridge/src/index.ts`
- `bridge/src/__tests__/moho-client.test.ts`
- `moho-plugin/moho_mcp/server.lua`
- `moho-plugin/moho_mcp/tools/animation.lua`
- `moho-plugin/tests/run_tests.lua`
- `docs/windows-codex-setup.md`
- `docs/codex-mcp.windows.example.toml`
- `moho-plugin/tests/test_server.lua`
- `moho-plugin/tests/test_animation.lua`
- `bridge/scripts/ipc-integration.cjs`
- `scripts/test-ipc.py`
- `docs/ipc-v2.md`
- `docs/implementation-pass-2-summary.md`

Pass 1 changes remain present, including the batch.lua installer copy fix, smoke test and audit. They are not reintroduced in the incremental Pass 2 patch. Build output and dependency folders are generated artifacts, not source changes. The accompanying patch applies to the completed Pass 1 checkout; the ZIP contains the listed Pass 2 files.
