#!/bin/sh
# Qi (CEF). Drops the AppImage library path, then runs the binary beside
# libcef.so and the pak files.
unset LD_LIBRARY_PATH APPDIR APPIMAGE OWD
# Chrome names its windows (Wayland app_id) after CHROME_DESKTOP, which an
# Electron app that opened a link would otherwise pass down.
export CHROME_DESKTOP=qi-cef.desktop
root=$(CDPATH= cd -- "$(dirname "$0")/../lib/qi-cef" && pwd)
cd "$root" || exit 1
exec "$root/qi-cef" "$@"
