local inspect=require('moho_mcp.attachment_inspection')
local function fixture(id)
    local parent={};local m={document={LayerAbsoluteID=function(_,l) assert(l==parent);return 4 end}}
    local l={LayerParentBone=function()return id end,Parent=function()return parent end,ControllingBoneLayer=function()return parent end,
        ControllingSkeleton=function()return {CountBones=function()return 3 end,Bone=function()return {Name=function()return 'Arm_Left' end}end}end}
    return m,l
end
test('attachment inspection resolves rigid bone and parent',function()
    local m,l=fixture(2);local r=inspect.read(m,l)
    assert_true(r.available);assert_eq(r.boundBoneName,'Arm_Left');assert_eq(r.parentLayerId,4);assert_eq(r.mode,'rigid')
end)
test('no explicit layer binding does not claim no deformation',function()
    local m,l=fixture(-1);assert_eq(inspect.read(m,l).mode,'no-explicit-layer-bone')
end)
test('special binding remains explicit',function()
    local m,l=fixture(-3);assert_eq(inspect.read(m,l).mode,'special-binding-state')
end)
for _,v in ipairs({3,-4,0.5,math.huge,0/0,'1'}) do
    test('invalid binding fails closed '..tostring(v),function()local m,l=fixture(v);assert_false(inspect.read(m,l).available)end)
end
test('missing accessor is unknown not unbound',function()assert_false(inspect.read({},{}).available)end)
test('root parent can be absent',function()
    local m,l=fixture(-1);l.Parent=function()return nil end;l.ControllingBoneLayer=function()return nil end
    local r=inspect.read(m,l);assert_true(r.available);assert_eq(r.parentLayerId,-1)
end)
