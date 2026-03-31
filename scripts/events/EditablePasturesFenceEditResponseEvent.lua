-- Server -> client: response to an edit request (approved/denied + optional reason).

EditablePasturesFenceEditResponseEvent = {}
local EditablePasturesFenceEditResponseEvent_mt = Class(EditablePasturesFenceEditResponseEvent, Event)
InitEventClass(EditablePasturesFenceEditResponseEvent, "EditablePasturesFenceEditResponseEvent")

function EditablePasturesFenceEditResponseEvent.emptyNew()
    return Event.new(EditablePasturesFenceEditResponseEvent_mt)
end

function EditablePasturesFenceEditResponseEvent.new(placeable, approved, reasonKey)
    local self = EditablePasturesFenceEditResponseEvent.emptyNew()
    self.placeable = placeable
    self.approved = approved or false
    self.reasonKey = reasonKey -- l10n key (optional)
    return self
end

function EditablePasturesFenceEditResponseEvent:readStream(streamId, connection)
    if connection:getIsServer() then
        self.placeable = NetworkUtil.readNodeObject(streamId)
        self.approved = streamReadBool(streamId)
        local hasReason = streamReadBool(streamId)
        if hasReason then
            self.reasonKey = streamReadString(streamId)
        end
        self:run(connection)
    end
end

function EditablePasturesFenceEditResponseEvent:writeStream(streamId, connection)
    if not connection:getIsServer() then
        NetworkUtil.writeNodeObject(streamId, self.placeable)
        streamWriteBool(streamId, self.approved or false)
        streamWriteBool(streamId, self.reasonKey ~= nil)
        if self.reasonKey ~= nil then
            streamWriteString(streamId, self.reasonKey)
        end
    end
end

function EditablePasturesFenceEditResponseEvent:run(connection)
    if g_client == nil then
        return
    end
    if g_editablePasturesClient ~= nil then
        g_editablePasturesClient:onFenceEditResponse(self.placeable, self.approved, self.reasonKey)
    end
end

function EditablePasturesFenceEditResponseEvent.send(connection, placeable, approved, reasonKey)
    if connection ~= nil then
        connection:sendEvent(EditablePasturesFenceEditResponseEvent.new(placeable, approved, reasonKey))
    end
end

