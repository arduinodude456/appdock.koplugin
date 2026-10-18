# Sleepscreens: Architektur und Implementierungsvertrag

AppDock erweitert seinen nativen KOReader-AppStore um **Sleepscreens**. Presets sind ausschließlich deklarative JSON-Daten und dürfen weder Lua noch URLs, lokale Pfade oder ausführbare Widgets enthalten. Die bestehenden Apps, Widgets und Designs bleiben unverändert. Ein gemeinsamer Renderer wird für Editor, Store-Vorschau und den tatsächlichen Sleepscreen benutzt.

## Format v1

Ein `definition`-Objekt enthält `schema_version: 1`, `name` (1–80 Zeichen), `description` (max. 500), `background` (`#RRGGBB`), `elements` (max. 32) und `assets` (max. 12). `assets` ist eine Liste von `{id, kind: "image" | "font", extension: "png" | "jpg" | "jpeg" | "webp" | "ttf" | "otf"}`. IDs sind einfache ASCII-Bezeichner (1–64 Zeichen, Buchstaben, Zahlen, `_`, `-`).

Elemente: `{type, x, y, w, h, text, font, font_size, color, background, background_alpha, bold, align, source, widget_id, images, fit}`. `type` ist `text`, `card`, `widget` oder `image`. Position und Größe sind Prozentwerte; x/y >= 0, w/h > 0, x+w <= 100 und y+h <= 100. `background` ist `#RRGGBB`; `background_alpha` ist optional und liegt zwischen `0` (vollständig transparent) und `1` (opak), Standard ist `1`. Ein `widget` kann entweder `source` (`clock`, `date`, `battery`, `device`) oder ein `widget_id` verwenden. `widgets` enthält bis zu 16 codefreie Custom-Widgets mit Basistextext, bis zu 12 Animationsframes und Zeitregeln im Format `HH:MM–HH:MM`. Ein Custom-Widget kann optional Open-Meteo für aktuelle Temperatur und Wetterbeschreibung aktivieren; Breite/Länge sind konfigurierbar, ein API-Schlüssel ist nicht erforderlich. Der Abruf erfolgt manuell im Editor; Messwerte werden lokal mit dem Preset gespeichert und im Sleepscreen offline angezeigt. Renderer und Suspend-Pfad machen keine Netzwerkanfragen. Ortskoordinaten sind Presetdaten; vor öffentlichem Teilen prüfen, ob diese geteilt werden sollen. Als optionale API-Quelle kann ein Widget Open-Meteo (aktuelle Temperatur und Wetterbeschreibung) mit konfigurierbarer Breite/Länge verwenden; der Abruf erfolgt ausdrücklich im Editor. Die begrenzten Messwerte werden zusammen mit dem Preset gecacht und im Sleepscreen offline eingesetzt. Der Renderer und Suspend-Pfad führen keine Netzwerkanfragen aus. Vor dem öffentlichen Teilen prüfen, dass ein Preset keine unerwünschten Ortsinformationen enthält. Fontgröße 8–96 bezieht sich auf eine 600px breite Referenzfläche. `font` ist `cfont`, `infofont`, `smallinfofont` oder `asset:<id>`. Ausrichtung: left/center/right. `fit`: contain/cover. `images`: Liste von Asset-IDs (1–12); bei mehreren Bildern wird pro Schlafzyklus ein Bild ausgewählt. Texte dürfen `{time}`, `{date}`, `{battery}`, `{device}` und `{sleeping}` enthalten; Wetter-Widgets unterstützen zusätzlich `{temperature}` und `{weather}` aus dem letzten lokalen Open-Meteo-Cache (Vorschau mit Beispieldaten). Unbekannte Felder werden verworfen; unzulässige Typen, Referenzen, Größen und Formate werden abgewiesen.

Ein transportables Paket ist `{definition, assets: {"asset-id": "BASE64_BYTES"}}`. Binäre Assets sind begrenzt auf 2 MiB pro Bild und 1 MiB pro Schrift, zusammen 6 MiB. Paket-JSON maximal 9 MiB. Nicht referenzierte/fehlende Assets werden abgewiesen. Lokale absolute Pfade gehören nie in das Paket. Vorschauen enthalten keine echten Geräteinformationen, sondern festgelegte Beispieldaten.

## Globale Speicherung

Supabase im vorhandenen TBS-Projekt. PostgreSQL hält Preset-ID (UUID), serverseitig zugeordnetes Creator-Konto, Name/Beschreibung, validierte Definition, Revision und Veröffentlichungszeit. Ein privater Storage-Bucket `appdock-sleepscreens` speichert immutable revisionsbezogene Assets. Nur die `tbs-sleepscreens` Edge Function darf schreiben oder Pakete lesen; kein direkter anon/authenticated Zugriff auf Tabellen. Liste und Download sind öffentlich, Veröffentlichungen/Änderungen/Zurückziehen verlangen gültige TBS-Geräte-Credentials. Der Creator wird aus `tbs_accounts` bestimmt, niemals aus Clientdaten. Änderungen verwenden eine atomare erwartete Revision, sodass alte Reader keine neuen Versionen überschreiben. Eine bereits installierte Version bleibt beim Zurückziehen offline erhalten. Veröffentlichungen teilen ausschließlich das ausdrücklich bestätigte Preset und dessen ausgewählte Assets, keine Bücher, Pfade, Kontosecrets oder Gerätewerte.

