// Qi's window around a Chrome-style CefBrowserView.
//
// Frameless, Omarchy-coloured, one page per window (Hyprland tiles and
// groups them). The Chrome toolbar, which carries the address box, the
// extension icons (LastPass's included) and their popups, is part of the
// window but hidden: Ctrl+L shows it until the next page loads,
// Ctrl+Shift+B pins it.
#include <spawn.h>
#include <unistd.h>

#include <algorithm>
#include <fstream>
#include <map>
#include <sstream>

#include "include/cef_app.h"
#include "include/cef_command_ids.h"
#include "include/cef_parser.h"
#include "include/views/cef_box_layout.h"
#include "include/views/cef_window.h"
#include "include/wrapper/cef_helpers.h"
#include "qi.h"

extern char** environ;

namespace qi {
namespace {

enum Command {
  kFocusLocation = 1001,
  kTogglePinnedToolbar,
  kNewWindow,
  kNewWindow2,
  kCloseWindow,
  kProfilePicker,
  kExtensions,
  kQuit,
  kSpace1 = 1100,  // ..1108
};

constexpr int kVkeyB = 'B', kVkeyL = 'L', kVkeyM = 'M', kVkeyN = 'N',
              kVkeyQ = 'Q', kVkeyT = 'T', kVkeyW = 'W', kVkeyX = 'X';

struct ToolbarState {
  bool pinned = false;
  bool transient = false;
};

std::vector<CefRefPtr<CefWindow>>& Windows() {
  static std::vector<CefRefPtr<CefWindow>> w;
  return w;
}

std::map<int, ToolbarState>& Toolbars() {
  static std::map<int, ToolbarState> m;
  return m;
}

void ShowToolbar(CefRefPtr<CefBrowserView> view, bool visible) {
  if (!view) return;
  auto toolbar = view->GetChromeToolbar();
  if (!toolbar || toolbar->IsVisible() == visible) return;
  toolbar->SetVisible(visible);
  if (auto window = view->GetWindow()) window->Layout();
}

class ViewDelegate : public CefBrowserViewDelegate {
 public:
  explicit ViewDelegate(std::string profile, bool toolbar)
      : profile_(std::move(profile)), toolbar_(toolbar) {}

  ChromeToolbarType GetChromeToolbarType(CefRefPtr<CefBrowserView>) override {
    return CEF_CTT_NORMAL;
  }
  cef_runtime_style_t GetBrowserRuntimeStyle() override {
    return CEF_RUNTIME_STYLE_CHROME;
  }

  void OnBrowserCreated(CefRefPtr<CefBrowserView>,
                        CefRefPtr<CefBrowser> browser) override {
    Toolbars()[browser->GetIdentifier()].pinned = toolbar_;
  }
  void OnBrowserDestroyed(CefRefPtr<CefBrowserView>,
                          CefRefPtr<CefBrowser> browser) override {
    Toolbars().erase(browser->GetIdentifier());
  }

  CefRefPtr<CefBrowserViewDelegate> GetDelegateForPopupBrowserView(
      CefRefPtr<CefBrowserView>,
      const CefBrowserSettings&,
      CefRefPtr<CefClient>,
      bool is_devtools) override {
    return new ViewDelegate(profile_, false);
  }

  bool OnPopupBrowserViewCreated(CefRefPtr<CefBrowserView>,
                                 CefRefPtr<CefBrowserView> popup,
                                 bool is_devtools) override;

 private:
  std::string profile_;
  bool toolbar_;
  IMPLEMENT_REFCOUNTING(ViewDelegate);
};

class WindowDelegate : public CefWindowDelegate {
 public:
  WindowDelegate(CefRefPtr<CefBrowserView> view, bool toolbar)
      : view_(view), toolbar_(toolbar) {}

