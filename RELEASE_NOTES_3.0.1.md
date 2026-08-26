# AppDock 3.0.1

AppDock 3.0.1 ist ein gezielter Stabilitätsfix für zwei 3.0.0-Interaktionspfade.

| Korrektur | Verhalten in 3.0.1 |
|---|---|
| DApp-Berechtigungen | Die App-Kontrollansicht verwendet keine lokale `_`-Schleifenvariable mehr, die die Übersetzungsfunktion innerhalb des Dialogaufbaus überschreiben kann. Der Berechtigungsdialog lässt sich damit wieder zuverlässig öffnen. |
| Schlafmodus und Lockscreen | Nach einem echten KOReader-Suspend wird ein aktivierter AppDock-only Lockscreen beim Aufwachen angezeigt. Das normale Schließen oder Verlassen einer DApp kehrt hingegen ohne erneute Sperre zum Homescreen zurück. |

Die Korrekturen sind mit erweiterten Lua-5.1-Core- und DApp-Regressionen getestet. Die Schutzgrenze bleibt unverändert: Der Lockscreen schützt ausschließlich den AppDock-Einstieg, nicht das Gerät oder andere KOReader-Bereiche.
