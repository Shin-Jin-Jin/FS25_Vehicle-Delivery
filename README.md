# FS25 Vehicle Delivery

Eine Scriptmod für den **Landwirtschafts-Simulator 25**: Neu gekaufte Fahrzeuge
stehen nicht mehr sofort auf dem Hof, sondern werden nach einer realistischen
Lieferzeit zugestellt – abhängig von Herkunftsregion des Herstellers,
Ausstattung und Entfernung zum Hof.

## Features

- **Lieferzeit statt sofortiger Verfügbarkeit** beim Fahrzeugkauf
- **Herkunfts- und Regionssystem**: über 240 Hersteller sind sechs Weltregionen
  (EU, NA, SA, AS, AF, OC) zugeordnet; die Lieferzeit ergibt sich aus der Route
  zwischen Herstellerregion und Hofregion
- **Konfigurationsabhängig**: Sonderausstattung verlängert die Lieferzeit
- **Spielkalender-gerecht**: Lieferzeiten sind auf einen Monat mit 28 Tagen
  bezogen und werden auf die Einstellung „Tage pro Monat" umgerechnet
  (bei 28 Tagen/Monat ist 1 Liefertag = 1 Spieltag, bei 1 Tag/Monat dauern
  12 Tage Lieferzeit rund 10 Spielstunden)
- **Anzahlungssystem** (optional): 20 % bei der Bestellung, Rest bei Lieferung –
  zum Bestellen muss nur die Anzahlung auf dem Konto sein
- **Zollgebühren** (optional): richtungsabhängig je nach Herkunft und Ziel
- **Stornierung** mit gestaffeltem Schadenersatz je nach Fortschritt
- **Zufällige Lieferverzögerungen** (optional)
- **Auftragsübersicht** im Menü mit Live-Status (Bestellung aufgegeben →
  In Produktion → Unterwegs → Kurz vor Lieferung)
- **Kennzeichen-Übertragung** auf das gelieferte Fahrzeug
- **Sofort verfügbar** bleiben: Paletten, BigBags, Gebraucht- und Mietfahrzeuge
- **Mehrspieler-Unterstützung** mit Server-Client-Synchronisation
- Übersetzungen in **Deutsch, Englisch, Französisch**

## Einstellungen

In den Spieleinstellungen lassen sich einstellen:

- Hofregion (bei bekannten Karten automatisch)
- Anzahlung an/aus
- Zollgebühren an/aus
- Lieferverzögerungen an/aus

## Installation

Den Ordnerinhalt als ZIP packen (mit `modDesc.xml` auf oberster Ebene) und in
den FS25-Mod-Ordner legen.

## Autor

Shin_Jin_Jin
