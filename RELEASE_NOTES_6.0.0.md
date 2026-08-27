# AppDock 6.0.0 „Continuity“

AppDock 6.0.0 stärkt die lokale DApp-Plattform und ihre tägliche Bedienung auf E-Ink-Geräten. Die Version führt eine deutlichere Android-/Material-orientierte Standardsprache ein, ohne die lokale Ausrichtung, den bestehenden Theme-/Designvertrag oder die reduzierte Bedienung von Simple Mode aufzugeben.

## Neue Funktionen

| Bereich | Änderung |
|---|---|
| Standardoberfläche | Homescreen, Kontrollzentrum, DApp-Appbar, Open Apps und die untere Navigation erhalten im normalen Modus klarere, abgerundete Material-orientierte Oberflächen und erkennbare aktive Akzentzustände. Die vorhandenen AppDock-Themen, Store-Designs und Graustufen-Fallbacks bleiben die Farbquelle. |
| Geschützter Simple Mode | Simple Mode bleibt ein unabhängiger reduzierter Pfad. Sein 4×3-Appgitter, die bestehende einfache Kontrollzentrale, die fokussierte Appauswahl sowie seine Abstände und Grundflächen erhalten keine neuen Statuskarten, Dock-Pills oder dekorativen Standardflächen. |
| Lokaler Arbeitsbereich | Unter **Settings → Other → Local workspace** kann die Wiederherstellung bewusst aktiviert werden. Sie ist standardmäßig deaktiviert, speichert maximal vier DApps und stellt nur DApps wieder her, die diesen Vertrag selbst erlauben. Analog Clock, Help und Settings sind zunächst freigegeben. |
| Registrierte Dateihandler | Store-DApps können `file_extensions` und einen `file_handler_title` deklarieren. Files öffnet eindeutige lokale Handler direkt und bietet bei mehreren geeigneten Apps eine sichtbare Auswahl. Die bisherigen Zuordnungen für NightLua, DReader und MarkUP bleiben erhalten. |
| Zugänglichkeit | **Settings → Display → Text & contrast** bietet 90 %, 100 %, 115 % und 130 % Textgröße sowie einen kontrastverstärkten lokalen Theme-Pfad für AppDock-eigene Normaloberflächen. |
| Integritätsstatus | **Settings → Storage** enthält eine schreibgeschützte Übersicht für installierte Store-Dateien, geöffnete DApps und Arbeitsbereichsmetadaten. Die Ansicht löscht, repariert oder verändert keine Dateien selbstständig. |

## Sicherheits- und Datenschutzgrenzen

Arbeitsbereichsdaten enthalten nur DApp-IDs und kleine, validierte Zustandswerte. Dokumentinhalte, Passwörter, Tokens, Geheimnisse, Schlüssel, Widget-Bäume und Funktionen werden nicht gespeichert. Browser, Files, AppStore und gehostete Plugin-Sitzungen werden nicht automatisch wiederhergestellt. Eine DApp muss sowohl `workspace_restore = true` setzen als auch optional `serializeState` beziehungsweise `restoreState` bereitstellen, bevor eigener lokaler Zustand verwendet wird.

Dateihandler sind auf kurze alphanumerische Endungen begrenzt und werden nur für bereits installierte DApps registriert. Der Filebrowser verändert eine Datei nicht; der konkrete DApp-Öffnungsvorgang bleibt eine sichtbare Nutzeraktion.

## Migration und Kompatibilität

Das Einstellungsmodell wird auf **Layout-Version 19** angehoben. Bestehende DApps und Widgets benötigen keine Änderungen: `buildPane`, `openFile`, Widgets, Themes, Designs, Homescreen-Layouts und Simple-Mode-Einstellungen bleiben gültig. Neue DApp-Verträge sind vollständig optional. Beim ersten Start bleibt die Arbeitsbereichswiederherstellung ausgeschaltet.

## Qualitätssicherung

Die Releasekandidaten werden mit Lua 5.1 syntaxgeprüft. Die Core-Regression umfasst die DApp-Registry, Store-Updates, Dateiübergaben, Handlernormalisierung, DApp-Schließschutz, Arbeitsbereichsspeicherung und -wiederherstellung, Splitscreen, normale Material-Oberflächen, die Simple-Mode-Grenze, Zugänglichkeit, Integritätsstatus sowie Browser- und E-Ink-Refreshpfade.

> **Hardware-Hinweis:** Die logischen Tests sichern keine konkrete Display-Geometrie jedes E-Readers ab. Vor dem endgültigen Einsatz sollten insbesondere Homescreen, Kontrollzentrum, Open Apps, DApp-Host und Simple Mode auf dem jeweiligen Gerät getestet werden. Bitte auch prüfen, dass der Simple Mode nach dem Update genau so reduziert bleibt wie zuvor.

## Aktualisierung

1. AppDock vollständig schließen und eine Kopie des bisherigen `appdock.koplugin`-Ordners behalten.
2. Das Release-Archiv entpacken und ausschließlich den darin enthaltenen Ordner `appdock.koplugin` in den KOReader-Pluginordner kopieren.
3. KOReader vollständig neu starten.
4. In **Settings → Other → Local workspace** nur dann die Wiederherstellung aktivieren, wenn die erneute Öffnung der wenigen lokal freigegebenen DApps erwünscht ist.
