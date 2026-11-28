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

# SingletonLock is "<host>-<pid>" on the user-data dir. A live browser on
# this machine holds it. A stale pid, or a lock from another computer, does not.
profile_busy() {
  dir=$1
  lock=$dir/SingletonLock
  [ -L "$lock" ] || return 1
  target=$(readlink "$lock" 2>/dev/null) || return 1
  host=${target%-*}
  pid=${target##*-}
  me=$(hostname 2>/dev/null || uname -n)
  [ "$host" = "$me" ] || return 1
  case $pid in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$pid" = "$$" ] && return 1
  kill -0 "$pid" 2>/dev/null
}

manifest="$state/$child.manifest"
if [ -f "$manifest" ]; then
  tab=$(printf '\t')
  busy_root=
  while IFS= read -r line || [ -n "$line" ]; do
    dest=${line%%"$tab"*}
    [ -n "$dest" ] || continue
    # dest is <user data>/<profile>/<file>. The lock sits on the user data dir.
    udata=$(dirname "$(dirname "$dest")")
    if profile_busy "$udata"; then
      busy_root=$udata
      break
    fi
  done < "$manifest"
  if [ -n "$busy_root" ]; then
    echo "qi-cef: leaving session files aside because another browser has $busy_root" >&2
  else
    while IFS= read -r line || [ -n "$line" ]; do
      dest=${line%%"$tab"*}
      src=${line#*"$tab"}
      [ -n "$dest" ] && [ -n "$src" ] && [ -e "$src" ] || continue
      rm -rf "$dest"
      mv "$src" "$dest" || echo "qi-cef: couldn't put back $dest" >&2
    done < "$manifest"
    rm -f "$manifest"
  fi
fi
prefs="$state/$child.prefs"
if [ -f "$prefs" ]; then
  "$root/qi-cef" --apply-startup-prefs="$prefs" ||
    echo "qi-cef: couldn't restore the startup setting" >&2
fi
exit "$rc"
