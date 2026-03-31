-- Client -> server: request permission to edit a placeable's customizable pasture fence.

EditablePasturesFenceEditRequestEvent = {}
local EditablePasturesFenceEditRequestEvent_mt = Class(EditablePasturesFenceEditRequestEvent, Event)
InitEventClass(EditablePasturesFenceEditRequestEvent, "EditablePasturesFenceEditRequestEvent")

function EditablePasturesFenceEditRequestEvent.emptyNew()
    return Event.new(EditablePasturesFenceEditRequestEvent_mt)
end

function EditablePasturesFenceEditRequestEvent.new(placeable)
    local self = EditablePasturesFenceEditRequestEvent.emptyNew()
    self.placeable = placeable
    return self
end

function EditablePasturesFenceEditRequestEvent:readStream(streamId, connection)
    if not connection:getIsServer() then
        self.placeable = NetworkUtil.readNodeObject(streamId)
        self:run(connection)
    end
end

function EditablePasturesFenceEditRequestEvent:writeStream(streamId, connection)
    if connection:getIsServer() then
        NetworkUtil.writeNodeObject(streamId, self.placeable)
    end
end

function EditablePasturesFenceEditRequestEvent:run(connection)
    if g_server == nil then
        return
    end
    if g_editablePasturesManager ~= nil then
        g_editablePasturesManager:onFenceEditRequestReceived(self.placeable, connection)
    end
end

function EditablePasturesFenceEditRequestEvent.send(placeable)
    if g_client ~= nil and g_client:getServerConnection() ~= nil then
        g_client:getServerConnection():sendEvent(EditablePasturesFenceEditRequestEvent.new(placeable))
    end
end

