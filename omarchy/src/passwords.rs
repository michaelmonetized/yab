//! Saved passwords live in the Secret Service (GNOME Keyring, KeePassXC,
//! KWallet's bridge), never in Qi's files: `secret-tool` stores and
//! reads them. A small index (site and user name, no secret) per profile
//! lets the settings screen list them without unlocking anything.

use serde::{Deserialize, Serialize};
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Entry {
    pub origin: String,
    pub username: String,
}

pub fn available() -> bool {
    Command::new("secret-tool").arg("--version").stdout(Stdio::null()).stderr(Stdio::null()).status().map(|_| true).unwrap_or(false)
}

/// "https://github.com/login" → "https://github.com"
pub fn origin_of(url: &str) -> String {
    let Some((scheme, rest)) = url.split_once("://") else { return url.to_string() };
    let host = rest.split(['/', '?', '#']).next().unwrap_or("");
    format!("{scheme}://{host}")
}

fn attrs<'a>(app: &'a str, profile: &'a str, origin: &'a str, username: &'a str) -> [&'a str; 8] {
    ["application", app, "profile", profile, "origin", origin, "username", username]
}

pub struct Store {
    index: PathBuf,
    profile: String,
}

impl Store {
    pub fn new(profile: &str, index: PathBuf) -> Store {
        Store { index, profile: profile.to_string() }
    }

    pub fn list(&self) -> Vec<Entry> {
        fs::read_to_string(&self.index).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default()
    }

    fn write_index(&self, list: &[Entry]) {
        if let Some(d) = self.index.parent() {
            let _ = fs::create_dir_all(d);
        }
        let _ = fs::write(&self.index, serde_json::to_string_pretty(list).unwrap_or_default());
    }

    pub fn save(&self, url: &str, username: &str, password: &str) -> Result<(), String> {
        let origin = origin_of(url);
        let label = format!("Qi: {username} at {origin}");
        let mut child = Command::new("secret-tool")
            .arg("store")
            .arg("--label")
            .arg(&label)
            .args(attrs("qi", &self.profile, &origin, username))
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|_| "secret-tool isn't installed (libsecret-tools), so passwords can't be kept".to_string())?;
        child.stdin.take().ok_or("no stdin")?.write_all(password.as_bytes()).map_err(|e| e.to_string())?;
        let out = child.wait_with_output().map_err(|e| e.to_string())?;
        if !out.status.success() {
            return Err(format!("The Secret Service refused: {}", String::from_utf8_lossy(&out.stderr).trim()));
        }
        let mut list = self.list();
        if !list.iter().any(|e| e.origin == origin && e.username == username) {
            list.push(Entry { origin, username: username.into() });
            self.write_index(&list);
        }
        Ok(())
    }

    pub fn lookup(&self, url: &str, username: &str) -> Option<String> {
        let origin = origin_of(url);
        // New entries are stored as `qi`. Entries saved under the old name
        // still unlock, so a rename does not drop them.
        for app in ["qi", "omaweb"] {
            let out = Command::new("secret-tool").arg("lookup").args(attrs(app, &self.profile, &origin, username)).output().ok()?;
            if out.status.success() {
                let s = String::from_utf8_lossy(&out.stdout).to_string();
                if !s.is_empty() {
                    return Some(s);
                }
            }
        }
        None
    }

    pub fn for_site(&self, url: &str) -> Vec<Entry> {
        let o = origin_of(url);
        let host = |s: &str| s.split("://").nth(1).unwrap_or(s).trim_start_matches("www.").to_string();
        self.list().into_iter().filter(|e| e.origin == o || host(&e.origin) == host(&o)).collect()
    }

    pub fn remove(&self, origin: &str, username: &str) {
        for app in ["qi", "omaweb"] {
            let _ = Command::new("secret-tool").arg("clear").args(attrs(app, &self.profile, origin, username)).status();
        }
        let list: Vec<Entry> = self.list().into_iter().filter(|e| !(e.origin == origin && e.username == username)).collect();
        self.write_index(&list);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn origins() {
        assert_eq!(origin_of("https://github.com/login?x=1"), "https://github.com");
        assert_eq!(origin_of("http://localhost:3000/a"), "http://localhost:3000");
    }

    #[test]
    fn index_holds_no_secrets() {
        let dir = tempfile::tempdir().unwrap();
        let s = Store::new("Default", dir.path().join("passwords.json"));
        s.write_index(&[Entry { origin: "https://www.github.com".into(), username: "me".into() }]);
        assert_eq!(s.for_site("https://github.com/login").len(), 1);
        let text = fs::read_to_string(dir.path().join("passwords.json")).unwrap();
        assert!(!text.contains("password"));
    }
}
