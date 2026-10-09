# AppDock 7.8.24

## YouTube-Fortschritt aktualisiert sich live

Die Video-Fortschrittsleiste übernimmt während des Jobs jetzt die jeweils neu gemeldeten Prozentwerte. Beim erstmaligen Einrichten der Werkzeuge bewegt sich eine Ladeanzeige, solange die Installation keinen verlässlichen Gesamtfortschritt liefern kann. Fortschrittsänderungen verwenden E-Ink-schonende Teilaktualisierungen.

## Video-Konvertierung beschleunigt

Die Konvertierung war zuvor künstlich auf höchstens zwei Frames pro Sekunde begrenzt: Pro UI-Tick wurden zwei Frames gelesen, danach wartete der Job eine volle Sekunde. Beide Dither-Pfade – FFmpeg `monow` und AppDocks Bayer-Konverter – lesen jetzt bis zu sechs Frames pro kurzem Tick, begrenzt durch ein kleines CPU-Zeitbudget. So kann FFmpeg kontinuierlich ausgeben, statt durch den UI-Poller ausgebremst zu werden; die Oberfläche bleibt dabei responsiv. Die tatsächliche Geschwindigkeit hängt weiterhin vom Reader, Video-Codec und der gewählten Auflösung/Bildrate ab.

## Verifikation

Die vollständige lokale Regressionstestsuite lief erfolgreich. Der YouTube-Integrationstest prüft beide Dither-Pfade an einer erzeugten Videodatei, den kurzen Tick-Takt, die gebündelte Frame-Verarbeitung und die Fortschrittsaktualisierung. Die optionale externe BWR-Video-Fixture war in der lokalen Umgebung nicht vorhanden.
