// Real Chrome profiles, the way Yab finds them.
//
// Yab (Sources/Fast/Import.swift, TabImport.swift, ExtensionImport.swift)
// finds each Chromium-family browser by its data folder, reads the profile
// list from "Local State" (profile.info_cache: folder -> name, avatar,
// colour) and treats every profile folder as a place with its own sign-ins.
// Qi (CEF) goes one step further on Linux: instead of copying a profile
// in, it opens the browser's own user data dir as CEF's root cache path and
// each profile folder as a request context, so the profile itself is live.
#include <sys/stat.h>

#include <cstdio>
#include <fstream>
#include <map>
#include <sstream>

#include "include/cef_parser.h"
#include "include/cef_request_context_handler.h"
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

bool MakeDirs(const std::string& path) {
  std::string cur;
  std::stringstream ss(path);
  std::string part;
  if (!path.empty() && path[0] == '/') cur = "/";
  while (std::getline(ss, part, '/')) {
    if (part.empty()) continue;
    cur += part + "/";
    mkdir(cur.c_str(), 0700);
  }
  struct stat st;
  return stat(path.c_str(), &st) == 0 && S_ISDIR(st.st_mode);
}

static void MoveIfAbsent(const std::string& from, const std::string& to) {
  if (!Exists(from) || Exists(to)) return;
  auto slash = to.find_last_of('/');
  if (slash != std::string::npos) MakeDirs(to.substr(0, slash));
  std::rename(from.c_str(), to.c_str());
}

void MigrateLegacyDirs() {
  const std::string cfg = Xdg("XDG_CONFIG_HOME", ".config");
  const std::string data = Xdg("XDG_DATA_HOME", ".local/share");
  const std::string state = Xdg("XDG_STATE_HOME", ".local/state");
  const std::string cache = Xdg("XDG_CACHE_HOME", ".cache");
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
  if (dirs.empty() && Exists(dir + "/Default")) dirs.push_back("Default");
  for (auto& d : dirs) {
    if (!Exists(dir + "/" + d)) continue;
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
    return dir.empty() ? StartupProfile() : dir;
  }
  // No Space there: the Nth Chrome profile, like Chrome's own Ctrl+Shift+M.
  auto list = ProfilesIn(g_root);
  if (index >= 0 && index < static_cast<int>(list.size()))
    return list[index].dir;
  return "";
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

}  // namespace qi