  void OnWindowCreated(CefRefPtr<CefWindow> window) override {
    const Theme& t = CurrentTheme();
    CefBoxLayoutSettings s;
    s.horizontal = false;
    auto layout = window->SetToBoxLayout(s);
    window->AddChildView(view_);
    layout->SetFlexForView(view_, 1);
    // The Chrome toolbar can only be fetched once the view is in a window.
    if (auto toolbar = view_->GetChromeToolbar()) {
      window->AddChildViewAt(toolbar, 0);
      layout->SetFlexForView(toolbar, 0);
      toolbar->SetVisible(toolbar_);
    }
    window->SetBackgroundColor(t.background);
    window->SetTitle("Qi");

    window->SetAccelerator(kFocusLocation, kVkeyL, false, true, false, true);
    window->SetAccelerator(kTogglePinnedToolbar, kVkeyB, true, true, false, true);
    window->SetAccelerator(kNewWindow, kVkeyT, false, true, false, true);
    window->SetAccelerator(kNewWindow2, kVkeyN, false, true, false, true);
    window->SetAccelerator(kCloseWindow, kVkeyW, false, true, false, true);
    window->SetAccelerator(kProfilePicker, kVkeyM, true, true, false, true);
    window->SetAccelerator(kExtensions, kVkeyX, true, true, false, true);
    window->SetAccelerator(kQuit, kVkeyQ, false, true, false, true);
    for (int i = 0; i < 9; ++i)
      window->SetAccelerator(kSpace1 + i, '1' + i, false, true, true, true);

    Windows().push_back(window);
    window->Show();
    view_->RequestFocus();
  }

  void OnWindowDestroyed(CefRefPtr<CefWindow> window) override {
    auto& w = Windows();
    w.erase(std::remove_if(w.begin(), w.end(),
                           [&](auto& x) { return x->IsSame(window); }),
            w.end());
    view_ = nullptr;
    if (w.empty()) CefQuitMessageLoop();
  }

  bool CanClose(CefRefPtr<CefWindow>) override {
    auto browser = view_ ? view_->GetBrowser() : nullptr;
    return browser ? browser->GetHost()->TryCloseBrowser() : true;
  }

  bool IsFrameless(CefRefPtr<CefWindow>) override { return true; }

  cef_runtime_style_t GetWindowRuntimeStyle() override {
    return CEF_RUNTIME_STYLE_CHROME;
  }

  bool GetLinuxWindowProperties(CefRefPtr<CefWindow>,
                                CefLinuxWindowProperties& p) override {
    CefString(&p.wayland_app_id) = "qi-cef";
    CefString(&p.wm_class_class) = "qi-cef";
    CefString(&p.wm_class_name) = "qi-cef";
    return true;
  }

  bool OnAccelerator(CefRefPtr<CefWindow> window, int id) override {
    auto browser = view_ ? view_->GetBrowser() : nullptr;
    const std::string profile =
        browser ? ProfileDirOf(browser) : StartupProfile();
    switch (id) {
      case kFocusLocation:
        if (browser) Toolbars()[browser->GetIdentifier()].transient = true;
        ShowToolbar(view_, true);
        if (browser)
          browser->GetHost()->ExecuteChromeCommand(IDC_FOCUS_LOCATION,
                                                   CEF_WOD_CURRENT_TAB);
        return true;
      case kTogglePinnedToolbar: {
        if (!browser) return true;
        auto& st = Toolbars()[browser->GetIdentifier()];
        st.pinned = !st.pinned;
        st.transient = false;
        ShowToolbar(view_, st.pinned);
        return true;
      }
      case kNewWindow:
      case kNewWindow2:
        OpenWindow(profile, "chrome://newtab/", true);
        return true;
      case kCloseWindow:
        window->Close();
        return true;
      case kProfilePicker:
        OpenProfilePicker();
        return true;
      case kExtensions:
        OpenWindow(profile, "chrome://extensions/", true);
        return true;
      case kQuit:
        CloseAllWindows();
        return true;
      default:
        if (id >= kSpace1 && id < kSpace1 + 9) {
          std::string dir = ProfileForSpace(id - kSpace1);
          if (!dir.empty()) OpenWindow(dir, "chrome://newtab/", false);
          return true;
        }
    }
    return false;
  }

