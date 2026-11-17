//! Bringing a Chrome or Chromium profile over: bookmarks, history,
//! cookies, passwords and extensions.
//!
//! Chrome on Linux encrypts cookie values and passwords with AES-128-CBC.
//! "v10" values use a key derived from the fixed password "peanuts"; "v11"
//! values use a password kept in the Secret Service (GNOME Keyring,
//! KWallet through its Secret Service bridge), read here with
//! `secret-tool`. When that password can't be read, v11 values stay
//! behind and the report says so. Nothing decrypted is written to disk:
//! cookies go straight into the web engine's cookie store, passwords into
//! the Secret Service under Omaweb's own entries.

use aes::cipher::{block_padding::Pkcs7, BlockDecryptMut, KeyIvInit};
use serde::Serialize;
use sha2::Digest;
use std::fs;
use std::path::{Path, PathBuf};

type Aes128CbcDec = cbc::Decryptor<aes::Aes128>;

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ChromeProfile {
    /// "Google Chrome" or "Chromium" (or another Chromium browser).
    pub browser: String,
    /// The folder under the browser's config dir: "Default", "Profile 1".
    pub dir: String,
    /// The name the person gave it.
    pub name: String,
    pub path: String,
    /// The Secret Service "application" its key is kept under.
    pub keyring_app: String,
}

/// Browsers looked for, under ~/.config.
const BROWSERS: &[(&str, &str, &str)] = &[
    ("google-chrome", "Google Chrome", "chrome"),
    ("google-chrome-beta", "Google Chrome Beta", "chrome"),
    ("google-chrome-unstable", "Google Chrome Dev", "chrome"),
    ("chromium", "Chromium", "chromium"),
    ("BraveSoftware/Brave-Browser", "Brave", "brave"),
    ("microsoft-edge", "Microsoft Edge", "chromium"),
    ("vivaldi", "Vivaldi", "chrome"),
];

pub fn find_profiles(config_home: &Path) -> Vec<ChromeProfile> {
    let mut out = Vec::new();
    for (sub, label, app) in BROWSERS {
        let root = config_home.join(sub);
        let Ok(text) = fs::read_to_string(root.join("Local State")) else { continue };
        let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) else { continue };
        let Some(cache) = v.pointer("/profile/info_cache").and_then(|c| c.as_object()) else { continue };
        let mut dirs: Vec<(&String, &serde_json::Value)> = cache.iter().collect();
        dirs.sort_by(|a, b| a.0.cmp(b.0));
        for (dir, info) in dirs {
            let path = root.join(dir);
            if !path.is_dir() {
                continue;
            }
            out.push(ChromeProfile {
                browser: label.to_string(),
                dir: dir.clone(),
                name: info.get("name").and_then(|n| n.as_str()).unwrap_or(dir).to_string(),
                path: path.to_string_lossy().into_owned(),
                keyring_app: app.to_string(),
            });
        }
    }
    out
}

pub fn derive_key(password: &[u8]) -> [u8; 16] {
    let mut key = [0u8; 16];
    pbkdf2::pbkdf2_hmac::<sha1::Sha1>(password, b"saltysalt", 1, &mut key);
    key
}

/// Decrypts one value. `keys` are tried in order; `host` strips the
/// SHA-256 of the host that newer cookie databases put in front.
pub fn decrypt(blob: &[u8], keys: &[[u8; 16]], host: Option<&str>) -> Option<String> {
    if blob.len() < 3 {
        return None;
    }
    let (tag, data) = blob.split_at(3);
    if tag != b"v10" && tag != b"v11" {
        // Old unencrypted value.
        return String::from_utf8(blob.to_vec()).ok();
    }
    if data.is_empty() || data.len() % 16 != 0 {
        return None;
    }
    let iv = [b' '; 16];
    for key in keys {
        let mut buf = data.to_vec();
        let Ok(plain) = Aes128CbcDec::new(key.into(), &iv.into()).decrypt_padded_mut::<Pkcs7>(&mut buf) else { continue };
        let mut plain = plain.to_vec();
        if let Some(h) = host {
            if plain.len() >= 32 && plain[..32] == sha2::Sha256::digest(h.as_bytes())[..] {
                plain.drain(..32);
            }
        }
        if let Ok(s) = String::from_utf8(plain) {
            return Some(s);
        }
    }
    None
}

