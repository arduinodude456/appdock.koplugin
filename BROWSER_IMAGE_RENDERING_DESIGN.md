# AppDock Webbrowser – Bilddarstellung

## Ziel

Der JavaScript-freie AppDock-Webbrowser zeigt in servergerenderten HTML-Seiten externe Bilder an, ohne MuPDF oder KOReader direkte Netzwerk- oder Dateipfade aus dem Webdokument zu übergeben. Das Rendering bleibt auf den lokalen Pane begrenzt und kann auf monochromen E-Ink-Geräten durch MuPDFs bestehende Bildausgabe dargestellt werden.

## Lokaler Ressourcenvertrag

| Schritt | Begrenzung |
|---|---|
| HTML abrufen | Wie bisher ausschließlich HTTP(S), maximal 2 MiB HTML und begrenzte Redirects. |
| Bildquellen erkennen | Nur `img`-Tags mit `src`; relative und protokollrelative Quellen werden gegen die Seiten-URL aufgelöst. |
| Bildquellen ablehnen | `data:`, `javascript:`, lokale Pfade, SVG und nicht unterstützte oder nicht als `image/*` deklarierte Antworten werden nie an MuPDF weitergereicht. |
| Bildabruf | Maximal acht Bilder, 1,5 MiB pro Bild und 5 MiB pro Seite; derselbe Timeout- und Redirectschutz wie beim HTML-Abruf. |
| Lokaler Cache | Bildbytes werden ausschließlich unter `data/cache/appdock-browser-images` mit generierten Dateinamen gespeichert. HTML verweist nur noch auf diese lokalen Namen. |
| MuPDF-Rendering | `ScrollHtmlWidget` erhält den Cache als `html_resource_directory`; CSS begrenzt Bilder auf die lesbare Pane-Breite. |
| Fehlerfall | Ein Bild wird durch seinen sicheren Alt-Text oder „Image unavailable“ ersetzt. Die Textseite bleibt lesbar. |
| Lebenszyklus | Beim Seitenwechsel, Home und Schließen des Browser-DApps werden die zu dieser Sitzung gehörenden Cachedateien entfernt. |

## Grenzen

Es gibt weiterhin kein JavaScript, keine Formulare, keine eingebetteten Medien, keine SVG-Ausführung und keine fremden lokalen Dateipfade. Die Funktion zeigt statische unterstützte Rasterbilder; sie ist kein vollständiger Webbrowser oder ein allgemeiner Downloadmanager.
