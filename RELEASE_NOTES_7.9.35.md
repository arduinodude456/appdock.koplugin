# AppDock 7.9.35

- DApp-Background-Checks laufen jetzt in separaten KOReader-Subprozessen und blockieren die Benutzeroberfläche nicht mehr durch Netzwerk-Timeouts.
- Ergebnisse werden sicher im UI-Thread übernommen; laufende Jobs werden beim Schließen des Plugins beendet.
- DChat 1.8.8 nutzt diesen asynchronen Background-Check.