/// The v11 password from the Secret Service, if it can be read.
pub fn keyring_password(app: &str) -> Option<String> {
    for args in [
        vec!["lookup", "xdg:schema", "chrome_libsecret_os_crypt_password_v2", "application", app],
        vec!["lookup", "application", app],
    ] {
        let out = std::process::Command::new("secret-tool").args(&args).output().ok()?;
        let s = String::from_utf8_lossy(&out.stdout).trim_end_matches('\n').to_string();
        if out.status.success() && !s.is_empty() {
            return Some(s);
        }
    }
    None
}

/// Chrome keeps its databases locked while it runs: read copies.
fn copy_db(src: &Path) -> Result<(tempfile::TempDir, PathBuf), String> {
    let dir = tempfile::tempdir().map_err(|e| e.to_string())?;
    let dst = dir.path().join("db");
    fs::copy(src, &dst).map_err(|e| format!("{}: {e}", src.display()))?;
    for ext in ["-wal", "-journal"] {
        let side = PathBuf::from(format!("{}{ext}", src.display()));
        if side.exists() {
            let _ = fs::copy(&side, PathBuf::from(format!("{}{ext}", dst.display())));
        }
    }
    Ok((dir, dst))
}

fn open_ro(path: &Path) -> Result<rusqlite::Connection, String> {
    rusqlite::Connection::open_with_flags(path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY).map_err(|e| e.to_string())
}

/// Chrome's times are microseconds since 1601.
pub fn chrome_time(t: i64) -> u64 {
    (t / 1_000_000 - 11_644_473_600).max(0) as u64
}

pub fn read_history(profile: &Path, limit: usize) -> Result<Vec<crate::history::Visit>, String> {
    let (_d, db) = copy_db(&profile.join("History"))?;
    let c = open_ro(&db)?;
    let mut st = c
        .prepare("SELECT url, title, visit_count, last_visit_time FROM urls WHERE hidden = 0 ORDER BY last_visit_time DESC LIMIT ?1")
        .map_err(|e| e.to_string())?;
    let rows = st
        .query_map([limit as i64], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, i64>(2)?, r.get::<_, i64>(3)?)))
        .map_err(|e| e.to_string())?;
    let mut out = Vec::new();
    for (url, title, count, t) in rows.flatten() {
        for _ in 0..count.clamp(1, 20) {
            out.push(crate::history::Visit { url: url.clone(), title: title.clone(), at: chrome_time(t) });
        }
    }
    Ok(out)
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Cookie {
    pub name: String,
    pub value: String,
    pub domain: String,
    pub path: String,
    /// Unix seconds; 0 for a session cookie.
    pub expires: u64,
    pub secure: bool,
    pub http_only: bool,
    /// 0 none, 1 lax, 2 strict, -1 unspecified
    pub same_site: i64,
}

/// Returns (cookies decrypted, cookies that couldn't be).
pub fn read_cookies(profile: &Path, keys: &[[u8; 16]]) -> Result<(Vec<Cookie>, usize), String> {
    let src = [profile.join("Cookies"), profile.join("Network/Cookies")].into_iter().find(|p| p.exists()).ok_or("no Cookies database")?;
    let (_d, db) = copy_db(&src)?;
    let c = open_ro(&db)?;
    let version: i64 = c.query_row("SELECT value FROM meta WHERE key = 'version'", [], |r| r.get::<_, String>(0)).ok().and_then(|v| v.parse().ok()).unwrap_or(0);
    let mut st = c
        .prepare("SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, samesite FROM cookies")
        .map_err(|e| e.to_string())?;
    let rows = st
        .query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, Vec<u8>>(3)?,
                r.get::<_, String>(4)?,
                r.get::<_, i64>(5)?,
                r.get::<_, i64>(6)?,
                r.get::<_, i64>(7)?,
                r.get::<_, i64>(8).unwrap_or(-1),
            ))
        })
        .map_err(|e| e.to_string())?;
    let (mut ok, mut failed) = (Vec::new(), 0);
    for (host, name, value, enc, path, exp, secure, http_only, same_site) in rows.flatten() {
        let value = if !value.is_empty() || enc.is_empty() {
            Some(value)
        } else {
            decrypt(&enc, keys, if version >= 24 { Some(host.as_str()) } else { None })
        };
        match value {
            Some(v) => ok.push(Cookie {
                name,
                value: v,
                domain: host,
                path,
                expires: if exp > 0 { chrome_time(exp) } else { 0 },
                secure: secure != 0,
                http_only: http_only != 0,
                same_site,
            }),
            None => failed += 1,
        }
    }
    Ok((ok, failed))
}

