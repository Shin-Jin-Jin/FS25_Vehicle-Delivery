--
-- VehicleDelivery
--
-- Neu gekaufte Fahrzeuge werden nicht sofort ausgeliefert, sondern nach einer
-- Wartezeit (drei Achsen): gebraucht=sofort; Basis +2 / Sonder +2; Region nach
-- Sprung-Distanz im Regionen-Netz (2 Tage je Sprung).
--
-- Autor: Shin_Jin_Jin
-- Hinweis: bewusst KEIN pcall / xpcall (Vorgabe GIANTS).
--
-- Neue Fahrzeuge werden als Auftrag gespeichert und spaeter ausgeliefert.
-- Importzoll ist ein konfigurierbarer Spielwert und bei Lieferung faellig.
--

-- Modverzeichnis merken (g_currentModDirectory ist nur hier auf oberster Ebene gueltig).
VehicleDelivery = {}
VehicleDelivery.dir = g_currentModDirectory
VehicleDelivery.modName = g_currentModName

-- GUI-Dateien laden. Auf oberster Ebene -- hier sind Basisklassen wie
-- TabbedMenuFrameElement bereits verfuegbar (anders als bei extraSourceFiles).
-- Sync-Event: Server UND Client brauchen die Event-Klasse (Netzwerk-Basis ist
-- auch auf dem dedizierten Server da, anders als die GUI).
source(VehicleDelivery.dir .. "scripts/VehicleDeliverySyncEvent.lua")

-- GUI-Dateien nur auf dem Client laden. Ein dedizierter Server hat keine
-- GUI-Basisklassen (TabbedMenuFrameElement fehlt) -- dann wuerde schon die
-- Klassendeklaration beim Laden crashen und die Mod waere server-inkompatibel.
if g_dedicatedServer == nil and TabbedMenuFrameElement ~= nil then
    source(VehicleDelivery.dir .. "scripts/gui/VehicleDeliveryPage.lua")
    source(VehicleDelivery.dir .. "scripts/gui/VehicleDeliveryGUI.lua")
    source(VehicleDelivery.dir .. "scripts/gui/VehicleDeliverySettings.lua")
    source(VehicleDelivery.dir .. "scripts/gui/VehicleDeliveryShopInfo.lua")
end

-- ========================= Einstellbare Werte =========================

-- Debug-Modus: nur fuer die Entwicklung. Wenn false, werden keine Debug-
-- Konsolenbefehle registriert und keine ausfuehrlichen Log-Meldungen
-- geschrieben (nur einmalige Statusmeldungen, Warnungen und Fehler).
VehicleDelivery.DEBUG = false

VehicleDelivery.BASE_DAYS    = 2
VehicleDelivery.CONFIG_DAYS  = 2
VehicleDelivery.DAYS_PER_HOP = 2

-- Abstand (m) zwischen mehreren am selben Tag gelieferten Fahrzeugen.
VehicleDelivery.DELIVERY_GAP = 1.5

VehicleDelivery.DEFAULT_REGION        = "EU"
VehicleDelivery.DEFAULT_PLAYER_REGION = "EU"

-- Kaufkategorien OHNE Lieferzeit (sofort verfuegbar). Keys GROSSGESCHRIEBEN
-- (Abfrage per string.upper). Erweiterbar: einfach weitere Kategorie ergaenzen.
VehicleDelivery.INSTANT_CATEGORIES = {
    PALLETS           = true,  -- Saatgut, Duenger, Kalk, Reifen ...
    BIGBAGS           = true,  -- BigBag-Saatgut/Duenger
    BIGBAGPALLETS     = true,  -- BigBags auf Paletten
    SHIPPINGCONTAINERS = true, -- Versand-Container
    BALES             = true,  -- Ballen
    IBC               = true,  -- IBC-Tanks (Fluessigduenger etc.)
}

VehicleDelivery.VALID_REGIONS = {
    EU = true, NA = true, SA = true, AS = true, AF = true, OC = true
}

-- Reihenfolge + Anzeigenamen fuer den Auswahldialog.
VehicleDelivery.REGION_ORDER = { "EU", "NA", "SA", "AS", "AF", "OC" }
VehicleDelivery.REGION_NAMES = {
    EU = "Europa",
    NA = "Nordamerika",
    SA = "Suedamerika",
    AS = "Asien",
    AF = "Afrika",
    OC = "Ozeanien",
}


---Liefert den lokalisierten Regionsnamen (l10n), Fallback auf REGION_NAMES.
function VehicleDelivery.getRegionName(code)
    if code == nil then
        return ""
    end
    if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n:hasText("vd_region" .. code) then
        return g_i18n:getText("vd_region" .. code)
    end
    return VehicleDelivery.REGION_NAMES[code] or code
end

-- Vorgabe-Region je Map (per mapId aus g_currentMission.missionInfo.mapId).
-- Nur Basisspiel + DLC -- unbekannte (Mod-)Maps fallen auf Default zurueck.
-- Erweiterbar: einfach weitere Zeilen "mapId = REGION" ergaenzen.
VehicleDelivery.MAP_REGION = {
    -- Basisspiel
    MapUS = "NA",  -- Riverbend Springs (USA)
    MapEU = "EU",  -- Zielonka (Polen/Europa)
    MapAS = "AS",  -- Hutan Pantai (Suedostasien)
    -- DLC (mapId per pdlc_-Prefix, exakt wie im Spiel)
    ["pdlc_highlandsFishingPack.HighlandsFishingMap"] = "EU",  -- Kinlaig (Schottland)
    ["pdlc_beansAndAlpacasPack.beansAndAlpacasMap"] = "SA",    -- Catuaí (Suedamerika)
    -- Kostenlose GIANTS-Maps vom ModHub (mapId = ZIP-Name . Map-ID)
    ["FS25_horschAgrovation.HorschAgrovation"] = "EU",         -- HORSCH AgroVation (Knezmost, Tschechien)
    ["FS25_silverrunForest.MapForest"] = "NA",                 -- Silverrun Forest (Pazifischer Nordwesten)
}

-- Regionen-Netz: Kanten mit Gewicht (Sprünge), ungerichtet.
VehicleDelivery.REGION_EDGES = {
    { "EU", "AF", 1 },
    { "EU", "AS", 1 },
    { "AS", "OC", 1 },
    { "NA", "SA", 1 },
    { "EU", "NA", 2 },  -- Atlantik-Bruecke
}

VehicleDelivery.regionGraph = nil
VehicleDelivery.manufacturerRegion = {}
VehicleDelivery.playerRegion = nil

-- Anzahlungsmodell: 20% beim Kauf, Rest bei Lieferung. Per Einstellung an/aus.
VehicleDelivery.DOWNPAYMENT_RATE = 0.20
VehicleDelivery.downpaymentEnabled = true

-- Zollmatrix: Zeile = Herkunft, Spalte = Ziel. Spielwerte, keine echten Tarife.
-- Die Werte in customs.xml werden in Prozent angegeben (hier als Bruchteil).
VehicleDelivery.customsEnabled = true
VehicleDelivery.CUSTOMS_RATES = {
    EU = {EU=0, NA=0.05, SA=0.08, AS=0.06, AF=0.08, OC=0.05},
    NA = {EU=0.06, NA=0, SA=0.07, AS=0.08, AF=0.09, OC=0.05},
    SA = {EU=0.07, NA=0.06, SA=0, AS=0.09, AF=0.08, OC=0.07},
    AS = {EU=0.08, NA=0.07, SA=0.09, AS=0, AF=0.07, OC=0.06},
    AF = {EU=0.06, NA=0.08, SA=0.07, AS=0.07, AF=0, OC=0.08},
    OC = {EU=0.07, NA=0.05, SA=0.08, AS=0.06, AF=0.09, OC=0},
}

-- Lieferverzoegerungen: kleine Chance pro Auftrag auf +1-2 Tage, einmalig.
-- Per Einstellung an/aus.
VehicleDelivery.DELAY_CHANCE = 0.15
VehicleDelivery.DELAY_MIN = 1
VehicleDelivery.DELAY_MAX = 2
VehicleDelivery.delaysEnabled = true

-- Zeitskala: Alle Lieferzeiten (BASE_DAYS, CONFIG_DAYS, DAYS_PER_HOP, Verzoegerungen)
-- sind Kalendertage bezogen auf einen Monat mit 28 Tagen (Hoechstwert der
-- Einstellung, dort gilt 1 Liefertag = 1 Spieltag). Sie werden auf die
-- Spieleinstellung "Tage pro Monat" umgerechnet und stuendlich heruntergezaehlt.
-- Beispiel: 12 Tage bei 1 Tag/Monat = 12/28 Monat = ca. 10,3 Spielstunden.
VehicleDelivery.DAYS_PER_MONTH_REFERENCE = 28
-- Toleranz fuer Rundungsreste beim Herunterzaehlen (Kalendertage).
VehicleDelivery.TIME_EPSILON = 0.0001

-- Offene Lieferauftraege. Eintrag (Baustein 1): { itemName=string, daysLeft=int }
VehicleDelivery.pendingDeliveries = {}
VehicleDelivery.nextOrderId = 1


-- ==================== Zeitskala (Tage pro Monat) ======================

---Spieleinstellung "Tage pro Monat" (mindestens 1).
-- Das Spiel fuehrt zwei Werte: plannedDaysPerPeriod ist das, was im
-- Einstellungsmenue steht; environment.daysPerPeriod ist die Laenge des
-- laufenden Monats und uebernimmt eine Aenderung erst zum naechsten Monat.
-- Die Mod rechnet mit dem eingestellten Wert, damit die angezeigte Lieferzeit
-- zur Einstellung passt und sich beim Monatswechsel nicht verschiebt.
function VehicleDelivery.getDaysPerMonth()
    local mission = g_currentMission
    local daysPerMonth = nil
    if mission ~= nil and mission.missionInfo ~= nil then
        daysPerMonth = mission.missionInfo.plannedDaysPerPeriod
    end
    if (daysPerMonth == nil or daysPerMonth <= 0) and mission ~= nil and mission.environment ~= nil then
        daysPerMonth = mission.environment.plannedDaysPerPeriod
    end
    if (daysPerMonth == nil or daysPerMonth <= 0) and mission ~= nil and mission.environment ~= nil then
        daysPerMonth = mission.environment.daysPerPeriod
    end
    if daysPerMonth == nil or daysPerMonth <= 0 then
        daysPerMonth = 1
    end
    return daysPerMonth
end


---Rechnet Kalendertage (Lieferzeit-Einheit der Mod) in Spielstunden um.
function VehicleDelivery.getGameHoursForDays(days)
    return (days or 0) * 24 * VehicleDelivery.getDaysPerMonth() / VehicleDelivery.DAYS_PER_MONTH_REFERENCE
end


---Rechnet Spielstunden in Kalendertage um (Gegenstueck zu getGameHoursForDays).
function VehicleDelivery.getDaysForGameHours(gameHours)
    return (gameHours or 0) * VehicleDelivery.DAYS_PER_MONTH_REFERENCE / (24 * VehicleDelivery.getDaysPerMonth())
end


---Lesbare Dauer in Spielzeit, z.B. "3 Tage", "9 Std." oder "1 Tag, 5 Std.".
function VehicleDelivery.formatDuration(days)
    local hours = math.ceil(VehicleDelivery.getGameHoursForDays(math.max(0, days or 0)) - 0.001)
    hours = math.max(0, hours)
    local fullDays = math.floor(hours / 24)
    local restHours = hours - fullDays * 24
    if fullDays == 0 then
        return string.format(g_i18n:getText("vd_durationHours"), restHours)
    elseif restHours == 0 then
        return string.format(g_i18n:getText("vd_durationDays"), fullDays)
    end
    return string.format(g_i18n:getText("vd_durationDaysHours"), fullDays, restHours)
end


-- ==================== Kauf-Einordnung =================================

