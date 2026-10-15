# MohoMCP implementation pass 1 audit

Audit date: October 14, 2026 (America/New_York).
Fork: https://github.com/Possi-xoxo/MohoMCP
Baseline commit: `d592a572d80d0de292b2b9c5866bdd0f058f8fd4`.

**Verdict:** The existing Node bridge can plausibly connect Codex to Moho through standard MCP stdio, and its MCP handshake was tested successfully with the installed SDK client. All 26 advertised tools have executable implementations. This is not evidence that their Moho API calls work in Pro 14.5. Sustained integration is blocked by a confirmed request-discovery bug, and several security and correctness issues need targeted follow-up before enabling writes or input.

No live Moho connection, GUI automation, project modification, plugin installation or global Codex configuration change occurred. No commit or push was made. The initial workspace was empty; the user supplied the fork URL and it was cloned under `work/MohoMCP`. No AGENTS.md exists in that checkout. No Moho-named installation directory was found in the two standard Program Files locations checked; this does not establish that Moho is absent elsewhere.

## Architecture and initialization

`bridge/src/index.ts` constructs SDK `McpServer`, registers tools/resources and connects `StdioServerTransport`. stdout carries MCP protocol; startup/errors use stderr. There is no TCP socket or HTTP listener despite obsolete TCP comments in index.ts/protocol.ts and a test comment. Codex launches `node bridge/dist/index.js`; it does not connect directly to the Lua plugin.

`bridge/src/tools.ts` defines the actual Zod input schemas and handlers. Twenty-three tool paths dispatch to dot-notation Lua methods, counting the scene branch of screenshot and batch. The three input tools call native platform helpers directly. Full-window screenshot also uses native capture and contacts Lua only when a frame change was requested. Two resources, `moho://shortcuts` and `moho://tools`, return static JSON and need no Moho process. Their data targets 14.4 and includes older manual/shortcut sources; it is not a verified complete 14.5 reference.

`MohoMCP_Server.lua` locates its own directory with debug.getinfo, prepends Lua package.path, loads json into `_G.json`, loads protocol/validator/server, then registers six tool modules. Module failures are warnings and do not necessarily prevent a success/start message. It wraps known global tool DrawMe methods, also polls from IsEnabled, and exposes a start/stop menu. `MohoMCP_Poller.lua` is an optional dedicated tool whose DrawMe also polls. Both use os.clock throttling and UpdateUI to encourage repaints; neither is a real background timer. Hooks are left installed after stop, gated by pollActive. Module/global caching can retain older versions until Moho restarts and can conflict with another globally loaded `json` module.

`server.lua` creates the temp directory and status.json, validates requests against a method allow-list plus required-field types, invokes handlers under pcall, and writes responses. Native Moho crashes are not catchable by Lua pcall; protected calls also do not undo partial mutations.

## File IPC lifecycle

1. Node resolves `MOHO_MCP_IPC_DIR` or `os.tmpdir()/moho-mcp`. Lua independently resolves TEMP/TMP/TMPDIR plus `moho-mcp`; it ignores the custom variable.
2. Node `connect()` checks only that status.json parses and has a truthy running field. There is no live ping, document identity, ownership authentication or freshness check. A successful check starts the native keep-alive helper.
3. Each MohoClient starts integer IDs at 1. It writes `req_N.json.tmp`, then renames it to `req_N.json`.
4. Lua polls from UI callbacks, scans integer filenames and processes at most two requests per call. A batch can contain up to 50 operations in one request, so this is not a strict UI execution-time bound.
5. Lua writes `resp_N.json.tmp`, removes any old final file, renames the temp file and removes the request. Response-write failures are ignored by poll, which still removes the request.
6. Node polls every 100 ms, reads/deletes the response, checks its JSON-RPC version and returns the result or error. It does not verify the response ID or enforce exactly one of result/error.
7. Default timeout is 10 s, screenshot 30 s, batch 10 s + 0.5 s per operation (35 s maximum). Timeout attempts to remove the request but cannot cancel an in-progress Moho operation. Disconnect stops keep-alive and clears local state; it does not cancel pending request loops.

Windows keep-alive writes a predictable `keep-alive.ps1` to the default temp IPC directory, starts hidden PowerShell with ExecutionPolicy Bypass, redraws every matching Moho window, and sends WM_MOUSEMOVE to child windows every 250 ms. Input/capture use separate PowerShell execFile calls with C# P/Invoke. Those calls lack windowsHide. A missing keep-alive executable has no child `error` handler and can terminate Node. macOS code uses osascript/cliclick/screencapture/sips; its drag ignores the right-button parameter and its middle-click path does not implement middle click. Cross-platform identity claims in README are therefore too strong.

## Tool inventory

