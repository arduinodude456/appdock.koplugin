# AppDock 6.1.4 — Switch Layout Safety Fix

AppDock 6.1.4 removes an invalid negative-size spacer from the custom switch layout. The switch is now rendered as one stable `FrameContainer` surface, avoiding unsupported native layout geometry during App Grid editing.

The release also replaces invalid `UIManager:setDirty(nil, ...)` calls with valid widget-targeted refreshes. No negative-size layout or nil refresh target remains in the custom Grid Editor UI path.
