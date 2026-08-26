# AppDock 3.0.0 „Cappuccino“

AppDock 3.0.0 erweitert den KOReader-internen Homescreen behutsam um lokale Personalisierung, ausdrücklich begrenzte Zugriffskontrolle und einen skalierbaren DApp-Vertrag. Die Version vermeidet Animationen und externe Hintergrunddienste; sie bleibt auf sparsames, nachvollziehbares E-Ink-Verhalten ausgerichtet.

| Bereich | Änderungen |
|---|---|
| Homescreen | Lokales Hintergrundbild, optionale schwarze Betarahmen und die Nachtmodusoption für das Originalbild. |
| Zugriff | AppDock-only Lockscreen per Wischen, PIN oder Muster. PIN und Muster werden nur lokal als Digest abgelegt; dies ersetzt weder Gerätesperre noch Verschlüsselung. |
| Kontrollzentrum | Konfigurierbare Kachelliste sowie Schlafmodus, Energiesparen und Hintergrundbild. Hardwareaktionen werden nur versucht, wenn KOReader die jeweilige Gerätefunktion bereitstellt. |
| AppStore | Lokale Suche über den zuletzt geladenen HTTPS-Katalog, ohne zusätzlichen Katalogabruf. |
| DApps | Berechtigungen für Autostart und Hintergrundlauf; neue `context.ui_scale`, `context.px(...)` und `context.relative(...)` für künftige skalierbare Split-Panes. Bestehende DApps bleiben kompatibel. |
| DockUpdate | Version 1.1.0 kann bei erlaubter Hintergrundberechtigung innerhalb einer aktiven KOReader-/AppDock-Sitzung alle zwei Minuten nur die stabile Release-Metadaten prüfen. Es meldet jeden neu beobachteten höheren Release-Tag höchstens einmal und führt niemals eine automatische Installation aus. |
| DReader | Version 2.1.0 liest lokale `.md`- und `.markdown`-Dateien. Markdown-Links und Bilder bleiben Textbestandteile; DReader lädt dabei keine externen Ressourcen. |

## Aktualisierung und Testhinweis

Die Aktualisierung erfolgt wie zuvor über das Release-Archiv oder nach einer sichtbaren Bestätigung in DockUpdate. Für DReader und DockUpdate ist anschließend im AppStore ein getrenntes Update verfügbar. Die automatisierten Lua-5.1-, Core-, Control-Center-, DApp-, Files-, AppStore-, Wallpaper-, Locksceen-, DReader- und DockUpdate-Regressionen wurden vor dem Paketbau ausgeführt.

> **Hardwarehinweis:** Die Wirkung von Suspend, WLAN-Abschaltung, Frontlight-Abschaltung, Bilddarstellung und Eingabegesten hängt weiterhin von KOReader und dem jeweiligen Reader-Modell ab. Deshalb soll 3.0.0 vor einer breiten Nutzung auf echter Hardware geprüft werden.
