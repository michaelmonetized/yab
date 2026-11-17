//! Chrome extensions: the parts Qt WebEngine leaves to the browser.
//! Qt 6.10+ (QWebEngineExtensionManager) loads and installs unpacked
//! extensions per profile; this gets them there: Chrome Web Store ids and
//! links, .crx files (CRX2 and CRX3), and .zip files, unpacked into the
//! profile's `extensions-src/<id>` for the manager to install.

use std::fs;
use std::io::{Cursor, Read};
use std::path::{Path, PathBuf};
use std::time::Duration;

/// The Chromium version Omaweb's Qt WebEngine is based on, sent to the
/// Web Store so it hands over a build that runs here.
pub const PROD_VERSION: &str = "140.0.7339.264";

fn is_id(s: &str) -> bool {
    s.len() == 32 && s.bytes().all(|b| (b'a'..=b'p').contains(&b))
}

/// An extension id from an id, a Web Store link (old or new) or anything
/// with `id=` in it.
pub fn store_id(input: &str) -> Option<String> {
    let s = input.trim();
    if is_id(s) {
        return Some(s.to_string());
    }
    let path = s.split(['?', '#']).next().unwrap_or("");
    for seg in path.split('/').rev() {
        if is_id(seg) {
            return Some(seg.to_string());
        }
    }
    s.split(['?', '&']).find_map(|kv| kv.strip_prefix("id=").filter(|v| is_id(v)).map(String::from))
}

pub fn is_store_page(url: &str) -> bool {
    (url.starts_with("https://chromewebstore.google.com/detail/") || url.starts_with("https://chrome.google.com/webstore/detail/"))
        && store_id(url).is_some()
}

pub fn download_url(id: &str) -> String {
    format!(
        "https://clients2.google.com/service/update2/crx?response=redirect&prodversion={PROD_VERSION}\
         &acceptformat=crx2,crx3&x=id%3D{id}%26installsource%3Dondemand%26uc"
    )
}

/// The zip inside a CRX (versions 2 and 3); a plain zip passes through.
pub fn crx_zip(bytes: &[u8]) -> Result<&[u8], String> {
    if bytes.starts_with(b"PK\x03\x04") {
        return Ok(bytes);
    }
    if bytes.len() < 16 || &bytes[..4] != b"Cr24" {
        return Err("not a Chrome extension (.crx) file".into());
    }
    let u32le = |o: usize| u32::from_le_bytes([bytes[o], bytes[o + 1], bytes[o + 2], bytes[o + 3]]) as usize;
    let start = match u32le(4) {
        2 => 16 + u32le(8) + u32le(12),
        3 => 12 + u32le(8),
        v => return Err(format!("CRX version {v} isn't known")),
    };
    bytes.get(start..).filter(|z| z.starts_with(b"PK")).ok_or_else(|| "the .crx file is damaged".to_string())
}

/// Reads a protobuf varint at `*o`.
fn varint(b: &[u8], o: &mut usize) -> Option<u64> {
    let mut v = 0u64;
    for shift in (0..64).step_by(7) {
        let byte = *b.get(*o)?;
        *o += 1;
        v |= ((byte & 0x7f) as u64) << shift;
        if byte & 0x80 == 0 {
            return Some(v);
        }
    }
    None
}

/// The length-delimited fields of one protobuf message: (field, bytes).
fn fields(b: &[u8]) -> Vec<(u64, &[u8])> {
    let mut out = Vec::new();
    let mut o = 0;
    while o < b.len() {
        let Some(tag) = varint(b, &mut o) else { break };
        match tag & 7 {
            0 => {
                if varint(b, &mut o).is_none() {
                    break;
                }
            }
            2 => {
                let Some(n) = varint(b, &mut o) else { break };
                let Some(v) = b.get(o..o + n as usize) else { break };
                out.push((tag >> 3, v));
                o += n as usize;
            }
            5 => o += 4,
            1 => o += 8,
            _ => break,
        }
    }
    out
}

/// Chrome's id for a public key: the first 16 bytes of its SHA-256, as
/// letters a-p.
pub fn id_of_key(key: &[u8]) -> String {
    use sha2::Digest;
    sha2::Sha256::digest(key)[..16].iter().flat_map(|b| [b >> 4, b & 15]).map(|n| (b'a' + n) as char).collect()
}

