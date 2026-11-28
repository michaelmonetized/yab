//! Reads the active Omarchy theme.
//!
//! Omarchy 4 renders the active theme into `~/.local/state/omarchy/current/theme`,
//! Omarchy 3 into `~/.config/omarchy/current/theme` (a symlink to the theme).
//! Either way the palette is a flat `colors.toml`; older themes only ship an
//! `alacritty.toml`, which we read as a fallback. Missing keys are derived
//! with the same rules `omarchy-theme-color` documents, so Qi agrees with
//! the bar, the terminal and every other themed app.

use crate::paths;
use serde::Serialize;
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Theme {
    pub name: String,
    pub dark: bool,
    pub font: String,
    /// Where the palette came from, for `qi --theme`.
    pub source: String,
    pub colors: BTreeMap<String, String>,
}

/// Tokyo Night, Omarchy's default, for machines without Omarchy.
const FALLBACK: &[(&str, &str)] = &[
    ("accent", "#7aa2f7"),
    ("selection", "#292e42"),
    ("muted", "#414868"),
    ("background", "#1a1b26"),
    ("foreground", "#a9b1d6"),
    ("bright_foreground", "#c0caf5"),
    ("red", "#f7768e"),
    ("yellow", "#e0af68"),
    ("green", "#9ece6a"),
    ("cyan", "#449dab"),
    ("blue", "#7aa2f7"),
    ("magenta", "#ad8ee6"),
];

/// Directories that may hold the active theme, most specific first.
pub fn theme_dirs() -> Vec<PathBuf> {
    if let Some(dir) = std::env::var_os("QI_THEME_DIR").or_else(|| std::env::var_os("OMAWEB_THEME_DIR")) {
        return vec![PathBuf::from(dir)];
    }
    vec![
        paths::user_state_home().join("omarchy/current/theme"),
        paths::user_config_home().join("omarchy/current/theme"),
    ]
}

/// Paths to watch so a theme or font switch reaches Qi. We watch the
/// `current` directories rather than the theme itself because Omarchy swaps
/// the theme in by renaming a staging dir or re-pointing a symlink.
pub fn watch_paths() -> Vec<PathBuf> {
    let mut out = Vec::new();
    for dir in theme_dirs() {
        if let Some(parent) = dir.parent() {
            out.push(parent.to_path_buf());
        }
        out.push(dir);
    }
    out.push(paths::user_config_home().join("fontconfig"));
    out.retain(|p| p.exists());
    out.dedup();
    out
}

pub fn load() -> Theme {
    for dir in theme_dirs() {
        if let Some(t) = load_dir(&dir) {
            return t;
        }
    }
    let mut colors = BTreeMap::new();
    for (k, v) in FALLBACK {
        colors.insert(k.to_string(), v.to_string());
    }
    finish("tokyo-night (built in)".into(), "built-in".into(), colors, None)
}

pub fn load_dir(dir: &Path) -> Option<Theme> {
    let name = theme_name(dir);
    let colors_toml = dir.join("colors.toml");
    if let Ok(text) = fs::read_to_string(&colors_toml) {
        let (colors, mode) = parse_colors_toml(&text);
        if !colors.is_empty() {
            let mode = mode.or_else(|| dir.join("light.mode").exists().then(|| "light".into()));
            return Some(finish(name, colors_toml.display().to_string(), colors, mode));
        }
    }
    let alacritty = dir.join("alacritty.toml");
    if let Ok(text) = fs::read_to_string(&alacritty) {
        let colors = parse_alacritty(&text);
        if !colors.is_empty() {
            let mode = dir.join("light.mode").exists().then(|| "light".into());
            return Some(finish(name, alacritty.display().to_string(), colors, mode));
        }
    }
    None
}

fn theme_name(dir: &Path) -> String {
    // Omarchy 4 writes the name beside the theme.
    if let Some(parent) = dir.parent() {
        if let Ok(n) = fs::read_to_string(parent.join("theme.name")) {
            let n = n.trim();
            if !n.is_empty() {
                return n.to_string();
            }
        }
    }
    // Omarchy 3: `current/theme` is a symlink into `themes/<name>`.
    if let Ok(target) = fs::read_link(dir) {
        if let Some(n) = target.file_name() {
            return n.to_string_lossy().into_owned();
        }
    }
    "omarchy".into()
}

fn parse_colors_toml(text: &str) -> (BTreeMap<String, String>, Option<String>) {
    let mut colors = BTreeMap::new();
    let mut mode = None;
    let Ok(table) = text.parse::<toml::Table>() else {
        return (colors, mode);
    };
    for (k, v) in table {
        let Some(s) = v.as_str() else { continue };
        if k == "mode" {
            mode = Some(s.to_ascii_lowercase());
        } else if let Some(hex) = normalize_hex(s) {
            colors.insert(k, hex);
        }
    }
    (colors, mode)
}