## HTTP-Vertrag

POST `<tbs-account endpoint, mit letztem /tbs-account ersetzt durch /tbs-sleepscreens>` mit `apikey`, und bei privaten Aktionen `x-tbs-account-id`, `x-tbs-device-id`, `x-tbs-device-secret`. Keine Account-Credentials an beliebige Asset-URLs weiterreichen.

- `{action:"list", offset:0, limit:12, query:""}` -> `{entries:[{id,name,description,creator:{account_id,display_name},revision,definition}],has_more:boolean}`. Server sortiert deterministisch. Definition ist eine echte Layout-Vorschau; Medien werden bei Bedarf aus dem Download-Paket lokal angezeigt.
- `{action:"get", id}` -> `{entry:{id,name,description,creator,revision,definition}, package:{definition,assets}}`.
- `{action:"publish", package, id?:UUID, expected_revision?:number}` -> `{entry}`. Ohne ID neue Veröffentlichung; mit ID nur eigener Creator und passende Revision.
- `{action:"unpublish", id, expected_revision}` -> `{ok:true}`. Nur Creator.
- Fehler -> `{error:{message,code?}}`, HTTP 400/401/403/404/409/413/429/503.

## Modulverträge

`appdock_sleepscreen_presets.lua`:

- `normalize(definition)` -> definition oder nil,error
- `defaultPreset()` -> Definition
- `newDraft(name?)` -> `{definition, asset_paths={}}`
- `listLocal(appdock)` -> Liste lokaler Records `{id,definition,asset_paths,remote_id?,revision?,creator?}`
- `saveDraft(appdock,draft,id?)` -> Record oder nil,error; id bezeichnet nur lokale Identität.
- `getActive(appdock)` -> Record oder nil; `activate(appdock,id)` -> true oder nil,error (aktiviert auch sleepscreen_enabled)
- `remove(appdock,id)` -> true oder nil,error; aktives Entfernen setzt Standard zurück.
- `importAsset(draft,path,kind)` -> Asset-ID oder nil,error; kopiert Datei in verwalteten lokalen Draft-Storage.
- `exportPackage(record)` -> Paket oder nil,error
- `installPackage(appdock,package,entry)` -> Record oder nil,error; überprüft alles vor atomarem Commit, existierender Download bleibt bei Fehlern bestehen.

`appdock_sleepscreen_renderer.lua`:

- `build(definition,width,height,options?)` -> KOReader-Widget. options: `{asset_paths,preview=true/false,appdock,cycle=number}`. Alle Kinder clippen an Elementgrenzen; Ressourcen werden beim Schließen freigegeben. Keine Netzwerkzugriffe im Renderer oder im Suspend-Handler.

`appdock_sleepscreen_store.lua`:

- `list(appdock,query,offset)` -> `{entries,has_more}` oder nil,error
- `get(appdock,id)` -> `{entry,package}` oder nil,error
- `publish(appdock,package,id?,expected_revision?)` -> entry oder nil,error
- `unpublish(appdock,id,expected_revision)` -> true oder nil,error

`appdock_sleepscreen_editor.lua`: `show(appdock,context,record?)`. Ohne record neuer Draft. Interaktive native Oberfläche mit stets sichtbarer Live-Vorschau. Elemente hinzufügen/auswählen/editieren/löschen/reihenfolgen; Position/Größe, Text, Schrift, Farben, Bilder und Widgetquellen. Lokales Speichern und Aktivieren ohne Konto. Öffentliches Veröffentlichen verlangt TBS-Konto und eine ausdrückliche Bestätigung des Namens, Creators und der geteilten Assets.

`appdock_sleepscreen_catalog.lua`: `buildPane(instance,context,store_ui)` -> Widget; kann eigene Kategorieoberfläche inklusive Navigation erstellen. Native Store-Karten mit Name, TBS-Creator und gemeinsamer Vorschau; Laden/Suche/Paginierung, Download/Use/Remove, lokale Presets und neuer Editor. Store-Vorschau kann über Öffnen vollständiges Paket laden, damit auch Bild-/Schriftvorschau verfügbar wird. Kein automatisches Veröffentlichen.

## Repository-Struktur

Der aktuelle installierbare Plugin-Code lebt in `appdock.koplugin/`. Die deutlich älteren Root-Kopien bleiben bewusst unangetastet; eine Synchronisierung würde viele unabhängige Änderungen einschließen. Die Erweiterung und ihre Tests verwenden den installierbaren Plugin-Ordner. `main.lua` übergibt seine Instanz an Sleep.show und übernimmt ausschließlich die lokale Sleepscreen-Auswahl. Die Preset-Registry und Medien liegen getrennt im KOReader-Datenverzeichnis und werden nicht in TBS-Einstellungsbackups hochgeladen. `supabase/migrations/` und `supabase/functions/` enthalten das separate Server-Deployment. Das globale Feature funktioniert erst nach Anwendung der Migration und Bereitstellung der Function; die lokale Erstellung und Nutzung funktioniert ohne Backend.
