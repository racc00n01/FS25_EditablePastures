-- Shared logic (loaded on both client and server).
-- Contains: eligibility helpers, safe fence rebuild for re-edit, and startFenceCustomization patch.

EditablePasturesShared = {}
EditablePasturesShared.MOD_NAME = g_currentModName
EditablePasturesShared.BASE_DIRECTORY = g_currentModDirectory

-- Fence rebuild before husbandry fence customization.
EditablePasturesFenceRebuild = {}

function EditablePasturesFenceRebuild.clearFenceNodeCache(spec)
    if spec == nil or spec.fence == nil then
        return
    end
    spec.fence:finalize()
end

function EditablePasturesFenceRebuild.finalizeNewDefaultFenceLikePlacement(spec)
    if spec == nil or spec.fence == nil or spec.previewSegments == nil then
        return
    end
    for _, segment in ipairs(spec.previewSegments) do
        segment:finalize()
    end
    spec.fence:finalize()
end

function EditablePasturesFenceRebuild.removeAllSegments(spec)
    if spec == nil or spec.fence == nil then
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

    -- Delete any preview-only/orphan segments that were never finalized into fence.segments.
    if spec.previewSegments ~= nil then
        for _, segment in ipairs(spec.previewSegments) do
            if segment ~= nil and segment.fence ~= nil then
                segment:delete()
            end
        end
    end

    spec.previewSegments = nil

    -- Defensive: ensure fence segment table / id counter are clean.
    -- Dedicated servers can otherwise end up with duplicate ids if any segment survived removal due to ordering.
    fence.segments = {}
    fence.nextUniqueSegmentId = 1
end

--- Sum segment:getPrice() for unique segments about to be removed; credit owner farm (server only).
--- Only runs when epFenceEditRefundEligible is set (after at least one successful customization), so the
--- first post-placement customize does not refund the initial default fence the player did not buy per segment.
function EditablePasturesFenceRebuild.refundRemovedFenceSegments(placeable)
    if placeable == nil or not placeable.isServer then
        return
    end
    local spec = placeable.spec_husbandryFence
    if spec == nil or not spec.epFenceEditRefundEligible or spec.fence == nil then
        return
    end
    local fence = spec.fence
    local counted = {}
    local total = 0
    local function addSegment(segment)
        if segment == nil or counted[segment] then
            return
        end
        counted[segment] = true
        if segment.getPrice ~= nil then
            local p = segment:getPrice()
            if p ~= nil and p > 0 then
                total = total + p
            end
        end
    end
    for _, segment in ipairs(fence:getSegments()) do
        addSegment(segment)
    end
    if spec.previewSegments ~= nil then
        for _, segment in ipairs(spec.previewSegments) do
            addSegment(segment)
        end
    end
    if total <= 0 then
        return
    end
    local farmId = placeable:getOwnerFarmId()
    if farmId == nil or g_currentMission == nil then
        return
    end
    local refund = math.floor(total + 0.5)
    if g_currentMission.addMoney ~= nil then
        g_currentMission:addMoney(refund, farmId, "other")
    end
end

function EditablePasturesFenceRebuild.resetFenceToDefaultForCustomization(placeable)
    if placeable == nil or placeable.createDefaultFence == nil then
        return false
    end
    local spec = placeable.spec_husbandryFence
    if spec == nil or spec.fence == nil then
        return false
    end

    -- Replace the fence completely. Do not call restoreDefaultFence(): that path is for cancel/finishFenceCustomization.
    EditablePasturesFenceRebuild.clearFenceNodeCache(spec)
    EditablePasturesFenceRebuild.refundRemovedFenceSegments(placeable)
    EditablePasturesFenceRebuild.removeAllSegments(spec)
    placeable:createDefaultFence()
    EditablePasturesFenceRebuild.finalizeNewDefaultFenceLikePlacement(spec)

    return true
end

function EditablePasturesShared.getFenceSpec(placeable)
    if placeable == nil then
        return nil
    end
    return placeable.spec_husbandryFence
end

function EditablePasturesShared.isEligibleForPastureEdit(placeable)
    if placeable == nil or not placeable:getIsSynchronized() then
        return false
    end
    if placeable.getHasCustomizableFence == nil or not placeable:getHasCustomizableFence() then
        return false
    end
    return true
end

function EditablePasturesShared.patchPlaceableHusbandryFenceStartCustomization()
    if EditablePasturesShared._startFenceCustomizationPatched then
        return
    end
    if PlaceableHusbandryFence == nil or PlaceableHusbandryFence.startFenceCustomization == nil then
        return
    end
    EditablePasturesShared._startFenceCustomizationPatched = true

    local original = PlaceableHusbandryFence.startFenceCustomization
    PlaceableHusbandryFence.startFenceCustomization = function(self, user, noEventSend)
        local spec = self.spec_husbandryFence
        if spec == nil or spec.fence == nil then
            return original(self, user, noEventSend)
        end

        -- Prevent nested/duplicate runs (client can see a replay via broadcast).
        if spec.epInsideStartFenceCustomization then
            return
        end
        if spec.userIsCustomizing and noEventSend then
            return
        end

        spec.epInsideStartFenceCustomization = true
        EditablePasturesFenceRebuild.resetFenceToDefaultForCustomization(self)
        original(self, user, noEventSend)
        spec.epInsideStartFenceCustomization = false
    end
end

function EditablePasturesShared.patchPlaceableHusbandryFenceTryFinalizeFence()
    if EditablePasturesShared._tryFinalizeFencePatched then
        return
    end
    if PlaceableHusbandryFence == nil or PlaceableHusbandryFence.tryFinalizeFence == nil then
        return
    end
    EditablePasturesShared._tryFinalizeFencePatched = true

    local original = PlaceableHusbandryFence.tryFinalizeFence
    PlaceableHusbandryFence.tryFinalizeFence = function(self, ...)
        local success = original(self, ...)
        if not success then
            return false
        end

        -- Capacity validation: prevent shrinking below current animal count.
        if self.getNumOfAnimals ~= nil and self.getMaxNumOfAnimals ~= nil then
            local num = self:getNumOfAnimals()
            local max = self:getMaxNumOfAnimals()
            if num ~= nil and max ~= nil and num > max then
                return false
            end
        end

        return true
    end
end

function EditablePasturesShared.patchPlaceableHusbandryFenceFinishCustomization()
    if EditablePasturesShared._finishFenceCustomizationPatched then
        return
    end
    if PlaceableHusbandryFence == nil or PlaceableHusbandryFence.finishFenceCustomization == nil then
        return
    end
    EditablePasturesShared._finishFenceCustomizationPatched = true
    local original = PlaceableHusbandryFence.finishFenceCustomization
    PlaceableHusbandryFence.finishFenceCustomization = function(self, user, success, noEventSend)
        original(self, user, success, noEventSend)
        if success and self.isServer then
            local spec = self.spec_husbandryFence
            if spec ~= nil then
                spec.epFenceEditRefundEligible = true
            end
        end
    end
end

function EditablePasturesShared.installOnce()
    if EditablePasturesShared._installed then
        return
    end
    EditablePasturesShared._installed = true
    EditablePasturesShared.patchPlaceableHusbandryFenceStartCustomization()
    EditablePasturesShared.patchPlaceableHusbandryFenceTryFinalizeFence()
    EditablePasturesShared.patchPlaceableHusbandryFenceFinishCustomization()
end

EditablePasturesShared.installOnce()
