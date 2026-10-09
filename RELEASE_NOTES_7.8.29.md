# AppDock 7.8.29

## GStreamer-Ton bleibt aktiv

Der Audio-/Videosync wartete zuvor auf die exakte Meldung `New clock:`. Manche GStreamer-Builds melden stattdessen zuerst oder ausschließlich `Setting pipeline to PLAYING`; wenn keine der erwarteten Meldungen erkannt wurde, beendete der Acht-Sekunden-Timeout die Audio-Pipeline. Das konnte dazu führen, dass ein Video völlig ohne Ton lief.

AppDock akzeptiert nun beide üblichen Startmeldungen. Wenn ein Gerät gar keine bekannte Meldung in die Logdatei schreibt, startet das Video nach dem Timeout trotzdem, lässt den Audioprozess aber weiterlaufen — ein fehlendes Logsignal schaltet den Ton nicht mehr stumm. Regressionstests decken beide Bereitschaftsmeldungen und den nicht-stummschaltenden Timeout ab.
