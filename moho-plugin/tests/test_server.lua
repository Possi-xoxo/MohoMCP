-- In-memory IO: never opens Moho, a shell, or the real IPC directory.
local function fixture(body)
    local originals = {open=io.open,popen=io.popen,remove=os.remove,rename=os.rename,
        getenv=os.getenv,tmpname=os.tmpname,execute=os.execute}
    local files, state = {}, {calls=0,failWrite=false,failRename=false,unique=0}
    local root = package.config:sub(1,1) == "\\" and "C:/IPC test & literal % path" or "/tmp/IPC test & literal $ path"
    os.getenv=function(name) if name=="MOHO_MCP_IPC_DIR" then return root end end
    io.popen=function() error("unexpected shell process") end
    os.execute=io.popen
    os.tmpname=function() state.unique=state.unique+1; return "unique"..state.unique end
    io.open=function(p,mode)
        if mode=="wb" then
            if state.failWrite and p:find("response.json",1,true) then return nil,"disk full" end
            return {write=function(self,s)
                if state.failDataWrite and p:find('response.json',1,true) then return nil,'write failed' end
                files[p]=s; return self
            end,close=function() return true end}
        end
        if files[p] then return {read=function(_,limit) return files[p]:sub(1,limit) end,close=function() return true end} end
        return nil,"missing"
    end
    os.remove=function(p) files[p]=nil; return true end
    os.rename=function(a,b)
        if state.failRename and b:find("response.json",1,true) then return nil,"rename denied" end
        files[b]=files[a];files[a]=nil;return true
    end
    package.loaded['moho_mcp.server']=nil
    local server=require('moho_mcp.server')
    server.init({protocol=require('moho_mcp.protocol'),validator=require('moho_mcp.validator'),json=json})
    local ok,err=pcall(function()
        assert_true(server.start())
        local dir=server.getInfo().ipcDir
        files[dir..'bridge-owner.json']=json.encode({session='session-one'})
        local function request(id, extra)
            local r={jsonrpc='2.0',ipcVersion=2,serverId=server.getInfo().serverId,
                session='session-one',id=id,method='document.getInfo',params={},expiresAt=os.time()*1000+60000}
            for k,v in pairs(extra or {}) do r[k]=v end
            files[dir..'request.json']=json.encode(r)
            files[dir..'response.json']=nil
        end
        local function response() return json.decode(files[dir..'response.json']) end
        server.registerHandler('document.getInfo',function()
            state.calls=state.calls+1
            if state.reenter then server.poll({}) end
            return {count=state.calls}
        end)
        body(server,files,state,dir,request,response)
    end)
    io.open,io.popen,os.remove,os.rename,os.getenv,os.tmpname,os.execute=
        originals.open,originals.popen,originals.remove,originals.rename,originals.getenv,originals.tmpname,originals.execute
    package.loaded['moho_mcp.server']=nil
    if not ok then error(err) end
end

