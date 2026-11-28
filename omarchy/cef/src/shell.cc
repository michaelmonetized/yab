// Qi's window.
//
// One CefWindow. The first page is a Chrome-style browser view so extensions
// keep working. CEF rejects a second Chrome view in that window, and this
// build's Chrome view is a popup so it cannot grow a tab. Later tabs are
// Alloy views in the same window, same profile. The stock toolbar stays put
// (moving it makes Browser's user-data host CHECK on close) and is hidden
// until the extension hatch asks for it.
#include "keys.h"
#include "qi.h"

#include <sqlite3.h>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <vector>

#include "include/cef_app.h"
#include "include/cef_command_ids.h"
#include "include/cef_parser.h"
#include "include/cef_task.h"
#include "include/views/cef_box_layout.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_browser_view_delegate.h"
#include "include/views/cef_button.h"
#include "include/views/cef_label_button.h"
#include "include/views/cef_panel.h"
#include "include/views/cef_textfield.h"
#include "include/views/cef_textfield_delegate.h"
#include "include/views/cef_window.h"
#include "include/wrapper/cef_helpers.h"

namespace qi {
namespace {

namespace fs = std::filesystem;

constexpr int kAccelBase = 3000;
constexpr int kHandleId = 1;
constexpr int kPinId = 2;
constexpr int kChipBack = 3;
constexpr int kTabBase = 10000;
constexpr int kFavBase = 20000;
constexpr int kChipBase = 30000;
constexpr int kSuggestBase = 40000;

enum class Side { Hidden, Icons, Full };

struct Accel {
  std::string name;
  Chord chord;
};
std::vector<Accel> g_accel;

int AccelKey(const Chord& chord) {
  int key = chord.key;
  if (key == '-' ) return 0xBD;
  if (key == '=' || key == '+') return 0xBB;
  if (key == '[') return 0xDB;
  if (key == ']') return 0xDD;
  if (key == ',') return 0xBC;
  return key;
}

bool RegisterChord(const Chord& chord) {
  if (chord.super || chord.key == 0) return false;
  if (!chord.ctrl && !chord.alt) {
    if (chord.key < 0x70 || chord.key > 0x87) return false;
  }
  return true;
}

std::string Trim(std::string s) {
  while (!s.empty() && std::isspace(static_cast<unsigned char>(s.front()))) s.erase(s.begin());
  while (!s.empty() && std::isspace(static_cast<unsigned char>(s.back()))) s.pop_back();
  return s;
}

std::string ConfigPath() {
  const char* cfg = getenv("XDG_CONFIG_HOME");
  if (cfg && *cfg) return std::string(cfg) + "/qi/config.toml";
  return HomeDir() + "/.config/qi/config.toml";
}

std::string ReadFile(const std::string& path) {
  std::ifstream in(path);
  if (!in) return "";
  std::stringstream ss;
  ss << in.rdbuf();
  return ss.str();
}

void WriteFile(const std::string& path, const std::string& body) {
  auto slash = path.find_last_of('/');
  if (slash != std::string::npos) MakeDirs(path.substr(0, slash));
  std::ofstream out(path, std::ios::trunc);
  out << body;
}

std::string Lower(std::string s) {
  for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return s;
}

bool Contains(const std::string& hay, const std::string& needle) {
  if (needle.empty()) return true;
  return Lower(hay).find(Lower(needle)) != std::string::npos;
}

std::string Letter(const std::string& url, const std::string& title) {
  std::string host = url;
  auto scheme = host.find("://");
  if (scheme != std::string::npos) host = host.substr(scheme + 3);
  auto cut = host.find_first_of("/?#");
  if (cut != std::string::npos) host.resize(cut);
  if (host.rfind("www.", 0) == 0) host = host.substr(4);
  if (host.empty()) host = title;
  if (host.empty()) return "?";
  unsigned char c = static_cast<unsigned char>(host[0]);
  if (c < 128) return std::string(1, static_cast<char>(std::toupper(c)));
  return host.substr(0, 1);
}

std::string Short(const std::string& text, size_t n) {
  if (text.size() <= n) return text;
  return text.substr(0, n - 1) + "…";
}

void StyleButton(CefRefPtr<CefLabelButton> button, cef_color_t fg) {
  if (!button) return;
  button->SetTextColor(CEF_BUTTON_STATE_NORMAL, fg);
  button->SetTextColor(CEF_BUTTON_STATE_HOVERED, fg);
  button->SetTextColor(CEF_BUTTON_STATE_PRESSED, fg);
  button->SetFontList("sans-serif, 13px");
}

void Clipboard(const std::string& text) {
  FILE* pipe = popen("wl-copy", "w");
  if (!pipe) return;
  fwrite(text.data(), 1, text.size(), pipe);
  pclose(pipe);
}

std::string SearchTemplate() {
  std::ifstream in(ConfigPath());
  std::string line;
  while (std::getline(in, line)) {
    auto hash = line.find('#');
    if (hash != std::string::npos) line.resize(hash);
    line = Trim(line);
    auto eq = line.find('=');
    if (eq == std::string::npos || Trim(line.substr(0, eq)) != "search") continue;
    auto a = line.find('"', eq);
    auto b = a == std::string::npos ? a : line.find('"', a + 1);
    if (a != std::string::npos && b != std::string::npos) return line.substr(a + 1, b - a - 1);
  }
  return "https://duckduckgo.com/?q={}";
}

std::string SearchUrl(const std::string& query) {
  std::string tmpl = SearchTemplate();
  std::string enc = CefURIEncode(query, false);
  auto at = tmpl.find("{}");
  if (at == std::string::npos) return tmpl + enc;
  tmpl.replace(at, 2, enc);
  return tmpl;
}

bool LooksLikeUrl(const std::string& text) {
  if (text.find("://") != std::string::npos) return true;
  if (text.find(' ') != std::string::npos) return false;
  if (text.rfind("localhost", 0) == 0) return true;
  if (text.rfind("chrome:", 0) == 0 || text.rfind("about:", 0) == 0) return true;
  return text.find('.') != std::string::npos;
}

struct Mark {
  std::string title;
  std::string url;
  bool folder = false;
  std::vector<Mark> kids;
};

struct Fav {
  std::string url;
  std::string title;
};

struct Hist {
  std::string url;
  std::string title;
};

class Shell;

std::vector<CefRefPtr<Shell>>& Shells() {
  static std::vector<CefRefPtr<Shell>> all;
  return all;
}

CefRefPtr<Shell> g_active;
bool g_polling = false;
bool g_keys_seen = false;
fs::file_time_type g_keys_time{};

class Shell : public CefBaseRefCounted {
 public:
  std::string profile;
  bool priv = false;
  bool alive = true;
  std::string start_url;
  bool show_well = false;
  CefRefPtr<CefRequestContext> ctx;
  CefRefPtr<CefWindow> window;
  CefRefPtr<CefPanel> edge;
  CefRefPtr<CefPanel> gutter;
  CefRefPtr<CefLabelButton> gutter_spacer;
  CefRefPtr<CefPanel> stack;
  CefRefPtr<CefBoxLayout> stack_layout;
  CefRefPtr<CefBrowserView> page;
  CefRefPtr<CefPanel> sidebar;
  CefRefPtr<CefPanel> favs;
  CefRefPtr<CefPanel> tabs_panel;
  CefRefPtr<CefPanel> palette;
  CefRefPtr<CefPanel> chips;
  CefRefPtr<CefPanel> suggests;
  CefRefPtr<CefPanel> well;
  CefRefPtr<CefTextfield> field;
  CefRefPtr<CefOverlayController> side_overlay;
  CefRefPtr<CefOverlayController> palette_overlay;
  bool pinned = false;
  bool peek = false;
  bool palette_on = false;
  bool rebind = false;
  Side mode = Side::Hidden;
  size_t active = 0;
  int suggest_at = 0;
  std::string private_dir;
  std::vector<int> chip_path;
  std::vector<Mark> bookmarks;
  std::vector<Fav> fav_items;
  std::vector<std::string> chip_urls;
  std::vector<std::string> suggest_urls;
  struct Tab {
    CefRefPtr<CefBrowser> browser;
    CefRefPtr<CefBrowserView> view;
    std::string title;
    std::string url;
    bool pinned = false;
    bool muted = false;
    bool keys = false;
  };
  std::vector<Tab> tabs;
  std::vector<Fav> closed;

