//! The Rust side of the window: one `Browser` QObject that QML talks to.
//! Everything that is not drawing or the web engine itself lives here:
//! theme, config, profiles, the workspace (spaces, folders, favorites,
//! archive), history, bookmarks, the blocker's lists, the agent, Chrome
//! import, extensions from the Web Store, passwords, single instance.

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
        #[allow(clippy::too_many_arguments)]
        fn add_cookie(profile: &QString, name: &QString, value: &QString, domain: &QString, path: &QString, expires: i64, secure: bool, http_only: bool, same_site: i32);
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, theme_json, cxx_name = "themeJson")]
        #[qproperty(QString, config_json, cxx_name = "configJson")]
        #[qproperty(QString, initial_json, cxx_name = "initialJson")]
        #[qproperty(QString, profiles_json, cxx_name = "profilesJson")]
        type Browser = super::BrowserRust;

        #[qinvokable]
        fn start(self: Pin<&mut Self>);
        #[qinvokable]
        #[cxx_name = "reloadTheme"]
        fn reload_theme(self: Pin<&mut Self>);
        #[qinvokable]
        fn resolve(&self, input: &QString) -> QString;
        #[qinvokable]
        fn suggest(&self, input: &QString, profile: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "topSites"]
        fn top_sites(&self, profile: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "recordVisit"]
        fn record_visit(&self, profile: &QString, url: &QString, title: &QString);
        #[qinvokable]
        fn retitle(&self, profile: &QString, url: &QString, title: &QString);
        #[qinvokable]
        fn history(&self, profile: &QString, query: &QString, limit: i32) -> QString;
        #[qinvokable]
        #[cxx_name = "removeHistory"]
        fn remove_history(&self, profile: &QString, url: &QString);
        #[qinvokable]
        #[cxx_name = "clearHistory"]
        fn clear_history(&self, profile: &QString);

        #[qinvokable]
        #[cxx_name = "wsApply"]
        fn ws_apply(&self, ws: &QString, op: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "saveWorkspace"]
        fn save_workspace(&self, ws: &QString);
        #[qinvokable]
        fn now(&self) -> i64;

        #[qinvokable]
        fn bookmarks(&self, profile: &QString, query: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "addBookmark"]
        fn add_bookmark(&self, profile: &QString, url: &QString, title: &QString, folder: &QString) -> i64;
        #[qinvokable]
        #[cxx_name = "removeBookmark"]
        fn remove_bookmark(&self, profile: &QString, id: i64);
        #[qinvokable]
        #[cxx_name = "removeBookmarkUrl"]
        fn remove_bookmark_url(&self, profile: &QString, url: &QString);
        #[qinvokable]
        #[cxx_name = "isBookmarked"]
        fn is_bookmarked(&self, profile: &QString, url: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "addProfile"]
        fn add_profile(self: Pin<&mut Self>, name: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "removeProfile"]
        fn remove_profile(self: Pin<&mut Self>, name: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "setSetting"]
        fn set_setting(self: Pin<&mut Self>, key: &QString, value_json: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "configPath"]
        fn config_path(&self) -> QString;

        #[qinvokable]
        #[cxx_name = "refreshBlocklist"]
        fn refresh_blocklist(self: Pin<&mut Self>, force: bool);
        #[qinvokable]
        #[cxx_name = "hideCss"]
        fn hide_css(&self, host: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "hiddenRules"]
        fn hidden_rules(&self) -> QString;
        #[qinvokable]
        #[cxx_name = "addHideRule"]
        fn add_hide_rule(&self, host: &QString, selector: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "clearHideRules"]
        fn clear_hide_rules(&self, host: &QString);

        #[qinvokable]
        #[cxx_name = "agentStatus"]
        fn agent_status(&self) -> QString;
        #[qinvokable]
        #[cxx_name = "agentSend"]
        fn agent_send(self: Pin<&mut Self>, id: i32, messages: &QString, page: &QString, tools: bool);
        #[qinvokable]
        #[cxx_name = "agentWatch"]
        fn agent_watch(self: Pin<&mut Self>, id: i32, condition: &QString, page: &QString);
        #[qinvokable]
        #[cxx_name = "agentCancel"]
        fn agent_cancel(&self, id: i32);

        #[qinvokable]
        #[cxx_name = "storeId"]
        fn store_id(&self, input: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "extensionIcon"]
        fn extension_icon(&self, dir: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "isStorePage"]
        fn is_store_page(&self, url: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "fetchExtension"]
        fn fetch_extension(self: Pin<&mut Self>, profile: &QString, input: &QString);
        #[qinvokable]
        #[cxx_name = "loadedExtensions"]
        fn loaded_extensions(&self, profile: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "rememberUnpacked"]
        fn remember_unpacked(&self, profile: &QString, path: &QString, on: bool);
        #[qinvokable]
        #[cxx_name = "disabledExtensions"]
        fn disabled_extensions(&self, profile: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "rememberDisabled"]
        fn remember_disabled(&self, profile: &QString, id: &QString, disabled: bool);

        #[qinvokable]
        #[cxx_name = "chromeProfiles"]
        fn chrome_profiles(&self) -> QString;
        #[qinvokable]
        #[cxx_name = "importChrome"]
        fn import_chrome(self: Pin<&mut Self>, source: &QString, keyring_app: &QString, profile: &QString, what: &QString);

        #[qinvokable]
        #[cxx_name = "passwordsAvailable"]
        fn passwords_available(&self) -> bool;
        #[qinvokable]
        fn passwords(&self, profile: &QString, url: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "passwordFor"]
        fn password_for(&self, profile: &QString, url: &QString, username: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "savePassword"]
        fn save_password(&self, profile: &QString, url: &QString, username: &QString, password: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "removePassword"]
        fn remove_password(&self, profile: &QString, origin: &QString, username: &QString);

        #[qinvokable]
        fn notify(&self, summary: &QString, body: &QString);

        #[qsignal]
        #[cxx_name = "openRequested"]
        fn open_requested(self: Pin<&mut Self>, url: QString, is_private: bool, profile: QString);
        #[qsignal]
        #[cxx_name = "focusRequested"]
        fn focus_requested(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "agentDelta"]
        fn agent_delta(self: Pin<&mut Self>, id: i32, text: QString);
        #[qsignal]
        #[cxx_name = "agentFinished"]
        fn agent_finished(self: Pin<&mut Self>, id: i32, result: QString);
        #[qsignal]
        #[cxx_name = "agentFailed"]
        fn agent_failed(self: Pin<&mut Self>, id: i32, error: QString);
        #[qsignal]
        #[cxx_name = "extensionReady"]
        fn extension_ready(self: Pin<&mut Self>, profile: QString, dir: QString, name: QString, error: QString);
        #[qsignal]
        #[cxx_name = "importFinished"]
        fn import_finished(self: Pin<&mut Self>, profile: QString, report: QString);
        #[qsignal]
        #[cxx_name = "blocklistReady"]
        fn blocklist_ready(self: Pin<&mut Self>, path: QString, hosts: i32);
    }

    impl cxx_qt::Threading for Browser {}
}

