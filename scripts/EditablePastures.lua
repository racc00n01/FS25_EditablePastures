EditablePastures = {}
EditablePastures.MOD_NAME = g_currentModName
EditablePastures.BASE_DIRECTORY = g_currentModDirectory
source(EditablePastures.BASE_DIRECTORY .. "scripts/events/EditablePasturesFenceCustomizeDeniedEvent.lua")
EditablePastures.initialized = false
EditablePastures.missionActive = false
EditablePastures.actionEventId = nil
EditablePastures.placeableInfoDialogPatched = false
EditablePastures.startFenceCustomizationPatched = false
EditablePastures.husbandryFenceCustomizeStartEventPatched = false
EditablePastures.DEBUG_MP = false

function EditablePastures.load()
    if EditablePastures.initialized then
        return
    end
    EditablePastures.initialized = true
    g_messageCenter:subscribe(MessageType.CURRENT_MISSION_LOADED, EditablePastures.onMissionLoaded, EditablePastures)
    g_messageCenter:subscribe(MessageType.MISSION_DELETED, EditablePastures.onMissionDeleted, EditablePastures)
    if g_currentMission ~= nil then
        EditablePastures:onMissionLoaded()
    end
end

function EditablePastures:onMissionLoaded()
    if EditablePastures.missionActive then
        return
    end
    EditablePastures.missionActive = true
    EditablePastures.patchPlaceableInfoDialogOnce()
    EditablePastures.patchPlaceableHusbandryFenceStartCustomization()
    EditablePastures.patchHusbandryFenceCustomizeStartEvent()
end

function EditablePastures:onMissionDeleted()
    EditablePastures.missionActive = false
end

function EditablePastures.getFenceSpec(placeable)
    if placeable == nil then
        return nil
    end
    return placeable.spec_husbandryFence
end

function EditablePastures.prepareFenceForReEdit(placeable)
    if placeable == nil or placeable.restoreDefaultFence == nil or placeable.createDefaultFence == nil then
        return
    end
    local spec = placeable.spec_husbandryFence
    if spec == nil or spec.fence == nil then
        return
    end

    placeable:restoreDefaultFence()

    local sx, sy, sz, ex, ey, ez = placeable:getCustomizeableSectionStartAndEndPositions()
    if sx ~= nil and ex ~= nil then
        return
    end

    local fence = spec.fence
    local toRemove = {}
    for _, segment in ipairs(fence:getSegments()) do
        table.insert(toRemove, segment)
    end
    for i = #toRemove, 1, -1 do
        local segment = toRemove[i]
        fence:removeSegment(segment)
        segment:delete()
    end

    placeable:createDefaultFence()

    if placeable.isServer and spec.previewSegments ~= nil then
        for _, segment in ipairs(spec.previewSegments) do
            segment:finalize()
        end
        spec.fence:finalize()
    end
end

function EditablePastures.patchPlaceableHusbandryFenceStartCustomization()
    if EditablePastures.startFenceCustomizationPatched then
        return
    end
    if PlaceableHusbandryFence == nil or PlaceableHusbandryFence.startFenceCustomization == nil then
        return
    end
    EditablePastures.startFenceCustomizationPatched = true
    local original = PlaceableHusbandryFence.startFenceCustomization
    PlaceableHusbandryFence.startFenceCustomization = function(self, user, noEventSend)
        EditablePastures.prepareFenceForReEdit(self)
        return original(self, user, noEventSend)
    end
end

