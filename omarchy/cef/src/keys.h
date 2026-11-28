// Qi's keyboard map.
//
// Defaults live in the binary. ~/.config/qi/keys.toml lists overrides
// only. Super chords are recorded here and installed by the Hyprland
// snippet. CEF accelerators have no Super flag, so they are not registered
// in the window.
#pragma once

#include <string>
#include <vector>

namespace qi {

struct Chord {
  bool ctrl = false;
  bool shift = false;
  bool alt = false;
  bool super = false;
  int key = 0;  // Windows virtual-key: 'A', VK_F1, or a digit
  std::string text;  // "Ctrl+T"
  bool operator==(const Chord& o) const {
    return ctrl == o.ctrl && shift == o.shift && alt == o.alt && super == o.super &&
           key == o.key;
  }
};

struct Action {
  std::string name;
  std::string title;
  bool high = false;
  std::vector<Chord> chords;
};

// Loads defaults, then overrides from path. A missing file keeps defaults.
// Pass "" to skip the file.
void LoadKeys(const std::string& path);
const std::vector<Action>& Actions();
const Action* FindAction(const std::string& name);
// Writes one override. An empty chord removes the override.
bool SetKeyOverride(const std::string& path, const std::string& action, const std::string& chord);
std::string KeysPath();
// "chord -> a, b" for non-super chords claimed by two actions.
std::vector<std::string> ChordConflicts();
bool ParseChord(const std::string& text, Chord* out);

}  // namespace qi
