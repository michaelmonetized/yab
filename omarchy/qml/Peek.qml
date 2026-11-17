// Peek: links that ask for a new window (and Shift+click) open in a card
// over the page instead of a new tab. Open it as a tab, split with it, or
// press Esc. Reading mode uses the same card.
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtWebEngine

Item {
    id: peek
    property QtObject pal
    property var host
    visible: false
    property var view: null
    property string profileName: "Default"
    property bool isPrivate: false
    property bool htmlMode: false
    property url sourceUrl: ""
    property string heading: ""

    Component {
        id: viewComp
        WebEngineView {
            anchors.fill: parent
            onNewWindowRequested: request => { const t = peek.host.newTab("", true, peek.isPrivate); if (t) request.openIn(t.view); peek.close() }
            onWindowCloseRequested: peek.close()
        }
    }
    function make(profile) {
        if (view) view.destroy()
        view = viewComp.createObject(frame, { profile: profile })
    }
    function openRequest(request, profile, priv, name) {
        make(profile)
        profileName = name
        isPrivate = priv
        htmlMode = false
        heading = ""
        request.openIn(view)
        visible = true
    }
    function openHtml(html, baseUrl, profile, title) {
        make(profile)
        htmlMode = true
        sourceUrl = baseUrl
        heading = title
        view.loadHtml(html, baseUrl)
        visible = true
    }
    function close() {
        visible = false
        if (view) { view.destroy(); view = null }
        if (host.currentTab) host.currentTab.view.forceActiveFocus()
    }
    function currentUrl() { return htmlMode ? sourceUrl.toString() : (view ? view.url.toString() : "") }
    function openAsTab(split) {
        const u = currentUrl()
        if (htmlMode && !split) { close(); return }
        const before = host.currentUid
        const t = host.newTab(u, !split, isPrivate, before)
        if (split && t) host.splitWith(t.uid)
        close()
    }

    Shortcut { sequences: ["Escape"]; enabled: peek.visible; onActivated: peek.close() }

    Rectangle { anchors.fill: parent; color: "black"; opacity: 0.35 }
    MouseArea { anchors.fill: parent; onClicked: peek.close() }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 1100)
        height: parent.height - 70
        radius: 12
        color: peek.pal.bgDark
        border.color: peek.pal.accent
        MouseArea { anchors.fill: parent }
        RowLayout {
            id: bar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 8
            height: 30
            spacing: 6
            Text {
                Layout.fillWidth: true
                text: peek.heading.length ? peek.heading : (peek.view ? (peek.view.title || peek.view.url.toString()) : "")
                elide: Text.ElideRight
                color: peek.pal.fgBright
                font.family: peek.pal.font
            }
            Widgets.Btn { pal: peek.pal; text: "Open as tab"; visible: !peek.htmlMode; primary: true; onClicked: peek.openAsTab(false) }
            Widgets.Btn { pal: peek.pal; text: "Split"; visible: !peek.htmlMode; onClicked: peek.openAsTab(true) }
            Widgets.Btn { pal: peek.pal; text: "\u2715"; tip: "Close (Esc)"; onClicked: peek.close() }
        }
        Item {
            id: frame
            anchors.top: bar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 6
            clip: true
        }
    }
}