All entries below are registered in tools.ts and have implementations, not placeholders. “Implemented” means source exists; none was verified against live Moho. IDs are discovered document absolute layer IDs and zero-based bone indices. The emitted MCP schemas are saved separately in `mcp-inventory.json`.

| MCP name | Dispatch / implementation | Actual scope and limitation |
|---|---|---|
| document_getInfo | document.getInfo / document.lua | Metadata; accessor failures silently become empty/default values |
| document_getLayers | document.getLayers / document.lua | Recursive layer tree, returned as a bare array |
| layer_getProperties | layer.getProperties / layer.lua | Layer details/current transform; fallback values can mask API mismatch |
| layer_getChildren | layer.getChildren / layer.lua | Direct children; uses IsGroupLayer, unlike IsGroupType elsewhere; verify 14.5 |
| layer_getBones | layer.getBones / layer.lua | Bone list/rest fields; bare array |
| bone_getProperties | bone.getProperties / bone.lua | Rest values, constraints and available animated channels |
| animation_getKeyframes | animation.getKeyframes / animation.lua | Layer channel whitelist only; not arbitrary bone/point channels |
| animation_getFrameState | animation.getFrameState / animation.lua | Layer channel snapshot; hidden visibility is incorrectly true |
| mesh_getPoints | mesh.getPoints / mesh.lua | Current fPos and selection, no topology or weights |
| mesh_getShapes | mesh.getShapes / mesh.lua | Shape summaries and best-effort style; no curve geometry despite README wording |
| bone_setTransform | bone.setTransform / bone.lua | Angle/position/scale keys, PrepUndo and SetDirty; partial change possible |
| bone_selectBone | bone.selectBone / bone.lua | Deselects skeleton bones and selects one; does not select its layer |
| animation_setKeyframe | animation.setKeyframe / animation.lua | translation/position/rotation/scale/opacity/shear only; vector/type assumptions |
| animation_deleteKeyframe | animation.deleteKeyframe / animation.lua | Calls DeleteKey(frame); no protection for setup frame |
| animation_setInterpolation | animation.setInterpolation / animation.lua | Five modes, key lookup then SetKeyInterp; signature/constant verification required |
| document_setFrame | document.setFrame / document.lua | SetCurFrame; no integer/range enforcement |
| layer_setTransform | layer.setTransform / layer.lua | XY translation/scale and Z rotation; constructs Vector2; verify layer channel types |
| layer_setVisibility | layer.setVisibility / layer.lua | SetVisible plus undo/dirty |
| layer_setOpacity | layer.setOpacity / layer.lua | fAlpha key; no 0..1 validation |
| layer_setName | layer.setName / layer.lua | Rename plus undo/dirty |
| layer_selectLayer | layer.selectLayer / layer.lua | SetSelLayer |
| document_screenshot | document.screenshot / document.lua OR platform-capture.ts | Scene FileRender vs full native capture; size options not applied to scene |
| input_mouseClick | platform-input.ts -> win32-input.ts | Global cursor/input after best-effort focus; no coordinate bounds |
| input_mouseDrag | platform-input.ts -> win32-input.ts | Global drag; steps unbounded; no finally release if interrupted |
| input_sendKeys | platform-input.ts -> win32-input.ts | Fixed key-code map, but shortcuts include save/delete/close |
| batch_execute | batch.execute / batch.lua | 1..50 sequential Lua operations; no rollback; screenshot/nesting blocked; input methods not registered in Lua |

The batch description overstates “all methods except screenshot and batch”: native input methods cannot be batched. `stopOnError` stops later operations, not earlier effects. Individual Zod schemas are not applied to batch operation params, which use `record(unknown)`; only the weaker Lua validation runs.

`schema/tools.json` is not loaded by either runtime. It covers only ten read tools, and some results disagree with actual handlers (wrapped objects vs bare arrays, blendMode string vs number, parent null vs -1). Public schemas and names were preserved in this pass.

## Dependency, build and test evidence

| Check | Result |
|---|---|
| npm ci, original lockfile | Passed, 143 installed packages; lockfile unchanged |
| npm run build | Passed on Node 24.14.0/npm 11.9.0, TypeScript 5.9.3 |
| npm test | 61 passed across four files after isolating keep-alive |
| Existing Lua test runner | 165 passed, 0 failed using Lupa 2.8 Lua 5.4 outside Moho |
| New stdio smoke test | Passed initialize, 26 unique object input schemas, two resource reads, expected missing-Moho error |
| In-memory Lua audit probes | Confirmed request 102 stall, hidden visibility bug, unchecked optional angle, omitted null error ID; batch module loads |
| npm audit | Exit 1: 21 affected package entries: 3 critical, 13 high, 3 moderate, 2 low |
| Live Moho 14.5 / Codex-to-Moho | Not tested |
| Installer / capture / native input / keep-alive | Reviewed statically, not executed |

