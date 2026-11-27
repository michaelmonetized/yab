//! XDG locations. Qi keeps config, data and state apart, the way every
//! other Omarchy app does, so `~/.config/qi` can live in a dotfiles repo.
//! On first launch the old `omaweb` directories are moved here.

use std::env;
use std::fs;
use std::io;
use std::os::unix::fs::MetadataExt;
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

fn current_uid() -> u32 {
    extern "C" {
        fn geteuid() -> u32;
    }
    unsafe { geteuid() }
}

fn omaweb_running() -> bool {
    let Ok(entries) = fs::read_dir("/proc") else {
        return false;
    };
    let uid = current_uid();
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(meta) = fs::metadata(&path) else {
            continue;
        };
        if meta.uid() != uid {
            continue;
        }
        let comm = fs::read_to_string(path.join("comm")).unwrap_or_default();
        if comm.trim() == "omaweb" {
            return true;
        }
    }
    false
}

fn home() -> PathBuf {
    env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"))
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
        BLOCKED
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .push(to.to_path_buf());
    }
}

fn real_dir(path: &Path) -> bool {
    fs::symlink_metadata(path)
        .map(|meta| meta.is_dir())
        .unwrap_or(false)
}

/// A directory is a stub when it holds nothing but empty directories.
/// Symlinks count as content so the walk never follows one.
fn stub_dir(path: &Path) -> bool {
    if !real_dir(path) {
        return false;
    }
    let Ok(entries) = fs::read_dir(path) else {
        return false;
    };
    for entry in entries {
        let Ok(entry) = entry else {
            return false;
        };
        if !stub_dir(&entry.path()) {
            return false;
        }
    }
    true
}

fn remove_stub(path: &Path) -> io::Result<()> {
    if !real_dir(path) {
        return Err(io::Error::new(io::ErrorKind::Other, "not a stub"));
    }
    for entry in fs::read_dir(path)? {
        remove_stub(&entry?.path())?;
    }
    fs::remove_dir(path)
}

fn move_if_absent(from: &Path, to: &Path) {
    if fs::symlink_metadata(from).is_err() {
        return;
    }
    match fs::symlink_metadata(to) {
        Err(err) if err.kind() == io::ErrorKind::NotFound => relocate(from, to),
        Ok(_) if real_dir(from) && real_dir(to) => {
            if stub_dir(to) && remove_stub(to).is_ok() {
                relocate(from, to);
            } else {
                merge_dirs(from, to);
            }
        }
        _ => {}
    }
}

fn relocate(from: &Path, to: &Path) {
    match rename_onto(from, to) {
        Ok(()) => {}
        Err(err) if err.raw_os_error() == Some(2) => {}
        Err(err) if err.raw_os_error() == Some(17) && real_dir(from) && real_dir(to) => {
            merge_dirs(from, to);
        }
        Err(err) => {
            eprintln!(
                "qi: couldn't move {} to {}: {err}",
                from.display(),
                to.display()
            );
            if from.exists() && !to.exists() {
                block(to);
            }
        }
    }
}

fn rename_onto(from: &Path, to: &Path) -> io::Result<()> {
    if let Some(parent) = to.parent() {
        if !creation_blocked(parent) {
            let _ = fs::create_dir_all(parent);
        }
    }
    rename_noreplace(from, to)
}

