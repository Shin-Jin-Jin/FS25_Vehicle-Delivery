-- VehicleDeliveryGUI.lua
-- Haengt die eigene Menue-Seite ins InGameMenu ein (nach YieldTracker-Vorbild).

VehicleDeliveryGUI = {
    dir = g_currentModDirectory,
    modName = g_currentModName
}


local function findIndex(tbl, value)
    for i, v in ipairs(tbl) do
        if v == value then return i end
    end
    return nil
end


local function moveElement(tbl, element, position)
    for i, v in ipairs(tbl) do
        if v == element then
            table.remove(tbl, i)
            table.insert(tbl, position, element)
            break
        end
    end
end


---Richtet die GUI-Seite ein und haengt sie ins Menue.
function VehicleDeliveryGUI:setup()
    local inGameMenu = g_gui.screenControllers[InGameMenu]
    if inGameMenu == nil then
        Logging.warning("VehicleDelivery: InGameMenu-Instanz nicht gefunden -- GUI-Seite nicht eingehaengt.")
        return
    end

    -- Eigene Profile laden.
    g_gui:loadProfiles(self.dir .. "gui/guiProfiles.xml")

    -- Seite erzeugen und laden.
    if VehicleDeliveryPage == nil then
        Logging.warning("VehicleDelivery: VehicleDeliveryPage-Klasse nicht geladen -- GUI-Seite nicht erstellt.")
        return
    end
    local page = VehicleDeliveryPage.new(g_i18n, g_messageCenter)
    g_gui:loadGui(self.dir .. "gui/vehicleDeliveryPage.xml", "VehicleDeliveryPage", page, true)

    -- Ins Menue einhaengen. Icon vorerst vom YieldTracker-Muster: eigenes DDS spaeter.
    self.fixInGameMenu(page, "VehicleDeliveryPage", {0, 0, 1024, 1024}, 2, nil)

    if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: GUI-Seite ins InGameMenu eingehaengt.") end
end


---Haengt die Seite als neuen Reiter ins InGameMenu (nach YieldTracker fixInGameMenu).
function VehicleDeliveryGUI.fixInGameMenu(frame, pageName, uvs, position, predicateFunc)
    local inGameMenu = g_gui.screenControllers[InGameMenu]

    inGameMenu.controlIDs[pageName] = nil

    local targetPos = findIndex(inGameMenu.pagingElement.elements, inGameMenu.pageStatistics) or position

    inGameMenu[pageName] = frame
    inGameMenu.pagingElement:addElement(frame)
    inGameMenu:exposeControlsAsFields(pageName)

    moveElement(inGameMenu.pagingElement.elements, frame, targetPos)

    for i, page in ipairs(inGameMenu.pagingElement.pages) do
        if page.element == frame then
            table.remove(inGameMenu.pagingElement.pages, i)
            table.insert(inGameMenu.pagingElement.pages, targetPos, page)
            break
        end
    end

    inGameMenu.pagingElement:updateAbsolutePosition()
    inGameMenu.pagingElement:updatePageMapping()

    inGameMenu:registerPage(frame, position, predicateFunc)

    -- Tab-Icon: vorerst ein vorhandenes Spiel-Icon als Platzhalter.
    local iconPath = Utils.getFilename("gui/vehicleDeliveryIcon.dds", VehicleDeliveryGUI.dir)
    inGameMenu:addPageTab(frame, iconPath, GuiUtils.getUVs(uvs))

    moveElement(inGameMenu.pageFrames, frame, targetPos)

    inGameMenu:rebuildTabList()
end
