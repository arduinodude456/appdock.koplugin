# AppDock 7.9.40

- Bluetooth verwendet jetzt eine eigenständige Kobo-/BlueZ-D-Bus-Steuerung.
- Kobo Libra Colour / MTK wird über `com.kobo.mtk.bluedroid` erkannt; `bluetoothctl` ist nicht mehr erforderlich.
- Standard-BlueZ-Geräte werden ebenfalls unterstützt, einschließlich Ein-/Ausschalten, Suche sowie Verbinden/Trennen.
- Die bisher irreführende pauschale Meldung „Bluetooth controls are unavailable on this device“ wird nur noch angezeigt, wenn tatsächlich kein Bluetooth-D-Bus-Dienst erreichbar ist.
