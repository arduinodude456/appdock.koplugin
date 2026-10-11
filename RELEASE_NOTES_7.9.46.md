# AppDock 7.9.46

- **Boot-Crash behoben:** Die Vorschlagsdatenbank wird nicht mehr beim Laden des Keyboard-Moduls importiert.
- Die Datenbank wird erst beim tatsächlichen Erzeugen einer Tastatur lazy geladen.
- Falls die Datenbank oder ihr Modul fehlt bzw. fehlerhaft ist, startet die Tastatur mit einer kleinen eingebetteten Fallback-Liste.
- Caps Lock und die größeren Tasten aus 7.9.45 bleiben erhalten.
