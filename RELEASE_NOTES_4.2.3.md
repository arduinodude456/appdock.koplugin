# AppDock 4.2.3 — Split

## Zuverlässiges Ziehen in beide Richtungen

Während eines Ziehvorgangs bleibt der Splitscreen-Mittelstreifen jetzt am gleichen Gestenobjekt gebunden. Dadurch kann die Teilung zuerst nach unten und anschließend wieder nach oben verschoben werden, bevor der Finger losgelassen wird.

## Stabilerer Neuaufbau

AppDock aktualisiert die Split-Teilung während der Pan-Geste nur intern und zeichnet die betroffene Region schnell nach. Der aufwändigere Host-Neuaufbau wird genau einmal beim Loslassen ausgeführt. Das verhindert, dass eine laufende Geste ihren Divider durch einen Zwischen-Neuaufbau verliert.

## Validierung

Lua-5.1-Syntax, Root-/Paketspiegel und die DApp-Core-Regression wurden ausgeführt. Die Splitter-Regression deckt nun Abwärts- und anschließende Aufwärtsbewegung innerhalb derselben Geste, positionsloses Loslassen, Persistenz und den fortlaufenden DApp-Lebenszyklus ab.
