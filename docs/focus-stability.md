# Moho text-entry focus investigation

## Findings

Read-only process inspection found one live bridge and one Windows keep-alive helper parented to that bridge. No duplicate or orphan helper was detected. No processes were terminated during investigation.

The previous Windows helper ran every 250 ms, unconditionally calls RedrawWindow(INVALIDATE | UPDATENOW | ALLCHILDREN) for every matching Moho process, enumerates all child windows and posts WM_MOUSEMOVE at (0,0) to each. This includes controls unrelated to the canvas. Both the dedicated Poller and wrapped editing-tool DrawMe callbacks also repeatedly call moho:UpdateUI(). These are strong candidates for the repeated loss of text-control focus, but which mechanism is decisive has NOT yet been isolated live.

RedrawWindow itself is not a SetFocus operation. However UPDATENOW invokes painting before returning and ALLCHILDREN includes child controls; application paint/mouse/UI handlers may refresh or recreate controls. Synthetic mouse messages are not harmless repaint signals. The separate Lua UpdateUI loop means disabling only the native helper may not fully resolve the problem.

Primary references:
- https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-redrawwindow
- https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getlastinputinfo

## Implemented focus fix

- Remove all synthetic mouse messaging and activation behavior from the helper.
- Remove recurring UpdateUI calls from MohoMCP_Server.lua and MohoMCP_Poller.lua. Natural DrawMe callbacks continue to poll and preserve the wrapped tool's original drawing callback.
- Windows helper requests ordinary asynchronous invalidation only (0x0081), at most 4 Hz, only while a nonexpired IPC request matches its owner/session/server. No pending request means no artificial repaint.
- Suppress repaint whenever Moho (including its dialogs) is foreground, the window is hidden/minimized, input was received within 1500 ms, UI/state checks fail, or more than one Moho process exists. This intentionally avoids relying on recognizing Moho's custom text-control class names.
- Never change focus or use synthetic input. Natural UI events can still satisfy requests; otherwise a request waits for safe background repaint. Long foreground work/input can cause a normal request timeout. Do not blindly retry mutations after timeout.
- Helper scripts use unique directories inside the configured private IPC directory rather than a shared temp script. Arguments are passed separately, including paths containing spaces.
- A dedicated background reader detects stdin EOF and ends the helper when its bridge dies, avoiding PID-reuse assumptions. Normal shutdown also closes stdin and stops only the exact owned child. Old child exit handlers cannot clear a newer helper's state. Empty script directories may remain after abrupt parent termination, but the process exits; do not delete ambiguous ownership files.
- The old macOS frontmost-activation fallback is removed as well; macOS falls back to natural repaint and has not been validated in this Windows pass. Linux behavior remains natural repaint.

Following explicit approval, the two focus-related Lua files were backed up and installed, and a focus-only bridge build was activated through a normal Codex restart. Pending Pass 7 bridge descriptions and transaction changes were excluded. MCP access was narrowed to the ten query tools. No project writes were performed. Pass 7 multi-bone source changes remain separate, pending installation approval.

## Tests

- TypeScript: 85 passed (8 new keep-alive tests).
- Actual C# decision policy: all 64 combinations of pending/ownership/visibility/foreground/idle-threshold conditions passed; no user32 function invoked.
- PowerShell helper parsed successfully and C# compiled.
- Real helper with an empty isolated mailbox stayed alive with stdin open and exited on EOF; no request existed, so no UI calls were made.
- Mocked lifecycle tests cover unique private script paths, one helper per owner, cleanup, spawn failure, old/new helper races, and no synthetic-input/activation API.
- Lua: 308 passed, including Poller and wrapped tool callbacks processing 100 paints without UpdateUI and retaining original drawing behavior.
- Isolated TypeScript compilation passed.
- One initial run exposed a Windows unlink/sharing race in the existing test server's exists/read mock. It now tolerates ENOENT/EPERM/EACCES for that transient read; the complete rerun passed with no unhandled errors. No production IPC error handling was weakened.

## Approval-gated live check

First report these findings and obtain approval to change the live runtime/plugin. User saves their rig manually as desired and closes Moho normally. Back up/install ONLY MohoMCP_Server.lua and MohoMCP_Poller.lua for this fix; do not install pending Pass 7 transaction code implicitly. Activate the tested bridge build via normal Codex shutdown/restart (old helper must exit; inspect identity before removing any proven orphan). Restart Moho once through the existing shared launcher.

With the Lua server/Poller active, user types in a bone-name or property field for 20–30 seconds. Codex does not rename anything or send a write. Confirm no focus loss, both while connected-idle and during a bounded read-only query. Switch focus to Codex and confirm a small number of queries succeed with background repaint. Check helper count and normal close/reconnect cleanup. If repaint-only cannot wake DrawMe reliably, report the limitation and investigate a supported Moho timer; do NOT restore simulated mouse input or recurring global UpdateUI as a workaround.

The approved live check passed on October 15, 2026. After normal restarts, document metadata, layer hierarchy, and all ten bones were read successfully. Two additional reads during the requested typing window succeeded in 2.406 seconds (document metadata) and 1.883 seconds (bones). The user confirmed continuous typing without focus loss and that Moho remained responsive. Process inspection confirmed the old helper was gone and one new helper belonged to the active IPC owner; two bridge processes were present, but only one held ownership and had a helper. No project mutations were issued. This verifies the combined fix in this session, not which original mechanism caused the problem in isolation. A scheduling race between checking input and painting cannot be eliminated completely; long foreground interaction may still defer requests or cause a timeout.

## Files changed for this fix

- bridge/src/keep-alive.ts
- bridge/src/moho-client.ts (pass private directory/session/server to helper)
- bridge/src/__tests__/keep-alive.test.ts (new)
- bridge/src/__tests__/moho-client.test.ts (test mock race handling)
- moho-plugin/MohoMCP_Server.lua
- moho-plugin/MohoMCP_Poller.lua
- moho-plugin/tests/test_focus_polling.lua (new)
- moho-plugin/tests/run_tests.lua
- docs/focus-stability.md


## Current outcome through Pass 8.3

The user confirmed continuous typing and responsiveness after the original focus
fix. Later diagnostics isolated background request starvation caused by the global
input-idle gate. The current helper removes that gate only from the already
background-only eligibility policy and rechecks foreground status before painting.
No synthetic input, activation or recurring Lua UpdateUI calls were restored.
The bridge reconnected without restarting Moho and completed the approved breathing
transaction plus independent readback. The user confirmed successful animation
and responsiveness; a separate post-adjustment continuous-typing test was not
repeated. See implementation-pass-8-3.md for final results and remaining limits.
