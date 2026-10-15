local document = require('moho_mcp.tools.document')
local function layer(id, children)
    return {id=id, Name=function() return 'Layer '..id end,
        LayerType=function() return 1 end, IsVisible=function() return true end,
        IsLocked=function() return false end, IsGroupType=function() return children ~= nil end,
        CountLayers=function() return #children end, Layer=function(_,i) return children[i+1] end}
end
local function moho(layers)
    return {document={CountLayers=function() return #layers end,
        Layer=function(_,i) return layers[i+1] end, LayerAbsoluteID=function(_,l) return l.id end,
        TotalLayerCount=function() error('Must not use unverified accessor') end},
        LayerAsGroup=function(_,l) return l end}
end
test('metadata counts a single vector layer without TotalLayerCount',function()
    local value=document.getInfo(moho({layer(0)}),{})
    assert_eq(value.totalLayers,1)
    assert_eq(value.topLevelLayers,1)
end)
test('metadata counts nested hierarchy consistently',function()
    local value=document.getInfo(moho({layer(0,{layer(1),layer(2,{layer(3)})}),layer(4)}),{})
    assert_eq(value.totalLayers,5)
    assert_eq(value.topLevelLayers,2)
end)
test('metadata counts empty document',function()
    assert_eq(document.getInfo(moho({}),{}).totalLayers,0)
end)
test('metadata reports hierarchy failure instead of plausible zero',function()
    local m=moho({});m.document.CountLayers=function() error('unavailable') end
    local value,err=document.getInfo(m,{})
    assert_eq(value,nil)
    assert_true(type(err)=='string')
end)