---Sofort-Kategorie (Paletten, BigBags ...)? Diese Artikel haben keine Lieferzeit.
function VehicleDelivery.getIsInstantStoreItem(storeItem)
    if storeItem == nil or storeItem.categoryName == nil then
        return false
    end
    return VehicleDelivery.INSTANT_CATEGORIES[string.upper(storeItem.categoryName)] == true
end


---Wird dieser Kauf als Bestellung mit Lieferzeit abgewickelt?
-- Gebraucht, Miete, kostenlos, In-App und Sofort-Kategorien: nein.
function VehicleDelivery.getIsDelayedPurchase(storeItem, saleItem, leaseVehicle, isFreeOfCharge)
    if storeItem == nil or storeItem.isInAppPurchase then
        return false
    end
    if isFreeOfCharge == true or saleItem ~= nil or leaseVehicle == true then
        return false
    end
    return not VehicleDelivery.getIsInstantStoreItem(storeItem)
end


---Angehaengt an BuyVehicleData.updatePrice: Bei einer Bestellung mit Anzahlung
-- verlangt das Spiel beim Kauf nur die Anzahlung. Damit prueft der Server die
-- Deckung gegen "Zahlung jetzt" statt gegen den Gesamtpreis und bucht auch nur
-- diesen Betrag ab. Der volle Preis bleibt in vdFullPrice erhalten.
function VehicleDelivery.onUpdateBuyPrice(buyData)
    if buyData == nil then
        return
    end
    buyData.vdFullPrice = nil
    if not VehicleDelivery.downpaymentEnabled then
        return
    end
    if not VehicleDelivery.getIsDelayedPurchase(buyData.storeItem, buyData.saleItem,
        buyData.leaseVehicle, buyData.isFreeOfCharge) then
        return
    end
    local fullPrice = buyData.price or 0
    if fullPrice <= 0 then
        return
    end
    local quote = VehicleDelivery.getCustomsQuote(buyData.storeItem, fullPrice)
    buyData.vdFullPrice = fullPrice
    buyData.price = quote.upfrontPayment
end


-- ============================ Init ====================================

function VehicleDelivery.init()
    VehicleDelivery.buildRegionGraph()
    VehicleDelivery.loadManufacturers()
    VehicleDelivery.loadCustomsRates()

    if BuyVehicleData ~= nil then
        BuyVehicleData.buy = Utils.overwrittenFunction(BuyVehicleData.buy, VehicleDelivery.onBuy)
        if BuyVehicleData.updatePrice ~= nil then
            BuyVehicleData.updatePrice = Utils.appendedFunction(BuyVehicleData.updatePrice, VehicleDelivery.onUpdateBuyPrice)
        end
    else
        Logging.warning("VehicleDelivery: BuyVehicleData nicht verfuegbar -- Hook nicht installiert.")
    end

    -- Lieferzeiten laufen stuendlich ab, damit sie der Einstellung "Tage pro
    -- Monat" folgen (bei 1 Tag/Monat ist ein Spieltag ein ganzer Monat).
    if g_messageCenter ~= nil and MessageType ~= nil and MessageType.HOUR_CHANGED ~= nil then
        g_messageCenter:subscribe(MessageType.HOUR_CHANGED, VehicleDelivery.onHourChanged, VehicleDelivery)
    else
        Logging.warning("VehicleDelivery: MessageCenter/HOUR_CHANGED nicht verfuegbar.")
    end

    -- Konsolenbefehle nur im Debug-Modus (Entwicklung).
    if VehicleDelivery.DEBUG and addConsoleCommand ~= nil then
        addConsoleCommand("vdTestOrder", "Test-Lieferauftrag: vdTestOrder <tage> [name]", "consoleAddTestOrder", VehicleDelivery)
        addConsoleCommand("vdList", "Offene Lieferauftraege anzeigen", "consoleListOrders", VehicleDelivery)
        addConsoleCommand("vdSetRegion", "Spieler-Region setzen: vdSetRegion <EU/NA/SA/AS/AF/OC>", "consoleSetRegion", VehicleDelivery)
        addConsoleCommand("vdSkipDay", "24 Spielstunden vorspulen (nur Lieferungen)", "consoleSkipDay", VehicleDelivery)
        addConsoleCommand("vdDump", "Struktur einer globalen Klasse ins Log: vdDump <name> [tiefe]", "consoleDump", VehicleDelivery)
        addConsoleCommand("vdDumpVehicle", "Struktur des ersten Fahrzeugs ins Log: vdDumpVehicle [tiefe]", "consoleDumpVehicle", VehicleDelivery)
        addConsoleCommand("vdFind", "Globale Namen mit Muster finden: vdFind <muster>", "consoleFind", VehicleDelivery)
        addConsoleCommand("vdGrep", "Keys eines Objekts mit Muster (inkl. Metatable): vdGrep <pfad> <muster>", "consoleGrep", VehicleDelivery)
        addConsoleCommand("vdFields", "Nur Felder (keine Funktionen) eines Objekts: vdFields <pfad>", "consoleFields", VehicleDelivery)
        addConsoleCommand("vdMenu", "Lebende InGameMenu-Instanz + ihre Seiten finden", "consoleMenu", VehicleDelivery)
        addConsoleCommand("vdSettings", "Settings-Frame-Schluesselfelder pruefen", "consoleSettings", VehicleDelivery)
    end

    if FSCareerMissionInfo ~= nil and FSCareerMissionInfo.saveToXMLFile ~= nil then
        FSCareerMissionInfo.saveToXMLFile = Utils.prependedFunction(FSCareerMissionInfo.saveToXMLFile, VehicleDelivery.onSaveGame)
    else
        Logging.warning("VehicleDelivery: FSCareerMissionInfo.saveToXMLFile nicht verfuegbar -- keine Persistenz beim Speichern!")
    end
end


-- ==================== Regionen-Netz ===================================

function VehicleDelivery.buildRegionGraph()
    local g = {}
    for _, edge in ipairs(VehicleDelivery.REGION_EDGES) do
        local a, b, w = edge[1], edge[2], edge[3]
        if g[a] == nil then g[a] = {} end
        if g[b] == nil then g[b] = {} end
        g[a][b] = w
        g[b][a] = w
    end
    VehicleDelivery.regionGraph = g
end


---Kuerzeste Distanz (Sprünge) zwischen zwei Regionen (Dijkstra). Gleich -> 0.
function VehicleDelivery.getRegionDistance(fromRegion, toRegion)
    if fromRegion == nil or toRegion == nil then
        return nil
    end
    if fromRegion == toRegion then
        return 0
    end

    local graph = VehicleDelivery.regionGraph
    if graph == nil or graph[fromRegion] == nil then
        return nil
    end

    local dist = {}
    local visited = {}
    dist[fromRegion] = 0

    while true do
        local current, currentDist = nil, nil
        for node, d in pairs(dist) do
            if not visited[node] and (currentDist == nil or d < currentDist) then
                current = node
                currentDist = d
            end
        end

        if current == nil then
            break
        end
        if current == toRegion then
            return dist[toRegion]
        end

        visited[current] = true

        local neighbors = graph[current]
        if neighbors ~= nil then
            for neighbor, weight in pairs(neighbors) do
                if not visited[neighbor] then
                    local nd = dist[current] + weight
                    if dist[neighbor] == nil or nd < dist[neighbor] then
                        dist[neighbor] = nd
                    end
                end
            end
        end
    end

    return dist[toRegion]
end


---Liefert die Regionen-Kette von fromRegion nach toRegion als Liste, z.B.
-- {"EU", "NA", "SA"}. Nil, wenn kein Weg existiert. Fuer die Reisedarstellung.
function VehicleDelivery.getRegionPath(fromRegion, toRegion)
    if fromRegion == nil or toRegion == nil then
        return nil
    end
    if fromRegion == toRegion then
        return { fromRegion }
    end

    local graph = VehicleDelivery.regionGraph
    if graph == nil or graph[fromRegion] == nil then
        return nil
    end

    local dist = {}
    local prev = {}
    local visited = {}
    dist[fromRegion] = 0

    while true do
        local current, currentDist = nil, nil
        for node, d in pairs(dist) do
            if not visited[node] and (currentDist == nil or d < currentDist) then
                current = node
                currentDist = d
            end
        end

        if current == nil then
            break
        end
        if current == toRegion then
            break
        end

        visited[current] = true

        local neighbors = graph[current]
        if neighbors ~= nil then
            for neighbor, weight in pairs(neighbors) do
                if not visited[neighbor] then
                    local nd = dist[current] + weight
                    if dist[neighbor] == nil or nd < dist[neighbor] then
                        dist[neighbor] = nd
                        prev[neighbor] = current
                    end
                end
            end
        end
    end

    if dist[toRegion] == nil then
        return nil
    end

    -- Pfad rueckwaerts ueber prev rekonstruieren, dann umdrehen.
    local path = {}
    local node = toRegion
    while node ~= nil do
        table.insert(path, 1, node)
        node = prev[node]
    end
    return path
end

---Einzige Eintragsstelle Marke->Region (spaeter oeffentlich fuer Option B).
function VehicleDelivery.registerManufacturer(brandName, region)
    if brandName == nil or brandName == "" then
        Logging.warning("VehicleDelivery: registerManufacturer ohne Markennamen -- ignoriert.")
        return
    end
    brandName = string.upper(brandName)
    if region == nil or VehicleDelivery.VALID_REGIONS[region] ~= true then
        return
    end
    VehicleDelivery.manufacturerRegion[brandName] = region
end


function VehicleDelivery.loadManufacturers()
    local path = VehicleDelivery.dir .. "manufacturers.xml"
    if not fileExists(path) then
        Logging.warning("VehicleDelivery: manufacturers.xml nicht gefunden (%s) -- Default-Region fuer alle.", path)
        return
    end

    local xmlFile = XMLFile.load("vehicleDeliveryManufacturers", path)
    if xmlFile == nil then
        Logging.warning("VehicleDelivery: manufacturers.xml konnte nicht geladen werden.")
        return
    end

    local count = 0
    for _, key in xmlFile:iterator("manufacturers.manufacturer") do
        local name = xmlFile:getString(key .. "#name")
        local region = xmlFile:getString(key .. "#region")
        VehicleDelivery.registerManufacturer(name, region)
        count = count + 1
    end

    xmlFile:delete()
    if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: %d Hersteller-Eintraege aus manufacturers.xml gelesen.", count) end
end


-- ==================== Spieler-Region ==================================

---Liefert die Vorgabe-Region fuer die aktuelle Map (per mapId) oder nil.
function VehicleDelivery.getMapDefaultRegion()
    if g_currentMission == nil or g_currentMission.missionInfo == nil then
        return nil
    end
    local mapId = g_currentMission.missionInfo.mapId
    if mapId == nil then
        return nil
    end
    local region = VehicleDelivery.MAP_REGION[mapId]
    if region ~= nil then
        if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Map '%s' erkannt -> Vorgabe-Region %s.", tostring(mapId), region) end
    else
        if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Map '%s' nicht in Vorgabe-Tabelle -- Default greift.", tostring(mapId)) end
    end
    return region
end


function VehicleDelivery.setDefaultRegionIfUnset()
    if VehicleDelivery.playerRegion ~= nil then
        return
    end

    -- Neuer Save ohne gespeicherte Region: erst Map-Vorgabe versuchen.
    local mapRegion = VehicleDelivery.getMapDefaultRegion()
    if mapRegion ~= nil then
        VehicleDelivery.playerRegion = mapRegion
        if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Spieler-Region aus Map-Vorgabe gesetzt: %s.", mapRegion) end
        return
    end

    -- Sonst Default.
    VehicleDelivery.playerRegion = VehicleDelivery.DEFAULT_PLAYER_REGION
    if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Spieler-Region auf Default (%s) gesetzt (unbekannte Map, kein gespeicherter Wert).",
        VehicleDelivery.DEFAULT_PLAYER_REGION) end
end


-- ==================== Region einer Marke ==============================

