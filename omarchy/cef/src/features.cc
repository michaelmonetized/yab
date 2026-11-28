#include "features.h"

#include <sstream>
#include <vector>

namespace qi {
namespace {

std::string TrimToken(std::string s) {
  while (!s.empty() && (s.front() == ' ' || s.front() == '\t')) s.erase(s.begin());
  while (!s.empty() && (s.back() == ' ' || s.back() == '\t')) s.pop_back();
  return s;
}

bool HasToken(const std::string& list, const std::string& name) {
  std::string cur;
  std::istringstream in(list);
  while (std::getline(in, cur, ',')) {
    if (TrimToken(cur) == name) return true;
  }
  return false;
}

}  // namespace

std::string WithOverlayScrollbars(const std::string& existing) {
  static const char* kNames[] = {
      "OverlayScrollbar",
      "OverlayScrollbarFlashAfterAnyScrollUpdate",
      "OverlayScrollbarFlashWhenMouseEnter",
  };
  std::string out = existing;
  for (const char* name : kNames) {
    if (HasToken(out, name)) continue;
    if (!out.empty()) out.push_back(',');
    out += name;
  }
  return out;
}

}  // namespace qi