use crate::agent::{self, PageContext};
use crate::bookmarks::{self, Bookmarks};
use crate::config::{self, Config};
use crate::history::History;
use crate::passwords;
use crate::profiles::{self, Profiles};
use crate::session::Session;
use crate::workspace::{self, TabRec, Workspace};
use crate::{chrome_import, extensions, hide, ipc, omnibox, paths, theme};
use core::pin::Pin;
use cxx_qt::Threading;
use cxx_qt_lib::QString;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

struct Core {
    config: Config,
    profiles: Profiles,
    histories: HashMap<String, History>,
    bookmarks: HashMap<String, Bookmarks>,
    cancels: HashMap<i32, Arc<AtomicBool>>,
}

impl Core {
    fn history(&mut self, profile: &str) -> &mut History {
        let p = if profile.is_empty() { profiles::DEFAULT } else { profile };
        self.histories.entry(p.to_string()).or_insert_with(|| History::open(profiles::history_path(p)))
    }
    fn bookmarks(&mut self, profile: &str) -> &mut Bookmarks {
        let p = if profile.is_empty() { profiles::DEFAULT } else { profile };
        self.bookmarks.entry(p.to_string()).or_insert_with(|| Bookmarks::open(profiles::bookmarks_path(p)))
    }
}

static CORE: OnceLock<Mutex<Core>> = OnceLock::new();
/// URLs given on the command line, set by `main` before Qt starts.
pub static INITIAL_URLS: OnceLock<Vec<String>> = OnceLock::new();
/// `--private` / `--incognito` / `--private-window` on the command line.
pub static INITIAL_PRIVATE: OnceLock<bool> = OnceLock::new();
/// `--profile <name>`.
pub static INITIAL_PROFILE: OnceLock<String> = OnceLock::new();

