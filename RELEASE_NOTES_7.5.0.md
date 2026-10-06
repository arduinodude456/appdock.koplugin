# AppDock 7.5.0 — DuckDuckGo search bar and Play Store AppStore

## DuckDuckGo search bar on the first homescreen page

- The first homescreen page now carries a branded DuckDuckGo search bar below the greeting and date line.
- The bar follows AppDock's E-Ink rules: one filled surface in DuckDuckGo orange with white glyph and white wordmark, a stable contrast role on grayscale panels, and no gradients or transparency.
- Tapping the bar opens the AppDock keyboard with the current query. The confirmed text is handed to AppDock's JavaScript-free Web Browser DApp, which runs the search against `html.duckduckgo.com` exactly like the browser's own **Search** action.
- The Web Browser shows a local "Searching DuckDuckGo" state for the query while the HTTPS request is in flight, so a tap is acknowledged immediately on E-Ink.
- The bar belongs to page one only. Swiping to the next app page keeps the grid uncluttered, and the launcher layout dialog gained a **Hide DuckDuckGo bar / Show DuckDuckGo bar** switch.

## AppStore rebuilt in the Google Play Store look

- The AppStore now uses a fixed Google Play surface: white background, Play green actions, the four-colour Play pinwheel mark next to a **Google Play** wordmark, and a rounded search pill.
- Top app bar: Play mark, wordmark, search chip, catalog refresh chip, and a green catalog profile chip that explains the trusted source and the confirmation requirement.
- **Recommended for you:** a shelf of up to three cards above the catalog list, drawn from real catalog entries. When installed entries have newer catalog versions, the same shelf becomes **Updates available** and labels each card with an **Update** action.
- List rows follow the Play pattern: tinted icon tile, bold title, kind and version metadata, a state line (**Not installed**, **Installed**, **Update available**) and a trailing Play button — filled green **Install**/**Update**, or an outlined green **Open**/**Use** plus a **Uninstall** secondary action for installed entries. Installed designs still activate through **Use**.
- Bottom navigation with the four catalog categories **For you**, **Apps**, **Widgets**, and **Designs**, highlighted with a green container pill instead of a tab bar.
- Empty, error, loading, and no-search-result situations are rendered inside the same Play surface instead of falling back to a bare list.
- No invented ratings, review counts, or screenshots were added: every visible value comes from the public `dapps.txt` catalog or from local installation state.

## Notes

- Colours keep an explicit grayscale counterpart, so the Play layout stays readable on monochrome readers.
- The Store keeps reading only `dapps.txt` over HTTPS, keeps validating relative Lua paths, and still requires an explicit confirmation before every install, update, or removal.
- The launcher layout dialog now reports `Spacing`, `Shape`, `Search`, and `DuckDuckGo` state in one line.

## Verification

- Lua 5.1 syntax validation passed for the plugin and tests.
- New AppStore Play regression test passed: it renders the real pane through a painting stand-in and checks the Play bar, search pill, shelf, list rows, category scoping, empty/error states, and the confirmation handoff.
- AppDock DApp regression test passed, including the DuckDuckGo bar on page one, the keyboard handoff, the trimmed query transfer to the Web Browser, and the page-two exclusion.
- Browser, keyboard, ordering, and setup assistant regression tests passed.