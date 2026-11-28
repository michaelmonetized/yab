#pragma once
// What QML can't reach on a web engine profile: the request interceptor
// (the ad and tracker blocker) and the cookie store (Chrome import).

#include <QtCore/QHash>
#include <QtCore/QMutex>
#include <QtCore/QObject>
#include <QtCore/QSet>
#include <QtCore/QString>
#include <QtCore/QStringList>
#include <QtWebEngineCore/QWebEngineUrlRequestInterceptor>

namespace qi {

class BlockInterceptor : public QWebEngineUrlRequestInterceptor
{
public:
    using QWebEngineUrlRequestInterceptor::QWebEngineUrlRequestInterceptor;
    void interceptRequest(QWebEngineUrlRequestInfo& info) override;
};

class WebTools : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int blockedTotal READ blockedTotal NOTIFY blockedChanged)
    Q_PROPERTY(int listSize READ listSize NOTIFY listChanged)
public:
    static WebTools* instance();

    // Remembers the profile under `name` and puts the blocker on it.
    Q_INVOKABLE void attachProfile(QObject* profile, const QString& name);
    // Reads the compiled list (a host per line, "@@host" allowed).
    Q_INVOKABLE int loadBlocklist(const QString& path);
    Q_INVOKABLE void setBlocking(bool enabled, const QStringList& allowSites);
    Q_INVOKABLE int blockedOn(const QString& firstPartyHost) const;
    Q_INVOKABLE void resetCount(const QString& firstPartyHost);
    // Clears a profile's cookies (settings: "Clear cookies").
    Q_INVOKABLE void clearCookies(const QString& name);

    int blockedTotal() const;
    int listSize() const;

    // The interceptor's question, on any thread.
    bool shouldBlock(const QString& host, const QString& firstPartyHost);
    void addCookie(const QString& profile, const QString& name, const QString& value, const QString& domain,
                   const QString& path, qint64 expires, bool secure, bool httpOnly, int sameSite);

Q_SIGNALS:
    void blockedChanged();
    void listChanged();
    void blocked(const QString& firstPartyHost, int count);

private:
    explicit WebTools(QObject* parent = nullptr);
    mutable QMutex m_mutex;
    QSet<QString> m_block;
    QSet<QString> m_allow;
    QSet<QString> m_allowSites;
    bool m_enabled = true;
    QHash<QString, int> m_counts;
    int m_total = 0;
    QHash<QString, QObject*> m_profiles;
    BlockInterceptor* m_interceptor = nullptr;
};

} // namespace qi
