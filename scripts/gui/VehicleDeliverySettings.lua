-- VehicleDeliverySettings.lua
-- Haengt die Region-Auswahl in die normalen Spieleinstellungen ein
-- (nach CombineXP-Muster: bestehendes MultiTextOption-Element klonen).

VehicleDeliverySettings = {}


---Registriert den Hook in die Settings-Seite. Einmal aus loadMap aufrufen.
function VehicleDeliverySettings.install()
    if InGameMenuSettingsFrame == nil then
        Logging.warning("VehicleDelivery: InGameMenuSettingsFrame nicht verfuegbar -- keine Settings-Integration.")
        return
    end
    InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(
        InGameMenuSettingsFrame.onFrameOpen, VehicleDeliverySettings.onSettingsFrameOpen)
    if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Settings-Integration installiert.") end
end


---Wird bei jedem Oeffnen der Settings-Seite aufgerufen (self = InGameMenuSettingsFrame).
function VehicleDeliverySettings.onSettingsFrameOpen(self)
    VehicleDeliverySettings.settingsFrame = self
    -- Nur einmal einfuegen.
    if self.vdRegionOption ~= nil then
        VehicleDeliverySettings.refreshState(self)
        return
    end

    -- Benoetigte Referenzen der Settings-Seite pruefen.
    if self.gameSettingsLayout == nil or self.economicDifficulty == nil then
        return
    end

    local numElements = #self.gameSettingsLayout.elements

    -- Abschnitts-Header "Fahrzeug-Lieferung".
    local headerIndex = math.min(7, numElements)
    if headerIndex >= 1 then
        local title = self.gameSettingsLayout.elements[headerIndex]:clone()
        title:applyProfile("fs25_settingsSectionHeader", true)
        title:setText(g_i18n:getText("vd_pageTitle"))
        title.focusChangeData = {}
        title.focusId = FocusManager.serveAutoFocusId()
        self.gameSettingsLayout:addElement(title)
    end

    -- Region-Auswahl: bestehenden Mehrfachwaehler (economicDifficulty) klonen.
    local settingsCloneIndex = math.min(5, numElements)
    local optionClone = self.economicDifficulty:clone()
    optionClone.target = VehicleDeliverySettings
    optionClone.onClickCallback = VehicleDeliverySettings.onRegionChanged
    optionClone.buttonLRChange = VehicleDeliverySettings.onRegionChanged

    -- Regionen als Auswahltexte setzen (wie CombineXP: texts direkt indizieren).
    for i = #optionClone.texts, 1, -1 do
        optionClone.texts[i] = nil
    end
    for i, code in ipairs(VehicleDelivery.REGION_ORDER) do
        optionClone.texts[i] = VehicleDelivery.getRegionName(code)
    end

    self.vdRegionOption = optionClone
    VehicleDeliverySettings.addOptionToLayout(
        self.gameSettingsLayout,
        self.vdRegionOption,
        "vdRegionOption",
        g_i18n:getText("vd_regionLabel"),
        self.gameSettingsLayout.elements[settingsCloneIndex]
    )

    VehicleDeliverySettings.updateRegionState(self)
    if self.vdRegionOption.updateSelection ~= nil then
        self.vdRegionOption:updateSelection()
    end

    -- Anzahlungs-Schalter (An/Aus): weiteren Mehrfachwaehler klonen.
    local dpClone = self.economicDifficulty:clone()
    dpClone.target = VehicleDeliverySettings
    dpClone.onClickCallback = VehicleDeliverySettings.onDownpaymentChanged
    dpClone.buttonLRChange = VehicleDeliverySettings.onDownpaymentChanged
    -- Nur zwei Texte: Aus / An.
    for i = #dpClone.texts, 1, -1 do
        dpClone.texts[i] = nil
    end
    dpClone.texts[1] = g_i18n:getText("vd_off")
    dpClone.texts[2] = g_i18n:getText("vd_on")

    self.vdDownpaymentOption = dpClone
    VehicleDeliverySettings.addOptionToLayout(
        self.gameSettingsLayout,
        self.vdDownpaymentOption,
        "vdDownpaymentOption",
        g_i18n:getText("vd_downpaymentLabel"),
        self.gameSettingsLayout.elements[settingsCloneIndex]
    )

    VehicleDeliverySettings.updateDownpaymentState(self)
    if self.vdDownpaymentOption.updateSelection ~= nil then
        self.vdDownpaymentOption:updateSelection()
    end

    -- Verzoegerungs-Schalter (An/Aus): weiteren Mehrfachwaehler klonen.
    local dlClone = self.economicDifficulty:clone()
    dlClone.target = VehicleDeliverySettings
    dlClone.onClickCallback = VehicleDeliverySettings.onDelaysChanged
    dlClone.buttonLRChange = VehicleDeliverySettings.onDelaysChanged
    for i = #dlClone.texts, 1, -1 do
        dlClone.texts[i] = nil
    end
    dlClone.texts[1] = g_i18n:getText("vd_off")
    dlClone.texts[2] = g_i18n:getText("vd_on")

    self.vdDelaysOption = dlClone
    VehicleDeliverySettings.addOptionToLayout(
        self.gameSettingsLayout,
        self.vdDelaysOption,
        "vdDelaysOption",
        g_i18n:getText("vd_delaysLabel"),
        self.gameSettingsLayout.elements[settingsCloneIndex]
    )

    VehicleDeliverySettings.updateDelaysState(self)
    if self.vdDelaysOption.updateSelection ~= nil then
        self.vdDelaysOption:updateSelection()
    end

    -- Zoll fuer neue Bestellungen; bereits vereinbarte Gebuehren bleiben erhalten.
    local customsClone = self.economicDifficulty:clone()
    customsClone.target = VehicleDeliverySettings
    customsClone.onClickCallback = VehicleDeliverySettings.onCustomsChanged
    customsClone.buttonLRChange = VehicleDeliverySettings.onCustomsChanged
    for i = #customsClone.texts, 1, -1 do
        customsClone.texts[i] = nil
    end
    customsClone.texts[1] = g_i18n:getText("vd_off")
    customsClone.texts[2] = g_i18n:getText("vd_on")
    self.vdCustomsOption = customsClone
    VehicleDeliverySettings.addOptionToLayout(
        self.gameSettingsLayout,
        self.vdCustomsOption,
        "vdCustomsOption",
        g_i18n:getText("vd_customsLabel"),
        self.gameSettingsLayout.elements[settingsCloneIndex]
    )

    VehicleDeliverySettings.refreshState(self)

    -- Layout neu anordnen -- sonst ueberlappen die Abschnitts-Header (wichtig!).
    self.gameSettingsLayout:invalidateLayout()
