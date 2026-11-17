//! Browsing history, kept on this machine only, as a JSON-lines log in
//! `~/.local/share/omaweb/history.jsonl`. It feeds address completion and
//! the start page.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Visit {
    pub url: String,
    pub title: String,
    pub at: u64,
}

#[derive(Debug, Clone, Serialize)]
pub struct Entry {
    pub url: String,
    pub title: String,
    pub visits: u32,
    pub last: u64,
}

pub struct History {
    path: Option<PathBuf>,
    entries: HashMap<String, Entry>,
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

fn worth_keeping(url: &str) -> bool {
    !(url.is_empty() || url.starts_with("about:") || url.starts_with("data:") || url.starts_with("qrc:"))
}

impl History {
    pub fn open(path: PathBuf) -> History {
        let mut h = History { path: Some(path.clone()), entries: HashMap::new() };
        if let Ok(text) = fs::read_to_string(&path) {
            for line in text.lines() {
                if let Ok(v) = serde_json::from_str::<Visit>(line) {
                    h.apply(v);
                }
            }
            // Compact the log when it has grown well past the unique URLs.
            if text.lines().count() > 4 * h.entries.len() + 500 {
                h.rewrite();
            }
        }
        h
    }

    fn apply(&mut self, v: Visit) {
        let e = self.entries.entry(v.url.clone()).or_insert(Entry {
            url: v.url.clone(),
            title: String::new(),
            visits: 0,
            last: 0,
        });
        e.visits += 1;
        e.last = e.last.max(v.at);
        if !v.title.is_empty() {
            e.title = v.title;
        }
    }

    fn rewrite(&self) {
        let Some(path) = &self.path else { return };
        let mut out = String::new();
        for e in self.entries.values() {
            for _ in 0..e.visits.min(50) {
                let v = Visit { url: e.url.clone(), title: e.title.clone(), at: e.last };
                out.push_str(&serde_json::to_string(&v).unwrap_or_default());
                out.push('\n');
            }
        }
        let tmp = path.with_extension("jsonl.tmp");
        if fs::write(&tmp, out).is_ok() {
            let _ = fs::rename(tmp, path);
        }
    }

    pub fn record(&mut self, url: &str, title: &str) {
        if !worth_keeping(url) {
            return;
        }
        let v = Visit { url: url.to_string(), title: title.to_string(), at: now() };
        if let Some(path) = &self.path {
            if let Some(dir) = path.parent() {
                let _ = fs::create_dir_all(dir);
            }
            if let Ok(mut f) = OpenOptions::new().create(true).append(true).open(path) {
                let _ = writeln!(f, "{}", serde_json::to_string(&v).unwrap_or_default());
            }
        }
        self.apply(v);
    }

    /// Updates a title without counting a visit (titles arrive after load).
    pub fn retitle(&mut self, url: &str, title: &str) {
        if let Some(e) = self.entries.get_mut(url) {
            if !title.is_empty() && e.title != title {
                e.title = title.to_string();
            }
        }
    }

    fn score(e: &Entry, t: u64) -> f64 {
        let age_days = (t.saturating_sub(e.last)) as f64 / 86_400.0;
        (e.visits as f64).ln_1p() * 2.0 + 4.0 / (1.0 + age_days)
    }

    pub fn suggest(&self, query: &str, limit: usize) -> Vec<Entry> {
        let q = query.trim().to_lowercase();
        if q.is_empty() {
            return Vec::new();
        }
        let t = now();
        let words: Vec<&str> = q.split_whitespace().collect();
        let mut hits: Vec<(f64, &Entry)> = self
            .entries
            .values()
            .filter_map(|e| {
                let url = e.url.to_lowercase();
                let title = e.title.to_lowercase();
                if !words.iter().all(|w| url.contains(w) || title.contains(w)) {
                    return None;
                }
                let bare = url.trim_start_matches("https://").trim_start_matches("http://").trim_start_matches("www.");
                let prefix = if bare.starts_with(&q) { 10.0 } else { 0.0 };
                Some((prefix + Self::score(e, t), e))
            })
            .collect();
        hits.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
        hits.into_iter().take(limit).map(|(_, e)| e.clone()).collect()
    }

    /// Most recent first, for the history panel; `query` filters like
    /// address completion does.
    pub fn recent(&self, query: &str, limit: usize) -> Vec<Entry> {
        let words: Vec<String> = query.to_lowercase().split_whitespace().map(String::from).collect();
        let mut all: Vec<&Entry> = self
            .entries
            .values()
            .filter(|e| {
                let (u, t) = (e.url.to_lowercase(), e.title.to_lowercase());
                words.iter().all(|w| u.contains(w.as_str()) || t.contains(w.as_str()))
            })
            .collect();
        all.sort_by(|a, b| b.last.cmp(&a.last));
        all.into_iter().take(limit).cloned().collect()
    }

    /// Visits brought in from another browser (Chrome's History database).
    /// Appended to the log like ordinary visits, keeping their own times.
    pub fn import(&mut self, visits: Vec<Visit>) -> usize {
        let mut n = 0;
        let mut out = String::new();
        for v in visits {
            if !worth_keeping(&v.url) {
                continue;
            }
            out.push_str(&serde_json::to_string(&v).unwrap_or_default());
            out.push('\n');
            self.apply(v);
            n += 1;
        }
        if let Some(path) = &self.path {
            if let Some(dir) = path.parent() {
                let _ = fs::create_dir_all(dir);
            }
            if let Ok(mut f) = OpenOptions::new().create(true).append(true).open(path) {
                let _ = f.write_all(out.as_bytes());
            }
        }
        n
    }

    pub fn remove(&mut self, url: &str) {
        if self.entries.remove(url).is_some() {
            self.rewrite();
        }
    }

    pub fn clear(&mut self) {
        self.entries.clear();
        if let Some(path) = &self.path {
            let _ = fs::write(path, "");
        }
    }

    pub fn top(&self, limit: usize) -> Vec<Entry> {
        let t = now();
        let mut all: Vec<&Entry> = self.entries.values().collect();
        all.sort_by(|a, b| Self::score(b, t).partial_cmp(&Self::score(a, t)).unwrap_or(std::cmp::Ordering::Equal));
        all.into_iter().take(limit).cloned().collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn records_and_suggests() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("history.jsonl");
        {
            let mut h = History::open(p.clone());
            h.record("https://omarchy.org/", "Omarchy");
            h.record("https://omarchy.org/", "Omarchy");
            h.record("https://github.com/anomalyco/rune", "Rune");
            h.record("about:blank", "");
        }
        let h = History::open(p);
        let s = h.suggest("omar", 5);
        assert_eq!(s[0].url, "https://omarchy.org/");
        assert_eq!(s[0].visits, 2);
        assert_eq!(h.suggest("rune", 5)[0].title, "Rune");
        assert!(h.suggest("blank", 5).is_empty());
        assert_eq!(h.top(10).len(), 2);
    }
}
