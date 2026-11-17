//! Bookmarks, one file per profile (`bookmarks.json`), in folders. Chrome's
//! bookmarks come in as a folder of their own.

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct Bookmark {
    pub id: u64,
    pub url: String,
    pub title: String,
    /// Folder path, "/"-separated, empty for the top level.
    pub folder: String,
    pub added: u64,
}

#[derive(Debug, Default)]
pub struct Bookmarks {
    path: Option<PathBuf>,
    pub items: Vec<Bookmark>,
    next: u64,
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

impl Bookmarks {
    pub fn open(path: PathBuf) -> Bookmarks {
        let items: Vec<Bookmark> = fs::read_to_string(&path).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default();
        let next = items.iter().map(|b| b.id).max().unwrap_or(0) + 1;
        Bookmarks { path: Some(path), items, next }
    }

    fn save(&self) {
        let Some(p) = &self.path else { return };
        if let Some(d) = p.parent() {
            let _ = fs::create_dir_all(d);
        }
        let tmp = p.with_extension("json.tmp");
        if fs::write(&tmp, serde_json::to_string_pretty(&self.items).unwrap_or_default()).is_ok() {
            let _ = fs::rename(tmp, p);
        }
    }

    pub fn contains(&self, url: &str) -> bool {
        self.items.iter().any(|b| b.url == url)
    }

    /// Adds, or (for a URL already kept) retitles and moves.
    pub fn add(&mut self, url: &str, title: &str, folder: &str) -> u64 {
        let folder = folder.trim_matches('/').to_string();
        if let Some(b) = self.items.iter_mut().find(|b| b.url == url) {
            if !title.is_empty() {
                b.title = title.into();
            }
            b.folder = folder;
            let id = b.id;
            self.save();
            return id;
        }
        let id = self.next;
        self.next += 1;
        self.items.push(Bookmark { id, url: url.into(), title: title.into(), folder, added: now() });
        self.save();
        id
    }

    pub fn remove(&mut self, id: u64) -> bool {
        let before = self.items.len();
        self.items.retain(|b| b.id != id);
        let changed = before != self.items.len();
        if changed {
            self.save();
        }
        changed
    }

    pub fn remove_url(&mut self, url: &str) -> bool {
        let before = self.items.len();
        self.items.retain(|b| b.url != url);
        let changed = before != self.items.len();
        if changed {
            self.save();
        }
        changed
    }

    pub fn search(&self, q: &str, limit: usize) -> Vec<Bookmark> {
        let words: Vec<String> = q.to_lowercase().split_whitespace().map(String::from).collect();
        if words.is_empty() {
            return Vec::new();
        }
        self.items
            .iter()
            .filter(|b| {
                let hay = format!("{} {} {}", b.url, b.title, b.folder).to_lowercase();
                words.iter().all(|w| hay.contains(w.as_str()))
            })
            .take(limit)
            .cloned()
            .collect()
    }

    /// Imports many at once (skipping URLs already kept). Returns how many.
    pub fn import(&mut self, list: Vec<(String, String, String)>) -> usize {
        let mut n = 0;
        for (url, title, folder) in list {
            if url.is_empty() || self.contains(&url) {
                continue;
            }
            let id = self.next;
            self.next += 1;
            self.items.push(Bookmark { id, url, title, folder: folder.trim_matches('/').into(), added: now() });
            n += 1;
        }
        if n > 0 {
            self.save();
        }
        n
    }
}

/// Reads Chrome's `Bookmarks` JSON: roots bookmark_bar, other, synced.
/// Each comes back as (url, title, folder path under `prefix`).
pub fn parse_chrome(path: &Path, prefix: &str) -> Result<Vec<(String, String, String)>, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let v: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    let mut out = Vec::new();
    fn walk(node: &serde_json::Value, folder: &str, out: &mut Vec<(String, String, String)>) {
        let name = node.get("name").and_then(|n| n.as_str()).unwrap_or("");
        match node.get("type").and_then(|t| t.as_str()) {
            Some("url") => {
                if let Some(u) = node.get("url").and_then(|u| u.as_str()) {
                    out.push((u.to_string(), name.to_string(), folder.to_string()));
                }
            }
            Some("folder") => {
                let sub = if folder.is_empty() { name.to_string() } else { format!("{folder}/{name}") };
                for c in node.get("children").and_then(|c| c.as_array()).into_iter().flatten() {
                    walk(c, &sub, out);
                }
            }
            _ => {}
        }
    }
    let roots = v.get("roots").ok_or("no roots in Bookmarks")?;
    for key in ["bookmark_bar", "other", "synced"] {
        if let Some(r) = roots.get(key) {
            let label = match key {
                "bookmark_bar" => "Bookmarks bar",
                "other" => "Other bookmarks",
                _ => "Mobile bookmarks",
            };
            let base = if prefix.is_empty() { label.to_string() } else { format!("{prefix}/{label}") };
            for c in r.get("children").and_then(|c| c.as_array()).into_iter().flatten() {
                walk(c, &base, &mut out);
            }
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn add_search_remove_persist() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("b/bookmarks.json");
        let mut b = Bookmarks::open(p.clone());
        let id = b.add("https://omarchy.org", "Omarchy", "Linux/");
        assert_eq!(b.add("https://omarchy.org", "Omarchy manual", "Linux"), id);
        b.add("https://hypr.land", "Hyprland", "");
        assert_eq!(b.items.len(), 2);
        assert_eq!(b.search("manual", 5).len(), 1);
        assert_eq!(b.search("linux", 5).len(), 1);
        let b2 = Bookmarks::open(p.clone());
        assert_eq!(b2.items.len(), 2);
        assert_eq!(b2.items[0].folder, "Linux");
        let mut b2 = b2;
        assert!(b2.remove(id));
        assert!(!b2.contains("https://omarchy.org"));
        assert_eq!(b2.add("https://x.test", "", ""), 3, "ids keep counting");
    }

    #[test]
    fn chrome_bookmarks_import() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("Bookmarks");
        fs::write(
            &p,
            r#"{"roots":{"bookmark_bar":{"children":[{"type":"url","name":"Arch","url":"https://archlinux.org"},
            {"type":"folder","name":"Dev","children":[{"type":"url","name":"Rust","url":"https://rust-lang.org"}]}],"type":"folder","name":"Bookmarks bar"},
            "other":{"children":[],"type":"folder"},"synced":{"children":[],"type":"folder"}},"version":1}"#,
        )
        .unwrap();
        let list = parse_chrome(&p, "Chrome").unwrap();
        assert_eq!(list.len(), 2);
        assert_eq!(list[1].2, "Chrome/Bookmarks bar/Dev");
        let mut b = Bookmarks::open(dir.path().join("mine.json"));
        assert_eq!(b.import(list.clone()), 2);
        assert_eq!(b.import(list), 0);
    }
}
