// Qi (CEF): shared declarations.
//
// Qi's second engine. Pages run in Chromium through CEF's Chrome
// runtime with Chrome-style browsers, so real Chrome extensions (Web Store
// installs, chrome.tabs, popups, native messaging) work. Profiles are the
// browser's own user data dir (~/.config/chromium, ~/.config/google-chrome,
// ...) and the profile folder in it ("Default", "Profile 1", ...). Chromium
// profiles keep their cookies and logins. Google Chrome and Brave open
// logged out until their safe-storage keys are mapped. The window is Qi's:
// a sidebar for tabs and favorites, and a floating address bar. Pages still
// run in the Chrome runtime so extensions work. The stock tab strip stays
// hidden. Ctrl+T opens a tab. Ctrl+N opens a window.
#pragma once

#include <cstdint>
#include <string>
#include <utility>
#include <vector>

#include "include/cef_browser.h"
#include "include/cef_command_line.h"
#include "include/cef_request_context.h"
#include "include/views/cef_browser_view.h"

class CefWindow;

namespace qi {

// ---- paths -----------------------------------------------------------------
std::string HomeDir();
std::string DataDir();   // ~/.local/share/qi
std::string StateDir();  // ~/.local/state/qi
// Moves omaweb's XDG dirs onto qi. An empty qi directory is replaced. A qi
// directory that already has files keeps them and takes the rest.
void MigrateLegacyDirs();
bool MakeDirs(const std::string& path);
bool Exists(const std::string& path);
bool IsDirectory(const std::string& path);
void Tell(const std::string& msg);

// ---- theme ------------------------------------------------------------------
struct Theme {
  std::string name = "tokyo-night (built in)";
  bool dark = true;
  uint32_t background = 0xFF1A1B26;
  uint32_t foreground = 0xFFA9B1D6;
  uint32_t accent = 0xFF7AA2F7;
  uint32_t muted = 0xFF414868;
  uint32_t selection = 0xFF292E42;
  std::string Css(uint32_t c) const;  // "#rrggbb"
};
const Theme& CurrentTheme();
void ApplyTheme(CefRefPtr<CefRequestContext> ctx);

// ---- real Chrome profiles ---------------------------------------------------
// A Chromium-family browser's user data dir.
struct ChromeRoot {
  std::string id;          // "chromium", "google-chrome", "brave", "qi"
  std::string label;       // "Chromium"
  std::string dir;         // ~/.config/chromium
  std::string flags_file;  // ~/.config/chromium-flags.conf ("" for none)
};
// One profile folder in it, named and coloured the way Local State says.
struct ChromeProfile {
  std::string dir;        // "Default", "Profile 1"
  std::string name;       // "Michael"
  std::string gaia_name;  // "Michael Monetized"
  std::string avatar;     // chrome://theme/IDR_PROFILE_AVATAR_26
  std::string picture;    // <dir>/Google Profile Picture.png if present
  uint32_t color = 0;     // profile_highlight_color (ARGB), 0 for none
};
std::vector<ChromeRoot> KnownRoots();  // those that exist, Chromium first
ChromeRoot RootById(const std::string& id);  // {} if unknown
std::vector<ChromeProfile> ProfilesIn(const ChromeRoot& root);
// The root and profile this process runs (set once in main()).
const ChromeRoot& ActiveRoot();
void SetActiveRoot(const ChromeRoot& root, const std::string& data_dir);
const std::string& ActiveDataDir();  // root.dir, or a snapshot copy of it
// Resolves a profile by folder or display name; "" if none.
std::string ResolveProfileDir(const std::string& name_or_dir);
std::string ProfileLabel(const std::string& dir);
CefRefPtr<CefRequestContext> ContextFor(const std::string& profile_dir);
void SetStartupProfile(const std::string& dir);
const std::string& StartupProfile();

// Spaces from the Qt build's workspace.json; a Space's profile is matched to
// a Chrome profile by folder or display name.
struct Space {
  std::string id, name, profile;
};
std::vector<Space> Spaces();
std::string ProfileForSpace(int index);  // 0-based; "" if none
// --space= on the command line: a 1-based slot, a Space id, or a Space name.
std::string ResolveSpaceSwitch(const std::string& selector);
// True when dir is a profile folder in this root, not a display name.
bool KnownProfileFolder(const ChromeRoot& root, const std::string& dir);
// Puts session.restore_on_startup back on profiles this process opened.
void RestoreOpenStartupPrefs();

// ---- safety: locks and backups (safety.cc) ----------------------------------
// Who holds the browser's SingletonLock: "" when free or stale.
std::string LiveLockHolder(const std::string& user_data_dir);
// True when another running Qi (CEF) holds the lock; it then gets our
// command line instead of a refusal.
bool LockHeldByQi(const std::string& user_data_dir);
// One process prepares a profile. Owner keeps the claim until exit.
// Busy: another Qi is already in its message loop on this directory.
// Preparing: a live Qi still holds the claim and has not finished starting.
enum class ProfileClaim { Owner, Busy, Error, Preparing };
ProfileClaim ClaimProfile(const std::string& data_dir);
void ReleaseProfileClaim();
// Where a --snapshot copy of this root is stored. Custom roots are keyed
// by their canonical path so two different directories do not share one copy.
std::string SnapshotDirFor(const ChromeRoot& root);
// True when replacing dest would delete source.
bool SnapshotClobbersSource(const std::string& source, const std::string& dest);
// True when dest is a finished snapshot of source.
bool SnapshotCanReuse(const std::string& data_dir, const std::string& source);
// False when the marker could not be written. The copy is not usable then.
bool WriteSnapshotMarker(const std::string& data_dir,
                         const std::string& source,
                         const std::string& label);
// Makes a --user-data-dir absolute against the current directory.
std::string AbsolutePath(const std::string& path);
// Copies the user data dir (minus caches, locks and sockets) to dest.
bool CopyUserDataDir(const std::string& src,
                     const std::string& dest,
                     std::string* error);
// Backs up the user data dir once per CEF version and day, keeping three.
// Returns the backup folder, or "" with *error set.
std::string BackupUserDataDir(const ChromeRoot& root, std::string* error);
// Records session.restore_on_startup for every profile, then moves session
// files aside so Chrome does not restore them into a second window. Release
// puts the files back. Either call returns false when the journal or a move
// failed, and a failed hold leaves the profile as it was.
bool RememberStartupPrefs(const std::string& data_dir);
void RestoreStartupPrefsOnDisk();
// Drops the preference sidecar when this launch never reached CEF.
void DiscardStartupPrefs();
bool ApplyStartupPrefFile(const std::string& path);
bool HoldBrowserSessions(const std::string& data_dir);
void ReleaseBrowserSessions(const std::string& data_dir);
// folder -> original restore_on_startup, for profiles that had the key.
const std::vector<std::pair<std::string, int>>& OpenStartupPrefValues();

// ---- windows ----------------------------------------------------------------
void OpenWindow(const std::string& profile_dir,
                const std::string& url,
                bool show_toolbar);
void OpenFreshWindow(const std::string& profile_dir,
                     const std::string& url,
                     bool show_toolbar,
                     bool priv);
// A link from a page. False when this process has no Qi window yet.
bool OpenAsTab(CefRefPtr<CefBrowser> opener, const std::string& url, bool background);
void NotePage(CefRefPtr<CefBrowser> browser, const std::string& title, const std::string& url);
void NoteLoad(CefRefPtr<CefBrowser> browser);
bool RunAction(const std::string& name);
void ReloadKeyMap();
void RememberWindow(CefRefPtr<CefWindow> window);
void ForgetWindow(CefRefPtr<CefWindow> window);
void OpenProfilePicker();
void CloseAllWindows();
void TrackBrowser(CefRefPtr<CefBrowser> browser);
void ForgetBrowser(CefRefPtr<CefBrowser> browser);
void OnBrowserLoading(CefRefPtr<CefBrowser> browser);
// Handles the command line of the first launch and of every relaunch.
void HandleCommandLine(CefRefPtr<CefCommandLine> cl);
// Starts another qi-cef for a different browser's user data dir.
void SpawnFor(const std::string& root_id, const std::string& profile_dir);

// ---- client -----------------------------------------------------------------
CefRefPtr<CefClient> SharedClient();
void RememberPickerDocument(const std::string& url);
bool IsPickerDocument(const std::string& url);
void RememberKeysDocument(const std::string& url);
bool IsKeysDocument(const std::string& url);

}  // namespace qi
