#!/bin/sh
# Qi (CEF). Drops the AppImage library path, then runs the binary beside
# libcef.so and the pak files.
unset LD_LIBRARY_PATH APPDIR APPIMAGE OWD
# Chrome names its windows (Wayland app_id) after CHROME_DESKTOP, which an
# Electron app that opened a link would otherwise pass down.
export CHROME_DESKTOP=qi-cef.desktop
root=$(CDPATH= cd -- "$(dirname "$0")/../lib/qi-cef" && pwd)
cd "$root" || exit 1

# Stay the parent. If the browser dies before it puts Chromium's session
# files back, the manifest it wrote still lists them and we finish the job.
"$root/qi-cef" "$@" &
child=$!
wait "$child"
rc=$?

state="${XDG_STATE_HOME:-$HOME/.local/state}/qi/session-hold"
manifest="$state/$child.manifest"
if [ -f "$manifest" ]; then
  tab=$(printf '\t')
  while IFS= read -r line || [ -n "$line" ]; do
    dest=${line%%"$tab"*}
    src=${line#*"$tab"}
    [ -n "$dest" ] && [ -n "$src" ] && [ -e "$src" ] || continue
    rm -rf "$dest"
    mv "$src" "$dest" || echo "qi-cef: couldn't put back $dest" >&2
  done < "$manifest"
  rm -f "$manifest"
fi
prefs="$state/$child.prefs"
if [ -f "$prefs" ]; then
  "$root/qi-cef" --apply-startup-prefs="$prefs" ||
    echo "qi-cef: couldn't restore the startup setting" >&2
fi
exit "$rc"
