# Qi (CEF) roadmap

Qi (CEF) is the Chromium build. The Qt build stays the daily browser with
the sidebar, Spaces, the agent and the rest. CEF exists because Qt
WebEngine cannot run a real Chrome extension. LastPass is the one that
had to work.

The engine is `omarchy/cef/`: a CEF Views window, Chrome runtime, Chrome
style (`CEF_RUNTIME_STYLE_CHROME`, toolbar type `CEF_CTT_NORMAL`). That is
the combination CEF's maintainer says extensions need. Alloy style and
off-screen rendering do not show extension icons. Embedding that window
inside the Qt Quick window is unsupported on Wayland (cef#2804), so Qi
(CEF) is its own process. The Rust core is not linked in yet.

Pinned build: CEF **158.0.6** / Chromium **158.0.8127.89**, the same
milestone as Omarchy's Chromium. Keep the majors equal. A newer CEF will
upgrade the profile out from under Chromium.

Launch: `qi-cef`. Install: `make install-cef` (runtime in
`~/.local/lib/qi-cef`, wrapper `~/.local/bin/qi-cef`, launcher
"Qi (CEF)"). The Qt binary stays `qi`. `omaweb` is a symlink to `qi`.

## What already works

- Native Wayland window, frameless, Omarchy colours from `colors.toml`
  at startup. App id `qi-cef`.
- Real Chromium, Chrome, Chrome Beta and Brave profiles. Names, avatars
  and colours come from `Local State`. One request context per profile
  folder. `--list-profiles`, `--profile`, `--profile-directory`,
  `--space`, `--picker`, `--browser`.
- The profile is opened in place. A live `SingletonLock` (the other
  browser's pid still exists) refuses to start and says to use
  `--snapshot`. A stale lock is ignored.
- Before the first open of a real profile, a backup lands in
  `~/.local/share/qi/chrome-backups/<browser>-<date>-cef<version>/`.
  Caches, locks and sockets are left out. Three backups are kept. Restore
  steps are in `.complete`. `--no-backup` skips it. `--snapshot` runs a
  throwaway copy instead, which is the right mode while Chromium is open.
- `Last Version` is restored on exit when CEF changed it, so Chromium
  does not treat the next start as a downgrade.
- Chrome's flags file is forwarded (password store, feature lists,
  `--load-extension`). Comma-list switches are merged and appended once.
  Overwriting CEF's own `--disable-features` crashes Chrome in
  `ActorUiContentsContainerController`. Do not append that switch a
  second time.
- Chrome toolbar with extension icons. Ctrl+Shift+B pins it, Ctrl+L
  shows it until the next load, Ctrl+Shift+X opens `chrome://extensions`,
  `--install-extension=<id>` opens the Web Store page.
- LastPass: the toolbar icon and the real popup, already signed in from
  the Chromium profile. Verified on this machine. Do not sign in or
  change anything inside LastPass from a test run.
- Popups and `chrome.tabs.create` become frameless Qi windows. One user
  data dir per process; another browser's profile is a second process.
- Unpacked extensions stay enabled by setting
  `extensions.ui.developer_mode` on the context. Chrome disables them
  otherwise (disable reason bit 24) and writes that into Preferences,
  which Chromium then sees too. Side effect: Chromium's Developer mode
  toggle shows on.
- XDG dirs moved from `omaweb` to `qi` on first launch (move, not copy,
  and only when `qi` is absent). The CEF download cache moved from
  `~/.cache/omaweb-cef` to `~/.cache/qi-cef`.

## Known gaps

- **Chrome sync is off under CEF.** Startup clears sync metadata
  (`HistorySyncBridge::ApplyDisableSyncChanges`: foreign-device history
  visits and "known to sync" flags). Chromium re-syncs from Google the
  next time it starts. The log still says Desktop Identity Consistency
  cannot be enabled because no OAuth client id was picked up, even though
  the flags file is forwarded. This is a real mutation of the profile.
  The backup runs first because of it. Whether CEF can keep sync is
  unknown.
- **Password key name.** CEF is unbranded, so libsecret is "Chromium Safe
  Storage", which matches Chromium. Google Chrome and Brave use their own
  key ("Chrome Safe Storage", "Brave Safe Storage"). Those profiles will
  open logged out until that is mapped.
- **No tab strip.** New windows tile under Hyprland. Some Chrome-created
  windows may still show up as stock Chrome windows through the default
  client. Not checked to exhaustion.
- **Toolbar is Chrome's.** Extension icons live on it. There is no
  Qi-drawn omnibox, no sidebar, no pinning UI of our own.
- **Theme is read once**, at startup.
- **Developer mode** is forced on, in the shared Preferences.
- The Qt build's own profiles (`~/.local/share/qi`) are not the same
  thing as a Chrome profile. Qi (CEF)'s `--browser=qi` is an empty CEF
  user data dir for a machine with no Chromium.

## Work left

One person, rough. The Qt column is what `qi` does today.

| Qt Qi today | Left on CEF | Est. |
| --- | --- | --- |
| Frameless themed window, live theme reload | Colours apply at startup. Watch `colors.toml` and re-apply. | 1–2 days |
| Hidden URL bar, Ctrl+L | Chrome's toolbar does this. A Qi omnibox replaces it. | 1 week |
| Sidebar: tabs, favorites, Spaces, folders, archive | A CEF Views panel or a WebUI side panel, and more than one browser in a window. | 3–4 weeks |
| Real Chrome profiles and the picker | Done as a spike. Create and remove profiles, avatars, a per-Space binding UI. | 1 week |
| Chrome extensions, including LastPass and the Web Store | Done via Chrome style. Popups that anchor with the toolbar hidden, and a pinning UI. | 1–2 weeks |
| Split view, Peek | Two `CefBrowserView`s in a box. Peek as an overlay window. | 1–2 weeks |
| Agent panel (OpenAI-compatible) | Port `agent.rs`. The panel is a View or a side panel. | 1–2 weeks |
| Ad blocker, hide element, reading mode | A `CefResourceRequestHandler` and a port of `blocker.rs`, or ship uBlock Origin. | 1–2 weeks |
| Passwords | Chrome's manager plus LastPass. Drop Qi's keyring store or bridge it. Map Chrome and Brave safe-storage key names. | 2–3 days |
| Session restore, history, bookmarks | Chrome's, per profile. Map them into the sidebar. | 1 week |
| Rust core (`cxx` or `cef-rs`) | Link the Rust core into this process, or port the app onto `cef-rs`. | 2–3 weeks |
| Sync and Google sign-in | Find out if CEF can keep sync. See the gap above. | unknown |
| Packaging, no AUR | Install script, strip, desktop file. Done for this machine. A repeatable install for another machine, and a stripped runtime that is not a 2 GB copy, still wants a pass. | 2–3 days |

Reaching the Qt feature set on CEF is about **6–10 weeks** after the
spike, plus a Chromium bump every four weeks. Do the bump by moving the
pin in `fetch-cef.sh` to the CEF build whose Chromium major matches the
distro package. Do not let CEF get ahead of it.

## Keys (CEF)

| Keys | Does |
| --- | --- |
| Ctrl+L | Address bar, until the next load |
| Ctrl+Shift+B | Pin or hide the Chrome toolbar (extension icons live here) |
| Ctrl+T, Ctrl+N | New window, same profile |
| Ctrl+W | Close |
| Ctrl+Shift+M | Profile picker |
| Ctrl+Shift+X | `chrome://extensions` |
| Ctrl+Alt+1 … 9 | That Space's profile |
| Ctrl+Q | Quit |

## Rules that stay

- No AUR, and no package named `qi` in `/usr`.
- Do not `pacman -S` a qt6 package. It downgrades `qt6-webengine`.
- Do not open a Chrome profile without the backup, unless `--snapshot`
  or `--no-backup` was asked for.
- Never print the flags file. It carries OAuth client material. Qi
  forwards it at runtime and does not store a copy.
- Never commit CEF binaries, build output, snapshots or profile backups.
