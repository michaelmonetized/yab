// Checks the key map and the scrollbar feature merge. No CEF, no profile.
#include <cstdlib>
#include <iostream>
#include <string>

#include "features.h"
#include "keys.h"

namespace {

int fails = 0;

void Expect(bool ok, const std::string& what) {
  if (ok) return;
  std::cerr << "fail: " << what << "\n";
  ++fails;
}

}  // namespace

int main() {
  qi::LoadKeys("");
  const char* want[] = {
      "focus-location", "find-in-page", "find-next", "find-previous", "new-tab",
      "close-tab",      "restore-tab",  "reload",    "reload-no-cache", "new-window",
      "private-window", "close-window", "pin-tab",   "mute-tab",        "duplicate-tab",
      "bookmark",       "history",      "copy-url",  "copy-url-markdown", "back",
      "forward",        "zoom-in",      "zoom-out",  "zoom-reset",      "previous-tab",
      "next-tab",       "tab-1",        "tab-9",     "toggle-sidebar",  "show-extension-toolbar",
      "downloads",      "view-source",  "devtools",  "print",           "save-page",
      "profile-picker", "extensions",   "quit",      "settings-keys",
  };
  for (const char* name : want) Expect(qi::FindAction(name) != nullptr, name);

  qi::Chord chord;
  Expect(qi::ParseChord("code:34", &chord) && chord.key == '[', "code 34 is [");
  Expect(qi::ParseChord("code:35", &chord) && chord.key == ']', "code 35 is ]");
  Expect(qi::ParseChord("code:20", &chord) && chord.key == '-', "code 20 is minus");
  Expect(qi::ParseChord("code:21", &chord) && chord.key == '=', "code 21 is equal");
  Expect(qi::ParseChord("code:10", &chord) && chord.key == '1', "code 10 is 1");
  Expect(qi::ParseChord("Super+T", &chord) && chord.super && !chord.ctrl && chord.key == 'T',
         "super t");
  Expect(qi::FindAction("duplicate-tab")->chords[0].text == "Ctrl+D", "ctrl d duplicates");
  Expect(qi::FindAction("bookmark")->chords[0].super, "super d bookmarks");
  Expect(qi::ChordConflicts().empty(), "default chords clash");

  const std::string path = "qi-keys-check.toml";
  Expect(qi::SetKeyOverride(path, "focus-location", "Ctrl+Shift+L"), "write override");
  qi::LoadKeys(path);
  bool found = false;
  for (auto& c : qi::FindAction("focus-location")->chords)
    found = found || c.text == "Ctrl+Shift+L";
  Expect(found && qi::FindAction("focus-location")->chords.size() == 1, "override replaces");
  Expect(qi::FindAction("new-tab")->chords.size() == 2, "unlisted action keeps defaults");
  qi::LoadKeys("");
  Expect(!qi::SetKeyOverride(path, "not-an-action", "Ctrl+K"), "unknown action rejected");
  std::remove(path.c_str());

  Expect(qi::WithOverlayScrollbars("") ==
             "OverlayScrollbar,OverlayScrollbarFlashAfterAnyScrollUpdate,"
             "OverlayScrollbarFlashWhenMouseEnter",
         "empty list gains the overlay names");
  Expect(qi::WithOverlayScrollbars("OverlayScrollbar,TouchpadOverscrollHistoryNavigation") ==
             "OverlayScrollbar,TouchpadOverscrollHistoryNavigation,"
             "OverlayScrollbarFlashAfterAnyScrollUpdate,OverlayScrollbarFlashWhenMouseEnter",
         "an existing name is not repeated");
  if (fails) {
    std::cerr << fails << " failed\n";
    return 1;
  }
  std::cout << "qi-check ok\n";
  return 0;
}
