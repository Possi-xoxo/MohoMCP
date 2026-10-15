local animation = require('moho_mcp.tools.animation')
for _,visible in ipairs({true,false}) do
    test('getFrameState preserves visibility '..tostring(visible),function()
        local layer={IsVisible=function() return visible end}
        local doc={LayerByAbsoluteID=function() return layer end,StartFrame=function() return 0 end,EndFrame=function() return 24 end}
        local result=animation.getFrameState({document=doc},{layerId=0,frame=0})
        assert_eq(result.visible,visible)
    end)
end
test('getFrameState retains fallback when visibility accessor fails',function()
    local doc={LayerByAbsoluteID=function() return {} end}
    assert_true(animation.getFrameState({document=doc},{layerId=0,frame=0}).visible)
end)
