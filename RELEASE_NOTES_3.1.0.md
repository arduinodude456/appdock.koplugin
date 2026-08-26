# AppDock 3.1.0

AppDock 3.1.0 ergänzt den Kern um die sichere lokale Infrastruktur für **WidgetGenerator 1.0.0**.

## WidgetGenerator

WidgetGenerator ist eine separat aus dem AppStore installierbare No-Code-DApp. Nutzer können eigene Homescreen-Widgets erstellen und ihnen einen Titel, begrenzten Freitext sowie die optionalen lokalen Systeminfos **Uhrzeit**, **Datum** und – soweit der Reader sie bereitstellt – **Akkustand** geben. Erstellte Widgets stehen wie andere Store-Widgets in **Manage apps & widgets** zur Anordnung und Sichtbarkeitssteuerung bereit. Sie können später in WidgetGenerator bearbeitet, ausgeblendet oder gelöscht werden.

## Datenschutz und Sicherheitsgrenzen

Die Kernintegration speichert ausschließlich begrenzte deklarative Werte in den lokalen AppDock-Einstellungen. Sie erzeugt oder führt keinen Nutzer-Lua-Code aus, lädt keine Daten aus dem Netz und überträgt keine Widgetdaten. Höchstens 20 eigene Widgets werden gespeichert. Beim Löschen werden Widgetdaten, Sichtbarkeitszustand und gespeicherte Reihenfolge bereinigt.

## Kompatibilität

Generierte Widgets verwenden den vorhandenen Homescreen-Widgetvertrag und werden in denselben regelmäßigen Homescreen-Aktualisierungen dargestellt wie Store-Widgets. Die Anzeige der Akkuinformation hängt von der vom jeweiligen KOReader-Gerät bereitgestellten Akku-Schnittstelle ab.
