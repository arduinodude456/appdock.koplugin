# AppDock 9.1.5 — Dialog Frosted Veil for Quick Settings

AppDock 9.1.5 verwendet für Quick Settings denselben abgesicherten Frosted-Veil-Mechanismus wie die AppDock-eigenen Dialoge. Der Hintergrund wird zuerst per Alpha-Blending überlagert; falls das nicht verfügbar ist, folgt ein kurzlebiges `addblitFrom`-Overlay und anschließend ein sicherer Graustufen-Fallback. Ein persistenter Backdrop-Blitbuffer wird nicht mehr verwaltet.