-- Server-only: farm ownership and eligibility before HusbandryFenceCustomizeStartEvent broadcasts.
function EditablePastures.validateFenceCustomizeStartServer(placeable, connection)
    if placeable == nil or not placeable:getIsSynchronized() then
        return false
    end
    if not EditablePastures.isEligibleForPastureEdit(placeable) then
        return false
    end
    local mission = g_currentMission
    if mission == nil then
        return false
    end
    -- Internal server/broadcast paths may call run(connection) with no connection; keep base behaviour.
    if connection == nil then
        local spec = EditablePastures.getFenceSpec(placeable)
        if spec ~= nil and spec.userIsCustomizing then
            return false
        end
        return true
    end
    local playerFarmId = mission:getFarmId(connection)
    local ownerFarmId = placeable:getOwnerFarmId()
    if playerFarmId == nil or ownerFarmId == nil or playerFarmId ~= ownerFarmId then
        if EditablePastures.DEBUG_MP then
            Logging.devInfo("EditablePastures: rejected fence customize (farmId owner=%s player=%s)",
                tostring(ownerFarmId), tostring(playerFarmId))
        end
        return false
    end
    local spec = EditablePastures.getFenceSpec(placeable)
    if spec ~= nil and spec.userIsCustomizing then
        if EditablePastures.DEBUG_MP then
            Logging.devInfo("EditablePastures: rejected fence customize (already customizing)")
        end
        return false
    end
    return true
end

function EditablePastures.sendFenceCustomizeDeniedToClient(placeable, connection)
    if placeable == nil or connection == nil or g_server == nil then
        return
    end
    connection:sendEvent(EditablePasturesFenceCustomizeDeniedEvent.new(placeable))
end

function EditablePastures.patchHusbandryFenceCustomizeStartEvent()
    if EditablePastures.husbandryFenceCustomizeStartEventPatched then
        return
    end
    if HusbandryFenceCustomizeStartEvent == nil or HusbandryFenceCustomizeStartEvent.run == nil then
        return
    end
    EditablePastures.husbandryFenceCustomizeStartEventPatched = true
    local originalRun = HusbandryFenceCustomizeStartEvent.run
    HusbandryFenceCustomizeStartEvent.run = function(self, connection)
        local mission = g_currentMission
        if mission ~= nil and mission:getIsServer() and self.placeable ~= nil then
            if not EditablePastures.validateFenceCustomizeStartServer(self.placeable, connection) then
                EditablePastures.sendFenceCustomizeDeniedToClient(self.placeable, connection)
                return
            end
        end
        originalRun(self, connection)
    end
end

--- Any husbandry with customizable fence (cows, sheep, pigs, …);
function EditablePastures.isEligibleForPastureEdit(placeable)
    if placeable == nil or not placeable:getIsSynchronized() then
        return false
    end
    if placeable.getHasCustomizableFence == nil or not placeable:getHasCustomizableFence() then
        return false
    end
    return true
end

function EditablePastures.findNearestEligiblePlaceable(maxDistance)
    local mission = g_currentMission
    if mission == nil or g_localPlayer == nil then
        return nil
    end
    local px, py, pz = g_localPlayer:getPosition()
    local best, bestDist
    local placeables = mission.placeableSystem.placeables
    for i = 1, #placeables do
        local placeable = placeables[i]
        if EditablePastures.isEligibleForPastureEdit(placeable) then
            local ox, oy, oz = placeable:getPosition()
            local dist = MathUtil.vector3Length(px - ox, py - oy, pz - oz)
            if dist <= maxDistance and (bestDist == nil or dist < bestDist) then
                best = placeable
                bestDist = dist
            end
        end
    end
    return best
end

function EditablePastures.patchPlaceableInfoDialogOnce()
    if EditablePastures.placeableInfoDialogPatched then
        return
    end
    if PlaceableInfoDialog == nil or PlaceableInfoDialog.setPlaceable == nil then
        return
    end
    EditablePastures.placeableInfoDialogPatched = true
    PlaceableInfoDialog.setPlaceable = Utils.appendedFunction(PlaceableInfoDialog.setPlaceable, function(self, placeable)
        EditablePastures.ensurePlaceableInfoDialogButton(self)
        if self.epEditPastureButton ~= nil then
            local show = EditablePastures.shouldShowEditPastureButton(placeable)
            self.epEditPastureButton:setVisible(show)
            self.epEditPastureButton:setDisabled(not show)
            if self.sellButton ~= nil and self.sellButton.parent ~= nil then
                self.sellButton.parent:invalidateLayout()
            end
        end
    end)
end

