# Unified Windows deployment

Requires Windows 10/11, Moho Pro 14.5, Node.js 18+ and npm. Package preparation
needs registry access. No Python is required for deployment. Lua regression tests
need a separate Lua 5.4 runner; they never require the live Moho application.

## Three separate stages

1. Development: change repository files, run bridge/Lua/deployment tests. Never
   copy individual modules into the live plugin as part of development.
2. Deployment: prepare a complete package, inspect its preview and obtain approval.
   Close Moho and Codex normally; run deployment from an independent PowerShell
   window. Do not launch Moho as a child of Codex. Install the complete release.
3. Live verification: reopen Moho via the existing IPC launcher and reconnect Codex.
   Inspect a disposable project read-only. Installation permission is not binding
   or animation-write permission. Record live results separately from mocks.

Lua modules are cached by require and callbacks retain references. No supported
safe hot reload has been established; do not clear package.loaded in live Moho.
A Lua release needs one normal Moho restart. The Node bridge can restart separately
while Moho remains open, using existing ownership recovery. Ordinary edits need
neither restart. The first unified migration updates both components together.

## Commands

Create a private JSON profile outside Git containing absolute `mohoExecutable`,
`scriptsRoot` (the actual custom Scripts directory), `bridgeRoot` (dedicated runtime,
not the development checkout), and `stateRoot` (separate deployment records/backups).
All three directories must be disjoint. IPC stays in its existing private directory;
this installer never changes its ACLs or contents.

From the repository root:

```powershell
.\Deploy-MohoMCP.ps1 -Action Prepare -Package C:\Packages\MohoMCP-release
.\Deploy-MohoMCP.ps1 -Action Preview -Profile C:\Private\deployment.json -Package C:\Packages\MohoMCP-release -Output C:\Private\preview.json
# After approval, with Moho and its bridge closed:
.\Deploy-MohoMCP.ps1 -Action Install -Profile C:\Private\deployment.json -Package C:\Packages\MohoMCP-release
.\Deploy-MohoMCP.ps1 -Action Verify -Profile C:\Private\deployment.json
.\Deploy-MohoMCP.ps1 -Action Update -Profile C:\Private\deployment.json -Package C:\Packages\MohoMCP-next
.\Deploy-MohoMCP.ps1 -Action Rollback -Profile C:\Private\deployment.json -Backup C:\Private\State\backups\EXACT-BACKUP-ID
.\Deploy-MohoMCP.ps1 -Action Uninstall -Profile C:\Private\deployment.json
```

Prepare uses npm ci with the lockfile and lifecycle scripts disabled, compiles in
an isolated staging directory, prunes development dependencies, and includes all
runtime dependencies. It does not touch the live bridge or plugin. Use a new output
directory each time; a failed preparation remains for diagnosis and is not deployed.

Preview validates SHA-256 inventory, Lua modules/dependencies, compiled release
metadata, target paths, Moho 14.5 and existing custom tool-list registration. An
existing custom `_tool_list.txt` that omits the Poller causes a clear stop; its
registration must be approved before proceeding. No custom tool list is replaced.

Install supports migration from the earlier manually copied plugin. The full old
plugin directory and every replaced owned file (including Poller) are backed up.
Only manifest-owned files are overwritten; unrelated scripts are preserved.
Update first verifies the existing installation. Unexpected manual edits stop
verification rather than silently being overwritten. Backups and manifests use
local absolute paths and must stay out of Git.

Rollback restores the immediate predecessor and verifies backup hashes before
restoring. Newly introduced files are removed individually, never recursive target
directories. Uninstall removes only unchanged files of a fresh managed install;
for a migrated or updated install, first roll back predecessors. Existing legacy
files are restored, not deleted. User projects, Codex configuration, unrelated
scripts and backups are never uninstalled.

## Verified startup and compatibility

After separate configuration approval, use Node to launch
`scripts/launch-installed.mjs <absolute-private-profile>` from this toolkit instead
of the development dist/index.js. The launcher verifies every installed hash and
refuses active/incomplete deployments before importing the installed bridge. Retain
existing IPC environment and tool filter; initially expose only queries and
attachment_inspect. The installer never edits global Codex configuration.

`release.json`, Lua version.lua and bridge compatibility.ts define release 0.9.2,
IPC v2 and supported Moho 14.5. Lua advertises toolkitVersion in status and the bridge
includes it in every request. Both sides reject non-read-only methods when versions
are missing or mismatched. Legacy read-only diagnosis remains possible. Matching
versions do not bypass session, inspection, ownership or approval validation.
Startup hash verification is also required: semantic version equality alone cannot
prove a complete installation. The legacy direct index.js entry is retained for
compatibility but lacks the installed-manifest startup check; use the guarded
launcher for managed deployment.

Multi-directory installation is not an atomic filesystem transaction. A journal
blocks guarded startup until completion. Ordinary copy failure automatically
restores verified backups. If power loss interrupts deployment, preserve the journal
and backup, close all Moho/bridge processes, and use Rollback with the journal's
exact backup. It refuses files with unrecognized content. A surviving operation.lock
is intentionally not auto-deleted: verify no deployment is running and obtain
explicit approval before removing only that lock. Rollback failures remain explicit;
never bypass the journal to launch or retry a write.

## Tests and release readiness

- TypeScript package compilation: passed.
- Bridge suite: 122 passed, including end-to-end pre-publication version rejection.
- Lua suite: 364 passed, including Lua pre-dispatch version rejection.
- Isolated deployment suite: 18 cases, no live installer invocation.
- Pass 9.1 binding, illustrated arm motion and animation-key Undo were live-verified;
  see implementation-pass-9-1.md for evidence and remaining limitations.
- No project modifications or bindings are part of deployment verification.

Run `node --test scripts/deployment.test.mjs`, `npm test` in bridge, and the existing
Lua test runner. Fixtures exercise missing/corrupted modules, metadata mismatch,
backup integrity, injected failures, rollback/recovery, repeated install, migration,
uninstall, protected unrelated files and unsafe paths. Package hashes detect damage,
not malicious publishers: deploy only trusted locally prepared releases.
