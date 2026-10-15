#!/usr/bin/env node
import { installLifecycle } from "./lifecycle.js";

/**
 * MohoMCP Bridge Server
 *
 * Entry point for the MCP server that bridges MCP clients (Claude Desktop,
 * Claude Code, Codex) to a MOHO Lua file-IPC server.
 *
 * Communication flow:
 *   MCP Client <--stdio--> This Bridge <--file JSON-RPC--> MOHO Lua Plugin
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { config } from "./config.js";
import { MohoClient } from "./moho-client.js";
import { registerTools } from "./tools.js";
import { registerResources } from "./resources.js";

// ---------------------------------------------------------------------------
// Bootstrap
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  process.stderr.write(
    `[moho-mcp] Starting ${config.server.name} v${config.server.version}\n`,
  );

  // Create the MCP server
  const server = new McpServer(
    {
      name: config.server.name,
      version: config.server.version,
    },
    {
      instructions: [
        "MohoMCP communicates with Moho using private file IPC. Inspect the active document and rig before writing.",
        "Respect the enabled tool filter. Do not enable unrestricted batch, screenshot, or input tools for convenience.",
        "bone_setTransform is angle-only in the validated workflow. A local session-bound approval is required.",
        "Version 2 approvals allow one inspected edit; version 3 explicitly approves a bounded same-layer two-bone transaction triggered by its first operation. Never infer transaction scope from the anchor call alone.",
        "Read back changes. Do not retry a timed-out mutation without inspecting the document. No automatic save.",
      ].join("\n"),
    },
  );

  // Create the file IPC client (connection is lazy — established on first tool call)
  const mohoClient = new MohoClient();

  // Register all MOHO tools on the MCP server
  registerTools(server, mohoClient);

  // Register static knowledge resources (shortcuts, tools reference)
  registerResources(server);

  const shutdown = installLifecycle(async () => {
    await mohoClient.disconnect();
    await server.close();
  });
  const transport = new StdioServerTransport();
  // MCP's protocol layer owns transport.onclose; use its public close hook.
  server.server.onclose = () => { void shutdown("MCP transport closed"); };
  try {
    await server.connect(transport);
    process.stderr.write("[moho-mcp] MCP server running on stdio transport\n");
  } catch (error) {
    await shutdown(`transport startup failed: ${String(error)}`, 1);
  }

}

// ---------------------------------------------------------------------------
// Run
// ---------------------------------------------------------------------------

main().catch((err: unknown) => {
  process.stderr.write(
    `[moho-mcp] Fatal error: ${err instanceof Error ? err.message : String(err)}\n`,
  );
  process.exit(1);
});
