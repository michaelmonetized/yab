// One CefClient for every browser: titles, loading, Qi's own links,
// and the shortcuts Chrome's window does not already own.
#include <fstream>
#include <set>

#include "include/cef_client.h"
#include "include/cef_command_ids.h"
#include "include/cef_parser.h"
#include "include/cef_task.h"
#include "include/views/cef_window.h"
#include "qi.h"

namespace qi {
namespace {

const char kCommandPrefix[] = "https://qi.invalid/";

std::set<std::string>& PickerDocuments() {
  static std::set<std::string> docs;
  return docs;
}

std::string Param(const std::string& query, const std::string& key) {
  size_t pos = 0;
  while (pos < query.size()) {
    size_t amp = query.find('&', pos);
    std::string pair = query.substr(pos, amp == std::string::npos ? std::string::npos : amp - pos);
    auto eq = pair.find('=');
    if (pair.substr(0, eq) == key && eq != std::string::npos) {
      return CefURIDecode(pair.substr(eq + 1), true,
                          static_cast<cef_uri_unescape_rule_t>(
                              UU_SPACES | UU_URL_SPECIAL_CHARS_EXCEPT_PATH_SEPARATORS |
                              UU_PATH_SEPARATORS | UU_REPLACE_PLUS_WITH_SPACE))
          .ToString();
    }
    if (amp == std::string::npos) break;
    pos = amp + 1;
  }
  return "";
}

std::string ProfileOf(CefRefPtr<CefBrowser> browser) {
  std::string path =
      browser->GetHost()->GetRequestContext()->GetCachePath().ToString();
  auto slash = path.find_last_of('/');
  return slash == std::string::npos ? path : path.substr(slash + 1);
}

std::string CachePathOf(CefRefPtr<CefBrowser> browser) {
  if (!browser || !browser->GetHost() || !browser->GetHost()->GetRequestContext())
    return "";
  return browser->GetHost()->GetRequestContext()->GetCachePath().ToString();
}

std::set<std::string>& ArmedProfiles() {
  static std::set<std::string> armed;
  return armed;
}

std::string ReadText(const std::string& path) {
  std::ifstream in(path);
  if (!in) return "";
  return std::string(std::istreambuf_iterator<char>(in),
                      std::istreambuf_iterator<char>());
}

bool PrefBool(CefRefPtr<CefDictionaryValue> dict, const char* key, bool fallback) {
  if (!dict || !dict->HasKey(key) || dict->GetType(key) != VTYPE_BOOL) return fallback;
  return dict->GetBool(key);
}

class ArmVerticalTabsTask : public CefTask {
 public:
  ArmVerticalTabsTask(CefRefPtr<CefBrowser> browser,
                      std::string profile,
                      bool enable,
                      bool hover,
                      bool collapse,
                      bool loaded,
                      int attempt)
      : browser_(browser),
        profile_(std::move(profile)),
        enable_(enable),
        hover_(hover),
        collapse_(collapse),
        loaded_(loaded),
        attempt_(attempt) {}

