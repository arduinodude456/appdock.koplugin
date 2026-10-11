# AppDock 7.9.47

- **Datenbank wieder aktiv:** Die deutsche und englische Vorschlagsdatenbank wird jetzt sicher direkt aus dem AppDock-Plugin-Ordner geladen.
- Funktioniert auch dann, wenn KOReader den Plugin-Ordner nicht in `package.path` einträgt.
- Der Boot-Schutz bleibt erhalten: Nur wenn die Datei wirklich fehlt oder unlesbar ist, wird die kleine Fallback-Liste verwendet.
- Die mitgelieferte `appdock_suggestions.db` bleibt vollständig Bestandteil des Releases.
