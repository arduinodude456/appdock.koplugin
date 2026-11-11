# AppDock 9.1.1 — Blitbuffer Glass Blur

AppDock 9.1.1 ersetzt die Glass-Backdrop-Skalierung über `ui/renderimage` durch eine eigenständige Blitbuffer-Implementierung. Der Hintergrund wird auf einem groben Raster abgetastet, bilinear interpoliert und direkt in kleine Blitbuffer-Blöcke gezeichnet. Dadurch benötigt die Glass-Oberfläche keine native Bildskalierungs-API und bleibt auf Geräten mit eingeschränkter RenderImage-Unterstützung robuster.