  void Build(CefRefPtr<CefWindow> created);
  void LayoutOverlays();
  void ApplyMode();
  void Cycle();
  void TogglePin();
  void Raise();
  void AddTab(const std::string& url, bool background);
  void Adopt(CefRefPtr<CefBrowser> browser);
  void Select(size_t index);
  void ShowActive();
  void CloseActive();
  void Restore();
  void Note(CefRefPtr<CefBrowser> browser, const std::string& title, const std::string& url);
  void Navigated(CefRefPtr<CefBrowser> browser);
  void Drop(CefRefPtr<CefBrowser> browser);
  // Drop the Chrome view before the window goes. Browser's destructor aborts
  // if the toolbar is still registered on it.
  void ReleaseChromeViews();
  void TakeToolbar(CefRefPtr<CefBrowserView> view);
  void Press(int id);
  void FieldChanged();
  bool FieldKey(const CefKeyEvent& event);
  bool Run(const std::string& name);
  void ApplyKeys();
  void ShowPalette();
  void ClosePalette();
  bool Owns(CefRefPtr<CefBrowser> browser) const;
  void RefreshKeysPage();

 private:
  void LoadSide();
  void SaveSide();
  void LoadFavs();
  void SaveFavs();
  void RebuildFavs();
  void RebuildTabs();
  void RebuildChips();
  void RebuildSuggest();
  void LoadBookmarks();
  void Go(const std::string& url);
  void Chrome(int id);
  CefRefPtr<CefBrowser> ActiveBrowser() const;
  std::string ActiveUrl() const;
  std::string ActiveTitle() const;
  const std::vector<Mark>* ChipFolder() const;
  CefRefPtr<CefLabelButton> MakeButton(int id, const std::string& text, const std::string& tip);
  void PaintActive();
  IMPLEMENT_REFCOUNTING(Shell);
};

CefRefPtr<Shell> ActiveShell() {
  if (g_active && g_active->alive && g_active->window) return g_active;
  if (Shells().empty()) return nullptr;
  return Shells().back();
}

CefRefPtr<Shell> ShellFor(CefRefPtr<CefBrowser> browser) {
  if (!browser) return nullptr;
  for (auto& shell : Shells())
    if (shell->Owns(browser)) return shell;
  return nullptr;
}

class CloseTask : public CefTask {
 public:
  explicit CloseTask(CefRefPtr<CefWindow> window) : window_(window) {}
  void Execute() override {
    if (window_ && !window_->IsClosed()) window_->Close();
  }

 private:
  CefRefPtr<CefWindow> window_;
  IMPLEMENT_REFCOUNTING(CloseTask);
};

class PollKeys : public CefTask {
 public:
  void Execute() override;
 private:
  IMPLEMENT_REFCOUNTING(PollKeys);
};

class ButtonHub : public CefButtonDelegate {
 public:
  explicit ButtonHub(CefRefPtr<Shell> shell) : shell_(shell) {}
  void OnButtonPressed(CefRefPtr<CefButton> button) override {
    if (shell_ && shell_->alive && button) shell_->Press(button->GetID());
  }

 private:
  CefRefPtr<Shell> shell_;
  IMPLEMENT_REFCOUNTING(ButtonHub);
};

class FieldHub : public CefTextfieldDelegate {
 public:
  explicit FieldHub(CefRefPtr<Shell> shell) : shell_(shell) {}
  void OnAfterUserAction(CefRefPtr<CefTextfield>) override {
    if (shell_ && shell_->alive) shell_->FieldChanged();
  }
  bool OnKeyEvent(CefRefPtr<CefTextfield>, const CefKeyEvent& event) override {
    return shell_ && shell_->alive && shell_->FieldKey(event);
  }

 private:
  CefRefPtr<Shell> shell_;
  IMPLEMENT_REFCOUNTING(FieldHub);
};

class AlloyHub : public CefBrowserViewDelegate {
 public:
  cef_runtime_style_t GetBrowserRuntimeStyle() override { return CEF_RUNTIME_STYLE_ALLOY; }

 private:
  IMPLEMENT_REFCOUNTING(AlloyHub);
};

class ViewHub : public CefBrowserViewDelegate {
 public:
  explicit ViewHub(CefRefPtr<Shell> shell) : shell_(shell) {}
  ChromeToolbarType GetChromeToolbarType(CefRefPtr<CefBrowserView>) override {
    return CEF_CTT_NORMAL;
  }
  cef_runtime_style_t GetBrowserRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
  void OnWindowChanged(CefRefPtr<CefView> view, bool added) override {
    if (!added || !shell_ || !shell_->alive || !view) return;
    if (auto browser_view = view->AsBrowserView()) shell_->TakeToolbar(browser_view);
  }
  void OnBrowserDestroyed(CefRefPtr<CefBrowserView>, CefRefPtr<CefBrowser> browser) override {
    if (shell_ && shell_->alive) shell_->Drop(browser);
  }
  bool OnPopupBrowserViewCreated(CefRefPtr<CefBrowserView>,
                                 CefRefPtr<CefBrowserView> popup,
                                 bool) override;

 private:
  CefRefPtr<Shell> shell_;
  IMPLEMENT_REFCOUNTING(ViewHub);
};

class WindowHub : public CefWindowDelegate {
 public:
  explicit WindowHub(CefRefPtr<Shell> shell) : shell_(shell) {}
  void OnWindowCreated(CefRefPtr<CefWindow> window) override {
    if (shell_) shell_->Build(window);
  }
  void OnWindowDestroyed(CefRefPtr<CefWindow> window) override {
    ForgetWindow(window);
    if (!shell_) return;
    auto shell = shell_;
    shell_ = nullptr;
    shell->alive = false;
    shell->window = nullptr;
    if (g_active && shell && g_active.get() == shell.get()) g_active = nullptr;
    auto& all = Shells();
    all.erase(std::remove_if(all.begin(), all.end(),
                             [&](auto& have) { return have.get() == shell.get(); }),
              all.end());
    if (shell->priv && !shell->private_dir.empty()) {
      std::error_code ec;
      fs::remove_all(shell->private_dir, ec);
    }
    for (auto& tab : shell->tabs) {
      auto browser = tab.browser;
      if (!browser && tab.view) browser = tab.view->GetBrowser();
      if (browser) ForgetBrowser(browser);
    }
    shell->tabs.clear();
    shell->page = nullptr;
  }
  void OnWindowBoundsChanged(CefRefPtr<CefWindow>, const CefRect&) override {
    if (shell_ && shell_->alive) shell_->LayoutOverlays();
  }
  void OnWindowActivationChanged(CefRefPtr<CefWindow>, bool active) override {
    if (active && shell_ && shell_->alive) g_active = shell_;
  }
  bool CanClose(CefRefPtr<CefWindow> window) override {
    // Closing a Chrome browser aborts inside Browser's destructor. The last
    // window is released and the process exits. Any earlier window is hidden
    // so the others keep running.
    if (shell_ && OtherWindowsOpen() && window) {
      window->Hide();
      ForgetWindow(window);
      shell_->alive = false;
      if (g_active && g_active.get() == shell_.get()) g_active = nullptr;
      return false;
    }
    if (shell_) shell_->ReleaseChromeViews();
    return true;
  }
  bool OnAccelerator(CefRefPtr<CefWindow>, int id) override {
    if (!shell_ || !shell_->alive) return false;
    int index = id - kAccelBase;
    if (index < 0 || index >= static_cast<int>(g_accel.size())) return false;
    return shell_->Run(g_accel[index].name);
  }
  bool IsFrameless(CefRefPtr<CefWindow>) override { return true; }
  cef_runtime_style_t GetWindowRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
  bool GetLinuxWindowProperties(CefRefPtr<CefWindow>, CefLinuxWindowProperties& props) override {
    CefString(&props.wayland_app_id) = "qi-cef";
    CefString(&props.wm_class_class) = "qi-cef";
    CefString(&props.wm_class_name) = "qi-cef";
    return true;
  }