#[derive(Debug, Clone, PartialEq)]
pub struct Login {
    pub origin: String,
    pub username: String,
    pub password: String,
}

pub fn read_logins(profile: &Path, keys: &[[u8; 16]]) -> Result<(Vec<Login>, usize), String> {
    let (_d, db) = copy_db(&profile.join("Login Data"))?;
    let c = open_ro(&db)?;
    let mut st = c.prepare("SELECT origin_url, username_value, password_value FROM logins WHERE blacklisted_by_user = 0").map_err(|e| e.to_string())?;
    let rows = st
        .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, Vec<u8>>(2)?)))
        .map_err(|e| e.to_string())?;
    let (mut ok, mut failed) = (Vec::new(), 0);
    for (origin, username, enc) in rows.flatten() {
        if enc.is_empty() {
            continue;
        }
        match decrypt(&enc, keys, None) {
            Some(password) => ok.push(Login { origin, username, password }),
            None => failed += 1,
        }
    }
    Ok((ok, failed))
}

/// Unpacked extensions in a Chrome profile: `Extensions/<id>/<version>`,
/// newest version of each.
pub fn find_extensions(profile: &Path) -> Vec<(String, PathBuf)> {
    let mut out = Vec::new();
    let Ok(rd) = fs::read_dir(profile.join("Extensions")) else { return out };
    for e in rd.flatten() {
        let id = e.file_name().to_string_lossy().into_owned();
        if id.len() != 32 {
            continue;
        }
        let mut versions: Vec<PathBuf> = fs::read_dir(e.path()).into_iter().flatten().flatten().map(|v| v.path()).filter(|p| p.join("manifest.json").exists()).collect();
        versions.sort();
        if let Some(v) = versions.pop() {
            out.push((id, v));
        }
    }
    out.sort();
    out
}

/// Copies an extension folder, leaving out `_metadata`.
pub fn copy_extension(src: &Path, dst: &Path) -> std::io::Result<()> {
    let _ = fs::remove_dir_all(dst);
    fs::create_dir_all(dst)?;
    for e in fs::read_dir(src)?.flatten() {
        let name = e.file_name();
        if name == "_metadata" {
            continue;
        }
        let to = dst.join(&name);
        if e.file_type()?.is_dir() {
            copy_extension(&e.path(), &to)?;
        } else {
            fs::copy(e.path(), to)?;
        }
    }
    Ok(())
}

pub fn keys_for(app: &str) -> (Vec<[u8; 16]>, bool) {
    let mut keys = Vec::new();
    let found = keyring_password(app);
    if let Some(p) = &found {
        keys.push(derive_key(p.as_bytes()));
    }
    keys.push(derive_key(b"peanuts"));
    keys.push(derive_key(b""));
    (keys, found.is_some())
}

#[cfg(test)]
mod tests {
    use super::*;
    use aes::cipher::BlockEncryptMut;
    type Enc = cbc::Encryptor<aes::Aes128>;

    fn encrypt(plain: &[u8], password: &[u8], tag: &[u8]) -> Vec<u8> {
        let key = derive_key(password);
        let mut buf = plain.to_vec();
        buf.resize(plain.len() + 16, 0);
        let ct = Enc::new(&key.into(), &[b' '; 16].into()).encrypt_padded_mut::<Pkcs7>(&mut buf, plain.len()).unwrap().to_vec();
        [tag, &ct].concat()
    }

    #[test]
    fn decrypts_v10_and_v11() {
        let peanuts = derive_key(b"peanuts");
        let v10 = encrypt(b"hunter2", b"peanuts", b"v10");
        assert_eq!(decrypt(&v10, &[peanuts], None).as_deref(), Some("hunter2"));
        let v11 = encrypt(b"s3cret", b"keyring-pass", b"v11");
        assert_eq!(decrypt(&v11, &[peanuts], None), None, "wrong key fails");
        assert_eq!(decrypt(&v11, &[peanuts, derive_key(b"keyring-pass")], None).as_deref(), Some("s3cret"));
        // Cookie DB v24+: SHA-256 of the host first.
        let mut p = sha2::Sha256::digest(b".example.com").to_vec();
        p.extend(b"cookieval");
        let v = encrypt(&p, b"peanuts", b"v10");
        assert_eq!(decrypt(&v, &[peanuts], Some(".example.com")).as_deref(), Some("cookieval"));
        assert_eq!(chrome_time(13_300_000_000_000_000), 1_655_526_400);
    }

