# AppDock 7.9.22

## Draw: KOReader-Stylus-Callback korrigiert

Die Stylus-Erkennung in Draw verwendet jetzt KOReaders öffentlichen `Device.input:registerStylusCallback(input, slot)`-Pfad – denselben Callback, den Quicky und die funktionierende Draw-DApp verwenden. Der vorherige Rohereignis-Hook wurde entfernt, da er auf realen KOReader-Versionen nicht zuverlässig registriert wurde.

Stiftkoordinaten, Druckwerte sowie die vom KOReader-Input gesetzten Zustände für physischen Radierer und Marker werden an Draw weitergereicht. Der Callback wird beim Öffnen der Draw-Pane registriert und beim Verlassen wieder entfernt.

## Tests

Die Stylus-Regressionstests simulieren den echten KOReader-Callback mit Druck, Radierer, Marker, eraser tool und Lifecycle. Draw-Tests, LuaJIT-Syntaxprüfung und `git diff --check` sind sauber.
