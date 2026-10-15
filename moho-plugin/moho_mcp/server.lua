-- IPC v2: constant-size mailbox, exclusive bridge owner, correlated responses.
-- No directory enumeration or shell processes, including during startup.
local server = {}
local protocol, validator, json
local running, polling = false, false
local ipcDir, serverId = "", ""
local handlers = {}
local cached = nil
local lastError = nil
local MAX_BYTES = 1024 * 1024
local SEP = package.config:sub(1, 1)

function server.init(deps)
    protocol, validator, json = deps.protocol, deps.validator, deps.json
end
function server.registerHandler(method, handler) handlers[method] = handler end
function server.getHandler(method) return handlers[method] end
function server.isRunning() return running end

local function readFile(name)
    local f, err = io.open(ipcDir .. name, "rb")
    if not f then return nil, err end
    local data = f:read(MAX_BYTES + 1)
    f:close()
    if data and #data > MAX_BYTES then return nil, "IPC file exceeds 1 MiB" end
    return data
end

local function decode(data)
    if not data then return nil end
    local ok, value = pcall(json.decode, data)
    if ok and type(value) == "table" then return value end
end

local function writeFile(name, content)
    local destination = ipcDir .. name
    local temp = destination .. ".tmp"
    local f, err = io.open(temp, "wb")
    if not f then return false, err end
    local wrote, writeErr = f:write(content)
    local closed, closeErr = f:close()
    if not wrote or not closed then
        os.remove(temp)
        return false, writeErr or closeErr
    end
    -- Lua/Windows rename cannot replace an existing file. Readers tolerate the
    -- small missing-file interval; a partially written final file is never used.
    os.remove(destination)
    local ok, renameErr = os.rename(temp, destination)
    if not ok then return false, renameErr end
    return true
end

local function resolveDirectory()
    local override = os.getenv("MOHO_MCP_IPC_DIR")
    local root
    if override and override ~= "" then root = override
    elseif SEP == "\\" then
        root = (os.getenv("TEMP") or os.getenv("TMP") or "") .. SEP .. "moho-mcp"
    else
        root = (os.getenv("TMPDIR") or "/tmp") .. SEP .. "moho-mcp"
    end
    if SEP == "\\" then
        if not root:match("^%a:[/\\]") and not root:match("^[/\\][/\\]") then
            return nil, "IPC directory must be absolute; set MOHO_MCP_IPC_DIR in both processes"
        end
    elseif root:sub(1, 1) ~= "/" then
        return nil, "IPC directory must be absolute"
    end
    return root:gsub("[/\\]+$", "") .. SEP
end

function server.start()
    if running then return true end
    local dir, err = resolveDirectory()
    if not dir then return false, err end
    ipcDir = dir
    -- os.tmpname supplies an OS-generated unique name; no shell construction.
    local unique = os.tmpname()
    os.remove(unique)
    serverId = unique:gsub("[^%w]", "") .. "-" .. tostring(os.time()) .. "-" .. tostring({}):gsub("[^%w]", "")
    local ok, writeErr = writeFile("status.json", json.encode({
        running = true, ipcVersion = 2, serverId = serverId, ipcDir = ipcDir,
        version = "0.1.0", startedAt = os.time()
    }))
    if not ok then
        return false, "Cannot write IPC status at " .. ipcDir .. ": " .. tostring(writeErr)
            .. ". Pre-create this directory and set the same MOHO_MCP_IPC_DIR for Moho and Node."
    end
    cached, lastError = nil, nil
    running = true
    return true
end

function server.stop()
    running = false
    local status = decode(readFile("status.json"))
    if status and status.serverId == serverId then os.remove(ipcDir .. "status.json") end
    -- Never delete client-owned requests/locks, including those from crashes.
    cached = nil
end

local function reply(request, result, code, message)
    local value = {jsonrpc = "2.0", ipcVersion = 2, serverId = serverId,
        session = request and request.session or json.null,
        id = request and request.id or json.null}
    if code then value.error = {code = code, message = message}
    else value.result = result == nil and json.null or result end
    return json.encode(value)
end

local function process(raw, moho)
    local request, err = protocol.parseRequest(raw)
    if not request then return reply(nil, nil, -32700, err) end
    local owner = decode(readFile("bridge-owner.json"))
    if request.ipcVersion ~= 2 or request.serverId ~= serverId
        or type(request.session) ~= "string" or not owner or owner.session ~= request.session then
        return reply(request, nil, -32600, "IPC session/ownership/server mismatch")
    end
    local idType = type(request.id)
    if (idType ~= "string" and idType ~= "number")
        or (idType == "string" and (#request.id == 0 or #request.id > 128))
        or (idType == "number" and (request.id ~= request.id or math.abs(request.id) > 9007199254740991)) then
        return reply(nil, nil, -32600, "Invalid request ID")
    end
    if type(request.expiresAt) ~= "number" or request.expiresAt ~= request.expiresAt
        or request.expiresAt == math.huge or request.expiresAt <= os.time() * 1000 then
        return reply(request, nil, -32600, "Request expired or missing deadline")
    end
    if request.method == "ipc.ping" then return reply(request, {alive = true}) end
    if not validator.isAllowed(request.method) then return reply(request, nil, -32601, "Method not found") end
    local params = request.params or {}
    if type(params) ~= "table" then return reply(request, nil, -32602, "Params must be an object") end
    local valid, validationError = validator.validateParams(request.method, params)
    if not valid then return reply(request, nil, -32602, validationError) end
    local handler = handlers[request.method]
    if not handler then return reply(request, nil, -32601, "No handler registered") end
    local ok, result, handlerError = pcall(handler, moho, params)
    if not ok then return reply(request, nil, -32603, tostring(result)) end
    if result == nil and handlerError then return reply(request, nil, -32603, tostring(handlerError)) end
    return reply(request, result)
end

function server.poll(moho)
    if not running or polling then return end
    polling = true
    local ok, err = pcall(function()
        local status = decode(readFile("status.json"))
        if not status or status.serverId ~= serverId then
            running = false
            error("IPC server ownership changed or status missing; restart explicitly")
        end
        local raw, readErr = readFile("request.json")
        if not raw then
            if readErr == "IPC file exceeds 1 MiB" then error(readErr) end
            return
        end
        if not cached or cached.raw ~= raw then
            -- Set a fallback BEFORE executing: even serialization failure must
            -- not cause a mutation to run twice in this server instance.
            cached = {raw = raw, response = reply(decode(raw), nil, -32603, "Handler/serialization failed; outcome unknown"), delivered = false}
            cached.response = process(raw, moho)
        end
        if cached.delivered then return end
        -- Client may have timed out or disconnected during a slow handler.
        -- Do not publish a stale completion over a newer request.
        if readFile("request.json") ~= raw then return end
        local written, writeErr = writeFile("response.json", cached.response)
        if not written then error("Response write failed (retained for retry, handler will not repeat): " .. tostring(writeErr)) end
        cached.delivered = true
        -- Node removes its own request after consuming the response. Lua must
        -- not delete it after publishing: Node could already post the next one.
        lastError = nil
    end)
    polling = false
    if not ok then
        local message = tostring(err)
        if message ~= lastError then print("[MohoMCP] " .. message) end
        lastError = message
    end
end

function server.getInfo()
    return {running = running, ipcDir = ipcDir, ipcVersion = 2, serverId = serverId, lastError = lastError}
end
return server
