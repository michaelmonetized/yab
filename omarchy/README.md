# Omaweb

A keyboard-first browser for [Omarchy](https://omarchy.org): Rust core, Qt Quick
chrome, Chromium pages through Qt WebEngine, and the active Omarchy theme
everywhere, live.

Omaweb is a Linux rewrite of [Yab](https://github.com/yetanotherbrowser/yab)
("yet another browser", a native macOS browser by Serafim Korablev). It keeps
Yab's look and idea, nothing in the way: no frame, no title bar, no
toolbar, just the page, edge to edge. Tabs live in a Yab-style sidebar
(back / forward / reload, the address as a quiet pill, New tab, the tab
list) that slides in when the pointer touches the left edge of the window
and hides again when it leaves, or stays pinned beside the page. Addresses
and searches go through one field that appears on demand as a palette
(Ctrl+L, Ctrl+T) and is gone again once you press Return. It does not reuse
Yab's Swift code, names or icons.

![Omaweb with the sidebar revealed over a page, Tokyo Night](docs/page.png)
![A new tab: the start page with the address palette open](docs/start.png)

## Why this stack

- **Qt Quick (QML), the toolkit Quickshell is built on.** Omarchy's shell
  and most Hyprland bars are QML, so Omaweb looks and behaves like part of
  the desktop, not a GTK or Electron guest. Quickshell itself is a runtime
  for desktop-shell configs (bars, panels, launchers), not for
  applications: it can load a `WebEngineView` behind a pragma, but only in
  a WebEngine-enabled build, and current releases crash Qt WebEngine on
  start (it builds `QGuiApplication` with `argc = 0`). So Omaweb is a
  standalone Qt Quick app with the same QML idiom and its own process.
- **Rust core via [cxx-qt](https://github.com/KDAB/cxx-qt).** Theme
  parsing and watching, the address field's logic, history, session and
  single-instance IPC are Rust (`src/`, unit-tested); QML only draws.
- **Qt WebEngine (Chromium).** Sites work the way they do in Chromium,
  Omarchy's default browser, with DevTools built in.
- **Not egui, not iced, not Rune (yet).** [Rune](https://github.com/anomalyco/rune),
  Anomaly's new GPU-rendered Rust UI framework, was the alternative. It is
  pre-release and has no way to host a web engine: there is no web view or
  external-texture embedding, so a browser would mean compositing Servo or
  WPE frames into it by hand. When Rune can embed a surface, the Rust core
  here can move over unchanged.

## What Omarchy gets

- **The live theme.** Reads `colors.toml` from
  `~/.local/state/omarchy/current/theme` (Omarchy 4) or
  `~/.config/omarchy/current/theme` (Omarchy 3), falling back to the
  theme's `alacritty.toml`, and fills missing keys with the same rules
  `omarchy-theme-color` uses. `omarchy theme set <name>` re-colours the
  sidebar, palette, menus, start page and the page background as it happens
  (inotify on the `current` dirs, plus a 3 s poll as a safety net). Light
  or dark mode goes to Qt's colour-scheme hint and from there to the web's
  `prefers-color-scheme`; open pages pick it up on reload.
- **The Omarchy font.** The fontconfig monospace family that
  `omarchy-font-set` writes, else your Alacritty or Ghostty font.
- **Hyprland-native.** Wayland first, app_id `omaweb`, a frameless
  window with no client-side decorations, title bar, shadows or margins,
  so it tiles edge to edge and Hyprland's border is the only frame. Super stays
  Hyprland's: every Omaweb shortcut uses Ctrl or Alt.
- **One instance.** `omaweb <url>` from a terminal, a bind or `xdg-open`
  opens a tab in the running window (a Unix socket in `$XDG_RUNTIME_DIR`).
- **Omarchy's browser binds.** Make Omaweb the default browser
  (`make default-browser`) and Omarchy's browser key opens it; `--private`,
  `--incognito` and `--private-window` all open a private tab, so the
  private-browser bind works too.
- **Mako notifications** for finished and failed downloads, through
  `notify-send`.
- **XDG paths.** Config `~/.config/omaweb/config.toml`
  ([example](config.example.toml)), history `~/.local/share/omaweb`,
  session `~/.local/state/omaweb`.

## What works

- Chromeless by default: the page fills the window. The tab sidebar is
  hidden until the pointer reaches the left edge (or Ctrl+Shift+B), hides
  when the pointer leaves, and can be pinned open (`pin_sidebar = true`,
  its top-left button, or Ctrl+Shift+B). Middle-click closes a tab; links
  that ask for a new window open as tabs. `tabs = "top"` brings back the
  classic tab strip and address bar.
- Frameless on every platform (`frameless = false` to get the window
  manager's title bar back). On X11 the sidebar's top row moves the
  window (double-click maximises) and the window edges resize it; on
  Hyprland the compositor does both.
- One field, on demand: Ctrl+L or Ctrl+T opens it as a palette over the
  page and Return or Esc puts it away. Addresses go, words search (DuckDuckGo unless you set
  `search`), keyword searches (`aw hyprland`, `aur yay`, `gh rune`,
  `crates serde`, `hypr ...`), completion from your history and open tabs.
  Nothing is sent until Return.
- Back, forward, reload and stop (keys, or the sidebar's buttons); load
  progress as an accent hairline along the top of the page.
- Find in page, zoom, full screen (page or window), view source, DevTools.
- Private tabs on an off-the-record profile; never saved, never in history.
- Session restore and reopen-closed-tab.
- Permission prompts (camera, mic, location, notifications, screen share)
  and downloads to `~/Downloads`.
- `tabs = "top"` has a compact mode: Ctrl+Shift+B hides the strip and
  toolbar, Ctrl+L brings the field back.

## Keys

| Keys | Does |
| --- | --- |
| Ctrl+L, Alt+D, F6 | Address palette (Esc closes it) |
| Ctrl+K | Jump to an open tab (palette) |
| Ctrl+T / Ctrl+Shift+N | New tab / new private tab (opens the palette) |
| Ctrl+Shift+B | Show and pin / hide the tab sidebar (`tabs = "top"`: compact mode) |
| Pointer at the left edge | Reveal the sidebar; it hides when the pointer leaves |
| Ctrl+W | Close tab |
| Ctrl+Shift+T | Reopen closed tab |
| Ctrl+Tab, Ctrl+PgDown / Ctrl+Shift+Tab, Ctrl+PgUp | Next / previous tab |
| Ctrl+Shift+PgDown / PgUp | Move tab right / left |
| Ctrl+1 … Ctrl+8, Ctrl+9 (also Alt+n) | Tab n, last tab |
| Alt+Left / Alt+Right | Back / forward |
| Ctrl+R, F5 / Ctrl+Shift+R | Reload / reload without cache |
| Esc | Stop loading |
| Ctrl+F, then Enter / Shift+Enter, Ctrl+G | Find, next, previous |
| Ctrl+= / Ctrl+- / Ctrl+0 | Zoom in / out / reset |
| F11 | Full screen |
| Ctrl+U | View source |
| F12, Ctrl+Shift+I | DevTools |
| Ctrl+Shift+C | Copy page address |
| Ctrl+Q | Quit (session is saved) |

In the address palette, Up/Down or Ctrl+N/Ctrl+P pick a suggestion.

## Build and run

On Omarchy / Arch:

```bash
sudo pacman -S --needed rust qt6-base qt6-declarative qt6-webengine qt6-wayland
cd omarchy
make install           # builds release, installs to ~/.local
omaweb                 # or: make default-browser
```

Optional: [`data/hyprland.conf`](data/hyprland.conf) has a bind and a window
rule to copy into your Hyprland config; pick a key Omarchy isn't using.

cxx-qt finds Qt through `qmake6`/`qmake` on `PATH`, or `QMAKE=/path/to/qmake`.
`cargo test` runs the Rust tests (theme, address field, history, session,
config). `omaweb --theme` prints the palette it would use.

Environment overrides: `OMAWEB_THEME_DIR` (read a theme dir directly),
`OMAWEB_FONT`. Omaweb sets `QT_WAYLAND_DISABLE_WINDOWDECORATION=1`,
`QT_QPA_PLATFORMTHEME=gtk3` and the Basic Quick Controls style unless you
set them yourself.

## Not here yet

- Yab's iPhone and Android companions, sync, agents, ad blocking, reading
  mode, split view, Peek and password-manager integration. The companions
  stay in the upstream tree, untouched.
- Bookmarks (history and the start page cover most of it for now) and a
  settings screen (edit `config.toml`).
- Spaces, pinned favourites, tab folders (Yab's sidebar has them; Omaweb's
  sidebar shows the tab list only).
- Web extensions; Qt WebEngine has no Chrome extension support.
- Packaging. Nothing is published to the AUR.

## Credit and license

Omaweb is derived from Yab, © 2026 Serafim Korablev, Apache License 2.0
(itself a fork of Search by Office Commun, MIT). "Yab", "Yet Another
Browser" and Yab's icons are Serafim Korablev's trademarks and are not used
for this app; see [TRADEMARKS.md](../TRADEMARKS.md). Omaweb's own code is
under the same Apache License 2.0 ([LICENSE](../LICENSE), [NOTICE](../NOTICE)).
Built with Qt (LGPLv3), Qt WebEngine / Chromium, cxx-qt (MIT or Apache-2.0)
and the crates in `Cargo.lock`.
