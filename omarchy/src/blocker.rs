//! The ad and tracker blocker's lists. Rust fetches and parses them into
//! one plain file of hosts (`~/.cache/qi/blocklist.txt`); the C++
//! QWebEngineUrlRequestInterceptor loads that file and turns away any
//! request to a listed host or its subdomains before it is made.
//!
//! Hosts files (`0.0.0.0 ads.example`) and the domain rules of Adblock
//! lists (`||ads.example^`, `@@||ok.example^`) are understood. Cosmetic
//! rules and path rules are not: this is a network blocker, not uBlock.

use std::collections::BTreeSet;
use std::fs;
use std::path::Path;
use std::time::{Duration, SystemTime};

/// A small list that works before any download: the biggest ad networks
/// and trackers.
pub const BUILTIN: &[&str] = &[
    "doubleclick.net", "googlesyndication.com", "googleadservices.com", "google-analytics.com",
    "googletagmanager.com", "googletagservices.com", "adservice.google.com", "app-measurement.com",
    "adnxs.com", "adsrvr.org", "advertising.com", "amazon-adsystem.com", "criteo.com", "criteo.net",
    "taboola.com", "outbrain.com", "scorecardresearch.com", "quantserve.com", "hotjar.com",
    "mixpanel.com", "segment.io", "connect.facebook.net", "pixel.facebook.com", "ads-twitter.com",
    "analytics.twitter.com", "ads.linkedin.com", "bat.bing.com", "adform.net", "pubmatic.com",
    "rubiconproject.com", "openx.net", "casalemedia.com", "moatads.com", "chartbeat.com",
    "newrelic.com", "nr-data.net", "yieldmo.com", "zedo.com", "media.net", "smartadserver.com",
    "teads.tv", "33across.com", "sharethrough.com", "indexww.com", "bidswitch.net", "mathtag.com",
];

#[derive(Debug, Default, PartialEq)]
pub struct Lists {
    pub block: BTreeSet<String>,
    pub allow: BTreeSet<String>,
}

fn clean_host(h: &str) -> Option<String> {
    let h = h.trim().trim_end_matches('.').to_ascii_lowercase();
    if h.is_empty() || h == "localhost" || h.starts_with("localhost.") || !h.contains('.') || h.contains('/') || h.contains('*') {
        return None;
    }
    if !h.chars().all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-' || c == '_') {
        return None;
    }
    if h.parse::<std::net::IpAddr>().is_ok() {
        return None;
    }
    Some(h)
}

/// Parses one list's text into `lists`.
pub fn parse_into(text: &str, lists: &mut Lists) {
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') || line.starts_with('!') || line.starts_with('[') {
            continue;
        }
        // Adblock domain rule, optionally with options we can honour by
        // ignoring ($third-party, $important); others are skipped.
        let (allow, rule) = match line.strip_prefix("@@") {
            Some(r) => (true, r),
            None => (false, line),
        };
        if let Some(r) = rule.strip_prefix("||") {
            let (body, opts) = r.split_once('$').unwrap_or((r, ""));
            if !opts.split(',').all(|o| matches!(o, "" | "third-party" | "3p" | "important" | "all")) {
                continue;
            }
            let Some(host) = body.strip_suffix('^').or(if body.ends_with('/') { None } else { Some(body) }) else { continue };
            if let Some(h) = clean_host(host) {
                if allow { lists.allow.insert(h); } else { lists.block.insert(h); }
            }
            continue;
        }
        if line.contains("##") || line.contains("#@#") || allow {
            continue;
        }
        // Hosts file: "0.0.0.0 host [host...]" or a bare host per line.
        let mut parts = line.split_whitespace();
        let first = parts.next().unwrap_or("");
        let is_addr = first.parse::<std::net::IpAddr>().is_ok();
        let hosts: Vec<&str> = if is_addr { parts.take_while(|p| !p.starts_with('#')).collect() } else if line.split_whitespace().count() == 1 { vec![first] } else { vec![] };
        for h in hosts {
            if let Some(h) = clean_host(h) {
                lists.block.insert(h);
            }
        }
    }
}

/// True when `host` or one of its parents is blocked and none is allowed.
/// The C++ interceptor does the same walk; this one is the tested spec.
#[cfg_attr(not(test), allow(dead_code))]
pub fn is_blocked(lists: &Lists, host: &str) -> bool {
    let host = host.to_ascii_lowercase();
    let mut h = host.as_str();
    let mut blocked = false;
    loop {
        if lists.allow.contains(h) {
            return false;
        }
        if lists.block.contains(h) {
            blocked = true;
        }
        match h.split_once('.') {
            Some((_, rest)) if rest.contains('.') => h = rest,
            _ => break,
        }
    }
    blocked
}