/// The signing public key in a CRX: the one whose id the header names
/// (CRX3), or the only one (CRX2). Put in the manifest as `key`, it keeps
/// the extension's Web Store id once unpacked, which some extensions need.
pub fn crx_public_key(bytes: &[u8]) -> Option<Vec<u8>> {
    if bytes.len() < 16 || &bytes[..4] != b"Cr24" {
        return None;
    }
    let u32le = |o: usize| u32::from_le_bytes([bytes[o], bytes[o + 1], bytes[o + 2], bytes[o + 3]]) as usize;
    match u32le(4) {
        2 => bytes.get(16..16 + u32le(8)).map(<[u8]>::to_vec),
        3 => {
            let header = bytes.get(12..12 + u32le(8))?;
            let f = fields(header);
            let crx_id = f.iter().find(|(n, _)| *n == 10000).and_then(|(_, sd)| fields(sd).into_iter().find(|(n, _)| *n == 1).map(|(_, v)| v.to_vec()));
            let keys: Vec<&[u8]> = f.iter().filter(|(n, _)| *n == 2 || *n == 3).filter_map(|(_, proof)| fields(proof).into_iter().find(|(n, _)| *n == 1).map(|(_, k)| k)).collect();
            let want = crx_id.map(|id| id.iter().flat_map(|b| [b >> 4, b & 15]).map(|n| (b'a' + n) as char).collect::<String>());
            keys.iter().find(|k| want.as_deref().map(|w| id_of_key(k) == w).unwrap_or(true)).map(|k| k.to_vec())
        }
        _ => None,
    }
}

fn base64(data: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::new();
    for c in data.chunks(3) {
        let n = (c[0] as u32) << 16 | (*c.get(1).unwrap_or(&0) as u32) << 8 | *c.get(2).unwrap_or(&0) as u32;
        for i in 0..4 {
            if i <= c.len() {
                out.push(T[(n >> (18 - 6 * i) & 63) as usize] as char);
            } else {
                out.push('=');
            }
        }
    }
    out
}

/// Adds `key` to an unpacked extension's manifest unless it has one.
pub fn set_manifest_key(dir: &Path, key: &[u8]) -> Result<(), String> {
    let p = dir.join("manifest.json");
    let text = fs::read_to_string(&p).map_err(|e| e.to_string())?;
    let mut v: serde_json::Value = serde_json::from_str(text.trim_start_matches('\u{feff}')).map_err(|e| format!("manifest.json: {e}"))?;
    if v.get("key").is_some() {
        return Ok(());
    }
    v["key"] = serde_json::Value::String(base64(key));
    fs::write(&p, serde_json::to_string_pretty(&v).unwrap_or_default()).map_err(|e| e.to_string())
}

/// Unpacks a CRX or zip and keeps the CRX's key, so the id survives.
fn unpack_crx(bytes: &[u8], dest: &Path) -> Result<String, String> {
    let name = unpack(crx_zip(bytes)?, dest)?;
    if let Some(k) = crx_public_key(bytes) {
        set_manifest_key(dest, &k)?;
    }
    Ok(name)
}

/// Unzips into `dest` (replacing it), refusing paths that leave it, and
/// drops `_metadata` (the Web Store's signatures, which unpacked loading
/// rejects). Returns the extension's name from its manifest.
pub fn unpack(zip_bytes: &[u8], dest: &Path) -> Result<String, String> {
    let mut z = zip::ZipArchive::new(Cursor::new(zip_bytes)).map_err(|e| format!("bad archive: {e}"))?;
    let _ = fs::remove_dir_all(dest);
    fs::create_dir_all(dest).map_err(|e| e.to_string())?;
    for i in 0..z.len() {
        let mut f = z.by_index(i).map_err(|e| e.to_string())?;
        let Some(rel) = f.enclosed_name() else { continue };
        if rel.components().next().map(|c| c.as_os_str() == "_metadata").unwrap_or(false) {
            continue;
        }
        let out = dest.join(rel);
        if f.is_dir() {
            fs::create_dir_all(&out).map_err(|e| e.to_string())?;
            continue;
        }
        if let Some(p) = out.parent() {
            fs::create_dir_all(p).map_err(|e| e.to_string())?;
        }
        let mut buf = Vec::new();
        f.read_to_end(&mut buf).map_err(|e| e.to_string())?;
        fs::write(&out, buf).map_err(|e| e.to_string())?;
    }
    manifest_name(dest)
}

