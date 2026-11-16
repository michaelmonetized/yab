//! `~/.config/omaweb/config.toml`. Every key is optional.

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct Config {
    /// Page a new window opens with when there is no session to restore.
    /// Empty means the built-in start page.
    pub homepage: String,
    /// Search URL; `{}` is replaced with the escaped query.
    pub search: String,
    /// `"sidebar"` (default: Yab-style tab sidebar, hidden until you reach
    /// for it, no toolbar) or `"top"` (classic tab strip and address bar).
    /// `"left"` is read as `"sidebar"`.
    pub tabs: String,
    /// Keep the sidebar open instead of revealing it on demand.
    pub pin_sidebar: bool,
    /// No window frame or title bar.
    pub frameless: bool,
    /// Bring back last session's tabs on launch.
    pub restore_session: bool,
    /// `tabs = "top"` only: start with the tab strip and toolbar hidden
    /// (toggle with Ctrl+Shift+B).
    pub compact: bool,
    /// Keyword searches: `gh rune` searches GitHub for "rune".
    pub keywords: BTreeMap<String, String>,
    /// Default page zoom, 1.0 = 100 %.
    pub zoom: f64,
}

impl Default for Config {
    fn default() -> Self {
        let mut keywords = BTreeMap::new();
        for (k, v) in [
            ("g", "https://www.google.com/search?q={}"),
            ("ddg", "https://duckduckgo.com/?q={}"),
            ("gh", "https://github.com/search?q={}"),
            ("yt", "https://www.youtube.com/results?search_query={}"),
            ("w", "https://en.wikipedia.org/w/index.php?search={}"),
            ("aw", "https://wiki.archlinux.org/index.php?search={}"),
            ("aur", "https://aur.archlinux.org/packages?K={}"),
            ("pkg", "https://archlinux.org/packages/?q={}"),
            ("crates", "https://crates.io/search?q={}"),
            ("hypr", "https://wiki.hypr.land/?q={}"),
        ] {
            keywords.insert(k.to_string(), v.to_string());
        }
        Config {
            homepage: String::new(),
            search: "https://duckduckgo.com/?q={}".to_string(),
            tabs: "sidebar".to_string(),
            pin_sidebar: false,
            frameless: true,
            restore_session: true,
            compact: false,
            keywords,
            zoom: 1.0,
        }
    }
}

impl Config {
    pub fn load(path: &Path) -> Config {
        let Ok(text) = fs::read_to_string(path) else {
            return Config::default();
        };
        match toml::from_str::<Config>(&text) {
            Ok(mut c) => {
                // User keywords extend the defaults rather than replace them.
                let mut merged = Config::default().keywords;
                merged.append(&mut c.keywords);
                c.keywords = merged;
                if c.tabs != "top" {
                    c.tabs = "sidebar".into();
                }
                if !(0.25..=5.0).contains(&c.zoom) {
                    c.zoom = 1.0;
                }
                c
            }
            Err(e) => {
                eprintln!("omaweb: ignoring {}: {e}", path.display());
                Config::default()
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn partial_config_keeps_defaults() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("config.toml");
        fs::write(&p, "tabs = \"left\"\n[keywords]\nrs = \"https://docs.rs/{}\"\n").unwrap();
        let c = Config::load(&p);
        assert_eq!(c.tabs, "sidebar");
        assert!(!c.pin_sidebar);
        assert!(c.frameless);
        assert!(c.restore_session);
        assert_eq!(c.keywords["rs"], "https://docs.rs/{}");
        assert!(c.keywords.contains_key("gh"));
    }

    #[test]
    fn default_is_chromeless() {
        let c = Config::default();
        assert_eq!(c.tabs, "sidebar");
        assert!(c.frameless);
        assert!(!c.pin_sidebar);
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("config.toml");
        fs::write(&p, "tabs = \"top\"\nframeless = false\npin_sidebar = true\n").unwrap();
        let c = Config::load(&p);
        assert_eq!(c.tabs, "top");
        assert!(!c.frameless);
        assert!(c.pin_sidebar);
    }

    #[test]
    fn bad_config_falls_back() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("config.toml");
        fs::write(&p, "tabs = [").unwrap();
        assert_eq!(Config::load(&p), Config::default());
    }
}
