EditablePasturesClient = {}
EditablePasturesClient_mt = Class(EditablePasturesClient)

function EditablePasturesClient.new()
    local self = {}
    setmetatable(self, EditablePasturesClient_mt)
    self._pendingBrushPlaceable = nil
    return self
end

function EditablePasturesClient:load()
    if g_client == nil then
        return
    end

    self:patchPlaceableInfoDialogOnce()
end

function EditablePasturesClient:isConstructionScreenActive()
    return g_gui ~= nil and g_gui.currentGuiName == "ConstructionScreen"
end

function EditablePasturesClient:shouldShowEditPastureButton(placeable)
    if not EditablePasturesShared.isEligibleForPastureEdit(placeable) then
        return false
    end
    if g_currentMission == nil then
        return false
    end
    if placeable:getOwnerFarmId() ~= g_currentMission:getFarmId() then
        return false
    end
    local spec = placeable.spec_husbandryFence
    if spec ~= nil and spec.userIsCustomizing then
        return false
    end
    return true
end

function EditablePasturesClient:ensurePlaceableInfoDialogButton(dialog)
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
    btn.onClickCallback = EditablePasturesClient.onPlaceableInfoDialogEditPastureClick
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

function EditablePasturesClient:patchPlaceableInfoDialogOnce()
    if self._placeableInfoDialogPatched then
        return
    end
    if PlaceableInfoDialog == nil or PlaceableInfoDialog.setPlaceable == nil then
        return
    end
    self._placeableInfoDialogPatched = true

    PlaceableInfoDialog.setPlaceable = Utils.appendedFunction(PlaceableInfoDialog.setPlaceable, function(dialog, placeable)
        self:ensurePlaceableInfoDialogButton(dialog)
        if dialog.epEditPastureButton ~= nil then
            local show = self:shouldShowEditPastureButton(placeable)
            dialog.epEditPastureButton:setVisible(show)
            dialog.epEditPastureButton:setDisabled(not show)
            if dialog.sellButton ~= nil and dialog.sellButton.parent ~= nil then
                dialog.sellButton.parent:invalidateLayout()
            end
        end
    end)
end

function EditablePasturesClient.onPlaceableInfoDialogEditPastureClick(dialog, _)
    if dialog == nil or dialog.placeable == nil then
        return
    end
    local placeable = dialog.placeable
    dialog:close()

    if not (g_gui ~= nil and g_gui.currentGuiName == "ConstructionScreen") then
        InfoDialog.show(g_i18n:getText("ep_openConstructionFirst"), nil, nil, DialogElement.TYPE_WARNING)
        return
    end

    EditablePasturesFenceEditRequestEvent.send(placeable)
end

function EditablePasturesClient:onFenceEditResponse(placeable, approved, reasonKey)
    if not approved then
        if reasonKey ~= nil and g_i18n ~= nil and g_i18n:hasText(reasonKey) then
            InfoDialog.show(g_i18n:getText(reasonKey), nil, nil, DialogElement.TYPE_WARNING)
        end
        return
    end

    -- Wait until the base start event has put the placeable into customization state and
    -- snap positions exist, then swap the brush. Ordering is not guaranteed in MP.
    self._pendingBrushPlaceable = placeable
    self:queueBrushSetupRetry(0)
end

function EditablePasturesClient:queueBrushSetupRetry(attempt)
    if g_asyncTaskManager == nil then
        -- Fallback: do it immediately.
        self:tryStartFenceBrush(attempt or 0)
        return
    end
    g_asyncTaskManager:addTask(function()
        self:tryStartFenceBrush(attempt or 0)
    end)
end

function EditablePasturesClient:tryStartFenceBrush(attempt)
    local placeable = self._pendingBrushPlaceable
    if placeable == nil or not placeable:getIsSynchronized() then
        self._pendingBrushPlaceable = nil
        return
    end
    local spec = placeable.spec_husbandryFence
    if spec == nil or not spec.userIsCustomizing then
        if attempt < 30 then
            return self:queueBrushSetupRetry(attempt + 1)
        end
        self._pendingBrushPlaceable = nil
        return
    end

    local sx, sy, sz, ex, ey, ez = placeable:getCustomizeableSectionStartAndEndPositions()
    if sx == nil or ex == nil then
        if attempt < 30 then
            return self:queueBrushSetupRetry(attempt + 1)
        end
        self._pendingBrushPlaceable = nil
        return
    end

    self._pendingBrushPlaceable = nil
    self:beginFenceCustomizationClient(placeable, sx, sy, sz, ex, ey, ez)
end

