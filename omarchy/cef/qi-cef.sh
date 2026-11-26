#!/bin/sh
# Qi (CEF). Drops the AppImage library path, then runs the binary beside
# libcef.so and the pak files.
unset LD_LIBRARY_PATH APPDIR APPIMAGE OWD
root=$(CDPATH= cd -- "$(dirname "$0")/../lib/qi-cef" && pwd)
cd "$root" || exit 1
exec "$root/qi-cef" "$@"