  void Execute() override {
    auto host = browser_ ? browser_->GetHost() : nullptr;
    if (!host) {
      ArmedProfiles().erase(profile_);
      return;
    }
    if (!loaded_) {
      auto root = CefParseJSON(ReadText(profile_ + "/Preferences"), JSON_PARSER_RFC);
      CefRefPtr<CefDictionaryValue> tabs;
      if (root && root->GetType() == VTYPE_DICTIONARY) {
        auto dict = root->GetDictionary();
        if (dict && dict->HasKey("vertical_tabs") &&
            dict->GetType("vertical_tabs") == VTYPE_DICTIONARY)
          tabs = dict->GetDictionary("vertical_tabs");
      }
      // Missing keys use Chromium's defaults: off, expand on hover, expanded.
      enable_ = !PrefBool(tabs, "enabled", false);
      hover_ = !PrefBool(tabs, "expand_on_hover", true);
      collapse_ = !PrefBool(tabs, "collapsed_state", false);
      loaded_ = true;
    }
    int id = 0;
    if (enable_) id = IDC_TOGGLE_VERTICAL_TABS;
    else if (hover_) id = IDC_TOGGLE_VERTICAL_TABS_EXPAND_ON_HOVER;
    else if (collapse_) id = IDC_TOGGLE_VERTICAL_TABS_COLLAPSE;
    else return;
    if (!host->CanExecuteChromeCommand(id)) {
      if (attempt_ < 20) {
        Schedule(attempt_ + 1);
        return;
      }
      if (id == IDC_TOGGLE_VERTICAL_TABS) enable_ = false;
      else if (id == IDC_TOGGLE_VERTICAL_TABS_EXPAND_ON_HOVER) hover_ = false;
      else collapse_ = false;
      if (enable_ || hover_ || collapse_) Schedule(0);
      return;
    }
    host->ExecuteChromeCommand(id, CEF_WOD_CURRENT_TAB);
    if (id == IDC_TOGGLE_VERTICAL_TABS) enable_ = false;
    else if (id == IDC_TOGGLE_VERTICAL_TABS_EXPAND_ON_HOVER) hover_ = false;
    else collapse_ = false;
    if (enable_ || hover_ || collapse_) Schedule(0);
  }

 private:
  void Schedule(int attempt) {
    CefPostDelayedTask(TID_UI,
                       new ArmVerticalTabsTask(browser_, profile_, enable_, hover_,
                                               collapse_, loaded_, attempt),
                       200);
  }

  CefRefPtr<CefBrowser> browser_;
  std::string profile_;
  bool enable_;
  bool hover_;
  bool collapse_;
  bool loaded_;
  int attempt_;
  IMPLEMENT_REFCOUNTING(ArmVerticalTabsTask);
};

void ArmVerticalTabs(CefRefPtr<CefBrowser> browser) {
  const std::string profile = CachePathOf(browser);
  if (profile.empty() || !ArmedProfiles().insert(profile).second) return;
  CefPostDelayedTask(TID_UI, new ArmVerticalTabsTask(browser, profile, false, false, false, false, 0),
                     300);
}

bool HandleShortcut(CefRefPtr<CefBrowser> browser, int type, int key, uint32_t mods) {
  if (type != KEYEVENT_RAWKEYDOWN) return false;
  if ((mods & EVENTFLAG_CONTROL_DOWN) == 0) return false;
  const bool shift = mods & EVENTFLAG_SHIFT_DOWN;
  const bool alt = mods & EVENTFLAG_ALT_DOWN;
  const bool repeat = mods & EVENTFLAG_IS_REPEAT;
  if (key >= 'a' && key <= 'z') key -= 'a' - 'A';
  if (!shift && !alt && (key == 'T' || key == 'N' || key == 'L' || key == 'W')) return false;
  // Ctrl+Shift+L is Chrome's own pin for this sidebar. Leave it alone.
  if (shift && !alt && key == 'M') {
    if (!repeat) OpenProfilePicker();
    return true;
  }
  if (shift && !alt && key == 'X') {
    if (!repeat) OpenWindow(ProfileOf(browser), "chrome://extensions/", true);
    return true;
  }
  if (!shift && !alt && key == 'Q') {
    if (!repeat) CloseAllWindows();
    return true;
  }
  if (!shift && alt && key >= '1' && key <= '9') {
    if (!repeat) {
      std::string dir = ProfileForSpace(key - '1');
      if (!dir.empty()) OpenWindow(dir, "chrome://newtab/", false);
    }
    return true;
  }
  return false;
}

class Client : public CefClient,
               public CefDisplayHandler,
               public CefLoadHandler,
               public CefRequestHandler,
               public CefLifeSpanHandler,
               public CefKeyboardHandler,
               public CefInputHandler {
 public:
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefKeyboardHandler> GetKeyboardHandler() override { return this; }
  CefRefPtr<CefInputHandler> GetInputHandler() override { return this; }

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    TrackBrowser(browser);
    ArmVerticalTabs(browser);
  }

  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override { ForgetBrowser(browser); }