fn parse_alacritty(text: &str) -> BTreeMap<String, String> {
    let mut colors = BTreeMap::new();
    let Ok(table) = text.parse::<toml::Table>() else {
        return colors;
    };
    let Some(c) = table.get("colors").and_then(|c| c.as_table()) else {
        return colors;
    };
    let get = |section: &str, key: &str| -> Option<String> {
        c.get(section)?.as_table()?.get(key)?.as_str().and_then(normalize_hex)
    };
    let names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"];
    for (i, n) in names.iter().enumerate() {
        if let Some(v) = get("normal", n) {
            colors.insert(format!("color{i}"), v.clone());
            if i > 0 && i < 7 {
                colors.insert(n.to_string(), v);
            }
        }
        if let Some(v) = get("bright", n) {
            colors.insert(format!("color{}", i + 8), v.clone());
            if i > 0 && i < 7 {
                colors.insert(format!("bright_{n}"), v);
            }
        }
    }
    if let Some(v) = get("primary", "background") {
        colors.insert("background".into(), v);
    }
    if let Some(v) = get("primary", "foreground") {
        colors.insert("foreground".into(), v);
    }
    if let Some(v) = get("selection", "background") {
        colors.insert("selection".into(), v);
    }
    colors
}

/// Fills every key Qi uses, following Omarchy's documented fallbacks.
fn finish(
    name: String,
    source: String,
    mut c: BTreeMap<String, String>,
    mode: Option<String>,
) -> Theme {
    let pick = |c: &BTreeMap<String, String>, keys: &[&str]| -> Option<String> {
        keys.iter().find_map(|k| c.get(*k).cloned())
    };
    let set_if_missing = |c: &mut BTreeMap<String, String>, key: &str, v: Option<String>| {
        if !c.contains_key(key) {
            if let Some(v) = v {
                c.insert(key.to_string(), v);
            }
        }
    };

    let bg = pick(&c, &["background", "color0"]).unwrap_or_else(|| "#1a1b26".into());
    let fg = pick(&c, &["foreground", "color7"]).unwrap_or_else(|| "#a9b1d6".into());
    c.insert("background".into(), bg.clone());
    c.insert("foreground".into(), fg.clone());
    let v = pick(&c, &["color7"]).or(Some(fg.clone()));
    set_if_missing(&mut c, "light_foreground", v);
    let v = pick(&c, &["color15"]).or(Some(fg.clone()));
    set_if_missing(&mut c, "bright_foreground", v);
    let v = pick(&c, &["color8"]).or(Some(mix(&fg, &bg, 0.4)));
    set_if_missing(&mut c, "dark_foreground", v);
    let v = pick(&c, &["color8", "dark_foreground"]);
    set_if_missing(&mut c, "muted", v);
    let v = pick(&c, &["selection_background", "color8", "color0"]).or(Some(bg.clone()));
    set_if_missing(&mut c, "selection", v);

    let dark = match mode.as_deref() {
        Some("light") => false,
        Some("dark") => true,
        _ => luminance(&bg) < 0.5,
    };
    let away = if dark { "#000000" } else { "#ffffff" };
    set_if_missing(&mut c, "dark_background", Some(mix(&bg, away, 0.25)));
    set_if_missing(&mut c, "darker_background", Some(mix(&bg, away, 0.5)));
    let toward = if dark { "#ffffff" } else { "#000000" };
    let v = pick(&c, &["color0"]).filter(|v| *v != bg).or(Some(mix(&bg, toward, 0.06)));
    set_if_missing(&mut c, "lighter_background", v);

    for (i, n) in ["red", "green", "yellow", "blue", "magenta", "cyan"].iter().enumerate() {
        let v = pick(&c, &[&format!("color{}", i + 1)]);
        set_if_missing(&mut c, n, v);
    }
    let v = pick(&c, &["yellow"]);
    set_if_missing(&mut c, "orange", v);
    let v = pick(&c, &["accent", "color4", "blue"]).or(Some("#7aa2f7".into()));
    set_if_missing(&mut c, "accent", v);
    for (k, v) in FALLBACK {
        set_if_missing(&mut c, k, Some(v.to_string()));
    }

    // Text drawn on the accent (the active tab, the selected suggestion).
    let accent = c["accent"].clone();
    let on_accent = if contrast(&accent, &c["background"]) >= contrast(&accent, &c["bright_foreground"]) {
        c["background"].clone()
    } else {
        c["bright_foreground"].clone()
    };
    c.insert("on_accent".into(), on_accent);

    Theme { name, dark, font: current_font(), source, colors: c }
}

/// Omarchy sets the system monospace font through fontconfig
/// (`omarchy-font-set`), and mirrors it into the terminal configs.
pub fn current_font() -> String {
    for key in ["QI_FONT", "OMAWEB_FONT"] {
        if let Ok(f) = std::env::var(key) {
            if !f.trim().is_empty() {
                return f.trim().to_string();
            }
        }
    }
    let cfg = paths::user_config_home();
    if let Ok(xml) = fs::read_to_string(cfg.join("fontconfig/fonts.conf")) {
        if let Some(f) = fontconfig_monospace(&xml) {
            return f;
        }
    }
    if let Ok(text) = fs::read_to_string(cfg.join("alacritty/alacritty.toml")) {
        if let Ok(t) = text.parse::<toml::Table>() {
            if let Some(f) = t
                .get("font")
                .and_then(|f| f.get("normal"))
                .and_then(|n| n.get("family"))
                .and_then(|f| f.as_str())
            {
                return f.to_string();
            }
        }
    }
    if let Ok(text) = fs::read_to_string(cfg.join("ghostty/config")) {
        for line in text.lines() {
            if let Some(rest) = line.trim().strip_prefix("font-family") {
                let v = rest.trim_start_matches([' ', '=']).trim().trim_matches('"');
                if !v.is_empty() {
                    return v.to_string();
                }
            }
        }
    }
    "JetBrainsMono Nerd Font".into()
}

