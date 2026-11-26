// Reads the active Omarchy theme's colors.toml, like src/theme.rs does.
#include <fstream>
#include <map>
#include <sstream>

#include "include/cef_values.h"
#include "qi.h"

namespace qi {
namespace {

bool ParseHex(std::string v, uint32_t* out) {
  auto q = v.find('#');
  if (q == std::string::npos) return false;
  v = v.substr(q + 1);
  std::string hex;
  for (char c : v) {
    if (isxdigit(static_cast<unsigned char>(c))) hex += c; else break;
  }
  if (hex.size() == 3) hex = {hex[0], hex[0], hex[1], hex[1], hex[2], hex[2]};
  if (hex.size() != 6) return false;
  *out = 0xFF000000u | static_cast<uint32_t>(std::stoul(hex, nullptr, 16));
  return true;
}

Theme Load() {
  Theme t;
  std::vector<std::string> dirs;
  if (const char* d = getenv("QI_THEME_DIR")) dirs.push_back(d);
  else if (const char* d = getenv("OMAWEB_THEME_DIR")) dirs.push_back(d);
  const char* xs = getenv("XDG_STATE_HOME");
  const char* xc = getenv("XDG_CONFIG_HOME");
  dirs.push_back((xs && *xs ? std::string(xs) : HomeDir() + "/.local/state") +
                 "/omarchy/current/theme");
  dirs.push_back((xc && *xc ? std::string(xc) : HomeDir() + "/.config") +
                 "/omarchy/current/theme");
  for (const auto& dir : dirs) {
    std::ifstream f(dir + "/colors.toml");
    if (!f) continue;
    std::map<std::string, std::string> kv;
    std::string line;
    while (std::getline(f, line)) {
      auto eq = line.find('=');
      if (eq == std::string::npos || line[0] == '#') continue;
      std::string k = line.substr(0, eq), v = line.substr(eq + 1);
      k.erase(0, k.find_first_not_of(" \t"));
      k.erase(k.find_last_not_of(" \t") + 1);
      kv[k] = v;
    }
    ParseHex(kv["background"], &t.background);
    ParseHex(kv["foreground"], &t.foreground);
    if (!ParseHex(kv["accent"], &t.accent)) ParseHex(kv["blue"], &t.accent);
    ParseHex(kv["muted"], &t.muted);
    ParseHex(kv["selection"], &t.selection);
    const std::string mode = kv["mode"];
    if (mode.find("light") != std::string::npos) {
      t.dark = false;
    } else if (mode.find("dark") == std::string::npos) {
      std::ifstream lm(dir + "/light.mode");
      t.dark = !lm.good();
    }
    std::ifstream n(dir + "/../theme.name");
    std::string name;
    if (n && std::getline(n, name) && !name.empty()) t.name = name;
    else t.name = "omarchy";
    break;
  }
  return t;
}

}  // namespace

std::string Theme::Css(uint32_t c) const {
  char buf[8];
  snprintf(buf, sizeof(buf), "#%06x", c & 0xFFFFFFu);
  return buf;
}

const Theme& CurrentTheme() {
  static Theme theme = Load();
  return theme;
}

void ApplyTheme(CefRefPtr<CefRequestContext> ctx) {
  if (!ctx) return;
  const Theme& t = CurrentTheme();
  // Mode first (light/dark), then seed Chrome's palette from the accent.
  ctx->SetChromeColorScheme(
      t.dark ? CEF_COLOR_VARIANT_DARK : CEF_COLOR_VARIANT_LIGHT, t.accent);
  ctx->SetChromeColorScheme(CEF_COLOR_VARIANT_TONAL_SPOT, t.accent);
  // Chrome style turns "Load unpacked" extensions off while the profile's
  // developer mode is off, and records that in the profile, so Chromium
  // would find them off too. Developer mode on keeps them as Chromium has
  // them (Chromium shows the same toggle on chrome://extensions).
  if (ctx->CanSetPreference("extensions.ui.developer_mode")) {
    CefString error;
    auto on = CefValue::Create();
    on->SetBool(true);
    ctx->SetPreference("extensions.ui.developer_mode", on, error);
  }
}

}  // namespace qi
