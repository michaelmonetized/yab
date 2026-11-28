#include "platform.h"
#include "webtools.h"

#include <QtCore/QCoreApplication>
#include <QtGui/QGuiApplication>
#include <QtGui/QStyleHints>
#include <QtQml/qqml.h>
#include <QtWebEngineQuick/QtWebEngineQuick>

namespace qi {

void init_webengine()
{
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    QtWebEngineQuick::initialize();
    qmlRegisterSingletonInstance("app.qi.native", 1, 0, "WebTools", WebTools::instance());
}

void add_cookie(const QString& profile, const QString& name, const QString& value, const QString& domain,
                const QString& path, std::int64_t expires, bool secure, bool http_only, std::int32_t same_site)
{
    WebTools::instance()->addCookie(profile, name, value, domain, path, expires, secure, http_only, same_site);
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

} // namespace qi
