-- Server -> client: revert local fence customization when the server rejects HusbandryFenceCustomizeStartEvent.
EditablePasturesFenceCustomizeDeniedEvent = {}
local EditablePasturesFenceCustomizeDeniedEvent_mt = Class(EditablePasturesFenceCustomizeDeniedEvent, Event)
InitEventClass(EditablePasturesFenceCustomizeDeniedEvent, "EditablePasturesFenceCustomizeDeniedEvent")

function EditablePasturesFenceCustomizeDeniedEvent.emptyNew()
    local self = Event.new(EditablePasturesFenceCustomizeDeniedEvent_mt)
    return self
end

function EditablePasturesFenceCustomizeDeniedEvent.new(placeable)
    local self = EditablePasturesFenceCustomizeDeniedEvent.emptyNew()
    self.placeable = placeable
    return self
end

function EditablePasturesFenceCustomizeDeniedEvent:readStream(streamId, connection)
    self.placeable = NetworkUtil.readNodeObject(streamId)
    self:run(connection)
end

function EditablePasturesFenceCustomizeDeniedEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.placeable)
end

function EditablePasturesFenceCustomizeDeniedEvent:run(connection)
    if not connection:getIsServer() then
        return
    end
    if self.placeable == nil or not self.placeable:getIsSynchronized() then
        return
    end
    local spec = self.placeable.spec_husbandryFence
    if spec == nil or not spec.userIsCustomizing then
        return
    end
    self.placeable:finishFenceCustomization(nil, false, true)
end
