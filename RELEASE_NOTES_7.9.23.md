# AppDock 7.9.23

## Draw: getrennte Stylus-Striche und Druckfallback

Ein Stylus-Strich wird jetzt beim KOReader-`pan_release` zuverlässig beendet. Wenn der Stift abgesetzt und an einer anderen Stelle wieder aufgesetzt wird, beginnt dadurch ein neuer Strich; getrennte Kontakte werden nicht mehr verbunden.

Die Druckerkennung übernimmt zusätzlich den echten Kobo-Rohsensorwert aus KOReaders Event-Adjust-Hook – analog zu Quicky – wenn der geparste Stylus-Slot keinen Druckwert liefert. Werte von `0…4095` werden für die Draw-Pinselstärke normalisiert; bereits normalisierte Werte bleiben unverändert.

## Tests

Die Regressionstests prüfen den Rohdruckfallback, Radierer/Marker, den Stylus-Callback-Lifecycle und das Beenden sowie erneute Beginnen getrennter Stylus-Kontakte. Draw-Tests, LuaJIT-Syntaxprüfung und `git diff --check` sind sauber.
