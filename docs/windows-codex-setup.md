# Windows / Moho Pro 14.5 / Codex setup

This guide prepares the Possi-xoxo/MohoMCP fork audited at commit
`d592a572d80d0de292b2b9c5866bdd0f058f8fd4`. No live Moho 14.5 connection was tested.
The audit checkout is at
`C:\Users\Blake\Documents\Codex\2026-10-14\mohomcp-implementation-pass-1-repository-audit\work\MohoMCP`.
Keep it or move/copy it to a permanent location before configuring Codex.

## 1. Prerequisites

- Windows 10/11 and a licensed Moho Pro 14.5 installation. Verify the exact version and installation location manually; neither was established in this pass.
- Native Windows Node.js and npm. Node 24.14.0/npm 11.9.0 were tested. Although package.json says Node >=18, the locked Vite requires `^20.19.0 || >=22.12.0`; use the tested Node 24 environment for this checkout.
- Codex running locally on the same Windows computer and user account as Moho. WSL/Linux Node will choose unsupported input/capture backends and a different temp directory.
- Windows PowerShell (`powershell.exe`), .NET `Add-Type`, `System.Drawing`, and `user32.dll`. These support keep-alive, capture and input. PowerShell restrictions can block them. No Python, separate Lua, LuaSocket, Visual Studio compiler, or external automation package is required by the bridge itself. Standalone Lua 5.4 is useful only for tests.
- Git if obtaining another checkout. Keep only one bridge and one Moho instance active during initial integration: IPC v2 enforces one bridge owner; use only one Moho instance per IPC directory.

## 2. Build and verify without Moho

From PowerShell, replace the checkout path below:

```powershell
Set-Location 'C:\path\to\MohoMCP\bridge'
node --version
npm.cmd --version
npm.cmd ci
npm.cmd run build
npm.cmd test
node scripts/smoke-test.cjs
```

Use the local changes from this pass: the test mock prevents native UI helpers from launching. The smoke test uses a fresh private IPC directory with no status file; it initializes MCP, lists 26 tools, reads both resources and verifies the missing-Moho error. It is not a live connection test.

With standalone Lua 5.4 installed, from the repository root:

```powershell
lua moho-plugin/tests/run_tests.lua
```

The audit used workspace-isolated Lupa 2.8's Lua 5.4 runtime for these tests, not Moho's embedded runtime. The lockfile currently has dependency advisories; see the audit before enabling broad use. Do not run `npm audit fix --force` as part of setup.

## 3. Install the Lua files manually when ready

No installation was performed during Pass 1 or Pass 2. IPC v2 requires updating BOTH the bridge and Lua plugin together; do not mix versions. Close Moho before copying files, and back up any existing MohoMCP plugin and tool-list file.

Identify the scripts directory used by your actual Moho 14.5 installation or its configured custom-content folder. Do not assume the repository's hard-coded `C:\Program Files\Moho 14` is correct. The built-in layout assumed by the installer is `Resources\Support\Scripts\Menu` and `Resources\Support\Scripts\Tool`; a custom-content location must be confirmed in your installation.

Under the chosen **Menu** directory, create `MohoMCP` and copy this exact structure:

```text
Menu/MohoMCP/
  MohoMCP_Server.lua
  json.lua
  moho_mcp/
    server.lua
    protocol.lua
    validator.lua
    tools/
      document.lua
      layer.lua
      bone.lua
      animation.lua
      mesh.lua
      batch.lua
```

Copy `moho-plugin/MohoMCP_Poller.lua` into the chosen **Tool** directory, not Menu. If the toolbar requires explicit registration, back up its `_tool_list.txt`, follow the existing group layout and add one entry with actual tab separators:

```text
tool<TAB>MohoMCP_Poller<TAB>...
```

Here `<TAB>` means a real tab character. Do not replace the full tool list. Check the poller appears after restarting Moho. The patched BAT now includes batch.lua but still hard-codes paths, overwrites plugin files and does not stop on copy failure; manual installation is preferable for this first verification. Program Files writes may require administrator permission for copying; run Moho and Codex normally under the same user afterward.

## 4. Prepare the IPC directory and start the Moho side

Pre-create the IPC directory before starting the Lua server. Lua deliberately does not run shell commands to create it. For the default:

```powershell
New-Item -ItemType Directory -Path (Join-Path $env:TEMP 'moho-mcp') -Force
```

For a custom location, create an absolute local directory and set `MOHO_MCP_IPC_DIR` to exactly that path in the environments of **both Moho and the bridge before launching them**. Setting it only in Codex's MCP configuration does not set Moho's environment. Spaces are supported. Prefer a directory writable only by your account. Avoid network shares. Default Windows resolution is TEMP, then TMP, plus `moho-mcp`; ensure those environments agree. If neither is defined, set the explicit override.