 private:
  CefRefPtr<Shell> shell_;
  IMPLEMENT_REFCOUNTING(WindowHub);
};

class PopupHub : public CefWindowDelegate {
 public:
  explicit PopupHub(CefRefPtr<CefBrowserView> view) : view_(view) {}
  void OnWindowCreated(CefRefPtr<CefWindow> window) override {
    window->AddChildView(view_);
    window->CenterWindow({480, 640});
    RememberWindow(window);
    window->Show();
  }
  void OnWindowDestroyed(CefRefPtr<CefWindow> window) override {
    ForgetWindow(window);
    view_ = nullptr;
  }
  bool CanClose(CefRefPtr<CefWindow> window) override {
    // Same Chrome destructor abort as a main window. Hide the popup.
    if (window) {
      window->Hide();
      ForgetWindow(window);
    }
    view_ = nullptr;
    return false;
  }
  cef_runtime_style_t GetWindowRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
  bool GetLinuxWindowProperties(CefRefPtr<CefWindow>, CefLinuxWindowProperties& props) override {
    CefString(&props.wayland_app_id) = "qi-cef";
    CefString(&props.wm_class_class) = "qi-cef";
    CefString(&props.wm_class_name) = "qi-cef";
    return true;
  }

 private:
  CefRefPtr<CefBrowserView> view_;
  IMPLEMENT_REFCOUNTING(PopupHub);
};

class PopupView : public CefBrowserViewDelegate {
 public:
  ChromeToolbarType GetChromeToolbarType(CefRefPtr<CefBrowserView>) override {
    return CEF_CTT_NORMAL;
  }
  cef_runtime_style_t GetBrowserRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
  bool OnPopupBrowserViewCreated(CefRefPtr<CefBrowserView>,
                                 CefRefPtr<CefBrowserView> popup,
                                 bool) override {
    CefWindow::CreateTopLevelWindow(new PopupHub(popup));
    return true;
  }

