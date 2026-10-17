# TBS-Konto mit Supabase einrichten – Schritt für Schritt

Diese Anleitung ist absichtlich ganz einfach gehalten. Du brauchst **keinen neuen Supabase-Server**: AppDock verwendet dasselbe Supabase-Projekt wie DChat.

## Was wird eingerichtet?

Es kommen drei kleine Tabellen in dein bestehendes Projekt. Darin liegen TBS-Konten, Reader-Geräte und ein kleiner AppDock-Einstellungsstand. Bücher, DChat-Nachrichten, Medien, App-Dateien und der geheime Supabase-Service-Schlüssel werden **nicht** in diesen Tabellen gespeichert. Direkter Tabellenzugriff ist gesperrt; AppDock spricht mit einer Supabase-Funktion, die den Gerätezugriff prüft.

## Teil 1: Tabellen in Supabase anlegen

1. Öffne [supabase.com/dashboard](https://supabase.com/dashboard) und melde dich an.
2. Wähle das Projekt aus, das DChat benutzt. Die Projektadresse für DChat lautet `qndwbriqomqqaqhkasbh.supabase.co`.
3. Links im Menü klicke auf **SQL Editor**.
4. Klicke auf **New query** (neue Abfrage).
5. Öffne die Datei [`supabase/migrations/20261017_tbs_account.sql`](supabase/migrations/20261017_tbs_account.sql) aus diesem Repository. Kopiere den gesamten Inhalt und füge ihn in das große SQL-Feld im Supabase-Dashboard ein.
6. Klicke auf **Run**. Warte auf die Erfolgsmeldung. Damit sind die Tabellen angelegt.

Wenn Supabase meldet, dass die Erweiterung `pgcrypto` bereits existiert, ist das in Ordnung. Die Abfrage kann erneut ausgeführt werden; sie ist so geschrieben, dass sie bestehende Tabellen und Richtlinien wiederverwendet.

## Teil 2: Die TBS-Funktion veröffentlichen

Die Tabellen allein reichen nicht. Die kleine Serverfunktion muss ebenfalls in **demselben Projekt** veröffentlicht werden. Am einfachsten geht das vom Computer mit dem AppDock-Repository:

1. Installiere [Node.js LTS](https://nodejs.org/) falls es noch nicht installiert ist.
2. Öffne ein Terminal im Hauptordner des AppDock-Repositories – also dort, wo `README.md` und der Ordner `supabase` liegen.
3. Melde die Supabase CLI an:

   ```sh
   npx supabase login
   ```

   Der Befehl zeigt dir, wie du ein Supabase-Zugriffstoken erzeugst. Folge den Anweisungen im Terminal und im Browser. **Das Token nicht in Chat, GitHub oder eine Datei kopieren, die du veröffentlichst.**

4. Verknüpfe das lokale Repository mit dem DChat-Projekt:

   ```sh
   npx supabase link --project-ref qndwbriqomqqaqhkasbh
   ```

   Wenn Supabase nach einem Datenbankpasswort fragt, gib das Datenbankpasswort dieses Projekts direkt im Terminal ein. Das Passwort wird nicht benötigt, um es in AppDock einzutragen.

5. Veröffentliche die Funktion:

   ```sh
   npx supabase functions deploy tbs-account --no-verify-jwt --project-ref qndwbriqomqqaqhkasbh
   ```

   `--no-verify-jwt` ist hier beabsichtigt: Die Funktion verwendet statt eines Supabase-Login-Tokens die zufälligen, gerätegebundenen TBS-Zugangsdaten und prüft diese selbst.

Supabase stellt der gehosteten Funktion `SUPABASE_URL` und `SUPABASE_SERVICE_ROLE_KEY` automatisch bereit. **Trage den Service-Role-Key nirgends in AppDock, Lua-Dateien oder GitHub ein.**

## Teil 3: Prüfen

1. Öffne nach erfolgreichem Deployment im Supabase-Dashboard **Edge Functions**.
2. Dort sollte `tbs-account` stehen.
3. In AppDock öffne **Settings → Other → TBS Account & cloud sync** (die Bezeichnungen können je nach Sprache leicht abweichen).
4. Erstelle ein Testkonto. Schreibe sowohl die angezeigte **Account ID** als auch den **Recovery-Code** auf. Der Recovery-Code wird aus Sicherheitsgründen nur einmal angezeigt.
5. Bei Problemen schau unter **Edge Functions → tbs-account → Logs** nach der Fehlermeldung.

## Wichtig

- Diese Einrichtung **ändert nichts an DChat-DMs** und löscht keine DChat-Tabellen.
- Die SQL-Datei erstellt nur Tabellen mit dem Präfix `tbs_`.
- Beim Einrichten eines neuen Readers brauchst du Account ID und Recovery-Code. Ohne Recovery-Code kann die Migration nicht freigeschaltet werden.
- AppStore-Apps werden nicht automatisch ohne Rückfrage installiert. AppDock merkt sich die Installationsliste; einzelne Installationen bleiben bestätigungspflichtig.
- `npx supabase link` verknüpft nur dein lokales Verzeichnis mit dem Projekt. Die Tabellen änderst du in Teil 1; die Funktion veröffentlichst du in Teil 2.
