// Yab's sidebar, Omarchy-coloured: window controls and history buttons on
// top, the current address as a pill, New tab, the tabs, and a footer.
// Hidden until you reach for it (left edge, Ctrl+Shift+B); can be pinned.
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: side
    property QtObject pal
    property var tabs: []
    property int current: -1
    property var currentTab: null
    property bool pinned: false
    property bool floating: false
    readonly property bool hovered: hover.hovered
    signal activate(int index)
    signal closeTab(int index)
    signal newTab()
    signal openPalette()
    signal togglePin()
    signal back()
    signal forward()
    signal reload()
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

    function hostOf(u) {
        const s = u.toString()
        const m = s.match(/^[a-z-]+:\/\/([^\/?#]+)/i)
        return m ? m[1].replace(/^www\./, "") : s
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        anchors.rightMargin: 9
        spacing: 6

        // Top row: pin, drag space, back / forward / reload.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            // Empty space moves the frameless window; double-click maximises.
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
                SideButton { glyph: "\u2190"; tip: "Back (Alt+Left)"; enabled: side.currentTab && side.currentTab.canGoBack; onClicked: side.back() }
                SideButton { glyph: "\u2192"; tip: "Forward (Alt+Right)"; enabled: side.currentTab && side.currentTab.canGoForward; onClicked: side.forward() }
                SideButton {
                    glyph: side.currentTab && side.currentTab.loading ? "\u2715" : "\u21bb"
                    tip: side.currentTab && side.currentTab.loading ? "Stop (Esc)" : "Reload (Ctrl+R)"
                    enabled: side.currentTab !== null
                    onClicked: side.reload()
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
                // Load progress fills the pill in the accent.
                Rectangle {
                    visible: side.currentTab !== null && side.currentTab.loading
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    height: 2
                    radius: 1
                    width: side.currentTab ? parent.width * side.currentTab.progress / 100 : 0
                    color: side.pal.accent
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
                    Layout.rightMargin: 10
                    text: pill.url.length ? side.hostOf(pill.url) : "Search or type an address"
                    elide: Text.ElideRight
                    color: pill.url.length ? side.pal.fg : side.pal.fgDark
                    font.family: side.pal.font
                    font.pixelSize: side.pal.fontSize
                }
                Text {
                    visible: side.currentTab !== null && side.currentTab.isPrivate
                    text: "private"
                    color: side.pal.accent
                    font.family: side.pal.font
                    font.pixelSize: side.pal.fontSize - 1
                    Layout.rightMargin: 10
                }
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; Layout.topMargin: 4; Layout.bottomMargin: 2; color: side.pal.muted; opacity: 0.4 }

        // New tab, then the tabs.
        Row_ {
            Layout.fillWidth: true
            glyph: "+"
            label: "New tab"
            dim: true
            onClicked: side.newTab()
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: side.tabs
            currentIndex: side.current
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 120
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 4 }

            delegate: AbstractButton {
                id: cell
                required property var modelData
                required property int index
                readonly property bool isCurrent: index === side.current
                width: list.width
                height: 32
                hoverEnabled: true
                focusPolicy: Qt.NoFocus
                onClicked: side.activate(index)
                TapHandler { acceptedButtons: Qt.MiddleButton; onTapped: side.closeTab(cell.index) }

                background: Rectangle {
                    radius: 8
                    color: cell.isCurrent ? side.pal.bgLighter : (cell.hovered ? side.pal.selection : "transparent")
                    border.width: cell.isCurrent ? 1 : 0
                    border.color: Qt.rgba(side.pal.accent.r, side.pal.accent.g, side.pal.accent.b, 0.45)
                }
                contentItem: RowLayout {
                    spacing: 8
                    Item {
                        Layout.leftMargin: 8
                        Layout.preferredWidth: 16
                        Layout.preferredHeight: 16
                        Image {
                            id: fav
                            anchors.fill: parent
                            source: cell.modelData.icon
                            sourceSize: Qt.size(32, 32)
                            visible: !cell.modelData.loading && status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !cell.modelData.loading && fav.status !== Image.Ready
                            text: cell.modelData.isPrivate ? "\u25cf" : (cell.modelData.title.length ? cell.modelData.title.charAt(0).toUpperCase() : "\u00b7")
                            color: cell.modelData.isPrivate ? side.pal.accent : side.pal.fgDark
                            font.family: side.pal.font
                            font.pixelSize: 11
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: cell.modelData.loading
                            text: "\u25cc"
                            color: side.pal.accent
                            font.pixelSize: 13
                            RotationAnimator on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: cell.modelData.loading }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: cell.modelData.title
                        elide: Text.ElideRight
                        color: cell.isCurrent ? side.pal.fgBright : side.pal.fg
                        font.family: side.pal.font
                        font.pixelSize: side.pal.fontSize
                    }
                    Text {
                        visible: cell.modelData.audible
                        text: "\u266a"
                        color: side.pal.fgDark
                        font.pixelSize: 12
                    }
                    AbstractButton {
                        id: x
                        visible: cell.hovered
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        Layout.rightMargin: 6
                        focusPolicy: Qt.NoFocus
                        hoverEnabled: true
                        onClicked: side.closeTab(cell.index)
                        background: Rectangle { radius: 5; color: x.hovered ? side.pal.muted : "transparent" }
                        contentItem: Text {
                            text: "\u00d7"
                            color: x.hovered ? side.pal.fgBright : side.pal.fgDark
                            font.pixelSize: 14
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }

        // Footer: theme name on the left, new tab on the right.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            spacing: 2
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                text: side.pal.name.length ? side.pal.name : "omaweb"
                elide: Text.ElideRight
                color: side.pal.fgDark
                font.family: side.pal.font
                font.pixelSize: side.pal.fontSize - 1
            }
            SideButton { glyph: "+"; tip: "New tab (Ctrl+T)"; onClicked: side.newTab() }
        }
    }

    component SideButton: AbstractButton {
        id: sb
        property string glyph
        property string tip
        Layout.preferredWidth: 28
        Layout.preferredHeight: 28
        focusPolicy: Qt.NoFocus
        hoverEnabled: true
        opacity: enabled ? 1 : 0.35
        ToolTip.visible: hovered && tip.length
        ToolTip.text: tip
        ToolTip.delay: 600
        background: Rectangle { radius: 6; color: sb.hovered ? side.pal.bgLighter : "transparent" }
        contentItem: Text {
            text: sb.glyph
            color: sb.hovered ? side.pal.fgBright : side.pal.fg
            font.family: side.pal.font
            font.pixelSize: 15
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    component Row_: AbstractButton {
        id: r
        property string glyph
        property string label
        property bool dim: false
        implicitHeight: 32
        focusPolicy: Qt.NoFocus
        hoverEnabled: true
        background: Rectangle { radius: 8; color: r.hovered ? side.pal.selection : "transparent" }
        contentItem: RowLayout {
            spacing: 8
            Text {
                Layout.leftMargin: 8
                Layout.preferredWidth: 16
                horizontalAlignment: Text.AlignHCenter
                text: r.glyph
                color: r.hovered ? side.pal.fgBright : side.pal.fgDark
                font.family: side.pal.font
                font.pixelSize: 16
            }
            Text {
                Layout.fillWidth: true
                text: r.label
                color: r.hovered ? side.pal.fgBright : side.pal.fgDark
                font.family: side.pal.font
                font.pixelSize: side.pal.fontSize
            }
        }
    }
}