---Liefert den Anzeige-Herstellernamen eines storeItems (oder nil).
function VehicleDelivery.getBrandName(storeItem)
    if storeItem == nil then
        return nil
    end
    if storeItem.brandIndex ~= nil and g_brandManager ~= nil then
        local brand = g_brandManager:getBrandByIndex(storeItem.brandIndex)
        if brand ~= nil then
            -- title ist der schoen formatierte Anzeigename, name das interne Kuerzel.
            return brand.title or brand.name
        end
    end
    return nil
end


function VehicleDelivery.getStoreItemRegion(storeItem)
    if storeItem == nil then
        return VehicleDelivery.DEFAULT_REGION
    end

    local brandName = nil
    if storeItem.brandIndex ~= nil and g_brandManager ~= nil then
        local brand = g_brandManager:getBrandByIndex(storeItem.brandIndex)
        if brand ~= nil then
            brandName = brand.name
        end
    end

    if brandName == nil then
        return VehicleDelivery.DEFAULT_REGION
    end

    local region = VehicleDelivery.manufacturerRegion[string.upper(brandName)]
    if region == nil then
        if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Marke '%s' ohne Region -- Default (%s).", brandName, VehicleDelivery.DEFAULT_REGION) end
        return VehicleDelivery.DEFAULT_REGION
    end

    return region
end


-- ==================== Importzoll ======================================

function VehicleDelivery.loadCustomsRates()
    local path = VehicleDelivery.dir .. "customs.xml"
    if not fileExists(path) then
        return
    end
    local xmlFile = XMLFile.load("vehicleDeliveryCustoms", path)
    if xmlFile == nil then
        Logging.warning("VehicleDelivery: customs.xml nicht lesbar -- Standardtarife bleiben aktiv.")
        return
    end
    xmlFile:iterate("customs.tariff", function(_, key)
        local from = xmlFile:getString(key .. "#from")
        local to = xmlFile:getString(key .. "#to")
        local rate = xmlFile:getFloat(key .. "#rate")
        if VehicleDelivery.VALID_REGIONS[from] and VehicleDelivery.VALID_REGIONS[to]
            and rate ~= nil and rate >= 0 and rate <= 100 and from ~= to then
            VehicleDelivery.CUSTOMS_RATES[from][to] = rate / 100
        else
            Logging.warning("VehicleDelivery: Ungueltiger Zolltarif '%s' ignoriert.", key)
        end
    end)
    xmlFile:delete()
end


---Zoll auf den konfigurierten Fahrzeugpreis; immer erst bei Lieferung zahlen.
-- Diese Momentaufnahme wird im Auftrag gespeichert, nie spaeter neu berechnet.
function VehicleDelivery.getCustomsQuote(storeItem, vehiclePrice)
    local price = math.max(0, vehiclePrice or 0)
    local origin = VehicleDelivery.getStoreItemRegion(storeItem)
    local destination = VehicleDelivery.playerRegion or VehicleDelivery.DEFAULT_PLAYER_REGION
    local rate = 0
    if VehicleDelivery.customsEnabled and origin ~= destination then
        local tariffs = VehicleDelivery.CUSTOMS_RATES[origin]
        rate = tariffs ~= nil and tariffs[destination] or 0
    end
    local customsFee = math.floor(price * rate + 0.5)
    local upfrontPayment = price
    if VehicleDelivery.downpaymentEnabled then
        upfrontPayment = math.floor(price * VehicleDelivery.DOWNPAYMENT_RATE)
    end
    return {
        vehiclePrice = price,
        originRegion = origin,
        destinationRegion = destination,
        customsRate = rate,
        customsFee = customsFee,
        totalPrice = price + customsFee,
        upfrontPayment = upfrontPayment,
        remainingPayment = price - upfrontPayment + customsFee,
    }
end


function VehicleDelivery.assignOrderId(order)
    if order.orderId == nil or order.orderId <= 0 then
        order.orderId = VehicleDelivery.nextOrderId
    end
    VehicleDelivery.nextOrderId = math.max(VehicleDelivery.nextOrderId, order.orderId + 1)
    return order.orderId
end


-- ==================== Basis/Sonder ====================================

function VehicleDelivery.getIsBaseConfiguration(storeItem, configurations)
    if storeItem == nil or configurations == nil then
        return true
    end
    if storeItem.configurations == nil then
        return true
    end

    for configName, chosenIndex in pairs(configurations) do
        if storeItem.configurations[configName] ~= nil then
            local defaultIndex = StoreItemUtil.getDefaultConfigId(storeItem, configName)
            if defaultIndex ~= nil and chosenIndex ~= defaultIndex then
                return false
            end
        end
    end

    return true
end


-- ==================== Lieferzeit berechnen ============================

---Wie calculateDeliveryDays, aber isBase wird direkt uebergeben statt aus den
-- Konfig-Indizes ermittelt. Fuer die Shop-Anzeige, die "Sonderkonfig" zuverlaessig
-- am Aufpreis erkennt (die Konfig-Index-Logik ist im Shop unzuverlaessig, weil
-- manche Default-Optionen trotzdem kostenpflichtig sind, z.B. 3-Punkt=YES).
function VehicleDelivery.calculateDeliveryDaysWithBase(storeItem, isBase)
    local days = VehicleDelivery.BASE_DAYS
    if not isBase then
        days = days + VehicleDelivery.CONFIG_DAYS
    end

    local originRegion = VehicleDelivery.getStoreItemRegion(storeItem)
    local playerRegion = VehicleDelivery.playerRegion or VehicleDelivery.DEFAULT_PLAYER_REGION

    local hops = VehicleDelivery.getRegionDistance(playerRegion, originRegion)
    if hops == nil then
        hops = 0
    end

    days = days + hops * VehicleDelivery.DAYS_PER_HOP
    return days
end


function VehicleDelivery.calculateDeliveryDays(storeItem, configurations)
    local isBase = VehicleDelivery.getIsBaseConfiguration(storeItem, configurations)

    local days = VehicleDelivery.BASE_DAYS
    if not isBase then
        days = days + VehicleDelivery.CONFIG_DAYS
    end

    local originRegion = VehicleDelivery.getStoreItemRegion(storeItem)
    local playerRegion = VehicleDelivery.playerRegion or VehicleDelivery.DEFAULT_PLAYER_REGION

    local hops = VehicleDelivery.getRegionDistance(playerRegion, originRegion)
    if hops == nil then
        hops = 0
    end

    local regionDays = hops * VehicleDelivery.DAYS_PER_HOP
    days = days + regionDays

    local info = {
        isBase = isBase,
        originRegion = originRegion,
        playerRegion = playerRegion,
        hops = hops,
        configDays = (isBase and 0 or VehicleDelivery.CONFIG_DAYS),
        regionDays = regionDays,
        totalDays = days,
    }

    return days, info
end


