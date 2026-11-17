#include "webtools.h"

#include <QtCore/QDateTime>
#include <QtCore/QFile>
#include <QtCore/QMetaObject>
#include <QtCore/QTextStream>
#include <QtCore/QUrl>
#include <QtNetwork/QNetworkCookie>
#include <QtWebEngineCore/QWebEngineCookieStore>
#include <QtWebEngineCore/QWebEngineUrlRequestInfo>
#include <QtWebEngineQuick/QQuickWebEngineProfile>

namespace omaweb {

static bool hostListed(const QSet<QString>& set, QStringView host)
{
    // host and each parent with at least one dot: a.b.example.com,
    // b.example.com, example.com
    while (true) {
        if (set.contains(host.toString()))
            return true;
        const auto dot = host.indexOf(u'.');
        if (dot < 0)
            return false;
        const auto rest = host.mid(dot + 1);
        if (!rest.contains(u'.'))
            return false;
        host = rest;
    }
}

void BlockInterceptor::interceptRequest(QWebEngineUrlRequestInfo& info)
{
    // Never the page itself: only what it pulls in.
    if (info.resourceType() == QWebEngineUrlRequestInfo::ResourceTypeMainFrame)
        return;
    const QString scheme = info.requestUrl().scheme();
    if (scheme != QLatin1String("http") && scheme != QLatin1String("https") && scheme != QLatin1String("ws")
        && scheme != QLatin1String("wss"))
        return;
    const QString host = info.requestUrl().host().toLower();
    const QString first = info.firstPartyUrl().host().toLower();
    if (WebTools::instance()->shouldBlock(host, first))
        info.block(true);
}

WebTools* WebTools::instance()
{
    static WebTools* self = new WebTools();
    return self;
}

WebTools::WebTools(QObject* parent) : QObject(parent), m_interceptor(new BlockInterceptor(this)) {}

void WebTools::attachProfile(QObject* profile, const QString& name)
{
    auto* p = qobject_cast<QQuickWebEngineProfile*>(profile);
    if (!p)
        return;
    {
        QMutexLocker lock(&m_mutex);
        m_profiles.insert(name, p);
    }
    p->setUrlRequestInterceptor(m_interceptor);
    connect(p, &QObject::destroyed, this, [this, name]() {
        QMutexLocker lock(&m_mutex);
        m_profiles.remove(name);
    });
}

int WebTools::loadBlocklist(const QString& path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return listSize();
    QSet<QString> block, allow;
    QTextStream in(&f);
    QString line;
    while (in.readLineInto(&line)) {
        if (line.isEmpty())
            continue;
        if (line.startsWith(QLatin1String("@@")))
            allow.insert(line.mid(2));
        else
            block.insert(line);
    }
    {
        QMutexLocker lock(&m_mutex);
        m_block = std::move(block);
        m_allow = std::move(allow);
    }
    Q_EMIT listChanged();
    return listSize();
}

void WebTools::setBlocking(bool enabled, const QStringList& allowSites)
{
    QMutexLocker lock(&m_mutex);
    m_enabled = enabled;
    m_allowSites.clear();
    for (const auto& s : allowSites)
        m_allowSites.insert(s.toLower().remove(QLatin1String("www.")));
}

bool WebTools::shouldBlock(const QString& host, const QString& firstPartyHost)
{
    int count = 0;
    {
        QMutexLocker lock(&m_mutex);
        if (!m_enabled || host.isEmpty())
            return false;
        QString site = firstPartyHost;
        if (site.startsWith(QLatin1String("www.")))
            site = site.mid(4);
        if (!site.isEmpty() && hostListed(m_allowSites, site))
            return false;
        if (hostListed(m_allow, host) || !hostListed(m_block, host))
            return false;
        count = ++m_counts[firstPartyHost];
        ++m_total;
    }
    QMetaObject::invokeMethod(this, [this, firstPartyHost, count]() {
        Q_EMIT blocked(firstPartyHost, count);
        Q_EMIT blockedChanged();
    }, Qt::QueuedConnection);
    return true;
}

int WebTools::blockedOn(const QString& firstPartyHost) const
{
    QMutexLocker lock(&m_mutex);
    return m_counts.value(firstPartyHost.toLower());
}

void WebTools::resetCount(const QString& firstPartyHost)
{
    QMutexLocker lock(&m_mutex);
    m_counts.remove(firstPartyHost.toLower());
}

int WebTools::blockedTotal() const
{
    QMutexLocker lock(&m_mutex);
    return m_total;
}

int WebTools::listSize() const
{
    QMutexLocker lock(&m_mutex);
    return m_block.size();
}

void WebTools::clearCookies(const QString& name)
{
    QMutexLocker lock(&m_mutex);
    if (auto* p = qobject_cast<QQuickWebEngineProfile*>(m_profiles.value(name)))
        p->cookieStore()->deleteAllCookies();
}

void WebTools::addCookie(const QString& profile, const QString& name, const QString& value, const QString& domain,
                         const QString& path, qint64 expires, bool secure, bool httpOnly, int sameSite)
{
    QQuickWebEngineProfile* p = nullptr;
    {
        QMutexLocker lock(&m_mutex);
        p = qobject_cast<QQuickWebEngineProfile*>(m_profiles.value(profile));
    }
    if (!p)
        return;
    QNetworkCookie c(name.toUtf8(), value.toUtf8());
    c.setDomain(domain);
    c.setPath(path.isEmpty() ? QStringLiteral("/") : path);
    if (expires > 0)
        c.setExpirationDate(QDateTime::fromSecsSinceEpoch(expires));
    c.setSecure(secure);
    c.setHttpOnly(httpOnly);
    switch (sameSite) {
    case 0: c.setSameSitePolicy(QNetworkCookie::SameSite::None); break;
    case 1: c.setSameSitePolicy(QNetworkCookie::SameSite::Lax); break;
    case 2: c.setSameSitePolicy(QNetworkCookie::SameSite::Strict); break;
    default: break;
    }
    QString host = domain.startsWith(u'.') ? domain.mid(1) : domain;
    QUrl origin(QStringLiteral("%1://%2/").arg(secure ? QStringLiteral("https") : QStringLiteral("http"), host));
    p->cookieStore()->setCookie(c, origin);
}

} // namespace omaweb
