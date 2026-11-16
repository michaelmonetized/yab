//! Single instance. `omaweb <url>` from a terminal, a Hyprland bind or
//! `xdg-open` hands the URL to the running window over a Unix socket in
//! `$XDG_RUNTIME_DIR` instead of starting a second browser.

use crate::paths;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;

pub fn socket_path() -> PathBuf {
    let wd = std::env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-0".into());
    paths::runtime_dir().join(format!("omaweb-{wd}.sock"))
}

/// Sends the URLs to a running instance. Returns true when one took them.
pub fn hand_off(urls: &[String], private: bool) -> bool {
    let Ok(mut s) = UnixStream::connect(socket_path()) else {
        return false;
    };
    let mut msg = String::new();
    if urls.is_empty() {
        msg.push_str(if private { "\x01private\n" } else { "\x01focus\n" });
    }
    for u in urls {
        if private {
            msg.push('\x02');
        }
        msg.push_str(u.replace('\n', "").as_str());
        msg.push('\n');
    }
    s.write_all(msg.as_bytes()).is_ok()
}

/// Binds the socket and calls `on_url(url, private)` for each URL received
/// (on a background thread). An empty URL means "focus the window", or
/// "open a blank private tab" when `private` is set.
pub fn listen(on_url: impl Fn(String, bool) + Send + 'static) {
    let path = socket_path();
    let _ = std::fs::remove_file(&path);
    let Ok(listener) = UnixListener::bind(&path) else {
        eprintln!("omaweb: could not bind {}", path.display());
        return;
    };
    std::thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            for line in BufReader::new(stream).lines().map_while(Result::ok) {
                let line = line.trim().to_string();
                if line == "\x01focus" {
                    on_url(String::new(), false);
                } else if line == "\x01private" {
                    on_url(String::new(), true);
                } else if let Some(u) = line.strip_prefix('\x02') {
                    on_url(u.to_string(), true);
                } else if !line.is_empty() {
                    on_url(line, false);
                }
            }
        }
    });
}

pub fn cleanup() {
    let _ = std::fs::remove_file(socket_path());
}
