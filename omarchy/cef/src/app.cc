// The browser-process side of CefApp: command line, first window, relaunch.
#include <fstream>
#include <map>
#include <sstream>

#include "include/cef_app.h"
#include "include/cef_browser_process_handler.h"
#include "qi.h"

namespace qi {
namespace {

// Lines of the browser's own flags file (~/.config/chromium-flags.conf), so
// the profile runs the way that browser runs it: the same password store
// (cookies and logins are encrypted with its key), the same extensions
// loaded from the command line, the same Google API keys for its sign-in.
void ForwardFlagsFile(const std::string& path,
                      CefRefPtr<CefCommandLine> cl,
                      std::map<std::string, std::string>* lists) {
  if (path.empty()) return;
  std::ifstream f(path);
  std::string line;
  while (std::getline(f, line)) {
    line.erase(0, line.find_first_not_of(" \t"));
    line.erase(line.find_last_not_of(" \t\r") + 1);
    if (line.rfind("--", 0) != 0) continue;
    std::string kv = line.substr(2);
    auto eq = kv.find('=');
    std::string key = kv.substr(0, eq);
    std::string value = eq == std::string::npos ? "" : kv.substr(eq + 1);
    if (key.rfind("ozone-platform", 0) == 0) continue;  // set by us
    if (lists->count(key)) {
      std::string& v = (*lists)[key];
      v += (v.empty() ? "" : ",") + value;
      continue;
    }
    if (cl->HasSwitch(key)) continue;
    if (eq == std::string::npos) {
      cl->AppendSwitch(key);
    } else {
      cl->AppendSwitchWithValue(key, value);
    }
  }
}

class App : public CefApp, public CefBrowserProcessHandler {
 public:
  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override {
    return this;
  }

  void OnBeforeCommandLineProcessing(
      const CefString& process_type,
      CefRefPtr<CefCommandLine> cl) override {
    if (!process_type.empty()) return;
    if (getenv("WAYLAND_DISPLAY") && !getenv("QI_CEF_X11") && !getenv("OMAWEB_CEF_X11") &&
        !cl->HasSwitch("ozone-platform")) {
      cl->AppendSwitchWithValue("ozone-platform", "wayland");
    }
    // Pin Chrome's notion of the profile to ours, as YabCore does, so it
    // never aliases "last used" from Local State.
    if (!cl->HasSwitch("profile-directory"))
      cl->AppendSwitchWithValue("profile-directory", StartupProfile());
    // Comma lists: what we were given, plus the browser's flags file, each
    // switch appended exactly once.
    std::map<std::string, std::string> lists;
    for (const char* key : {"enable-features", "disable-features", "load-extension"})
      lists[key] = cl->HasSwitch(key) ? cl->GetSwitchValue(key).ToString() : "";
    ForwardFlagsFile(ActiveRoot().flags_file, cl, &lists);
    for (auto& [key, value] : lists) {
      if (!value.empty() && (!cl->HasSwitch(key) || cl->GetSwitchValue(key).ToString() != value))
        cl->AppendSwitchWithValue(key, value);
    }
  }

  void OnContextInitialized() override {
    ApplyTheme(CefRequestContext::GetGlobalContext());
    HandleCommandLine(CefCommandLine::GetGlobalCommandLine());
  }

  CefRefPtr<CefClient> GetDefaultClient() override { return SharedClient(); }

  bool OnAlreadyRunningAppRelaunch(CefRefPtr<CefCommandLine> cl,
                                   const CefString&) override {
    HandleCommandLine(cl);
    return true;
  }

 private:
  IMPLEMENT_REFCOUNTING(App);
};

}  // namespace

CefRefPtr<CefApp> CreateApp() {
  return new App();
}

}  // namespace qi
