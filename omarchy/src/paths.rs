//! XDG locations. Qi keeps config, data and state apart, the way every
//! other Omarchy app does, so `~/.config/qi` can live in a dotfiles repo.
//! On first launch the old `omaweb` directories are moved here.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};

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

fn move_if_absent(from: &Path, to: &Path) {
    if !from.exists() || to.exists() {
        return;
    }
    if let Some(parent) = to.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let _ = fs::rename(from, to);
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
    move_if_absent(&config.join("omaweb"), &config.join("qi"));
    move_if_absent(&data.join("omaweb"), &data.join("qi"));
    move_if_absent(&state.join("omaweb"), &state.join("qi"));
    move_if_absent(&cache.join("omaweb"), &cache.join("qi"));
    move_if_absent(&cache.join("omaweb-cef"), &cache.join("qi-cef"));
    move_if_absent(&data.join("qi/omaweb"), &data.join("qi/qi"));
    move_if_absent(&cache.join("qi/omaweb"), &cache.join("qi/qi"));
    move_if_absent(
        &data.join("qi/qi/QtWebEngine/omaweb"),
        &data.join("qi/qi/QtWebEngine/qi"),
    );
    move_if_absent(
        &cache.join("qi/qi/QtWebEngine/omaweb"),
        &cache.join("qi/qi/QtWebEngine/qi"),
    );
}