    #[test]
    fn reads_a_chrome_profile() {
        let home = tempfile::tempdir().unwrap();
        let root = home.path().join("chromium");
        let prof = root.join("Default");
        fs::create_dir_all(&prof).unwrap();
        fs::write(root.join("Local State"), r#"{"profile":{"info_cache":{"Default":{"name":"Michael"},"Gone":{"name":"x"}}}}"#).unwrap();
        let found = find_profiles(home.path());
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].name, "Michael");
        assert_eq!(found[0].browser, "Chromium");

        let h = rusqlite::Connection::open(prof.join("History")).unwrap();
        h.execute_batch("CREATE TABLE urls(id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INTEGER, typed_count INTEGER, last_visit_time INTEGER, hidden INTEGER);
            INSERT INTO urls VALUES(1,'https://omarchy.org/','Omarchy',3,0,13300000000000000,0);").unwrap();
        drop(h);
        let v = read_history(&prof, 100).unwrap();
        assert_eq!(v.len(), 3);
        assert_eq!(v[0].title, "Omarchy");

        let c = rusqlite::Connection::open(prof.join("Cookies")).unwrap();
        c.execute_batch("CREATE TABLE meta(key TEXT, value TEXT); INSERT INTO meta VALUES('version','24');
            CREATE TABLE cookies(host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB, path TEXT, expires_utc INTEGER, is_secure INTEGER, is_httponly INTEGER, samesite INTEGER);").unwrap();
        let mut p = sha2::Sha256::digest(b".omarchy.org").to_vec();
        p.extend(b"abc");
        c.execute("INSERT INTO cookies VALUES('.omarchy.org','sid','',?1,'/',13300000000000000,1,1,1)", [encrypt(&p, b"peanuts", b"v10")]).unwrap();
        c.execute("INSERT INTO cookies VALUES('.locked.test','k','',?1,'/',0,0,0,-1)", [encrypt(b"zzz", b"not-known", b"v11")]).unwrap();
        drop(c);
        let (cookies, failed) = read_cookies(&prof, &[derive_key(b"peanuts")]).unwrap();
        assert_eq!(failed, 1);
        assert_eq!(cookies[0].value, "abc");
        assert!(cookies[0].secure && cookies[0].http_only);

        let l = rusqlite::Connection::open(prof.join("Login Data")).unwrap();
        l.execute_batch("CREATE TABLE logins(origin_url TEXT, username_value TEXT, password_value BLOB, blacklisted_by_user INTEGER);").unwrap();
        l.execute("INSERT INTO logins VALUES('https://omarchy.org/','me',?1,0)", [encrypt(b"pw", b"peanuts", b"v10")]).unwrap();
        drop(l);
        let (logins, failed) = read_logins(&prof, &[derive_key(b"peanuts")]).unwrap();
        assert_eq!(failed, 0);
        assert_eq!(logins[0], Login { origin: "https://omarchy.org/".into(), username: "me".into(), password: "pw".into() });

        let ext = prof.join("Extensions/ddkjiahejlhfcafbddmgiahcphecmpfh/1.0_0");
        fs::create_dir_all(ext.join("_metadata")).unwrap();
        fs::write(ext.join("manifest.json"), "{}").unwrap();
        let exts = find_extensions(&prof);
        assert_eq!(exts.len(), 1);
        let dst = home.path().join("copy");
        copy_extension(&exts[0].1, &dst).unwrap();
        assert!(dst.join("manifest.json").exists() && !dst.join("_metadata").exists());
    }

    /// Against a real throwaway Chrome profile made with
    /// `google-chrome --user-data-dir=DIR --password-store=basic`, never a
    /// real one: `OMAWEB_CHROME_TEST_PROFILE=DIR/Default cargo test -- --ignored`.
    #[test]
    #[ignore]
    fn real_throwaway_chrome_profile() {
        let Ok(dir) = std::env::var("OMAWEB_CHROME_TEST_PROFILE") else { return };
        let p = Path::new(&dir);
        let visits = read_history(p, 1000).unwrap();
        assert!(!visits.is_empty(), "history");
        let (keys, _) = keys_for("chrome");
        let (cookies, failed) = read_cookies(p, &keys).unwrap();
        eprintln!("history {} cookies {} not decrypted {failed}", visits.len(), cookies.len());
        assert!(cookies.iter().any(|c| c.name == "omatest" && c.value == "hello123"), "{cookies:?}");
        assert_eq!(failed, 0);
    }
}
