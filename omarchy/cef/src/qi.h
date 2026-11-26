// Qi (CEF): shared declarations.
//
// Qi's second engine. Pages run in Chromium through CEF's Chrome
// runtime with Chrome-style browsers, so real Chrome extensions (Web Store
// installs, chrome.tabs, popups, native messaging) work. Profiles are your
// real Chrome/Chromium profiles: CEF opens the browser's own user data dir
// (~/.config/chromium, ~/.config/google-chrome, ...) and the profile folder
// in it ("Default", "Profile 1", ...), so that profile's cookies, logins,
// extensions and settings are live. The window stays Qi's: frameless,
// Omarchy-themed, the Chrome toolbar hidden until asked for.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "include/cef_browser.h"
#include "include/cef_command_line.h"
#include "include/cef_request_context.h"
#include "include/views/cef_browser_view.h"

namespace qi {

// ---- paths -----------------------------------------------------------------
std::string HomeDir();
std::string DataDir();   // ~/.local/share/qi
std::string StateDir();  // ~/.local/state/qi
// Moves omaweb's XDG dirs to qi when the qi dir is not already there.
void MigrateLegacyDirs();
bool MakeDirs(const std::string& path);
bool Exists(const std::string& path);

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

// ---- safety: locks and backups (safety.cc) ----------------------------------
// Who holds the browser's SingletonLock: "" when free or stale.
std::string LiveLockHolder(const std::string& user_data_dir);
// Copies the user data dir (minus caches, locks and sockets) to dest.
bool CopyUserDataDir(const std::string& src,
                     const std::string& dest,
                     std::string* error);
// Backs up the user data dir once per CEF version and day, keeping three.
// Returns the backup folder, or "" with *error set.
std::string BackupUserDataDir(const ChromeRoot& root, std::string* error);

// ---- windows ----------------------------------------------------------------
void OpenWindow(const std::string& profile_dir,
                const std::string& url,
                bool show_toolbar);
void OpenProfilePicker();
void CloseAllWindows();
void OnBrowserLoading(CefRefPtr<CefBrowser> browser);
// Handles the command line of the first launch and of every relaunch.
void HandleCommandLine(CefRefPtr<CefCommandLine> cl);
// Starts another qi-cef for a different browser's user data dir.
void SpawnFor(const std::string& root_id, const std::string& profile_dir);

// ---- client -----------------------------------------------------------------
CefRefPtr<CefClient> SharedClient();

}  // namespace qi
