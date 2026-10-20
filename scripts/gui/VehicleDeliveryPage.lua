-- VehicleDeliveryPage.lua
-- Seiten-Controller fuer die eigene Menue-Seite (nach YieldTracker-Vorbild).
-- Erbt von TabbedMenuFrameElement (Basisklasse fuer InGameMenu-Seiten).

VehicleDeliveryPage = {}
VehicleDeliveryPage._mt = Class(VehicleDeliveryPage, TabbedMenuFrameElement)


function VehicleDeliveryPage.new(i18n, messageCenter)
    local self = VehicleDeliveryPage:superClass().new(nil, VehicleDeliveryPage._mt)
    self.name = "VehicleDeliveryPage"
    self.hasCustomMenuButtons = true
    self.i18n = i18n
    self.messageCenter = messageCenter
    self.orders = {}
    return self
end


function VehicleDeliveryPage:setupCustomButtons()
    self.backButtonInfo = {
        inputAction = InputAction.MENU_BACK
    }
    self.cancelButtonInfo = {
        inputAction = InputAction.MENU_CANCEL,
        text = g_i18n:getText("vd_cancelButton"),
        callback = function() self:onClickCancelOrder() end
    }
    self.menuButtons = { self.backButtonInfo, self.cancelButtonInfo }
    self:setMenuButtonInfo(self.menuButtons)
end


---Storno-Button gedrueckt: selektierten Auftrag ermitteln, pruefen, Dialog zeigen.
function VehicleDeliveryPage:onClickCancelOrder()
    if self.orderList == nil or self.orders == nil then
        return
    end
    local sel = self.orderList.selectedIndex or 1
    local order = self.orders[sel]
    if order == nil or order.orderId == nil then
        g_gui:showInfoDialog({ text = g_i18n:getText("vd_cancelNoOrder") })
        return
    end

    local cancelInfo = VehicleDelivery.getCancelInfo(order)
    if cancelInfo == nil then
        return
    end

    local itemName = tostring(order.itemName or "?")
    local text
    if cancelInfo.stage == "production" then
        -- Volle Anzahlung zurueck.
        text = string.format(g_i18n:getText("vd_cancelFull"),
            itemName, g_i18n:formatMoney(cancelInfo.refund, 0, true, true))
    elseif cancelInfo.stage == "shipped" then
        -- Teil der Anzahlung als Schaden einbehalten.
        text = string.format(g_i18n:getText("vd_cancelDamage"),
            itemName,
            g_i18n:formatMoney(cancelInfo.refund, 0, true, true),
            g_i18n:formatMoney(cancelInfo.damage, 0, true, true))
    else
        -- Kurz vor Lieferung: Anzahlung weg + Strafe (Spieler zahlt drauf).
        text = string.format(g_i18n:getText("vd_cancelPenalty"),
            itemName,
            g_i18n:formatMoney(cancelInfo.paid, 0, true, true),
            g_i18n:formatMoney(cancelInfo.penalty, 0, true, true))
    end
    text = text:gsub("\\n", "\n")
    text = text .. "\n\n" .. g_i18n:getText("vd_cancelNoCustoms")

    YesNoDialog.show(
        function(yes)
            if yes then
                -- Die Liste zeigt nur die eigene Farm. Eine stabile Auftrags-ID
                -- bleibt auch bei MP-Updates oder Lieferung eines anderen
                -- Auftrags korrekt, anders als der gefilterte Listenindex.
                VehicleDelivery.requestCancelOrder(order.orderId)
                self:refreshOrders()
            end
        end,
        nil, text, nil, nil, nil, nil, nil, nil, nil, true
    )
end


function VehicleDeliveryPage:onGuiSetupFinished()
    VehicleDeliveryPage:superClass().onGuiSetupFinished(self)
    self:setupCustomButtons()

    -- Auftragsliste anbinden.
    self.orderList = self:getDescendantById("orderList")
    if self.orderList ~= nil then
        self.orderList:setDataSource(self)
        self.orderList:setDelegate(self)
    end
    self.emptyText = self:getDescendantById("emptyText")

    if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Menue-Seite eingerichtet (orderList: %s).",
        tostring(self.orderList ~= nil)) end
end


