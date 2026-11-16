//! The Rust side of the window: one `Browser` QObject that QML talks to.
//! Everything that is not drawing or the web engine itself lives here:
//! theme, config, address resolution, history, session, single instance.

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[namespace = "omaweb"]
    unsafe extern "C++" {
        include!("platform.h");
        fn init_webengine();
        fn set_desktop_file_name(name: &QString);
        fn set_color_scheme(dark: bool);
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, theme_json, cxx_name = "themeJson")]
        #[qproperty(QString, config_json, cxx_name = "configJson")]
        #[qproperty(QString, initial_json, cxx_name = "initialJson")]
        type Browser = super::BrowserRust;

        #[qinvokable]
        fn start(self: Pin<&mut Self>);

        #[qinvokable]
        #[cxx_name = "reloadTheme"]
        fn reload_theme(self: Pin<&mut Self>);

        #[qinvokable]
        fn resolve(&self, input: &QString) -> QString;

        #[qinvokable]
        fn suggest(&self, input: &QString) -> QString;

        #[qinvokable]
        #[cxx_name = "topSites"]
        fn top_sites(&self) -> QString;

        #[qinvokable]
        #[cxx_name = "recordVisit"]
        fn record_visit(&self, url: &QString, title: &QString);

        #[qinvokable]
        fn retitle(&self, url: &QString, title: &QString);

        #[qinvokable]
        #[cxx_name = "saveSession"]
        fn save_session(&self, json: &QString);

        #[qinvokable]
        fn notify(&self, summary: &QString, body: &QString);

        #[qsignal]
        #[cxx_name = "openRequested"]
        fn open_requested(self: Pin<&mut Self>, url: QString, is_private: bool);

        #[qsignal]
        #[cxx_name = "focusRequested"]
        fn focus_requested(self: Pin<&mut Self>);
    }

    impl cxx_qt::Threading for Browser {}
}

use crate::config::Config;
use crate::history::History;
use crate::session::{Session, SessionTab};
use crate::{ipc, omnibox, paths, theme};
use core::pin::Pin;
use cxx_qt::Threading;
use cxx_qt_lib::QString;
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

struct Core {
    config: Config,
    history: History,
}

static CORE: OnceLock<Mutex<Core>> = OnceLock::new();
/// URLs given on the command line, set by `main` before Qt starts.
pub static INITIAL_URLS: OnceLock<Vec<String>> = OnceLock::new();
/// `--private` / `--incognito` / `--private-window` on the command line.
pub static INITIAL_PRIVATE: OnceLock<bool> = OnceLock::new();

fn core() -> &'static Mutex<Core> {
    CORE.get_or_init(|| {
        let config = Config::load(&paths::config_dir().join("config.toml"));
        let history = History::open(paths::data_dir().join("history.jsonl"));
        Mutex::new(Core { config, history })
    })
}

#[derive(Default)]
pub struct BrowserRust {
    theme_json: QString,
    config_json: QString,
    initial_json: QString,
}

fn theme_to_json(t: &theme::Theme) -> String {
    serde_json::to_string(t).unwrap_or_else(|_| "{}".into())
}

/// What decides whether the theme changed: cheap to compute every poll.
fn theme_fingerprint() -> String {
    let mut fp = String::new();
    for dir in theme::theme_dirs() {
        fp.push_str(&format!("{:?}", std::fs::read_link(&dir).ok()));
        if let Some(parent) = dir.parent() {
            fp.push_str(&std::fs::read_to_string(parent.join("theme.name")).unwrap_or_default());
        }
        for f in ["colors.toml", "alacritty.toml", "light.mode"] {
            let m = std::fs::metadata(dir.join(f)).and_then(|m| m.modified()).ok();
            fp.push_str(&format!("{m:?}"));
        }
    }
    let fc = paths::user_config_home().join("fontconfig/fonts.conf");
    fp.push_str(&format!("{:?}", std::fs::metadata(fc).and_then(|m| m.modified()).ok()));
    fp
}

