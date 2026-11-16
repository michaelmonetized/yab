//! XDG locations. Omaweb keeps config, data and state apart, the way every
//! other Omarchy app does, so `~/.config/omaweb` can live in a dotfiles repo.

use std::env;
use std::path::PathBuf;

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
    xdg("XDG_CONFIG_HOME", ".config").join("omaweb")
}

pub fn data_dir() -> PathBuf {
    xdg("XDG_DATA_HOME", ".local/share").join("omaweb")
}

pub fn state_dir() -> PathBuf {
    xdg("XDG_STATE_HOME", ".local/state").join("omaweb")
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