function VehicleDeliveryPage:onFrameOpen()
    VehicleDeliveryPage:superClass().onFrameOpen(self)
    self:refreshOrders()
end


---Holt die offenen Auftraege aus dem Kern und laedt die Liste neu.
function VehicleDeliveryPage:refreshOrders()
    self.orders = {}

    -- Farm des lokalen Spielers ermitteln (fuer MP-Filterung).
    -- Nur eigene Bestellungen anzeigen, nicht die anderer Hoefe.
    local myFarmId = nil
    if g_currentMission ~= nil then
        if g_currentMission.getFarmId ~= nil then
            myFarmId = g_currentMission:getFarmId()
        elseif g_localPlayer ~= nil then
            myFarmId = g_localPlayer.farmId
        end
    end

    if VehicleDelivery ~= nil and VehicleDelivery.pendingDeliveries ~= nil then
        for _, order in ipairs(VehicleDelivery.pendingDeliveries) do
            -- Anzeigen, wenn: keine Farm-Info (Altauftrag/SP) ODER Farm passt.
            if myFarmId == nil or order.ownerFarmId == nil or order.ownerFarmId == myFarmId then
                table.insert(self.orders, order)
            end
        end
    end

    if self.orderList ~= nil then
        self.orderList:reloadData()
    end

    -- Hinweistext anzeigen, wenn keine Auftraege.
    if self.emptyText ~= nil then
        self.emptyText:setVisible(#self.orders == 0)
    end
end


-- ===== SmoothList Delegate/DataSource =====

function VehicleDeliveryPage:getNumberOfItemsInSection(list, sectionIndex)
    if list == self.orderList then
        return #self.orders
    end
    return 0
end


function VehicleDeliveryPage:getCellTypeForItemInSection(list, sectionIndex, index)
    return "default"
end


function VehicleDeliveryPage:populateCellForItemInSection(list, sectionIndex, index, listItem)
    if list ~= self.orderList then
        return
    end
    local order = self.orders[index]
    if order == nil then
        return
    end

    local itemImage = listItem:getAttribute("itemImage")
    local brandText = listItem:getAttribute("brandText")
    local machineText = listItem:getAttribute("machineText")
    local travelText = listItem:getAttribute("travelText")
    local daysText = listItem:getAttribute("daysText")
    local routeText = listItem:getAttribute("routeText")
    local customsText = listItem:getAttribute("customsText")
    local paymentText = listItem:getAttribute("paymentText")

    if itemImage ~= nil then
        if order.imageFilename ~= nil and order.imageFilename ~= "" then
            itemImage:setImageFilename(order.imageFilename)
            itemImage:setVisible(true)
        else
            itemImage:setVisible(false)
        end
    end
    if brandText ~= nil then
        brandText:setText(tostring(order.brandName or "-"))
    end
    if machineText ~= nil then
        machineText:setText(tostring(order.itemName or "?"))
    end
    if travelText ~= nil then
        travelText:setText(VehicleDelivery.getOrderStatus(order.daysLeft, order.totalDays, order.awaitingPayment, order.wasDelayed))
    end
    if daysText ~= nil then
        local d = order.daysLeft or 0
        local suffix = (d == 1) and g_i18n:getText("vd_daySingular") or g_i18n:getText("vd_dayPlural")
        daysText:setText(string.format("%d %s", d, suffix))
    end
    if routeText ~= nil then
        if order.originRegion ~= nil and order.destinationRegion ~= nil then
            -- Region und Tarif werden bei der Bestellung festgeschrieben.
            routeText:setText(VehicleDelivery.getRegionName(order.originRegion)
                .. " -> " .. VehicleDelivery.getRegionName(order.destinationRegion))
        else
            routeText:setText(VehicleDelivery.getTravelDescriptionByBrand(order.brandName))
        end
    end
    if customsText ~= nil then
        customsText:setText(string.format(g_i18n:getText("vd_orderCustoms"),
            string.format("%g", (order.customsRate or 0) * 100),
            g_i18n:formatMoney(order.customsFee or 0, 0, true, true)))
    end
    if paymentText ~= nil then
        paymentText:setText(string.format(g_i18n:getText("vd_orderPayOnDelivery"),
            g_i18n:formatMoney(order.remainingPayment or 0, 0, true, true)))
    end
end