pub fn manifest_name(dir: &Path) -> Result<String, String> {
    let text = fs::read_to_string(dir.join("manifest.json")).map_err(|_| "no manifest.json: not an extension".to_string())?;
    let text = text.trim_start_matches('\u{feff}');
    let v: serde_json::Value = serde_json::from_str(text).map_err(|e| format!("manifest.json: {e}"))?;
    Ok(v.get("name").and_then(|n| n.as_str()).unwrap_or("Extension").to_string())
}

/// The largest icon the manifest names (action icon first).
pub fn icon_path(dir: &Path) -> Option<PathBuf> {
    let text = fs::read_to_string(dir.join("manifest.json")).ok()?;
    let v: serde_json::Value = serde_json::from_str(text.trim_start_matches('\u{feff}')).ok()?;
    let pick = |icons: &serde_json::Value| -> Option<String> {
        if let Some(s) = icons.as_str() {
            return Some(s.to_string());
        }
        let obj = icons.as_object()?;
        obj.iter().max_by_key(|(k, _)| k.parse::<u32>().unwrap_or(0)).and_then(|(_, v)| v.as_str().map(String::from))
    };
    let candidates = [v.pointer("/action/default_icon"), v.pointer("/browser_action/default_icon"), v.get("icons")];
    let found = candidates.into_iter().flatten().filter_map(pick).map(|rel| dir.join(rel.trim_start_matches('/'))).find(|p| p.exists());
    found
}

/// Downloads from the Web Store and unpacks into `root/<id>`.
pub fn fetch_store(id: &str, root: &Path) -> Result<(PathBuf, String), String> {
    let resp = ureq::get(&download_url(id))
        .timeout(Duration::from_secs(60))
        .set("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.7339.264 Safari/537.36")
        .call()
        .map_err(|e| format!("Couldn't download {id} from the Chrome Web Store: {e}"))?;
    let mut bytes = Vec::new();
    resp.into_reader().take(256 << 20).read_to_end(&mut bytes).map_err(|e| e.to_string())?;
    if bytes.is_empty() {
        return Err("The Chrome Web Store sent nothing back for that id".into());
    }
    let dest = root.join(id);
    let name = unpack_crx(&bytes, &dest)?;
    Ok((dest, name))
}

/// A local .crx or .zip, unpacked into `root/<file stem>`; a directory is
/// used where it is.
pub fn from_file(path: &Path, root: &Path) -> Result<(PathBuf, String), String> {
    if path.is_dir() {
        return Ok((path.to_path_buf(), manifest_name(path)?));
    }
    let bytes = fs::read(path).map_err(|e| e.to_string())?;
    let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or("extension");
    let dest = root.join(crate::profiles::slugify(stem));
    let name = unpack_crx(&bytes, &dest)?;
    Ok((dest, name))
}

/// A JSON list of strings in a file (unpacked folders, disabled ids).
pub fn read_list(file: &Path) -> Vec<String> {
    fs::read_to_string(file).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default()
}