The first clone/install attempts encountered restricted network access; approved retries succeeded. Initial Vitest startup failed in esbuild's config-loader directory traversal with access denied, before any tests executed. Running the same test command outside that sandbox restriction passed. These were environment failures, not TypeScript or unit-test defects. There were no failing build/tests requiring production-code repair.

The client test originally called real startKeepAlive. The only test modification mocks that module so no redraw/input helper runs. “Connected to MOHO” lines in unit logs refer to simulated IPC status files. The fake Node server enumerates filenames with readdir rather than using the Lua scanner, which explains why 61 passing tests do not detect request 102. The existing Lua suite covers JSON/protocol/validator only, not server polling or Moho handlers. The new smoke test is repeatable with `node bridge/scripts/smoke-test.cjs` after build.

Locked versions: MCP SDK 1.26.0, Zod 3.25.76, TypeScript 5.9.3, Vitest 3.2.4 and Vite 7.3.1. package.json has only SDK/Zod production dependencies. The lockfile root additionally lists `@rollup/rollup-win32-x64-msvc`; npm ci succeeded on this x64 Windows host, but that drift and macOS/ARM portability need reconciliation. Vite's Node requirement exceeds the advertised >=18. The build emits tests into dist because tsconfig includes all src files; this does not prevent launching dist/index.js.