  bool OnPreKeyEvent(CefRefPtr<CefBrowser> browser,
                     const CefKeyEvent& event,
                     CefEventHandle,
                     bool*) override {
    return HandleShortcut(browser, event.type, event.windows_key_code, event.modifiers);
  }

  bool OnPreKeyboardEvent(CefRefPtr<CefBrowser> browser,
                          const CefKeyboardInputEvent& event,
                          const CefInputEventContext&,
                          bool*) override {
    return HandleShortcut(browser, event.type, event.windows_key_code, event.modifiers);
  }

  void OnTitleChange(CefRefPtr<CefBrowser> browser,
                     const CefString& title) override {
    auto view = CefBrowserView::GetForBrowser(browser);
    if (!view) return;
    if (auto window = view->GetWindow()) {
      const std::string profile = ProfileLabel(ProfileOf(browser));
      window->SetTitle(title.ToString() + ": Qi · " + profile);
    }
  }

  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                            bool loading,
                            bool,
                            bool) override {
    if (loading) OnBrowserLoading(browser);
  }

  bool RunPickerCommand(CefRefPtr<CefBrowser> browser,
                        CefRefPtr<CefFrame> frame,
                        const std::string& url,
                        bool user_gesture,
                        bool is_redirect) {
    if (is_redirect || !user_gesture || !frame || !frame->IsMain()) return false;
    if (!PickerDocuments().count(frame->GetURL().ToString())) return false;
    std::string rest = url.substr(sizeof(kCommandPrefix) - 1);
    auto q = rest.find('?');
    const std::string cmd = rest.substr(0, q);
    const std::string query = q == std::string::npos ? "" : rest.substr(q + 1);
    if (cmd == "open") {
      std::string root_id = Param(query, "root");
      std::string dir = Param(query, "dir");
      if (root_id.empty() || root_id == ActiveRoot().id) {
        if (!KnownProfileFolder(ActiveRoot(), dir)) return false;
        OpenWindow(dir, "chrome://newtab/", false);
      } else {
        ChromeRoot root = RootById(root_id);
        if (root.id.empty() || !KnownProfileFolder(root, dir)) return false;
        SpawnFor(root.id, dir);
      }
    } else if (cmd == "picker") {
      OpenProfilePicker();
    }
    return true;
  }

  bool OnBeforeBrowse(CefRefPtr<CefBrowser> browser,
                      CefRefPtr<CefFrame> frame,
                      CefRefPtr<CefRequest> request,
                      bool user_gesture,
                      bool is_redirect) override {
    const std::string url = request->GetURL();
    if (url.rfind(kCommandPrefix, 0) != 0) return false;
    RunPickerCommand(browser, frame, url, user_gesture, is_redirect);
    return true;  // never actually navigate to qi.invalid
  }

  bool OnBeforePopup(CefRefPtr<CefBrowser> browser,
                     CefRefPtr<CefFrame> frame,
                     int,
                     const CefString& target_url,
                     const CefString&,
                     CefLifeSpanHandler::WindowOpenDisposition,
                     bool user_gesture,
                     const CefPopupFeatures&,
                     CefWindowInfo&,
                     CefRefPtr<CefClient>&,
                     CefBrowserSettings&,
                     CefRefPtr<CefDictionaryValue>&,
                     bool*) override {
    const std::string url = target_url;
    if (url.rfind(kCommandPrefix, 0) != 0) return false;
    RunPickerCommand(browser, frame, url, user_gesture, false);
    return true;
  }

 private:
  IMPLEMENT_REFCOUNTING(Client);
};

}  // namespace

CefRefPtr<CefClient> SharedClient() {
  static CefRefPtr<CefClient> client = new Client();
  return client;
}

void RememberPickerDocument(const std::string& url) { PickerDocuments().insert(url); }

bool IsPickerDocument(const std::string& url) { return PickerDocuments().count(url) != 0; }

}  // namespace qi
