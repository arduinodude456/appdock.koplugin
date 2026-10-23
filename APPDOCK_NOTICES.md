# Live-Mitteilungen für AppDock

AppDock lädt beim Start und danach alle drei Minuten die Datei `appdock_notice.json` aus dem `main`-Branch dieses Repositories über HTTPS. Wird eine neue `id` veröffentlicht und `enabled` auf `true` gesetzt, erscheint die Meldung als Update-ähnliches Popup und zusätzlich in der lokalen AppDock-Benachrichtigungs-Inbox.

Für eine technische Störung genügt es, die Datei zu ändern und zu pushen:

```json
{
  "id": "maintenance-2026-10-23-01",
  "enabled": true,
  "priority": "high",
  "title": "Technische Störung",
  "message": "Der YouTube-Shorts-Feed kann aktuell verzögert laden.",
  "details": "Wir arbeiten an der Behebung. Bereits geladene Videos können weiterhin abgespielt werden.",
  "source": "AppDock Status",
  "expires_at": 0
}
```

Wichtig ist eine neue, eindeutige `id` für jede neue Meldung. `expires_at` ist ein optionaler Unix-Zeitstempel; `0` bedeutet kein Ablaufdatum. Wenn eine Meldung deaktiviert werden soll, setze `enabled` auf `false`. Die Meldung wird nicht erneut angezeigt, solange ihre ID bereits lokal als gesehen gespeichert ist. Für eine Korrektur mit erneuter Anzeige veröffentlichst du deshalb eine neue ID.

Die Nutzdaten sind auf eine begrenzte Größe beschränkt. Es werden nur HTTPS und JSON akzeptiert; Netzwerkfehler bleiben für Nutzer unsichtbar und blockieren AppDock nicht.