fn fontconfig_monospace(xml: &str) -> Option<String> {
    // Looks for <alias><family>monospace</family><prefer><family>X</family>.
    let idx = xml.find("<family>monospace</family>")?;
    let rest = &xml[idx + "<family>monospace</family>".len()..];
    let start = rest.find("<family>")? + "<family>".len();
    let end = rest[start..].find("</family>")? + start;
    let f = rest[start..end].trim();
    (!f.is_empty()).then(|| f.to_string())
}

pub fn normalize_hex(s: &str) -> Option<String> {
    let s = s.trim();
    let h = s.strip_prefix('#').or_else(|| s.strip_prefix("0x")).unwrap_or(s);
    if !h.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    match h.len() {
        6 | 8 => Some(format!("#{}", h[..6].to_ascii_lowercase())),
        3 => {
            let e: String = h.chars().flat_map(|c| [c, c]).collect();
            Some(format!("#{}", e.to_ascii_lowercase()))
        }
        _ => None,
    }
}

fn rgb(hex: &str) -> (f64, f64, f64) {
    let h = hex.trim_start_matches('#');
    let p = |i: usize| u8::from_str_radix(h.get(i..i + 2).unwrap_or("00"), 16).unwrap_or(0) as f64;
    (p(0), p(2), p(4))
}

pub fn mix(a: &str, b: &str, t: f64) -> String {
    let (ar, ag, ab) = rgb(a);
    let (br, bg, bb) = rgb(b);
    let m = |x: f64, y: f64| (x + (y - x) * t).round().clamp(0.0, 255.0) as u8;
    format!("#{:02x}{:02x}{:02x}", m(ar, br), m(ag, bg), m(ab, bb))
}

pub fn luminance(hex: &str) -> f64 {
    let (r, g, b) = rgb(hex);
    let lin = |c: f64| {
        let c = c / 255.0;
        if c <= 0.03928 { c / 12.92 } else { ((c + 0.055) / 1.055).powf(2.4) }
    };
    0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
}

fn contrast(a: &str, b: &str) -> f64 {
    let (la, lb) = (luminance(a), luminance(b));
    (la.max(lb) + 0.05) / (la.min(lb) + 0.05)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_colors_toml_and_derives_missing_keys() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("colors.toml"),
            "mode = \"dark\"\naccent = \"#4fa3a5\"\nbackground = \"#101a1f\"\nforeground = \"#c2d2d8\"\n",
        )
        .unwrap();
        let t = load_dir(dir.path()).unwrap();
        assert!(t.dark);
        assert_eq!(t.colors["accent"], "#4fa3a5");
        assert_eq!(t.colors["background"], "#101a1f");
        assert_eq!(t.colors["darker_background"], mix("#101a1f", "#000000", 0.5));
        assert!(t.colors.contains_key("on_accent"));
        assert!(t.colors.contains_key("muted"));
    }

    #[test]
    fn light_mode_from_marker() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("colors.toml"), "background = \"#fcfcfc\"\nforeground = \"#222222\"\n").unwrap();
        fs::write(dir.path().join("light.mode"), "").unwrap();
        assert!(!load_dir(dir.path()).unwrap().dark);
    }

    #[test]
    fn falls_back_to_alacritty() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("alacritty.toml"),
            "[colors.primary]\nbackground = \"0x282828\"\nforeground = \"#ebdbb2\"\n[colors.normal]\nblue = \"#458588\"\nred = \"#cc241d\"\n",
        )
        .unwrap();
        let t = load_dir(dir.path()).unwrap();
        assert_eq!(t.colors["background"], "#282828");
        assert_eq!(t.colors["accent"], "#458588");
        assert_eq!(t.colors["red"], "#cc241d");
    }

    #[test]
    fn hex_forms() {
        assert_eq!(normalize_hex("0xAABBCC").as_deref(), Some("#aabbcc"));
        assert_eq!(normalize_hex("#abc").as_deref(), Some("#aabbcc"));
        assert_eq!(normalize_hex("#11223344").as_deref(), Some("#112233"));
        assert_eq!(normalize_hex("red"), None);
    }

    #[test]
    fn fontconfig_parse() {
        let xml = "<fontconfig><alias><family>monospace</family><prefer><family>CaskaydiaMono Nerd Font</family></prefer></alias></fontconfig>";
        assert_eq!(fontconfig_monospace(xml).as_deref(), Some("CaskaydiaMono Nerd Font"));
    }
}
