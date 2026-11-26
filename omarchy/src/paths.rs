//! XDG locations. Qi keeps config, data and state apart, the way every
//! other Omarchy app does, so `~/.config/qi` can live in a dotfiles repo.
//! On first launch the old `omaweb` directories are moved here.

use std::env;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

static BLOCKED: Mutex<Vec<PathBuf>> = Mutex::new(Vec::new());

/// True when `path` is a folder an unfinished omaweb move still owns.
pub fn creation_blocked(path: &Path) -> bool {
    let blocked = BLOCKED.lock().unwrap_or_else(|e| e.into_inner());
    blocked.iter().any(|b| path == b || path.starts_with(b))
}

pub fn create_dir_all(path: &Path) -> io::Result<()> {
    if creation_blocked(path) {
        eprintln!(
            "qi: not creating {} until the old omaweb folder moves",
            path.display()
        );
        return Err(io::Error::new(
            io::ErrorKind::Other,
            "omaweb folder still needs to move",
        ));
    }
    fs::create_dir_all(path)
}

fn omaweb_running() -> bool {
    let Ok(entries) = fs::read_dir("/proc") else {
        return false;
    };
    for entry in entries.flatten() {
        let comm = fs::read_to_string(entry.path().join("comm")).unwrap_or_default();
        if comm.trim() == "omaweb" {
            return true;
        }
    }
    false
}

fn home() -> PathBuf {
    env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/tmp"))
}

fn xdg(var: &str, fallback: &str) -> PathBuf {
    match env::var_os(var) {
        Some(v) if !v.is_empty() => PathBuf::from(v),
        _ => home().join(fallback),
    }
}

pub fn config_dir() -> PathBuf {
    xdg("XDG_CONFIG_HOME", ".config").join("qi")
}

pub fn data_dir() -> PathBuf {
    xdg("XDG_DATA_HOME", ".local/share").join("qi")
}

pub fn state_dir() -> PathBuf {
    xdg("XDG_STATE_HOME", ".local/state").join("qi")
}

pub fn cache_dir() -> PathBuf {
    xdg("XDG_CACHE_HOME", ".cache").join("qi")
}

pub fn runtime_dir() -> PathBuf {
    match env::var_os("XDG_RUNTIME_DIR") {
        Some(v) if !v.is_empty() => PathBuf::from(v),
        _ => env::temp_dir(),
    }
}

/// `~/.config`, for reading other apps' config (Omarchy, fontconfig, terminals).
pub fn user_config_home() -> PathBuf {
    xdg("XDG_CONFIG_HOME", ".config")
}

/// `~/.local/state`, where Omarchy 4 keeps the active theme.
pub fn user_state_home() -> PathBuf {
    xdg("XDG_STATE_HOME", ".local/state")
}

pub fn home_dir() -> PathBuf {
    home()
}

fn block(to: &Path) {
    if !to.exists() {
        BLOCKED.lock().unwrap_or_else(|e| e.into_inner()).push(to.to_path_buf());
    }
}

fn move_if_absent(from: &Path, to: &Path) {
    if !from.exists() || to.exists() {
        return;
    }
    if let Some(parent) = to.parent() {
        if !creation_blocked(parent) {
            let _ = fs::create_dir_all(parent);
        }
    }
    match rename_noreplace(from, to) {
        Ok(()) => {}
        Err(err) if err.raw_os_error() == Some(17) || err.raw_os_error() == Some(2) => {}
        Err(err) => {
            eprintln!("qi: couldn't move {} to {}: {err}", from.display(), to.display());
            if from.exists() && !to.exists() {
                block(to);
            }
        }
    }
}

fn rename_noreplace(from: &Path, to: &Path) -> io::Result<()> {
    use std::ffi::CString;
    use std::os::raw::c_char;
    use std::os::unix::ffi::OsStrExt;
    extern "C" {
        fn renameat2(
            olddirfd: i32,
            oldpath: *const c_char,
            newdirfd: i32,
            newpath: *const c_char,
            flags: u32,
        ) -> i32;
    }
    let from_c = CString::new(from.as_os_str().as_bytes())
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "path"))?;
    let to_c = CString::new(to.as_os_str().as_bytes())
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "path"))?;
    let rc = unsafe { renameat2(-100, from_c.as_ptr(), -100, to_c.as_ptr(), 1) };
    if rc == 0 {
        Ok(())
    } else {
        Err(io::Error::last_os_error())
    }
}

/// Moves Omaweb's directories to Qi. A move, not a copy, and only when the
/// destination is not already there. Qt kept engine data in a nested folder
/// named for the old organization (`…/omaweb/omaweb/QtWebEngine/omaweb`);
/// that becomes `…/qi/qi/QtWebEngine/qi`.
pub fn migrate_legacy_dirs() {
    let config = xdg("XDG_CONFIG_HOME", ".config");
    let data = xdg("XDG_DATA_HOME", ".local/share");
    let state = xdg("XDG_STATE_HOME", ".local/state");
    let cache = xdg("XDG_CACHE_HOME", ".cache");
    let pairs = [
        (config.join("omaweb"), config.join("qi")),
        (data.join("omaweb"), data.join("qi")),
        (state.join("omaweb"), state.join("qi")),
        (cache.join("omaweb"), cache.join("qi")),
        (cache.join("omaweb-cef"), cache.join("qi-cef")),
        (data.join("qi/omaweb"), data.join("qi/qi")),
        (cache.join("qi/omaweb"), cache.join("qi/qi")),
        (data.join("qi/qi/QtWebEngine/omaweb"), data.join("qi/qi/QtWebEngine/qi")),
        (cache.join("qi/qi/QtWebEngine/omaweb"), cache.join("qi/qi/QtWebEngine/qi")),
    ];
    if omaweb_running() {
        eprintln!("qi: Omaweb is still open, so its folders were left where they are");
        for (from, to) in &pairs {
            if from.exists() {
                block(to);
            }
        }
        return;
    }
    for (from, to) in &pairs {
        move_if_absent(from, to);
    }
}
