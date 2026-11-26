#!/usr/bin/env bash
# Fetch the pinned CEF binary distribution for Qi (CEF).
#
# CEF is ~430 MB compressed and ~3 GB unpacked, so it never goes in git.
# This script downloads the "minimal" distribution from the official
# Spotify-hosted CEF builds, checks its SHA-1, unpacks it into a cache
# outside the repo and points omarchy/cef/third_party/cef at it.
#
#   ./fetch-cef.sh            fetch the pinned version for this machine
#   CEF_VERSION=... ./fetch-cef.sh   try another version (see index.json)
set -euo pipefail

CEF_VERSION="${CEF_VERSION:-158.0.6+g23f1736+chromium-158.0.8127.89}"
case "$(uname -m)" in
  aarch64|arm64) CEF_PLATFORM=linuxarm64 ;;
  x86_64)        CEF_PLATFORM=linux64 ;;
  armv7l)        CEF_PLATFORM=linuxarm ;;
  *) echo "fetch-cef: unsupported arch $(uname -m)" >&2; exit 1 ;;
esac

here="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${QI_CEF_CACHE:-}" ]; then
  cache="$QI_CEF_CACHE"
elif [ -n "${OMAWEB_CEF_CACHE:-}" ]; then
  cache="$OMAWEB_CEF_CACHE"
else
  cache="${XDG_CACHE_HOME:-$HOME/.cache}/qi-cef"
  legacy="${XDG_CACHE_HOME:-$HOME/.cache}/omaweb-cef"
  if [ ! -e "$cache" ] && [ -d "$legacy" ]; then
    mv "$legacy" "$cache"
  fi
fi
name="cef_binary_${CEF_VERSION}_${CEF_PLATFORM}_minimal"
archive="$name.tar.bz2"
# The version string contains '+', which must be percent-encoded in the URL.
url_name="${archive//+/%2B}"
base="https://cef-builds.spotifycdn.com"

mkdir -p "$cache" "$here/third_party"
cd "$cache"
if [ ! -d "$name" ]; then
  if [ ! -f "$archive" ]; then
    echo "fetch-cef: downloading $archive"
    curl -fL --retry 3 -o "$archive.part" "$base/$url_name"
    mv "$archive.part" "$archive"
  fi
  curl -fsSL -o "$archive.sha1" "$base/$url_name.sha1"
  echo "$(cat "$archive.sha1")  $archive" | sha1sum -c -
  echo "fetch-cef: unpacking"
  tar xjf "$archive"
fi
ln -sfn "$cache/$name" "$here/third_party/cef"
echo "fetch-cef: $here/third_party/cef -> $cache/$name"