fn config_file() -> PathBuf {
    paths::config_dir().join("config.toml")
}

fn core() -> &'static Mutex<Core> {
    CORE.get_or_init(|| {
        let config = Config::load(&config_file());
        let mut profiles = Profiles::load();
        if profiles.get(&config.default_profile).is_none() {
            profiles.add(&config.default_profile);
            let _ = profiles.save();
        }
        Mutex::new(Core { config, profiles, histories: HashMap::new(), bookmarks: HashMap::new(), cancels: HashMap::new() })
    })
}

fn workspace_file() -> PathBuf {
    paths::state_dir().join("workspace.json")
}
fn hidden_file() -> PathBuf {
    paths::data_dir().join("hidden.json")
}
fn blocklist_file() -> PathBuf {
    paths::cache_dir().join("blocklist.txt")
}
fn unpacked_file(profile: &str) -> PathBuf {
    profiles::data_dir_of(profile).join("unpacked-extensions.json")
}

fn disabled_file(profile: &str) -> PathBuf {
    profiles::data_dir_of(profile).join("disabled-extensions.json")
}

fn qs(s: &str) -> QString {
    QString::from(s)
}

fn now_secs() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

#[derive(Default)]
pub struct BrowserRust {
    theme_json: QString,
    config_json: QString,
    initial_json: QString,
    profiles_json: QString,
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

/// The workspace to open with: last one (or the old session, migrated),
/// plus whatever the command line asked for.
fn initial_workspace(c: &mut Core) -> Workspace {
    let mut w = Workspace::load(&workspace_file()).unwrap_or_else(|| {
        let s = Session::load(&paths::state_dir().join("session.json")).sanitized();
        Workspace::from_session(&s, &c.config.default_profile)
    });
    if !c.config.restore_session {
        for s in &mut w.spaces {
            s.tabs.retain(|t| t.pinned);
        }
    }
    let profile = INITIAL_PROFILE.get().cloned().unwrap_or_default();
    if !profile.is_empty() {
        let name = c.profiles.add(&profile);
        let _ = c.profiles.save();
        match w.spaces.iter().find(|s| s.profile == name) {
            Some(s) => w.current_space = s.id.clone(),
            None => {
                let id = format!("s{}", now_secs());
                let n = w.spaces.len();
                w.spaces.push(workspace::new_space(&id, &name, &name, n));
                w.current_space = id;
            }
        }
        w.current_favorite.clear();
    }
    let private = INITIAL_PRIVATE.get().copied().unwrap_or(false);
    let cli: Vec<String> = INITIAL_URLS
        .get()
        .cloned()
        .unwrap_or_default()
        .iter()
        .map(|u| omnibox::resolve(u, &c.config))
        .filter(|u| !u.is_empty())
        .collect();
    let add = |w: &mut Workspace, url: String, i: usize| {
        let uid = format!("c{}-{i}", now_secs());
        let cur = w.current_space.clone();
        if let Some(s) = w.spaces.iter_mut().find(|s| s.id == cur) {
            s.tabs.push(TabRec { uid: uid.clone(), url, private, last_active: now_secs(), ..Default::default() });
            s.current = uid;
        }
        w.current_favorite.clear();
    };
    if !cli.is_empty() {
        for (i, u) in cli.into_iter().enumerate() {
            add(&mut w, u, i);
        }
    } else if private {
        add(&mut w, String::new(), 0);
    }
    let empty = w.favorites.is_empty() && w.spaces.iter().all(|s| s.tabs.is_empty());
    if empty {
        let home = c.config.homepage.clone();
        add(&mut w, home, 0);
    }
    for s in &w.spaces {
        c.profiles.add(&s.profile);
    }
    let _ = c.profiles.save();
    w.sanitized(false)
}

fn profiles_json(c: &Core) -> String {
    serde_json::to_string(&c.profiles.infos()).unwrap_or_else(|_| "[]".into())
}

fn page_of(json: &QString) -> Option<PageContext> {
    let s = json.to_string();
    if s.trim().is_empty() || s == "null" {
        return None;
    }
    serde_json::from_str(&s).ok()
}

impl qobject::Browser {
    pub fn start(mut self: Pin<&mut Self>) {
        let (config_json, initial, profiles) = {
            let mut c = core().lock().unwrap();
            let w = initial_workspace(&mut c);
            (serde_json::to_string(&c.config).unwrap_or_default(), serde_json::to_string(&w).unwrap_or_default(), profiles_json(&c))
        };
        self.as_mut().set_config_json(qs(&config_json));
        self.as_mut().set_profiles_json(qs(&profiles));
        self.as_mut().set_initial_json(qs(&initial));
        self.as_mut().reload_theme();

        // Single instance: later `omaweb <url>` calls land here.
        let qt = self.qt_thread();
        ipc::listen(move |url, private, profile| {
            let _ = qt.queue(move |mut b| {
                if url.is_empty() && !private && profile.is_empty() {
                    b.as_mut().focus_requested();
                } else {
                    let resolved = {
                        let c = core().lock().unwrap();
                        omnibox::resolve(&url, &c.config)
                    };
                    b.as_mut().open_requested(qs(&resolved), private, qs(&profile));
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
        let json = qs(&theme_to_json(&t));
        if *self.theme_json() != json {
            self.as_mut().set_theme_json(json);
        }
    }

    pub fn resolve(&self, input: &QString) -> QString {
        let c = core().lock().unwrap();
        qs(&omnibox::resolve(&input.to_string(), &c.config))
    }

    pub fn suggest(&self, input: &QString, profile: &QString) -> QString {
        let input = input.to_string();
        let profile = profile.to_string();
        let mut c = core().lock().unwrap();
        let mut out = Vec::new();
        let resolved = omnibox::resolve(&input, &c.config);
        if !resolved.is_empty() {
            let kind = if omnibox::as_url(input.trim()).is_some() { "go" } else { "search" };
            out.push(json!({ "url": resolved, "title": input.trim(), "kind": kind }));
        }
        let mut seen = vec![resolved.clone()];
        for b in c.bookmarks(&profile).search(&input, 3) {
            if !seen.contains(&b.url) {
                seen.push(b.url.clone());
                out.push(json!({ "url": b.url, "title": b.title, "kind": "bookmark" }));
            }
        }
        for e in c.history(&profile).suggest(&input, 7) {
            if !seen.contains(&e.url) {
                out.push(json!({ "url": e.url, "title": e.title, "kind": "history" }));
            }
        }
        qs(&Value::Array(out).to_string())
    }

    pub fn top_sites(&self, profile: &QString) -> QString {
        let mut c = core().lock().unwrap();
        qs(&serde_json::to_string(&c.history(&profile.to_string()).top(12)).unwrap_or_else(|_| "[]".into()))
    }

    pub fn record_visit(&self, profile: &QString, url: &QString, title: &QString) {
        let mut c = core().lock().unwrap();
        c.history(&profile.to_string()).record(&url.to_string(), &title.to_string());
    }

    pub fn retitle(&self, profile: &QString, url: &QString, title: &QString) {
        let mut c = core().lock().unwrap();
        c.history(&profile.to_string()).retitle(&url.to_string(), &title.to_string());
    }

    pub fn history(&self, profile: &QString, query: &QString, limit: i32) -> QString {
        let mut c = core().lock().unwrap();
        let list = c.history(&profile.to_string()).recent(&query.to_string(), limit.max(1) as usize);
        qs(&serde_json::to_string(&list).unwrap_or_else(|_| "[]".into()))
    }

    pub fn remove_history(&self, profile: &QString, url: &QString) {
        core().lock().unwrap().history(&profile.to_string()).remove(&url.to_string());
    }

    pub fn clear_history(&self, profile: &QString) {
        core().lock().unwrap().history(&profile.to_string()).clear();
    }

    pub fn ws_apply(&self, ws: &QString, op: &QString) -> QString {
        let w: Workspace = match serde_json::from_str(&ws.to_string()) {
            Ok(w) => w,
            Err(e) => return qs(&json!({ "error": e.to_string() }).to_string()),
        };
        let op: Value = serde_json::from_str(&op.to_string()).unwrap_or(Value::Null);
        match workspace::apply(w, &op) {
            Ok(w) => qs(&json!({ "ws": w }).to_string()),
            Err(e) => qs(&json!({ "error": e }).to_string()),
        }
    }

    pub fn save_workspace(&self, ws: &QString) {
        if let Ok(w) = serde_json::from_str::<Workspace>(&ws.to_string()) {
            let _ = w.save(&workspace_file());
        }
    }

    pub fn now(&self) -> i64 {
        now_secs() as i64
    }

    pub fn bookmarks(&self, profile: &QString, query: &QString) -> QString {
        let mut c = core().lock().unwrap();
        let b = c.bookmarks(&profile.to_string());
        let q = query.to_string();
        let list = if q.trim().is_empty() { b.items.clone() } else { b.search(&q, 500) };
        qs(&serde_json::to_string(&list).unwrap_or_else(|_| "[]".into()))
    }

    pub fn add_bookmark(&self, profile: &QString, url: &QString, title: &QString, folder: &QString) -> i64 {
        core().lock().unwrap().bookmarks(&profile.to_string()).add(&url.to_string(), &title.to_string(), &folder.to_string()) as i64
    }

    pub fn remove_bookmark(&self, profile: &QString, id: i64) {
        core().lock().unwrap().bookmarks(&profile.to_string()).remove(id.max(0) as u64);
    }

    pub fn remove_bookmark_url(&self, profile: &QString, url: &QString) {
        core().lock().unwrap().bookmarks(&profile.to_string()).remove_url(&url.to_string());
    }

    pub fn is_bookmarked(&self, profile: &QString, url: &QString) -> bool {
        core().lock().unwrap().bookmarks(&profile.to_string()).contains(&url.to_string())
    }

    pub fn add_profile(mut self: Pin<&mut Self>, name: &QString) -> QString {
        let (n, j) = {
            let mut c = core().lock().unwrap();
            let n = c.profiles.add(&name.to_string());
            let _ = c.profiles.save();
            (n, profiles_json(&c))
        };
        self.as_mut().set_profiles_json(qs(&j));
        qs(&n)
    }

    pub fn remove_profile(mut self: Pin<&mut Self>, name: &QString) -> bool {
        let (ok, j) = {
            let mut c = core().lock().unwrap();
            let ok = c.profiles.remove(&name.to_string());
            let _ = c.profiles.save();
            (ok, profiles_json(&c))
        };
        self.as_mut().set_profiles_json(qs(&j));
        ok
    }

    pub fn set_setting(mut self: Pin<&mut Self>, key: &QString, value_json: &QString) -> QString {
        let v: Value = match serde_json::from_str(&value_json.to_string()) {
            Ok(v) => v,
            Err(e) => return qs(&e.to_string()),
        };
        if let Err(e) = config::set_value(&config_file(), &key.to_string(), &v) {
            return qs(&e);
        }
        let j = {
            let mut c = core().lock().unwrap();
            c.config = Config::load(&config_file());
            serde_json::to_string(&c.config).unwrap_or_default()
        };
        self.as_mut().set_config_json(qs(&j));
        QString::default()
    }

    pub fn config_path(&self) -> QString {
        qs(&config_file().to_string_lossy())
    }

    pub fn refresh_blocklist(self: Pin<&mut Self>, force: bool) {
        let lists = core().lock().unwrap().config.blocker.lists.clone();
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            let out = blocklist_file();
            let (n, _) = crate::blocker::refresh(&lists, &paths::cache_dir().join("lists"), &out, force);
            let p = out.to_string_lossy().into_owned();
            let _ = qt.queue(move |b| b.blocklist_ready(qs(&p), n as i32));
        });
    }

    pub fn hide_css(&self, host: &QString) -> QString {
        qs(&hide::css_for(&hide::load(&hidden_file()), &host.to_string()))
    }

    pub fn hidden_rules(&self) -> QString {
        qs(&serde_json::to_string(&hide::load(&hidden_file())).unwrap_or_else(|_| "{}".into()))
    }

    pub fn add_hide_rule(&self, host: &QString, selector: &QString) -> bool {
        let mut r = hide::load(&hidden_file());
        let ok = hide::add(&mut r, &host.to_string(), &selector.to_string());
        if ok {
            hide::save(&hidden_file(), &r);
        }
        ok
    }

    pub fn clear_hide_rules(&self, host: &QString) {
        let mut r = hide::load(&hidden_file());
        r.remove(&hide::host_key(&host.to_string()));
        hide::save(&hidden_file(), &r);
    }

    pub fn agent_status(&self) -> QString {
        let cfg = core().lock().unwrap().config.agent.clone();
        let (_, src) = agent::resolve_key(&cfg, &|k| std::env::var(k).ok());
        let (ready, source) = match &src {
            agent::KeySource::Env(v) => (true, format!("env:{v}")),
            agent::KeySource::Command => (true, "api_key_command".into()),
            agent::KeySource::Config => (true, "config api_key".into()),
            agent::KeySource::NotNeeded => (true, "none needed (local server)".into()),
            agent::KeySource::Missing => (false, String::new()),
        };
        qs(&json!({ "ready": ready, "keySource": source, "endpoint": cfg.endpoint, "model": cfg.model,
            "envVar": cfg.api_key_env, "confirmActions": cfg.confirm_actions }).to_string())
    }

    pub fn agent_send(self: Pin<&mut Self>, id: i32, messages: &QString, page: &QString, tools: bool) {
        let msgs: Vec<Value> = serde_json::from_str(&messages.to_string()).unwrap_or_default();
        let page = page_of(page);
        let body = {
            let c = core().lock().unwrap();
            agent::build_request(&c.config.agent, &msgs, page.as_ref(), tools, true)
        };
        self.run_agent(id, body);
    }

    pub fn agent_watch(self: Pin<&mut Self>, id: i32, condition: &QString, page: &QString) {
        let Some(page) = page_of(page) else { return };
        let body = {
            let c = core().lock().unwrap();
            agent::build_watch_request(&c.config.agent, &condition.to_string(), &page)
        };
        self.run_agent(id, body);
    }

    fn run_agent(self: Pin<&mut Self>, id: i32, body: Value) {
        let cancel = Arc::new(AtomicBool::new(false));
        let cfg = {
            let mut c = core().lock().unwrap();
            c.cancels.insert(id, cancel.clone());
            c.config.agent.clone()
        };
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            let (key, src) = agent::resolve_key(&cfg, &|k| std::env::var(k).ok());
            if src == agent::KeySource::Missing {
                let msg = format!("No API key. Set {} in your environment (or api_key_command in config.toml), or point the agent at a local server.", cfg.api_key_env);
                let _ = qt.queue(move |b| b.agent_failed(id, qs(&msg)));
                return;
            }
            let q2 = qt.clone();
            let res = agent::send(&cfg, key.as_deref(), &body, cancel.clone(), |t| {
                let t = t.to_string();
                let _ = q2.queue(move |b| b.agent_delta(id, qs(&t)));
            });
            core().lock().unwrap().cancels.remove(&id);
            match res {
                Ok(s) => {
                    let out = json!({ "text": s.text, "calls": s.calls, "cancelled": cancel.load(Ordering::Relaxed) }).to_string();
                    let _ = qt.queue(move |b| b.agent_finished(id, qs(&out)));
                }
                Err(e) => {
                    let _ = qt.queue(move |b| b.agent_failed(id, qs(&e)));
                }
            }
        });
    }

    pub fn agent_cancel(&self, id: i32) {
        if let Some(c) = core().lock().unwrap().cancels.get(&id) {
            c.store(true, Ordering::Relaxed);
        }
    }

    pub fn store_id(&self, input: &QString) -> QString {
        qs(&extensions::store_id(&input.to_string()).unwrap_or_default())
    }

    pub fn extension_icon(&self, dir: &QString) -> QString {
        qs(&extensions::icon_path(std::path::Path::new(&dir.to_string())).map(|p| format!("file://{}", p.display())).unwrap_or_default())
    }

    pub fn is_store_page(&self, url: &QString) -> bool {
        extensions::is_store_page(&url.to_string())
    }

    /// A Web Store id or link, or a local .crx/.zip/folder.
    pub fn fetch_extension(self: Pin<&mut Self>, profile: &QString, input: &QString) {
        let profile = profile.to_string();
        let input = input.to_string();
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            let root = profiles::extensions_src_dir(&profile);
            let local = input.strip_prefix("file://").unwrap_or(&input).to_string();
            let res = if std::path::Path::new(&local).exists() {
                extensions::from_file(std::path::Path::new(&local), &root)
            } else {
                match extensions::store_id(&input) {
                    Some(id) => extensions::fetch_store(&id, &root),
                    None => Err("That isn't a Chrome Web Store link, an extension id, or a .crx/.zip file".into()),
                }
            };
            let (dir, name, err) = match res {
                Ok((d, n)) => (d.to_string_lossy().into_owned(), n, String::new()),
                Err(e) => (String::new(), String::new(), e),
            };
            let _ = qt.queue(move |b| b.extension_ready(qs(&profile), qs(&dir), qs(&name), qs(&err)));
        });
    }