impl qobject::Browser {
    pub fn start(mut self: Pin<&mut Self>) {
        let (config_json, initial) = {
            let c = core().lock().unwrap();
            let mut tabs: Vec<SessionTab> = Vec::new();
            let mut current = 0;
            let cli: Vec<String> = INITIAL_URLS
                .get()
                .cloned()
                .unwrap_or_default()
                .iter()
                .map(|u| omnibox::resolve(u, &c.config))
                .filter(|u| !u.is_empty())
                .collect();
            if c.config.restore_session {
                let s = Session::load(&paths::state_dir().join("session.json")).sanitized();
                current = s.current;
                tabs = s.tabs;
            }
            let private = INITIAL_PRIVATE.get().copied().unwrap_or(false);
            if !cli.is_empty() {
                current = tabs.len();
                tabs.extend(cli.into_iter().map(|url| SessionTab { url, title: String::new(), private }));
            } else if private {
                current = tabs.len();
                tabs.push(SessionTab { url: String::new(), title: String::new(), private });
            }
            if tabs.is_empty() {
                tabs.push(SessionTab { url: c.config.homepage.clone(), title: String::new(), private: false });
            }
            let initial = Session { tabs, current };
            (
                serde_json::to_string(&c.config).unwrap_or_default(),
                serde_json::to_string(&initial).unwrap_or_default(),
            )
        };
        self.as_mut().set_config_json(QString::from(&config_json));
        self.as_mut().set_initial_json(QString::from(&initial));
        self.as_mut().reload_theme();

        // Single instance: later `omaweb <url>` calls land here.
        let qt = self.qt_thread();
        ipc::listen(move |url, private| {
            let _ = qt.queue(move |mut b| {
                if url.is_empty() && !private {
                    b.as_mut().focus_requested();
                } else {
                    let resolved = {
                        let c = core().lock().unwrap();
                        omnibox::resolve(&url, &c.config)
                    };
                    b.as_mut().open_requested(QString::from(&resolved), private);
                    b.as_mut().focus_requested();
                }
            });
        });

        // Live theme: inotify on Omarchy's `current` dirs, plus a slow poll
        // as a safety net for filesystems where inotify misses a swap.
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            use notify::{RecursiveMode, Watcher};
            let (tx, rx) = std::sync::mpsc::channel::<()>();
            let mut watcher = notify::recommended_watcher(move |_res: notify::Result<notify::Event>| {
                let _ = tx.send(());
            })
            .ok();
            let mut watched: Vec<std::path::PathBuf> = Vec::new();
            let mut last = theme_fingerprint();
            loop {
                if let Some(w) = watcher.as_mut() {
                    for p in theme::watch_paths() {
                        if !watched.contains(&p) && w.watch(&p, RecursiveMode::NonRecursive).is_ok() {
                            watched.push(p);
                        }
                    }
                }
                let got = rx.recv_timeout(Duration::from_secs(3)).is_ok();
                if got {
                    // Let Omarchy finish writing the theme before reading it.
                    std::thread::sleep(Duration::from_millis(250));
                    while rx.try_recv().is_ok() {}
                    watched.retain(|p| p.exists());
                }
                let fp = theme_fingerprint();
                if fp != last {
                    last = fp;
                    if qt.queue(|b| b.reload_theme()).is_err() {
                        break;
                    }
                }
            }
        });
    }

    pub fn reload_theme(mut self: Pin<&mut Self>) {
        let t = theme::load();
        qobject::set_color_scheme(t.dark);
        let json = QString::from(&theme_to_json(&t));
        if *self.theme_json() != json {
            self.as_mut().set_theme_json(json);
        }
    }

    pub fn resolve(&self, input: &QString) -> QString {
        let c = core().lock().unwrap();
        QString::from(&omnibox::resolve(&input.to_string(), &c.config))
    }

    pub fn suggest(&self, input: &QString) -> QString {
        let input = input.to_string();
        let c = core().lock().unwrap();
        let mut out = Vec::new();
        let resolved = omnibox::resolve(&input, &c.config);
        if !resolved.is_empty() {
            let kind = if omnibox::as_url(input.trim()).is_some() { "go" } else { "search" };
            out.push(serde_json::json!({ "url": resolved, "title": input.trim(), "kind": kind }));
        }
        for e in c.history.suggest(&input, 7) {
            if e.url != resolved {
                out.push(serde_json::json!({ "url": e.url, "title": e.title, "kind": "history" }));
            }
        }
        QString::from(&serde_json::Value::Array(out).to_string())
    }

    pub fn top_sites(&self) -> QString {
        let c = core().lock().unwrap();
        QString::from(&serde_json::to_string(&c.history.top(12)).unwrap_or_else(|_| "[]".into()))
    }

    pub fn record_visit(&self, url: &QString, title: &QString) {
        let mut c = core().lock().unwrap();
        c.history.record(&url.to_string(), &title.to_string());
    }

    pub fn retitle(&self, url: &QString, title: &QString) {
        let mut c = core().lock().unwrap();
        c.history.retitle(&url.to_string(), &title.to_string());
    }

    pub fn save_session(&self, json: &QString) {
        if let Ok(s) = serde_json::from_str::<Session>(&json.to_string()) {
            let _ = s.sanitized().save(&paths::state_dir().join("session.json"));
        }
    }

    /// Desktop notification through mako (Omarchy's notifier) via notify-send.
    pub fn notify(&self, summary: &QString, body: &QString) {
        let _ = std::process::Command::new("notify-send")
            .args(["-a", "Omaweb", &summary.to_string(), &body.to_string()])
            .spawn();
    }
}

pub fn shutdown() {
    ipc::cleanup();
}