1. Open Moho Pro 14.5 and create/open a disposable test document containing a group, vector layer and bone layer. Use a copy, never a production project.
2. Choose **Scripts > MohoMCP > Start/Stop MohoMCP Server** (menu nesting can depend on installation location).
3. In the script console, verify module registration, including `batch.execute`, and the server-start message. A start dialog alone is insufficient: the loader tolerates missing handler modules.
4. Select **MohoMCP Poller** for the initial test and keep Moho visible. Other tools are wrapped by DrawMe hooks but must be verified individually in 14.5.
5. Note the IPC directory shown by the plugin. With matching default environments it should be `%TEMP%\moho-mcp\`. Inspect the status file from PowerShell:

```powershell
Get-Content (Join-Path $env:TEMP 'moho-mcp\status.json')
```

`running: true` only proves a file was written. IPC v2 adds `ipcVersion: 2`, a server-instance token and the resolved directory. The bridge sends an internal ping challenge before reporting connected. Missing status errors show the bridge's expected path; compare it with the plugin console. A directory mismatch detected in status is rejected. A stale status with no polling times out.

## 5. Configure and launch the bridge through Codex

Review `codex-mcp.windows.example.toml`. Replace its Node and repository paths and manually merge the table into either `%USERPROFILE%\.codex\config.toml` or the trusted project's `.codex\config.toml`. Back up an existing config and merge rather than overwrite it. Set `enabled = true` only when ready for the live test. No global settings were changed in this pass.

Codex supports local stdio servers using `command`, `args`, `cwd` and tool filters in TOML. The fork's `.mcp.json.example` is a different client's format. See the [official MCP documentation](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).

Restart the Codex MCP connection/app after the manual edit. Codex launches the Node bridge itself; do not also leave a second `npm start` bridge running. For a standalone launch diagnostic only:

```powershell
& 'C:\Program Files\nodejs\node.exe' 'C:\path\to\MohoMCP\bridge\dist\index.js'
```

It should log that MCP is running on stdio and wait for protocol input. Stop it with Ctrl+C before using Codex. A waiting process does not establish Moho connectivity. There is no TCP port or HTTP URL to configure.

The example exposes ten query tools and omits batch, writes, input and screenshots for the first test. This is a client filter, not IPC authentication. Even a query starts the production keep-alive after it sees status.json; that helper redraws Moho and posts synthetic mouse-move messages. Plan the live test accordingly. None of this automation was run in Pass 1 or Pass 2; automated tests replace native helpers with no-ops.

## 6. Confirm real connectivity in Pass 3

1. If using the CLI, `codex mcp list` confirms registration; `/mcp` shows active connections in the Codex TUI. Registration alone is insufficient.
2. Ask Codex to call `document_getInfo` and `document_getLayers` only. Compare the returned name, dimensions, FPS, current frame and layer names against the disposable document manually. Fallback zero/default values are not proof of API compatibility.
3. Query a discovered layer ID and bone ID. Do not guess IDs. Capture the request, result, script-console diagnostics and exact Moho version.
4. Run 200 sequential read calls, including calls 101–103, and compare results. Pass 2 simulated these successfully, but Moho polling still needs live validation. Disconnect and reconnect the bridge, then restart the Lua server and verify explicit reconnect. Do not blindly retry timed-out writes: timeout does not cancel a handler already executing.
5. Test nested-group access, hidden-layer reporting, channel types, interpolation signatures and undo on disposable content before expanding the tool filter. Width/height overrides for scene screenshots are currently ineffective. Input/capture require their own explicit later test.

If no status file appears, check plugin loading and the two temp paths. If requests time out, inspect polling/tool selection, PowerShell availability, script errors and request IDs. If a response returns but contains defaults, verify the relevant 14.5 API accessor. To stop, disconnect the Codex bridge, toggle the Moho server off, and close the disposable document without saving unwanted changes.

## 7. Ownership conflicts and crash recovery

A second bridge is rejected while `bridge-owner.json` exists. Graceful disconnect releases it; a killed/crashed bridge can leave it behind. Locks are intentionally never stolen automatically, including apparently dead PIDs.

1. Disconnect Codex's MCP server and stop any standalone bridge. Stop the Moho-side server; closing Moho is safest if its state is uncertain. Confirm no bridge or Lua server still uses this directory. A PID in the owner file is diagnostic, not proof of safety because PIDs can be reused.
2. Inspect the disposable document before retrying any mutation whose result was lost. Save only if you intentionally want those changes.
3. In the verified IPC directory only, manually remove `bridge-owner.json`, `request.json`, `request.json.tmp`, `response.json`, `response.json.tmp`, `status.json`, and `status.json.tmp` if present. Do not delete unrelated files or directories. Old `req_*.json`/`res_*.json` files are ignored by v2; archive/remove those only after confirming all legacy processes are stopped.
4. Restart the Lua server, then reconnect Codex. The new ping must succeed. If the server epoch changes during a request, reconnect explicitly; the bridge never replays the interrupted operation automatically.

See [IPC v2 architecture](ipc-v2.md) and [Pass 2 results](implementation-pass-2-summary.md). Screenshots, input automation, mutation validation, and dependency advisories remain blockers to broader use.