end


---Aktualisiert alle Optionen beim Oeffnen und nach einem Server-Sync.
function VehicleDeliverySettings.refreshState(frame)
    local self = frame or VehicleDeliverySettings.settingsFrame
    if self == nil then
        return
    end
    VehicleDeliverySettings.updateRegionState(self)
    VehicleDeliverySettings.updateDownpaymentState(self)
    VehicleDeliverySettings.updateDelaysState(self)
    VehicleDeliverySettings.updateCustomsState(self)

    -- Die globalen Einstellungen werden ausschliesslich am Server geaendert.
    local disabled = g_server == nil
    local options = {self.vdRegionOption, self.vdDownpaymentOption, self.vdDelaysOption, self.vdCustomsOption}
    for _, option in ipairs(options) do
        option:setDisabled(disabled)
        if option.updateSelection ~= nil then
            option:updateSelection()
        end
    end
end


---Sendet geaenderte Server-Einstellungen mit der aktuellen Auftragsliste.
function VehicleDeliverySettings.broadcastState()
    VehicleDeliverySettings.refreshState()
    if VehicleDeliverySyncEvent ~= nil then
        VehicleDeliverySyncEvent.sendToClients()
    end
end


---Setzt den Zoll-Schalter auf den aktuellen Server-Wert.
function VehicleDeliverySettings.updateCustomsState(self)
    if self.vdCustomsOption ~= nil then
        self.vdCustomsOption:setState(VehicleDelivery.customsEnabled and 2 or 1, false)
    end
