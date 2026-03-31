EditablePasturesManager = {}
EditablePasturesManager_mt = Class(EditablePasturesManager)
EditablePasturesManager.modName = g_currentModName
EditablePasturesManager.dir = g_currentModDirectory

function EditablePasturesManager.new()
    local self = {}
    setmetatable(self, EditablePasturesManager_mt)
    return self
end

function EditablePasturesManager:load()
    if g_currentMission == nil or g_server == nil then
        return
    end
    self.isServer = true
end

function EditablePasturesManager:validateFenceEditRequest(placeable, connection)
    if placeable == nil or connection == nil then
        return false, "ep_editDenied"
    end
    if not placeable:getIsSynchronized() then
        return false, "ep_editDenied"
    end
    if not EditablePasturesShared.isEligibleForPastureEdit(placeable) then
        return false, "ep_editDenied"
    end

    local playerFarmId = g_currentMission:getFarmId(connection)
    local ownerFarmId = placeable:getOwnerFarmId()
    if playerFarmId == nil or ownerFarmId == nil or playerFarmId ~= ownerFarmId then
        return false, "ep_editDeniedNotOwner"
    end

    local spec = placeable.spec_husbandryFence
    if spec ~= nil and spec.userIsCustomizing then
        return false, "ep_editDeniedBusy"
    end

    return true
end

function EditablePasturesManager:onFenceEditRequestReceived(placeable, connection)
    local ok, reasonKey = self:validateFenceEditRequest(placeable, connection)
    if not ok then
        EditablePasturesFenceEditResponseEvent.send(connection, placeable, false, reasonKey)
        return
    end

    -- Start customization server-side (authoritative), but don't send the base event again from inside
    -- startFenceCustomization; we broadcast it explicitly afterwards.
    local user = g_currentMission.userManager:getUserByConnection(connection)
    placeable:startFenceCustomization(user, true)

    -- Broadcast the base game start event so all clients enter customization state too.
    g_server:broadcastEvent(HusbandryFenceCustomizeStartEvent.new(placeable), nil, nil, placeable)

    -- Tell the requesting client to switch its brush once customization state is active.
    EditablePasturesFenceEditResponseEvent.send(connection, placeable, true, nil)
end
