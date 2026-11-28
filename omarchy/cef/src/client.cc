// One CefClient for every browser: titles, loading, Qi's own links,
// and the shortcuts Chrome's window does not already own.
#include <set>

#include "include/cef_client.h"
#include "include/cef_parser.h"
#include "keys.h"
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

std::set<std::string>& KeysDocuments() {
  static std::set<std::string> docs;
  return docs;
}

bool HandleShortcut(int type, int key, uint32_t mods) {
  if (type != KEYEVENT_RAWKEYDOWN) return false;
  if (mods & EVENTFLAG_IS_REPEAT) return false;
  const bool ctrl = mods & EVENTFLAG_CONTROL_DOWN;
  const bool shift = mods & EVENTFLAG_SHIFT_DOWN;
  const bool alt = mods & EVENTFLAG_ALT_DOWN;
  if (key >= 'a' && key <= 'z') key -= 'a' - 'A';
  if (ctrl && alt && !shift && key >= '1' && key <= '9') {
    RunAction(std::string("space-") + static_cast<char>(key));
    return true;
  }
  if (alt && !ctrl && !shift && key >= '1' && key <= '9') {
    RunAction(std::string("tab-") + static_cast<char>(key));
    return true;
  }
  if (alt && !ctrl && !shift && key == 0x25) return RunAction("back");
  if (alt && !ctrl && !shift && key == 0x27) return RunAction("forward");
  if (alt && !ctrl && !shift && key == 'D') return RunAction("focus-location");
  if (!ctrl) return false;
  if (!shift && !alt && key == 'T') return RunAction("new-tab");
  if (!shift && !alt && key == 'N') return RunAction("new-window");
  if (!shift && !alt && key == 'W') return RunAction("close-tab");
  if (!shift && !alt && key == 'L') return RunAction("focus-location");
  if (!shift && !alt && key == 'Q') return RunAction("quit");
  if (!shift && !alt && key == 'D') return RunAction("duplicate-tab");
  if (!shift && !alt && key == 'F') return RunAction("find-in-page");
  if (!shift && !alt && key == 'R') return RunAction("reload");
  if (!shift && !alt && key == 'S') return RunAction("save-page");
  if (!shift && !alt && key == 'P') return RunAction("print");
  if (!shift && !alt && key == 'J') return RunAction("downloads");
  if (!shift && !alt && key == 'U') return RunAction("view-source");
  if (shift && !alt && key == 'B') return RunAction("toggle-sidebar");
  if (shift && !alt && key == 'L') return RunAction("toggle-sidebar");
  if (shift && !alt && key == 'T') return RunAction("restore-tab");
  if (shift && !alt && key == 'R') return RunAction("reload-no-cache");
  if (shift && !alt && key == 'M') return RunAction("profile-picker");
  if (shift && !alt && key == 'X') return RunAction("extensions");
  if (shift && !alt && key == 'U') return RunAction("show-extension-toolbar");
  if (shift && !alt && key == 'I') return RunAction("devtools");
  if (shift && key == 0x09) return RunAction("previous-tab");
  if (!shift && key == 0x09) return RunAction("next-tab");
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
    NoteOpened(browser);
  }

  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override { ForgetBrowser(browser); }

  bool OnPreKeyEvent(CefRefPtr<CefBrowser> browser,
                     const CefKeyEvent& event,
                     CefEventHandle,
                     bool*) override {
    return HandleShortcut(event.type, event.windows_key_code, event.modifiers);
  }

  bool OnPreKeyboardEvent(CefRefPtr<CefBrowser>,
                          const CefKeyboardInputEvent& event,
                          const CefInputEventContext&,
                          bool*) override {
    return HandleShortcut(event.type, event.windows_key_code, event.modifiers);
  }

  void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) override {
    NotePage(browser, title, "");
  }

  void OnAddressChange(CefRefPtr<CefBrowser> browser,
                       CefRefPtr<CefFrame> frame,
                       const CefString& url) override {
    if (!frame || !frame->IsMain()) return;
    NotePage(browser, "", url);
  }

  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool loading, bool, bool) override {
    if (!loading) return;
    OnBrowserLoading(browser);
    NoteLoad(browser);
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
    if (!is_redirect && user_gesture && frame && frame->IsMain() &&
        IsKeysDocument(frame->GetURL().ToString())) {
      std::string rest = url.substr(sizeof(kCommandPrefix) - 1);
      auto q = rest.find('?');
      const std::string cmd = rest.substr(0, q);
      const std::string query = q == std::string::npos ? "" : rest.substr(q + 1);
      if (cmd == "set-key") {
        std::string action = Param(query, "action");
        std::string chord = Param(query, "chord");
        if (!action.empty()) SetKeyOverride(KeysPath(), action, chord);
        ReloadKeyMap();
        return true;
      }
    }
    RunPickerCommand(browser, frame, url, user_gesture, is_redirect);
    return true;  // never actually navigate to qi.invalid
  }

  bool OnBeforePopup(CefRefPtr<CefBrowser> browser,
                     CefRefPtr<CefFrame> frame,
                     int,
                     const CefString& target_url,
                     const CefString&,
                     CefLifeSpanHandler::WindowOpenDisposition disposition,
                     bool user_gesture,
                     const CefPopupFeatures&,
                     CefWindowInfo&,
                     CefRefPtr<CefClient>&,
                     CefBrowserSettings&,
                     CefRefPtr<CefDictionaryValue>&,
                     bool*) override {
    const std::string url = target_url;
    if (url.rfind(kCommandPrefix, 0) == 0) {
      RunPickerCommand(browser, frame, url, user_gesture, false);
      return true;
    }
    if (url.rfind("chrome-extension://", 0) == 0 || disposition == CEF_WOD_NEW_POPUP)
      return false;
    if (disposition == CEF_WOD_NEW_WINDOW) {
      OpenFreshWindow(ProfileOf(browser), url, false, false);
      return true;
    }
    if (disposition == CEF_WOD_OFF_THE_RECORD) {
      OpenFreshWindow(ProfileOf(browser), url, false, true);
      return true;
    }
    if (disposition == CEF_WOD_NEW_BACKGROUND_TAB) {
      if (!OpenAsTab(browser, url, true)) OpenFreshWindow(ProfileOf(browser), url, false, false);
      return true;
    }
    if (disposition == CEF_WOD_NEW_FOREGROUND_TAB || disposition == CEF_WOD_SINGLETON_TAB ||
        disposition == CEF_WOD_SWITCH_TO_TAB) {
      if (!OpenAsTab(browser, url, false)) OpenFreshWindow(ProfileOf(browser), url, false, false);
      return true;
    }
    return false;
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

void RememberKeysDocument(const std::string& url) { KeysDocuments().insert(url); }

bool IsKeysDocument(const std::string& url) { return KeysDocuments().count(url) != 0; }

}  // namespace qi
