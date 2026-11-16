#pragma once
// Small C++ shims for Qt calls cxx-qt-lib does not wrap: Qt WebEngine has to
// be initialised before the QGuiApplication exists, and the Wayland app_id
// and colour-scheme hint live on QGuiApplication statics.
#include <QtCore/QString>

namespace omaweb {
void init_webengine();
void set_desktop_file_name(const QString& name);
void set_color_scheme(bool dark);
}