function EditablePasturesClient:beginFenceCustomizationClient(placeable, sx, sy, sz, ex, ey, ez)
    if g_constructionScreen == nil then
        return
    end
    local fence = placeable:getFence()
    if fence == nil then
        return
    end
    local xmlFilename = fence.xmlFilename
    if xmlFilename ~= nil then
        xmlFilename = string.lower(xmlFilename)
    end
    local storeItem = g_storeManager:getItemByXMLFilename(xmlFilename)
    if storeItem == nil or storeItem.brush == nil or storeItem.brush.type == nil then
        return
    end
    local brushClass = g_constructionBrushTypeManager:getClassObjectByTypeName(storeItem.brush.type)
    if brushClass == nil then
        return
    end

    local cursor = g_constructionScreen.cursor
    local brush = brushClass.new(nil, cursor)
    brush:setFenceParentObject(placeable)
    brush:setSnapStartAndEndPositions(sx, sy, sz, ex, ey, ez)
    brush:setFinishCallback(function(statusCode)
        local back = g_constructionScreen.selectorBrush
        g_constructionScreen:setBrush(back, false)
        local success = statusCode == ConstructionBrushNewFence.STATUS.SUCCESS
        placeable:finishFenceCustomization(nil, success)
        if success then
            self:onCustomizableFenceFinished(placeable)
        end
        self:scheduleRefreshAnimalVisuals(placeable)
    end)
    brush:setValidateCallback(function(finishedValidationFunc)
        MessageDialog.show(g_i18n:getText("ui_construction_fenceHusbandryValidating"))
        g_messageCenter:subscribeOneshot(HusbandryFenceValidateEvent, function(success)
            MessageDialog.hide()
            finishedValidationFunc(success)
            if not success then
                -- If fence geometry is valid but the pasture was shrunk below current animal count,
                -- PlaceableHusbandryFence.tryFinalizeFence was patched to return false. Show a clearer warning.
                if placeable ~= nil and placeable.getNumOfAnimals ~= nil and placeable.getMaxNumOfAnimals ~= nil then
                    local num = placeable:getNumOfAnimals()
                    local max = placeable:getMaxNumOfAnimals()
                    if num ~= nil and max ~= nil and num > max then
                        InfoDialog.show(g_i18n:getText("ep_pastureTooSmall"), nil, nil, DialogElement.TYPE_WARNING)
                        return
                    end
                end
                InfoDialog.show(g_i18n:getText("ui_construction_fenceHusbandryFailed"))
            end
        end, nil)
        g_client:getServerConnection():sendEvent(HusbandryFenceValidateEvent.new(placeable))
    end)
    g_constructionScreen:setBrush(brush, true)
end

function EditablePasturesClient:scheduleRefreshAnimalVisuals(placeable)
    if g_asyncTaskManager == nil then
        self:tryRefreshAnimalVisuals(placeable, 0)
        return
    end
    g_asyncTaskManager:addTask(function()
        self:tryRefreshAnimalVisuals(placeable, 0)
    end)
end

function EditablePasturesClient:tryRefreshAnimalVisuals(placeable, attempt)
    if placeable == nil or placeable.updateVisualAnimals == nil then
        return
    end
    local spec = placeable.spec_husbandryAnimals
    if spec == nil or spec.clusterHusbandry == nil or spec.clusterHusbandry.getHusbandryId == nil then
        return
    end

    local husbandryId = spec.clusterHusbandry:getHusbandryId()
    if husbandryId == nil then
        if attempt < 60 then
            return self:queueRefreshRetry(placeable, attempt + 1)
        end
        return
    end

    if isHusbandryReady ~= nil and not isHusbandryReady(husbandryId) then
        if attempt < 60 then
            return self:queueRefreshRetry(placeable, attempt + 1)
        end
        return
    end

    placeable:updateVisualAnimals()
end

function EditablePasturesClient:queueRefreshRetry(placeable, attempt)
    if g_asyncTaskManager == nil then
        return
    end
    g_asyncTaskManager:addTask(function()
        self:tryRefreshAnimalVisuals(placeable, attempt)
    end)
end

function EditablePasturesClient:onCustomizableFenceFinished(placeable)
    if placeable == nil or placeable.getCanCreateMeadow == nil then
        return
    end
    if not placeable:getCanCreateMeadow() then
        return
    end

    local createMeadowCallback = function(yes)
        if g_constructionScreen ~= nil then
            g_constructionScreen:setBrush(g_constructionScreen.selectorBrush, false)
        end
        placeable:createMeadow(yes)
        self:scheduleRefreshAnimalVisuals(placeable)
    end

    YesNoDialog.show(createMeadowCallback, nil,
        string.namedFormat(g_i18n:getText("ui_construction_createMeadow"), "placeableName", placeable:getName()))
end

