-- Entry point (referenced by modDesc.xml)
-- Loads shared logic on both client/server, and the correct side-specific module.

local modDir = g_currentModDirectory

source(modDir .. "scripts/EditablePasturesShared.lua")
source(modDir .. "scripts/events/EditablePasturesFenceEditRequestEvent.lua")
source(modDir .. "scripts/events/EditablePasturesFenceEditResponseEvent.lua")

if g_server ~= nil then
    source(modDir .. "scripts/EditablePasturesManager.lua")
    g_editablePasturesManager = EditablePasturesManager.new()
    g_editablePasturesManager:load()
end

if g_client ~= nil then
    source(modDir .. "scripts/EditablePasturesClient.lua")
    g_editablePasturesClient = EditablePasturesClient.new()
    g_editablePasturesClient:load()
end
