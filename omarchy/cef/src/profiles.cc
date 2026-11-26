#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
// Real Chrome profiles, the way Yab finds them.
//
// Yab (Sources/Fast/Import.swift, TabImport.swift, ExtensionImport.swift)
// finds each Chromium-family browser by its data folder, reads the profile
// list from "Local State" (profile.info_cache: folder -> name, avatar,
// colour) and treats every profile folder as a place with its own sign-ins.
// Qi (CEF) goes one step further on Linux: instead of copying a profile
// in, it opens the browser's own user data dir as CEF's root cache path and
// each profile folder as a request context, so the profile itself is live.
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>

#include <cerrno>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iostream>
#include <map>
#include <sstream>
#include <vector>

#ifndef RENAME_NOREPLACE
#define RENAME_NOREPLACE 1
#endif

#include "include/cef_parser.h"
#include "include/cef_request_context_handler.h"
#include "include/cef_values.h"
#include "qi.h"

namespace qi {

std::string HomeDir() {
  const char* h = getenv("HOME");
  return h && *h ? h : "/tmp";
}

static std::string Xdg(const char* var, const char* fallback) {
  const char* v = getenv(var);
  return v && *v ? std::string(v) : HomeDir() + "/" + fallback;
}

std::string DataDir() { return Xdg("XDG_DATA_HOME", ".local/share") + "/qi"; }
std::string StateDir() { return Xdg("XDG_STATE_HOME", ".local/state") + "/qi"; }

bool Exists(const std::string& path) {
  struct stat st;
  return stat(path.c_str(), &st) == 0;
}

bool IsDirectory(const std::string& path) {
  struct stat st;
  return stat(path.c_str(), &st) == 0 && S_ISDIR(st.st_mode);
}

static std::vector<std::string>& BlockedDirs() {
  static std::vector<std::string> v;
  return v;
}

static bool CreationBlocked(const std::string& path) {
  for (auto& b : BlockedDirs()) {
    if (path == b || path.rfind(b + "/", 0) == 0) return true;
  }
  return false;
}

bool MakeDirs(const std::string& path) {
  if (CreationBlocked(path)) return false;
  std::string cur;
  std::stringstream ss(path);
  std::string part;
  if (!path.empty() && path[0] == '/') cur = "/";
  while (std::getline(ss, part, '/')) {
    if (part.empty()) continue;
    cur += part + "/";
    if (CreationBlocked(cur.substr(0, cur.size() - 1))) return false;
    mkdir(cur.c_str(), 0700);
  }
  struct stat st;
  return stat(path.c_str(), &st) == 0 && S_ISDIR(st.st_mode);
}

static bool OmawebRunning() {
  DIR* d = opendir("/proc");
  if (!d) return false;
  bool found = false;
  while (dirent* ent = readdir(d)) {
    if (ent->d_name[0] < '1' || ent->d_name[0] > '9') continue;
    std::ifstream in(std::string("/proc/") + ent->d_name + "/comm");
    std::string comm;
    std::getline(in, comm);
    if (comm == "omaweb") {
      found = true;
      break;
    }
  }
  closedir(d);
  return found;
}

static void MoveIfAbsent(const std::string& from, const std::string& to) {
  if (!Exists(from)) return;
  auto slash = to.find_last_of('/');
  if (slash != std::string::npos) {
    std::string parent = to.substr(0, slash);
    if (!CreationBlocked(parent)) MakeDirs(parent);
  }
  if (renameat2(AT_FDCWD, from.c_str(), AT_FDCWD, to.c_str(), RENAME_NOREPLACE) == 0)
    return;
  if (errno == EEXIST || errno == ENOTEMPTY || errno == ENOENT) return;
  std::cerr << "qi-cef: couldn't move " << from << " to " << to << ": " << strerror(errno)
            << "\n";
  if (Exists(from) && !Exists(to)) BlockedDirs().push_back(to);
}

void MigrateLegacyDirs() {
  const std::string cfg = Xdg("XDG_CONFIG_HOME", ".config");
  const std::string data = Xdg("XDG_DATA_HOME", ".local/share");
  const std::string state = Xdg("XDG_STATE_HOME", ".local/state");
  const std::string cache = Xdg("XDG_CACHE_HOME", ".cache");
  if (OmawebRunning()) {
    std::cerr << "qi-cef: Omaweb is still open, so its folders were left where they are\n";
    const std::pair<std::string, std::string> pairs[] = {
        {cfg + "/omaweb", cfg + "/qi"},
        {data + "/omaweb", data + "/qi"},
        {state + "/omaweb", state + "/qi"},
        {cache + "/omaweb", cache + "/qi"},
        {cache + "/omaweb-cef", cache + "/qi-cef"},
    };
    for (auto& [from, to] : pairs) {
      if (Exists(from) && !Exists(to)) BlockedDirs().push_back(to);
    }
    return;
  }
  MoveIfAbsent(cfg + "/omaweb", cfg + "/qi");
  MoveIfAbsent(data + "/omaweb", data + "/qi");
  MoveIfAbsent(state + "/omaweb", state + "/qi");
  MoveIfAbsent(cache + "/omaweb", cache + "/qi");
  MoveIfAbsent(cache + "/omaweb-cef", cache + "/qi-cef");
  MoveIfAbsent(data + "/qi/omaweb", data + "/qi/qi");
  MoveIfAbsent(cache + "/qi/omaweb", cache + "/qi/qi");
  MoveIfAbsent(data + "/qi/qi/QtWebEngine/omaweb", data + "/qi/qi/QtWebEngine/qi");
  MoveIfAbsent(cache + "/qi/qi/QtWebEngine/omaweb", cache + "/qi/qi/QtWebEngine/qi");
}

static std::string ReadFile(const std::string& path) {
  std::ifstream f(path);
  std::stringstream ss;
  ss << f.rdbuf();
  return ss.str();
}

// ---- roots ------------------------------------------------------------------

static std::vector<ChromeRoot> AllRoots() {
  const std::string cfg = Xdg("XDG_CONFIG_HOME", ".config");
  return {
      {"chromium", "Chromium", cfg + "/chromium", cfg + "/chromium-flags.conf"},
      {"google-chrome", "Google Chrome", cfg + "/google-chrome",
       cfg + "/chrome-flags.conf"},
      {"google-chrome-beta", "Chrome Beta", cfg + "/google-chrome-beta",
       cfg + "/chrome-beta-flags.conf"},
      {"brave", "Brave", cfg + "/BraveSoftware/Brave-Browser",
       cfg + "/brave-flags.conf"},
      // Qi's own, for machines with no Chromium browser.
      {"qi", "Qi", DataDir() + "/cef", ""},
  };
}

std::vector<ChromeRoot> KnownRoots() {
  std::vector<ChromeRoot> out;
  for (auto& r : AllRoots()) {
    if (r.id != "qi" && Exists(r.dir + "/Local State")) out.push_back(r);
  }
  if (out.empty()) out.push_back(AllRoots().back());
  return out;
}

ChromeRoot RootById(const std::string& id) {
  for (auto& r : AllRoots()) {
    if (r.id == id) return r;
  }
  return {};
}

static ChromeRoot g_root;
static std::string g_data_dir;
static std::string g_startup_profile = "Default";

const ChromeRoot& ActiveRoot() { return g_root; }
const std::string& ActiveDataDir() { return g_data_dir; }
void SetActiveRoot(const ChromeRoot& root, const std::string& data_dir) {
  g_root = root;
  g_data_dir = data_dir;
}
void SetStartupProfile(const std::string& dir) { g_startup_profile = dir; }
const std::string& StartupProfile() { return g_startup_profile; }

// ---- profiles ---------------------------------------------------------------

static std::vector<ChromeProfile> ProfilesInDir(const std::string& dir) {
  std::vector<ChromeProfile> out;
  auto v = CefParseJSON(ReadFile(dir + "/Local State"), JSON_PARSER_RFC);
  CefRefPtr<CefDictionaryValue> cache;
  CefRefPtr<CefListValue> order;
  if (v && v->GetType() == VTYPE_DICTIONARY) {
    auto profile = v->GetDictionary()->GetDictionary("profile");
    if (profile) {
      cache = profile->GetDictionary("info_cache");
      order = profile->GetList("profiles_order");
    }
  }
  std::vector<std::string> dirs;
  for (size_t i = 0; order && i < order->GetSize(); ++i)
    dirs.push_back(order->GetString(i));
  if (cache) {
    CefDictionaryValue::KeyList keys;
    cache->GetKeys(keys);
    for (auto& k : keys) {
      bool seen = false;
      for (auto& d : dirs) seen |= d == k.ToString();
      if (!seen) dirs.push_back(k);
    }
  }
  if (dirs.empty() && IsDirectory(dir + "/Default")) dirs.push_back("Default");
  for (auto& d : dirs) {
    if (d.empty() || d.find('/') != std::string::npos || d == "." || d == "..") continue;
    if (!IsDirectory(dir + "/" + d)) continue;
    ChromeProfile p;
    p.dir = d;
    p.name = d;
    if (cache) {
      if (auto e = cache->GetDictionary(d)) {
        std::string n = e->GetString("name");
        if (!n.empty()) p.name = n;
        p.gaia_name = e->GetString("gaia_name");
        p.avatar = e->GetString("avatar_icon");
        if (e->HasKey("profile_highlight_color"))
          p.color = static_cast<uint32_t>(e->GetInt("profile_highlight_color"));
      }
    }
    std::string pic = dir + "/" + d + "/Google Profile Picture.png";
    if (Exists(pic)) p.picture = pic;
    out.push_back(p);
  }
  if (out.empty()) out.push_back({"Default", "Default"});
  return out;
}

std::vector<ChromeProfile> ProfilesIn(const ChromeRoot& root) {
  // A snapshot run reads its own copy of Local State.
  if (root.id == g_root.id && !g_data_dir.empty())
    return ProfilesInDir(g_data_dir);
  return ProfilesInDir(root.dir);
}

std::string ResolveProfileDir(const std::string& want) {
  if (want.empty()) return "";
  auto list = ProfilesIn(g_root);
  for (auto& p : list) {
    if (p.dir == want) return p.dir;
  }
  for (auto& p : list) {
    if (strcasecmp(p.name.c_str(), want.c_str()) == 0) return p.dir;
  }
  for (auto& p : list) {
    if (!p.gaia_name.empty() &&
        strcasecmp(p.gaia_name.c_str(), want.c_str()) == 0)
      return p.dir;
  }
  return "";
}

std::string ProfileLabel(const std::string& dir) {
  for (auto& p : ProfilesIn(g_root)) {
    if (p.dir == dir) return p.name;
  }
  return dir;
}

// ---- Spaces -----------------------------------------------------------------

std::vector<Space> Spaces() {
  std::vector<Space> out;
  auto v = CefParseJSON(ReadFile(StateDir() + "/workspace.json"),
                        JSON_PARSER_RFC);
  if (v && v->GetType() == VTYPE_DICTIONARY) {
    auto list = v->GetDictionary()->GetList("spaces");
    for (size_t i = 0; list && i < list->GetSize(); ++i) {
      auto d = list->GetDictionary(i);
      if (!d) continue;
      Space s{d->GetString("id"), d->GetString("name"),
              d->GetString("profile")};
      if (s.profile.empty()) s.profile = "Default";
      out.push_back(s);
    }
  }
  return out;
}

std::string ProfileForSpace(int index) {
  auto spaces = Spaces();
  if (index >= 0 && index < static_cast<int>(spaces.size())) {
    std::string dir = ResolveProfileDir(spaces[index].profile);
    if (dir.empty()) dir = ResolveProfileDir(spaces[index].name);
    return dir;
  }
  // No Space there: the Nth Chrome profile, like Chrome's own Ctrl+Shift+M.
  auto list = ProfilesIn(g_root);
  if (index >= 0 && index < static_cast<int>(list.size()))
    return list[index].dir;
  return "";
}

std::string ResolveSpaceSwitch(const std::string& selector) {
  if (selector.empty()) return "";
  int index = -1;
  if (selector.find_first_not_of("0123456789") == std::string::npos) {
    index = atoi(selector.c_str()) - 1;
  } else {
    auto spaces = Spaces();
    for (size_t i = 0; i < spaces.size(); ++i) {
      if (spaces[i].id == selector ||
          strcasecmp(spaces[i].name.c_str(), selector.c_str()) == 0) {
        index = static_cast<int>(i);
        break;
      }
    }
  }
  if (index < 0) return "";
  return ProfileForSpace(index);
}

bool KnownProfileFolder(const ChromeRoot& root, const std::string& dir) {
  if (dir.empty() || dir.find('/') != std::string::npos || dir.find('\\') != std::string::npos ||
      dir == "." || dir == "..")
    return false;
  const std::string base =
      (root.id == g_root.id && !g_data_dir.empty()) ? g_data_dir : root.dir;
  if (!IsDirectory(base + "/" + dir)) return false;
  for (auto& p : ProfilesIn(root)) {
    if (p.dir == dir) return true;
  }
  return false;
}

// ---- request contexts -------------------------------------------------------

namespace {

class ContextHandler : public CefRequestContextHandler {
 public:
  void OnRequestContextInitialized(
      CefRefPtr<CefRequestContext> ctx) override {
    ApplyTheme(ctx);
  }