test('poll: reproduces old request-102 blind spot, v2 handles 200 sequential requests',function()
    -- Original algorithm stops after 101 misses before reaching ID 102.
    local found=false
    local misses=0
    for id=1,10000 do
        if id==102 then found=true; break else misses=misses+1 end
        if misses>100 then break end
    end
    assert_false(found)
    fixture(function(s,files,state,dir,request,response)
        for id=1,200 do
            request(id);s.poll({});assert_eq(response().id,id);assert_eq(response().result.count,id)
            files[dir..'request.json']=nil;files[dir..'response.json']=nil
        end
        assert_eq(state.calls,200)
    end)
end)
test('poll: failed data write is retried without reexecution',function()
    fixture(function(s,_,state,_,request,response)
        state.failDataWrite=true;request(1);s.poll({});assert_eq(state.calls,1)
        state.failDataWrite=false;s.poll({});assert_eq(response().result.count,1);assert_eq(state.calls,1)
    end)
end)
test('poll: serialization failure cannot reexecute a completed mutation',function()
    fixture(function(s,_,state,_,request,response)
        s.registerHandler('document.getInfo',function() state.calls=state.calls+1;return function() end end)
        request(1);s.poll({});s.poll({});assert_eq(state.calls,1);assert_eq(response().error.code,-32603)
    end)
end)
test('startup: missing/unwritable directory is explicit and does not launch shell',function()
    fixture(function(s)
        s.stop();local old=io.open
        io.open=function() return nil,'access denied' end
        local ok,err=s.start();io.open=old
        assert_false(ok);assert_true(err:find('Pre-create',1,true));assert_false(s.isRunning())
    end)
end)
test('config: Windows TEMP or POSIX TMPDIR default matches Node precedence',function()
    fixture(function(s)
        s.stop();local windows=package.config:sub(1,1)=='\\'
        os.getenv=function(name)
            if name=='TEMP' then return 'C:/temp primary' end
            if name=='TMP' then return 'C:/temp secondary' end
            if name=='TMPDIR' then return '/tmp/primary' end
        end
        assert_true(s.start());assert_true(s.getInfo().ipcDir:find(windows and 'C:/temp primary' or '/tmp/primary',1,true))
    end)
end)
test('poll: noncontiguous and large numeric/string IDs do not affect discovery',function()
    fixture(function(s,_,state,_,request,response)
        for _,id in ipairs({1,102,999999999,9007199254740991,'uuid-like-request'}) do
            request(id);s.poll({});assert_eq(response().id,id)
        end
        assert_eq(state.calls,5)
    end)
end)
test('poll: repeated and reentrant callbacks execute a request once',function()
    fixture(function(s,_,state,_,request,response)
        state.reenter=true;request(1);s.poll({});s.poll({});assert_eq(state.calls,1);assert_eq(response().result.count,1)
    end)
end)
test('poll: malformed request gets error and next request is processed',function()
    fixture(function(s,files,state,dir,request,response)
        files[dir..'request.json']='{broken';s.poll({});assert_eq(response().error.code,-32700)
        request(200);s.poll({});assert_eq(state.calls,1);assert_eq(response().id,200)
    end)
end)
test('poll: response open failure retains request and retries without mutation replay',function()
    fixture(function(s,files,state,dir,request,response)
        state.failWrite=true;request(1);s.poll({});s.poll({})
        assert_eq(state.calls,1);assert_true(files[dir..'request.json']);assert_true(s.getInfo().lastError)
        state.failWrite=false;s.poll({});assert_eq(response().result.count,1);assert_eq(state.calls,1)
    end)
end)
test('poll: response rename failure retries without mutation replay',function()
    fixture(function(s,_,state,_,request,response)
        state.failRename=true;request(1);s.poll({});assert_eq(state.calls,1)
        state.failRename=false;s.poll({});assert_eq(response().result.count,1);assert_eq(state.calls,1)
    end)
end)
test('poll: expired request never dispatches',function()
    fixture(function(s,_,state,_,request,response)
        request(1,{expiresAt=0});s.poll({});assert_eq(response().error.code,-32600);assert_eq(state.calls,0)
    end)
end)
test('poll: wrong session or old server cannot mutate',function()
    fixture(function(s,_,state,_,request,response)
        request(1,{session='other'});s.poll({});assert_true(response().error)
        request(2,{serverId='old'});s.poll({});assert_true(response().error);assert_eq(state.calls,0)
    end)
end)
test('poll: server restart rejects pending old-instance request',function()
    fixture(function(s,_,state,_,request,response)
        request(1);local old=s.getInfo().serverId;s.stop();assert_true(s.start())
        assert_true(old~=s.getInfo().serverId);s.poll({});assert_true(response().error);assert_eq(state.calls,0)
    end)
end)
test('poll: new bridge owner can proceed after abandoned failed response',function()
    fixture(function(s,files,state,dir,request,response)
        state.failWrite=true;request(1);s.poll({})
        files[dir..'bridge-owner.json']=json.encode({session='new-owner'})
        state.failWrite=false;request(1,{session='new-owner'});s.poll({})
        assert_eq(response().session,'new-owner');assert_eq(state.calls,2)
    end)
end)
test('poll: ping establishes liveness without Moho API',function()
    fixture(function(s,_,state,_,request,response)
        request('ping',{method='ipc.ping'});s.poll(nil);assert_true(response().result.alive);assert_eq(state.calls,0)
    end)
end)
test('poll: handler exception does not wedge guard or repeat handler',function()
    fixture(function(s,_,state,_,request,response)
        s.registerHandler('document.getInfo',function() state.calls=state.calls+1;error('failure') end)
        request(1);s.poll({});s.poll({});assert_eq(state.calls,1);assert_eq(response().error.code,-32603)
        request(2);s.poll({});assert_eq(state.calls,2)
    end)
end)
test('poll: literal special characters and spaces in IPC override never reach a shell',function()
    fixture(function(s,_,_,_,request,response)
        assert_true(s.getInfo().ipcDir:find('IPC test & literal',1,true));request(1);s.poll({});assert_true(response().result)
    end)
end)
test('poll: oversized malformed file does not prevent next valid mailbox request',function()
    fixture(function(s,files,_,dir,request,response)
        files[dir..'request.json']=string.rep('x',1024*1024+1);s.poll({});assert_true(s.getInfo().lastError)
        request(2);s.poll({});assert_eq(response().id,2)
    end)
end)