---Baut eine lesbare Reise-Beschreibung fuer ein StoreItem, z.B.
-- "Nordamerika -> Europa" (Regionsnamen lokalisiert). Gibt die Pfad-Liste der
-- Regionscodes und den fertigen Text zurueck. Fuer Kaufbildschirm + Auftragsliste.
function VehicleDelivery.getTravelDescription(storeItem)
    local originRegion = VehicleDelivery.getStoreItemRegion(storeItem)
    local playerRegion = VehicleDelivery.playerRegion or VehicleDelivery.DEFAULT_PLAYER_REGION

    -- Pfad geht vom Herkunftsort zum Spieler.
    local path = VehicleDelivery.getRegionPath(originRegion, playerRegion)
    if path == nil then
        path = { originRegion }
    end

    local names = {}
    for _, code in ipairs(path) do
        names[#names+1] = VehicleDelivery.getRegionName(code)
    end

    local text
    if #names <= 1 then
        text = string.format(g_i18n:getText("vd_travelLocal"), names[1] or "?")
    else
        text = table.concat(names, " -> ")
    end

    return path, text, originRegion, playerRegion
end


---Wie getTravelDescription, aber nur anhand des Markennamens (fuer die
-- Auftragsliste, die nach dem MP-Sync kein storeItem mehr hat). Gibt den
-- fertigen Reisetext zurueck.
function VehicleDelivery.getTravelDescriptionByBrand(brandName)
    local originRegion = VehicleDelivery.DEFAULT_REGION
    if brandName ~= nil and brandName ~= "" then
        local region = VehicleDelivery.manufacturerRegion[string.upper(brandName)]
        if region ~= nil then
            originRegion = region
        end
    end
    local playerRegion = VehicleDelivery.playerRegion or VehicleDelivery.DEFAULT_PLAYER_REGION

    local path = VehicleDelivery.getRegionPath(originRegion, playerRegion)
    if path == nil then
        path = { originRegion }
    end

    local names = {}
    for _, code in ipairs(path) do
        names[#names+1] = VehicleDelivery.getRegionName(code)
    end

    if #names <= 1 then
        return string.format(g_i18n:getText("vd_travelLocal"), names[1] or "?")
    end
    return table.concat(names, " -> ")
end


---Leitet aus dem Lieferfortschritt einen Status ab:
-- "In Produktion" (Anfang) -> "Unterwegs" (Mitte) -> "Kurz vor Lieferung" (Ende).
-- Bei sehr kurzer Lieferzeit (1-2 Tage) direkt "Unterwegs".
function VehicleDelivery.getOrderStatus(daysLeft, totalDays, awaitingPayment, wasDelayed)
    daysLeft = daysLeft or 0
    totalDays = totalDays or daysLeft

    if awaitingPayment then
        return g_i18n:getText("vd_statusAwaitingPayment")
    end
    if daysLeft <= 1 then
        return g_i18n:getText("vd_statusArriving")
    end
    -- Verzoegert: anzeigen solange nicht kurz vor Lieferung.
    if wasDelayed then
        return g_i18n:getText("vd_statusDelayed")
    end
    if totalDays <= 2 then
        return g_i18n:getText("vd_statusShipped")
    end

    -- Anteil der bereits vergangenen Zeit.
    local elapsed = totalDays - daysLeft

    -- Ganz frisch bestellt (noch kein Tag vergangen): Bestellung aufgegeben.
    if elapsed <= 0 then
        return g_i18n:getText("vd_statusPlaced")
    end

    local progress = elapsed / totalDays

    if progress < 0.34 then
        return g_i18n:getText("vd_statusProduction")
    elseif progress < 0.84 then
        return g_i18n:getText("vd_statusShipped")
    else
        return g_i18n:getText("vd_statusArriving")
    end
end


-- Storno-Schadenersatz je nach Fortschritt (Modell mit Anzahlung):
--  In Produktion: volle Anzahlung zurueck, kein Schaden.
--  Unterwegs:     Anteil der Anzahlung als Schaden einbehalten.
--  Kurz vor Lieferung: Anzahlung komplett weg + Zusatzstrafe vom Vollpreis.
VehicleDelivery.CANCEL_DAMAGE_PRODUCTION = 0.00  -- In Produktion: 0% der Anzahlung
VehicleDelivery.CANCEL_DAMAGE_SHIPPED = 0.50     -- Unterwegs: 50% der Anzahlung
VehicleDelivery.CANCEL_PENALTY_ARRIVING = 0.10   -- Kurz vor Lieferung: +10% vom Vollpreis


---Liefert den Storno-Status eines Auftrags: "ok" + Gebuehrenanteil, oder
-- "locked" wenn nicht mehr stornierbar. Nutzt dieselbe Fortschrittslogik
-- wie getOrderStatus.
function VehicleDelivery.getCancelInfo(order)
    if order == nil then
        return nil
    end
    local daysLeft = order.daysLeft or 0
    local totalDays = order.totalDays or daysLeft

    -- Gleiche Schwellen wie getOrderStatus.
    local arriving = false
    local shipped = false
    if daysLeft <= 1 then
        arriving = true
    elseif totalDays <= 2 then
        shipped = true
    else
        local progress = (totalDays - daysLeft) / totalDays
        if progress < 0.34 then
            shipped = false
        elseif progress < 0.84 then
            shipped = true
        else
            arriving = true
        end
    end

    -- Bereits gezahlter Betrag: bei Anzahlung nur die Anzahlung (Preis - Rest),
    -- sonst der volle Preis.
    local price = order.price or 0
    -- Zoll ist bis zur Lieferung unbezahlt und wird beim Storno nicht faellig.
    local vehicleRest = math.max(0, (order.remainingPayment or 0) - (order.customsFee or 0))
    local paid = math.max(0, price - vehicleRest)

    local stage, damage, penalty, refund

    if arriving then
        -- Kurz vor Lieferung: Anzahlung komplett weg + Zusatzstrafe vom Vollpreis.
        stage = "arriving"
        damage = paid  -- gesamte Anzahlung als Schaden
        penalty = math.floor(price * VehicleDelivery.CANCEL_PENALTY_ARRIVING)
        -- Rueckerstattung negativ = der Spieler zahlt drauf.
        refund = -penalty
    elseif shipped then
        -- Unterwegs: Anteil der Anzahlung als Schaden.
        stage = "shipped"
        damage = math.floor(paid * VehicleDelivery.CANCEL_DAMAGE_SHIPPED)
        penalty = 0
        refund = paid - damage
    else
        -- In Produktion: volle Anzahlung zurueck.
        stage = "production"
        damage = math.floor(paid * VehicleDelivery.CANCEL_DAMAGE_PRODUCTION)
        penalty = 0
        refund = paid - damage
    end

    return {
        locked = false,
        stage = stage,
        price = price,
        paid = paid,
        damage = damage,      -- einbehaltener Teil der Anzahlung
        penalty = penalty,    -- zusaetzliche Strafe (nur spaet)
        refund = refund,      -- was der Spieler erhaelt (negativ = zahlt drauf)
    }
end


---Fuehrt das Storno SERVERSEITIG durch: Auftrag entfernen, Geld erstatten,
-- Clients syncen. Stabile ID statt Position in einer gefilterten/veraenderten Liste.
function VehicleDelivery.cancelOrderOnServer(orderId, requestingFarmId)
    if g_server == nil then
        return false
    end
    local list = VehicleDelivery.pendingDeliveries
    local order, index
    for i, candidate in ipairs(list) do
        if candidate.orderId == orderId then
            order, index = candidate, i
            break
        end
    end
    if order == nil or requestingFarmId == nil or order.ownerFarmId ~= requestingFarmId then
        return false
    end

    local cancelInfo = VehicleDelivery.getCancelInfo(order)
    if cancelInfo == nil or cancelInfo.locked then
        return false
    end

    -- Geldbewegung: refund > 0 = Rueckerstattung, refund < 0 = Spieler zahlt
    -- drauf (spaetes Storno: Strafe). refund == 0 = nichts.
    local farmId = order.ownerFarmId or (g_currentMission ~= nil and g_currentMission:getFarmId()) or 1
    if cancelInfo.refund ~= 0 and g_currentMission ~= nil and g_currentMission.addMoney ~= nil then
        g_currentMission:addMoney(cancelInfo.refund, farmId, MoneyType.SHOP_VEHICLE_BUY, true, true)
    end

    local name = order.itemName or "?"
    table.remove(list, index)
    if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Auftrag '%s' storniert [%s]. Erstattung %d (Schaden %d, Strafe %d).",
        name, tostring(cancelInfo.stage), cancelInfo.refund, cancelInfo.damage, cancelInfo.penalty) end

    -- Benachrichtigung + Sync an Clients.
    if VehicleDeliveryNotifyEvent ~= nil then
        VehicleDeliveryNotifyEvent.broadcast("cancelled", name, 0)
    else
        VehicleDelivery.notify(string.format(g_i18n:getText("vd_notifyCancelled"), name))
    end
    if VehicleDeliverySyncEvent ~= nil then
        VehicleDeliverySyncEvent.sendToClients()
    end
    return true
end


---Einstieg vom Client oder Singleplayer: stosst das Storno an. Im MP schickt
-- der Client eine Anfrage an den Server, im SP/Host laeuft es direkt.
function VehicleDelivery.requestCancelOrder(orderId)
    if g_server ~= nil then
        local farmId = g_currentMission ~= nil and g_currentMission:getFarmId() or nil
        if g_currentMission ~= nil and g_currentMission.getHasPlayerPermission ~= nil
            and not g_currentMission:getHasPlayerPermission("buyVehicle", nil, farmId) then
            return false
        end
        return VehicleDelivery.cancelOrderOnServer(orderId, farmId)
    elseif VehicleDeliveryCancelRequestEvent ~= nil and g_client ~= nil then
        g_client:getServerConnection():sendEvent(VehicleDeliveryCancelRequestEvent.new(orderId))
        return true
    end
    return false
end


-- ==================== Region-Auswahldialog ===========================

VehicleDelivery.regionDialogShown = false

---Zeigt beim ersten Start einen Auswahldialog fuer die Spieler-Region.
-- Nutzt MultiOptionDialog (natives FS25-Element). Signatur nach FS-Konvention:
-- show(callback, target, args, title, text, options, defaultOptionIndex)
function VehicleDelivery.showRegionDialog()
    if VehicleDelivery.regionDialogShown then
        return
    end
    VehicleDelivery.regionDialogShown = true

    if InfoDialog == nil or InfoDialog.show == nil then
        Logging.warning("VehicleDelivery: InfoDialog nicht verfuegbar -- Hinweis uebersprungen (Region bleibt %s).",
            tostring(VehicleDelivery.playerRegion))
        return
    end

    local regionName = VehicleDelivery.getRegionName(VehicleDelivery.playerRegion)
    local text = string.format(
        "Vehicle Delivery ist aktiv.\n\n"
        .. "Deine Hof-Region ist auf %s gesetzt. Sie bestimmt die Lieferzeiten "
        .. "fuer Fahrzeuge aus verschiedenen Herkunftslaendern.\n\n"
        .. "Zum Aendern nutze in der Konsole: vdSetRegion <EU/NA/SA/AS/AF/OC>",
        regionName
    )

    -- InfoDialog: VERIFIZIERTE Signatur (text, callback, target, dialogType, ...).
    -- dialogType TYPE_INFO fuer das Info-Symbol statt Fragezeichen.
    local dialogType = nil
    if DialogElement ~= nil then
        dialogType = DialogElement.TYPE_INFO
    end

    InfoDialog.show(text, nil, nil, dialogType)
end


---Callback des Region-Dialogs.
-- MultiOptionDialog liefert typischerweise (clickOk, optionIndex, target/args...).
-- Wir gehen defensiv mit den Parametern um.
function VehicleDelivery.onRegionDialogResult(target, arg1, arg2)
    -- Der gewaehlte Options-Index kann je nach Signatur in arg1 oder arg2 stecken.
    local index = nil
    if type(arg1) == "number" then
        index = arg1
    elseif type(arg2) == "number" then
        index = arg2
    end

    if index == nil then
        if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Region-Dialog ohne gueltige Auswahl -- Region bleibt %s.", tostring(VehicleDelivery.playerRegion)) end
        return
    end

    local code = VehicleDelivery.REGION_ORDER[index]
    if code ~= nil and VehicleDelivery.VALID_REGIONS[code] == true then
        VehicleDelivery.playerRegion = code
        if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Region per Dialog gesetzt auf %s.", code) end
        VehicleDelivery.notify(string.format("Region gesetzt: %s", VehicleDelivery.getRegionName(code)))
    end
end


-- ==================== Diagnose: Struktur-Dumper =======================
-- Tipp eines GIANTS-Devs: statt Signaturen zu raten, die Engine zur Laufzeit
-- selbst befragen -- ueber _G / Objekte iterieren und schauen, was existiert.

---Schreibt die Struktur eines Wertes bis 'maxDepth' Tiefe ins Log.
-- @param value zu untersuchender Wert
-- @param name Anzeigename
-- @param maxDepth maximale Tiefe (Default 2)
function VehicleDelivery.dumpStructure(value, name, maxDepth)
    maxDepth = maxDepth or 2
    local t = type(value)
    Logging.info("VehicleDelivery: [DUMP] === %s (Typ %s) ===", tostring(name), t)
    -- Direkter Skalarwert: gleich anzeigen (nicht nur Tabellen-Inhalte).
    if t == "string" or t == "number" or t == "boolean" then
        Logging.info("VehicleDelivery: [DUMP] Wert = %s", tostring(value))
        return
    end
    VehicleDelivery.dumpRecursive(value, "", 0, maxDepth)
end


function VehicleDelivery.dumpRecursive(value, prefix, depth, maxDepth)
    if depth > maxDepth then
        return
    end
    if type(value) ~= "table" then
        return
    end

    -- Erst Funktionen, dann Felder -- getrennt sammeln fuer Lesbarkeit.
    local funcs = {}
    local fields = {}
    for k, v in pairs(value) do
        local tk = type(v)
        if tk == "function" then
            table.insert(funcs, tostring(k))
        elseif tk == "string" or tk == "number" or tk == "boolean" then
            -- Wert direkt mitschreiben (Strings gekuerzt), damit .name/.xmlFilename lesbar sind.
            local vs = tostring(v)
            if tk == "string" and #vs > 80 then
                vs = string.sub(vs, 1, 80) .. "..."
            end
            table.insert(fields, string.format("%s = %s", tostring(k), vs))
        else
            table.insert(fields, string.format("%s=%s", tostring(k), tk))
        end
    end
    table.sort(funcs)
    table.sort(fields)

    for _, f in ipairs(funcs) do
        Logging.info("VehicleDelivery: [DUMP] %s():%s", prefix, f)
    end
    for _, fld in ipairs(fields) do
        Logging.info("VehicleDelivery: [DUMP] %s.%s", prefix, fld)
    end

    -- Metatable (fuer geerbte Methoden aus verschlossenen Basisklassen!)
    local mt = getmetatable(value)
    if mt ~= nil and depth < maxDepth then
        local index = rawget(mt, "__index")
        if type(index) == "table" and index ~= value then
            Logging.info("VehicleDelivery: [DUMP] %s >> (Metatable __index) >>", prefix)
            VehicleDelivery.dumpRecursive(index, prefix .. "  ^", depth + 1, maxDepth)
        end
    end
end


---vdDump <globalName> [tiefe]: leuchtet eine globale Klasse/Tabelle aus.
-- z.B. vdDump MultiOptionDialog 2   oder   vdDump g_i18n 1
function VehicleDelivery.consoleDump(_, path, depthStr)
    if path == nil then
        return "Nutzung: vdDump <pfad> [tiefe].  z.B. vdDump MultiOptionDialog 2  oder  vdDump g_gui.dialogs 1"
    end
    local depth = tonumber(depthStr) or 2

    -- Pfad an "." zerlegen und Schritt fuer Schritt runterhangeln (z.B. g_gui.dialogs).
    local value = _G
    local walked = ""
    for part in string.gmatch(path, "[^%.]+") do
        if type(value) ~= "table" then
            return string.format("'%s' ist keine Tabelle -- kann '.%s' nicht folgen.", walked, part)
        end
        -- Reine Zahl -> numerischer Schluessel (z.B. dialogs.1 = dialogs[1]).
        local key = part
        local num = tonumber(part)
        if num ~= nil then
            key = num
        end
        value = value[key]
        walked = (walked == "") and part or (walked .. "." .. part)
        if value == nil then
            return string.format("'%s' existiert nicht.", walked)
        end
    end

    VehicleDelivery.dumpStructure(value, path, depth)
    return string.format("Struktur von '%s' (Tiefe %d) ins Log geschrieben.", path, depth)
end


---vdFind <muster>: listet alle globalen Namen (_G), die das Muster enthalten.
-- z.B. vdFind Dialog  -> alle Dialog-Klassen; vdFind Selection
function VehicleDelivery.consoleFind(_, pattern)
    if pattern == nil then
        return "Nutzung: vdFind <muster>.  z.B. vdFind Dialog"
    end
    local lowerPattern = string.lower(pattern)
    local hits = {}
    for name, value in pairs(_G) do
        if type(name) == "string" and string.find(string.lower(name), lowerPattern, 1, true) ~= nil then
            table.insert(hits, string.format("%s (%s)", name, type(value)))
        end
    end
    table.sort(hits)
    for _, h in ipairs(hits) do
        Logging.info("VehicleDelivery: [FIND] %s", h)
    end
    return string.format("%d Treffer fuer '%s' ins Log geschrieben.", #hits, pattern)
end


---vdSettings: findet die lebende Settings-Frame-Instanz und prueft die Schluesselfelder.
function VehicleDelivery.consoleSettings()
    local frame = nil
    if g_currentMission ~= nil and g_currentMission.inGameMenu ~= nil then
        frame = g_currentMission.inGameMenu.pageSettings
    end
    if frame == nil and g_gui ~= nil and g_gui.screenControllers ~= nil then
        local menu = g_gui.screenControllers[InGameMenu]
        if menu ~= nil then
            frame = menu.pageSettings
        end
    end
    if frame == nil then
        return "Settings-Frame nicht gefunden (Menue offen?). Felder: g_gui.screenControllers[InGameMenu].pageSettings"
    end

    Logging.info("VehicleDelivery: [SETTINGS] Frame gefunden. Pruefe Schluesselfelder:")
    for _, key in ipairs({"gameSettingsLayout", "economicDifficulty", "checkTraffic", "boxLayout", "settingsLayout"}) do
        local v = frame[key]
        Logging.info("VehicleDelivery: [SETTINGS]   .%s = %s", key, tostring(v))
        if type(v) == "table" and v.elements ~= nil then
            Logging.info("VehicleDelivery: [SETTINGS]     -> hat %d elements", #v.elements)
        end
    end
    return "Settings-Frame-Felder ins Log geschrieben."
end


---vdMenu: findet die lebende InGameMenu-Instanz und listet ihre Seiten (page*-Felder).
-- Sucht die Instanz in g_gui.screenControllers / g_gui.guis.
function VehicleDelivery.consoleMenu()
    local menu = nil
    local source = nil

    -- Kandidaten fuer die lebende Instanz durchprobieren.
    if g_gui ~= nil then
        if g_gui.screenControllers ~= nil then
            for k, v in pairs(g_gui.screenControllers) do
                if type(v) == "table" and v.pageAI ~= nil or (type(v)=="table" and tostring(k):find("InGameMenu")) then
                    menu = v; source = "screenControllers." .. tostring(k); break
                end
            end
        end
        if menu == nil and g_gui.guis ~= nil then
            local g = g_gui.guis["InGameMenu"]
            if g ~= nil then
                menu = g.target or g
                source = "guis.InGameMenu(.target)"
            end
        end
    end

    if menu == nil then
        return "Lebende InGameMenu-Instanz nicht gefunden. Menue offen? Sonst vdFields g_gui.guis probieren."
    end

    Logging.info("VehicleDelivery: [MENU] Instanz gefunden via %s", tostring(source))
    -- Alle page*-Felder auflisten.
    local count = 0
    for k, v in pairs(menu) do
        if type(k) == "string" and string.sub(k,1,4) == "page" then
            Logging.info("VehicleDelivery: [MENU] %s (%s)", k, type(v))
            count = count + 1
        end
    end
    -- Auch pagingElement / pages-Liste suchen
    for _, key in ipairs({"pages", "pagingElement", "pageSelector", "settingsPage"}) do
        if menu[key] ~= nil then
            Logging.info("VehicleDelivery: [MENU] +%s (%s)", key, type(menu[key]))
        end
    end
    return string.format("%d page*-Felder gefunden (via %s). Details im Log.", count, tostring(source))
end


---vdFields <pfad>: zeigt nur die FELDER (keine Funktionen) eines Objekts, mit Wert.
-- Nuetzlich um z.B. Seiten-Referenzen (page...) in InGameMenu zu finden.
function VehicleDelivery.consoleFields(_, path)
    if path == nil then
        return "Nutzung: vdFields <pfad>.  z.B. vdFields InGameMenu"
    end
    local value = _G
    for part in string.gmatch(path, "[^%.]+") do
        if type(value) ~= "table" then
            return string.format("'%s' ist keine Tabelle.", path)
        end
        local key = part
        local num = tonumber(part)
        if num ~= nil then key = num end
        value = value[key]
        if value == nil then
            return string.format("'%s' existiert nicht.", path)
        end
    end
    if type(value) ~= "table" then
        return string.format("'%s' Typ %s = %s", path, type(value), tostring(value))
    end

    local fields = {}
    for k, v in pairs(value) do
        local tk = type(v)
        if tk ~= "function" then
            local vs = tk
            if tk == "string" or tk == "number" or tk == "boolean" then
                vs = tostring(v)
                if tk == "string" and #vs > 60 then vs = string.sub(vs,1,60).."..." end
            end
            table.insert(fields, string.format("%s (%s) = %s", tostring(k), tk, vs))
        end
    end
    table.sort(fields)
    for _, fld in ipairs(fields) do
        Logging.info("VehicleDelivery: [FIELDS] %s", fld)
    end
    return string.format("%d Felder in '%s' ins Log.", #fields, path)
end


---vdGrep <pfad> <muster>: zeigt nur Keys eines Objekts, die das Muster enthalten.
-- Durchsucht auch die Metatable-Kette. z.B. vdGrep InGameMenu page
function VehicleDelivery.consoleGrep(_, path, pattern)
    if path == nil or pattern == nil then
        return "Nutzung: vdGrep <pfad> <muster>.  z.B. vdGrep InGameMenu page"
    end

    -- Pfad aufloesen (wie consoleDump).
    local value = _G
    for part in string.gmatch(path, "[^%.]+") do
        if type(value) ~= "table" then
            return string.format("'%s' ist keine Tabelle.", path)
        end
        local key = part
        local num = tonumber(part)
        if num ~= nil then key = num end
        value = value[key]
        if value == nil then
            return string.format("'%s' existiert nicht.", path)
        end
    end

    if type(value) ~= "table" then
        return string.format("'%s' ist keine Tabelle (Typ %s).", path, type(value))
    end

    local lowerPat = string.lower(pattern)
    local hits = {}
    -- eigene Keys + Metatable-Kette durchgehen
    local seen = {}
    local current = value
    local level = 0
    while type(current) == "table" and level < 5 do
        for k, v in pairs(current) do
            if type(k) == "string" and string.find(string.lower(k), lowerPat, 1, true) ~= nil and not seen[k] then
                seen[k] = true
                table.insert(hits, string.format("%s (%s)", k, type(v)))
            end
        end
        local mt = getmetatable(current)
        current = mt ~= nil and rawget(mt, "__index") or nil
        level = level + 1
    end

    table.sort(hits)
    for _, h in ipairs(hits) do
        Logging.info("VehicleDelivery: [GREP] %s", h)
    end
    return string.format("%d Treffer fuer '%s' in '%s' (inkl. Metatable) ins Log.", #hits, pattern, path)
end


---vdDumpVehicle [tiefe]: leuchtet das erste eigene Fahrzeug aus.
function VehicleDelivery.consoleDumpVehicle(_, depthStr)
    local depth = tonumber(depthStr) or 2
    if g_currentMission == nil then
        return "Keine Mission aktiv."
    end
    local vehicles = g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles or g_currentMission.vehicles
    if vehicles == nil or vehicles[1] == nil then
        return "Kein Fahrzeug gefunden."
    end
    VehicleDelivery.dumpStructure(vehicles[1], "Vehicle[1]", depth)
    return string.format("Struktur des ersten Fahrzeugs (Tiefe %d) ins Log geschrieben.", depth)
end


-- ==================== Konsolenbefehle Region/Test ====================

---vdSetRegion <region>: setzt die Region fuer den AKTUELLEN Spielstand.
function VehicleDelivery.consoleSetRegion(_, region)
    if g_server == nil then
        return "Die Hof-Region kann nur auf dem Server geaendert werden."
    end
    if region == nil then
        return "Nutzung: vdSetRegion <EU/NA/SA/AS/AF/OC>. Aktuell: " .. tostring(VehicleDelivery.playerRegion)
    end
    region = string.upper(region)
    if VehicleDelivery.VALID_REGIONS[region] ~= true then
        return "Ungueltige Region '" .. region .. "'. Gueltig: EU, NA, SA, AS, AF, OC"
    end
    VehicleDelivery.playerRegion = region
    if VehicleDeliverySyncEvent ~= nil then
        VehicleDeliverySyncEvent.sendToClients()
    end
    return "Spieler-Region gesetzt auf " .. region .. " (wird beim naechsten Speichern gesichert)."
end


---vdSkipDay: spult die Lieferungen um 24 Spielstunden vor (zum Testen).
function VehicleDelivery.consoleSkipDay()
    VehicleDelivery.advanceDeliveries(24)
    return string.format("24 Spielstunden vorgespult. Offene Lieferauftraege: %d", #VehicleDelivery.pendingDeliveries)
end


-- ==================== Lieferauftraege: Zaehlwerk ======================

---Stundenwechsel im Spiel: Lieferungen um eine Spielstunde voranbringen.
function VehicleDelivery.onHourChanged()
    VehicleDelivery.advanceDeliveries(1)
end


---Bringt alle Auftraege um gameHours Spielstunden voran und liefert faellige aus.
-- Die Auftraege zaehlen in Kalendertagen; wie viele davon eine Spielstunde
-- ausmacht, haengt von der Einstellung "Tage pro Monat" ab.
function VehicleDelivery.advanceDeliveries(gameHours)
    -- Auslieferung ist Server-Aufgabe. Ein reiner Client hat nur die abgespeckte
    -- Sync-Liste (ohne storeItem/Spawn-Daten) und darf NICHT ausliefern -- sonst
    -- "deliverOrder ohne gueltige Auftragsdaten". Der Server sendet danach die
    -- aktualisierte Liste an die Clients.
    if g_server == nil then
        return
    end

    local list = VehicleDelivery.pendingDeliveries
    if list == nil or #list == 0 then
        return
    end

    -- Vergangene Zeit in Kalendertagen (Lieferzeit-Einheit der Mod).
    local step = VehicleDelivery.getDaysForGameHours(gameHours or 1)
    if step <= 0 then
        return
    end

    if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: +%d Spielstunde(n) = %.3f Tag(e) -- %d offene Lieferung(en).",
        gameHours or 1, step, #list) end

    -- Erst runterzaehlen und faellige Auftraege sammeln (noch nicht ausliefern).
    -- Faellige, bei denen die Restzahlung nicht gedeckt ist, werden NICHT
    -- geliefert: sie bleiben mit daysLeft=0 + awaitingPayment in der Liste.
    local due = {}
    local availableMoneyByFarm = {}
    for i = #list, 1, -1 do
        local order = list[i]

        -- Lieferverzoegerung: einmalige Chance auf +1-2 Tage, DELAY_CHANCE je
        -- Kalendertag (auf den Zeitschritt umgerechnet). Nur bei noch laufenden
        -- Auftraegen (daysLeft > 1, nicht kurz vor Lieferung) und hoechstens
        -- einmal pro Auftrag (wasDelayed).
        if VehicleDelivery.delaysEnabled and not order.wasDelayed and order.daysLeft > 1 then
            local chance = 1 - (1 - VehicleDelivery.DELAY_CHANCE) ^ step
            if math.random() < chance then
                local extra = math.random(VehicleDelivery.DELAY_MIN, VehicleDelivery.DELAY_MAX)
                order.daysLeft = order.daysLeft + extra
                if order.totalDays ~= nil then
                    order.totalDays = order.totalDays + extra
                end
                order.wasDelayed = true
                VehicleDelivery.notify(string.format(g_i18n:getText("vd_notifyDelayed"),
                    tostring(order.itemName), VehicleDelivery.formatDuration(extra)))
                if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: '%s' verzoegert sich um %d Tag(e).",
                    tostring(order.itemName), extra) end
            end
        end

        if order.daysLeft > 0 then
            order.daysLeft = math.max(0, order.daysLeft - step)
        end

        if order.daysLeft <= VehicleDelivery.TIME_EPSILON then
            -- Kann die Restzahlung gedeckt werden?
            local canPay = true
            local rest = order.remainingPayment or 0
            local farmId = order.ownerFarmId or (g_currentMission ~= nil and g_currentMission:getFarmId())
            if rest > 0 then
                canPay = g_currentMission ~= nil and g_currentMission.getMoney ~= nil
                    and g_currentMission.addMoney ~= nil and farmId ~= nil
                if canPay then
                    if availableMoneyByFarm[farmId] == nil then
                        availableMoneyByFarm[farmId] = g_currentMission:getMoney(farmId)
                    end
                    canPay = availableMoneyByFarm[farmId] >= rest
                    if canPay then
                        availableMoneyByFarm[farmId] = availableMoneyByFarm[farmId] - rest
                    end
                end
            end

            if canPay then
                order.awaitingPayment = false
                table.insert(due, order)
                table.remove(list, i)
            else
                -- Geld fehlt: Lieferung wartet. Auftrag bleibt in der Liste.
                order.daysLeft = 0
                if not order.awaitingPayment then
                    order.awaitingPayment = true
                    -- Einmalige Warnung an den Spieler.
                    VehicleDelivery.notify(string.format(
                        g_i18n:getText("vd_notifyAwaitingPayment"), tostring(order.itemName)))
                    if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: '%s' faellig, aber Restzahlung nicht gedeckt -- wartet.",
                        tostring(order.itemName)) end
                end
            end
        else
            if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: '%s' noch %.2f Tag(e) = %s.", tostring(order.itemName),
                order.daysLeft, VehicleDelivery.formatDuration(order.daysLeft)) end
        end
    end

    -- Faellige mit seitlichem Versatz ausliefern, damit sie nicht ineinander stecken.
    -- accumOffset waechst pro Fahrzeug um dessen Breite (+ Abstand).
    local accumOffset = 0
    for _, order in ipairs(due) do
        if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: LIEFERUNG '%s' eingetroffen -- lade Fahrzeug...", tostring(order.itemName)) end

        local halfWidth = VehicleDelivery.getOrderHalfWidth(order)
        -- Vor dem Spawn: um halbe eigene Breite weiterruecken (Mitte des naechsten Platzes)
        accumOffset = accumOffset + halfWidth
        VehicleDelivery.deliverOrder(order, accumOffset)
        -- Danach: restliche halbe Breite + Abstand fuer den naechsten
        accumOffset = accumOffset + halfWidth + VehicleDelivery.DELIVERY_GAP
    end

    -- MP: Server schickt die aktualisierte Liste (Tage runter, faellige raus) an Clients.
    if VehicleDeliverySyncEvent ~= nil then
        VehicleDeliverySyncEvent.sendToClients()
    end
end


---Halbe Breite eines Auftrags-Fahrzeugs (aus Store-Item-Massen). Fallback 3m.
function VehicleDelivery.getOrderHalfWidth(order)
    if order ~= nil and order.xmlFilename ~= nil and StoreItemUtil ~= nil and StoreItemUtil.getSizeValues ~= nil then
        local yRot = order.spawnRY or 0
        local size = StoreItemUtil.getSizeValues(order.xmlFilename, "vehicle", yRot, order.configurations or {})
        if size ~= nil and size.width ~= nil and size.width > 0 then
            return size.width * 0.5
        end
    end
    return 3.0
end


---Konsolenbefehl: Test-Auftrag anlegen. vdTestOrder <tage> [name]
function VehicleDelivery.consoleAddTestOrder(_, days, name)
    local d = tonumber(days)
    if d == nil or d < 1 then
        return "Nutzung: vdTestOrder <tage> [name]   (tage muss >= 1 sein)"
    end
    name = name or "Testmaschine"

    local order = { itemName = name, brandName = "TEST", daysLeft = d }
    VehicleDelivery.assignOrderId(order)
    table.insert(VehicleDelivery.pendingDeliveries, order)
    return string.format("Test-Auftrag angelegt: '%s' in %d Tag(en). Offen: %d",
        name, d, #VehicleDelivery.pendingDeliveries)
end


---Konsolenbefehl: offene Auftraege listen.
function VehicleDelivery.consoleListOrders()
    local list = VehicleDelivery.pendingDeliveries
    if list == nil or #list == 0 then
        return "Keine offenen Lieferauftraege."
    end
    local lines = { string.format("%d offene Lieferauftraege:", #list) }
    for i, order in ipairs(list) do
        table.insert(lines, string.format("  %d) '%s' -- noch %.2f Tag(e) = %s", i, tostring(order.itemName),
            order.daysLeft or 0, VehicleDelivery.formatDuration(order.daysLeft)))
    end
    return table.concat(lines, "\n")
end


-- ==================== Benachrichtigung ================================

---Zeigt dem Spieler eine Bildschirm-Nachricht. Nutzt die erste verfuegbare
-- FS-Notification-Methode (Name variiert je Version) -- defensiv, ohne pcall.
-- @param string text anzuzeigender Text
function VehicleDelivery.notify(text)
    if text == nil then
        return
    end

    local mission = g_currentMission
    if mission == nil then
        if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: (keine Mission fuer Notification) %s", text) end
        return
    end

    -- Variante A: addIngameNotification (haeufigste in FS22/FS25)
    if mission.addIngameNotification ~= nil and FSBaseMission ~= nil and FSBaseMission.INGAME_NOTIFICATION_OK ~= nil then
        mission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, text)
        return
    end

    -- Variante B: hud:addSideNotification
    if mission.hud ~= nil and mission.hud.addSideNotification ~= nil then
        -- Farbe: weiss/gruen, falls verfuegbar
        mission.hud:addSideNotification(nil, text)
        return
    end

    -- Variante C: showBlinkingWarning (immer vorhanden, kurze Warnung)
    if mission.showBlinkingWarning ~= nil then
        mission:showBlinkingWarning(text, 4000)
        return
    end

    -- Fallback: wenigstens ins Log
    if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: (Notification) %s", text) end
end


-- ==================== Lieferung ausliefern ============================

---Laedt das Fahrzeug eines faelligen Auftrags an der gemerkten Shop-Position.
-- Restzahlung inklusive gespeicherten Zollbetrags wird bei Lieferung bezahlt.
function VehicleDelivery.deliverOrder(order, sideOffset)
    if order == nil or order.storeItem == nil then
        Logging.warning("VehicleDelivery: deliverOrder ohne gueltige Auftragsdaten -- abgebrochen.")
        return
    end
    sideOffset = sideOffset or 0

    -- Anzahlungsmodell: Restbetrag (80%) bei Lieferung abbuchen. Die Deckung
    -- wurde bereits in advanceDeliveries geprueft (sonst wartet die Lieferung).
    local chargedPayment = order.remainingPayment or 0
    if chargedPayment > 0 and g_currentMission ~= nil and g_currentMission.addMoney ~= nil then
        local farmId = order.ownerFarmId or g_currentMission:getFarmId()
        g_currentMission:addMoney(-order.remainingPayment, farmId, MoneyType.SHOP_VEHICLE_BUY, true, true)
        if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Restzahlung %d bei Lieferung abgebucht.", order.remainingPayment) end
    end

    local data = VehicleLoadingData.new()
    data:setStoreItem(order.storeItem)
    data:setConfigurations(order.configurations, order.boughtConfigurations)
    data:setConfigurationData(order.configurationData)
    data:setPropertyState(VehiclePropertyState.OWNED)
    data:setOwnerFarmId(order.ownerFarmId)

    -- Position: an der beim Kauf gemerkten Shop-Stelle spawnen, ggf. seitlich versetzt.
    if order.spawnX ~= nil then
        local px, pz = order.spawnX, order.spawnZ
        if sideOffset ~= 0 then
            -- seitlich = senkrecht zur Blickrichtung (yRot). Rechtsversatz.
            local yRot = order.spawnRY or 0
            px = px + math.cos(yRot) * sideOffset
            pz = pz - math.sin(yRot) * sideOffset
        end
        data:setPosition(px, order.spawnY, pz)
        if order.spawnRX ~= nil then
            data:setRotation(order.spawnRX, order.spawnRY, order.spawnRZ)
        end
    else
        Logging.warning("VehicleDelivery: '%s' ohne gemerkte Position -- Spiel waehlt Standardposition.", tostring(order.itemName))
    end

    data:load(VehicleDelivery.onDelivered, VehicleDelivery, {
        itemName = order.itemName,
        licensePlateData = order.licensePlateData,
        order = order,
        chargedPayment = chargedPayment,
    })
end


---Callback nach dem Ausliefern.
function VehicleDelivery.onDelivered(_, loadedVehicles, loadingState, args)
    if args == nil or args.processed then
        return
    end
    args.processed = true
    local name = (args ~= nil and args.itemName) or "?"
    local order = args.order
    if loadingState ~= VehicleLoadingState.OK or loadedVehicles == nil or #loadedVehicles == 0 then
        for _, vehicle in ipairs(loadedVehicles or {}) do
            if vehicle.delete ~= nil then
                vehicle:delete()
            end
        end
        -- Fehlgeschlagener Spawn: Zahlung zurueckgeben und denselben Auftrag
        -- mit unveraenderten Zollwerten fuer die naechste Spielstunde wiederherstellen.
        if order ~= nil then
            if (args.chargedPayment or 0) > 0 then
                local farmId = order.ownerFarmId or g_currentMission:getFarmId()
                g_currentMission:addMoney(args.chargedPayment, farmId, MoneyType.SHOP_VEHICLE_BUY, true, true)
            end
            order.daysLeft = 0
            order.awaitingPayment = false
            table.insert(VehicleDelivery.pendingDeliveries, order)
            if VehicleDeliverySyncEvent ~= nil then
                VehicleDeliverySyncEvent.sendToClients()
            end
        end
        Logging.warning("VehicleDelivery: '%s' konnte nicht geliefert werden -- Auftrag wiederhergestellt.", name)
        VehicleDelivery.notify(string.format(g_i18n:getText("vd_notifyDeliveryFailed"), name))
        return
    end
    if order ~= nil then
        order.remainingPayment = 0
    end
    local n = 0
    if loadedVehicles ~= nil then
        for _, v in ipairs(loadedVehicles) do
            if v ~= nil then n = n + 1 end
        end
    end
    if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: '%s' geliefert -- %d Fahrzeug(e) gespawnt (loadingState=%s).",
        name, n, tostring(loadingState)) end

    -- Kennzeichen ans gelieferte Fahrzeug uebertragen (aus dem Kauf gemerkt).
    local plateData = args ~= nil and args.licensePlateData or nil
    if plateData ~= nil and loadedVehicles ~= nil and loadedVehicles[1] ~= nil then
        local vehicle = loadedVehicles[1]
        if vehicle.setLicensePlatesData ~= nil then
            vehicle:setLicensePlatesData(plateData)
            if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Kennzeichen ans gelieferte Fahrzeug uebertragen.") end
        end
    end

    if VehicleDeliveryNotifyEvent ~= nil then
        VehicleDeliveryNotifyEvent.broadcast("delivered", name, 0)
    else
        VehicleDelivery.notify(string.format(g_i18n:getText("vd_notifyDelivered"), name))
    end
end


-- ==================== Abgefangener Kauf ===============================

function VehicleDelivery.onBuy(self, superFunc, storePlaces, usedStorePlaces, callback, callbackTarget, callbackArguments)
    -- Gebraucht, Miete, kostenlos, In-App und Sofort-Kategorien (Paletten,
    -- BigBags, Container, Ballen, IBC ...) sind sofort verfuegbar.
    if g_server == nil or not VehicleDelivery.getIsDelayedPurchase(self.storeItem, self.saleItem,
        self.leaseVehicle, self.isFreeOfCharge) then
        return superFunc(self, storePlaces, usedStorePlaces, callback, callbackTarget, callbackArguments)
    end

    -- "Sonderkonfig" am Aufpreis erkennen (konsistent mit der Shop-Anzeige):
    -- der volle Preis inkl. Konfig (bei Anzahlung in vdFullPrice, weil price dann
    -- schon die Anzahlung ist), storeItem.price ist der Basispreis.
    local basePrice = (self.storeItem ~= nil and self.storeItem.price) or 0
    local fullPrice = self.vdFullPrice or self.price or basePrice
    local quote = VehicleDelivery.getCustomsQuote(self.storeItem, fullPrice)

    -- Das Spiel bucht beim Kauf self.price ab: nur "Zahlung jetzt" (Anzahlung
    -- bzw. ohne Anzahlung den vollen Fahrzeugpreis). Der Rest inkl. Zoll wird
    -- bei der Lieferung faellig.
    self.vdFullPrice = fullPrice
    self.price = quote.upfrontPayment
    local isBaseConfig = (fullPrice <= basePrice)
    local days = VehicleDelivery.calculateDeliveryDaysWithBase(self.storeItem, isBaseConfig)
    -- info nur fuer die Log-Ausgabe (Regionen/Sprünge) weiterhin ermitteln.
    local _, info = VehicleDelivery.calculateDeliveryDays(self.storeItem, self.configurations)
    info.totalDays = days
    info.isBase = isBaseConfig
    info.configDays = (isBaseConfig and 0 or VehicleDelivery.CONFIG_DAYS)

    local itemName = "?"
    if self.storeItem ~= nil and self.storeItem.name ~= nil then
        itemName = self.storeItem.name
    end

    -- Herstellername fuer die Anzeige in der Menue-Liste ermitteln.
    local brandName = VehicleDelivery.getBrandName(self.storeItem)

    -- Shop-Vorschaubild fuer die Anzeige in der Auftragsliste.
    local imageFilename = nil
    if self.storeItem ~= nil then
        imageFilename = self.storeItem.imageFilename
    end

    if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: '%s' -> %d Tage Lieferzeit [Basis=%s, Konfig+%d, Region %s->%s = %d Sprünge/+%d Tage]",
        itemName, info.totalDays, tostring(info.isBase), info.configDays,
        info.playerRegion, info.originRegion, info.hops, info.regionDays) end



    -- BAUSTEIN 2 - STUFE 1: Kauf normal durchlaufen lassen, aber unseren eigenen
    -- Callback einschieben. Der ruft erst den Original-Callback (Shop zufrieden,
    -- kein Haenger, Geld abgezogen) und loescht dann das geladene Fahrzeug sofort
    -- wieder. Noch OHNE Auftrag/Wiedererscheinen -- reiner Test: laesst sich das
    -- Fahrzeug sauber abfangen und entfernen?
    -- Kaufdaten fuer den Lieferauftrag sichern (alles, was buy() zum Laden braucht).
    local orderData = {
        itemName = itemName,
        brandName = brandName,
        imageFilename = imageFilename,
        daysLeft = days,
        totalDays = days,
        storeItem = self.storeItem,
        xmlFilename = (self.storeItem ~= nil and self.storeItem.xmlFilename) or nil,
        configurations = self.configurations,
        boughtConfigurations = self.boughtConfigurations,
        configurationData = self.configurationData,
        leaseVehicle = self.leaseVehicle,
        ownerFarmId = self.ownerFarmId,
        licensePlateData = self.licensePlateData,
        price = fullPrice,
        originRegion = quote.originRegion,
        destinationRegion = quote.destinationRegion,
        customsRate = quote.customsRate,
        customsFee = quote.customsFee,
        remainingPayment = quote.remainingPayment,
    }

    local args = {
        origCallback = callback,
        origCallbackTarget = callbackTarget,
        origCallbackArguments = callbackArguments,
        orderData = orderData,
    }
    return superFunc(self, storePlaces, usedStorePlaces, VehicleDelivery.onVehicleBought, VehicleDelivery, args)
end


---Eigener Callback nach dem Laden des gekauften Fahrzeugs.
-- Signatur wie der Original-Callback (onBought ruft: callbackTarget, loadedVehicles, loadingState, callbackArguments)
function VehicleDelivery.onVehicleBought(_, loadedVehicles, loadingState, args)
    if args == nil or args.processed then
        return
    end
    args.processed = true
    -- 1) Original-Callback zuerst aufrufen, damit der Shop weitermacht.
    if args ~= nil and args.origCallback ~= nil then
        args.origCallback(args.origCallbackTarget, loadedVehicles, loadingState, args.origCallbackArguments)
    end

    -- Ein fehlgeschlagener Kauf erzeugt weder Rueckerstattung noch Auftrag.
    if g_server == nil or loadingState ~= VehicleLoadingState.OK
        or loadedVehicles == nil or #loadedVehicles == 0 then
        return
    end

    -- 2) Lieferauftrag anlegen (Kaufdaten merken), dann Fahrzeug entfernen.
    local orderData = args ~= nil and args.orderData or nil
    local name = orderData ~= nil and orderData.itemName or "?"

    -- Anzahlungsmodell: Das Spiel hat beim Kauf nur "Zahlung jetzt" abgebucht
    -- (siehe onUpdateBuyPrice/onBuy). Der Rest wird bei Lieferung faellig.

    if orderData ~= nil then
        VehicleDelivery.assignOrderId(orderData)
        table.insert(VehicleDelivery.pendingDeliveries, orderData)
        if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: [Stufe2] Lieferauftrag angelegt: '%s' in %s. Offen: %d",
            name, VehicleDelivery.formatDuration(orderData.daysLeft), #VehicleDelivery.pendingDeliveries) end

        -- MP: Server schickt die aktualisierte Liste an alle Clients.
        if VehicleDeliverySyncEvent ~= nil then
            VehicleDeliverySyncEvent.sendToClients()
        end

        -- Benachrichtigung "Lieferung in X Tagen" (lokal + an Clients).
        if VehicleDeliveryNotifyEvent ~= nil then
            VehicleDeliveryNotifyEvent.broadcast("ordered", name, orderData.daysLeft)
        else
            VehicleDelivery.notify(string.format(g_i18n:getText("vd_notifyOrdered"), name,
                VehicleDelivery.formatDuration(orderData.daysLeft)))
        end

    else
        Logging.warning("VehicleDelivery: [Stufe2] '%s' -- keine orderData, kein Auftrag angelegt!", name)
    end

    if loadedVehicles ~= nil then
        -- Spawn-Position/-Rotation vom ersten (Haupt-)Fahrzeug merken -- genau da,
        -- wo das Spiel es auf der Shopflaeche platziert hat.
        if orderData ~= nil then
            local first = loadedVehicles[1]
            if first ~= nil and first.components ~= nil and first.components[1] ~= nil and first.components[1].node ~= nil then
                local node = first.components[1].node
                local x, y, z = getWorldTranslation(node)
                local rx, ry, rz = getWorldRotation(node)
                orderData.spawnX, orderData.spawnY, orderData.spawnZ = x, y, z
                orderData.spawnRX, orderData.spawnRY, orderData.spawnRZ = rx, ry, rz
                if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: [Stufe3] Spawn-Position gemerkt: %.1f / %.1f / %.1f", x, y, z) end
            else
                Logging.warning("VehicleDelivery: [Stufe3] '%s' -- keine Position auslesbar, Lieferung nutzt Fallback.", name)
            end
        end

        local n = 0
        for _, vehicle in ipairs(loadedVehicles) do
            if vehicle ~= nil and vehicle.delete ~= nil then
                vehicle:delete()
                n = n + 1
            end
        end
        if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: [Stufe2] '%s' -> %d Fahrzeug(e) entfernt, wartet jetzt auf Lieferung.", name, n) end
    else
        Logging.warning("VehicleDelivery: [Stufe2] '%s' -- keine loadedVehicles im Callback.", name)
    end
end


-- ==================== Persistenz (Save/Load) ==========================
-- Muster aus Courseplay_FS25.

VehicleDelivery.SAVE_FILENAME = "vehicleDelivery.xml"

function VehicleDelivery.getSavegamePath()
    if g_currentMission == nil or g_currentMission.missionInfo == nil then
        return nil
    end
    local dir = g_currentMission.missionInfo.savegameDirectory
    if dir == nil then
        return nil
    end
    return dir .. "/" .. VehicleDelivery.SAVE_FILENAME
end


function VehicleDelivery.onSaveGame(missionInfo)
    if missionInfo == nil or not missionInfo.isValid then
        return
    end
    local dir = missionInfo.savegameDirectory
    if dir == nil then
        return
    end

    local path = dir .. "/" .. VehicleDelivery.SAVE_FILENAME
    local xmlFile = XMLFile.create("vehicleDeliverySave", path, "vehicleDelivery")
    if xmlFile == nil then
        Logging.warning("VehicleDelivery: Savegame-Datei konnte nicht angelegt werden (%s).", path)
        return
    end

    -- Spieler-Region dieses Spielstands mitspeichern.
    if VehicleDelivery.playerRegion ~= nil then
        xmlFile:setString("vehicleDelivery#playerRegion", VehicleDelivery.playerRegion)
    end

    -- Anzahlungs-Einstellung mitspeichern.
    xmlFile:setBool("vehicleDelivery#downpaymentEnabled", VehicleDelivery.downpaymentEnabled)
    xmlFile:setBool("vehicleDelivery#delaysEnabled", VehicleDelivery.delaysEnabled)
    xmlFile:setBool("vehicleDelivery#customsEnabled", VehicleDelivery.customsEnabled)
    xmlFile:setInt("vehicleDelivery#nextOrderId", VehicleDelivery.nextOrderId)

    local i = 0
    for _, order in ipairs(VehicleDelivery.pendingDeliveries) do
        if order.xmlFilename ~= nil and order.daysLeft ~= nil then
            local key = string.format("vehicleDelivery.order(%d)", i)
            VehicleDelivery.assignOrderId(order)
            xmlFile:setInt(key .. "#orderId", order.orderId)
            xmlFile:setString(key .. "#xmlFilename", order.xmlFilename)
            -- Kalendertage als Kommazahl (laufen stuendlich ab).
            xmlFile:setFloat(key .. "#daysLeft", order.daysLeft)
            xmlFile:setFloat(key .. "#totalDays", order.totalDays or order.daysLeft)
            xmlFile:setInt(key .. "#remainingPayment", order.remainingPayment or 0)
            xmlFile:setInt(key .. "#price", order.price or 0)
            xmlFile:setFloat(key .. "#customsRate", order.customsRate or 0)
            xmlFile:setInt(key .. "#customsFee", order.customsFee or 0)
            if order.originRegion ~= nil then
                xmlFile:setString(key .. "#originRegion", order.originRegion)
            end
            if order.destinationRegion ~= nil then
                xmlFile:setString(key .. "#destinationRegion", order.destinationRegion)
            end
            xmlFile:setBool(key .. "#awaitingPayment", order.awaitingPayment == true)
            xmlFile:setBool(key .. "#wasDelayed", order.wasDelayed == true)
            xmlFile:setString(key .. "#itemName", order.itemName or "?")
            if order.brandName ~= nil then
                xmlFile:setString(key .. "#brandName", order.brandName)
            end
            if order.imageFilename ~= nil then
                xmlFile:setString(key .. "#imageFilename", order.imageFilename)
            end
            if order.ownerFarmId ~= nil then
                xmlFile:setInt(key .. "#ownerFarmId", order.ownerFarmId)
            end
            if order.spawnX ~= nil then
                xmlFile:setFloat(key .. "#spawnX", order.spawnX)
                xmlFile:setFloat(key .. "#spawnY", order.spawnY)
                xmlFile:setFloat(key .. "#spawnZ", order.spawnZ)
            end
            if order.spawnRX ~= nil then
                xmlFile:setFloat(key .. "#spawnRX", order.spawnRX)
                xmlFile:setFloat(key .. "#spawnRY", order.spawnRY)
                xmlFile:setFloat(key .. "#spawnRZ", order.spawnRZ)
            end

            -- Konfigurationen (configName -> index) als Unter-Eintraege speichern.
            if order.configurations ~= nil then
                local c = 0
                for configName, index in pairs(order.configurations) do
                    if type(index) == "number" then
                        local cKey = string.format("%s.configuration(%d)", key, c)
                        xmlFile:setString(cKey .. "#name", configName)
                        xmlFile:setInt(cKey .. "#index", index)
                        c = c + 1
                    end
                end
            end

            -- Kennzeichen (licensePlateData) speichern.
            local plate = order.licensePlateData
            if plate ~= nil then
                local pKey = key .. ".licensePlate"
                if plate.colorIndex ~= nil then xmlFile:setInt(pKey .. "#colorIndex", plate.colorIndex) end
                if plate.placementIndex ~= nil then xmlFile:setInt(pKey .. "#placementIndex", plate.placementIndex) end
                if plate.variation ~= nil then xmlFile:setInt(pKey .. "#variation", plate.variation) end
                if plate.hasFrontPlate ~= nil then xmlFile:setBool(pKey .. "#hasFrontPlate", plate.hasFrontPlate) end
                -- characters als einzelne Unter-Eintraege (Reihenfolge wichtig).
                if type(plate.characters) == "table" then
                    for ci, ch in ipairs(plate.characters) do
                        local chKey = string.format("%s.char(%d)", pKey, ci - 1)
                        xmlFile:setString(chKey .. "#v", tostring(ch))
                    end
                end
            end

            i = i + 1
        end
    end

    xmlFile:save()
    xmlFile:delete()
    if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: %d Lieferauftrag/-auftraege gespeichert.", i) end
end


function VehicleDelivery.loadFromSavegame()
    local path = VehicleDelivery.getSavegamePath()
    if path == nil or not fileExists(path) then
        return
    end

    local xmlFile = XMLFile.load("vehicleDeliveryLoad", path)
    if xmlFile == nil then
        Logging.warning("VehicleDelivery: Savegame-Datei konnte nicht geladen werden (%s).", path)
        return
    end

    -- Spieler-Region dieses Spielstands laden.
    local region = xmlFile:getString("vehicleDelivery#playerRegion")
    if region ~= nil and VehicleDelivery.VALID_REGIONS[region] == true then
        VehicleDelivery.playerRegion = region
        if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Spieler-Region = %s (aus Savegame).", region) end
    end

    -- Anzahlungs-Einstellung laden.
    if xmlFile:hasProperty("vehicleDelivery#downpaymentEnabled") then
        VehicleDelivery.downpaymentEnabled = xmlFile:getBool("vehicleDelivery#downpaymentEnabled")
    end
    if xmlFile:hasProperty("vehicleDelivery#delaysEnabled") then
        VehicleDelivery.delaysEnabled = xmlFile:getBool("vehicleDelivery#delaysEnabled")
    end
    if xmlFile:hasProperty("vehicleDelivery#customsEnabled") then
        VehicleDelivery.customsEnabled = xmlFile:getBool("vehicleDelivery#customsEnabled")
    end
    VehicleDelivery.nextOrderId = math.max(1, xmlFile:getInt("vehicleDelivery#nextOrderId") or 1)
    -- Freie IDs oberhalb aller gespeicherten IDs halten (auch bei Altauftraegen).
    xmlFile:iterate("vehicleDelivery.order", function(_, key)
        VehicleDelivery.nextOrderId = math.max(VehicleDelivery.nextOrderId,
            (xmlFile:getInt(key .. "#orderId") or 0) + 1)
    end)

    local count = 0
    xmlFile:iterate("vehicleDelivery.order", function(_, key)
        local xmlFilename = xmlFile:getString(key .. "#xmlFilename")
        local daysLeft = xmlFile:getFloat(key .. "#daysLeft")
        local totalDays = xmlFile:getFloat(key .. "#totalDays") or daysLeft
        local remainingPayment = xmlFile:getInt(key .. "#remainingPayment") or 0
        local price = xmlFile:getInt(key .. "#price") or 0
        local awaitingPayment = xmlFile:getBool(key .. "#awaitingPayment") == true
        local wasDelayed = xmlFile:getBool(key .. "#wasDelayed") == true
        if xmlFilename ~= nil and daysLeft ~= nil then
            local storeItem = nil
            if g_storeManager ~= nil then
                storeItem = g_storeManager:getItemByXMLFilename(xmlFilename)
            end
            if storeItem ~= nil then
                -- Konfigurationen zuruecklesen + boughtConfigurations rekonstruieren.
                local configurations = {}
                local boughtConfigurations = {}
                xmlFile:iterate(key .. ".configuration", function(_, cKey)
                    local cName = xmlFile:getString(cKey .. "#name")
                    local cIndex = xmlFile:getInt(cKey .. "#index")
                    if cName ~= nil and cIndex ~= nil then
                        configurations[cName] = cIndex
                        if boughtConfigurations[cName] == nil then
                            boughtConfigurations[cName] = {}
                        end
                        boughtConfigurations[cName][cIndex] = true
                    end
                end)

                -- Kennzeichen (licensePlateData) aus der XML rekonstruieren.
                local licensePlateData = nil
                local pKey = key .. ".licensePlate"
                if xmlFile:hasProperty(pKey) then
                    licensePlateData = {
                        colorIndex = xmlFile:getInt(pKey .. "#colorIndex") or 1,
                        placementIndex = xmlFile:getInt(pKey .. "#placementIndex") or 1,
                        variation = xmlFile:getInt(pKey .. "#variation") or 1,
                        hasFrontPlate = xmlFile:getBool(pKey .. "#hasFrontPlate"),
                        characters = {},
                    }
                    local ci = 0
                    while true do
                        local chKey = string.format("%s.char(%d)", pKey, ci)
                        if not xmlFile:hasProperty(chKey .. "#v") then
                            break
                        end
                        licensePlateData.characters[ci + 1] = xmlFile:getString(chKey .. "#v")
                        ci = ci + 1
                    end
                end

                local order = {
                    orderId = xmlFile:getInt(key .. "#orderId"),
                    itemName = xmlFile:getString(key .. "#itemName") or "?",
                    brandName = xmlFile:getString(key .. "#brandName"),
                    imageFilename = xmlFile:getString(key .. "#imageFilename"),
                    daysLeft = daysLeft,
                    totalDays = totalDays,
                    remainingPayment = remainingPayment,
                    price = price,
                    -- Altauftraege behalten Zoll = 0; kein nachtraeglicher Tarif.
                    customsRate = xmlFile:getFloat(key .. "#customsRate") or 0,
                    customsFee = xmlFile:getInt(key .. "#customsFee") or 0,
                    originRegion = xmlFile:getString(key .. "#originRegion") or VehicleDelivery.getStoreItemRegion(storeItem),
                    destinationRegion = xmlFile:getString(key .. "#destinationRegion") or VehicleDelivery.playerRegion or VehicleDelivery.DEFAULT_PLAYER_REGION,
                    awaitingPayment = awaitingPayment,
                    wasDelayed = wasDelayed,
                    storeItem = storeItem,
                    xmlFilename = xmlFilename,
                    configurations = configurations,
                    boughtConfigurations = boughtConfigurations,
                    licensePlateData = licensePlateData,
                    ownerFarmId = xmlFile:getInt(key .. "#ownerFarmId") or g_currentMission:getFarmId(),
                    spawnX = xmlFile:getFloat(key .. "#spawnX"),
                    spawnY = xmlFile:getFloat(key .. "#spawnY"),
                    spawnZ = xmlFile:getFloat(key .. "#spawnZ"),
                    spawnRX = xmlFile:getFloat(key .. "#spawnRX"),
                    spawnRY = xmlFile:getFloat(key .. "#spawnRY"),
                    spawnRZ = xmlFile:getFloat(key .. "#spawnRZ"),
                }
                VehicleDelivery.assignOrderId(order)
                table.insert(VehicleDelivery.pendingDeliveries, order)
                count = count + 1
            else
                Logging.warning("VehicleDelivery: Store-Item fuer '%s' nicht gefunden -- Auftrag uebersprungen.", tostring(xmlFilename))
            end
        end
    end)

    xmlFile:delete()
    if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: %d Lieferauftrag/-auftraege aus Savegame geladen.", count) end
end


function VehicleDelivery:loadMap(filename)
    VehicleDelivery.pendingDeliveries = {}
    VehicleDelivery.playerRegion = nil
    VehicleDelivery.nextOrderId = 1
    VehicleDelivery.downpaymentEnabled = true
    VehicleDelivery.delaysEnabled = true
    VehicleDelivery.customsEnabled = true
    local hadRegion = (VehicleDelivery.playerRegion ~= nil)
    VehicleDelivery.loadFromSavegame()
    local loadedRegion = (VehicleDelivery.playerRegion ~= nil)
    VehicleDelivery.setDefaultRegionIfUnset()

    -- GUI + Textanpassung NUR auf dem Client -- ein dedizierter Server hat keine
    -- GUI (g_gui/InGameMenu fehlen). Ohne diese Pruefung ist die Mod nicht
    -- server-kompatibel, weil loadMap auf dem Dedi die GUI-Aufrufe crasht.
    local hasGui = (g_dedicatedServer == nil) and (g_gui ~= nil)

    if hasGui then
        -- Kaufbestaetigungs-Text ueberschreiben -- HIER (nicht in init), weil g_i18n
        -- beim frühen init() noch nicht bereit ist. FS-Standard "Dein Kauf ist beim
        -- Haendler abholbereit" ist falsch -- die Maschine ist unterwegs.
        local newText = g_i18n ~= nil and g_i18n:getText("vd_purchaseOrdered") or nil
        if newText == nil then
            -- ohne Text nichts ueberschreiben
        elseif g_i18n.setGlobalText ~= nil then
            g_i18n:setGlobalText("shop_messagePurchaseReady", newText)
            if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Kaufbestaetigungs-Text ueberschrieben (setGlobalText).") end
        elseif g_i18n ~= nil and g_i18n.setText ~= nil then
            g_i18n:setText("shop_messagePurchaseReady", newText)
            if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Kaufbestaetigungs-Text ueberschrieben (setText-Fallback).") end
        end

        -- Eigene Menue-Seite ins InGameMenu einhaengen (nach YieldTracker-Vorbild).
        if VehicleDeliveryGUI ~= nil then
            VehicleDeliveryGUI:setup()
        else
            Logging.warning("VehicleDelivery: VehicleDeliveryGUI nicht geladen -- keine Menue-Seite.")
        end

        -- Region-Auswahl in die Spieleinstellungen einhaengen (nach CombineXP-Vorbild).
        if VehicleDeliverySettings ~= nil then
            VehicleDeliverySettings.install()
        end

        -- Lieferzeit im Shop-Kaufbildschirm anzeigen (nach RDM-Vorbild).
        if VehicleDeliveryShopInfo ~= nil then
            VehicleDeliveryShopInfo.install()
        end
    else
        if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Dedizierter Server erkannt -- GUI uebersprungen.") end
    end

    -- MP: Ein Client (nicht der Server) fordert beim Beitritt die aktuelle
    -- Auftragsliste vom Server an. Im Singleplayer/als Host ist g_server gesetzt
    -- und es passiert nichts (die Liste ist ohnehin lokal vorhanden).
    if g_client ~= nil and g_server == nil and VehicleDeliverySyncRequestEvent ~= nil then
        VehicleDeliverySyncRequestEvent.sendToServer()
        if VehicleDelivery.DEBUG then Logging.info("VehicleDelivery: Auftragsliste beim Server angefordert (Client-Beitritt).") end
    end
end

function VehicleDelivery:deleteMap()
end


VehicleDelivery.init()

if addModEventListener ~= nil then
    addModEventListener(VehicleDelivery)
end