 private:
  IMPLEMENT_REFCOUNTING(ContextHandler);
};

std::map<std::string, CefRefPtr<CefRequestContext>>& Contexts() {
  static std::map<std::string, CefRefPtr<CefRequestContext>> m;
  return m;
}

}  // namespace

CefRefPtr<CefRequestContext> ContextFor(const std::string& raw) {
  std::string dir = raw.empty() ? g_startup_profile : raw;
  auto& m = Contexts();
  auto it = m.find(dir);
  if (it != m.end()) return it->second;
  CefRefPtr<CefRequestContext> ctx;
  if (dir == g_startup_profile) {
    // CefSettings.cache_path is this profile's folder.
    ctx = CefRequestContext::GetGlobalContext();
    ApplyTheme(ctx);
  } else {
    CefRequestContextSettings s;
    CefString(&s.cache_path) = g_data_dir + "/" + dir;
    s.persist_session_cookies = true;
    ctx = CefRequestContext::CreateContext(s, new ContextHandler());
  }
  m[dir] = ctx;
  return ctx;
}

void RestoreOpenStartupPrefs() {
  for (auto& [folder, value] : OpenStartupPrefValues()) {
    CefRefPtr<CefRequestContext> ctx;
    auto& m = Contexts();
    auto it = m.find(folder);
    if (it != m.end()) ctx = it->second;
    if (!ctx) {
      auto g = CefRequestContext::GetGlobalContext();
      if (g) {
        std::string cache = g->GetCachePath().ToString();
        auto slash = cache.find_last_of('/');
        if ((slash == std::string::npos ? cache : cache.substr(slash + 1)) == folder) ctx = g;
      }
    }
    if (!ctx) continue;
    auto v = CefValue::Create();
    v->SetInt(value);
    CefString err;
    if (!ctx->SetPreference("session.restore_on_startup", v, err)) {
      std::cerr << "qi-cef: couldn't keep the startup setting for " << folder << "\n";
    }
  }
}

}  // namespace qi
