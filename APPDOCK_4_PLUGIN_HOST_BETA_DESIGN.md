# AppDock 4.0.0 „Bueno“ – Plugin-in-DApp-Beta

## Ziel und klarer Umfang

Die Beta erweitert ausschließlich den Start von **bereits aktivierten, normalen KOReader-Plugins über AppDock**. Wenn die neue Einstellung aktiv ist, öffnet eine Plugin-Kachel zunächst eine AppDock-verwaltete Plugin-Sitzung mit eigener Kopfzeile, Aktionseinträgen und einem Eintrag in **Open apps**. Ohne aktivierte Beta bleibt der bisherige direkte Pluginstart unverändert.

> Diese erste Beta virtualisiert keine beliebige fremde KOReader-Oberfläche in ein Pane. Sie stellt einen lokalen AppDock-Host für die veröffentlichte `addToMainMenu(menu_items)`-Schnittstelle bereit und behält die Sitzung unter einer anschließend vom Plugin geöffneten KOReader-Ansicht logisch geöffnet.

| Bereich | Vertrag |
|---|---|
| Aktivierung | Eine persistente Einstellung unter **Settings → Display → Beta features**. Der Standardwert ist `false`. |
| Sitzungs-ID | `plugin_host:<Pluginname>`; getrennt von DApps und den Homescreen-Kachel-IDs `plugin:<Pluginname>`. |
| Oberfläche | AppDock-Pane mit Pluginname, Beta-Hinweis und den vom Plugin veröffentlichten Hauptmenüaktionen. |
| Pluginaufruf | Die bestehende Callback-Funktion wird geschützt und **ohne neue Argumente** aufgerufen. Ein kooperierendes Plugin kann den Host-Kontext über `buildAppDockPane(context)` oder einmalig über `onAppDockHostOpened(context)` erhalten. |
| Benachrichtigungen | `context.notify({ title, message, priority, source })` leitet ausschließlich an `AppDock:notify` weiter. Erfolgs- oder Fehlermeldungen des Hosts verwenden daher die lokale Inbox und den AppDock-Toast. |
| Splitscreen | Plugin-Host-Sitzungen sind technisch nicht splittbar: Sie erscheinen nicht als Auswahlkandidaten, ihr Long-Press bietet keine Splitscreen-Aktion, und `startSplit` verweigert sie zusätzlich defensiv. |
| Grenzen | AppDock fängt keine globalen oder fremden Plugin-Pop-ups ab und behauptet keine vollständige Einbettung beliebiger Plugin-UIs. Nicht angepasste Plugins können weiterhin eigene KOReader-Ansichten oder Dialoge öffnen. |

## Sicherheits- und E-Ink-Regeln

Die Beta führt keine Shell-Befehle, keine neuen Netzwerkzugriffe und keine globale Monkey-Patch-Interzeption von KOReader-Fenstern ein. Nur Plugins, die bereits aktiviert sind und die normale Hauptmenü-Schnittstelle bereitstellen, erscheinen als Plugin-Hosts. Die lokale Benachrichtigungsbrücke begrenzt Titel, Inhalt und Speicherdauer weiterhin über die bestehende AppDock-Inbox.

Die Aktionliste besteht aus großen, statischen E-Ink-tauglichen Zeilen. Aktionen werden ausschließlich durch eine explizite Berührung ausgelöst; der Host startet keine Plugin-Hintergrundaufgaben und übernimmt keine Berechtigungen von DApps.
