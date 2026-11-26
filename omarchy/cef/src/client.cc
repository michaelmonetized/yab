// One CefClient for every browser: titles, loading, Qi's own links.
#include "include/cef_client.h"
#include "include/cef_parser.h"
#include "include/views/cef_window.h"
#include "qi.h"

namespace qi {
namespace {

const char kCommandPrefix[] = "https://qi.invalid/";

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

class Client : public CefClient,
               public CefDisplayHandler,
               public CefLoadHandler,
               public CefRequestHandler,
               public CefLifeSpanHandler {
 public:
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }

  void OnTitleChange(CefRefPtr<CefBrowser> browser,
                     const CefString& title) override {
    auto view = CefBrowserView::GetForBrowser(browser);
    if (!view) return;
    if (auto window = view->GetWindow()) {
      const std::string profile = ProfileLabel(ProfileOf(browser));
      window->SetTitle(title.ToString() + " — Qi · " + profile);
    }
  }

  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                            bool loading,
                            bool,
                            bool) override {
    if (loading) OnBrowserLoading(browser);
  }

  bool OnBeforeBrowse(CefRefPtr<CefBrowser> browser,
                      CefRefPtr<CefFrame> frame,
                      CefRefPtr<CefRequest> request,
                      bool,
                      bool) override {
    const std::string url = request->GetURL();
    if (url.rfind(kCommandPrefix, 0) != 0) return false;
    std::string rest = url.substr(sizeof(kCommandPrefix) - 1);
    auto q = rest.find('?');
    const std::string cmd = rest.substr(0, q);
    const std::string query = q == std::string::npos ? "" : rest.substr(q + 1);
    if (cmd == "open") {
      std::string root = Param(query, "root");
      std::string dir = Param(query, "dir");
      if (root.empty() || root == ActiveRoot().id) {
        OpenWindow(dir, "chrome://newtab/", false);
      } else {
        SpawnFor(root, dir);
      }
    } else if (cmd == "picker") {
      OpenProfilePicker();
    }
    return true;  // never actually navigate to qi.invalid
  }

 private:
  IMPLEMENT_REFCOUNTING(Client);
};

}  // namespace

CefRefPtr<CefClient> SharedClient() {
  static CefRefPtr<CefClient> client = new Client();
  return client;
}

}  // namespace qi
