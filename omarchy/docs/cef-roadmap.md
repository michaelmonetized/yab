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
  `--snapshot`. That copy can miss writes while the browser is saving.
  A stale lock is ignored.
- Before the first open of a real profile, a backup lands in
  `~/.local/share/qi/chrome-backups/<browser>-<date>-cef<version>/`.
  Caches, locks and sockets are left out. Three backups are kept. Restore
  steps are in `.complete`. `--no-backup` skips it. `--snapshot` runs a
  throwaway copy instead while Chromium is open. The copy can be incomplete.
- `Last Version` is restored on exit when CEF changed it, so Chromium
  does not treat the next start as a downgrade.
- Chrome's flags file forwards an allowlist (password store, feature
  lists, `--load-extension`, the OAuth client). Sandbox switches are not
  copied. Comma-list switches are merged and appended once.
  Overwriting CEF's own `--disable-features` crashes Chrome in
  `ActorUiContentsContainerController`. Do not append that switch a
  second time.
- Qi draws the window. The stock tab strip stays off screen. Tabs are
  `CefBrowserView`s in one window. The sidebar has three states (hidden,
  icons, full). Ctrl+T opens a tab. Ctrl+N opens a window. Ctrl+L opens a
  floating address bar over the page. Favorites live in
  `~/.local/share/qi/favorites.json`. Shortcuts live in
  `~/.config/qi/keys.toml`. The Chrome toolbar is hidden inside that bar
  so LastPass still has an icon. Ctrl+Shift+U shows it.
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
- **Extension popups** (LastPass) are still Chrome popup windows. A normal
  link that asks for a new tab becomes a Qi tab.
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
| Hidden URL bar, Ctrl+L | Floating address bar over the page. History is read from a copy of the profile database. | done |
| Sidebar: tabs, favorites, Spaces, folders, archive | Hidden, icons, and full. Favorites above the tabs. Spaces still switch profile. No folders or archive yet. | done for the three states |
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
| Ctrl+L, Alt+D, F6 | Floating address bar |
| Ctrl+Shift+B, Ctrl+Shift+L | Cycle the sidebar: hidden, icons, full |
| Ctrl+T | New tab in this window |
| Ctrl+N | New window |
| Ctrl+W | Close the tab |
| Ctrl+Shift+T | Reopen the last closed tab |
| Ctrl+D | Duplicate the tab |
| Ctrl+Shift+U | Show the extension icons (LastPass) |
| Ctrl+Shift+M | Profile picker |
| Ctrl+Shift+X | `chrome://extensions` |
| Ctrl+Alt+1 … 9 | That Space's profile |
| Ctrl+Q | Quit |
| Super chords | `omarchy/data/qi-keys-hypr.conf`. CEF cannot register Super. |

`qi-cef --list-keys` prints the table. `qi-cef --set-key=<action> --chord=<Ctrl+T>` writes one override. The keyboard page is Ctrl+Shift+Comma.

## Rules that stay

- No AUR, and no package named `qi` in `/usr`.
- Do not `pacman -S` a qt6 package. It downgrades `qt6-webengine`.
- Do not open a Chrome profile without the backup, unless `--snapshot`
  or `--no-backup` was asked for.
- Never print the flags file. It carries OAuth client material. Qi
  forwards it at runtime and does not store a copy.
- Never commit CEF binaries, build output, snapshots or profile backups.
