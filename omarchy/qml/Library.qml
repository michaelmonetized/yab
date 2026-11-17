// The library: bookmarks, history, downloads and archived tabs, per profile.
// Ctrl+Alt+B, Ctrl+H, Ctrl+Shift+J, Ctrl+Alt+A. Esc closes.
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtWebEngine

Item {
    id: lib
    property QtObject pal
    property QtObject browser
    property var host
    visible: false
    property string tab: "bookmarks"
    property string profile: "Default"
    property var rows: []
    property int rev: 0

    function show(t) {
        tab = t || "bookmarks"
        profile = host.profileOfCurrent() === "private" ? host.defaultProfile : host.profileOfCurrent()
        visible = true
        query.text = ""
        reload()
        query.forceActiveFocus()
    }
    function close() { visible = false; if (host.currentTab) host.currentTab.view.forceActiveFocus() }
    function ago(secs) {
        const d = host.nowSecs() - secs
        if (d < 3600) return Math.max(1, Math.round(d / 60)) + " min ago"
        if (d < 86400) return Math.round(d / 3600) + " h ago"
        return new Date(secs * 1000).toLocaleDateString()
    }
    function reload() {
        const q = query.text
        if (tab === "bookmarks") rows = JSON.parse(browser.bookmarks(profile, q)).map(b => ({ id: b.id, title: b.title || b.url, sub: (b.folder.length ? b.folder + " \u00b7 " : "") + b.url, url: b.url }))
        else if (tab === "history") rows = JSON.parse(browser.history(profile, q, 300)).map(h => ({ title: h.title || h.url, sub: h.url + " \u00b7 " + ago(h.last), url: h.url }))
        else if (tab === "downloads") rows = host.downloads.filter(d => !q.length || d.downloadFileName.toLowerCase().indexOf(q.toLowerCase()) >= 0).map(d => ({
            title: d.downloadFileName,
            sub: d.state === WebEngineDownloadRequest.DownloadInProgress ? Math.round(100 * d.receivedBytes / Math.max(1, d.totalBytes)) + "% \u00b7 " + d.downloadDirectory
                : d.state === WebEngineDownloadRequest.DownloadCompleted ? d.downloadDirectory : d.interruptReasonString,
            url: "file://" + d.downloadDirectory + "/" + d.downloadFileName, dl: d }))
        else rows = host.ws.archive.map((a, i) => ({ index: i, title: a.title || a.url, sub: a.space + " \u00b7 " + a.url + " \u00b7 " + ago(a.archived_at), url: a.url }))
            .filter(r => !q.length || (r.title + r.sub).toLowerCase().indexOf(q.toLowerCase()) >= 0)
    }
    function openRow(r) {
        if (tab === "archive") host.op({ op: "restore_archived", index: r.index, uid: host.genUid(), now: host.nowSecs() })
        else if (tab === "downloads") Qt.openUrlExternally(r.url)
        else host.newTab(r.url, true)
        close()
    }
    function removeRow(r) {
        if (tab === "bookmarks") browser.removeBookmark(profile, r.id)
        else if (tab === "history") browser.removeHistory(profile, r.url)
        else if (tab === "downloads") { if (r.dl.state === WebEngineDownloadRequest.DownloadInProgress) r.dl.cancel(); host.downloads = host.downloads.filter(d => d !== r.dl) }
        else host.op({ op: "remove_archived", index: r.index })
        reload()
    }
    Timer { interval: 1000; running: lib.visible && lib.tab === "downloads" && lib.host.activeDownloads > 0; repeat: true; onTriggered: lib.reload() }
    Shortcut { sequences: ["Escape"]; enabled: lib.visible; onActivated: lib.close() }

    Rectangle { anchors.fill: parent; color: "black"; opacity: 0.35 }
    MouseArea { anchors.fill: parent; onClicked: lib.close() }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 860)
        height: Math.min(parent.height - 80, 680)
        radius: 12
        color: lib.pal.bgDark
        border.color: lib.pal.accent
        MouseArea { anchors.fill: parent }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10
            RowLayout {
                spacing: 6
                Repeater {
                    model: [["bookmarks", "Bookmarks"], ["history", "History"], ["downloads", "Downloads"], ["archive", "Archive"]]
                    delegate: Widgets.Btn { required property var modelData; pal: lib.pal; text: modelData[1]; primary: lib.tab === modelData[0]; onClicked: { lib.tab = modelData[0]; lib.reload() } }
                }
                Item { Layout.fillWidth: true }
                Widgets.Label { pal: lib.pal; text: "Profile"; dim: true; visible: lib.tab === "bookmarks" || lib.tab === "history" }
                ComboBox {
                    visible: lib.tab === "bookmarks" || lib.tab === "history"
                    model: lib.host.profiles.map(p => p.name)
                    currentIndex: Math.max(0, model.indexOf(lib.profile))
                    onActivated: i => { lib.profile = model[i]; lib.reload() }
                }
                Widgets.Btn { pal: lib.pal; text: "\u2715"; onClicked: lib.close() }
            }
            RowLayout {
                Widgets.Field { id: query; pal: lib.pal; Layout.fillWidth: true; placeholderText: "Search " + lib.tab; onTextChanged: lib.reload(); Keys.onReturnPressed: if (lib.rows.length) lib.openRow(lib.rows[0]) }
                Widgets.Btn { pal: lib.pal; text: "Clear history"; danger: true; visible: lib.tab === "history"; onClicked: { lib.browser.clearHistory(lib.profile); lib.reload() } }
                Widgets.Btn { pal: lib.pal; text: "Clear archive"; danger: true; visible: lib.tab === "archive" && lib.rows.length > 0; onClicked: { lib.host.op({ op: "clear_archive" }); lib.reload() } }
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: lib.rows
                ScrollBar.vertical: ScrollBar {}
                delegate: AbstractButton {
                    id: row
                    required property var modelData
                    width: ListView.view.width
                    height: 46
                    hoverEnabled: true
                    onClicked: lib.openRow(modelData)
                    background: Rectangle { radius: 7; color: row.hovered ? lib.pal.bgLighter : "transparent" }
                    contentItem: RowLayout {
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 8
                            spacing: 1
                            Text { Layout.fillWidth: true; text: row.modelData.title; elide: Text.ElideRight; color: lib.pal.fgBright; font.family: lib.pal.font }
                            Text { Layout.fillWidth: true; text: row.modelData.sub; elide: Text.ElideMiddle; color: lib.pal.fgDark; font.family: lib.pal.font; font.pixelSize: lib.pal.fontSize - 2 }
                        }
                        Widgets.Btn { pal: lib.pal; visible: row.hovered; text: lib.tab === "archive" ? "Restore" : (lib.tab === "downloads" ? "Open" : "Open"); onClicked: lib.openRow(row.modelData) }
                        Widgets.Btn { pal: lib.pal; visible: row.hovered; text: "\u2715"; tip: "Remove"; onClicked: lib.removeRow(row.modelData) }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: !lib.rows.length
                    text: lib.tab === "bookmarks" ? "No bookmarks yet. Ctrl+Shift+D bookmarks a page." : "Nothing here yet."
                    color: lib.pal.fgDark
                    font.family: lib.pal.font
                }
            }
        }
    }
}
