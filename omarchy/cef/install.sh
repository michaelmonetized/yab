#!/bin/sh
# Install Qi (CEF) under ~/.local: the runtime in lib/qi-cef, a wrapper
# on PATH, and a "Qi (CEF)" launcher. Does not touch the Qt build.
# CEF's namespace sandbox is enough here; chrome-sandbox is not made setuid.
set -eu
PREFIX="${PREFIX:-$HOME/.local}"
here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
src="$here/build/Release"
dest="$PREFIX/lib/qi-cef"
if [ ! -x "$src/qi-cef" ]; then
  echo "install-cef: $src/qi-cef is missing. Build it first:" >&2
  echo "  cd omarchy/cef && ./fetch-cef.sh" >&2
  echo "  cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j\$(nproc)" >&2
  exit 1
fi
mkdir -p "$dest" "$PREFIX/bin" "$PREFIX/share/applications"
cp -a "$src/." "$dest/"
if [ -f "$dest/libcef.so" ]; then
  strip --strip-unneeded "$dest/libcef.so"
fi
install -m755 "$here/qi-cef.sh" "$PREFIX/bin/qi-cef"
install -Dm644 "$here/../data/qi.svg" "$PREFIX/share/icons/hicolor/scalable/apps/qi.svg"
sed "s|^Exec=qi-cef|Exec=$PREFIX/bin/qi-cef|" "$here/../data/qi-cef.desktop" \
  > "$PREFIX/share/applications/qi-cef.desktop"
chmod 644 "$PREFIX/share/applications/qi-cef.desktop"
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$PREFIX/share/applications" || true
fi
echo "install-cef: $PREFIX/bin/qi-cef"
echo "install-cef: launcher $PREFIX/share/applications/qi-cef.desktop"