    /// Unpacked (developer) extensions to load again at start.
    pub fn loaded_extensions(&self, profile: &QString) -> QString {
        let p = unpacked_file(&profile.to_string());
        qs(&std::fs::read_to_string(p).unwrap_or_else(|_| "[]".into()))
    }

    pub fn remember_unpacked(&self, profile: &QString, path: &QString, on: bool) {
        let _ = extensions::set_in_list(&unpacked_file(&profile.to_string()), &path.to_string(), on);
    }

    /// Qt WebEngine doesn't keep an extension's on/off across restarts, so
    /// Omaweb keeps the ids switched off and turns the rest back on.
    pub fn disabled_extensions(&self, profile: &QString) -> QString {
        qs(&serde_json::to_string(&extensions::read_list(&disabled_file(&profile.to_string()))).unwrap_or_else(|_| "[]".into()))
    }

    pub fn remember_disabled(&self, profile: &QString, id: &QString, disabled: bool) {
        let _ = extensions::set_in_list(&disabled_file(&profile.to_string()), &id.to_string(), disabled);
    }

    pub fn chrome_profiles(&self) -> QString {
        qs(&serde_json::to_string(&chrome_import::find_profiles(&paths::user_config_home())).unwrap_or_else(|_| "[]".into()))
    }

    /// `what`: {"bookmarks":true,"history":true,"cookies":true,"passwords":true,"extensions":true}
    pub fn import_chrome(self: Pin<&mut Self>, source: &QString, keyring_app: &QString, profile: &QString, what: &QString) {
        let src = PathBuf::from(source.to_string());
        let app = keyring_app.to_string();
        let profile = profile.to_string();
        let what: Value = serde_json::from_str(&what.to_string()).unwrap_or_else(|_| json!({}));
        let want = move |k: &str| what.get(k).and_then(Value::as_bool).unwrap_or(true);
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            let mut report = serde_json::Map::new();
            let mut notes: Vec<String> = Vec::new();
            let (keys, keyring) = chrome_import::keys_for(&app);
            if !keyring {
                notes.push("The Secret Service password for this browser couldn't be read (no keyring running, or it is locked), so only values Chrome encrypted with its built-in key (v10) could be decrypted; v11 cookies and passwords stay behind.".into());
            }
            if want("bookmarks") {
                let label = src.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
                match bookmarks::parse_chrome(&src.join("Bookmarks"), &format!("Imported ({label})")) {
                    Ok(list) => {
                        let n = core().lock().unwrap().bookmarks(&profile).import(list);
                        report.insert("bookmarks".into(), json!(n));
                    }
                    Err(e) => notes.push(format!("Bookmarks: {e}")),
                }
            }
            if want("history") {
                match chrome_import::read_history(&src, 20_000) {
                    Ok(v) => {
                        let n = core().lock().unwrap().history(&profile).import(v);
                        report.insert("historyVisits".into(), json!(n));
                    }
                    Err(e) => notes.push(format!("History: {e}")),
                }
            }
            if want("cookies") {
                match chrome_import::read_cookies(&src, &keys) {
                    Ok((cookies, failed)) => {
                        report.insert("cookies".into(), json!(cookies.len()));
                        report.insert("cookiesNotDecrypted".into(), json!(failed));
                        let p = profile.clone();
                        let _ = qt.queue(move |_b| {
                            for c in cookies {
                                qobject::add_cookie(&qs(&p), &qs(&c.name), &qs(&c.value), &qs(&c.domain), &qs(&c.path), c.expires as i64, c.secure, c.http_only, c.same_site as i32);
                            }
                        });
                    }
                    Err(e) => notes.push(format!("Cookies: {e}")),
                }
            }
            if want("passwords") {
                match chrome_import::read_logins(&src, &keys) {
                    Ok((logins, failed)) => {
                        report.insert("passwordsNotDecrypted".into(), json!(failed));
                        if !logins.is_empty() && !passwords::available() {
                            notes.push(format!("{} passwords were decrypted but not kept: Omaweb keeps passwords only in the Secret Service, and secret-tool (libsecret) isn't installed.", logins.len()));
                            report.insert("passwords".into(), json!(0));
                        } else {
                            let store = passwords::Store::new(&profile, profiles::passwords_index_path(&profile));
                            let mut n = 0;
                            for l in logins {
                                match store.save(&l.origin, &l.username, &l.password) {
                                    Ok(()) => n += 1,
                                    Err(e) => {
                                        notes.push(format!("Passwords: {e}"));
                                        break;
                                    }
                                }
                            }
                            report.insert("passwords".into(), json!(n));
                        }
                    }
                    Err(e) => notes.push(format!("Passwords: {e}")),
                }
            }
            if want("extensions") {
                let root = profiles::extensions_src_dir(&profile);
                let mut dirs = Vec::new();
                for (id, dir) in chrome_import::find_extensions(&src) {
                    let dst = root.join(&id);
                    if chrome_import::copy_extension(&dir, &dst).is_ok() {
                        dirs.push(dst.to_string_lossy().into_owned());
                    }
                }
                report.insert("extensionDirs".into(), json!(dirs));
            }
            notes.push("Open tabs, saved payment cards, autofill addresses, site settings and sync can't come across.".into());
            report.insert("notes".into(), json!(notes));
            let out = Value::Object(report).to_string();
            let _ = qt.queue(move |b| b.import_finished(qs(&profile), qs(&out)));
        });
    }

    pub fn passwords_available(&self) -> bool {
        passwords::available()
    }

    pub fn passwords(&self, profile: &QString, url: &QString) -> QString {
        let p = profile.to_string();
        let store = passwords::Store::new(&p, profiles::passwords_index_path(&p));
        let u = url.to_string();
        let list = if u.is_empty() { store.list() } else { store.for_site(&u) };
        qs(&serde_json::to_string(&list).unwrap_or_else(|_| "[]".into()))
    }

    pub fn password_for(&self, profile: &QString, url: &QString, username: &QString) -> QString {
        let p = profile.to_string();
        let store = passwords::Store::new(&p, profiles::passwords_index_path(&p));
        let u = url.to_string();
        let user = username.to_string();
        let found = store.lookup(&u, &user).or_else(|| store.for_site(&u).into_iter().find(|e| e.username == user).and_then(|e| store.lookup(&e.origin, &user)));
        qs(&found.unwrap_or_default())
    }

    pub fn save_password(&self, profile: &QString, url: &QString, username: &QString, password: &QString) -> QString {
        let p = profile.to_string();
        let store = passwords::Store::new(&p, profiles::passwords_index_path(&p));
        match store.save(&url.to_string(), &username.to_string(), &password.to_string()) {
            Ok(()) => QString::default(),
            Err(e) => qs(&e),
        }
    }

    pub fn remove_password(&self, profile: &QString, origin: &QString, username: &QString) {
        let p = profile.to_string();
        passwords::Store::new(&p, profiles::passwords_index_path(&p)).remove(&origin.to_string(), &username.to_string());
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

