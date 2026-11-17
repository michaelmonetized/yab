// The one field: addresses, searches, history and open tabs (Ctrl+K).
import QtQuick
import QtQuick.Controls.Basic

Item {
    id: box
    property QtObject pal
    property QtObject browser
    property var tabs: []
    property var currentTab: null
    property string profileName: "Default"
    readonly property string currentUid: currentTab ? currentTab.uid : ""
    property alias text: field.text
    readonly property bool editing: field.activeFocus
    signal go(string text)
    signal switchTo(int index)
    signal dismissed()

    property var items: []
    // Ctrl+K: an empty field lists the open tabs.
    property bool tabMode: false
    property int sel: 0

    function focusField(tabsOnly) {
        tabMode = !!tabsOnly
        field.text = currentTab && !currentTab.blank && !tabMode ? currentTab.url.toString() : ""
        field.forceActiveFocus()
        field.selectAll()
        refresh()
    }

    function refresh() {
        const q = field.text.trim()
        let out = []
        if (q.length) {
            const lq = q.toLowerCase()
            for (let i = 0; i < tabs.length; ++i) {
                const t = tabs[i]
                if (t.uid === currentUid) continue
                if (t.title.toLowerCase().indexOf(lq) >= 0 || t.url.toString().toLowerCase().indexOf(lq) >= 0)
                    out.push({ kind: "tab", index: i, title: t.title, url: t.url.toString() })
                if (out.length >= 3) break
            }
            out = JSON.parse(browser.suggest(q, profileName)).concat(out)
        } else if (tabMode) {
            for (let i = 0; i < tabs.length; ++i)
                if (tabs[i].uid !== currentUid) out.push({ kind: "tab", index: i, title: tabs[i].title, url: tabs[i].url.toString() })
        }
        items = out.slice(0, 10)
        sel = 0
        // Finish addresses from history: "omar" + Return goes to omarchy.org.
        if (q.length && q.indexOf(" ") < 0 && items.length > 1 && items[1].kind === "history") {
            const bare = items[1].url.replace(/^https?:\/\/(www\.)?/, "")
            if (bare.toLowerCase().startsWith(q.toLowerCase())) sel = 1
        }
        if (field.activeFocus && items.length) popup.open()
        else popup.close()
    }

    function accept() {
        const it = items[sel]
        popup.close()
        if (it && it.kind === "tab") { switchTo(it.index); return }
        if (it && sel > 0) { go(it.url); return }
        go(field.text)
    }

    Rectangle {
        anchors.fill: parent
        color: field.activeFocus ? box.pal.bgDarker : box.pal.bgDark
        border.width: 1
        border.color: field.activeFocus ? box.pal.accent : "transparent"
    }

    TextField {
        id: field
        anchors.fill: parent
        leftPadding: 10
        rightPadding: 10
        verticalAlignment: TextInput.AlignVCenter
        color: box.pal.fgBright
        placeholderText: "Search or type an address"
        placeholderTextColor: box.pal.fgDark
        selectionColor: box.pal.selection
        selectedTextColor: box.pal.fgBright
        font.family: box.pal.font
        font.pixelSize: box.pal.fontSize + 1
        background: null
        inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoPredictiveText
        text: box.currentTab && !box.currentTab.blank ? box.currentTab.url.toString() : ""

        onTextEdited: box.refresh()
        onActiveFocusChanged: {
            if (activeFocus) box.refresh()
            else {
                popup.close()
                box.tabMode = false
                text = Qt.binding(() => box.currentTab && !box.currentTab.blank ? box.currentTab.url.toString() : "")
            }
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Down || (event.key === Qt.Key_N && event.modifiers & Qt.ControlModifier)) {
                box.sel = Math.min(box.sel + 1, box.items.length - 1); event.accepted = true
            } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_P && event.modifiers & Qt.ControlModifier)) {
                box.sel = Math.max(box.sel - 1, 0); event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                box.accept(); event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
                popup.close(); box.dismissed(); event.accepted = true
            }
        }
    }

    Popup {
        id: popup
        y: box.height + 2
        width: box.width
        padding: 0
        closePolicy: Popup.CloseOnPressOutsideParent
        background: Rectangle { color: box.pal.bgDark; border.color: box.pal.muted; border.width: 1 }
        contentItem: Column {
            Repeater {
                model: box.items
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: popup.width
                    height: 28
                    color: index === box.sel ? box.pal.selection : (ma.containsMouse ? box.pal.bgLighter : "transparent")
                    Rectangle { visible: row.index === box.sel; width: 2; height: parent.height; color: box.pal.accent }
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        spacing: 10
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 56
                            text: row.modelData.kind === "tab" ? "tab" : row.modelData.kind === "search" ? "search" : row.modelData.kind === "go" ? "go" : row.modelData.kind === "bookmark" ? "\u2605" : "visited"
                            color: row.index === box.sel ? box.pal.accent : box.pal.fgDark
                            font.family: box.pal.font
                            font.pixelSize: box.pal.fontSize - 1
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: (popup.width - 90) * 0.45
                            elide: Text.ElideRight
                            text: row.modelData.title || row.modelData.url
                            color: box.pal.fgBright
                            font.family: box.pal.font
                            font.pixelSize: box.pal.fontSize
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: (popup.width - 90) * 0.5
                            elide: Text.ElideMiddle
                            text: row.modelData.kind === "search" ? "" : row.modelData.url
                            color: box.pal.fgDark
                            font.family: box.pal.font
                            font.pixelSize: box.pal.fontSize - 1
                        }
                    }
                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { box.sel = row.index; box.accept() }
                    }
                }
            }
        }
    }
}
