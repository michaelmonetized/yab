// Yab's sidebar, Omarchy-coloured: window controls and history buttons,
// the address as a pill, extension buttons, favorites as tiles, the
// space's name, its folders and pinned tabs, New tab, today's tabs, and a
// footer with downloads, the spaces, settings and the agent.
// Hidden until you reach for it (left edge, Ctrl+Shift+B); can be pinned.
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: side
    property QtObject pal
    property var host                       // Main's window: the workspace and its operations
    property var currentTab: null
    property bool pinned: false
    property bool floating: false
    readonly property bool hovered: hover.hovered || menuOpen
    property bool menuOpen: false
    readonly property var space: host ? host.currentSpace : null
    readonly property color spaceColor: space ? host.spaceColor(space.color) : pal.accent
    signal openPalette()
    signal togglePin()
    signal windowMove()
    signal windowToggleMaximized()

    color: pal.bgDark
    HoverHandler { id: hover }

    // Soft edge when it floats over the page.
    Rectangle {
        visible: side.floating
        anchors.left: parent.right
        width: 14
        height: parent.height
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, side.pal.dark ? 0.35 : 0.15) }
            GradientStop { position: 1; color: "transparent" }
        }
    }
    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: side.pal.muted; opacity: 0.45 }
    // The space's colour, a hairline down the inner edge.
    Rectangle { anchors.right: parent.right; anchors.rightMargin: 1; width: 2; height: parent.height; color: side.spaceColor; opacity: 0.55 }

    function hostOf(u) {
        const s = u.toString()
        const m = s.match(/^[a-z-]+:\/\/([^\/?#]+)/i)
        return m ? m[1].replace(/^www\./, "") : s
    }

    // Two-finger swipe sideways: the next or previous space, as in Arc.
    WheelHandler {
        acceptedDevices: PointerDevice.TouchPad | PointerDevice.Mouse
        orientation: Qt.Horizontal
        property real acc: 0
        onWheel: event => {
            acc += event.angleDelta.x
            if (Math.abs(acc) > 240) { side.host.stepSpace(acc > 0 ? -1 : 1); acc = 0 }
        }
    }

    // What is being dragged: a tab's uid.
    Rectangle {
        id: ghost
        property string uid: ""
        property string label: ""
        width: 200
        height: 28
        radius: 8
        z: 100
        visible: Drag.active
        color: side.pal.selection
        border.color: side.spaceColor
        opacity: 0.92
        Drag.keys: ["qi-tab"]
        Drag.hotSpot.x: 20
        Drag.hotSpot.y: 14
        Text { anchors.fill: parent; anchors.leftMargin: 10; verticalAlignment: Text.AlignVCenter; text: ghost.label; elide: Text.ElideRight; color: side.pal.fgBright; font.family: side.pal.font; font.pixelSize: side.pal.fontSize }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        anchors.rightMargin: 10
        spacing: 6

        // Top row: pin, drag space, back / forward / reload.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onPressed: side.windowMove()
                onDoubleClicked: side.windowToggleMaximized()
            }
            RowLayout {
                anchors.fill: parent
                spacing: 2
                SideButton { glyph: side.pinned ? "\u25e7" : "\u25a1"; tip: side.pinned ? "Hide sidebar (Ctrl+Shift+B)" : "Keep sidebar open (Ctrl+Shift+B)"; onClicked: side.togglePin() }
                Item { Layout.fillWidth: true }
                SideButton { glyph: "\u2190"; tip: "Back (Alt+Left)"; enabled: side.currentTab && side.currentTab.canGoBack; onClicked: side.currentTab.view.goBack() }
                SideButton { glyph: "\u2192"; tip: "Forward (Alt+Right)"; enabled: side.currentTab && side.currentTab.canGoForward; onClicked: side.currentTab.view.goForward() }
                SideButton {
                    glyph: side.currentTab && side.currentTab.loading ? "\u2715" : "\u21bb"
                    tip: side.currentTab && side.currentTab.loading ? "Stop (Esc)" : "Reload (Ctrl+R)"
                    enabled: side.currentTab !== null
                    onClicked: side.host.reloadOrStop()
                }
            }
        }

        // The address, as Yab shows it: a quiet pill that opens the palette.
        AbstractButton {
            id: pill
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            focusPolicy: Qt.NoFocus
            hoverEnabled: true
            onClicked: side.openPalette()
            readonly property string url: side.currentTab && !side.currentTab.blank ? side.currentTab.url.toString() : ""
            background: Rectangle {
                radius: 8
                color: pill.hovered ? side.pal.selection : side.pal.bgLighter
                Rectangle {
                    visible: side.currentTab !== null && side.currentTab.loading
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    height: 2
                    radius: 1
                    width: side.currentTab ? parent.width * side.currentTab.progress / 100 : 0
                    color: side.spaceColor
                }
            }
            contentItem: RowLayout {
                spacing: 6
                Text {
                    Layout.leftMargin: 10
                    visible: pill.url.startsWith("http://")
                    text: "Not secure"
                    color: side.pal.yellow
                    font.family: side.pal.font
                    font.pixelSize: side.pal.fontSize - 1
                }
                Text {
                    Layout.leftMargin: pill.url.startsWith("http://") ? 0 : 10
                    Layout.fillWidth: true
                    text: pill.url.length ? side.hostOf(pill.url) : "Search or type an address"
                    elide: Text.ElideRight
                    color: pill.url.length ? side.pal.fg : side.pal.fgDark
                    font.family: side.pal.font
                    font.pixelSize: side.pal.fontSize
                }
                Text {
                    visible: side.currentTab !== null && side.currentTab.blockedCount > 0
                    text: "\u26d2 " + (side.currentTab ? side.currentTab.blockedCount : 0)
                    color: side.pal.fgDark
                    font.family: side.pal.font
                    font.pixelSize: side.pal.fontSize - 2
                    ToolTip.visible: blockedHover.hovered
                    ToolTip.text: "Ads and trackers blocked on this page (Ctrl+E for site controls)"
                    HoverHandler { id: blockedHover }
                }
                Text {
                    visible: side.currentTab !== null && side.currentTab.isPrivate
                    text: "private"
                    color: side.pal.accent
                    font.family: side.pal.font
                    font.pixelSize: side.pal.fontSize - 1
                }
                Text {
                    visible: side.host && side.host.currentBookmarked
                    text: "\u2605"
                    color: side.spaceColor
                    font.pixelSize: 12
                    Layout.rightMargin: 10
                }
                Item { visible: !(side.host && side.host.currentBookmarked); Layout.preferredWidth: 4 }
            }
        }

        // Extension buttons: those with a popup open it, like Chrome's toolbar.
        Flow {
            Layout.fillWidth: true
            visible: side.host && side.host.extensionButtons.length > 0
            spacing: 4
            Repeater {
                model: side.host ? side.host.extensionButtons : []
                delegate: AbstractButton {
                    id: eb
                    required property var modelData
                    width: 28
                    height: 28
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    onClicked: side.host.openExtensionPopup(modelData)
                    ToolTip.visible: hovered
                    ToolTip.text: modelData.name + (modelData.popup.length ? "" : " (no popup)")
                    ToolTip.delay: 400
                    background: Rectangle { radius: 7; color: eb.hovered ? side.pal.selection : side.pal.bgLighter }
                    contentItem: Item {
                        Image { id: eimg; anchors.centerIn: parent; width: 16; height: 16; source: eb.modelData.icon; sourceSize: Qt.size(32, 32); visible: status === Image.Ready }
                        Text { anchors.centerIn: parent; visible: eimg.status !== Image.Ready; text: eb.modelData.name.charAt(0); color: side.pal.fg; font.family: side.pal.font; font.pixelSize: 12 }
                    }
                }
            }
        }

        // Favorites: tiles, the same in every space.
        GridLayout {
            id: favGrid
            Layout.fillWidth: true
            visible: favRepeater.count > 0 || ghost.Drag.active
            columns: 4
            columnSpacing: 6
            rowSpacing: 6
            Repeater {
                id: favRepeater
                model: side.host ? side.host.favoriteRows : []
                delegate: AbstractButton {
                    id: tile
                    required property var modelData
                    readonly property bool isCurrent: side.host.currentUid === modelData.uid
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    onClicked: side.host.selectUid(modelData.uid)
                    ToolTip.visible: hovered
                    ToolTip.text: modelData.title
                    ToolTip.delay: 500
                    TapHandler { acceptedButtons: Qt.RightButton; onTapped: side.openTabMenu(tile.modelData, true) }
                    background: Rectangle {
                        radius: 9
                        color: tile.isCurrent ? side.pal.bgLighter : (tile.hovered ? side.pal.selection : Qt.rgba(side.pal.bgLighter.r, side.pal.bgLighter.g, side.pal.bgLighter.b, 0.55))
                        border.width: tile.isCurrent ? 1 : 0
                        border.color: side.spaceColor
                    }
                    contentItem: Item {
                        Image { id: fimg; anchors.centerIn: parent; width: 18; height: 18; source: tile.modelData.icon; sourceSize: Qt.size(36, 36); visible: status === Image.Ready && !tile.modelData.loading }
                        Text {
                            anchors.centerIn: parent
                            visible: fimg.status !== Image.Ready || tile.modelData.loading
                            text: tile.modelData.loading ? "\u25cc" : (tile.modelData.title.length ? tile.modelData.title.charAt(0).toUpperCase() : "\u00b7")
                            color: side.pal.fg
                            font.family: side.pal.font
                            font.pixelSize: 14
                        }
                    }
                }
            }
            // Drop a tab here to make it a favorite.
            Rectangle {
                visible: ghost.Drag.active
                Layout.fillWidth: true
                Layout.columnSpan: favRepeater.count === 0 ? 4 : 1
                Layout.preferredHeight: 40
                radius: 9
                color: favDrop.containsDrag ? side.pal.selection : "transparent"
                border.width: 1
                border.color: side.spaceColor
                Text { anchors.centerIn: parent; text: "\u2605"; color: side.spaceColor; font.pixelSize: 14 }
                DropArea { id: favDrop; anchors.fill: parent; keys: ["qi-tab"]; onDropped: side.host.op({ op: "favorite", uid: ghost.uid, on: true }) }
            }
        }

        // The space: its name in its colour.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            Layout.topMargin: 2
            RowLayout {
                anchors.fill: parent
                spacing: 6
                visible: !spaceName.visible
                Text { Layout.leftMargin: 6; text: side.space ? side.space.icon : ""; color: side.spaceColor; font.family: side.pal.font; font.pixelSize: side.pal.fontSize + 1; font.bold: true }
                Text {
                    Layout.fillWidth: true
                    text: side.space ? side.space.name : ""
                    elide: Text.ElideRight
                    color: side.pal.fgBright
                    font.family: side.pal.font
                    font.pixelSize: side.pal.fontSize
                    font.bold: true
                }
                Text {
                    visible: side.space && side.space.profile !== side.host.defaultProfile
                    text: side.space ? side.space.profile : ""
                    color: side.pal.fgDark
                    font.family: side.pal.font
                    font.pixelSize: side.pal.fontSize - 2
                }
                SideButton { glyph: "\u22ef"; tip: "Space: rename, colour, profile, new folder"; onClicked: side.openSpaceMenu() }
            }
            TapHandler { acceptedButtons: Qt.RightButton; onTapped: side.openSpaceMenu() }
            TapHandler { onDoubleTapped: side.renameSpace() }
            TextField {
                id: spaceName
                visible: false
                anchors.fill: parent
                color: side.pal.fgBright
                font.family: side.pal.font
                font.pixelSize: side.pal.fontSize
                background: Rectangle { radius: 6; color: side.pal.bgDarker; border.color: side.spaceColor }
                onAccepted: { side.host.op({ op: "update_space", id: side.space.id, name: text }); visible = false }
                onActiveFocusChanged: if (!activeFocus) visible = false
                Keys.onEscapePressed: visible = false
            }
        }
    
        // Folders, pinned tabs, New tab, today tabs.
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: side.host ? side.host.sidebarRows : []
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 4 }
            delegate: Loader {
                id: rowLoader
                required property var modelData
                width: list.width
                sourceComponent: modelData.kind === "folder" ? folderRow : modelData.kind === "tab" ? tabRow : modelData.kind === "divider" ? dividerRow : modelData.kind === "new" ? newRow : pinnedHint
                onLoaded: item.row = modelData
            }
        }

        // Footer: downloads, the spaces, new space, settings, agent.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            spacing: 2
            SideButton {
                glyph: "\u2913"
                tip: "Downloads (Ctrl+Shift+J)"
                onClicked: side.host.openLibrary("downloads")
                Rectangle {
                    visible: side.host && side.host.activeDownloads > 0
                    anchors.right: parent.right
                    anchors.top: parent.top
                    width: 14; height: 14; radius: 7
                    color: side.spaceColor
                    Text { anchors.centerIn: parent; text: side.host ? side.host.activeDownloads : ""; color: side.pal.onAccent; font.pixelSize: 9 }
                }
            }
            Item { Layout.fillWidth: true }
            Repeater {
                model: side.host ? side.host.ws.spaces : []
                delegate: AbstractButton {
                    id: sp
                    required property var modelData
                    required property int index
                    readonly property bool isCurrent: side.host.ws.current_space === modelData.id
                    readonly property color c: side.host.spaceColor(modelData.color)
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    onClicked: side.host.switchSpace(modelData.id)
                    ToolTip.visible: hovered
                    ToolTip.text: modelData.name + (index < 9 ? "  (Ctrl+Alt+" + (index + 1) + ")" : "")
                    ToolTip.delay: 400
                    TapHandler { acceptedButtons: Qt.RightButton; onTapped: { side.host.switchSpace(sp.modelData.id); side.openSpaceMenu() } }
                    background: Rectangle {
                        radius: 12
                        color: sp.isCurrent ? sp.c : (sp.hovered || spDrop.containsDrag ? side.pal.selection : "transparent")
                        border.width: sp.isCurrent ? 0 : 1
                        border.color: Qt.rgba(sp.c.r, sp.c.g, sp.c.b, 0.7)
                    }
                    contentItem: Text {
                        text: sp.modelData.icon
                        color: sp.isCurrent ? side.pal.onAccent : sp.c
                        font.family: side.pal.font
                        font.pixelSize: 11
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    DropArea {
                        id: spDrop
                        anchors.fill: parent
                        keys: ["qi-tab"]
                        onDropped: side.host.op({ op: "move_tab", uid: ghost.uid, space: sp.modelData.id, folder: "" })
                    }
                }
            }
            SideButton { glyph: "+"; tip: "New space (Ctrl+Alt+N)"; onClicked: side.host.newSpace() }
            Item { Layout.fillWidth: true }
            SideButton { glyph: "\u2699"; tip: "Settings (Ctrl+,)"; onClicked: side.host.openSettings("") }
            SideButton { glyph: "\u2726"; tip: "Agent (Ctrl+Shift+A)"; highlighted: side.host && side.host.agentOpen; onClicked: side.host.toggleAgent() }
        }
    }

    function renameSpace() {
        if (!space) return
        spaceName.text = space.name
        spaceName.visible = true
        spaceName.forceActiveFocus()
        spaceName.selectAll()
    }

    // ---- Rows ------------------------------------------------------------
    Component {
        id: folderRow
        AbstractButton {
            id: fr
            property var row
            readonly property var folder: row ? row.folder : null
            height: 30
            hoverEnabled: true
            focusPolicy: Qt.NoFocus
            onClicked: side.host.op({ op: "toggle_folder", id: folder.id })
            TapHandler { acceptedButtons: Qt.RightButton; onTapped: side.openFolderMenu(fr.folder, fr) }
            function rename() { nameField.text = folder.name; nameField.visible = true; nameField.forceActiveFocus(); nameField.selectAll() }
            Connections { target: side; function onRenameFolderRequested(id) { if (fr.folder && id === fr.folder.id) fr.rename() } }
            background: Rectangle { radius: 8; color: drop.containsDrag ? side.pal.selection : (fr.hovered ? Qt.rgba(side.pal.selection.r, side.pal.selection.g, side.pal.selection.b, 0.6) : "transparent"); border.width: drop.containsDrag ? 1 : 0; border.color: side.spaceColor }
            contentItem: RowLayout {
                spacing: 8
                Text { Layout.leftMargin: 8; Layout.preferredWidth: 16; horizontalAlignment: Text.AlignHCenter; text: fr.folder && fr.folder.collapsed ? "\u25b8" : "\u25be"; color: side.pal.fgDark; font.pixelSize: 12 }
                Text { text: fr.folder && fr.folder.collapsed ? "\ud83d\uddc0" : "\ud83d\uddc1"; color: side.spaceColor; font.pixelSize: 13; visible: false }
                Text {
                    Layout.fillWidth: true
                    visible: !nameField.visible
                    text: fr.folder ? fr.folder.name : ""
                    elide: Text.ElideRight
                    color: side.pal.fg
                    font.family: side.pal.font
                    font.pixelSize: side.pal.fontSize
                    font.bold: true
                }
                TextField {
                    id: nameField
                    visible: false
                    Layout.fillWidth: true
                    Layout.rightMargin: 4
                    implicitHeight: 24
                    color: side.pal.fgBright
                    font.family: side.pal.font
                    font.pixelSize: side.pal.fontSize
                    background: Rectangle { radius: 5; color: side.pal.bgDarker; border.color: side.spaceColor }
                    onAccepted: { side.host.op({ op: "rename_folder", id: fr.folder.id, name: text }); visible = false }
                    onActiveFocusChanged: if (!activeFocus) visible = false
                    Keys.onEscapePressed: visible = false
                }
                Text { visible: !nameField.visible; text: fr.row ? fr.row.count : ""; color: side.pal.fgDark; font.family: side.pal.font; font.pixelSize: side.pal.fontSize - 2; Layout.rightMargin: 8 }
            }
            DropArea { id: drop; anchors.fill: parent; keys: ["qi-tab"]; onDropped: side.host.op({ op: "move_tab", uid: ghost.uid, folder: fr.folder.id }) }
        }
    }

    Component {
        id: tabRow
        AbstractButton {
            id: cell
            property var row
            readonly property var rec: row ? row.rec : null
            readonly property bool isCurrent: rec && side.host.currentUid === rec.uid
            readonly property bool inSplit: rec && side.host.splitUid === rec.uid
            height: row && row.watch.length ? 42 : 32
            hoverEnabled: true
            focusPolicy: Qt.NoFocus
            onClicked: side.host.selectUid(rec.uid)
            TapHandler { acceptedButtons: Qt.MiddleButton; onTapped: side.host.closeUid(cell.rec.uid) }
            TapHandler { acceptedButtons: Qt.RightButton; onTapped: side.openTabMenu(cell.row, false) }
            MouseArea {
                z: 1
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                drag.target: ghost
                drag.threshold: 8
                propagateComposedEvents: true
                onPressed: mouse => {
                    // Leave clicks on the close button to the button.
                    const c = closeBtn.mapToItem(cell, 0, 0)
                    if (closeBtn.visible && mouse.x >= c.x && mouse.x <= c.x + closeBtn.width && mouse.y >= c.y && mouse.y <= c.y + closeBtn.height) { mouse.accepted = false; return }
                    ghost.uid = cell.rec.uid
                    ghost.label = cell.row.title
                    const p = cell.mapToItem(side, 0, 0)
                    ghost.x = p.x; ghost.y = p.y
                }
                onClicked: side.host.selectUid(cell.rec.uid)
                drag.onActiveChanged: if (drag.active) ghost.Drag.active = true
                onReleased: { if (ghost.Drag.active) { ghost.Drag.drop(); ghost.Drag.active = false } }
            }
            background: Rectangle {
                radius: 8
                color: tabDrop.containsDrag ? side.pal.selection : (cell.isCurrent ? side.pal.bgLighter : (cell.hovered ? side.pal.selection : "transparent"))
                border.width: cell.isCurrent || cell.inSplit ? 1 : 0
                border.color: Qt.rgba(side.spaceColor.r, side.spaceColor.g, side.spaceColor.b, cell.inSplit ? 0.9 : 0.5)
                Rectangle { visible: tabDrop.containsDrag; width: parent.width; height: 2; color: side.spaceColor }
            }
            contentItem: RowLayout {
                spacing: 8
                Item {
                    Layout.leftMargin: cell.row && cell.row.indent ? 24 : 8
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                    Image {
                        id: fav
                        anchors.fill: parent
                        source: cell.row ? cell.row.icon : ""
                        sourceSize: Qt.size(32, 32)
                        visible: cell.row && !cell.row.loading && status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: cell.row && !cell.row.loading && fav.status !== Image.Ready
                        text: !cell.row ? "" : cell.row.isPrivate ? "\u25cf" : (cell.row.title.length ? cell.row.title.charAt(0).toUpperCase() : "\u00b7")
                        color: cell.row && cell.row.isPrivate ? side.pal.accent : side.pal.fgDark
                        font.family: side.pal.font
                        font.pixelSize: 11
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: cell.row && cell.row.loading
                        text: "\u25cc"
                        color: side.spaceColor
                        font.pixelSize: 13
                        RotationAnimator on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: cell.row && cell.row.loading }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: cell.row ? cell.row.title : ""
                        elide: Text.ElideRight
                        color: cell.isCurrent ? side.pal.fgBright : (cell.row && !cell.row.live ? side.pal.fgDark : side.pal.fg)
                        font.family: side.pal.font
                        font.pixelSize: side.pal.fontSize
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: cell.row && cell.row.watch.length > 0
                        text: cell.row ? "\ud83d\udc41 " + cell.row.watch : ""
                        elide: Text.ElideRight
                        color: side.spaceColor
                        font.family: side.pal.font
                        font.pixelSize: side.pal.fontSize - 2
                    }
                }
                Text { visible: cell.row && cell.row.audible; text: "\u266a"; color: side.pal.fgDark; font.pixelSize: 12 }
                Text { visible: cell.inSplit; text: "\u25eb"; color: side.spaceColor; font.pixelSize: 12 }
                AbstractButton {
                    id: closeBtn
                    visible: cell.hovered
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    Layout.rightMargin: 6
                    focusPolicy: Qt.NoFocus
                    hoverEnabled: true
                    onClicked: side.host.closeUid(cell.rec.uid)
                    background: Rectangle { radius: 5; color: closeBtn.hovered ? side.pal.muted : "transparent" }
                    contentItem: Text {
                        text: cell.rec && cell.rec.pinned ? "\u2212" : "\u00d7"
                        color: closeBtn.hovered ? side.pal.fgBright : side.pal.fgDark
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    ToolTip.visible: hovered
                    ToolTip.text: cell.rec && cell.rec.pinned ? "Close (stays pinned: unload)" : "Close (Ctrl+W)"
                    ToolTip.delay: 600
                }
            }
            DropArea {
                id: tabDrop
                anchors.fill: parent
                keys: ["qi-tab"]
                onDropped: if (ghost.uid !== cell.rec.uid) side.host.op({ op: "move_tab", uid: ghost.uid, before: cell.rec.uid, pinned: cell.rec.pinned, folder: cell.rec.folder })
            }
        }
    }

    Component {
        id: dividerRow
        Item {
            property var row
            height: 22
            Rectangle { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.right: clear.left; anchors.rightMargin: 6; height: 1; color: side.pal.muted; opacity: 0.45 }
            AbstractButton {
                id: clear
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: parent.row && parent.row.today > 0
                hoverEnabled: true
                focusPolicy: Qt.NoFocus
                onClicked: side.host.op({ op: "clear_today", now: side.host.nowSecs() })
                contentItem: Text { text: "\u2193 Clear"; color: clear.hovered ? side.pal.fgBright : side.pal.fgDark; font.family: side.pal.font; font.pixelSize: side.pal.fontSize - 2 }
                background: Item {}
                ToolTip.visible: hovered
                ToolTip.text: "Archive today's tabs (pinned tabs stay)"
                ToolTip.delay: 500
            }
            DropArea { anchors.fill: parent; keys: ["qi-tab"]; onDropped: side.host.op({ op: "move_tab", uid: ghost.uid, folder: "", pinned: false }) }
        }
    }

    Component {
        id: pinnedHint
        Rectangle {
            property var row
            height: ghost.Drag.active ? 26 : 0
            visible: ghost.Drag.active
            radius: 8
            color: pinDrop.containsDrag ? side.pal.selection : "transparent"
            border.width: 1
            border.color: Qt.rgba(side.spaceColor.r, side.spaceColor.g, side.spaceColor.b, 0.6)
            Text { anchors.centerIn: parent; text: "Drop here to pin"; color: side.pal.fgDark; font.family: side.pal.font; font.pixelSize: side.pal.fontSize - 1 }
            DropArea { id: pinDrop; anchors.fill: parent; keys: ["qi-tab"]; onDropped: side.host.op({ op: "move_tab", uid: ghost.uid, folder: "", pinned: true }) }
        }
    }

    Component {
        id: newRow
        AbstractButton {
            id: r
            property var row
            height: 32
            focusPolicy: Qt.NoFocus
            hoverEnabled: true
            onClicked: side.host.newTab()
            background: Rectangle { radius: 8; color: r.hovered || nd.containsDrag ? side.pal.selection : "transparent" }
            contentItem: RowLayout {
                spacing: 8
                Text { Layout.leftMargin: 8; Layout.preferredWidth: 16; horizontalAlignment: Text.AlignHCenter; text: "+"; color: r.hovered ? side.pal.fgBright : side.pal.fgDark; font.family: side.pal.font; font.pixelSize: 16 }
                Text { Layout.fillWidth: true; text: "New tab"; color: r.hovered ? side.pal.fgBright : side.pal.fgDark; font.family: side.pal.font; font.pixelSize: side.pal.fontSize }
                Text { text: "ctrl+t"; color: side.pal.fgDark; opacity: 0.7; font.family: side.pal.font; font.pixelSize: side.pal.fontSize - 2; Layout.rightMargin: 8 }
            }
            DropArea { id: nd; anchors.fill: parent; keys: ["qi-tab"]; onDropped: side.host.op({ op: "move_tab", uid: ghost.uid, folder: "", pinned: false }) }
        }
    }

    // ---- Menus -------------------------------------------------------------
    signal renameFolderRequested(string id)
    Widgets.OMenu { id: tabMenu; pal: side.pal; onOpened: side.menuOpen = true; onClosed: side.menuOpen = false
        property var row: null
        property bool fav: false
        Widgets.OMenuItem { pal: side.pal; text: tabMenu.fav ? "Remove from favorites" : "Add to favorites"; enabled: tabMenu.row && !tabMenu.row.isPrivate; onTriggered: side.host.op({ op: "favorite", uid: tabMenu.row.uid, on: !tabMenu.fav }) }
        Widgets.OMenuItem { pal: side.pal; visible: !tabMenu.fav; height: visible ? implicitHeight : 0; text: tabMenu.row && tabMenu.row.pinned ? "Unpin" : "Pin (Ctrl+D)"; enabled: tabMenu.row && !tabMenu.row.isPrivate; onTriggered: side.host.op({ op: "pin", uid: tabMenu.row.uid, on: !tabMenu.row.pinned }) }
        Widgets.OMenuItem { pal: side.pal; visible: tabMenu.row && tabMenu.row.pinned; height: visible ? implicitHeight : 0; text: "Back to pinned address"; onTriggered: side.host.resetPinned(tabMenu.row.uid) }
        Widgets.OMenu {
            id: folderSub
            pal: side.pal
            title: "Move to folder"
            enabled: tabMenu.row && !tabMenu.row.isPrivate && !tabMenu.fav
            Instantiator {
                model: side.space ? side.space.folders : []
                delegate: Widgets.OMenuItem { required property var modelData; pal: side.pal; text: modelData.name; onTriggered: side.host.op({ op: "move_tab", uid: tabMenu.row.uid, folder: modelData.id }) }
                onObjectAdded: (i, o) => folderSub.insertItem(i, o)
                onObjectRemoved: (i, o) => folderSub.removeItem(o)
            }
            Widgets.OMenuItem { pal: side.pal; text: "New folder\u2026"; onTriggered: side.host.newFolder(tabMenu.row.uid) }
            Widgets.OMenuItem { pal: side.pal; text: "Out of folders"; onTriggered: side.host.op({ op: "move_tab", uid: tabMenu.row.uid, folder: "" }) }
        }
        Widgets.OMenu {
            id: spaceSub
            pal: side.pal
            title: "Move to space"
            Instantiator {
                model: side.host ? side.host.ws.spaces : []
                delegate: Widgets.OMenuItem { required property var modelData; pal: side.pal; text: modelData.name; enabled: !side.space || modelData.id !== side.space.id || tabMenu.fav; onTriggered: side.host.op({ op: "move_tab", uid: tabMenu.row.uid, space: modelData.id, folder: "" }) }
                onObjectAdded: (i, o) => spaceSub.insertItem(i, o)
                onObjectRemoved: (i, o) => spaceSub.removeItem(o)
            }
        }
        Widgets.OMenuItem { pal: side.pal; text: side.host && side.host.splitUid === (tabMenu.row ? tabMenu.row.uid : "") ? "Close split view" : "Open in split view"; onTriggered: side.host.splitWith(tabMenu.row.uid) }
        Widgets.OMenuItem { pal: side.pal; text: "Duplicate"; onTriggered: side.host.duplicate(tabMenu.row.uid) }
        Widgets.OMenuItem { pal: side.pal; text: "Bookmark (Ctrl+Shift+D)"; enabled: tabMenu.row && !tabMenu.row.isPrivate; onTriggered: side.host.bookmarkUid(tabMenu.row.uid) }
        Widgets.OMenuItem { pal: side.pal; text: "Copy address"; onTriggered: side.host.copyText(tabMenu.row.url) }
        MenuSeparator { contentItem: Rectangle { implicitHeight: 1; color: side.pal.muted; opacity: 0.5 } }
        Widgets.OMenuItem { pal: side.pal; text: "Close"; onTriggered: side.host.closeUid(tabMenu.row.uid) }
    }
    function openTabMenu(row, fav) {
        tabMenu.row = row
        tabMenu.fav = fav
        tabMenu.popup()
    }

    Widgets.OMenu { id: folderMenu; pal: side.pal; onOpened: side.menuOpen = true; onClosed: side.menuOpen = false
        property var folder: null
        Widgets.OMenuItem { pal: side.pal; text: "Rename"; onTriggered: side.renameFolderRequested(folderMenu.folder.id) }
        Widgets.OMenuItem { pal: side.pal; text: folderMenu.folder && folderMenu.folder.collapsed ? "Expand" : "Collapse"; onTriggered: side.host.op({ op: "toggle_folder", id: folderMenu.folder.id }) }
        Widgets.OMenuItem { pal: side.pal; text: "Open all"; onTriggered: side.host.openFolder(folderMenu.folder.id) }
        Widgets.OMenuItem { pal: side.pal; text: "Delete folder (keeps its tabs)"; onTriggered: side.host.op({ op: "remove_folder", id: folderMenu.folder.id }) }
    }
    function openFolderMenu(folder) { folderMenu.folder = folder; folderMenu.popup() }

    Widgets.OMenu { id: spaceMenu; pal: side.pal; onOpened: side.menuOpen = true; onClosed: side.menuOpen = false
        Widgets.OMenuItem { pal: side.pal; text: "Rename space"; onTriggered: side.renameSpace() }
        Widgets.OMenuItem { pal: side.pal; text: "New folder"; onTriggered: side.host.newFolder("") }
        Widgets.OMenu {
            id: colorSub
            pal: side.pal
            title: "Colour"
            Instantiator {
                model: ["accent", "blue", "magenta", "green", "yellow", "cyan", "red"]
                delegate: Widgets.OMenuItem { required property var modelData; pal: side.pal; text: "\u25cf  " + modelData; onTriggered: side.host.op({ op: "update_space", id: side.space.id, color: modelData }) }
                onObjectAdded: (i, o) => colorSub.insertItem(i, o)
                onObjectRemoved: (i, o) => colorSub.removeItem(o)
            }
        }
        Widgets.OMenu {
            id: profileSub
            pal: side.pal
            title: "Profile"
            Instantiator {
                model: side.host ? side.host.profiles : []
                delegate: Widgets.OMenuItem { required property var modelData; pal: side.pal; text: (side.space && side.space.profile === modelData.name ? "\u2713 " : "    ") + modelData.name; onTriggered: side.host.setSpaceProfile(side.space.id, modelData.name) }
                onObjectAdded: (i, o) => profileSub.insertItem(i, o)
                onObjectRemoved: (i, o) => profileSub.removeItem(o)
            }
            Widgets.OMenuItem { pal: side.pal; text: "New profile\u2026"; onTriggered: side.host.openSettings("profiles") }
        }
        Widgets.OMenuItem { pal: side.pal; text: "Archive today's tabs"; onTriggered: side.host.op({ op: "clear_today", now: side.host.nowSecs() }) }
        Widgets.OMenuItem { pal: side.pal; text: "New space (Ctrl+Alt+N)"; onTriggered: side.host.newSpace() }
        Widgets.OMenuItem { pal: side.pal; text: "Delete space (archives its tabs)"; enabled: side.host && side.host.ws.spaces.length > 1; onTriggered: side.host.op({ op: "remove_space", id: side.space.id, now: side.host.nowSecs() }) }
    }
    function openSpaceMenu() { spaceMenu.popup() }

    component SideButton: AbstractButton {
        id: sb
        property string glyph
        property string tip
        property bool highlighted: false
        Layout.preferredWidth: 28
        Layout.preferredHeight: 28
        focusPolicy: Qt.NoFocus
        hoverEnabled: true
        opacity: enabled ? 1 : 0.35
        ToolTip.visible: hovered && tip.length
        ToolTip.text: tip
        ToolTip.delay: 600
        background: Rectangle { radius: 6; color: sb.highlighted ? side.pal.selection : (sb.hovered ? side.pal.bgLighter : "transparent") }
        contentItem: Text {
            text: sb.glyph
            color: sb.highlighted ? side.spaceColor : (sb.hovered ? side.pal.fgBright : side.pal.fg)
            font.family: side.pal.font
            font.pixelSize: 15
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
