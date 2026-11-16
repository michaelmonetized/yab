#include "platform.h"

#include <QtCore/QCoreApplication>
#include <QtGui/QGuiApplication>
#include <QtGui/QStyleHints>
#include <QtWebEngineQuick/QtWebEngineQuick>

namespace omaweb {

void init_webengine()
{
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    QtWebEngineQuick::initialize();
}

void set_desktop_file_name(const QString& name)
{
    // On Wayland this becomes the xdg-shell app_id Hyprland matches with
    // `class:` rules.
    QGuiApplication::setDesktopFileName(name);
}

void set_color_scheme(bool dark)
{
#if QT_VERSION >= QT_VERSION_CHECK(6, 8, 0)
    if (auto* hints = QGuiApplication::styleHints()) {
        hints->setColorScheme(dark ? Qt::ColorScheme::Dark : Qt::ColorScheme::Light);
    }
#else
    (void)dark;
#endif
}

} // namespace omaweb
