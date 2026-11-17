#pragma once

#include <QtCore/QString>
#include <cstdint>

namespace omaweb {

void init_webengine();
void set_desktop_file_name(const QString& name);
void set_color_scheme(bool dark);
// Chrome import: one cookie into the named profile's cookie store.
void add_cookie(const QString& profile, const QString& name, const QString& value, const QString& domain,
                const QString& path, std::int64_t expires, bool secure, bool http_only, std::int32_t same_site);

} // namespace omaweb
