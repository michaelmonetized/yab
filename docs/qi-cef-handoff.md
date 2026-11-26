# Qi: CEF engine, Chrome extensions + real Chrome profiles — handoff

Written 2026-11-26 09:40 EST by the Grok Bot executor that started this work.
Carried out the same day: the rename, the Qi (CEF) launcher, the live
LastPass check and `omarchy/docs/cef-roadmap.md`. This file is the brief.
The roadmap is the status.
Repo: `~/Projects/yab` on m1pro16 (github.com/michaelmonetized/yab). `main` is at
`7df8dad` (PRs #1–#3 merged). Work-in-progress is on local branch
**`omaweb-cef-engine`**, uncommitted (`omarchy/cef/`, `.gitignore` additions,
this file). Nothing has been committed or pushed. Do not commit WIP to `main`.

## What Michael asked for (his words, in order)

1. "I want chrome extensions and chrome user profile support." (Omaweb runs on
   Qt WebEngine, which only has a sliver of the extension API: no chrome.tabs,
   windows, contextMenus, nativeMessaging. Bitwarden's popup spins; LastPass
   fails.) **Target extension: LastPass** (he uses it daily).
2. "Not chrome style profiles actual chrome profiles like yab does." List and
   open his *real* Chrome/Chromium profiles (`~/.config/chromium`,
   `~/.config/google-chrome`, …: `Default`, `Profile 1`, … with names/avatars
   from `Local State`), so that profile's cookies, logins, extensions
   (LastPass included) and settings are live. Handle Chrome's `SingletonLock`.
   **Never corrupt or migrate his profile without making a backup first.**
3. "That name is terrible 'omaweb' yuck call it 'Qi'." Rename everything
   user-facing: app name and window title; binary/command `qi`; launchers
   "Qi" and "Qi (CEF)" (or just "Qi" once CEF is the default); config dir
   `~/.config/qi`, migrating `~/.config/omaweb` (also migrate
   `~/.local/share/omaweb`, `~/.local/state/omaweb`, `~/.cache/omaweb`);
   README and docs; crate/package names where practical. **Keep the current
   icon** (`omarchy/data/omaweb.svg`, a plain window glyph, no wordmark —
   just rename the file); Michael designs his own marks, don't make a logo.
   On m1pro16 replace the old Omaweb launcher and `~/.local/bin/omaweb` with
   the Qi ones; a temporary `omaweb -> qi` symlink is fine.

## Deliverables

- A working **"Qi (CEF)"** launcher on m1pro16 (separate from the Qt build,
  which must keep working), launched and verified on his Hyprland session,
  LastPass icon + popup confirmed.
- **One PR** (or a stacked pair: CEF engine + rename) to `main` of
  michaelmonetized/yab, authored as Michael C. Hurley
  (git config here is already `Michael C Hurley <michaelmonetized@gmail.com>`).
- A **roadmap doc** in the repo (`omarchy/docs/cef-roadmap.md` or similar):
  every Yab/Omaweb feature, the work left on the CEF engine, rough estimate.

## Rules (hard)

- Never use the AUR. Never publish to the AUR.
- Don't `pacman -S` any qt6 package: it downgrades qt6-webengine
  (6.140.0-1 → 6.11.2-2). Refuse any downgrade. No careless `pacman -Syu`.
- Don't restart `t3code.service`, don't touch/remount `~/cloud`, don't reboot.
- Before any commit/push: update `.gitignore` (CEF binaries, build output,
  profile dirs/snapshots/backups never committed — lines already added) and
  run `gitleaks` on the staged changes (`gitleaks git --staged` or
  `gitleaks protect --staged`; binary at `~/.local/bin/gitleaks`). Never push
  until clean. No force-push to main.
- Large CEF downloads stay out of git; `omarchy/cef/fetch-cef.sh` fetches them.
- Back up a Chrome user data dir before Qi first opens it (code does this).
- Never put passwords, keys or tokens in chat/PR text. Note:
  `~/.config/chromium-flags.conf` contains Google OAuth client id/secret
  flags; Qi forwards them at runtime but never print or commit them.
- Don't sign into LastPass; Michael will. Don't change anything inside
  LastPass.

## Engine choice and research

**CEF (Chromium Embedded Framework) with the Chrome runtime and Chrome-style
browsers in a Views-hosted CefWindow.** Reasons:

- Since M125 CEF splits runtime vs style; the Alloy bootstrap was removed in
  M128 (cef#3685). CEF maintainer: "Extensions are only supported with Chrome
  style windows that show some portion of the Chrome UI (like the Chrome
  toolbar)" (magpcss.org/ceforum viewtopic.php?p=56226, and t=20278: icons need a Views-hosted
  Chrome-style CefBrowserView + CefWindow). Alloy style / OSR → no extension
  UI. So: `CEF_RUNTIME_STYLE_CHROME`, `GetChromeToolbarType → CEF_CTT_NORMAL`.
- Chrome style = Chrome's own extension system: chrome://extensions, Web
  Store installs, chrome.tabs, action popups, native messaging lookups.
- Each `CefRequestContext` with a distinct `cache_path` under
  `root_cache_path` is a separate Chrome Profile. Pointing `root_cache_path`
  at `~/.config/chromium` and `cache_path` at `~/.config/chromium/Default`
  opens his real profile.
- Wayland: CEF Views windows run natively under Ozone Wayland
  (`--ozone-platform=wayland`) — **verified on m1pro16** (Hyprland reports
  `xwayland: false`). Only *embedding* a CEF browser into another toolkit's
  Wayland surface is unsupported (cef#2804, still open; a fork exists). That
  rules out putting CEF inside the Qt Quick window; Qi (CEF) is therefore a
  CEF-Views app (C++), with the Rust core to be linked/ported later.
- Alternatives rejected: Qt WebEngine (partial extension API — the reason for
  this work); WebKitGTK/WPE (no Chrome extensions); CEF OSR/Alloy (no
  extension UI); driving stock Chromium with `--app` (no custom chrome, no
  embedding).
- Rust `cef` crate (tauri-apps/cef-rs) exists if a later port wants Rust
  bindings instead of C++.

### CEF builds (linuxarm64)

Index: https://cef-builds.spotifycdn.com/index.json → `linuxarm64`.
Pinned: **158.0.6+g23f1736+chromium-158.0.8127.89** (stable). His system
Chromium is 158.0.8127.88 (Omarchy package), so the profile versions match
within the milestone. Keep CEF's major equal to the installed Chromium's major
so his profile isn't upgraded under Chromium.

- minimal (used, 435 MB): https://cef-builds.spotifycdn.com/cef_binary_158.0.6%2Bg23f1736%2Bchromium-158.0.8127.89_linuxarm64_minimal.tar.bz2 (+ `.sha1`)
- standard (911 MB, has cefclient/cefsimple sources & tests): https://cef-builds.spotifycdn.com/cef_binary_158.0.6%2Bg23f1736%2Bchromium-158.0.8127.89_linuxarm64.tar.bz2
- Already downloaded and unpacked in `~/.cache/omaweb-cef/` (rename the cache
  to `~/.cache/qi-cef` when renaming; update fetch-cef.sh).
- `libcef.so` is 2.5 GB unstripped; strip it on install
  (`strip --strip-unneeded`) to save disk.

## How upstream Yab handles Chrome profiles (read from the macOS sources in this repo)

- `Sources/Fast/Import.swift`, `TabImport.swift`, `SpaceImport.swift`,
  `ExtensionImport.swift`, `BringCounts.swift`.
- Yab finds each Chromium-family browser by its data folder, reads profile
  names from `Local State` → `profile.info_cache` (folder → name, avatar,
  colour), and treats each profile folder as a "place". On **Bring In**, each
  profile becomes a Yab **Space "signed in as" that profile, with its own
  sign-ins / cookie store**; the browser's first profile maps to Yab's first
  space (Personal).
- It **copies, it doesn't open in place**: "The file is copied before it is
  read. The browser it belongs to is usually running, and reading its live
  database underneath it is how you get a lock error". Passwords/cookies are
  decrypted with "<Name> Safe Storage" from the macOS keychain and re-stored.
- Extensions: reads `Preferences`/`Secure Preferences` →
  `extensions.settings`; Web Store ones are **re-installed from the store**
  (signed), unpacked ones load from their folder; extension storage/sign-ins
  do *not* come over (you sign into LastPass again).
- YabCore (CEF) itself uses `DATA_ROOT/space-PROFILE` request contexts and
  pins `--profile-directory=Default` (`YabCore/README.md`).
- Michael asked for *actual* profiles, so Qi goes one step further on Linux:
  open the real user data dir live (with lock check + backup). A copy mode
  (`--snapshot`) exists for when Chromium is open, which is closest to Yab.

## What's built (branch `omaweb-cef-engine`, `omarchy/cef/`, uncommitted)

```
omarchy/cef/fetch-cef.sh     pinned download + sha1 check → ~/.cache/omaweb-cef, symlink third_party/cef
omarchy/cef/CMakeLists.txt   CEF cmake macros; forces PROJECT_ARCH=arm64 on aarch64
omarchy/cef/src/omaweb.h     declarations
  main.cc     args, root choice, lock check, backup, snapshot, CefInitialize, restore "Last Version"
  app.cc      CefApp: ozone wayland, --profile-directory pin, forwards ~/.config/chromium-flags.conf
              (password-store=gnome-libsecret, oauth2 client flags, enable/disable-features,
              load-extension) merging comma lists ONCE; relaunch → new window
  client.cc   titles ("<page> — Omaweb · <profile>"), auto-hide toolbar on load,
              https://omaweb.invalid/open?root=&dir= commands from the picker page
  window.cc   frameless CefWindow (IsFrameless), app_id omaweb-cef, Chrome toolbar
              (CEF_CTT_NORMAL) hidden by default; accelerators; profile picker (data: page
              with real profiles + avatars + Spaces map); popups → new frameless windows;
              SpawnFor() runs another process for another browser's root
  profiles.cc roots (chromium, google-chrome, -beta, brave, own fallback), Local State
              parsing (info_cache, profiles_order, gaia_name, highlight colour, picture),
              Spaces from ~/.local/state/omaweb/workspace.json mapped to Chrome profiles
              by folder/name, one CefRequestContext per profile dir
  safety.cc   LiveLockHolder (SingletonLock host-pid, stale = pid gone), CopyUserDataDir
              (skips caches/locks/sockets), BackupUserDataDir → ~/.local/share/omaweb/
              chrome-backups/<browser>-<date>-cef<ver>/ once per day+version, keep 3,
              restore instructions in .complete
  theme.cc    Omarchy colors.toml → background/accent; SetChromeColorScheme(dark/light,
              accent) + TONAL_SPOT; sets extensions.ui.developer_mode=true (see findings)
```

Build (note the env quirk below):
```
cd ~/Projects/yab/omarchy/cef && ./fetch-cef.sh
env -i PATH=/usr/bin:/bin HOME=$HOME LANG=C.UTF-8 cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
env -i PATH=/usr/bin:/bin HOME=$HOME LANG=C.UTF-8 cmake --build build -j10
# → build/Release/omaweb-cef (+ libcef.so, paks, locales; run from that dir layout)
```
CLI: `--list-profiles`, `--browser=chromium|google-chrome|brave|omaweb`,
`--user-data-dir=`, `--profile=<name|dir>`, `--profile-directory=`,
`--space=N|id`, `--picker`, `--snapshot [--keep-snapshot]`, `--no-backup`,
`--install-extension=<id>` (opens Web Store page), `--extensions`, `--version`.
Keys: Ctrl+L address (toolbar until next load), Ctrl+Shift+B pin toolbar
(extension icons live there), Ctrl+T/N new window same profile, Ctrl+W close,
Ctrl+Shift+M profile picker, Ctrl+Shift+X chrome://extensions,
Ctrl+Alt+1…9 Space's profile, Ctrl+Q quit.

## Verified on m1pro16 (in `--snapshot` mode, a throwaway copy of his Chromium profile)

- Native Wayland window, frameless, dark Omarchy colours, page renders.
- `--list-profiles` → `Chromium ~/.config/chromium: Default  Michael  Michael Monetized`.
- Ctrl+Shift+B shows the Chrome toolbar with his extension icons
  (**LastPass first**, plus copy-url, yt-dlp, whatsapp-slim, a puzzle menu).
- **Clicking the LastPass icon opened the real LastPass popup, already signed
  in from his profile** (vault/generator/alerts/account tabs). I closed it with
  Escape and touched nothing in it. So: real profile + real LastPass works.
- chrome://version shows all forwarded flags applied (password store, oauth,
  features, load-extension) and User Data/Profile Path = the snapshot.
- The live (non-snapshot) path — backup + open `~/.config/chromium` directly —
  has **not** been run yet. Chromium was not running at 09:30 EST; its
  `SingletonLock -> m1pro16-257430` is stale (pid gone).
- The snapshot copy was deleted afterwards (it held his session data).

## Findings / caveats to handle

1. **Crash if CEF's own `--disable-features` is overwritten.** CEF adds
   `--disable-features=GlicActorUi,AutofillActorMode,LensOverlay,KillOnInvalidNavigationHeaders`.
   Appending the switch a second time replaced it and Chrome crashed in
   `actor::ui::ActorUiContentsContainerController::OnWebContentsAttached`
   (`TabInterface::GetFromContents` null). Fixed by merging comma lists and
   appending each switch once (app.cc). Keep it that way.
2. **Unpacked extensions get disabled** (disable_reasons 1<<24) by Chrome style
   when developer mode is off, and that is written into his Preferences, so
   Chromium would see them off too (his `~/.config/browser-keys/chrome`
   unpacked extension). `--disable-features=ExtensionDeveloperModeSettings`
   did NOT help. Setting `extensions.ui.developer_mode=true` per context did
   (verified: no disable_reasons after the run). Side effect: Developer mode
   toggle shows on in Chromium too. Mention it in the PR.
3. **Sync metadata gets cleared.** The crash dump showed
   `HistorySyncBridge::ApplyDisableSyncChanges →
   DeleteAllForeignVisitsAndResetIsKnownToSync`: under CEF, Chrome sync is
   off for the profile, so it clears sync metadata (foreign-device history
   visits, "known to sync" flags). Chromium re-syncs from Google on its next
   start, but it IS a mutation of his profile → this is why the backup runs
   first. Investigate whether CEF can keep sync (oauth flags are forwarded;
   log still says "Desktop Identity Consistency cannot be enabled as no
   OAuth client ID…") or whether to default to snapshot mode. Call it out in
   the PR and the roadmap.
4. `Last Version` in the user data dir: main.cc restores Chromium's value on
   exit so Chromium never treats the next start as a downgrade. CEF did not
   change it in the snapshot test.
5. Cookie/password decryption: CEF is unbranded, so libsecret key is
   "Chromium Safe Storage" — matches Chromium. Google Chrome / Brave profiles
   would need their own key name ("Chrome Safe Storage"); expect logged-out
   sites there. Gap for the roadmap.
6. Process singleton: CEF takes `SingletonLock` on the root, so while Qi (CEF)
   runs, launching Chromium forwards to Qi (`OnAlreadyRunningAppRelaunch` →
   new window). Qi refuses to start if a live Chromium holds the lock and
   suggests `--snapshot`. One root per process; other browsers' profiles open
   in a second process (SpawnFor).
7. Chrome-created windows (chrome.tabs.create from an extension, Ctrl+click)
   arrive via OnPopupBrowserViewCreated → Qi makes a frameless window; no
   tab strip yet (Hyprland groups/tiles windows). Some may still appear as
   stock Chrome windows via GetDefaultClient — check.
8. Env quirk on m1pro16: shells started from the Grok Bot AppImage inherit
   `LD_LIBRARY_PATH=/tmp/.mount_appima…/usr/lib` + `APPDIR/APPIMAGE/OWD`,
   which breaks `cmake` ("Could not find CMAKE_ROOT") and could break the app.
   Build/launch with `env -i …` or `env -u LD_LIBRARY_PATH -u APPDIR -u APPIMAGE -u OWD`.
   Hyprland here uses a **Lua config**: `hyprctl dispatch 'hl.dsp.focus({ window = "address:0x…" })'`,
   `hyprctl dispatch 'hl.dsp.cursor.move({ x = X, y = Y })'`. Input for tests:
   `wtype` (keys), `ydotool click 0xC0` after `systemctl --user start ydotool`
   (stop it afterwards). Screenshots: `grim -g "x,y wxh" ~/…png` (keep them
   under $HOME, gitignored).
9. Chrome style startup log noise (portal Secret, idle, overlay_prioritizer)
   is harmless.

## Remaining work (suggested order)

1. Rename to Qi (Qt build + CEF build + data/docs), with XDG dir migration
   (`omaweb` → `qi` for config/data/state/cache; move, don't copy; only if the
   `qi` dir doesn't exist). Binary `qi` (Qt) and `qi-cef` (CEF) or a single
   `qi` with the CEF engine behind a flag — keep the Qt build working.
   Wayland app_id `qi` / `qi-cef`. Update `omarchy/data/hyprland.conf`.
   Icon: rename `omaweb.svg` → `qi.svg`, same content. Crate name: `qi`
   (crates.io has an unrelated 2021 `qi` 0.0.1; fine for an unpublished
   binary crate). No pacman/AUR package or `/usr/bin/qi` named qi on m1pro16.
2. `make install-cef` / install script: copy `build/Release` to
   `~/.local/lib/qi-cef/` (strip libcef.so), wrapper `~/.local/bin/qi-cef`
   that unsets the AppImage env, `qi-cef.desktop` "Qi (CEF)" with absolute
   Exec, icon. Check chrome-sandbox: it ran fine with the namespace sandbox
   (no setuid needed) — confirm.
3. Run the live path once on m1pro16 (Chromium closed): confirm the backup
   lands in chrome-backups, the window opens his real Default profile,
   LastPass icon + popup load. Don't sign in or change LastPass.
4. Roadmap doc + README updates; PR with screenshots (gitignored originals,
   only small PNGs in docs if wanted).
5. Replace `~/.local/bin/omaweb` + the "Omaweb" launcher on m1pro16 with Qi;
   temporary `omaweb → qi` symlink.

## Roadmap seeds (estimates are rough, one engineer)

| Feature (Qt Omaweb today) | CEF work left | Est. |
|---|---|---|
| Frameless themed window, live theme reload | theme done at start; watch colors.toml + re-apply | 1–2 d |
| Hidden URL bar, Ctrl+L | done via Chrome toolbar; custom omnibox to replace Chrome's | 1 wk |
| Sidebar tabs, favorites, Spaces, folders, archive | rebuild as CEF Views panel or a WebUI side panel; multiple browsers per window | 3–4 wk |
| Real Chrome profiles + picker | done (spike); profile create/remove, avatars, per-Space binding UI | 1 wk |
| Chrome extensions incl. LastPass, Web Store | done via Chrome style; toolbar-less popups anchoring, pinning UI | 1–2 wk |
| Split view, Peek | two CefBrowserViews in a box layout; Peek as overlay window | 1–2 wk |
| Agent panel (Grok/xAI OpenAI-compatible) | port Rust agent.rs; panel as View or side panel | 1–2 wk |
| Ad blocker, hide element, reading mode | CefResourceRequestHandler + port blocker.rs, or uBO extension | 1–2 wk |
| Passwords | Chrome's own manager + LastPass; drop Qi keyring store or bridge | 2–3 d |
| Session restore, history, bookmarks | Chrome's own per profile; map to sidebar | 1 wk |
| Rust core integration (cxx / cef-rs) | link Rust core into CEF app or port app to cef-rs | 2–3 wk |
| Sync, Google sign-in | investigate CEF sync limits (finding 3) | unknown |
| Packaging (no AUR): install script, strip, desktop file | | 2–3 d |