  static std::string ProfileDirOf(CefRefPtr<CefBrowser> browser) {
    std::string path =
        browser->GetHost()->GetRequestContext()->GetCachePath().ToString();
    auto slash = path.find_last_of('/');
    return slash == std::string::npos ? path : path.substr(slash + 1);
  }

 private:
  CefRefPtr<CefBrowserView> view_;
  bool toolbar_;
  IMPLEMENT_REFCOUNTING(WindowDelegate);
};

bool ViewDelegate::OnPopupBrowserViewCreated(CefRefPtr<CefBrowserView>,
                                             CefRefPtr<CefBrowserView> popup,
                                             bool is_devtools) {
  CefWindow::CreateTopLevelWindow(new WindowDelegate(popup, false));
  return true;
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

void OpenWindow(const std::string& profile_dir,
                const std::string& url,
                bool show_toolbar) {
  CEF_REQUIRE_UI_THREAD();
  const Theme& t = CurrentTheme();
  CefBrowserSettings bs;
  bs.background_color = t.background;
  auto view = CefBrowserView::CreateBrowserView(
      SharedClient(), url.empty() ? "chrome://newtab/" : url, bs, nullptr,
      ContextFor(profile_dir), new ViewDelegate(profile_dir, show_toolbar));
  CefWindow::CreateTopLevelWindow(new WindowDelegate(view, show_toolbar));
}

void OnBrowserLoading(CefRefPtr<CefBrowser> browser) {
  auto it = Toolbars().find(browser->GetIdentifier());
  if (it == Toolbars().end() || !it->second.transient) return;
  it->second.transient = false;
  if (!it->second.pinned) ShowToolbar(CefBrowserView::GetForBrowser(browser), false);
}

void CloseAllWindows() {
  auto copy = Windows();
  for (auto& w : copy) w->Close();
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
    << "place-items:center;font-weight:700;color:" << t.Css(t.background) << ";object-fit:cover}"
    << "small{opacity:.65;display:block}.warn{color:" << t.Css(t.accent) << "}"
    << "</style><h1>Choose a Chrome profile</h1>"
    << "<p>These are your real browser profiles. Opening one runs it live in "
       "Qi: its cookies, logins, extensions and settings.</p>";
  for (auto& root : KnownRoots()) {
    const bool active = root.id == ActiveRoot().id;
    std::string holder = active ? "" : LiveLockHolder(root.dir);
    h << "<h2>" << Escape(root.label) << " &middot; " << Escape(root.dir)
      << (active ? " (this window)" : "") << "</h2>";
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
  OpenWindow(StartupProfile(), url, false);
}

void SpawnFor(const std::string& root_id, const std::string& profile_dir) {
  char exe[4096];
  ssize_t n = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
  if (n <= 0) return;
  exe[n] = 0;
  std::string a1 = "--browser=" + root_id;
  std::string a2 = "--profile-directory=" + profile_dir;
  char* argv[] = {exe, a1.data(), a2.data(), nullptr};
  pid_t pid;
  posix_spawn(&pid, exe, nullptr, nullptr, argv, environ);
}

void HandleCommandLine(CefRefPtr<CefCommandLine> cl) {
  CEF_REQUIRE_UI_THREAD();
  if (cl->HasSwitch("picker")) {
    OpenProfilePicker();
    return;
  }
  std::string dir;
  if (cl->HasSwitch("space")) {
    std::string s = cl->GetSwitchValue("space");
    int index = atoi(s.c_str()) - 1;
    if (index < 0) {
      auto spaces = Spaces();
      for (size_t i = 0; i < spaces.size(); ++i) {
        if (spaces[i].id == s || strcasecmp(spaces[i].name.c_str(), s.c_str()) == 0)
          index = static_cast<int>(i);
      }
    }
    dir = ProfileForSpace(index);
  }
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
      if (url[0] == '/' ) url = "file://" + url;
      else if (url.find('.') != std::string::npos && url.find(' ') == std::string::npos)
        url = "https://" + url;
    }
    OpenWindow(dir, url, toolbar);
  }
}

}  // namespace qi
