"""Real file IPC contract test, no Moho. Requires Python + Lupa with Lua 5.4.

Usage from repo root after npm run build:
  python scripts/test-ipc.py [--lua-module-dir PATH]
Install Lupa in a test venv, not as an application dependency.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('--lua-module-dir')
args = parser.parse_args()
if args.lua_module_dir:
    sys.path.insert(0, str(Path(args.lua_module_dir).resolve()))
from lupa.lua54 import LuaRuntime

repo = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='moho real IPC test ') as ipc:
    os.environ['MOHO_MCP_IPC_DIR'] = ipc
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().plugin_path = (repo / 'moho-plugin').as_posix() + '/'
    lua.execute('''
        package.path = plugin_path .. '?.lua;' .. package.path
        json = require('json')
        server = require('moho_mcp.server')
        server.init({json=json,protocol=require('moho_mcp.protocol'),validator=require('moho_mcp.validator')})
        server.registerHandler('document.getInfo',function(_,params) return {n=params.n} end)
        assert(server.start())
    ''')
    child = None
    try:
        for restart in range(2):
            child = subprocess.Popen(['node', str(repo/'bridge/scripts/ipc-integration.cjs')],
                                     cwd=repo, env=os.environ.copy(), stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, text=True)
            deadline = time.monotonic() + 60
            while child.poll() is None:
                if time.monotonic() > deadline:
                    raise TimeoutError('IPC integration exceeded 60 seconds')
                lua.execute('server.poll({})')
                time.sleep(0.001)
            stdout, stderr = child.communicate()
            print(stdout, end='', flush=True)
            if stderr:
                print(stderr, file=sys.stderr, end='')
            if child.returncode:
                raise RuntimeError(f'Node client failed: {child.returncode}')
            if (Path(ipc)/'bridge-owner.json').exists():
                raise AssertionError('Bridge ownership not released')
        print('PASS: 400 requests across two separate Node processes against the same Lua server.')
    finally:
        if child and child.poll() is None:
            child.kill()
            child.communicate()
        lua.execute('server.stop()')
