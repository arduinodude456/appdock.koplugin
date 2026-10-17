#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export APPDOCK_PLUGIN_DIR="$PWD/appdock.koplugin/"
export LUA_PATH="$APPDOCK_PLUGIN_DIR?.lua;;"
LUA_BIN="${LUA_BIN:-luajit}"
command -v "$LUA_BIN" >/dev/null || { echo "Install LuaJIT (or set LUA_BIN=lua5.1)." >&2; exit 1; }
for module in appdock.koplugin/appdock_sleepscreen*.lua appdock.koplugin/main.lua appdock.koplugin/appdock_appstore.lua appdock.koplugin/appdock_dapps.lua; do
    "$LUA_BIN" -e "assert(loadfile([[$module]]))"
done
for test in test_sleepscreen*.lua test_appstore_play.lua test_tbs_account.lua test_setup_assistant.lua test_lockscreen.lua test_theme_contrast.lua; do
    echo "==> $test"
    "$LUA_BIN" "$test"
done
if command -v deno >/dev/null; then
    echo '==> Sleepscreen server typecheck'
    deno check supabase/functions/tbs-sleepscreens/index.ts
    echo '==> Sleepscreen server tests'
    deno test supabase/functions/tbs-sleepscreens/
else
    echo 'Deno unavailable: server tests skipped; install Deno to run the complete suite.' >&2
fi