/// The compiled file: a host per line, allowed hosts as `@@host`.
pub fn write_compiled(lists: &Lists, path: &Path) -> std::io::Result<()> {
    if let Some(d) = path.parent() {
        fs::create_dir_all(d)?;
    }
    let mut out = String::with_capacity(lists.block.len() * 20);
    for h in &lists.block {
        out.push_str(h);
        out.push('\n');
    }
    for h in &lists.allow {
        out.push_str("@@");
        out.push_str(h);
        out.push('\n');
    }
    let tmp = path.with_extension("txt.tmp");
    fs::write(&tmp, out)?;
    fs::rename(tmp, path)
}

fn cache_name(url: &str) -> String {
    let mut h: u64 = 0xcbf29ce484222325;
    for b in url.bytes() {
        h ^= b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    format!("list-{h:016x}.txt")
}

/// Fetches lists older than a week (keeping the cached copy when offline)
/// and writes the compiled file. Returns (hosts blocked, lists used).
pub fn refresh(urls: &[String], cache: &Path, out: &Path, force: bool) -> (usize, usize) {
    let mut lists = Lists::default();
    for h in BUILTIN {
        lists.block.insert(h.to_string());
    }
    let mut used = 0;
    for url in urls {
        let file = cache.join(cache_name(url));
        let fresh = fs::metadata(&file)
            .and_then(|m| m.modified())
            .map(|t| SystemTime::now().duration_since(t).unwrap_or_default() < Duration::from_secs(7 * 86400))
            .unwrap_or(false);
        if force || !fresh {
            if let Some(path) = url.strip_prefix("file://") {
                if let Ok(t) = fs::read_to_string(path) {
                    let _ = fs::create_dir_all(cache);
                    let _ = fs::write(&file, t);
                }
            } else if let Ok(resp) = ureq::get(url).timeout(Duration::from_secs(20)).call() {
                if let Ok(t) = resp.into_string() {
                    let _ = fs::create_dir_all(cache);
                    let _ = fs::write(&file, t);
                }
            }
        }
        if let Ok(t) = fs::read_to_string(&file) {
            parse_into(&t, &mut lists);
            used += 1;
        }
    }
    let _ = write_compiled(&lists, out);
    (lists.block.len(), used)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_hosts_and_adblock() {
        let mut l = Lists::default();
        parse_into(
            "# hosts\n0.0.0.0 ads.example.com tracker.example.net # c\n127.0.0.1 localhost\n\
             ||doubleclick.example^\n||cdn.example^$third-party\n||path.example/ads.js\n||opt.example^$script\n\
             @@||ok.ads.example.com^\nexample.com##.banner\n! comment\n[Adblock Plus 2.0]\nbare.example\n",
            &mut l,
        );
        for h in ["ads.example.com", "tracker.example.net", "doubleclick.example", "cdn.example", "bare.example"] {
            assert!(l.block.contains(h), "{h}");
        }
        assert!(!l.block.contains("localhost"));
        assert!(!l.block.iter().any(|h| h.contains("path.example") || h.contains("opt.example")));
        assert!(l.allow.contains("ok.ads.example.com"));
    }

    #[test]
    fn matches_subdomains_and_allows() {
        let mut l = Lists::default();
        parse_into("||ads.example.com^\n@@||ok.ads.example.com^\n||doubleclick.net^", &mut l);
        assert!(is_blocked(&l, "ads.example.com"));
        assert!(is_blocked(&l, "x.y.ads.example.com"));
        assert!(is_blocked(&l, "stats.g.doubleclick.net"));
        assert!(!is_blocked(&l, "ok.ads.example.com"));
        assert!(!is_blocked(&l, "example.com"));
        assert!(!is_blocked(&l, "notads.example.com"));
    }

    #[test]
    fn compiles_with_builtin_and_file_lists() {
        let dir = tempfile::tempdir().unwrap();
        let list = dir.path().join("mine.txt");
        fs::write(&list, "0.0.0.0 mine.example\n@@||googletagmanager.com^\n").unwrap();
        let out = dir.path().join("blocklist.txt");
        let (n, used) = refresh(&[format!("file://{}", list.display())], &dir.path().join("cache"), &out, true);
        assert_eq!(used, 1);
        assert!(n > BUILTIN.len());
        let text = fs::read_to_string(&out).unwrap();
        assert!(text.lines().any(|l| l == "mine.example"));
        assert!(text.lines().any(|l| l == "@@googletagmanager.com"));
    }
}
