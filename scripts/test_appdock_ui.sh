#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export APPDOCK_PLUGIN_DIR="$PWD/appdock.koplugin/"
export LUA_PATH="$APPDOCK_PLUGIN_DIR?.lua;;"
LUA_BIN="${LUA_BIN:-luajit}"
command -v "$LUA_BIN" >/dev/null || { echo 'Install LuaJIT and the Lua filesystem, cjson and socket packages.' >&2; exit 1; }

for module in appdock.koplugin/*.lua; do
    "$LUA_BIN" -e "assert(loadfile([[$module]]))"
done

for test in test_dapps.lua test_youtube.lua test_ytmusic.lua test_dialogs.lua test_setup_assistant.lua test_theme_contrast.lua test_app_group_pinning.lua test_appdock_manager.lua test_appdock_keyboard.lua test_appdock_text.lua; do
    echo "==> $test"
    "$LUA_BIN" "$test"
done

# Include focused regression suites as they are added, without duplicating the
# end-to-end YouTube conversion suite above.
for test in test_youtube_shorts*.lua test_plugin_host*.lua; do
    [[ -f "$test" ]] || continue
    echo "==> $test"
    "$LUA_BIN" "$test"
done