/// Moves each missing child from `from` into `to`. An existing file stays,
/// and so does its copy in `from`, so a later launch can try again. `from`
/// is removed only once nothing is left in it.
fn merge_dirs(from: &Path, to: &Path) {
    let Ok(entries) = fs::read_dir(from) else {
        return;
    };
    let names: Vec<_> = entries
        .filter_map(|entry| entry.ok().map(|entry| entry.file_name()))
        .collect();
    for name in names {
        let src = from.join(&name);
        let dst = to.join(&name);
        if fs::symlink_metadata(&src).is_err() {
            continue;
        }
        match fs::symlink_metadata(&dst) {
            Err(err) if err.kind() == io::ErrorKind::NotFound => relocate(&src, &dst),
            Ok(_) if real_dir(&src) && real_dir(&dst) => {
                if stub_dir(&dst) && remove_stub(&dst).is_ok() {
                    relocate(&src, &dst);
                } else if real_dir(&dst) {
                    merge_dirs(&src, &dst);
                }
            }
            _ => {}
        }
    }
    let _ = fs::remove_dir(from);
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

/// Moves Omaweb's directories to Qi. A move, not a copy. An empty destination
/// is cleared so the old directory can take its place. A destination that
/// already holds files keeps them and receives the rest; a file that would
/// be overwritten stays in the old directory for a later launch. Qt kept
/// engine data in a nested folder named for the old organization
/// (`…/omaweb/omaweb/QtWebEngine/omaweb`); that becomes `…/qi/qi/QtWebEngine/qi`.
///
/// Returns false when Omaweb is still running and the directories were left
/// where they are. The caller must not open a Qt profile until this is true.
pub fn migrate_legacy_dirs() -> bool {
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
        (
            data.join("qi/qi/QtWebEngine/omaweb"),
            data.join("qi/qi/QtWebEngine/qi"),
        ),
        (
            cache.join("qi/qi/QtWebEngine/omaweb"),
            cache.join("qi/qi/QtWebEngine/qi"),
        ),
    ];
    if omaweb_running() {
        eprintln!("qi: Omaweb is still open, so its folders were left where they are");
        for (from, to) in &pairs {
            if from.exists() {
                block(to);
            }
        }
        return false;
    }
    for (from, to) in &pairs {
        move_if_absent(from, to);
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::symlink;

    fn write(path: &Path, body: &str) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, body).unwrap();
    }

    #[test]
    fn moves_the_tree_when_the_destination_is_missing() {
        let dir = tempfile::tempdir().unwrap();
        let from = dir.path().join("omaweb");
        let to = dir.path().join("qi");
        write(&from.join("bookmarks.json"), "old");
        write(&from.join("nested/a.txt"), "a");
        move_if_absent(&from, &to);
        assert!(!from.exists());
        assert_eq!(
            fs::read_to_string(to.join("bookmarks.json")).unwrap(),
            "old"
        );
        assert_eq!(fs::read_to_string(to.join("nested/a.txt")).unwrap(), "a");
    }

    #[test]
    fn replaces_an_empty_destination() {
        let dir = tempfile::tempdir().unwrap();
        let from = dir.path().join("omaweb");
        let to = dir.path().join("qi");
        write(&from.join("bookmarks.json"), "old");
        fs::create_dir_all(&to).unwrap();
        move_if_absent(&from, &to);
        assert!(!from.exists());
        assert_eq!(
            fs::read_to_string(to.join("bookmarks.json")).unwrap(),
            "old"
        );
    }

    #[test]
    fn replaces_a_destination_of_only_empty_directories() {
        let dir = tempfile::tempdir().unwrap();
        let from = dir.path().join("omaweb");
        let to = dir.path().join("qi");
        write(&from.join("bookmarks.json"), "old");
        fs::create_dir_all(to.join("empty/deeper")).unwrap();
        move_if_absent(&from, &to);
        assert!(!from.exists());
        assert_eq!(
            fs::read_to_string(to.join("bookmarks.json")).unwrap(),
            "old"
        );
        assert!(!to.join("empty").exists());
    }

    #[test]
    fn merges_a_partial_destination_and_retries_the_rest() {
        let dir = tempfile::tempdir().unwrap();
        let from = dir.path().join("omaweb");
        let to = dir.path().join("qi");
        write(&from.join("settings.toml"), "legacy");
        write(&from.join("bookmarks.json"), "old-marks");
        write(&from.join("keep/note.txt"), "note");
        write(&to.join("settings.toml"), "qi-wrote-this");
        move_if_absent(&from, &to);
        assert_eq!(
            fs::read_to_string(to.join("settings.toml")).unwrap(),
            "qi-wrote-this"
        );
        assert_eq!(
            fs::read_to_string(to.join("bookmarks.json")).unwrap(),
            "old-marks"
        );
        assert_eq!(
            fs::read_to_string(to.join("keep/note.txt")).unwrap(),
            "note"
        );
        assert_eq!(
            fs::read_to_string(from.join("settings.toml")).unwrap(),
            "legacy"
        );
        assert!(!from.join("bookmarks.json").exists());
        assert!(!from.join("keep").exists());

        move_if_absent(&from, &to);
        assert_eq!(
            fs::read_to_string(to.join("settings.toml")).unwrap(),
            "qi-wrote-this"
        );
        assert!(from.join("settings.toml").is_file());

        fs::remove_file(to.join("settings.toml")).unwrap();
        move_if_absent(&from, &to);
        assert!(!from.exists());
        assert_eq!(
            fs::read_to_string(to.join("settings.toml")).unwrap(),
            "legacy"
        );
    }

    #[test]
    fn merges_a_partial_child_and_replaces_a_stub_child() {
        let dir = tempfile::tempdir().unwrap();
        let from = dir.path().join("omaweb");
        let to = dir.path().join("qi");
        write(&from.join("sub/a.txt"), "legacy-a");
        write(&from.join("sub/b.txt"), "legacy-b");
        write(&from.join("stubbed/c.txt"), "legacy-c");
        write(&to.join("sub/a.txt"), "qi-a");
        fs::create_dir_all(to.join("stubbed/empty")).unwrap();
        move_if_absent(&from, &to);
        assert_eq!(fs::read_to_string(to.join("sub/a.txt")).unwrap(), "qi-a");
        assert_eq!(
            fs::read_to_string(to.join("sub/b.txt")).unwrap(),
            "legacy-b"
        );
        assert_eq!(
            fs::read_to_string(from.join("sub/a.txt")).unwrap(),
            "legacy-a"
        );
        assert!(!from.join("sub/b.txt").exists());
        assert_eq!(
            fs::read_to_string(to.join("stubbed/c.txt")).unwrap(),
            "legacy-c"
        );
        assert!(!to.join("stubbed/empty").exists());
        assert!(!from.join("stubbed").exists());
    }

    #[test]
    fn leaves_a_symlink_destination_alone() {
        let dir = tempfile::tempdir().unwrap();
        let from = dir.path().join("omaweb");
        let to = dir.path().join("qi");
        let elsewhere = dir.path().join("elsewhere");
        write(&from.join("secret.txt"), "legacy");
        fs::create_dir_all(&elsewhere).unwrap();
        symlink(&elsewhere, &to).unwrap();
        move_if_absent(&from, &to);
        assert_eq!(
            fs::read_to_string(from.join("secret.txt")).unwrap(),
            "legacy"
        );
        assert!(!elsewhere.join("secret.txt").exists());
        assert!(fs::symlink_metadata(&to).unwrap().file_type().is_symlink());
    }

    #[test]
    fn does_not_follow_a_symlink_inside_the_destination() {
        let dir = tempfile::tempdir().unwrap();
        let from = dir.path().join("omaweb");
        let to = dir.path().join("qi");
        let elsewhere = dir.path().join("elsewhere");
        write(&from.join("link/secret.txt"), "legacy");
        fs::create_dir_all(&to).unwrap();
        fs::create_dir_all(&elsewhere).unwrap();
        symlink(&elsewhere, to.join("link")).unwrap();
        move_if_absent(&from, &to);
        assert_eq!(
            fs::read_to_string(from.join("link/secret.txt")).unwrap(),
            "legacy"
        );
        assert!(!elsewhere.join("secret.txt").exists());
    }
}
