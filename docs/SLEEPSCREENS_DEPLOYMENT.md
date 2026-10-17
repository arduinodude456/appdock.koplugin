# Sleep-Screens-Backend bereitstellen

> **Deployment-Status:** Der Zustand der Supabase-Datenbank und der Edge Functions
> ist nicht aus dem Repository allein ableitbar. Ein erreichbarer öffentlicher
> Katalog bestätigt nicht, dass die private Publish-RPC korrekt bereitgestellt ist.
> Lokale Sleep-Screen-Entwürfe funktionieren unabhängig vom Backend.

## Voraussetzungen

- Supabase CLI, bei dem **gleichen Projekt** angemeldet, in dem `tbs-account` und
  dessen Tabellen laufen.
- Die Account-Migration `supabase/migrations/20261017_tbs_account.sql` ist bereits
  angewandt; insbesondere müssen `public.tbs_accounts` und `public.tbs_devices`
  vorhanden sein.
- Zum Deploy ist ein Projektadministrator nötig. Der **Service-Role-Key wird weder
  in den Reader noch in dieses Repository geschrieben**; gehostete Supabase Edge
  Functions erhalten ihn als `SUPABASE_SERVICE_ROLE_KEY`.

## Bereitstellung

1. Projekt verknüpfen und zuerst die Account-Grundlage (falls noch nicht geschehen)
   anwenden:

   ```sh
   supabase login
   supabase link --project-ref <PROJECT_REF>
   supabase db push
   # Alternativ im SQL Editor die Migrationen in dieser Reihenfolge ausführen:
   # 20261017_tbs_account.sql → 20261017_sleepscreens.sql
   # → 20261017163000_fix_sleepscreen_publish_ambiguity.sql.
   ```

   Bei manuellem SQL-Editor-Einsatz ist die Reihenfolge verbindlich:
   `20261017_tbs_account.sql` → `20261017_sleepscreens.sql` →
   `20261017163000_fix_sleepscreen_publish_ambiguity.sql`.

2. Tests lokal ausführen. Deno wird für die Function-Tests benötigt; der
   Repository-Workflow installiert es automatisch:

   ```sh
   bash scripts/test_sleepscreens.sh
   # oder gezielt:
   deno check supabase/functions/tbs-sleepscreens/index.ts
   deno test supabase/functions/tbs-sleepscreens/
   ```

3. Edge Function bereitstellen. `--no-verify-jwt` ist absichtlich gesetzt: Die
   öffentliche Liste und der Download sind ohne Supabase-Auth erreichbar. **Private
   Schreibaktionen führen zusätzlich ihre TBS-Geräteauthentisierung durch.**

   ```sh
   supabase functions deploy tbs-sleepscreens --no-verify-jwt
   ```

4. Mit einem gültigen `tbs-account`-Endpoint testen. Der Reader leitet ausschließlich
   dessen letzten Pfadbestandteil ab:

   ```text
   https://<project>.supabase.co/functions/v1/tbs-account
   → https://<project>.supabase.co/functions/v1/tbs-sleepscreens
   ```

   Beispiel für den öffentlichen Katalog (nur der **Publishable Key** darf im
   Client stehen):

   ```sh
   curl -sS https://<project>.supabase.co/functions/v1/tbs-sleepscreens \
     -X POST \
     -H 'content-type: application/json' \
     -H 'apikey: sb_publishable_…' \
     --data '{"action":"list","offset":0,"limit":12,"query":""}'
   ```

   Veröffentlichung und Zurückziehen brauchen zusätzlich die drei Header
   `x-tbs-account-id`, `x-tbs-device-id` und `x-tbs-device-secret`. Diese Werte
   gehören **nie** in JSON, URLs, Storage-Links, Logs oder Fehlerdialoge.

## Sicherheitsmodell

| Bereich | Schutz |
|---|---|
| Zugriffspfad | Der Client kennt nur Publishable Key und eine opaque Geräte-ID/-Secret-Kombination. Der Service-Role-Key bleibt in der Edge Function. |
| Authentisierung | `publish` und `unpublish` hashen das Header-Secret (SHA-256) und vergleichen es mit dem aktiven Eintrag aus `tbs_devices`. Der Creator stammt anschließend ausschließlich aus `tbs_accounts`, nie aus Paketdaten. |
| Öffentliche Daten | Nur `list` und veröffentlichte `get`-Pakete sind öffentlich. Metadatenlisten enthalten keine Base64-Binärdaten. Nicht veröffentlichte Presets liefern keinen Download. |
| Storage | `appdock-sleepscreens` ist privat (`public=false`). Restriktive RLS verhindert direkten anon/authenticated-Zugriff. Nur die Function liest/schreibt über Service Role. Es werden keine signierten Asset-URLs an Reader ausgegeben. |
| Paketprüfung | Nur deklaratives Format v1 wird normalisiert: maximal 32 Elemente/12 Assets, bekannte Felder, keine Kontrollschlüssel, URLs oder lokalen Pfade; Base64, Größen, Asset-Verweise und PNG/JPEG/WebP/TTF/OTF-Signaturen werden geprüft. Grenzen: 2 MiB je Bild, 1 MiB je Schrift, 6 MiB Assets, 9 MiB Paket/Request. |
| Parallelität | Assets landen vor der Metadaten-Änderung unter einem neuen UUID-Versuchspräfix. Die SQL-RPC sperrt pro Creator und Preset und führt erwartete Revisionen atomar als CAS aus. Verlierer können keine aktuelle Revision überschreiben; verwaiste Versuche werden best-effort entfernt. |
| Missbrauchsgrenzen | Die Datenbank begrenzt auf 50 Presets pro Creator und höchstens 12 Publish/Unpublish-Schreibvorgänge pro Creator und 60 Sekunden. Fehlerantworten geben keine Datenbank- oder Storage-Details preis. |
| Zurückziehen | `unpublish` markiert soft und bewahrt Assets. Bereits lokal installierte Offline-Pakete bleiben funktionsfähig, öffentliche Liste/Download sind danach gesperrt. |

## Betriebshinweise

- Die Function benötigt keine zusätzlichen manuell gesetzten Secrets im gehosteten
  Supabase-Fall, solange `SUPABASE_URL` und `SUPABASE_SERVICE_ROLE_KEY` verfügbar
  sind. Für `supabase functions serve` sind diese nur in einer **lokalen,
  nicht eingecheckten** Umgebung bereitzustellen.
- Eine spätere Garbage-Collection kann unreferenzierte, alte Storage-Präfixe nach
  einer angemessenen Aufbewahrungsfrist serverseitig löschen. Sie darf weder
  aktuelle Präfixe noch soft zurückgezogene Revisionen entfernen, solange deren
  Offline-Erhaltungsversprechen gilt.
- Nach einem Deployment sollten erfolgreiche und abgewiesene CAS-Versuche,
  Rate-Limits und Storage-Fehler als aggregierte Betriebsmetriken beobachtet
  werden, ohne Geräte-Secrets, Base64-Inhalte oder private Header zu protokollieren.
