local function fixture(fn)
    local oldServer,oldPoller,oldTool,oldLM,oldMOHO,oldScript=MohoMCP_Server,MohoMCP_Poller,LM_TransformBone,LM,MOHO,ScriptName
    local polls,draws,updates=0,0,0
    LM={GUI={Alert=function()end}};MOHO={Localize=function(s)return s end}
    LM_TransformBone={DrawMe=function()draws=draws+1 end}
    MohoMCP_Server={isLoaded=true,BASE_DIR='fixture/',server={isRunning=function()return false end,start=function()return true end,poll=function()polls=polls+1 end,getInfo=function()return {ipcDir='fixture/'}end}}
    local base=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])')..'../'
    dofile(base..'MohoMCP_Server.lua');dofile(base..'MohoMCP_Poller.lua')
    local m={UpdateUI=function()updates=updates+1 end}
    local ok,err=pcall(fn,m,function()return polls,draws,updates end)
    MohoMCP_Server,MohoMCP_Poller,LM_TransformBone,LM,MOHO,ScriptName=oldServer,oldPoller,oldTool,oldLM,oldMOHO,oldScript
    if not ok then error(err)end
end
test('Poller handles natural paint without rebuilding text-entry UI',function()fixture(function(m,counts)
    MohoMCP_Server.pollActive=true
    for i=1,100 do MohoMCP_Poller:DrawMe(m,{})end
    local polls,draws,updates=counts();assert_eq(polls,100);assert_eq(updates,0)
end)end)
test('wrapped editing tools poll and preserve original drawing without UpdateUI',function()fixture(function(m,counts)
    MohoMCP_Server:Run(m)
    for i=1,100 do LM_TransformBone:DrawMe(m,{})end
    local polls,draws,updates=counts();assert_eq(polls,101);assert_eq(draws,100);assert_eq(updates,0)
    MohoMCP_Server.pollActive=false;LM_TransformBone:DrawMe(m,{})
    polls,draws,updates=counts();assert_eq(polls,101);assert_eq(draws,101);assert_eq(updates,0)
end)end)
