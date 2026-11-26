//! Profiles, like Chrome's: each one its own cookies, storage, cache,
//! history, bookmarks, passwords and extensions. "Default" keeps the
//! original Qt WebEngine directory, so sign-ins survive upgrades and the
//! rename from Omaweb. Qt's AppDataLocation is organization/application,
//! both `qi`:
//!
//!   ~/.local/share/qi/profiles.json                 the list
//!   ~/.local/share/qi/qi/QtWebEngine/qi             Default's web engine data
//!   ~/.local/share/qi/history.jsonl                 Default's history
//!   ~/.local/share/qi/profiles/<slug>/              any other profile's data
//!   ~/.cache/qi/profiles/<slug>/                    its HTTP cache

use crate::paths;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

pub const DEFAULT: &str = "Default";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Profile {
    pub name: String,
    #[serde(default)]
    pub slug: String,
}

/// What QML needs to make the profile's web engine.
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ProfileInfo {
    pub name: String,
    pub slug: String,
    pub storage_name: String,
    /// Empty: let Qt pick its default (Default only).
    pub storage_path: String,
    pub cache_path: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Profiles {
    pub profiles: Vec<Profile>,
}

/// Lowercase letters, digits and dashes; never empty, never "default".
pub fn slugify(name: &str) -> String {
    let mut s = String::new();
    for c in name.trim().chars() {
        if c.is_ascii_alphanumeric() {
            s.push(c.to_ascii_lowercase());
        } else if !s.ends_with('-') && !s.is_empty() {
            s.push('-');
        }
    }
    let s = s.trim_matches('-').to_string();
    if s.is_empty() {
        "profile".into()
    } else {
        s
    }
}

impl Profiles {
    pub fn path() -> PathBuf {
        paths::data_dir().join("profiles.json")
    }

    pub fn load_from(path: &Path) -> Profiles {
        let mut p: Profiles = fs::read_to_string(path)
            .ok()
            .and_then(|t| serde_json::from_str(&t).ok())
            .unwrap_or_default();
        p.normalize();
        p
    }

    pub fn load() -> Profiles {
        Self::load_from(&Self::path())
    }

    pub fn save_to(&self, path: &Path) -> std::io::Result<()> {
        if let Some(d) = path.parent() {
            paths::create_dir_all(d)?;
        }
        fs::write(path, serde_json::to_string_pretty(self)?)
    }

    pub fn save(&self) -> std::io::Result<()> {
        self.save_to(&Self::path())
    }

    fn normalize(&mut self) {
        let mut seen = std::collections::HashSet::new();
        self.profiles.retain(|p| !p.name.trim().is_empty());
        for p in &mut self.profiles {
            p.slug = if p.name == DEFAULT { "default".into() } else { slugify(&p.name) };
        }
        self.profiles.retain(|p| seen.insert(p.slug.clone()));
        if !self.profiles.iter().any(|p| p.name == DEFAULT) {
            self.profiles.insert(0, Profile { name: DEFAULT.into(), slug: "default".into() });
        }
    }

    pub fn get(&self, name: &str) -> Option<&Profile> {
        self.profiles.iter().find(|p| p.name == name || p.slug == slugify(name))
    }

    /// Adds a profile; returns its canonical name (an existing one when the
    /// slug is taken).
    pub fn add(&mut self, name: &str) -> String {
        let name = name.trim();
        if let Some(p) = self.get(name) {
            return p.name.clone();
        }
        let name = if name.is_empty() { "Profile".to_string() } else { name.to_string() };
        self.profiles.push(Profile { name: name.clone(), slug: String::new() });
        self.normalize();
        name
    }

    /// Takes a profile off the list. Its files stay on disk.
    pub fn remove(&mut self, name: &str) -> bool {
        if name == DEFAULT {
            return false;
        }
        let before = self.profiles.len();
        self.profiles.retain(|p| p.name != name);
        before != self.profiles.len()
    }

    pub fn infos(&self) -> Vec<ProfileInfo> {
        self.profiles.iter().map(info).collect()
    }
}

pub fn data_dir_of(name: &str) -> PathBuf {
    if name == DEFAULT {
        paths::data_dir()
    } else {
        paths::data_dir().join("profiles").join(slugify(name))
    }
}

pub fn info(p: &Profile) -> ProfileInfo {
    if p.name == DEFAULT {
        ProfileInfo {
            name: p.name.clone(),
            slug: "default".into(),
            storage_name: "qi".into(),
            storage_path: String::new(),
            cache_path: String::new(),
        }
    } else {
        let slug = slugify(&p.name);
        ProfileInfo {
            name: p.name.clone(),
            slug: slug.clone(),
            storage_name: format!("qi-{slug}"),
            storage_path: data_dir_of(&p.name).join("engine").to_string_lossy().into_owned(),
            cache_path: paths::cache_dir().join("profiles").join(&slug).to_string_lossy().into_owned(),
        }
    }
}

pub fn history_path(name: &str) -> PathBuf {
    data_dir_of(name).join("history.jsonl")
}

pub fn bookmarks_path(name: &str) -> PathBuf {
    data_dir_of(name).join("bookmarks.json")
}

pub fn passwords_index_path(name: &str) -> PathBuf {
    data_dir_of(name).join("passwords.json")
}

pub fn extensions_src_dir(name: &str) -> PathBuf {
    data_dir_of(name).join("extensions-src")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slugs() {
        assert_eq!(slugify("Work Stuff!"), "work-stuff");
        assert_eq!(slugify("  "), "profile");
        assert_eq!(slugify("Ünïcode 2"), "n-code-2");
    }

    #[test]
    fn default_always_present_and_unique() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("profiles.json");
        let mut ps = Profiles::load_from(&p);
        assert_eq!(ps.profiles.len(), 1);
        assert_eq!(ps.profiles[0].name, DEFAULT);
        assert_eq!(ps.add("Work"), "Work");
        assert_eq!(ps.add("work"), "Work");
        assert_eq!(ps.profiles.len(), 2);
        assert!(!ps.remove(DEFAULT));
        ps.save_to(&p).unwrap();
        let back = Profiles::load_from(&p);
        assert_eq!(back, ps);
        let infos = back.infos();
        assert_eq!(infos[0].storage_name, "qi");
        assert_eq!(infos[0].storage_path, "");
        assert_eq!(infos[1].storage_name, "qi-work");
        assert!(infos[1].storage_path.ends_with("profiles/work/engine"));
    }
}