function EditablePastures.ensurePlaceableInfoDialogButton(dialog)
    if dialog.epEditPastureButton ~= nil then
        return
    end
    if dialog.sellButton == nil or dialog.sellButton.parent == nil then
        return
    end
    local parent = dialog.sellButton.parent
    local btn = dialog.sellButton:clone(parent, false, false, false)
    btn.id = "epEditPastureButton"
    btn:setText("Edit Pasture")
    btn.target = dialog
    btn.onClickCallback = EditablePastures.onPlaceableInfoDialogEditPastureClick
    btn:setVisible(false)
    if parent.elements ~= nil then
        for i = #parent.elements, 1, -1 do
            if parent.elements[i] == btn then
                table.remove(parent.elements, i)
                break
            end
        end
        table.insert(parent.elements, 1, btn)
    end
    parent:invalidateLayout()
    dialog.epEditPastureButton = btn
end

function EditablePastures.onPlaceableInfoDialogEditPastureClick(dialog, _)
    if dialog == nil or dialog.placeable == nil then
        return
    end
    local placeable = dialog.placeable
    dialog:close()
    EditablePastures.queueFenceCustomizationAfterDialog(placeable)
end

function EditablePastures.shouldShowEditPastureButton(placeable)
    if not EditablePastures.isEligibleForPastureEdit(placeable) then
        return false
    end
    if g_currentMission == nil then
        return false
    end
    if placeable:getOwnerFarmId() ~= g_currentMission:getFarmId() then
        return false
    end
    local spec = EditablePastures.getFenceSpec(placeable)
    if spec ~= nil and spec.userIsCustomizing then
        return false
    end
    return true
end

function EditablePastures.trySendFenceEditRequest(placeable)
    if not EditablePastures.isEligibleForPastureEdit(placeable) then
        return
    end
    local ownerFarmId = placeable:getOwnerFarmId()
    local playerFarmId = g_currentMission:getFarmId()
    if ownerFarmId ~= playerFarmId then
        return
    end
    local spec = EditablePastures.getFenceSpec(placeable)
    if spec ~= nil and spec.userIsCustomizing then
        return
    end
    EditablePastures.beginFenceCustomization(placeable)
end

function EditablePastures.queueFenceCustomizationAfterDialog(placeable)
    if g_asyncTaskManager ~= nil then
        g_asyncTaskManager:addTask(function()
            EditablePastures.beginFenceCustomization(placeable, true)
        end)
    else
        EditablePastures.beginFenceCustomization(placeable, true)
    end
end

function EditablePastures.isConstructionScreenActive()
    return g_gui ~= nil and g_gui.currentGuiName == "ConstructionScreen"
end

function EditablePastures.beginFenceCustomization(placeable, skipConstructionGuiCheck)
    if g_client == nil then
        return
    end
    if g_constructionScreen == nil then
        return
    end
    if not skipConstructionGuiCheck and not EditablePastures.isConstructionScreenActive() then
        InfoDialog.show(g_i18n:getText("ep_openConstructionFirst"), nil, nil, DialogElement.TYPE_WARNING)
        return
    end
    if not EditablePastures.isEligibleForPastureEdit(placeable) then
        return
    end
    local spec = EditablePastures.getFenceSpec(placeable)
    if spec ~= nil and spec.userIsCustomizing then
        return
    end

    EditablePastures.patchPlaceableHusbandryFenceStartCustomization()
    EditablePastures.returnBrush = g_constructionScreen.brush

    placeable:startFenceCustomization(nil)

    local fence = placeable:getFence()
    if fence == nil then
        placeable:finishFenceCustomization(nil, false)
        EditablePastures.restoreConstructionBrush()
        return
    end

    local xmlFilename = fence.xmlFilename
    if xmlFilename ~= nil then
        xmlFilename = string.lower(xmlFilename)
    end
    local storeItem = g_storeManager:getItemByXMLFilename(xmlFilename)
    if storeItem == nil or storeItem.brush == nil or storeItem.brush.type == nil then
        placeable:finishFenceCustomization(nil, false)
        EditablePastures.restoreConstructionBrush()
        return
    end

    local brushClass = g_constructionBrushTypeManager:getClassObjectByTypeName(storeItem.brush.type)
    if brushClass == nil then
        placeable:finishFenceCustomization(nil, false)
        EditablePastures.restoreConstructionBrush()
        return
    end

    local cursor = g_constructionScreen.cursor
    local brush = brushClass.new(nil, cursor)
    brush:setFenceParentObject(placeable)
    local sx, sy, sz, ex, ey, ez = placeable:getCustomizeableSectionStartAndEndPositions()
    brush:setSnapStartAndEndPositions(sx, sy, sz, ex, ey, ez)
    brush:setFinishCallback(function(statusCode)
        EditablePastures.onFinishedCustomFence(statusCode, placeable)
    end)
    brush:setValidateCallback(function(finishedValidationFunc)
        EditablePastures.validateFenceForPlaceable(finishedValidationFunc, placeable)
    end)
    g_constructionScreen:setBrush(brush, true)