 private:
  IMPLEMENT_REFCOUNTING(PopupView);
};

bool ViewHub::OnPopupBrowserViewCreated(CefRefPtr<CefBrowserView>,
                                       CefRefPtr<CefBrowserView> popup,
                                       bool) {
  CefWindow::CreateTopLevelWindow(new PopupHub(popup));
  return true;
}

CefRefPtr<CefLabelButton> Shell::MakeButton(int id, const std::string& text, const std::string& tip) {
  auto button = CefLabelButton::CreateLabelButton(new ButtonHub(this), text);
  button->SetID(id);
  button->SetTooltipText(tip);
  button->SetAccessibleName(tip.empty() ? text : tip);
  StyleButton(button, CurrentTheme().foreground);
  return button;
}

void Shell::LoadSide() {
  pinned = false;
  mode = Side::Hidden;
  std::ifstream in(ConfigPath());
  std::string line;
  while (std::getline(in, line)) {
    auto hash = line.find('#');
    if (hash != std::string::npos) line.resize(hash);
    line = Trim(line);
    auto eq = line.find('=');
    if (eq == std::string::npos) continue;
    std::string key = Trim(line.substr(0, eq));
    std::string value = Trim(line.substr(eq + 1));
    if (key == "pin_sidebar") pinned = value.find("true") != std::string::npos;
    if (key == "sidebar") {
      if (value.find("full") != std::string::npos) mode = Side::Full;
      else if (value.find("icons") != std::string::npos) mode = Side::Icons;
      else mode = Side::Hidden;
    }
  }
  if (!pinned) mode = Side::Hidden;
}

void Shell::SaveSide() {
  const std::string path = ConfigPath();
  std::ifstream in(path);
  std::vector<std::string> lines;
  std::string line;
  bool saw_pin = false;
  bool saw_mode = false;
  while (std::getline(in, line)) {
    std::string body = line;
    auto hash = body.find('#');
    if (hash != std::string::npos) body.resize(hash);
    std::string trimmed = Trim(body);
    auto eq = trimmed.find('=');
    std::string key = eq == std::string::npos ? "" : Trim(trimmed.substr(0, eq));
    if (key == "pin_sidebar") {
      line = std::string("pin_sidebar = ") + (pinned ? "true" : "false");
      saw_pin = true;
    } else if (key == "sidebar") {
      const char* name = mode == Side::Full ? "full" : mode == Side::Icons ? "icons" : "hidden";
      line = std::string("sidebar = \"") + name + "\"";
      saw_mode = true;
    }
    lines.push_back(line);
  }
  if (!saw_pin) lines.push_back(std::string("pin_sidebar = ") + (pinned ? "true" : "false"));
  if (!saw_mode) {
    const char* name = mode == Side::Full ? "full" : mode == Side::Icons ? "icons" : "hidden";
    lines.push_back(std::string("sidebar = \"") + name + "\"");
  }
  std::string body;
  for (auto& item : lines) body += item + "\n";
  WriteFile(path, body);
}

void Shell::LoadFavs() {
  fav_items.clear();
  auto parsed = CefParseJSON(ReadFile(DataDir() + "/favorites.json"), JSON_PARSER_RFC);
  if (!parsed || parsed->GetType() != VTYPE_LIST) return;
  auto list = parsed->GetList();
  for (size_t i = 0; i < list->GetSize(); ++i) {
    auto row = list->GetDictionary(i);
    if (!row) continue;
    Fav fav;
    fav.url = row->GetString("url");
    fav.title = row->GetString("title");
    if (!fav.url.empty()) fav_items.push_back(fav);
  }
}

void Shell::SaveFavs() {
  if (priv) return;
  auto list = CefListValue::Create();
  for (size_t i = 0; i < fav_items.size(); ++i) {
    auto row = CefDictionaryValue::Create();
    row->SetString("url", fav_items[i].url);
    row->SetString("title", fav_items[i].title);
    list->SetDictionary(i, row);
  }
  auto value = CefValue::Create();
  value->SetList(list);
  WriteFile(DataDir() + "/favorites.json", CefWriteJSON(value, JSON_WRITER_DEFAULT));
}

void Shell::RebuildFavs() {
  if (!favs) return;
  favs->RemoveAllChildViews();
  const bool row = mode != Side::Icons && !peek;
  const int across = row ? 6 : 1;
  CefRefPtr<CefPanel> line;
  CefRefPtr<CefBoxLayout> layout;
  for (size_t i = 0; i < fav_items.size(); ++i) {
    if (!line || static_cast<int>(i) % across == 0) {
      line = CefPanel::CreatePanel(nullptr);
      CefBoxLayoutSettings settings;
      settings.horizontal = true;
      layout = line->SetToBoxLayout(settings);
      favs->AddChildView(line);
    }
    auto button = MakeButton(kFavBase + static_cast<int>(i), Letter(fav_items[i].url, fav_items[i].title),
                             fav_items[i].title.empty() ? fav_items[i].url : fav_items[i].title);
    button->SetMinimumSize({40, 36});
    line->AddChildView(button);
    if (layout) layout->SetFlexForView(button, 0);
  }
}

void Shell::RebuildTabs() {
  if (!tabs_panel) return;
  tabs_panel->RemoveAllChildViews();
  const bool icons = mode == Side::Icons && !peek;
  const Theme& theme = CurrentTheme();
  for (size_t i = 0; i < tabs.size(); ++i) {
    std::string face = icons ? Letter(tabs[i].url, tabs[i].title)
                             : Short(tabs[i].title.empty() ? tabs[i].url : tabs[i].title, 32);
    if (tabs[i].pinned && !icons) face = "• " + face;
    std::string tip = tabs[i].title.empty() ? tabs[i].url : tabs[i].title + "\n" + tabs[i].url;
    auto button = MakeButton(kTabBase + static_cast<int>(i), face, tip);
    button->SetMinimumSize({icons ? 44 : 248, 32});
    if (i == active) button->SetBackgroundColor(theme.accent);
    else button->SetBackgroundColor(theme.selection);
    tabs_panel->AddChildView(button);
  }
  auto pin = MakeButton(kPinId, pinned ? "Unpin" : "Pin", pinned ? "Unpin the sidebar" : "Pin the sidebar");
  pin->SetMinimumSize({icons ? 44 : 248, 28});
  tabs_panel->AddChildView(pin);
}

void HideOmnibox(CefRefPtr<CefView> view) {
  if (!view) return;
  const std::string type = view->GetTypeString();
  if (type.find("Omnibox") != std::string::npos || type.find("LocationBar") != std::string::npos) {
    view->SetVisible(false);
    return;
  }
  if (auto panel = view->AsPanel()) {
    for (size_t i = 0; i < panel->GetChildViewCount(); ++i) HideOmnibox(panel->GetChildViewAt(i));
  }
}

void HideStockChrome(CefRefPtr<CefBrowserView> view, bool show_toolbar) {
  if (!view) return;
  auto bar = view->GetChromeToolbar();
  if (!bar) return;
  HideOmnibox(bar);
  bar->SetVisible(show_toolbar);
  auto parent = bar->GetParentView();
  auto panel = parent ? parent->AsPanel() : nullptr;
  if (!panel) return;
  for (size_t i = 0; i < panel->GetChildViewCount(); ++i) {
    auto child = panel->GetChildViewAt(i);
    if (!child || child->IsSame(bar)) continue;
    const std::string type = child->GetTypeString();
    if (type.find("TabStrip") != std::string::npos) child->SetVisible(false);
  }
}

void Shell::TakeToolbar(CefRefPtr<CefBrowserView> view) {
  HideStockChrome(view, show_well);
}

void Shell::ShowActive() {
  if (stack_layout) {
    for (size_t i = 0; i < tabs.size(); ++i) {
      if (!tabs[i].view) continue;
      bool on = i == active;
      tabs[i].view->SetVisible(on);
      stack_layout->SetFlexForView(tabs[i].view, on ? 1 : 0);
      if (on) HideStockChrome(tabs[i].view, show_well);
    }
  }
  rebind = !tabs.empty() && active < tabs.size() && tabs[active].keys;
  ApplyKeys();
  if (window) {
    std::string title = ActiveTitle();
    if (title.empty()) title = "Qi";
    std::string who = priv ? "Private" : ProfileLabel(profile);
    window->SetTitle(title + ": Qi · " + who);
    window->Layout();
  }
  PaintActive();
}

void Shell::PaintActive() { RebuildTabs(); }

CefRefPtr<CefBrowser> Shell::ActiveBrowser() const {
  if (active >= tabs.size()) return nullptr;
  if (tabs[active].browser) return tabs[active].browser;
  if (tabs[active].view) return tabs[active].view->GetBrowser();
  return nullptr;
}

std::string Shell::ActiveUrl() const {
  if (active >= tabs.size()) return "";
  return tabs[active].url;
}

std::string Shell::ActiveTitle() const {
  if (active >= tabs.size()) return "";
  return tabs[active].title;
}

bool Shell::Owns(CefRefPtr<CefBrowser> browser) const {
  if (!browser) return false;
  for (auto& tab : tabs) {
    if (tab.browser && tab.browser->IsSame(browser)) return true;
    auto have = tab.view ? tab.view->GetBrowser() : nullptr;
    if (have && have->IsSame(browser)) return true;
  }
  return false;
}

void Shell::Select(size_t index) {
  if (index >= tabs.size()) return;
  active = index;
  ShowActive();
  if (auto browser = ActiveBrowser()) {
    if (browser->GetHost()) browser->GetHost()->SetFocus(true);
  }
}

void Shell::AddTab(const std::string& url, bool background) {
  const Theme& theme = CurrentTheme();
  CefBrowserSettings settings;
  settings.background_color = theme.background;
  std::string dest = url.empty() ? "chrome://newtab/" : url;
  const bool chrome = !page;
  CefRefPtr<CefBrowserViewDelegate> hub = chrome ? static_cast<CefBrowserViewDelegate*>(new ViewHub(this))
                                                 : static_cast<CefBrowserViewDelegate*>(new AlloyHub());
  auto view = CefBrowserView::CreateBrowserView(SharedClient(), dest, settings, nullptr, ctx, hub);
  view->SetPreferAccelerators(true);
  if (chrome) page = view;
  Tab tab;
  tab.view = view;
  tab.url = dest;
  tab.title = "New tab";
  tab.keys = dest.rfind("data:text/html", 0) == 0 && dest.find("Qi%20keys") != std::string::npos;
  tabs.push_back(tab);
  if (stack) stack->AddChildView(view);
  if (!background) active = tabs.size() - 1;
  ShowActive();
}

void Shell::Adopt(CefRefPtr<CefBrowser> browser) {
  if (!browser) return;
  auto view = CefBrowserView::GetForBrowser(browser);
  if (!view) return;
  for (auto& tab : tabs) {
    if (!tab.view || !tab.view->IsSame(view)) continue;
    if (!tab.browser) tab.browser = browser;
    return;
  }
}

void Shell::Go(const std::string& url) {
  auto browser = ActiveBrowser();
  if (!browser || !browser->GetMainFrame()) {
    AddTab(url, false);
  } else {
    browser->GetMainFrame()->LoadURL(url);
    if (active < tabs.size()) tabs[active].url = url;
  }
  ClosePalette();
}

void Shell::Chrome(int id) {
  auto browser = ActiveBrowser();
  if (!browser || !browser->GetHost()) return;
  browser->GetHost()->ExecuteChromeCommand(id, CEF_WOD_CURRENT_TAB);
}

void ReadMarks(CefRefPtr<CefListValue> list, std::vector<Mark>* out) {
  if (!list || !out) return;
  for (size_t i = 0; i < list->GetSize(); ++i) {
    auto row = list->GetDictionary(i);
    if (!row) continue;
    Mark mark;
    mark.title = row->GetString("name");
    std::string type = row->GetString("type");
    if (type == "folder") {
      mark.folder = true;
      ReadMarks(row->GetList("children"), &mark.kids);
    } else {
      mark.url = row->GetString("url");
    }
    if (mark.folder || !mark.url.empty()) out->push_back(std::move(mark));
  }
}

void Shell::LoadBookmarks() {
  bookmarks.clear();
  std::string path = ActiveDataDir() + "/" + profile + "/Bookmarks";
  auto parsed = CefParseJSON(ReadFile(path), JSON_PARSER_RFC);
  if (!parsed || parsed->GetType() != VTYPE_DICTIONARY) return;
  auto roots = parsed->GetDictionary()->GetDictionary("roots");
  if (!roots) return;
  auto bar = roots->GetDictionary("bookmark_bar");
  if (!bar) return;
  ReadMarks(bar->GetList("children"), &bookmarks);
}

const std::vector<Mark>* Shell::ChipFolder() const {
  const std::vector<Mark>* at = &bookmarks;
  for (int index : chip_path) {
    if (index < 0 || index >= static_cast<int>(at->size()) || !(*at)[index].folder) return at;
    at = &(*at)[index].kids;
  }
  return at;
}

void Shell::RebuildChips() {
  if (!chips) return;
  chips->RemoveAllChildViews();
  chip_urls.clear();
  const std::vector<Mark>* folder = ChipFolder();
  if (!chip_path.empty()) {
    auto back = MakeButton(kChipBack, "<", "Back");
    back->SetMinimumSize({32, 32});
    chips->AddChildView(back);
  }
  if (!folder) return;
  int n = 0;
  for (auto& mark : *folder) {
    if (n >= 16) break;
    std::string face = mark.folder ? "+" : Letter(mark.url, mark.title);
    auto button = MakeButton(kChipBase + n, face, mark.title.empty() ? mark.url : mark.title);
    button->SetMinimumSize({32, 32});
    chips->AddChildView(button);
    chip_urls.push_back(mark.folder ? "" : mark.url);
    ++n;
  }
}

std::vector<Hist> RecentHistory(const std::string& profile) {
  std::vector<Hist> rows;
  std::string src = ActiveDataDir() + "/" + profile + "/History";
  if (!fs::exists(src)) return rows;
  std::string dest = StateDir() + "/history-read.db";
  std::error_code ec;
  fs::copy_file(src, dest, fs::copy_options::overwrite_existing, ec);
  if (ec) return rows;
  fs::copy_file(src + "-wal", dest + "-wal", fs::copy_options::overwrite_existing, ec);
  sqlite3* db = nullptr;
  if (sqlite3_open_v2(dest.c_str(), &db, SQLITE_OPEN_READONLY, nullptr) != SQLITE_OK) {
    if (db) sqlite3_close(db);
    return rows;
  }
  auto collect = [](void* ptr, int count, char** values, char**) -> int {
    auto* out = static_cast<std::vector<Hist>*>(ptr);
    if (count >= 1 && values && values[0]) {
      Hist row;
      row.url = values[0];
      row.title = count >= 2 && values[1] ? values[1] : values[0];
      out->push_back(std::move(row));
    }
    return 0;
  };
  char* err = nullptr;
  sqlite3_exec(db,
               "SELECT url, title FROM urls ORDER BY last_visit_time DESC LIMIT 50",
               collect, &rows, &err);
  if (err) sqlite3_free(err);
  sqlite3_close(db);
  return rows;
}

void CollectMarks(const std::vector<Mark>& marks, const std::string& query, std::vector<Hist>* out) {
  for (auto& mark : marks) {
    if (mark.folder) {
      CollectMarks(mark.kids, query, out);
      continue;
    }
    if (Contains(mark.title, query) || Contains(mark.url, query)) out->push_back({mark.url, mark.title});
  }
}

void Shell::RebuildSuggest() {
  if (!suggests || !field) return;
  suggests->RemoveAllChildViews();
  suggest_urls.clear();
  std::string query = Trim(field->GetText().ToString());
  std::vector<Hist> hits;
  if (!query.empty()) {
    for (auto& shell : Shells()) {
      for (auto& tab : shell->tabs) {
        if (Contains(tab.title, query) || Contains(tab.url, query))
          hits.push_back({tab.url, tab.title.empty() ? tab.url : tab.title + "  (open)"});
      }
    }
    CollectMarks(bookmarks, query, &hits);
  }
  if (!priv) {
    for (auto& row : RecentHistory(profile)) {
      if (query.empty() || Contains(row.title, query) || Contains(row.url, query)) hits.push_back(row);
    }
  }
  if (suggest_at >= static_cast<int>(hits.size())) suggest_at = 0;
  int shown = 0;
  for (size_t i = 0; i < hits.size() && shown < 8; ++i, ++shown) {
    std::string face = hits[i].title.empty() ? hits[i].url : hits[i].title;
    if (static_cast<int>(i) == suggest_at) face = "> " + face;
    auto button = MakeButton(kSuggestBase + shown, Short(face, 72), hits[i].url);
    button->SetMinimumSize({640, 28});
    suggests->AddChildView(button);
    suggest_urls.push_back(hits[i].url);
  }
}

void Shell::ShowPalette() {
  palette_on = true;
  LoadBookmarks();
  chip_path.clear();
  RebuildChips();
  suggest_at = 0;
  if (field) {
    field->SetText(ActiveUrl());
    field->SelectAll(false);
  }
  RebuildSuggest();
  ShowActive();
  LayoutOverlays();
  if (palette_overlay) palette_overlay->SetVisible(true);
  if (field) field->RequestFocus();
}

void Shell::ClosePalette() {
  if (!palette_on) return;
  palette_on = false;
  if (palette_overlay) palette_overlay->SetVisible(false);
  ShowActive();
}

void Shell::FieldChanged() {
  suggest_at = 0;
  RebuildSuggest();
  LayoutOverlays();
}

bool Shell::FieldKey(const CefKeyEvent& event) {
  if (event.type != KEYEVENT_RAWKEYDOWN) return false;
  if (event.windows_key_code == 0x1B) {
    if (peek && !pinned) {
      peek = false;
      ApplyMode();
    }
    ClosePalette();
    return true;
  }
  if (event.windows_key_code == 0x26) {
    if (suggest_at > 0) --suggest_at;
    RebuildSuggest();
    return true;
  }
  if (event.windows_key_code == 0x28) {
    ++suggest_at;
    RebuildSuggest();
    return true;
  }
  if (event.windows_key_code == 0x0D) {
    std::string query = Trim(field ? field->GetText().ToString() : "");
    if (suggest_at >= 0 && suggest_at < static_cast<int>(suggest_urls.size()) && !query.empty()) {
      Go(suggest_urls[suggest_at]);
      return true;
    }
    if (query.empty()) query = "chrome://newtab/";
    else if (!LooksLikeUrl(query)) query = SearchUrl(query);
    else if (query.find("://") == std::string::npos && query.find(' ') == std::string::npos &&
             query.rfind("chrome:", 0) != 0 && query.rfind("about:", 0) != 0 &&
             query.rfind("file:", 0) != 0)
      query = "https://" + query;
    Go(query);
    return true;
  }
  return false;
}

void Shell::LayoutOverlays() {
  if (!window) return;
  CefRect client = window->GetClientAreaBoundsInScreen();
  int width = client.width > 0 ? client.width : 1280;
  int height = client.height > 0 ? client.height : 800;
  int side = (mode == Side::Icons && pinned && !peek) ? 48 : 260;
  bool show_side = peek || pinned;
  if (side_overlay) {
    side_overlay->SetBounds({0, 0, side, height});
    side_overlay->SetVisible(show_side);
  }
  if (edge) edge->SetVisible(!show_side);
  if (gutter) gutter->SetVisible(pinned && !peek);
  if (gutter_spacer) gutter_spacer->SetMinimumSize({pinned && !peek ? side : 1, 1});
  if (palette_overlay) {
    int box_w = std::min(720, std::max(320, width - 48));
    int box_h = std::min(420, std::max(180, height / 2));
    palette_overlay->SetBounds({(width - box_w) / 2, 28, box_w, box_h});
    palette_overlay->SetVisible(palette_on);
  }
}

void Shell::ApplyMode() {
  if (gutter) gutter->SetVisible(pinned && !peek);
  RebuildFavs();
  RebuildTabs();
  LayoutOverlays();
  if (window) window->Layout();
}

void Shell::Cycle() {
  peek = false;
  if (!pinned || mode == Side::Hidden) {
    pinned = true;
    mode = Side::Icons;
  } else if (mode == Side::Icons) {
    mode = Side::Full;
  } else {
    pinned = false;
    mode = Side::Hidden;
  }
  SaveSide();
  ApplyMode();
}

void Shell::TogglePin() {
  peek = false;
  if (!pinned) {
    pinned = true;
    if (mode == Side::Hidden) mode = Side::Full;
  } else {
    pinned = false;
    mode = Side::Hidden;
  }
  SaveSide();
  ApplyMode();
}

void Shell::Raise() {
  if (pinned) return;
  peek = true;
  ApplyMode();
}

void Shell::Press(int id) {
  if (id == kHandleId) {
    Raise();
    return;
  }
  if (id == kPinId) {
    TogglePin();
    return;
  }
  if (id == kChipBack) {
    if (!chip_path.empty()) chip_path.pop_back();
    RebuildChips();
    return;
  }
  if (id >= kTabBase && id < kFavBase) {
    Select(static_cast<size_t>(id - kTabBase));
    return;
  }
  if (id >= kFavBase && id < kChipBase) {
    size_t index = static_cast<size_t>(id - kFavBase);
    if (index >= fav_items.size()) return;
    const std::string& url = fav_items[index].url;
    for (size_t i = 0; i < tabs.size(); ++i) {
      if (tabs[i].url == url) {
        Select(i);
        return;
      }
    }
    AddTab(url, false);
    return;
  }
  if (id >= kChipBase && id < kSuggestBase) {
    const std::vector<Mark>* folder = ChipFolder();
    int index = id - kChipBase;
    if (!folder || index < 0 || index >= static_cast<int>(folder->size())) return;
    if ((*folder)[index].folder) {
      chip_path.push_back(index);
      RebuildChips();
      return;
    }
    if (index < static_cast<int>(chip_urls.size()) && !chip_urls[index].empty()) Go(chip_urls[index]);
    return;
  }
  if (id >= kSuggestBase) {
    size_t index = static_cast<size_t>(id - kSuggestBase);
    if (index < suggest_urls.size()) Go(suggest_urls[index]);
  }
}

void Shell::CloseActive() {
  if (active >= tabs.size()) return;
  auto browser = ActiveBrowser();
  if (active < tabs.size()) closed.push_back({tabs[active].url, tabs[active].title});
  if (closed.size() > 20) closed.erase(closed.begin());
  if (browser && browser->GetHost()) browser->GetHost()->CloseBrowser(false);
}

void Shell::Restore() {
  if (closed.empty()) return;
  Fav back = closed.back();
  closed.pop_back();
  AddTab(back.url, false);
}

void Shell::Note(CefRefPtr<CefBrowser> browser, const std::string& title, const std::string& url) {
  for (auto& tab : tabs) {
    auto have = tab.browser ? tab.browser : (tab.view ? tab.view->GetBrowser() : nullptr);
    if (!have || !have->IsSame(browser)) continue;
    if (url.rfind("data:text/html", 0) == 0 && url.find("Qi%20keys") != std::string::npos) tab.keys = true;
    if (!title.empty()) tab.title = title;
    if (!url.empty()) tab.url = url;
  }
  RebuildTabs();
  if (window && ActiveBrowser() && ActiveBrowser()->IsSame(browser)) {
    std::string heading = ActiveTitle();
    if (heading.empty()) heading = "Qi";
    window->SetTitle(heading + ": Qi · " + (priv ? std::string("Private") : ProfileLabel(profile)));
  }
}

void Shell::Navigated(CefRefPtr<CefBrowser> browser) {
  if (ActiveBrowser() && ActiveBrowser()->IsSame(browser)) ClosePalette();
}

void Shell::ReleaseChromeViews() {
  // These three register on Chrome's browser and outlive a normal close:
  // the toolbar, its autofill bubble, and the extension container. Remove
  // the toolbar view so they unregister before that destructor runs.
  if (page) {
    auto bar = page->GetChromeToolbar();
    auto parent = bar ? bar->GetParentView() : nullptr;
    auto panel = parent ? parent->AsPanel() : nullptr;
    if (panel && bar) panel->RemoveChildView(bar);
  }
  std::vector<CefRefPtr<CefBrowser>> browsers;
  std::vector<CefRefPtr<CefBrowserView>> views;
  for (auto& tab : tabs) {
    auto browser = tab.browser;
    if (!browser && tab.view) browser = tab.view->GetBrowser();
    if (browser) browsers.push_back(browser);
    if (tab.view) views.push_back(tab.view);
    tab.view = nullptr;
    tab.browser = nullptr;
  }
  page = nullptr;
  tabs.clear();
  for (auto& browser : browsers) ForgetBrowser(browser);
  for (auto& view : views) {
    if (stack) stack->RemoveChildView(view);
  }
}

void Shell::Drop(CefRefPtr<CefBrowser> browser) {
  for (size_t i = 0; i < tabs.size(); ++i) {
    auto have = tabs[i].browser ? tabs[i].browser : (tabs[i].view ? tabs[i].view->GetBrowser() : nullptr);
    if (!have || !have->IsSame(browser)) continue;
    if (tabs[i].view && stack) stack->RemoveChildView(tabs[i].view);
    if (page && tabs[i].view && page->IsSame(tabs[i].view)) page = nullptr;
    tabs.erase(tabs.begin() + static_cast<long>(i));
    if (!tabs.empty() && active >= tabs.size()) active = tabs.size() - 1;
    if (!tabs.empty()) ShowActive();
    break;
  }
  if (tabs.empty() && window && !window->IsClosed())
    CefPostTask(TID_UI, new CloseTask(window));
}

std::string KeysPage() {
  const Theme& theme = CurrentTheme();
  std::ostringstream html;
  html << "<!doctype html><meta charset=utf-8><title>Qi keys</title><style>"
       << "body{background:" << theme.Css(theme.background) << ";color:" << theme.Css(theme.foreground)
       << ";font:14px sans-serif;margin:32px auto;max-width:720px}"
       << "button{font:inherit;color:inherit;background:" << theme.Css(theme.selection)
       << ";border:1px solid " << theme.Css(theme.muted)
       << ";border-radius:8px;padding:8px 12px;margin:4px 0;display:block;width:100%;text-align:left}"
       << "button:focus{outline:2px solid " << theme.Css(theme.accent) << "}"
       << "#wait{min-height:1.4em}</style><h1>Keyboard</h1>"
       << "<p id=wait>Click a row, then press the new shortcut. Escape clears it. "
          "Super shortcuts are delivered by the Hyprland snippet, not by this window.</p>";
  LoadKeys(KeysPath());
  for (auto& action : Actions()) {
    std::string chords;
    for (auto& chord : action.chords) {
      if (!chords.empty()) chords += ", ";
      chords += chord.text;
    }
    html << "<button data-a=\"" << action.name << "\">" << action.title << "  <small>"
         << chords << "</small></button>";
  }
  html << "<script>\n"
          "let action='';\n"
          "function chord(e){\n"
          "  const skip=['Control','Shift','Alt','Meta'];\n"
          "  if(skip.indexOf(e.key)>=0) return '';\n"
          "  const p=[];\n"
          "  if(e.ctrlKey)p.push('Ctrl');\n"
          "  if(e.shiftKey)p.push('Shift');\n"
          "  if(e.altKey)p.push('Alt');\n"
          "  if(e.metaKey)p.push('Super');\n"
          "  let k=e.key;\n"
          "  if(k===' ')k='Space';\n"
          "  if(k.length===1)k=k.toUpperCase();\n"
          "  const map={ArrowLeft:'Left',ArrowRight:'Right',ArrowUp:'Up',ArrowDown:'Down',"
          "PageUp:'PageUp',PageDown:'PageDown',Escape:'Escape'};\n"
          "  if(map[k])k=map[k];\n"
          "  p.push(k);\n"
          "  return p.join('+');\n"
          "}\n"
          "document.querySelectorAll('button').forEach(b=>b.onclick=()=>{\n"
          "  action=b.dataset.a;\n"
          "  document.getElementById('wait').textContent='Press a shortcut for '+action;\n"
          "});\n"
          "window.onkeydown=e=>{\n"
          "  if(!action) return;\n"
          "  e.preventDefault();\n"
          "  if(e.key==='Escape'){\n"
          "    location.href='https://qi.invalid/set-key?action='+encodeURIComponent(action)+'&chord=';\n"
          "    return;\n"
          "  }\n"
          "  const c=chord(e);\n"
          "  if(!c) return;\n"
          "  location.href='https://qi.invalid/set-key?action='+encodeURIComponent(action)+'&chord='+encodeURIComponent(c);\n"
          "};\n"
          "</script>";
  std::string body = html.str();
  std::string url = "data:text/html;base64," + CefBase64Encode(body.data(), body.size()).ToString();
  RememberKeysDocument(url);
  return url;
}

void Shell::RefreshKeysPage() {
  if (active >= tabs.size() || !tabs[active].keys) return;
  auto browser = ActiveBrowser();
  if (!browser || !browser->GetMainFrame()) return;
  std::string url = KeysPage();
  tabs[active].url = url;
  tabs[active].keys = true;
  browser->GetMainFrame()->LoadURL(url);
}

void BuildAccelTable();

void Shell::ApplyKeys() {
  if (!window) return;
  if (g_accel.empty() && !g_keys_seen) BuildAccelTable();
  window->RemoveAllAccelerators();
  if (rebind) return;
  for (size_t i = 0; i < g_accel.size(); ++i) {
    const Action* action = FindAction(g_accel[i].name);
    const Chord& chord = g_accel[i].chord;
    bool shift = chord.shift || chord.key == '+';
    window->SetAccelerator(kAccelBase + static_cast<int>(i), AccelKey(chord), shift, chord.ctrl,
                           chord.alt, action && action->high);
  }
}

bool Shell::Run(const std::string& name) {
  if (!alive) return false;
  if (name == "focus-location") {
    ShowPalette();
    return true;
  }
  if (name == "toggle-sidebar") {
    Cycle();
    return true;
  }
  if (name == "show-extension-toolbar") {
    show_well = true;
    ShowPalette();
    return true;
  }
  if (name == "new-tab") {
    AddTab("chrome://newtab/", false);
    return true;
  }
  if (name == "close-tab") {
    CloseActive();
    return true;
  }
  if (name == "restore-tab") {
    Restore();
    return true;
  }
  if (name == "duplicate-tab") {
    AddTab(ActiveUrl().empty() ? "chrome://newtab/" : ActiveUrl(), false);
    return true;
  }
  if (name == "pin-tab") {
    if (active < tabs.size()) {
      tabs[active].pinned = !tabs[active].pinned;
      if (tabs[active].pinned) {
        Tab tab = tabs[active];
        tabs.erase(tabs.begin() + static_cast<long>(active));
        size_t at = 0;
        while (at < tabs.size() && tabs[at].pinned) ++at;
        tabs.insert(tabs.begin() + static_cast<long>(at), tab);
        active = at;
      }
      ShowActive();
    }
    return true;
  }
  if (name == "mute-tab") {
    auto browser = ActiveBrowser();
    if (browser && browser->GetHost() && active < tabs.size()) {
      tabs[active].muted = !tabs[active].muted;
      browser->GetHost()->SetAudioMuted(tabs[active].muted);
    }
    return true;
  }
  if (name == "bookmark") {
    if (priv) return true;
    std::string url = ActiveUrl();
    if (url.empty() || url.rfind("data:", 0) == 0) return true;
    for (auto& fav : fav_items)
      if (fav.url == url) return true;
    fav_items.push_back({url, ActiveTitle().empty() ? url : ActiveTitle()});
    SaveFavs();
    RebuildFavs();
    return true;
  }
  if (name == "copy-url") {
    Clipboard(ActiveUrl());
    return true;
  }
  if (name == "copy-url-markdown") {
    std::string title = ActiveTitle().empty() ? ActiveUrl() : ActiveTitle();
    Clipboard("[" + title + "](" + ActiveUrl() + ")");
    return true;
  }
  if (name == "previous-tab" && !tabs.empty()) {
    Select(active == 0 ? tabs.size() - 1 : active - 1);
    return true;
  }
  if (name == "next-tab" && !tabs.empty()) {
    Select((active + 1) % tabs.size());
    return true;
  }
  if (name.rfind("tab-", 0) == 0 && name.size() == 5 && name[4] >= '1' && name[4] <= '9') {
    size_t index = static_cast<size_t>(name[4] - '1');
    if (name[4] == '9') index = tabs.empty() ? 0 : tabs.size() - 1;
    if (index < tabs.size()) Select(index);
    return true;
  }
  if (name.rfind("space-", 0) == 0 && name.size() == 7 && name[6] >= '1' && name[6] <= '9') {
    std::string dir = ProfileForSpace(name[6] - '1');
    if (!dir.empty()) OpenFreshWindow(dir, "chrome://newtab/", false, false);
    return true;
  }
  if (name == "new-window") {
    OpenFreshWindow(profile, "chrome://newtab/", false, priv);
    return true;
  }
  if (name == "private-window") {
    OpenFreshWindow(profile, "chrome://newtab/", false, true);
    return true;
  }
  if (name == "close-window") {
    if (window) window->Close();
    return true;
  }
  if (name == "quit") {
    CloseAllWindows();
    return true;
  }
  if (name == "profile-picker") {
    OpenProfilePicker();
    return true;
  }
  if (name == "extensions") {
    AddTab("chrome://extensions/", false);
    return true;
  }
  if (name == "settings-keys") {
    AddTab(KeysPage(), false);
    return true;
  }
  if (name == "history") {
    AddTab("chrome://history", false);
    return true;
  }
  if (name == "downloads") {
    AddTab("chrome://downloads", false);
    return true;
  }
  if (name == "reload") {
    Chrome(IDC_RELOAD);
    return true;
  }
  if (name == "reload-no-cache") {
    Chrome(IDC_RELOAD_BYPASSING_CACHE);
    return true;
  }
  if (name == "back") {
    Chrome(IDC_BACK);
    return true;
  }
  if (name == "forward") {
    Chrome(IDC_FORWARD);
    return true;
  }
  if (name == "zoom-in") {
    Chrome(IDC_ZOOM_PLUS);
    return true;
  }
  if (name == "zoom-out") {
    Chrome(IDC_ZOOM_MINUS);
    return true;
  }
  if (name == "zoom-reset") {
    Chrome(IDC_ZOOM_NORMAL);
    return true;
  }
  if (name == "find-in-page") {
    Chrome(IDC_FIND);
    return true;
  }
  if (name == "find-next") {
    Chrome(IDC_FIND_NEXT);
    return true;
  }
  if (name == "find-previous") {
    Chrome(IDC_FIND_PREVIOUS);
    return true;
  }
  if (name == "view-source") {
    Chrome(IDC_VIEW_SOURCE);
    return true;
  }
  if (name == "devtools") {
    Chrome(IDC_DEV_TOOLS_TOGGLE);
    return true;
  }
  if (name == "print") {
    Chrome(IDC_PRINT);
    return true;
  }
  if (name == "save-page") {
    Chrome(IDC_SAVE_PAGE);
    return true;
  }
  return false;
}

void Shell::Build(CefRefPtr<CefWindow> created) {
  window = created;
  g_active = this;
  RememberWindow(window);
  const Theme& theme = CurrentTheme();
  window->SetBackgroundColor(theme.background);
  LoadSide();
  LoadFavs();

  CefBoxLayoutSettings horizontal;
  horizontal.horizontal = true;
  CefBoxLayoutSettings vertical;
  vertical.horizontal = false;

  auto root = CefPanel::CreatePanel(nullptr);
  auto root_layout = root->SetToBoxLayout(horizontal);
  edge = CefPanel::CreatePanel(nullptr);
  CefBoxLayoutSettings edge_box;
  edge_box.horizontal = false;
  edge_box.main_axis_alignment = CEF_AXIS_ALIGNMENT_CENTER;
  edge->SetToBoxLayout(edge_box);
  edge->SetBackgroundColor(theme.selection);
  auto handle_button = MakeButton(kHandleId, ">", "Show the sidebar");
  handle_button->SetMinimumSize({22, 96});
  handle_button->SetBackgroundColor(theme.accent);
  edge->AddChildView(handle_button);
  root->AddChildView(edge);
  root_layout->SetFlexForView(edge, 0);
  gutter = CefPanel::CreatePanel(nullptr);
  gutter->SetToBoxLayout(vertical);
  gutter_spacer = MakeButton(0, "", "");
  gutter_spacer->SetMinimumSize({1, 1});
  gutter->AddChildView(gutter_spacer);
  root->AddChildView(gutter);
  root_layout->SetFlexForView(gutter, 0);

  stack = CefPanel::CreatePanel(nullptr);
  stack_layout = stack->SetToBoxLayout(vertical);
  root->AddChildView(stack);
  root_layout->SetFlexForView(stack, 1);
  auto window_layout = window->SetToBoxLayout(vertical);
  window->AddChildView(root);
  window_layout->SetFlexForView(root, 1);

  sidebar = CefPanel::CreatePanel(nullptr);
  sidebar->SetToBoxLayout(vertical);
  sidebar->SetBackgroundColor(theme.background);
  favs = CefPanel::CreatePanel(nullptr);
  favs->SetToBoxLayout(vertical);
  tabs_panel = CefPanel::CreatePanel(nullptr);
  auto tabs_layout = tabs_panel->SetToBoxLayout(vertical);
  sidebar->AddChildView(favs);
  sidebar->AddChildView(tabs_panel);
  tabs_layout->SetFlexForView(tabs_panel, 1);

  palette = CefPanel::CreatePanel(nullptr);
  palette->SetToBoxLayout(vertical);
  palette->SetBackgroundColor(theme.selection);
  auto row = CefPanel::CreatePanel(nullptr);
  auto row_layout = row->SetToBoxLayout(horizontal);
  field = CefTextfield::CreateTextfield(new FieldHub(this));
  field->SetPlaceholderText("Search or type a URL");
  field->SetFontList("sans-serif, 16px");
  row->AddChildView(field);
  row_layout->SetFlexForView(field, 1);
  well = CefPanel::CreatePanel(nullptr);
  well->SetToBoxLayout(horizontal);
  row->AddChildView(well);
  chips = CefPanel::CreatePanel(nullptr);
  chips->SetToBoxLayout(horizontal);
  suggests = CefPanel::CreatePanel(nullptr);
  suggests->SetToBoxLayout(vertical);
  palette->AddChildView(row);
  palette->AddChildView(chips);
  palette->AddChildView(suggests);

  side_overlay = window->AddOverlayView(sidebar, CEF_DOCKING_MODE_CUSTOM, true);
  palette_overlay = window->AddOverlayView(palette, CEF_DOCKING_MODE_CUSTOM, true);

  ApplyMode();
  AddTab(start_url.empty() ? "chrome://newtab/" : start_url, false);
  if (show_well) ShowPalette();
  window->CenterWindow({1280, 800});
  LayoutOverlays();
  window->Show();
  ApplyKeys();
  if (!g_polling) {
    g_polling = true;
    CefPostDelayedTask(TID_UI, new PollKeys(), 1000);
  }
}

void PollKeys::Execute() {
  std::error_code ec;
  auto stamped = fs::last_write_time(KeysPath(), ec);
  if (!ec && (!g_keys_seen || stamped != g_keys_time)) ReloadKeyMap();
  CefPostDelayedTask(TID_UI, new PollKeys(), 1000);
}

void BuildAccelTable() {
  g_accel.clear();
  LoadKeys(KeysPath());
  for (auto& action : Actions()) {
    for (auto& chord : action.chords) {
      if (!RegisterChord(chord)) continue;
      g_accel.push_back({action.name, chord});
    }
  }
  std::error_code ec;
  auto stamped = fs::last_write_time(KeysPath(), ec);
  g_keys_seen = true;
  if (!ec) g_keys_time = stamped;
}

CefRefPtr<CefRequestContext> PrivateContext(std::string* dir_out) {
  static int seq = 0;
  std::string dir = ActiveDataDir() + "/.qi-private-" + std::to_string(++seq);
  MakeDirs(dir);
  if (dir_out) *dir_out = dir;
  CefRequestContextSettings settings;
  CefString(&settings.cache_path) = dir;
  settings.persist_session_cookies = 0;
  return CefRequestContext::CreateContext(settings, nullptr);
}

}  // namespace

void OpenFreshWindow(const std::string& profile_dir, const std::string& url, bool show_toolbar, bool priv) {
  CEF_REQUIRE_UI_THREAD();
  auto shell = new Shell();
  shell->profile = profile_dir.empty() ? StartupProfile() : profile_dir;
  shell->priv = priv;
  shell->start_url = url.empty() ? "chrome://newtab/" : url;
  shell->show_well = show_toolbar;
  if (priv) shell->ctx = PrivateContext(&shell->private_dir);
  else shell->ctx = ContextFor(shell->profile);
  Shells().push_back(shell);
  CefWindow::CreateTopLevelWindow(new WindowHub(shell));
}

void OpenWindow(const std::string& profile_dir, const std::string& url, bool show_toolbar) {
  OpenFreshWindow(profile_dir, url, show_toolbar, false);
}

bool OpenAsTab(CefRefPtr<CefBrowser> opener, const std::string& url, bool background) {
  auto shell = ShellFor(opener);
  if (!shell) shell = ActiveShell();
  if (!shell) return false;
  shell->AddTab(url, background);
  return true;
}

void NoteOpened(CefRefPtr<CefBrowser> browser) {
  if (!browser) return;
  for (auto& shell : Shells()) {
    if (!shell->alive || !shell->page) continue;
    auto view = CefBrowserView::GetForBrowser(browser);
    if (view && view->IsSame(shell->page)) {
      shell->Adopt(browser);
      return;
    }
  }
}

void NotePage(CefRefPtr<CefBrowser> browser, const std::string& title, const std::string& url) {
  if (auto shell = ShellFor(browser)) shell->Note(browser, title, url);
}

void NoteLoad(CefRefPtr<CefBrowser> browser) {
  if (auto shell = ShellFor(browser)) shell->Navigated(browser);
}

bool RunAction(const std::string& name) {
  CEF_REQUIRE_UI_THREAD();
  if (name == "quit") {
    CloseAllWindows();
    return true;
  }
  auto shell = ActiveShell();
  if (!shell) {
    if (name == "close-tab" || name == "close-window" || name == "toggle-sidebar") return true;
    bool priv = name == "private-window";
    OpenFreshWindow(StartupProfile(), "chrome://newtab/", name == "focus-location", priv);
    shell = ActiveShell();
    if (!shell) return false;
    if (name == "new-tab" || name == "new-window" || name == "private-window" || name == "focus-location")
      return true;
  }
  if (name == "new-window") {
    OpenFreshWindow(shell->profile, "chrome://newtab/", false, shell->priv);
    return true;
  }
  if (name == "private-window") {
    OpenFreshWindow(shell->profile, "chrome://newtab/", false, true);
    return true;
  }
  return shell->Run(name);
}

void ReloadKeyMap() {
  BuildAccelTable();
  for (auto& shell : Shells()) {
    if (!shell->alive) continue;
    shell->ApplyKeys();
    shell->RefreshKeysPage();
  }
}

}  // namespace qi
