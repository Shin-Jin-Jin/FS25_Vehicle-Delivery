-- VehicleDeliverySyncEvent.lua
-- Synchronisiert die komplette Auftragsliste vom Server zu den Clients.
-- Server ist die Wahrheit; Clients bekommen bei Beitritt + bei jeder Aenderung
-- die vollstaendige Liste. Nach CombineXP-Event-Vorbild.

VehicleDeliverySyncEvent = {}
local VehicleDeliverySyncEvent_mt = Class(VehicleDeliverySyncEvent, Event)

InitEventClass(VehicleDeliverySyncEvent, "VehicleDeliverySyncEvent")


function VehicleDeliverySyncEvent.emptyNew()
    return Event.new(VehicleDeliverySyncEvent_mt)
end


---Erzeugt das Event mit der aktuellen Auftragsliste.
function VehicleDeliverySyncEvent.new(orders)
    local self = VehicleDeliverySyncEvent.emptyNew()
    self.orders = orders or {}
    self.playerRegion = VehicleDelivery.playerRegion or VehicleDelivery.DEFAULT_PLAYER_REGION
    self.downpaymentEnabled = VehicleDelivery.downpaymentEnabled == true
    self.delaysEnabled = VehicleDelivery.delaysEnabled == true
    self.customsEnabled = VehicleDelivery.customsEnabled == true
    return self
end


---Schreibt die Auftragsliste in den Netzwerk-Stream.
function VehicleDeliverySyncEvent:writeStream(streamId, connection)
    -- Diese Einstellungen gelten fuer alle Hoefe. Nur der Server legt sie fest.
    streamWriteString(streamId, self.playerRegion or VehicleDelivery.DEFAULT_PLAYER_REGION)
    streamWriteBool(streamId, self.downpaymentEnabled == true)
    streamWriteBool(streamId, self.delaysEnabled == true)
    streamWriteBool(streamId, self.customsEnabled == true)

    local orders = self.orders or {}
    local count = #orders
    if count > 65535 then
        count = 65535
    end
    streamWriteUInt16(streamId, count)

    for i = 1, count do
        local order = orders[i]
        streamWriteInt32(streamId, order.orderId or 0)
        streamWriteString(streamId, order.itemName or "?")
        streamWriteString(streamId, order.brandName or "")
        streamWriteString(streamId, order.imageFilename or "")
        streamWriteInt32(streamId, order.daysLeft or 0)
        streamWriteInt32(streamId, order.totalDays or order.daysLeft or 0)
        streamWriteInt32(streamId, order.remainingPayment or 0)
        streamWriteInt32(streamId, order.price or 0)
        streamWriteBool(streamId, order.awaitingPayment == true)
        streamWriteBool(streamId, order.wasDelayed == true)
        streamWriteInt32(streamId, order.ownerFarmId or 0)
        streamWriteString(streamId, order.originRegion or "")
        streamWriteString(streamId, order.destinationRegion or "")
        streamWriteFloat32(streamId, order.customsRate or 0)
        streamWriteInt32(streamId, order.customsFee or 0)
    end
end


---Liest die Auftragsliste aus dem Stream (laeuft auf dem Client).
function VehicleDeliverySyncEvent:readStream(streamId, connection)
    self.playerRegion = streamReadString(streamId)
    self.downpaymentEnabled = streamReadBool(streamId)
    self.delaysEnabled = streamReadBool(streamId)
    self.customsEnabled = streamReadBool(streamId)
    local count = streamReadUInt16(streamId)
    self.orders = {}
    for i = 1, count do
        local order = {}
        order.orderId = streamReadInt32(streamId)
        order.itemName = streamReadString(streamId)
        local brand = streamReadString(streamId)
        order.brandName = (brand ~= "") and brand or nil
        local img = streamReadString(streamId)
        order.imageFilename = (img ~= "") and img or nil
        order.daysLeft = streamReadInt32(streamId)
        order.totalDays = streamReadInt32(streamId)
        order.remainingPayment = streamReadInt32(streamId)
        order.price = streamReadInt32(streamId)
        order.awaitingPayment = streamReadBool(streamId)
        order.wasDelayed = streamReadBool(streamId)
        local farm = streamReadInt32(streamId)
        order.ownerFarmId = (farm ~= 0) and farm or nil
        local origin = streamReadString(streamId)
        order.originRegion = (origin ~= "") and origin or nil
        local destination = streamReadString(streamId)
        order.destinationRegion = (destination ~= "") and destination or nil
        order.customsRate = streamReadFloat32(streamId)
        order.customsFee = streamReadInt32(streamId)
        self.orders[i] = order
    end
    self:run(connection)
end