end


---Callback bei Aenderung des Zoll-Schalters.
function VehicleDeliverySettings:onCustomsChanged(state, element)
    if g_server == nil then
        VehicleDeliverySettings.refreshState()
        return
    end
    VehicleDelivery.customsEnabled = (state == 2)
    VehicleDeliverySettings.broadcastState()
    if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Zollgebuehren fuer neue Bestellungen %s.",
        VehicleDelivery.customsEnabled and "aktiviert" or "deaktiviert") end
end


---Setzt den Verzoegerungs-Schalter auf den aktuellen Wert.
function VehicleDeliverySettings.updateDelaysState(self)
    if self.vdDelaysOption == nil then
        return
    end
    local state = VehicleDelivery.delaysEnabled and 2 or 1
    self.vdDelaysOption:setState(state, false)
end


---Callback bei Aenderung des Verzoegerungs-Schalters.
function VehicleDeliverySettings:onDelaysChanged(state, element)
    if g_server == nil then
        VehicleDeliverySettings.refreshState()
        return
    end
    VehicleDelivery.delaysEnabled = (state == 2)
    VehicleDeliverySettings.broadcastState()
    if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Lieferverzoegerungen per Einstellung %s.",
        VehicleDelivery.delaysEnabled and "aktiviert" or "deaktiviert") end
end


---Setzt den Anzahlungs-Schalter auf den aktuellen Wert.
function VehicleDeliverySettings.updateDownpaymentState(self)
    if self.vdDownpaymentOption == nil then
        return
    end
    local state = VehicleDelivery.downpaymentEnabled and 2 or 1
    self.vdDownpaymentOption:setState(state, false)
end


---Callback bei Aenderung des Anzahlungs-Schalters.
function VehicleDeliverySettings:onDownpaymentChanged(state, element)
    if g_server == nil then
        VehicleDeliverySettings.refreshState()
        return
    end
    VehicleDelivery.downpaymentEnabled = (state == 2)
    VehicleDeliverySettings.broadcastState()
    if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Anzahlung per Einstellung %s.",
        VehicleDelivery.downpaymentEnabled and "aktiviert" or "deaktiviert") end
end


---Setzt das Auswahlfeld auf die aktuell gespeicherte Region.
function VehicleDeliverySettings.updateRegionState(self)
    if self.vdRegionOption == nil then
        return
    end
    local current = VehicleDelivery.playerRegion or VehicleDelivery.DEFAULT_PLAYER_REGION
    for i, code in ipairs(VehicleDelivery.REGION_ORDER) do
        if code == current then
            self.vdRegionOption:setState(i, false)
            break
        end
    end
end


---Callback bei Aenderung der Region.
function VehicleDeliverySettings:onRegionChanged(state, element)
    if g_server == nil then
        VehicleDeliverySettings.refreshState()
        return
    end
    local code = VehicleDelivery.REGION_ORDER[state]
    if code ~= nil then
        VehicleDelivery.playerRegion = code
        VehicleDeliverySettings.broadcastState()
        if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Region per Einstellungen gesetzt auf %s.", code) end
    end
end


---Fuegt ein geklontes Option-Element mit Titel in das Settings-Layout ein
-- (nach CombineXP-Muster).
function VehicleDeliverySettings.addOptionToLayout(gameSettingsLayout, cloneElement, id, titleText, settingsClone)
    cloneElement.id = id

    local optionTitle = settingsClone.elements[2]:clone()
    optionTitle.id = id .. "Title"
    optionTitle:applyProfile("fs25_settingsMultiTextOptionTitle", true)
    optionTitle:setText(titleText)

    local optionContainer = settingsClone:clone()
    optionContainer.id = id .. "Container"
    optionContainer:applyProfile("fs25_multiTextOptionContainer", true)
    for key in pairs(optionContainer.elements) do
        optionContainer.elements[key] = nil
    end

    optionContainer:addElement(optionTitle)
    optionContainer:addElement(cloneElement)
    gameSettingsLayout:addElement(optionContainer)
end
