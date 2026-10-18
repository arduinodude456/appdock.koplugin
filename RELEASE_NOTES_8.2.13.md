# AppDock 8.2.13 – transparente Textdarstellung

Mehrzeilige, nicht editierbare Texte verwenden nun `appdock_text.TextBoxWidget`. Der lokale Renderer erzeugt eine Glyphenmaske und komponiert sie mit KOReaders nativen Graustufen-/RGB-Blitfunktionen über die bereits gezeichnete Fläche. Leerraum und Zeilenabstände malen dadurch keine weißen Rechtecke mehr. Schriftfarbe, Kantenglättung, Umbruch und native Ressourcenverwaltung bleiben erhalten.

Die integrierten Diagnoseansichten von YouTube und YouTube Music verwenden den neuen Renderer. Store-DApps können ihn über `require("appdock_text")` oder `context.text` nutzen. Vorhandene `ScrollTextWidget`-Kinder können über `appdock_text.makeTransparent(widget.text_widget)` angepasst werden, ohne globale KOReader-Klassen zu verändern.

Einzeilige `TextWidget`-Beschriftungen zeichnen schon nativ ohne Hintergrund und bleiben unverändert. Editierbare Texte, Bildinhalte und hervorgehobene Auswahlen behalten ihren nativen Renderer. Für diese Fälle beziehungsweise ältere Blitbuffer-APIs muss `bgcolor` zur tatsächlichen Elternfläche passen. HTML-Dokumentseiten und ausdrücklich gestaltete Karten-/Dialogflächen werden nicht pauschal entfernt.

Die begleitenden DApps-Updates erweitern insbesondere den bisherigen dChat-Sprechblasen-Fix auf alle Chatansichten. Sie behalten passende Hintergrundfarben als Fallback für ältere AppDock-Versionen. DockUpdate berücksichtigt das neue Modul erst für AppDock-Releases ab 8.2.13, sodass ältere Releases weiterhin installierbar bleiben.

Der Patch enthält Pixel-Regressionen für transparente Zwischenräume, weiße und farbige Schrift, Kantenglättung, Renderer-Fallbacks sowie die Unverändertheit der globalen KOReader-Klassen. Ein Test auf physischer E-Ink-Hardware steht noch aus.
