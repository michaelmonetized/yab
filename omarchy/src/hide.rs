//! "Hide something": elements you picked on a site stay hidden there, as
//! CSS selectors per host in `~/.local/share/omaweb/hidden.json`.

use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

pub type Rules = BTreeMap<String, Vec<String>>;

pub fn host_key(host: &str) -> String {
    host.trim().to_ascii_lowercase().trim_start_matches("www.").to_string()
}

pub fn load(path: &Path) -> Rules {
    fs::read_to_string(path).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default()
}

pub fn save(path: &Path, rules: &Rules) {
    if let Some(d) = path.parent() {
        let _ = fs::create_dir_all(d);
    }
    let _ = fs::write(path, serde_json::to_string_pretty(rules).unwrap_or_default());
}

/// Adds a selector; refuses ones that could hide the whole page.
pub fn add(rules: &mut Rules, host: &str, selector: &str) -> bool {
    let sel = selector.trim();
    if sel.is_empty() || matches!(sel, "html" | "body" | "*" | "head") || sel.contains('{') || sel.contains('}') || sel.len() > 500 {
        return false;
    }
    let list = rules.entry(host_key(host)).or_default();
    if !list.iter().any(|s| s == sel) {
        list.push(sel.to_string());
    }
    true
}

/// The stylesheet for a host (and its parent domains' rules).
pub fn css_for(rules: &Rules, host: &str) -> String {
    let h = host_key(host);
    let mut sels: Vec<&str> = Vec::new();
    for (k, v) in rules {
        if h == *k || h.ends_with(&format!(".{k}")) {
            sels.extend(v.iter().map(String::as_str));
        }
    }
    if sels.is_empty() {
        String::new()
    } else {
        format!("{} {{ display: none !important; }}", sels.join(", "))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rules_by_site() {
        let mut r = Rules::new();
        assert!(add(&mut r, "www.example.com", ".cookie-banner"));
        assert!(add(&mut r, "example.com", "#promo"));
        assert!(add(&mut r, "example.com", "#promo"));
        assert!(!add(&mut r, "example.com", "body"));
        assert!(!add(&mut r, "example.com", "a{}"));
        assert_eq!(r["example.com"].len(), 2);
        let css = css_for(&r, "news.example.com");
        assert_eq!(css, ".cookie-banner, #promo { display: none !important; }");
        assert_eq!(css_for(&r, "other.test"), "");
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("hidden.json");
        save(&p, &r);
        assert_eq!(load(&p), r);
    }
}
