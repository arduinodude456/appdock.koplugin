# AppDock 8.2.16 — Stabilitäts-Hotfix für Store-DApps

- Deaktiviert vorübergehend den benutzerdefinierten Transparent-TextBox-Renderer für Store-DApps. `appdock_text` stellt KOReaders natives `TextBoxWidget` bereit; bestehende DApps bleiben API-kompatibel.
- Stellt die Fehler-/Schema-Prüfung beim Wiederherstellen installierter Store-DApps und Store-Widgets wieder her. Damit wird das riskante Verhalten aus 8.2.15 zurückgenommen.
- Der Import von `appdock_text` ist optional; ein fehlendes Modul blockiert nicht mehr die Initialisierung des DApp-Managers.
- Das isolierte DApp-Fehlerfenster zeigt zusätzlich die gekürzte konkrete Fehlermeldung an, falls eine App weiterhin scheitert.

Die DApps behalten ihre expliziten `bgcolor`-Oberflächenwerte. Der Alpha-Masken-Renderer wird erst wieder aktiviert, nachdem er auf echten KOReader-Geräten validiert wurde.
