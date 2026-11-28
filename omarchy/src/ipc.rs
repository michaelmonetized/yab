//! Single instance. `qi <url>` from a terminal, a Hyprland bind or
//! `xdg-open` hands the URL to the running window over a Unix socket in
//! `$XDG_RUNTIME_DIR` instead of starting a second browser.

use crate::paths;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;

pub fn socket_path() -> PathBuf {
    let wd = std::env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-0".into());
    paths::runtime_dir().join(format!("qi-{wd}.sock"))
}

/// Sends the URLs to a running instance. Returns true when one took them.
pub fn hand_off(urls: &[String], private: bool, profile: &str) -> bool {
    let Ok(mut s) = UnixStream::connect(socket_path()) else {
        return false;
    };
    let msg = encode(urls, private, profile);
    s.write_all(msg.as_bytes()).is_ok()
}

/// One line per URL: `[\x02][\x03profile\x1f]url`; with no URLs a
/// command line (`\x01focus`, `\x01private`, `\x01profile\x1fname`).
pub fn encode(urls: &[String], private: bool, profile: &str) -> String {
    let profile = profile.replace(['\n', '\x1f'], "");
    let mut msg = String::new();
    if urls.is_empty() {
        if !profile.is_empty() {
            msg.push_str(&format!("\x01profile\x1f{profile}{}\n", if private { "\x1fprivate" } else { "" }));
        } else {
            msg.push_str(if private { "\x01private\n" } else { "\x01focus\n" });
        }
    }
    for u in urls {
        if private {
            msg.push('\x02');
        }
        if !profile.is_empty() {
            msg.push_str(&format!("\x03{profile}\x1f"));
        }
        msg.push_str(u.replace('\n', "").as_str());
        msg.push('\n');
    }
    msg
}

/// Reads one line back: (url, private, profile). An empty URL means
/// focus (or a new blank tab when private or a profile is given).
pub fn decode(line: &str) -> Option<(String, bool, String)> {
    let line = line.trim();
    if line == "\x01focus" {
        return Some((String::new(), false, String::new()));
    }
    if line == "\x01private" {
        return Some((String::new(), true, String::new()));
    }
    if let Some(rest) = line.strip_prefix("\x01profile\x1f") {
        let (name, private) = match rest.strip_suffix("\x1fprivate") {
            Some(n) => (n, true),
            None => (rest, false),
        };
        return Some((String::new(), private, name.to_string()));
    }
    let (private, rest) = match line.strip_prefix('\x02') {
        Some(r) => (true, r),
        None => (false, line),
    };
    let (profile, url) = match rest.strip_prefix('\x03').and_then(|r| r.split_once('\x1f')) {
        Some((p, u)) => (p.to_string(), u),
        None => (String::new(), rest),
    };
    if url.is_empty() {
        return None;
    }
    Some((url.to_string(), private, profile))
}

/// Binds the socket and calls `on_url(url, private)` for each URL received
/// (on a background thread). An empty URL means "focus the window", or
/// "open a blank private tab" when `private` is set.
pub fn listen(on_url: impl Fn(String, bool, String) + Send + 'static) {
    let path = socket_path();
    let _ = std::fs::remove_file(&path);
    let Ok(listener) = UnixListener::bind(&path) else {
        eprintln!("qi: could not bind {}", path.display());
        return;
    };
    std::thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            for line in BufReader::new(stream).lines().map_while(Result::ok) {
                if let Some((u, p, prof)) = decode(&line) {
                    on_url(u, p, prof);
                }
            }
        }
    });
}

pub fn cleanup() {
    let _ = std::fs::remove_file(socket_path());
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips() {
        let m = encode(&["https://a.test".into()], true, "Work");
        assert_eq!(decode(m.lines().next().unwrap()), Some(("https://a.test".into(), true, "Work".into())));
        let m = encode(&["https://b.test".into()], false, "");
        assert_eq!(decode(m.trim()), Some(("https://b.test".into(), false, String::new())));
        assert_eq!(decode(encode(&[], false, "").trim()), Some((String::new(), false, String::new())));
        assert_eq!(decode(encode(&[], true, "").trim()), Some((String::new(), true, String::new())));
        assert_eq!(decode(encode(&[], false, "Work").trim()), Some((String::new(), false, "Work".into())));
        assert_eq!(decode(""), None);
    }
}
