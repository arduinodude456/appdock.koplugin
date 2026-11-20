# DockAI: Backend und Erstkonfiguration

AppDock 9.12.0 verwendet das Edge-Endpoint `dockai` im vorhandenen Supabase-Projekt `dchat`. Der Datenbankteil ist in `supabase/migrations/20261120_dockai.sql` beschrieben; das Edge-Function-Quellfile liegt unter `supabase/functions/dockai/index.ts`. Auf dem bereits eingerichteten dchat-Projekt wurden Migration und Funktion bereitgestellt.

Die Tabellen für API-Keys, Admin-Prüfwert, Geräteverbrauch und Anfragen haben RLS aktiviert und verweigern direkte Zugriffe von `anon` und `authenticated`. Nur die Edge Function nutzt die Service-Role. Die Funktion gibt niemals API-Keys zurück. AppDock bietet ausschließlich das Hinzufügen an; Anzeigen, Entfernen und Dateiimport sind aus der Oberfläche entfernt. 401/403-Provider-Keys werden serverseitig deaktiviert.

Nutzer müssen in AppDock bei einem TBS-Konto angemeldet sein, weil dessen zufällige Geräte-ID und Gerätegeheimnis die Identität für die Limits bilden. Pro Gerät gelten 25 erfolgreiche Antworten pro UTC-Tag sowie 100 pro UTC-Woche (Montag bis Montag); fehlgeschlagene Provider-Aufrufe geben die Reservierung frei. Alle Nutzer können dieselben serverseitig hinterlegten Provider-Keys verwenden.

Für ein neues Supabase-Projekt zuerst die Migration anwenden, anschließend das Passwort initialisieren: `python3 scripts/dockai_admin_hash.py` fragt es verdeckt ab und erzeugt SQL mit einer PBKDF2-Prüfsumme (das Passwort selbst wird nicht ausgegeben). Dieses SQL im Supabase SQL Editor ausführen und danach die Edge Function deployen. Keine Service-Role- oder Groq-Schlüssel in AppDock eintragen.