end

function EditablePastures.restoreConstructionBrush()
    local brush = EditablePastures.returnBrush
    if brush == nil then
        brush = g_constructionScreen.selectorBrush
    end
    if g_constructionScreen ~= nil and brush ~= nil then
        g_constructionScreen:setBrush(brush, false)
    end
    EditablePastures.returnBrush = nil
end

function EditablePastures.validateFenceForPlaceable(finishedValidationFunc, placeable)
    MessageDialog.show(g_i18n:getText("ui_construction_fenceHusbandryValidating"))
    g_messageCenter:subscribeOneshot(HusbandryFenceValidateEvent, function(success)
        MessageDialog.hide()
        finishedValidationFunc(success)
        if not success then
            InfoDialog.show(g_i18n:getText("ui_construction_fenceHusbandryFailed"))
        end
    end, nil)
    g_client:getServerConnection():sendEvent(HusbandryFenceValidateEvent.new(placeable))
end

-- createHusbandry() (after fence finalize) does not call updateVisualAnimals; cluster visuals stay empty until
-- clusterHusbandry:setClusters runs (same gap onMissionStarted fixes for load).
function EditablePastures.refreshAnimalVisuals(placeable)
    if placeable == nil or placeable.updateVisualAnimals == nil then
        return
    end
    placeable:updateVisualAnimals()
end

function EditablePastures.scheduleRefreshAnimalVisuals(placeable)
    if placeable == nil then
        return
    end
    EditablePastures.refreshAnimalVisuals(placeable)
    if g_asyncTaskManager == nil then
        return
    end
    g_asyncTaskManager:addTask(function()
        EditablePastures.refreshAnimalVisuals(placeable)
        g_asyncTaskManager:addTask(function()
            EditablePastures.refreshAnimalVisuals(placeable)
        end)
    end)
end

function EditablePastures.onFinishedCustomFence(statusCode, placeable)
    local back = EditablePastures.returnBrush
    if back == nil then
        back = g_constructionScreen.selectorBrush
    end
    g_constructionScreen:setBrush(back, false)
    local success = statusCode == ConstructionBrushNewFence.STATUS.SUCCESS
    placeable:finishFenceCustomization(nil, success)
    EditablePastures.onCustomizableFenceFinished(placeable)
    EditablePastures.returnBrush = nil
    EditablePastures.scheduleRefreshAnimalVisuals(placeable)
end

function EditablePastures.onCustomizableFenceFinished(placeable)
    if placeable.getCanCreateMeadow ~= nil and placeable:getCanCreateMeadow() then
        local createMeadowCallback = function(yes)
            g_constructionScreen:setBrush(g_constructionScreen.selectorBrush, false)
            placeable:createMeadow(yes)
            EditablePastures.scheduleRefreshAnimalVisuals(placeable)
        end
        YesNoDialog.show(createMeadowCallback, nil,
            string.namedFormat(g_i18n:getText("ui_construction_createMeadow"), "placeableName", placeable:getName()))
    end
end

EditablePastures.load()