/// Adds `item` to the list in `file`, or takes it out.
pub fn set_in_list(file: &Path, item: &str, on: bool) -> Result<(), String> {
    let mut list = read_list(file);
    list.retain(|p| p != item);
    if on {
        list.push(item.to_string());
    }
    if let Some(d) = file.parent() {
        fs::create_dir_all(d).map_err(|e| e.to_string())?;
    }
    fs::write(file, serde_json::to_string(&list).unwrap_or_default()).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn zip_bytes() -> Vec<u8> {
        let mut buf = Cursor::new(Vec::new());
        {
            let mut w = zip::ZipWriter::new(&mut buf);
            let o = zip::write::SimpleFileOptions::default();
            w.start_file("manifest.json", o).unwrap();
            w.write_all(br#"{"manifest_version":3,"name":"Test Ext","version":"1"}"#).unwrap();
            w.start_file("_metadata/verified_contents.json", o).unwrap();
            w.write_all(b"{}").unwrap();
            w.start_file("js/bg.js", o).unwrap();
            w.write_all(b"//").unwrap();
            w.finish().unwrap();
        }
        buf.into_inner()
    }

    #[test]
    fn ids_from_links() {
        let id = "ddkjiahejlhfcafbddmgiahcphecmpfh";
        assert_eq!(store_id(id).as_deref(), Some(id));
        assert_eq!(store_id(&format!("https://chromewebstore.google.com/detail/ublock-origin-lite/{id}?hl=en")).as_deref(), Some(id));
        assert_eq!(store_id(&format!("https://chrome.google.com/webstore/detail/{id}")).as_deref(), Some(id));
        assert!(is_store_page(&format!("https://chromewebstore.google.com/detail/x/{id}")));
        assert!(store_id("https://example.com/detail/zzz").is_none());
        assert!(download_url(id).contains(&format!("id%3D{id}")));
    }

    #[test]
    fn crx3_and_crx2_unwrap() {
        let z = zip_bytes();
        let header = vec![7u8; 20];
        let mut crx3 = b"Cr24".to_vec();
        crx3.extend(3u32.to_le_bytes());
        crx3.extend((header.len() as u32).to_le_bytes());
        crx3.extend(&header);
        crx3.extend(&z);
        assert_eq!(crx_zip(&crx3).unwrap(), &z[..]);
        let mut crx2 = b"Cr24".to_vec();
        crx2.extend(2u32.to_le_bytes());
        crx2.extend(4u32.to_le_bytes());
        crx2.extend(3u32.to_le_bytes());
        crx2.extend([1, 2, 3, 4, 5, 6, 7]);
        crx2.extend(&z);
        assert_eq!(crx_zip(&crx2).unwrap(), &z[..]);
        assert_eq!(crx_zip(&z).unwrap(), &z[..]);
        assert!(crx_zip(b"nope, not an extension").is_err());

        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("t.crx");
        fs::write(&p, &crx3).unwrap();
        let (dest, name) = from_file(&p, &dir.path().join("src")).unwrap();
        assert_eq!(name, "Test Ext");
        assert!(dest.join("js/bg.js").exists());
        assert!(!dest.join("_metadata").exists());
        fs::write(dest.join("i48.png"), b"png").unwrap();
        fs::write(dest.join("manifest.json"), r#"{"name":"T","icons":{"16":"i16.png","48":"i48.png"}}"#).unwrap();
        assert_eq!(icon_path(&dest), Some(dest.join("i48.png")));
    }

    #[test]
    fn lists_in_files() {
        let dir = tempfile::tempdir().unwrap();
        let f = dir.path().join("a/disabled.json");
        assert!(read_list(&f).is_empty());
        set_in_list(&f, "x", true).unwrap();
        set_in_list(&f, "y", true).unwrap();
        set_in_list(&f, "x", true).unwrap();
        assert_eq!(read_list(&f), vec!["y", "x"]);
        set_in_list(&f, "y", false).unwrap();
        assert_eq!(read_list(&f), vec!["x"]);
    }

    fn pb(field: u64, v: &[u8]) -> Vec<u8> {
        let mut out = vec![];
        let mut put = |mut n: u64| loop {
            let b = (n & 0x7f) as u8;
            n >>= 7;
            if n == 0 {
                out.push(b);
                break;
            }
            out.push(b | 0x80);
        };
        put(field << 3 | 2);
        put(v.len() as u64);
        out.extend_from_slice(v);
        out
    }

    #[test]
    fn crx3_key_keeps_the_store_id() {
        let key = b"not really DER, but any bytes hash".to_vec();
        let other = b"a second signer (the Web Store's)".to_vec();
        let id = id_of_key(&key);
        assert_eq!(id.len(), 32);
        assert!(is_id(&id));
        let id_bytes: Vec<u8> = id.as_bytes().chunks(2).map(|c| (c[0] - b'a') << 4 | (c[1] - b'a')).collect();
        let mut header = pb(2, &[pb(1, &other), pb(2, b"sig")].concat());
        header.extend(pb(2, &[pb(1, &key), pb(2, b"sig")].concat()));
        header.extend(pb(10000, &pb(1, &id_bytes)));
        let mut crx = b"Cr24".to_vec();
        crx.extend(3u32.to_le_bytes());
        crx.extend((header.len() as u32).to_le_bytes());
        crx.extend(&header);
        crx.extend(zip_bytes());
        assert_eq!(crx_public_key(&crx), Some(key.clone()));
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("x.crx");
        fs::write(&p, &crx).unwrap();
        let (dest, _) = from_file(&p, &dir.path().join("src")).unwrap();
        let m: serde_json::Value = serde_json::from_str(&fs::read_to_string(dest.join("manifest.json")).unwrap()).unwrap();
        assert_eq!(m["key"], base64(&key));
        assert_eq!(base64(b"Ma"), "TWE=");
        assert_eq!(base64(b"Man"), "TWFu");
        assert_eq!(base64(b"M"), "TQ==");
    }
}
