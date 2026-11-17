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
    /// Today tabs (not pinned, not favorites) untouched for this many hours
    /// move to the archive, the way Arc's do. 0 keeps them forever.
    pub archive_after_hours: f64,
    /// Shift+click and pop-up windows open in a Peek card over the page.
    pub peek: bool,
    /// Darken pages that have no dark style of their own.
    pub force_dark: bool,
    /// Profile new spaces use, and the one `omaweb` opens without `--profile`.
    pub default_profile: String,
    pub blocker: BlockerConfig,
    pub agent: AgentConfig,
}

/// The built-in ad and tracker blocker.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct BlockerConfig {
    pub enabled: bool,
    /// Filter lists: hosts files or Adblock-style lists (only their
    /// `||domain^` rules are used). Fetched weekly into the cache.
    pub lists: Vec<String>,
    /// Sites where nothing is blocked.
    pub allow: Vec<String>,
}

impl Default for BlockerConfig {
    fn default() -> Self {
        BlockerConfig {
            enabled: true,
            lists: vec![
                "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext".into(),
            ],
            allow: Vec::new(),
        }
    }
}

/// The agent panel. Any OpenAI-compatible chat completions endpoint:
/// OpenAI, OpenRouter, xAI, Groq, a local Ollama or llama.cpp server.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct AgentConfig {
    /// Base URL; `/chat/completions` is appended unless it is already there.
    pub endpoint: String,
    pub model: String,
    /// Environment variable holding the API key.
    pub api_key_env: String,
    /// A command that prints the key, e.g. `pass show openai`.
    pub api_key_command: String,
    /// The key itself. Prefer the env var or the command: config.toml
    /// tends to end up in a dotfiles repo.
    #[serde(skip_serializing)]
    pub api_key: String,
    /// How much of the page's text goes with each question.
    pub max_page_chars: usize,
    /// Added to the built-in system prompt.
    pub instructions: String,
    /// Ask before the agent clicks or types on a page.
    pub confirm_actions: bool,
}

impl Default for AgentConfig {
    fn default() -> Self {
        AgentConfig {
            endpoint: "https://api.openai.com/v1".into(),
            model: "gpt-4o-mini".into(),
            api_key_env: "OMAWEB_AGENT_API_KEY".into(),
            api_key_command: String::new(),
            api_key: String::new(),
            max_page_chars: 12_000,
            instructions: String::new(),
            confirm_actions: true,
        }
    }
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
            archive_after_hours: 12.0,
            peek: true,
            force_dark: false,
            default_profile: "Default".into(),
            blocker: BlockerConfig::default(),
            agent: AgentConfig::default(),
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
                if !c.archive_after_hours.is_finite() || c.archive_after_hours < 0.0 {
                    c.archive_after_hours = 12.0;
                }
                if c.default_profile.trim().is_empty() {
                    c.default_profile = "Default".into();
                }
                c.agent.max_page_chars = c.agent.max_page_chars.clamp(500, 200_000);
                c
            }
            Err(e) => {
                eprintln!("omaweb: ignoring {}: {e}", path.display());
                Config::default()
            }
        }
    }
}

/// What the settings screen may write, and the TOML type each key takes.
fn setting_kind(key: &str) -> Option<&'static str> {
    Some(match key {
        "homepage" | "search" | "tabs" | "default_profile" => "str",
        "pin_sidebar" | "frameless" | "restore_session" | "compact" | "peek" | "force_dark" => "bool",
        "zoom" | "archive_after_hours" => "float",
        "blocker.enabled" | "agent.confirm_actions" => "bool",
        "blocker.lists" | "blocker.allow" => "list",
        "agent.endpoint" | "agent.model" | "agent.api_key_env" | "agent.api_key_command" | "agent.instructions" => "str",
        "agent.max_page_chars" => "int",
        _ => return None,
    })
}

/// Writes one setting into config.toml, keeping the file's comments and
/// layout (toml_edit), so a hand-written config survives the settings
/// screen. The API key itself is never written from the UI.
pub fn set_value(path: &Path, key: &str, value: &serde_json::Value) -> Result<(), String> {
    let kind = setting_kind(key).ok_or_else(|| format!("unknown setting {key}"))?;
    let text = fs::read_to_string(path).unwrap_or_default();
    let mut doc = text.parse::<toml_edit::DocumentMut>().map_err(|e| e.to_string())?;
    let item = match kind {
        "str" => toml_edit::value(value.as_str().ok_or("expected text")?),
        "bool" => toml_edit::value(value.as_bool().ok_or("expected true or false")?),
        "float" => toml_edit::value(value.as_f64().ok_or("expected a number")?),
        "int" => toml_edit::value(value.as_i64().ok_or("expected a whole number")?),
        _ => {
            let mut a = toml_edit::Array::new();
            for v in value.as_array().ok_or("expected a list")? {
                a.push(v.as_str().unwrap_or_default());
            }
            toml_edit::value(a)
        }
    };
    match key.split_once('.') {
        Some((table, k)) => {
            if !doc.contains_key(table) {
                doc[table] = toml_edit::table();
            }
            doc[table][k] = item;
        }
        None => doc[key] = item,
    }
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let out = doc.to_string();
    // Refuse to write something we could not read back.
    toml::from_str::<Config>(&out).map_err(|e| e.to_string())?;
    let tmp = path.with_extension("toml.tmp");
    fs::write(&tmp, out).map_err(|e| e.to_string())?;
    fs::rename(tmp, path).map_err(|e| e.to_string())
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

    #[test]
    fn new_sections_default_and_parse() {
        let c = Config::default();
        assert_eq!(c.archive_after_hours, 12.0);
        assert!(c.blocker.enabled);
        assert_eq!(c.agent.api_key_env, "OMAWEB_AGENT_API_KEY");
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("config.toml");
        fs::write(&p, "archive_after_hours = -3\n[agent]\nmodel = \"llama3\"\nendpoint = \"http://localhost:11434/v1\"\n[blocker]\nenabled = false\n").unwrap();
        let c = Config::load(&p);
        assert_eq!(c.archive_after_hours, 12.0);
        assert_eq!(c.agent.model, "llama3");
        assert_eq!(c.agent.api_key_env, "OMAWEB_AGENT_API_KEY");
        assert!(!c.blocker.enabled);
    }

    #[test]
    fn api_key_is_never_serialized() {
        let mut c = Config::default();
        c.agent.api_key = "sk-test-not-a-real-key".into();
        let json = serde_json::to_string(&c).unwrap();
        assert!(!json.contains("sk-test"));
    }

    #[test]
    fn set_value_keeps_comments() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("config.toml");
        fs::write(&p, "# mine\nzoom = 1.2 # big\n").unwrap();
        set_value(&p, "archive_after_hours", &serde_json::json!(24.0)).unwrap();
        set_value(&p, "agent.model", &serde_json::json!("gpt-4.1")).unwrap();
        set_value(&p, "blocker.allow", &serde_json::json!(["example.com"])).unwrap();
        let text = fs::read_to_string(&p).unwrap();
        assert!(text.contains("# mine") && text.contains("# big"));
        let c = Config::load(&p);
        assert_eq!(c.archive_after_hours, 24.0);
        assert_eq!(c.agent.model, "gpt-4.1");
        assert_eq!(c.blocker.allow, vec!["example.com".to_string()]);
        assert!(set_value(&p, "agent.api_key", &serde_json::json!("x")).is_err());
        assert!(set_value(&p, "zoom", &serde_json::json!("big")).is_err());
    }
}
