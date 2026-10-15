// Driven by scripts/test-ipc.py. Never starts native helpers or calls Moho.
const assert = require('node:assert/strict');
const helpers = require('../dist/keep-alive.js');
helpers.startKeepAlive = () => {};
helpers.stopKeepAlive = () => {};
const { MohoClient } = require('../dist/moho-client.js');
async function main() {
  {
    const client = new MohoClient();
    try {
      await client.connect();
      for (let n = 1; n <= 200; n++) {
        assert.deepEqual(await client.sendRequest('document.getInfo', {n}), {n});
      }
    } finally { await client.disconnect(); }
  }
  console.log('PASS: 200 real Node-to-Lua file IPC requests; native helpers disabled.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