---Wird nach dem Lesen ausgefuehrt. Nur ein REINER CLIENT uebernimmt die Liste.
function VehicleDeliverySyncEvent:run(connection)
    -- WICHTIG: Der Server behaelt seine vollstaendige Liste mit allen Spawn-Daten
    -- (storeItem, configurations, spawn-Position). Wuerde er sie durch die
    -- abgespeckte Sync-Liste ersetzen, schluege die Auslieferung fehl.
    if g_server ~= nil or not connection:getIsServer() then
        return
    end
    if VehicleDelivery ~= nil then
        VehicleDelivery.pendingDeliveries = self.orders
        VehicleDelivery.playerRegion = self.playerRegion
        VehicleDelivery.downpaymentEnabled = self.downpaymentEnabled
        VehicleDelivery.delaysEnabled = self.delaysEnabled
        VehicleDelivery.customsEnabled = self.customsEnabled
        if VehicleDeliverySettings ~= nil then
            VehicleDeliverySettings.refreshState()
        end
        if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Auftragsliste vom Server empfangen (%d Auftraege).", #self.orders) end
    end
end


---Server ruft dies auf, um die aktuelle Liste an alle Clients zu senden.
function VehicleDeliverySyncEvent.sendToClients()
    if g_server == nil then
        return
    end
    local orders = (VehicleDelivery ~= nil and VehicleDelivery.pendingDeliveries) or {}
    g_server:broadcastEvent(VehicleDeliverySyncEvent.new(orders), false, nil, nil)
end


-- ============================================================================
-- Request-Event: Client fordert beim Beitritt die aktuelle Liste vom Server an.
-- Ablauf: Client -> RequestEvent -> Server -> SyncEvent -> Client
-- ============================================================================

VehicleDeliverySyncRequestEvent = {}
local VehicleDeliverySyncRequestEvent_mt = Class(VehicleDeliverySyncRequestEvent, Event)

InitEventClass(VehicleDeliverySyncRequestEvent, "VehicleDeliverySyncRequestEvent")


function VehicleDeliverySyncRequestEvent.emptyNew()
    return Event.new(VehicleDeliverySyncRequestEvent_mt)
end


function VehicleDeliverySyncRequestEvent.new()
    return VehicleDeliverySyncRequestEvent.emptyNew()
end


function VehicleDeliverySyncRequestEvent:writeStream(streamId, connection)
    -- keine Daten noetig
end


function VehicleDeliverySyncRequestEvent:readStream(streamId, connection)
    self:run(connection)
end


---Laeuft auf dem Server, wenn ein Client die Liste anfordert.
function VehicleDeliverySyncRequestEvent:run(connection)
    if g_server ~= nil and not connection:getIsServer() then
        local orders = (VehicleDelivery ~= nil and VehicleDelivery.pendingDeliveries) or {}
        connection:sendEvent(VehicleDeliverySyncEvent.new(orders))
        if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Client fordert Auftragsliste an -- sende %d Auftraege.", #orders) end
    end
end


---Client ruft dies beim Beitritt auf, um die Liste vom Server zu holen.
function VehicleDeliverySyncRequestEvent.sendToServer()
    if g_client ~= nil and g_server == nil then
        g_client:getServerConnection():sendEvent(VehicleDeliverySyncRequestEvent.new())
    end
end


-- ==================== Storno-Anfrage (Client -> Server) ===============

VehicleDeliveryCancelRequestEvent = {}
local VehicleDeliveryCancelRequestEvent_mt = Class(VehicleDeliveryCancelRequestEvent, Event)

InitEventClass(VehicleDeliveryCancelRequestEvent, "VehicleDeliveryCancelRequestEvent")


function VehicleDeliveryCancelRequestEvent.emptyNew()
    return Event.new(VehicleDeliveryCancelRequestEvent_mt)
end


function VehicleDeliveryCancelRequestEvent.new(orderId)
    local self = VehicleDeliveryCancelRequestEvent.emptyNew()
    self.orderId = orderId or 0
    return self
end


function VehicleDeliveryCancelRequestEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.orderId)
end


function VehicleDeliveryCancelRequestEvent:readStream(streamId, connection)
    self.orderId = streamReadInt32(streamId)
    self:run(connection)
end


---Laeuft auf dem Server, wenn ein Client ein Storno anfordert.
function VehicleDeliveryCancelRequestEvent:run(connection)
    if g_server == nil or connection:getIsServer() or self.orderId <= 0 then
        return
    end

    local mission = g_currentMission
    if mission == nil or mission.userManager == nil or g_farmManager == nil then
        return
    end
    local userId = mission.userManager:getUserIdByConnection(connection)
    if userId == nil then
        return
    end
    local farm = g_farmManager:getFarmByUserId(userId)
    local farmId = farm ~= nil and farm.farmId or nil
    if farmId == nil or farmId <= 0
        or not mission:getHasPlayerPermission("buyVehicle", connection, farmId) then
        return
    end

    -- Die Hof-ID wird aus der Verbindung ermittelt, niemals vom Client uebernommen.
    -- Die stabile Auftrags-ID verhindert Stornos des falschen Auftrags nach einer
    -- zwischenzeitlichen Aenderung der Liste. Der Core prueft den Eigentuemer.
    if VehicleDelivery ~= nil and VehicleDelivery.cancelOrderOnServer ~= nil then
        VehicleDelivery.cancelOrderOnServer(self.orderId, farmId)
    end
end

