-- VehicleDeliveryShopInfo.lua
-- Zeigt beim Kauf eines verzoegerten Fahrzeugs einen Bestaetigungsdialog mit
-- Lieferzeit, Herkunft/Ziel, Zoll und Zahlungsaufteilung. Die fruehere Info-Box im Kaufbildschirm
-- wurde entfernt, weil sie sich bei Konfig-Wechsel nicht zuverlaessig
-- aktualisierte. Die Lieferzeit erfaehrt der Spieler im Dialog + in der
-- Auftragsliste.

VehicleDeliveryShopInfo = {}


---Installiert die Hooks auf den Shop-Kaufbildschirm. Einmal aus loadMap aufrufen.
function VehicleDeliveryShopInfo.install()
    if ShopConfigScreen == nil then
        Logging.warning("VehicleDelivery: ShopConfigScreen nicht verfuegbar -- kein Kaufdialog.")
        return
    end
    -- updateButtons: verdrahtet den Kauf-Button-Callback auf unsere onClickBuy
    -- (der Button speichert seine Referenz beim Erstellen, sonst greift der
    -- overwrittenFunction-Hook nicht).
    if ShopConfigScreen.updateButtons ~= nil then
        ShopConfigScreen.updateButtons = Utils.appendedFunction(
            ShopConfigScreen.updateButtons, VehicleDeliveryShopInfo.onUpdateButtons)
    end
    -- Kauf-Button ueberschreiben: bei verzoegerten Fahrzeugen erst einen
    -- Bestaetigungsdialog mit der Lieferzeit zeigen.
    if ShopConfigScreen.onClickBuy ~= nil then
        ShopConfigScreen.onClickBuy = Utils.overwrittenFunction(
            ShopConfigScreen.onClickBuy, VehicleDeliveryShopInfo.onClickBuy)
    end
    if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Kaufdialog-Integration installiert.") end
end


---Verdrahtet bei jedem Button-Update den Kauf-Button auf unsere onClickBuy.
function VehicleDeliveryShopInfo.onUpdateButtons(screen)
    if screen == nil or screen.storeItem == nil then
        return
    end
    if screen.buyButton ~= nil and ShopConfigScreen.onClickBuy ~= nil then
        screen.buyButton.onClickCallback = ShopConfigScreen.onClickBuy
    end
end


-- Cache: kauft dieses Store-Item mehrere Objekte auf einmal (Mengenauswahl)?
VehicleDeliveryShopInfo.multiPurchaseCache = {}


---True, wenn das Store-Item ueber die Mengenauswahl gekauft wird
-- (vehicle.multipleItemPurchase). Dann bleibt der Vanilla-Kaufablauf zustaendig.
function VehicleDeliveryShopInfo.getIsMultipleItemPurchase(storeItem)
    local filename = storeItem ~= nil and storeItem.xmlFilename or nil
    if filename == nil or XMLFile == nil then
        return false
    end
    local cached = VehicleDeliveryShopInfo.multiPurchaseCache[filename]
    if cached ~= nil then
        return cached
    end
    local result = false
    local xmlFile = XMLFile.load("vdMultiPurchaseCheck", filename, nil)
    if xmlFile ~= nil then
        result = xmlFile:hasProperty("vehicle.multipleItemPurchase")
        xmlFile:delete()
    end
    VehicleDeliveryShopInfo.multiPurchaseCache[filename] = result
    return result
end


---Geld des eigenen Hofs (Client-Sicht), nil wenn nicht ermittelbar.
function VehicleDeliveryShopInfo.getOwnFarmMoney()
    local mission = g_currentMission
    if mission == nil or mission.getMoney == nil then
        return nil
    end
    local farmId = mission.getFarmId ~= nil and mission:getFarmId() or nil
    return mission:getMoney(farmId)
end


