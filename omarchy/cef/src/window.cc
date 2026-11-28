// Profile picker, process spawn, and the list of open windows.
// The window itself lives in shell.cc.
#include <spawn.h>
#include <unistd.h>

#include <algorithm>
#include <cstring>
#include <fstream>
#include <sstream>

#include "include/cef_app.h"
#include "include/cef_parser.h"
#include "include/views/cef_window.h"
#include "include/wrapper/cef_helpers.h"
#include "qi.h"

extern char** environ;

namespace qi {
namespace {

std::vector<CefRefPtr<CefWindow>>& Windows() {
  static std::vector<CefRefPtr<CefWindow>> w;
  return w;
}

std::vector<CefRefPtr<CefBrowser>>& Browsers() {
  static std::vector<CefRefPtr<CefBrowser>> b;
  return b;
}

void EndProcess() {
  RestoreOpenStartupPrefs();
  RestoreStartupPrefsOnDisk();
  ReleaseBrowserSessions(ActiveDataDir());
  ReleaseProfileClaim();
  // Browser::~Browser aborts while ToolbarButtonProvider is still registered.
  // The session files and the profile claim are already released.
  _exit(0);
}

void QuitIfIdle() {
  if (!Windows().empty() || !Browsers().empty()) return;
  EndProcess();
}

std::string Escape(const std::string& s) {
  std::string out;
  for (char c : s) {
    switch (c) {
      case '&': out += "&amp;"; break;
      case '<': out += "&lt;"; break;
      case '>': out += "&gt;"; break;
      case '"': out += "&quot;"; break;
      default: out += c;
    }
  }
  return out;
}

std::string UrlPart(const std::string& s) {
  return CefURIEncode(s, false).ToString();
}

std::string Avatar(const ChromeProfile& p, const Theme& t) {
  if (!p.picture.empty()) {
    std::ifstream f(p.picture, std::ios::binary);
    std::string bytes((std::istreambuf_iterator<char>(f)),
                      std::istreambuf_iterator<char>());
    if (!bytes.empty()) {
      return "<img class=av src=\"data:image/png;base64," +
             CefBase64Encode(bytes.data(), bytes.size()).ToString() + "\">";
    }
  }
  std::string bg = p.color ? t.Css(p.color) : t.Css(t.accent);
  std::string initial = p.name.empty() ? "?" : p.name.substr(0, 1);
  return "<span class=av style=\"background:" + bg + "\">" + Escape(initial) +
         "</span>";
}

}  // namespace

void RememberWindow(CefRefPtr<CefWindow> window) {
  if (!window) return;
  auto& all = Windows();
  for (auto& have : all)
    if (have->IsSame(window)) return;
  all.push_back(window);
}

bool OtherWindowsOpen() { return Windows().size() > 1; }

void ForgetWindow(CefRefPtr<CefWindow> window) {
  auto& all = Windows();
  all.erase(std::remove_if(all.begin(), all.end(),
                           [&](auto& have) { return have->IsSame(window); }),
            all.end());
  if (all.empty()) EndProcess();
  else QuitIfIdle();
}

void TrackBrowser(CefRefPtr<CefBrowser> browser) {
  if (!browser) return;
  auto& all = Browsers();
  for (auto& have : all)
    if (have->IsSame(browser)) return;
  all.push_back(browser);
}

void ForgetBrowser(CefRefPtr<CefBrowser> browser) {
  auto& all = Browsers();
  all.erase(std::remove_if(all.begin(), all.end(),
                           [&](auto& have) { return have->IsSame(browser); }),
            all.end());
  QuitIfIdle();
}

void OnBrowserLoading(CefRefPtr<CefBrowser>) {}

void CloseAllWindows() {
  // Close the windows. CanClose asks each tab to close. Forcing the browsers
  // shut here runs Chrome's tab-strip layout after the view has left the
  // widget, which segfaults.
  auto views = Windows();
  for (auto& window : views) window->Close();
}

void OpenProfilePicker() {
  const Theme& t = CurrentTheme();
  std::ostringstream h;
  h << "<!doctype html><meta charset=utf-8><title>Profiles</title><style>"
    << "body{background:" << t.Css(t.background) << ";color:" << t.Css(t.foreground)
    << ";font:15px system-ui,sans-serif;margin:48px auto;max-width:760px}"
    << "h1{font-weight:600;font-size:22px}h2{font-size:14px;opacity:.7;margin-top:32px}"
    << "a.p{display:flex;gap:14px;align-items:center;padding:12px 14px;border-radius:12px;"
    << "color:inherit;text-decoration:none;border:1px solid " << t.Css(t.muted) << ";margin:8px 0}"
    << "a.p:hover,a.p:focus{background:" << t.Css(t.selection) << ";outline:2px solid "
    << t.Css(t.accent) << "}.av{width:40px;height:40px;border-radius:50%;display:inline-grid;"
    << "place-items:center;font-weight:700;color:#fff;text-shadow:0 1px 2px #0008;object-fit:cover}"
    << "small{opacity:.65;display:block}.warn{color:" << t.Css(t.accent) << "}"
    << "</style><h1>Choose a Chrome profile</h1>"
    << "<p>These are your real browser profiles. Opening one runs it live in "
       "Qi. A row marked copy is not the live profile. Chrome and Brave open "
       "logged out until their safe-storage keys are mapped.</p>";
  std::vector<ChromeRoot> roots = KnownRoots();
  bool seen_active = false;
  for (auto& r : roots) {
    if (r.id == ActiveRoot().id && r.dir == ActiveRoot().dir) seen_active = true;
  }
  if (!seen_active && !ActiveRoot().dir.empty()) roots.push_back(ActiveRoot());
  for (auto& root : roots) {
    const bool active = root.id == ActiveRoot().id && root.dir == ActiveRoot().dir;
    const bool copy =
        active && !ActiveDataDir().empty() && ActiveDataDir() != root.dir;
    const std::string shown = copy ? ActiveDataDir() : root.dir;
    std::string holder = copy ? "" : LiveLockHolder(root.dir);
    h << "<h2>" << Escape(root.label) << " &middot; " << Escape(shown)
      << (copy ? " (copy)" : active ? " (this window)" : "") << "</h2>";
    if (!holder.empty())
      h << "<p class=warn>" << Escape(root.label) << " is open (" << Escape(holder)
        << "). Quit it before opening these here.</p>";
    for (auto& p : ProfilesIn(root)) {
      h << "<a class=p href=\"https://qi.invalid/open?root=" << UrlPart(root.id)
        << "&dir=" << UrlPart(p.dir) << "\">" << Avatar(p, t) << "<span>"
        << Escape(p.name) << "<small>" << Escape(p.gaia_name.empty() ? "" : p.gaia_name + " · ")
        << Escape(p.dir) << "</small></span></a>";
    }
  }
  auto spaces = Spaces();
  if (!spaces.empty()) {
    h << "<h2>Spaces (Ctrl+Alt+1&hellip;9)</h2>";
    int i = 1;
    for (auto& s : spaces) {
      std::string dir = ProfileForSpace(i - 1);
      h << "<p>" << i++ << ". " << Escape(s.name) << " &rarr; "
        << Escape(ProfileLabel(dir)) << " <small>" << Escape(dir) << "</small></p>";
    }
  }
  std::string html = h.str();
  std::string url = "data:text/html;base64," +
                    CefBase64Encode(html.data(), html.size()).ToString();
  RememberPickerDocument(url);
  OpenWindow(StartupProfile(), url, false);
}

void SpawnFor(const std::string& root_id, const std::string& profile_dir) {
  std::string exe = HomeDir() + "/.local/bin/qi-cef";
  if (access(exe.c_str(), X_OK) != 0) {
    char buf[4096];
    ssize_t n = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
    if (n <= 0) {
      Tell("couldn't find qi-cef to open " + root_id);
      return;
    }
    buf[n] = 0;
    exe = buf;
  }
  std::string a1 = "--browser=" + root_id;
  std::string a2 = "--profile-directory=" + profile_dir;
  char* argv[] = {exe.data(), a1.data(), a2.data(), nullptr};
  pid_t pid = 0;
  int rc = posix_spawn(&pid, exe.c_str(), nullptr, nullptr, argv, environ);
  if (rc != 0) Tell("couldn't start " + root_id + ": " + strerror(rc));
}

void HandleCommandLine(CefRefPtr<CefCommandLine> cl) {
  CEF_REQUIRE_UI_THREAD();
  if (cl->HasSwitch("command")) {
    RunAction(cl->GetSwitchValue("command"));
    std::vector<CefString> args;
    cl->GetArguments(args);
    bool extra = cl->HasSwitch("picker") || cl->HasSwitch("extensions") ||
                 cl->HasSwitch("install-extension");
    if (args.empty() && !extra) return;
  }
  if (cl->HasSwitch("picker")) {
    OpenProfilePicker();
    return;
  }
  std::string dir;
  if (cl->HasSwitch("space")) dir = ResolveSpaceSwitch(cl->GetSwitchValue("space"));
  for (const char* key : {"profile-directory", "profile"}) {
    if (dir.empty() && cl->HasSwitch(key))
      dir = ResolveProfileDir(cl->GetSwitchValue(key));
  }
  if (dir.empty()) dir = StartupProfile();

  std::vector<CefString> args;
  cl->GetArguments(args);
  bool toolbar = cl->HasSwitch("toolbar");
  if (cl->HasSwitch("install-extension")) {
    args.push_back("https://chromewebstore.google.com/detail/" +
                   cl->GetSwitchValue("install-extension").ToString());
    toolbar = true;
  }
  if (cl->HasSwitch("extensions")) {
    args.push_back("chrome://extensions/");
    toolbar = true;
  }
  if (args.empty()) args.push_back("chrome://newtab/");
  for (auto& a : args) {
    std::string url = a;
    if (url.find("://") == std::string::npos && url.rfind("data:", 0) != 0 &&
        url.rfind("about:", 0) != 0) {
      if (url[0] == '/') url = "file://" + url;
      else if (url.find('.') != std::string::npos && url.find(' ') == std::string::npos)
        url = "https://" + url;
    }
    OpenWindow(dir, url, toolbar);
  }
}

}  // namespace qi
