# AppDock 7.8.18

## YouTube-Setup: Live-Shellausgabe

- Die Setup-Ansicht zeigt jetzt fortlaufend die letzten fünf Zeilen des Hintergrund-Logs, aktualisiert im bestehenden Zwei-Sekunden-Takt.
- `curl`/`wget`-Downloadfortschritt wird sichtbar; Statuswechsel wie Prüfsummenprüfung, Entpacken und Installation erscheinen zusätzlich im Log.
- Während `yt-dlp --version` läuft, zeigt die App den gestarteten Prozess und regelmäßige Wartezeit-Hinweise. Die Ausgabe des Versionsbefehls wird nicht länger verworfen.
- Fehlerausgaben des FFmpeg-Starttests werden ebenfalls protokolliert.
- Steuerzeichen und ANSI-Farbcodes werden für die E-Ink-Ansicht bereinigt; die Vorschau bleibt auf wenige Zeilen begrenzt.

Damit lässt sich direkt in der YouTube-App unterscheiden, ob der Download, die Integritätsprüfung, das Entpacken oder der Binärstart gerade aktiv ist bzw. fehlschlägt.