---Ueberschreibt den Kauf-Button. Zeigt bei verzoegerten Fahrzeugen einen
-- Bestaetigungsdialog mit Lieferzeit und Zahlungsaufteilung. Er ersetzt die
-- Vanilla-Kaufbestaetigung: Die Vanilla-Pruefung verlangt den GESAMTpreis auf
-- dem Konto, faellig ist bei einer Bestellung aber nur "Zahlung jetzt". Deshalb
-- pruefen wir die Deckung selbst und starten den Kauf direkt (onYesNoBuy).
-- Den Kauf faengt unsere Mod serverseitig ab und verzoegert ihn.
function VehicleDeliveryShopInfo.onClickBuy(screen, superFunc)
    local storeItem = screen.storeItem

    -- Sofort-Faelle: kein Dialog, direkt Originalkauf (gebraucht/Konfiguration
    -- eines vorhandenen Fahrzeugs/In-App/Miete/Palette ...).
    if storeItem == nil
        or storeItem.xmlFilename == nil
        or screen.vehicle ~= nil
        or not VehicleDelivery.getIsDelayedPurchase(storeItem, screen.saleItem,
            screen.leaseVehicle, screen.isFreeOfCharge) then
        return superFunc(screen)
    end

    -- Lieferzeit ueber den Aufpreis bestimmen (Sonderausstattung = Aufpreis > 0).
    local basePrice = storeItem.price or 0
    local currentPrice = screen.totalPrice
    if currentPrice == nil and g_currentMission ~= nil and g_currentMission.economyManager ~= nil then
        currentPrice = g_currentMission.economyManager:getBuyPrice(storeItem, screen.configurations, screen.saleItem)
    end
    if currentPrice == nil and StoreItemUtil ~= nil and StoreItemUtil.getDefaultPrice ~= nil then
        currentPrice = StoreItemUtil.getDefaultPrice(storeItem, screen.configurations)
    end
    currentPrice = currentPrice or basePrice
    local isBase = (currentPrice <= basePrice)
    local days = VehicleDelivery.calculateDeliveryDaysWithBase(storeItem, isBase)
    if days == nil or days <= 0 then
        return superFunc(screen)
    end

    -- Das Angebot verwendet denselben Fahrzeugpreis wie der Kaufbildschirm.
    -- Zoll ist immer bei Lieferung faellig, unabhaengig von der Anzahlung.
    local quote = VehicleDelivery.getCustomsQuote(storeItem, currentPrice)
    local function money(value)
        return g_i18n:formatMoney(value or 0, 0, true, true)
    end
    local route = VehicleDelivery.getRegionName(quote.originRegion)
        .. " -> " .. VehicleDelivery.getRegionName(quote.destinationRegion)

    -- Deckung pruefen: faellig ist jetzt nur "Zahlung jetzt" (Anzahlung bzw.
    -- ohne Anzahlung der Fahrzeugpreis). Der Server prueft dasselbe noch einmal.
    local balance = VehicleDeliveryShopInfo.getOwnFarmMoney()
    if balance ~= nil and quote.upfrontPayment > 0 and balance < quote.upfrontPayment then
        InfoDialog.show(string.format(g_i18n:getText("vd_notEnoughMoneyNow"), money(quote.upfrontPayment)))
        return
    end

    local lines = {
        string.format(g_i18n:getText("vd_confirmDelivery"), VehicleDelivery.formatDuration(days)),
        string.format(g_i18n:getText("vd_confirmTravel"), route),
        string.format(g_i18n:getText("vd_confirmVehiclePrice"), money(quote.vehiclePrice))
    }
    if VehicleDelivery.customsEnabled == false then
        lines[#lines + 1] = string.format(g_i18n:getText("vd_confirmCustomsDisabled"), money(quote.customsFee))
    else
        lines[#lines + 1] = string.format(g_i18n:getText("vd_confirmCustoms"),
            string.format("%g", (quote.customsRate or 0) * 100), money(quote.customsFee))
    end
    lines[#lines + 1] = string.format(g_i18n:getText("vd_confirmTotal"), money(quote.totalPrice))
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format(g_i18n:getText("vd_confirmPayNow"), money(quote.upfrontPayment))
    lines[#lines + 1] = string.format(g_i18n:getText("vd_confirmPayOnDelivery"), money(quote.remainingPayment))
    lines[#lines + 1] = ""
    lines[#lines + 1] = g_i18n:getText("vd_confirmPlaceOrder")
    local text = table.concat(lines, "\n"):gsub("\\n", "\n")

    -- Mengenauswahl-Artikel bleiben beim Vanilla-Ablauf (er fragt die Menge ab).
    local useVanillaFlow = screen.onYesNoBuy == nil
        or VehicleDeliveryShopInfo.getIsMultipleItemPurchase(storeItem)

    YesNoDialog.show(
        function(yes)
            if not yes then
                return
            end
            if useVanillaFlow then
                superFunc(screen)
            else
                -- Unser Dialog ist die Kaufbestaetigung: direkt kaufen, ohne die
                -- Vanilla-Pruefung gegen den Gesamtpreis.
                screen:onYesNoBuy(true)
            end
        end,
        nil,
        text,
        nil, nil, nil, nil, nil, nil, nil,
        true
    )
end