The full npm advisory response is `npm-audit.json`. Critical package entries are proxy-addr, tinypool and vitest. Example advisories: [Vitest UI file execution](https://github.com/advisories/GHSA-5xrq-8626-4rwp), [Tinypool worker-option gadget](https://github.com/advisories/GHSA-5gmw-xhrv-c9v3), [proxy-addr IP spoofing](https://github.com/advisories/GHSA-jqcg-44mw-7w3h). The SDK entry concerns [OAuth credential forwarding](https://github.com/advisories/GHSA-6qxp-vccf-f47h). This application does not instantiate an HTTP server or OAuth client, and the tests ran in one-shot mode without Vitest UI. Advisory severity is not proof of exploitability through this stdio bridge. Triage reachable paths and update in a separate tested change; no blanket audit fix was applied.

## Security and stability findings

Severity here describes this implementation's practical impact; dependency ratings above are registry ratings. Source paths below refer to the baseline commit unless marked fixed.

| ID / severity | Evidence and impact | Disposition |
|---|---|---|
| S1 High | `server.lua:110-127`: scanner restarts at 1, stops after >100 misses, caps at 10000. After requests 1..101 are removed, 102 is invisible. Startup/stop cleanup has the same blind spot. Dead discoverCurrentIdRange also references undeclared lastSeenMaxId. | Confirmed with in-memory sequential requests; resolve before sustained use |
| S2 High | `moho-client.ts:22,105-138`, `protocol.ts:parseResponse`: all clients reuse IDs, no response-ID/session validation. Parallel clients, stale responses or a restart can return wrong data or overwrite requests. | Single instance during initial test; session design and restart tests needed |
| S3 High | `tools.ts:685-689`: screenshot response filePath is read and then unlinked without confinement, type/size checks or PNG verification. A process able to write forged IPC responses can cause arbitrary accessible-file disclosure and deletion. | No exploit executed; fix before screenshot exposure |
| S4 High | `win32-input.ts:FIND_MOHO_WINDOW/sendMouse*`: regex matches first process, focus result ignored, coordinates not clamped. Input is global; focus changes/out-of-bounds clicks can affect other apps. Huge steps can outlive 15 s timeout and leave a button down. | Native input excluded from example; bounds, focus identity, serialized input and finally-release needed |
| S5 High (integrity) | `validator.lua`, `tools.ts:batch_execute`, transform handlers: required-field type checking only, optional values unchecked in raw IPC/batch, fractional/negative IDs/frames and invalid ranges accepted. Multi-field transforms may mutate before returning error, with no rollback and sometimes no SetDirty on failure. | Validate fully before mutation; test undo/partial failures before writes |
| S6 Medium | IPC uses predictable per-user temp filenames, no authentication/explicit ACL/ownership/reparse-point check. Anyone who can write that directory can submit allowed mutations or forge replies. It is not demonstrated world-writable; actual Windows ACLs were not audited. | Document same-account trust boundary; inspect ACLs and isolate sessions in Pass 2 |
| S7 Medium | `keep-alive.ts`: predictable script file executed after write, inherited profile (no NoProfile), ExecutionPolicy Bypass, no spawn error handler; connection flag is set before startup. Orphan/race behavior and multi-instance cleanup are unhandled. | Controlled helper lifecycle and secure temp creation needed |
| S8 Medium | `server.lua:332`: response-write return ignored, request then deleted; status write unchecked and no heartbeat. Timeouts do not cancel side effects; Lua UpdateUI hooks can re-enter while a request still exists. | Error propagation, polling reentrancy guard, liveness tests |
| S9 Medium | `animation.lua:278`: `visOk and (vis == true) or true` always returns true for false visibility. `document.lua:264-305`: width/height returned but never passed to FileRender. | Confirmed visibility probe; screenshot defect from direct source inspection; left explicit for Pass 2 |
| S10 Medium | `install-plugin.bat`: fixed paths, copy /Y overwrite, no failure gates/backups, success printed regardless. It omitted batch.lua, so advertised batch was missing after installer use. | Missing copy fixed locally; remaining installer issues documented, installer not run |
| S11 Medium | `server.lua`, `document.lua`: temp-path strings interpolated into shell commands. Environment paths with quotes/expansion syntax are not escaped robustly; screenshots/readFiles have no size bounds and JSON has no depth limit. | Environment/local IPC threat, not a demonstrated remote code-execution tool; harden separately |
| S12 Low/Medium | `protocol.lua` omits id for nil parse-error IDs, uses parse error for structural invalid requests; JSON decode loses empty object identity. Node validates only version; docs promise app error codes Lua never emits. | Tighten protocol tests/validation without changing tool names |
| S13 Medium (compatibility) | pcall fallbacks return plausible metadata/default transforms despite missing API; getChildren uses IsGroupLayer while siblings use IsGroupType; layer transforms construct Vector2; interpolation uses SetKeyInterp(index, mode, 0, 0); styles may be animated/userdata. | Verify on 14.5 shipped scripts/API, do not infer compatibility from success flag |

No registered eval/exec/loadstring tool or user-supplied executable path was found. JSON is decoded by a parser, not evaluated as Lua. Windows key names map to fixed numeric codes and capture paths escape single quotes; those are useful controls. Nevertheless the bridge deliberately provides powerful native automation, and the Lua method allow-list is not an authorization boundary against local IPC writers. No broad security changes were silently introduced.

Additional 14.5 concerns: tool global names/callback signatures, IsLocked/CurrentFrame accessors, 3D layer channel types and Z preservation, frame offsets/actions vs document frame numbers, color channel extraction, rendering behavior during DrawMe, modal/minimized-window polling, DPI/multi-monitor coordinates, multiple documents and undo behavior. These remain hypotheses to verify, not asserted API incompatibilities. The repository's Lua 5.4 assumption was tested only in a standalone 5.4 runtime. Public vendor scripting material found during research did not establish all 14.5 signatures.

## Changes made and files supplied

Local repository changes:

1. `install-plugin.bat`: add missing batch.lua copy; no installer execution.
2. `bridge/src/__tests__/moho-client.test.ts`: mock native keep-alive to keep unit tests isolated.
3. `bridge/scripts/smoke-test.cjs`: new non-GUI stdio smoke test.
4. `docs/implementation-pass-1-audit.md`: this audit and full tool inventory.
5. `docs/windows-codex-setup.md`: installation and integration procedure.
6. `docs/codex-mcp.windows.example.toml`: inactive example with query-only tool filter.

No tool registration names, schemas, dependency manifests/lockfile, production bridge logic or Lua handlers changed. The unresolved defects above remain present. A patch deliverable and copies of the documentation are in the chat outputs directory, along with MCP inventory, dependency advisory JSON, Lua results and probe evidence. Generated node_modules/dist and workspace-only Lua runtime/probes are not source changes. The scope is an audit/preparation pass, not production certification.

## Pass 2 order and acceptance criteria

1. Repair request discovery with tests for >150 sequential calls, large IDs, gaps, bridge restart and cleanup; avoid a new shell process on every repaint. Add a polling reentrancy guard and detect response-write failure. Keep the existing tool schemas.
2. Correct false visibility and align IPC configuration on both sides. Validate each advertised Moho API against 14.5 before changing signatures; create mocked handler tests for confirmed defects.
3. Add request/response correlation and a session/single-owner strategy; document migration compatibility with original bridge/plugin pairs. Add stale/forged response and concurrent-client tests.
4. Constrain screenshot file access and enforce complete Lua validation, finite/range rules and partial-failure/undo behavior. Harden helpers/input independently. Triage npm advisories and lockfile/platform drift with targeted upgrades.
5. Follow the Windows guide: verify Moho version and scripts paths, back up existing scripts, install manually, open disposable content, start the Lua server, manually add the example config with correct absolute paths and enable it, then query document/layers. Record exact outputs and compare against the UI manually.
6. Prove 150+ read requests work and restart recovery is correct. Only then expand to transform/interpolation/undo tests, followed by screenshots and input in separately controlled steps. No new animation capabilities yet.

Before the next live pass the user must supply/verify the actual Moho 14.5 scripts location, prepare disposable content, perform the manual plugin installation and Codex config edit, and agree to a live test that starts the native keep-alive. The exact commands and folder layout are in `windows-codex-setup.md`. Implementation work on the blockers can proceed before those manual actions.
