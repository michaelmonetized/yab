// One tab: a WebEngineView plus the bits of state the chrome shows.
// Restored tabs are lazy: nothing loads until the tab is first shown.
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtWebEngine

Item {
    id: tab
    // Full width, or one half of a split.
    property int splitSide: 0          // 0 alone, 1 left, 2 right
    property real splitRatio: 0.5
    x: splitSide === 2 ? Math.round(parent.width * splitRatio) + 1 : 0
    y: 0
    width: splitSide === 0 ? parent.width : (splitSide === 1 ? Math.round(parent.width * splitRatio) : parent.width - Math.round(parent.width * splitRatio) - 1)
    height: parent.height
    visible: active || splitSide !== 0

    property QtObject pal
    property QtObject browser
    property alias profile: view.profile
    property string uid: ""
    property string profileName: "Default"
    property bool isPrivate: false
    property bool active: false
    property real zoom: 1.0
    property bool forceDark: false
    property string token: ""          // secret prefix for our own console messages
    property alias view: view

    // Lazy restore.
    property string lazyUrl: ""
    property string lazyTitle: ""
    property bool started: false
    function wake() {
        if (started) return
        started = true
        if (lazyUrl.length) view.url = lazyUrl
    }
    onActiveChanged: if (active) wake()
    onSplitSideChanged: if (splitSide !== 0) wake()

    readonly property url url: started ? view.url : lazyUrl
    readonly property string host: { const m = url.toString().match(/^[a-z-]+:\/\/([^\/?#:]+)/i); return m ? m[1].toLowerCase() : "" }
    readonly property string title: view.title.length ? view.title : (lazyTitle.length && !started ? lazyTitle : (blank ? (isPrivate ? "Private tab" : "New tab") : url.toString()))
    readonly property url icon: view.icon
    readonly property bool loading: view.loading
    readonly property int progress: view.loadProgress
    readonly property bool canGoBack: view.canGoBack
    readonly property bool canGoForward: view.canGoForward
    readonly property bool blank: !url.toString().length || url.toString() === "about:blank"
    property string hoveredLink: ""
    property bool audible: view.recentlyAudible
    property int blockedCount: 0

    signal newTabRequested(var request)
    signal closeRequested()
    signal fullScreenChanged(bool on)
    signal changed()
    signal liveChanged()
    signal pageLoaded()
    signal pageMessage(string kind, string payload)

    function load(u) { started = true; lazyUrl = u; view.url = u }
    function zoomBy(d) { zoom = Math.max(0.25, Math.min(5.0, Math.round((zoom + d) * 10) / 10)) }
    function toggleDevTools() { devtools.visible = !devtools.visible }
    onLoadingChanged: liveChanged()
    onIconChanged: liveChanged()
    onAudibleChanged: liveChanged()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Permission prompt: camera, mic, location, notifications, ...
        Rectangle {
            id: permBar
            property var pending: null
            visible: pending !== null
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            color: tab.pal.bgLighter
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 6
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: tab.pal.fg
                    font.family: tab.pal.font
                    font.pixelSize: tab.pal.fontSize
                    text: permBar.pending ? permBar.pending.origin.toString() + " wants " + tab.permissionName(permBar.pending.permissionType) : ""
                }
                BarButton { label: "Allow"; primary: true; onClicked: { permBar.pending.grant(); permBar.pending = null } }
                BarButton { label: "Deny"; onClicked: { permBar.pending.deny(); permBar.pending = null } }
            }
        }

        WebEngineView {
            id: view
            Layout.fillWidth: true
            Layout.fillHeight: true
            focus: true
            backgroundColor: tab.pal.bg
            zoomFactor: tab.zoom
            settings.fullScreenSupportEnabled: true
            settings.focusOnNavigationEnabled: true
            settings.scrollAnimatorEnabled: true
            settings.playbackRequiresUserGesture: true
            settings.dnsPrefetchEnabled: false
            settings.forceDarkMode: tab.forceDark
            settings.javascriptCanAccessClipboard: false

            onNewWindowRequested: request => tab.newTabRequested(request)
            onJavaScriptConsoleMessage: (level, message, line, source) => {
                if (!tab.token.length || !message.startsWith(tab.token)) return
                const rest = message.slice(tab.token.length)
                const i = rest.indexOf(":")
                if (i > 0) tab.pageMessage(rest.slice(0, i), rest.slice(i + 1))
            }
            onWindowCloseRequested: tab.closeRequested()
            onLinkHovered: hoveredUrl => tab.hoveredLink = hoveredUrl.toString()
            onFullScreenRequested: request => { request.accept(); tab.fullScreenChanged(request.toggleOn) }
            onPermissionRequested: permission => permBar.pending = permission
            onUrlChanged: { tab.blockedCount = 0; tab.changed() }
            onTitleChanged: {
                if (!tab.isPrivate && title.length) tab.browser.retitle(tab.profileName, url.toString(), title)
                tab.changed()
            }
            onLoadingChanged: info => {
                if (info.status === WebEngineView.LoadSucceededStatus) {
                    if (!tab.isPrivate) tab.browser.recordVisit(tab.profileName, info.url.toString(), view.title)
                    tab.pageLoaded()
                }
            }
            onRenderProcessTerminated: (status, code) => {
                if (status !== WebEngineView.NormalTerminationStatus) reloadTimer.start()
            }
            Timer { id: reloadTimer; interval: 300; onTriggered: view.reload() }
        }

        Rectangle {
            visible: devtools.visible
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: tab.pal.muted
        }
        WebEngineView {
            id: devtools
            visible: false
            Layout.fillWidth: true
            Layout.preferredHeight: tab.height * 0.4
            inspectedView: visible ? view : null
            backgroundColor: tab.pal.bg
        }
    }

    function permissionName(t) {
        switch (t) {
        case WebEnginePermission.PermissionType.MediaAudioCapture: return "your microphone"
        case WebEnginePermission.PermissionType.MediaVideoCapture: return "your camera"
        case WebEnginePermission.PermissionType.MediaAudioVideoCapture: return "your camera and microphone"
        case WebEnginePermission.PermissionType.DesktopVideoCapture:
        case WebEnginePermission.PermissionType.DesktopAudioVideoCapture: return "to share your screen"
        case WebEnginePermission.PermissionType.Geolocation: return "your location"
        case WebEnginePermission.PermissionType.Notifications: return "to show notifications"
        case WebEnginePermission.PermissionType.ClipboardReadWrite: return "your clipboard"
        case WebEnginePermission.PermissionType.MouseLock: return "to lock the pointer"
        default: return "a permission"
        }
    }

    component BarButton: AbstractButton {
        id: bb
        property string label
        property bool primary: false
        focusPolicy: Qt.NoFocus
        hoverEnabled: true
        implicitWidth: lbl.implicitWidth + 20
        implicitHeight: 24
        background: Rectangle {
            color: bb.primary ? tab.pal.accent : (bb.hovered ? tab.pal.bg : "transparent")
            border.color: tab.pal.muted
            border.width: bb.primary ? 0 : 1
        }
        contentItem: Text {
            id: lbl
            text: bb.label
            color: bb.primary ? tab.pal.onAccent : tab.pal.fg
            font.family: tab.pal.font
            font.pixelSize: tab.pal.fontSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
