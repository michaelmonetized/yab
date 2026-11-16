//! One field for addresses and searches, as in Yab: type an address and you
//! go there, type words and you search. Nothing leaves the machine until
//! Return is pressed.

use crate::config::Config;
use percent_encoding::{utf8_percent_encode, AsciiSet, NON_ALPHANUMERIC};

const QUERY: &AsciiSet = &NON_ALPHANUMERIC.remove(b'-').remove(b'_').remove(b'.').remove(b'~');

const SCHEMES: &[&str] = &[
    "http", "https", "file", "about", "data", "view-source", "chrome", "qrc", "ftp", "mailto",
    "blob", "javascript",
];

pub fn resolve(input: &str, cfg: &Config) -> String {
    let s = input.trim();
    if s.is_empty() {
        return String::new();
    }
    if let Some(url) = as_url(s) {
        return url;
    }
    // Keyword search: "gh rune", "aw hyprland".
    if let Some((kw, rest)) = s.split_once(char::is_whitespace) {
        if let Some(tpl) = cfg.keywords.get(kw) {
            return fill(tpl, rest.trim());
        }
    }
    fill(&cfg.search, s)
}

fn fill(template: &str, q: &str) -> String {
    let enc = utf8_percent_encode(q, QUERY).to_string();
    if template.contains("{}") {
        template.replace("{}", &enc)
    } else {
        format!("{template}{enc}")
    }
}

pub fn as_url(s: &str) -> Option<String> {
    if s.contains(char::is_whitespace) {
        return None;
    }
    if let Some((scheme, rest)) = s.split_once(':') {
        let sl = scheme.to_ascii_lowercase();
        if SCHEMES.contains(&sl.as_str()) && (!rest.is_empty() || sl == "about") {
            // "localhost:3000" has no known scheme and falls through.
            return Some(s.to_string());
        }
    }
    if let Some(path) = s.strip_prefix("~/") {
        let home = crate::paths::home_dir();
        return Some(format!("file://{}/{}", home.display(), path));
    }
    if s.starts_with('/') {
        return Some(format!("file://{s}"));
    }
    let host_port = s.split(['/', '?', '#']).next().unwrap_or(s);
    let host = match host_port.rsplit_once(':') {
        Some((h, port)) if !port.is_empty() && port.chars().all(|c| c.is_ascii_digit()) => h,
        _ => host_port,
    };
    let lower = host.to_ascii_lowercase();
    if lower == "localhost" || lower.ends_with(".localhost") || is_ipv4(&lower) {
        return Some(format!("http://{s}"));
    }
    if let Some((_, tld)) = lower.rsplit_once('.') {
        let labels_ok = lower.split('.').all(|l| {
            !l.is_empty() && l.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
        });
        let tld_ok = tld.len() >= 2 && tld.chars().all(|c| c.is_ascii_alphabetic());
        if labels_ok && tld_ok {
            return Some(format!("https://{s}"));
        }
    }
    None
}

fn is_ipv4(s: &str) -> bool {
    let parts: Vec<_> = s.split('.').collect();
    parts.len() == 4 && parts.iter().all(|p| !p.is_empty() && p.len() <= 3 && p.parse::<u8>().is_ok())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn r(s: &str) -> String {
        resolve(s, &Config::default())
    }

    #[test]
    fn addresses() {
        assert_eq!(r("omarchy.org"), "https://omarchy.org");
        assert_eq!(r("github.com/basecamp/omarchy"), "https://github.com/basecamp/omarchy");
        assert_eq!(r("https://x.com"), "https://x.com");
        assert_eq!(r("localhost:3000"), "http://localhost:3000");
        assert_eq!(r("192.168.1.10:8080/admin"), "http://192.168.1.10:8080/admin");
        assert_eq!(r("about:blank"), "about:blank");
        assert_eq!(r("/etc/hosts"), "file:///etc/hosts");
    }

    #[test]
    fn searches() {
        assert_eq!(r("rust gui"), "https://duckduckgo.com/?q=rust%20gui");
        assert_eq!(r("hello"), "https://duckduckgo.com/?q=hello");
        assert_eq!(r("v1.2"), "https://duckduckgo.com/?q=v1.2");
        assert_eq!(r("aw hyprland"), "https://wiki.archlinux.org/index.php?search=hyprland");
        assert_eq!(r("gh anomalyco rune"), "https://github.com/search?q=anomalyco%20rune");
        assert_eq!(r("c++ & qt"), "https://duckduckgo.com/?q=c%2B%2B%20%26%20qt");
    }
}
