# AppDock 9.10.0

## Deutsch
- **Neu: DockAI.** Chat-App im ChatGPT-Look (Begrüßung, Vorschläge, Nachrichtenblasen, Eingabefeld mit Senden-Knopf, Modellwahl, neuer Chat), angetrieben von Groq. Antworten werden als Markdown dargestellt (Listen, fett, Code).
- **Limits:** Jeder Nutzer hat ein Tageslimit (Standard 25) und ein Wochenlimit (Standard 100 Nachrichten). Tag setzt um Mitternacht zurück, Woche am Montag. Nur zugestellte Antworten zählen. Das Limit steht in der App (Leiste mit Balken, Hinweis im Startbild, Meldung bei Erreichen) und unter Einstellungen > DockAI.
- **Admin:** Einstellungen > DockAI > Admin (Passwort). Beliebig viele Groq-API-Keys hinzufügen, entfernen, aus `dockai_keys.txt` importieren, Limits und Modell ändern. Key-Rotation: reihum; 429 = Key pausiert (Retry-After), 401/403 = Key abgeschaltet, dann automatisch der nächste Key.
- **Wichtig:** Ohne eigenen Server liegen Limits, Keys und das Admin-Passwort auf dem Gerät. Das schützt vor Versehen, nicht vor jemandem, der die Dateien des Geräts lesen kann. Für harte Limits pro Nutzer braucht es einen kleinen Proxy-Server vor Groq.
- Außerdem aus 9.9.0: echte Liquid-Glass-Ziffern, Standby beim Laden, Tastatur-Vorschau-Fix.

## English
- **New: DockAI.** A ChatGPT-style chat app (greeting, suggestions, message bubbles, input pill with send button, model picker, new chat) powered by Groq. Replies render Markdown (lists, bold, code).
- **Limits:** Every user has a daily (default 25) and a weekly (default 100 messages) limit. The day resets at midnight, the week on Monday. Only delivered replies count. The limit is shown in the app (strip with bar, note on the start screen, message when reached) and under Settings > DockAI.
- **Admin:** Settings > DockAI > Admin (password). Add any number of Groq API keys, remove them, import them from `dockai_keys.txt`, change limits and model. Key rotation: round robin; 429 = key rests (Retry-After), 401/403 = key switched off, then the next key is tried automatically.
- **Important:** Without a server of its own, limits, keys and the admin password live on the device. That prevents accidents, not someone who can read the device's files. Hard per-user limits need a small proxy server in front of Groq.
- Also from 9.9.0: real Liquid Glass digits, standby while charging, keyboard preview fix.
