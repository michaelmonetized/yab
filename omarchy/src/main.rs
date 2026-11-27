//! Qi: a Rust + Qt Quick rewrite of Yab for Omarchy.

mod agent;
mod blocker;
mod bookmarks;
mod bridge;
mod chrome_import;
mod config;
mod extensions;
mod hide;
mod history;
mod ipc;
mod omnibox;
mod passwords;
mod paths;
mod profiles;
mod session;
mod theme;
mod workspace;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QString, QUrl};

const HELP: &str = "qi [URL|SEARCH]...

A keyboard-first browser for Omarchy. With a window already open, the
URLs open as tabs there.

  --theme     print the Omarchy theme Qi would use, then exit
  --private   open the URLs (or a blank tab) as private tabs
              (--incognito and --private-window work too)
  --profile NAME
              open in a space that uses profile NAME (made if new):
              its own cookies, history, bookmarks and extensions
  --new       start a separate instance even if one is running
  --version   print the version
  -h, --help  this text";

fn main() {
    let migrated = paths::migrate_legacy_dirs();
    let mut urls = Vec::new();
    let mut separate = false;
    let mut private = false;
    let mut profile = String::new();
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        if let Some(p) = a.strip_prefix("--profile=").or(a.strip_prefix("--profile-directory=")) {
            profile = p.to_string();
            continue;
        }
        match a.as_str() {
            "-h" | "--help" => {
                println!("{HELP}");
                return;
            }
            "--version" => {
                println!("qi {}", env!("CARGO_PKG_VERSION"));
                return;
            }
            "--theme" => {
                println!("{}", serde_json::to_string_pretty(&theme::load()).unwrap_or_default());
                return;
            }
            "--new" => separate = true,
            "--profile" | "--profile-directory" => profile = args.next().unwrap_or_default(),
            "--private" | "--incognito" | "--private-window" => private = true,
            _ => urls.push(a),
        }
    }

    if !separate && ipc::hand_off(&urls, private, &profile) {
        return;
    }
    if !migrated {
        eprintln!("qi: not starting until those folders can move");
        std::process::exit(1);
    }
    let _ = bridge::INITIAL_PROFILE.set(profile);
    let _ = bridge::INITIAL_URLS.set(urls);
    let _ = bridge::INITIAL_PRIVATE.set(private);

    // Hyprland draws no decorations and wants none drawn for it: no title
    // bar, no shadow margins, so the window tiles edge to edge.
    if std::env::var_os("QT_WAYLAND_DISABLE_WINDOWDECORATION").is_none() {
        std::env::set_var("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1");
    }
    if std::env::var_os("WAYLAND_DISPLAY").is_some() && std::env::var_os("QT_QPA_PLATFORM").is_none() {
        std::env::set_var("QT_QPA_PLATFORM", "wayland;xcb");
    }
    // The GTK platform theme honours Qt's colour-scheme request, which is
    // what carries the Omarchy light/dark mode into `prefers-color-scheme`.
    if std::env::var_os("QT_QPA_PLATFORMTHEME").is_none() {
        std::env::set_var("QT_QPA_PLATFORMTHEME", "gtk3");
    }
    if std::env::var_os("QT_QUICK_CONTROLS_STYLE").is_none() {
        std::env::set_var("QT_QUICK_CONTROLS_STYLE", "Basic");
    }

    bridge::qobject::init_webengine();
    bridge::qobject::set_desktop_file_name(&QString::from("qi"));

    let mut app = QGuiApplication::new();
    if let Some(mut app) = app.as_mut() {
        app.as_mut().set_application_name(&QString::from("qi"));
        app.as_mut().set_application_display_name(&QString::from("Qi"));
        app.as_mut().set_application_version(&QString::from(env!("CARGO_PKG_VERSION")));
        app.as_mut().set_organization_name(&QString::from("qi"));
    }
    let mut engine = QQmlApplicationEngine::new();
    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from("qrc:/qt/qml/app/qi/qml/Main.qml"));
    }
    let code = app.as_mut().map(|a| a.exec()).unwrap_or(1);
    bridge::shutdown();
    std::process::exit(code);
}
