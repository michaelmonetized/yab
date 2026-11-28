#include "keys.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <map>
#include <sstream>

namespace qi {
namespace {

std::vector<Action> g_actions;

std::string Home() {
  const char* h = getenv("HOME");
  return h ? h : "";
}

int CodeKey(int code) {
  if (code >= 10 && code <= 18) return '1' + (code - 10);
  if (code == 20) return '-';
  if (code == 21) return '=';
  if (code == 34) return '[';
  if (code == 35) return ']';
  return 0;
}

std::string Trim(std::string s) {
  while (!s.empty() && std::isspace(static_cast<unsigned char>(s.front()))) s.erase(s.begin());
  while (!s.empty() && std::isspace(static_cast<unsigned char>(s.back()))) s.pop_back();
  return s;
}

void Add(const char* name, const char* title, bool high, std::initializer_list<const char*> chords) {
  Action a;
  a.name = name;
  a.title = title;
  a.high = high;
  for (const char* c : chords) {
    Chord chord;
    if (ParseChord(c, &chord)) a.chords.push_back(chord);
  }
  g_actions.push_back(std::move(a));
}

void Defaults() {
  g_actions.clear();
  Add("focus-location", "Address bar", true, {"Ctrl+L", "Alt+D", "F6", "Super+L"});
  Add("find-in-page", "Find", true, {"Ctrl+F", "Super+F"});
  Add("find-next", "Find next", false, {"Ctrl+G", "Super+J"});
  Add("find-previous", "Find previous", false, {"Ctrl+Shift+G", "Super+K"});
  Add("new-tab", "New tab", true, {"Ctrl+T", "Super+T"});
  Add("close-tab", "Close tab", true, {"Ctrl+W", "Super+W"});
  Add("restore-tab", "Reopen tab", true, {"Ctrl+Shift+T", "Super+Shift+T"});
  Add("reload", "Reload", false, {"Ctrl+R", "Super+R"});
  Add("reload-no-cache", "Reload without cache", false, {"Ctrl+Shift+R", "Super+Shift+R"});
  Add("new-window", "New window", true, {"Ctrl+N", "Super+N"});
  Add("private-window", "Private window", true, {"Super+Shift+N"});
  Add("close-window", "Close window", true, {"Super+Shift+W"});
  Add("pin-tab", "Pin tab", true, {"Super+Shift+D"});
  Add("mute-tab", "Mute tab", true, {"Super+M"});
  Add("duplicate-tab", "Duplicate tab", true, {"Ctrl+D"});
  Add("bookmark", "Pin favorite", true, {"Super+D"});
  Add("history", "History", true, {"Super+H", "Super+Alt+H"});
  Add("copy-url", "Copy URL", true, {"Super+Shift+C"});
  Add("copy-url-markdown", "Copy URL as Markdown", true, {"Super+Alt+Shift+C"});
  Add("back", "Back", false, {"Alt+Left", "Super+["});
  Add("forward", "Forward", false, {"Alt+Right", "Super+]"});
  Add("zoom-in", "Zoom in", false, {"Ctrl+Plus", "Ctrl+Equal", "Super+="});
  Add("zoom-out", "Zoom out", false, {"Ctrl+Minus", "Super+-"});
  Add("zoom-reset", "Zoom reset", false, {"Ctrl+0", "Super+Alt+Shift+0"});
  Add("previous-tab", "Previous tab", true, {"Super+Alt+Up", "Ctrl+Shift+Tab", "Ctrl+PageUp"});
  Add("next-tab", "Next tab", true, {"Super+Alt+Down", "Ctrl+Tab", "Ctrl+PageDown"});
  Add("tab-1", "Tab 1", true, {"Super+1", "Alt+1"});
  Add("tab-2", "Tab 2", true, {"Super+2", "Alt+2"});
  Add("tab-3", "Tab 3", true, {"Super+3", "Alt+3"});
  Add("tab-4", "Tab 4", true, {"Super+4", "Alt+4"});
  Add("tab-5", "Tab 5", true, {"Super+5", "Alt+5"});
  Add("tab-6", "Tab 6", true, {"Super+6", "Alt+6"});
  Add("tab-7", "Tab 7", true, {"Super+7", "Alt+7"});
  Add("tab-8", "Tab 8", true, {"Super+8", "Alt+8"});
  Add("tab-9", "Last tab", true, {"Super+9", "Alt+9"});
  Add("toggle-sidebar", "Sidebar", true, {"Ctrl+Shift+B", "Ctrl+Shift+L"});
  Add("show-extension-toolbar", "Extension toolbar", true, {"Ctrl+Shift+U"});
  Add("downloads", "Downloads", true, {"Ctrl+J", "Super+Shift+E"});
  Add("view-source", "View source", false, {"Ctrl+U", "Super+Alt+J"});
  Add("devtools", "Developer tools", true, {"Ctrl+Shift+I", "Super+Shift+I"});
  Add("print", "Print", false, {"Ctrl+P", "Super+P"});
  Add("save-page", "Save page", false, {"Ctrl+S", "Super+S"});
  Add("profile-picker", "Profiles", true, {"Ctrl+Shift+M"});
  Add("extensions", "Extensions", true, {"Ctrl+Shift+X"});
  Add("quit", "Quit", true, {"Ctrl+Q"});
  Add("settings-keys", "Keyboard", true, {"Ctrl+Shift+Comma"});
  Add("space-1", "Space 1", true, {"Ctrl+Alt+1"});
  Add("space-2", "Space 2", true, {"Ctrl+Alt+2"});
  Add("space-3", "Space 3", true, {"Ctrl+Alt+3"});
  Add("space-4", "Space 4", true, {"Ctrl+Alt+4"});
  Add("space-5", "Space 5", true, {"Ctrl+Alt+5"});
  Add("space-6", "Space 6", true, {"Ctrl+Alt+6"});
  Add("space-7", "Space 7", true, {"Ctrl+Alt+7"});
  Add("space-8", "Space 8", true, {"Ctrl+Alt+8"});
  Add("space-9", "Space 9", true, {"Ctrl+Alt+9"});
}

std::vector<std::string> Quoted(const std::string& value) {
  std::vector<std::string> out;
  std::string cur;
  bool in = false;
  for (char c : value) {
    if (c == '"') {
      if (in) out.push_back(cur);
      cur.clear();
      in = !in;
      continue;
    }
    if (in) cur.push_back(c);
  }
  return out;
}

void ApplyOverride(const std::string& name, const std::vector<std::string>& chords) {
  Action* action = nullptr;
  for (auto& a : g_actions)
    if (a.name == name) action = &a;
  if (!action) return;
  action->chords.clear();
  for (auto& text : chords) {
    Chord chord;
    if (ParseChord(text, &chord)) action->chords.push_back(chord);
  }
}

void ReadOverrides(const std::string& path) {
  std::ifstream in(path);
  if (!in) return;
  bool keys = false;
  std::string line;
  while (std::getline(in, line)) {
    auto hash = line.find('#');
    if (hash != std::string::npos) line.resize(hash);
    line = Trim(line);
    if (line.empty()) continue;
    if (line.front() == '[') {
      keys = line == "[keys]";
      continue;
    }
    if (!keys) continue;
    auto eq = line.find('=');
    if (eq == std::string::npos) continue;
    ApplyOverride(Trim(line.substr(0, eq)), Quoted(line.substr(eq + 1)));
  }
}

}  // namespace

bool ParseChord(const std::string& text, Chord* out) {
  if (!out) return false;
  Chord chord;
  chord.text = text;
  std::string token;
  auto take = [&](const std::string& part) {
    std::string p = part;
    for (char& c : p) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    if (p == "ctrl" || p == "control") chord.ctrl = true;
    else if (p == "shift") chord.shift = true;
    else if (p == "alt") chord.alt = true;
    else if (p == "super" || p == "meta") chord.super = true;
    else if (p.rfind("code:", 0) == 0) chord.key = CodeKey(std::atoi(p.c_str() + 5));
    else if (p == "left") chord.key = 0x25;
    else if (p == "up") chord.key = 0x26;
    else if (p == "right") chord.key = 0x27;
    else if (p == "down") chord.key = 0x28;
    else if (p == "tab") chord.key = 0x09;
    else if (p == "pageup") chord.key = 0x21;
    else if (p == "pagedown") chord.key = 0x22;
    else if (p == "f6") chord.key = 0x75;
    else if (p == "comma") chord.key = ',';
    else if (p == "plus") chord.key = '+';
    else if (p == "equal") chord.key = '=';
    else if (p == "minus") chord.key = '-';
    else if (p.size() == 1) chord.key = std::toupper(static_cast<unsigned char>(p[0]));
    else return false;
    return true;
  };
  std::stringstream ss(text);
  std::string part;
  while (std::getline(ss, part, '+')) {
    if (!take(Trim(part))) return false;
  }
  if (!chord.key) return false;
  *out = chord;
  return true;
}

void LoadKeys(const std::string& path) {
  Defaults();
  if (!path.empty()) ReadOverrides(path);
}

const std::vector<Action>& Actions() {
  if (g_actions.empty()) Defaults();
  return g_actions;
}

const Action* FindAction(const std::string& name) {
  for (auto& a : Actions())
    if (a.name == name) return &a;
  return nullptr;
}

std::string KeysPath() {
  const char* cfg = getenv("XDG_CONFIG_HOME");
  if (cfg && *cfg) return std::string(cfg) + "/qi/keys.toml";
  return Home() + "/.config/qi/keys.toml";
}

bool SetKeyOverride(const std::string& path, const std::string& action, const std::string& chord) {
  if (!FindAction(action)) return false;
  if (!chord.empty()) {
    Chord parsed;
    if (!ParseChord(chord, &parsed)) return false;
  }
  std::ifstream in(path);
  std::vector<std::string> lines;
  std::string line;
  bool keys = false;
  bool replaced = false;
  bool saw_table = false;
  while (std::getline(in, line)) {
    std::string raw = line;
    std::string body = raw;
    auto hash = body.find('#');
    if (hash != std::string::npos) body.resize(hash);
    std::string trimmed = Trim(body);
    if (!trimmed.empty() && trimmed.front() == '[') {
      keys = trimmed == "[keys]";
      if (keys) saw_table = true;
    } else if (keys) {
      auto eq = trimmed.find('=');
      if (eq != std::string::npos && Trim(trimmed.substr(0, eq)) == action) {
        replaced = true;
        if (chord.empty()) continue;
        raw = action + " = [\"" + chord + "\"]";
      }
    }
    lines.push_back(raw);
  }
  if (!replaced && !chord.empty()) {
    if (!saw_table) lines.push_back("[keys]");
    lines.push_back(action + " = [\"" + chord + "\"]");
  }
  std::error_code ec;
  auto slash = path.find_last_of('/');
  if (slash != std::string::npos)
    std::filesystem::create_directories(path.substr(0, slash), ec);
  if (ec) return false;
  std::ofstream out(path, std::ios::trunc);
  for (auto& l : lines) out << l << '\n';
  out.flush();
  return static_cast<bool>(out);
}

std::vector<std::string> ChordConflicts() {
  std::map<std::string, std::vector<std::string>> who;
  for (auto& a : Actions()) {
    for (auto& c : a.chords) {
      if (c.super) continue;
      who[c.text].push_back(a.name);
    }
  }
  std::vector<std::string> out;
  for (auto& [chord, names] : who) {
    if (names.size() < 2) continue;
    std::string line = chord + " -> " + names[0];
    for (size_t i = 1; i < names.size(); ++i) line += ", " + names[i];
    out.push_back(line);
  }
  return out;
}

}  // namespace qi
