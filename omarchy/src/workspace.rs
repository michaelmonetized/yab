//! Spaces, folders, favorites, pinned and today tabs, and the archive: the
//! shape of the sidebar, as Arc and Yab have it.
//!
//! QML keeps one `Workspace` as JSON and every structural change goes
//! through [`apply`], so the rules live here and are tested here. QML only
//! writes the fields that follow a live page: url, title, last_active.
//! Saved to `~/.local/state/qi/workspace.json`; private tabs never are.

use crate::session::Session;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashSet;
use std::fs;
use std::path::Path;

/// Theme colour keys a space can take, in the order new spaces get them.
pub const SPACE_COLORS: &[&str] = &["accent", "blue", "magenta", "green", "yellow", "cyan", "red"];
const ARCHIVE_CAP: usize = 500;

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct TabRec {
    pub uid: String,
    pub url: String,
    pub title: String,
    /// Pinned tabs stay until closed and never archive; today tabs do.
    pub pinned: bool,
    /// Folder id, empty for none. Only pinned tabs live in folders.
    pub folder: String,
    /// Where a pinned tab or favorite goes back to.
    pub pinned_url: String,
    /// Unix seconds the tab was last looked at.
    pub last_active: u64,
    #[serde(skip_serializing_if = "std::ops::Not::not")]
    pub private: bool,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct Folder {
    pub id: String,
    pub name: String,
    pub collapsed: bool,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct Space {
    pub id: String,
    pub name: String,
    /// A theme colour key (see SPACE_COLORS): the space's accent follows
    /// the Omarchy theme instead of being a fixed colour.
    pub color: String,
    /// One character or emoji shown in the footer.
    pub icon: String,
    /// The profile (cookies, extensions, history) the space's tabs use.
    pub profile: String,
    pub folders: Vec<Folder>,
    pub tabs: Vec<TabRec>,
    /// uid of the tab last selected in this space.
    pub current: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct ArchivedTab {
    pub url: String,
    pub title: String,
    pub space: String,
    pub archived_at: u64,
}

/// "Tell me when this drops under $200": the agent re-reads a tab now and
/// then and says when the condition holds.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct Watch {
    pub id: String,
    pub tab_uid: String,
    pub url: String,
    pub title: String,
    pub condition: String,
    pub every_minutes: u32,
    pub last_checked: u64,
    pub last_result: String,
    pub done: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct Workspace {
    pub version: u32,
    pub spaces: Vec<Space>,
    /// Tiles at the top of the sidebar, the same in every space.
    pub favorites: Vec<TabRec>,
    pub current_space: String,
    /// uid of the selected tab when it is a favorite.
    pub current_favorite: String,
    pub archive: Vec<ArchivedTab>,
    pub watches: Vec<Watch>,
}

impl Default for Workspace {
    fn default() -> Self {
        Workspace {
            version: 2,
            spaces: vec![new_space("home", "Home", "Default", 0)],
            favorites: Vec::new(),
            current_space: "home".into(),
            current_favorite: String::new(),
            archive: Vec::new(),
            watches: Vec::new(),
        }
    }
}

pub fn new_space(id: &str, name: &str, profile: &str, n: usize) -> Space {
    Space {
        id: id.into(),
        name: name.into(),
        color: SPACE_COLORS[n % SPACE_COLORS.len()].into(),
        icon: name.chars().next().map(|c| c.to_uppercase().collect()).unwrap_or_else(|| "·".into()),
        profile: profile.into(),
        ..Default::default()
    }
}

impl Workspace {
    pub fn load(path: &Path) -> Option<Workspace> {
        let text = fs::read_to_string(path).ok()?;
        serde_json::from_str::<Workspace>(&text).ok().map(|w| w.sanitized(false))
    }

    pub fn save(&self, path: &Path) -> std::io::Result<()> {
        if let Some(dir) = path.parent() {
            fs::create_dir_all(dir)?;
        }
        let tmp = path.with_extension("json.tmp");
        fs::write(&tmp, serde_json::to_string_pretty(&self.clone().sanitized(true))?)?;
        fs::rename(tmp, path)
    }

    /// The old single-list session becomes the Home space's today tabs.
    pub fn from_session(s: &Session, profile: &str) -> Workspace {
        let mut w = Workspace::default();
        w.spaces[0].profile = profile.into();
        for (i, t) in s.tabs.iter().enumerate() {
            w.spaces[0].tabs.push(TabRec {
                uid: format!("t{i}"),
                url: t.url.clone(),
                title: t.title.clone(),
                private: t.private,
                ..Default::default()
            });
        }
        if let Some(t) = w.spaces[0].tabs.get(s.current) {
            w.spaces[0].current = t.uid.clone();
        }
        w
    }

    /// Repairs anything a crash or a hand edit could leave behind. With
    /// `for_disk`, also drops private and blank tabs.
    pub fn sanitized(mut self, for_disk: bool) -> Workspace {
        self.version = 2;
        let mut uids = HashSet::new();
        let keep = |t: &TabRec, uids: &mut HashSet<String>| -> bool {
            if for_disk && (t.private || t.url.is_empty() || t.url == "about:blank") {
                return false;
            }
            !t.uid.is_empty() && uids.insert(t.uid.clone())
        };
        self.favorites.retain(|t| keep(t, &mut uids));
        for f in &mut self.favorites {
            f.pinned = true;
            f.folder.clear();
            f.private = false;
        }
        let mut space_ids = HashSet::new();
        self.spaces.retain(|s| !s.id.is_empty() && space_ids.insert(s.id.clone()));
        if self.spaces.is_empty() {
            self.spaces.push(new_space("home", "Home", "Default", 0));
        }
        for s in &mut self.spaces {
            if s.profile.is_empty() {
                s.profile = "Default".into();
            }
            if s.color.is_empty() {
                s.color = "accent".into();
            }
            let mut fids = HashSet::new();
            s.folders.retain(|f| !f.id.is_empty() && fids.insert(f.id.clone()));
            s.tabs.retain(|t| keep(t, &mut uids));
            for t in &mut s.tabs {
                if !t.folder.is_empty() && !fids.contains(&t.folder) {
                    t.folder.clear();
                }
                if !t.folder.is_empty() {
                    t.pinned = true;
                }
                if t.private {
                    t.pinned = false;
                    t.folder.clear();
                }
            }
            if !s.tabs.iter().any(|t| t.uid == s.current) {
                s.current = s.tabs.last().map(|t| t.uid.clone()).unwrap_or_default();
            }
        }
        if !self.spaces.iter().any(|s| s.id == self.current_space) {
            self.current_space = self.spaces[0].id.clone();
        }
        if !self.favorites.iter().any(|t| t.uid == self.current_favorite) {
            self.current_favorite.clear();
        }
        let watched: HashSet<String> = self.all_tabs().map(|t| t.uid.clone()).collect();
        self.watches.retain(|w| !w.done || watched.contains(&w.tab_uid));
        if self.archive.len() > ARCHIVE_CAP {
            let cut = self.archive.len() - ARCHIVE_CAP;
            self.archive.drain(..cut);
        }
        self
    }

    pub fn all_tabs(&self) -> impl Iterator<Item = &TabRec> {
        self.favorites.iter().chain(self.spaces.iter().flat_map(|s| s.tabs.iter()))
    }

    fn space_mut(&mut self, id: &str) -> Result<&mut Space, String> {
        self.spaces.iter_mut().find(|s| s.id == id).ok_or_else(|| format!("no space {id}"))
    }

    /// Takes a tab out wherever it is; returns it and the space it was in
    /// ("" for favorites).
    fn take(&mut self, uid: &str) -> Option<(TabRec, String)> {
        if let Some(i) = self.favorites.iter().position(|t| t.uid == uid) {
            return Some((self.favorites.remove(i), String::new()));
        }
        for s in &mut self.spaces {
            if let Some(i) = s.tabs.iter().position(|t| t.uid == uid) {
                return Some((s.tabs.remove(i), s.id.clone()));
            }
        }
        None
    }

    fn find_mut(&mut self, uid: &str) -> Option<&mut TabRec> {
        let fav = self.favorites.iter_mut();
        let rest = self.spaces.iter_mut().flat_map(|s| s.tabs.iter_mut());
        fav.chain(rest).find(|t| t.uid == uid)
    }

    /// Today tabs not looked at for `hours`, except each space's current
    /// tab and private ones (which go when closed anyway).
    pub fn archive_due(&self, now: u64, hours: f64) -> Vec<String> {
        if hours <= 0.0 {
            return Vec::new();
        }
        let limit = (hours * 3600.0) as u64;
        let mut out = Vec::new();
        for s in &self.spaces {
            for t in &s.tabs {
                if !t.pinned && !t.private && t.uid != s.current && t.last_active > 0 && now.saturating_sub(t.last_active) > limit {
                    out.push(t.uid.clone());
                }
            }
        }
        out
    }

    fn archive_tabs(&mut self, uids: &[String], now: u64) {
        for uid in uids {
            if let Some((t, space)) = self.take(uid) {
                if !t.private && !t.url.is_empty() && t.url != "about:blank" {
                    let name = self.spaces.iter().find(|s| s.id == space).map(|s| s.name.clone()).unwrap_or_default();
                    self.archive.push(ArchivedTab { url: t.url, title: t.title, space: name, archived_at: now });
                }
            }
        }
    }
}

fn s<'a>(op: &'a Value, k: &str) -> &'a str {
    op.get(k).and_then(Value::as_str).unwrap_or("")
}
fn b(op: &Value, k: &str) -> Option<bool> {
    op.get(k).and_then(Value::as_bool)
}
fn n(op: &Value, k: &str) -> u64 {
    op.get(k).and_then(Value::as_u64).unwrap_or(0)
}

/// Inserts `t` into `list` before `before` (uid), or at the end of its
/// group: pinned tabs stay above today tabs.
fn insert_tab(list: &mut Vec<TabRec>, t: TabRec, before: &str, after: &str) {
    if let Some(i) = list.iter().position(|x| x.uid == before) {
        list.insert(i, t);
    } else if let Some(i) = list.iter().position(|x| x.uid == after) {
        list.insert(i + 1, t);
    } else if t.pinned {
        let i = list.iter().rposition(|x| x.pinned).map(|i| i + 1).unwrap_or(0);
        list.insert(i, t);
    } else {
        list.push(t);
    }
}

/// One change to the workspace. Returns the new workspace or why not.
pub fn apply(mut w: Workspace, op: &Value) -> Result<Workspace, String> {
    match s(op, "op") {
        "new_tab" => {
            let space = if s(op, "space").is_empty() { w.current_space.clone() } else { s(op, "space").to_string() };
            let t = TabRec {
                uid: s(op, "uid").to_string(),
                url: s(op, "url").to_string(),
                title: s(op, "title").to_string(),
                private: b(op, "private").unwrap_or(false),
                last_active: n(op, "now"),
                ..Default::default()
            };
            if t.uid.is_empty() {
                return Err("tab needs a uid".into());
            }
            let sp = w.space_mut(&space)?;
            insert_tab(&mut sp.tabs, t, "", s(op, "after"));
        }
        "close_tab" => {
            w.take(s(op, "uid")).ok_or("no such tab")?;
        }
        "select" => {
            let uid = s(op, "uid").to_string();
            let now = n(op, "now");
            if w.favorites.iter().any(|t| t.uid == uid) {
                w.current_favorite = uid.clone();
            } else {
                let sid = w.spaces.iter().find(|sp| sp.tabs.iter().any(|t| t.uid == uid)).map(|sp| sp.id.clone()).ok_or("no such tab")?;
                w.current_space = sid.clone();
                w.current_favorite.clear();
                w.space_mut(&sid)?.current = uid.clone();
            }
            if let Some(t) = w.find_mut(&uid) {
                t.last_active = now;
            }
        }
        "pin" => {
            let on = b(op, "on").unwrap_or(true);
            let (mut t, space) = w.take(s(op, "uid")).ok_or("no such tab")?;
            if t.private {
                return Err("private tabs can't be pinned".into());
            }
            let space = if space.is_empty() { w.current_space.clone() } else { space };
            t.pinned = on;
            if on {
                t.pinned_url = t.url.clone();
            } else {
                t.folder.clear();
            }
            let sp = w.space_mut(&space)?;
            insert_tab(&mut sp.tabs, t, "", "");
        }
        "favorite" => {
            let on = b(op, "on").unwrap_or(true);
            let uid = s(op, "uid").to_string();
            let (mut t, space) = w.take(&uid).ok_or("no such tab")?;
            if t.private {
                return Err("private tabs can't be favorites".into());
            }
            if on {
                t.pinned = true;
                t.folder.clear();
                if t.pinned_url.is_empty() {
                    t.pinned_url = t.url.clone();
                }
                let i = (n(op, "index") as usize).min(w.favorites.len());
                let i = if op.get("index").is_some() { i } else { w.favorites.len() };
                w.favorites.insert(i, t);
                if !space.is_empty() {
                    let sp = w.space_mut(&space)?;
                    if sp.current == uid {
                        sp.current.clear();
                    }
                    w.current_favorite = uid;
                }
            } else {
                let target = if space.is_empty() { w.current_space.clone() } else { space };
                if w.current_favorite == uid {
                    w.current_favorite.clear();
                }
                let sp = w.space_mut(&target)?;
                insert_tab(&mut sp.tabs, t, "", "");
                sp.current = uid;
            }
        }
        "move_tab" => {
            // Drag and drop: into a folder, out of one, between pinned and
            // today, to another space, before another tab.
            let uid = s(op, "uid").to_string();
            let before = s(op, "before").to_string();
            let (mut t, from) = w.take(&uid).ok_or("no such tab")?;
            let to = if s(op, "space").is_empty() { if from.is_empty() { w.current_space.clone() } else { from.clone() } } else { s(op, "space").to_string() };
            let folder = s(op, "folder").to_string();
            if !folder.is_empty() {
                let sp = w.spaces.iter().find(|sp| sp.id == to).ok_or("no such space")?;
                if !sp.folders.iter().any(|f| f.id == folder) {
                    return Err("no such folder".into());
                }
                if t.private {
                    return Err("private tabs can't go in folders".into());
                }
                t.pinned = true;
            } else if let Some(p) = b(op, "pinned") {
                if t.private && p {
                    return Err("private tabs can't be pinned".into());
                }
                t.pinned = p;
            }
            if op.get("folder").is_some() {
                t.folder = folder;
            }
            if t.pinned && t.pinned_url.is_empty() {
                t.pinned_url = t.url.clone();
            }
            if w.current_favorite == uid {
                w.current_favorite.clear();
            }
            let sp = w.space_mut(&to)?;
            insert_tab(&mut sp.tabs, t, &before, "");
            if from != to {
                if let Some(f) = w.spaces.iter_mut().find(|sp| sp.id == from) {
                    if f.current == uid {
                        f.current.clear();
                    }
                }
            }
        }
        "reset_pinned" => {
            let t = w.find_mut(s(op, "uid")).ok_or("no such tab")?;
            if !t.pinned_url.is_empty() {
                t.url = t.pinned_url.clone();
            }
        }
        "add_folder" => {
            let id = s(op, "id").to_string();
            let name = if s(op, "name").is_empty() { "New folder" } else { s(op, "name") };
            let space = if s(op, "space").is_empty() { w.current_space.clone() } else { s(op, "space").to_string() };
            if id.is_empty() || w.spaces.iter().any(|sp| sp.folders.iter().any(|f| f.id == id)) {
                return Err("folder needs a new id".into());
            }
            w.space_mut(&space)?.folders.push(Folder { id, name: name.into(), collapsed: false });
        }
        "rename_folder" | "toggle_folder" | "remove_folder" => {
            let id = s(op, "id").to_string();
            let sp = w.spaces.iter_mut().find(|sp| sp.folders.iter().any(|f| f.id == id)).ok_or("no such folder")?;
            match s(op, "op") {
                "rename_folder" => {
                    let name = s(op, "name").trim();
                    if name.is_empty() {
                        return Err("a folder needs a name".into());
                    }
                    sp.folders.iter_mut().find(|f| f.id == id).unwrap().name = name.into();
                }
                "toggle_folder" => {
                    let f = sp.folders.iter_mut().find(|f| f.id == id).unwrap();
                    f.collapsed = b(op, "collapsed").unwrap_or(!f.collapsed);
                }
                _ => {
                    // Its tabs stay, pinned, out of the folder.
                    sp.folders.retain(|f| f.id != id);
                    for t in &mut sp.tabs {
                        if t.folder == id {
                            t.folder.clear();
                        }
                    }
                }
            }
        }
        "add_space" => {
            let id = s(op, "id").to_string();
            if id.is_empty() || w.spaces.iter().any(|sp| sp.id == id) {
                return Err("space needs a new id".into());
            }
            let name = if s(op, "name").is_empty() { "Space" } else { s(op, "name") };
            let profile = if s(op, "profile").is_empty() { w.spaces[0].profile.clone() } else { s(op, "profile").to_string() };
            let sp = new_space(&id, name, &profile, w.spaces.len());
            w.spaces.push(sp);
            if b(op, "switch").unwrap_or(true) {
                w.current_space = id;
                w.current_favorite.clear();
            }
        }
        "update_space" => {
            let sp = w.space_mut(s(op, "id"))?;
            if !s(op, "name").trim().is_empty() {
                sp.name = s(op, "name").trim().into();
            }
            if !s(op, "color").is_empty() {
                sp.color = s(op, "color").into();
            }
            if !s(op, "icon").is_empty() {
                sp.icon = s(op, "icon").chars().take(2).collect();
            }
            if !s(op, "profile").is_empty() {
                sp.profile = s(op, "profile").into();
            }
        }
        "remove_space" => {
            if w.spaces.len() < 2 {
                return Err("the last space stays".into());
            }
            let id = s(op, "id").to_string();
            let uids: Vec<String> = w.spaces.iter().find(|sp| sp.id == id).ok_or("no such space")?.tabs.iter().map(|t| t.uid.clone()).collect();
            w.archive_tabs(&uids, n(op, "now"));
            w.spaces.retain(|sp| sp.id != id);
            if w.current_space == id {
                w.current_space = w.spaces[0].id.clone();
            }
        }
        "switch_space" => {
            let id = s(op, "id");
            if !w.spaces.iter().any(|sp| sp.id == id) {
                return Err("no such space".into());
            }
            w.current_space = id.into();
            w.current_favorite.clear();
        }
        "move_space" => {
            let from = w.spaces.iter().position(|sp| sp.id == s(op, "id")).ok_or("no such space")?;
            let to = (n(op, "to") as usize).min(w.spaces.len() - 1);
            let sp = w.spaces.remove(from);
            w.spaces.insert(to, sp);
        }
        "archive_due" => {
            let due = w.archive_due(n(op, "now"), op.get("hours").and_then(Value::as_f64).unwrap_or(12.0));
            w.archive_tabs(&due, n(op, "now"));
        }
        "clear_today" => {
            let space = if s(op, "space").is_empty() { w.current_space.clone() } else { s(op, "space").to_string() };
            let uids: Vec<String> = w.space_mut(&space)?.tabs.iter().filter(|t| !t.pinned).map(|t| t.uid.clone()).collect();
            w.archive_tabs(&uids, n(op, "now"));
        }
        "restore_archived" => {
            let i = n(op, "index") as usize;
            if i >= w.archive.len() {
                return Err("nothing archived there".into());
            }
            let a = w.archive.remove(i);
            let space = w.current_space.clone();
            let t = TabRec { uid: s(op, "uid").into(), url: a.url, title: a.title, last_active: n(op, "now"), ..Default::default() };
            let sp = w.space_mut(&space)?;
            sp.current = t.uid.clone();
            insert_tab(&mut sp.tabs, t, "", "");
        }
        "clear_archive" => w.archive.clear(),
        "remove_archived" => {
            let i = n(op, "index") as usize;
            if i >= w.archive.len() {
                return Err("nothing archived there".into());
            }
            w.archive.remove(i);
        }
        "add_watch" => {
            let uid = s(op, "tab_uid");
            let t = w.all_tabs().find(|t| t.uid == uid).ok_or("no such tab")?.clone();
            if t.private {
                return Err("the agent never watches private tabs".into());
            }
            w.watches.push(Watch {
                id: s(op, "id").into(),
                tab_uid: uid.into(),
                url: t.url,
                title: t.title,
                condition: s(op, "condition").into(),
                every_minutes: (n(op, "every_minutes") as u32).clamp(1, 24 * 60),
                ..Default::default()
            });
        }
        "update_watch" => {
            let wa = w.watches.iter_mut().find(|x| x.id == s(op, "id")).ok_or("no such watch")?;
            wa.last_checked = n(op, "now");
            wa.last_result = s(op, "result").into();
            if let Some(d) = b(op, "done") {
                wa.done = d;
            }
        }
        "remove_watch" => w.watches.retain(|x| x.id != s(op, "id")),
        other => return Err(format!("unknown op {other}")),
    }
    Ok(w.sanitized(false))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn ws() -> Workspace {
        let mut w = Workspace::default();
        for (i, u) in ["https://a.test", "https://b.test", "https://c.test"].iter().enumerate() {
            w = apply(w, &json!({"op": "new_tab", "uid": format!("t{i}"), "url": u, "now": 100})).unwrap();
        }
        w
    }

    #[test]
    fn spaces_keep_their_own_tabs() {
        let w = ws();
        let w = apply(w, &json!({"op": "add_space", "id": "work", "name": "Work", "profile": "Work"})).unwrap();
        assert_eq!(w.current_space, "work");
        assert_eq!(w.spaces[1].color, "blue");
        assert_eq!(w.spaces[1].icon, "W");
        let w = apply(w, &json!({"op": "new_tab", "uid": "w1", "url": "https://w.test"})).unwrap();
        assert_eq!(w.spaces[1].tabs.len(), 1);
        assert_eq!(w.spaces[0].tabs.len(), 3);
        let w = apply(w, &json!({"op": "move_tab", "uid": "t0", "space": "work"})).unwrap();
        assert_eq!(w.spaces[1].tabs.len(), 2);
        let w = apply(w, &json!({"op": "switch_space", "id": "home"})).unwrap();
        assert_eq!(w.current_space, "home");
        let w = apply(w, &json!({"op": "remove_space", "id": "work", "now": 5})).unwrap();
        assert_eq!(w.spaces.len(), 1);
        assert_eq!(w.archive.len(), 2);
        assert!(apply(w, &json!({"op": "remove_space", "id": "home"})).is_err());
    }

    #[test]
    fn folders_take_and_give_back_tabs() {
        let w = ws();
        let w = apply(w, &json!({"op": "add_folder", "id": "f1", "name": "Reading"})).unwrap();
        let w = apply(w, &json!({"op": "move_tab", "uid": "t2", "folder": "f1"})).unwrap();
        let t = w.spaces[0].tabs.iter().find(|t| t.uid == "t2").unwrap();
        assert!(t.pinned && t.folder == "f1" && t.pinned_url == "https://c.test");
        // Pinned tabs sort above today tabs.
        assert_eq!(w.spaces[0].tabs[0].uid, "t2");
        let w = apply(w, &json!({"op": "rename_folder", "id": "f1", "name": "Later"})).unwrap();
        assert_eq!(w.spaces[0].folders[0].name, "Later");
        let w = apply(w, &json!({"op": "toggle_folder", "id": "f1"})).unwrap();
        assert!(w.spaces[0].folders[0].collapsed);
        // Out of the folder, back to today.
        let w2 = apply(w.clone(), &json!({"op": "move_tab", "uid": "t2", "folder": "", "pinned": false})).unwrap();
        let t = w2.spaces[0].tabs.iter().find(|t| t.uid == "t2").unwrap();
        assert!(!t.pinned && t.folder.is_empty());
        // Removing the folder keeps its tabs, pinned.
        let w = apply(w, &json!({"op": "remove_folder", "id": "f1"})).unwrap();
        assert!(w.spaces[0].folders.is_empty());
        let t = w.spaces[0].tabs.iter().find(|t| t.uid == "t2").unwrap();
        assert!(t.pinned && t.folder.is_empty());
        assert!(apply(w, &json!({"op": "move_tab", "uid": "t1", "folder": "nope"})).is_err());
    }

    #[test]
    fn favorites_are_shared_and_reset() {
        let w = ws();
        let w = apply(w, &json!({"op": "favorite", "uid": "t1", "on": true})).unwrap();
        assert_eq!(w.favorites.len(), 1);
        assert_eq!(w.current_favorite, "t1");
        let mut w = apply(w, &json!({"op": "add_space", "id": "s2", "name": "Two"})).unwrap();
        assert_eq!(w.favorites.len(), 1, "favorites stay across spaces");
        w.favorites[0].url = "https://b.test/elsewhere".into();
        let w = apply(w, &json!({"op": "reset_pinned", "uid": "t1"})).unwrap();
        assert_eq!(w.favorites[0].url, "https://b.test");
        let w = apply(w, &json!({"op": "favorite", "uid": "t1", "on": false})).unwrap();
        assert!(w.favorites.is_empty());
        assert!(w.spaces[1].tabs.iter().any(|t| t.uid == "t1"));
    }

    #[test]
    fn old_today_tabs_archive_but_pinned_and_current_do_not() {
        let mut w = ws();
        w = apply(w, &json!({"op": "pin", "uid": "t0"})).unwrap();
        w = apply(w, &json!({"op": "select", "uid": "t2", "now": 100})).unwrap();
        let hour = 3600;
        assert!(w.archive_due(100 + 11 * hour, 12.0).is_empty());
        assert_eq!(w.archive_due(100 + 13 * hour, 12.0), vec!["t1".to_string()]);
        assert!(w.archive_due(100 + 1000 * hour, 0.0).is_empty(), "0 = never");
        let w = apply(w, &json!({"op": "archive_due", "now": 100 + 13 * hour, "hours": 12.0})).unwrap();
        assert_eq!(w.spaces[0].tabs.len(), 2);
        assert_eq!(w.archive[0].url, "https://b.test");
        assert_eq!(w.archive[0].space, "Home");
        let w = apply(w, &json!({"op": "restore_archived", "index": 0, "uid": "r1", "now": 1})).unwrap();
        assert!(w.archive.is_empty());
        assert_eq!(w.spaces[0].current, "r1");
        let w = apply(w, &json!({"op": "clear_today", "now": 2})).unwrap();
        assert!(!w.archive.is_empty());
        let n0 = w.archive.len();
        let w = apply(w, &json!({"op": "remove_archived", "index": 0})).unwrap();
        assert_eq!(w.archive.len(), n0 - 1);
        assert!(w.spaces[0].tabs.iter().all(|t| t.pinned));
    }

    #[test]
    fn private_tabs_never_reach_disk_or_folders() {
        let w = ws();
        let w = apply(w, &json!({"op": "new_tab", "uid": "p", "url": "https://secret.test", "private": true})).unwrap();
        assert!(apply(w.clone(), &json!({"op": "pin", "uid": "p"})).is_err());
        assert!(apply(w.clone(), &json!({"op": "favorite", "uid": "p"})).is_err());
        assert!(apply(w.clone(), &json!({"op": "add_watch", "id": "x", "tab_uid": "p", "condition": "c"})).is_err());
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("workspace.json");
        w.save(&p).unwrap();
        let text = std::fs::read_to_string(&p).unwrap();
        assert!(!text.contains("secret.test"));
        assert_eq!(Workspace::load(&p).unwrap().spaces[0].tabs.len(), 3);
    }

    #[test]
    fn migrates_old_session_and_repairs() {
        let s = Session {
            tabs: vec![crate::session::SessionTab { url: "https://x.test".into(), title: "X".into(), private: false }],
            current: 0,
        };
        let w = Workspace::from_session(&s, "Default");
        assert_eq!(w.spaces[0].tabs[0].url, "https://x.test");
        assert_eq!(w.spaces[0].current, "t0");
        let mut broken = w.clone();
        broken.current_space = "gone".into();
        broken.spaces[0].tabs[0].folder = "missing".into();
        broken.spaces.push(broken.spaces[0].clone());
        let fixed = broken.sanitized(false);
        assert_eq!(fixed.spaces.len(), 1);
        assert_eq!(fixed.current_space, "home");
        assert!(fixed.spaces[0].tabs[0].folder.is_empty());
    }

    #[test]
    fn watches_follow_tabs() {
        let w = ws();
        let w = apply(w, &json!({"op": "add_watch", "id": "w1", "tab_uid": "t0", "condition": "price under $200", "every_minutes": 30})).unwrap();
        assert_eq!(w.watches[0].url, "https://a.test");
        let w = apply(w, &json!({"op": "update_watch", "id": "w1", "now": 9, "result": "Now $249"})).unwrap();
        assert_eq!(w.watches[0].last_result, "Now $249");
        let w = apply(w, &json!({"op": "remove_watch", "id": "w1"})).unwrap();
        assert!(w.watches.is_empty());
    }
}
