// Feature-flag merge for Qi's own command line.
//
// Chromium crashes if --disable-features is passed twice. Names are
// appended to the single comma list, once each.
#pragma once

#include <string>

namespace qi {

// Adds OverlayScrollbar (and the flash companions) to a comma-separated
// enable-features value. A name already present is left alone.
std::string WithOverlayScrollbars(const std::string& existing);

}  // namespace qi
