// Run after npm run build. Never connects to Moho or launches native UI helpers.
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { Client } = require('@modelcontextprotocol/sdk/client/index.js');
const { StdioClientTransport } = require('@modelcontextprotocol/sdk/client/stdio.js');

async function main() {
  const ipcDir = await fs.mkdtemp(path.join(os.tmpdir(), 'moho-mcp-smoke-'));
  const client = new Client({ name: 'moho-audit', version: '1.0.0' });
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [path.resolve(__dirname, '../dist/index.js')],
    env: { ...process.env, MOHO_MCP_IPC_DIR: ipcDir },
    stderr: 'inherit',
  });
  try {
    await client.connect(transport);
    const { tools } = await client.listTools();
    assert.equal(tools.length, 26);
    assert.equal(new Set(tools.map(t => t.name)).size, 26);
    assert(tools.every(t => t.inputSchema.type === 'object'));
    const { resources } = await client.listResources();
    assert.deepEqual(resources.map(r => r.uri).sort(), ['moho://shortcuts', 'moho://tools']);
    for (const resource of resources) {
      const result = await client.readResource({ uri: resource.uri });
      JSON.parse(result.contents[0].text);
    }
    // No status file exists in this private test directory, so connect() must
    // fail before startKeepAlive(). Do not create a fake running status here.
    const missingServer = await client.callTool({ name: 'document_getInfo', arguments: {} });
    assert.equal(missingServer.isError, true);
    assert.match(missingServer.content[0].text, /No status file found/);
    if (process.argv[2]) {
      await fs.writeFile(process.argv[2], JSON.stringify({ tools, resources }, null, 2) + '\n');
    }
    console.log('PASS: stdio initialize, 26 tool schemas, 2 resource reads, missing-Moho error. No live Moho connection.');
  } finally {
    await client.close();
    // Only remove the directory created by mkdtemp above.
    await fs.rmdir(ipcDir);
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
