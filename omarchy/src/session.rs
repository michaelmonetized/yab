//! Last session's tabs, restored on launch like Yab does.

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Session {
    pub tabs: Vec<SessionTab>,
    pub current: usize,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct SessionTab {
    pub url: String,
    #[serde(default)]
    pub title: String,
    /// Only ever set for tabs opened from the command line; never saved.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub private: bool,
}

impl Session {
    pub fn load(path: &Path) -> Session {
        fs::read_to_string(path)
            .ok()
            .and_then(|t| serde_json::from_str(&t).ok())
            .unwrap_or_default()
    }

    #[cfg_attr(not(test), allow(dead_code))]
    pub fn save(&self, path: &Path) -> std::io::Result<()> {
        if let Some(dir) = path.parent() {
            crate::paths::create_dir_all(dir)?;
        }
        let tmp = path.with_extension("json.tmp");
        fs::write(&tmp, serde_json::to_string_pretty(self)?)?;
        fs::rename(tmp, path)
    }

    /// Drops private and blank tabs; keeps `current` in range.
    pub fn sanitized(mut self) -> Session {
        self.tabs.retain(|t| !t.private && !t.url.is_empty() && t.url != "about:blank");
        if self.current >= self.tabs.len() {
            self.current = self.tabs.len().saturating_sub(1);
        }
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("s/session.json");
        let s = Session {
            tabs: vec![
                SessionTab { url: "https://omarchy.org".into(), title: "Omarchy".into(), private: false },
                SessionTab { url: "about:blank".into(), title: String::new(), private: false },
            ],
            current: 1,
        };
        s.save(&p).unwrap();
        let back = Session::load(&p).sanitized();
        assert_eq!(back.tabs.len(), 1);
        assert_eq!(back.current, 0);
    }
}
