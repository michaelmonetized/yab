// Tabs across the top (default) or down the left (`tabs = "left"`).
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: strip
    property QtObject pal
    property var tabs: []
    property int current: -1
    property bool vertical: false
    signal activate(int index)
    signal closeTab(int index)
    signal newTab()

    color: pal.bgDark

    ListView {
        id: list
        anchors.fill: parent
        anchors.rightMargin: strip.vertical ? 0 : plus.width
        anchors.bottomMargin: strip.vertical ? plus.height : 0
        orientation: strip.vertical ? ListView.Vertical : ListView.Horizontal
        model: strip.tabs
        currentIndex: strip.current
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentWidth > width || contentHeight > height
        highlightMoveDuration: 120
        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOff }

        delegate: AbstractButton {
            id: cell
            required property var modelData
            required property int index
            readonly property bool isCurrent: index === strip.current
            width: strip.vertical ? list.width : Math.max(120, Math.min(240, (list.width) / Math.max(1, strip.tabs.length)))
            height: strip.vertical ? 30 : list.height
            hoverEnabled: true
            focusPolicy: Qt.NoFocus
            onClicked: strip.activate(index)

            TapHandler {
                acceptedButtons: Qt.MiddleButton
                onTapped: strip.closeTab(cell.index)
            }

            background: Rectangle {
                color: cell.isCurrent ? strip.pal.bg : (cell.hovered ? strip.pal.bgLighter : "transparent")
                // Active tab: accent edge, like Hyprland's active border.
                Rectangle {
                    visible: cell.isCurrent
                    color: strip.pal.accent
                    width: strip.vertical ? 2 : parent.width
                    height: strip.vertical ? parent.height : 2
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                }
                Rectangle {
                    visible: !strip.vertical
                    width: 1
                    height: parent.height
                    anchors.right: parent.right
                    color: strip.pal.muted
                    opacity: 0.35
                }
            }

            contentItem: RowLayout {
                spacing: 6
                anchors.leftMargin: 10
                Item { Layout.preferredWidth: 4 }
                Image {
                    source: cell.modelData.icon
                    visible: !cell.modelData.loading && status === Image.Ready
                    sourceSize: Qt.size(16, 16)
                    Layout.preferredWidth: 14
                    Layout.preferredHeight: 14
                }
                Text {
                    visible: cell.modelData.loading
                    text: "\u25cc"
                    color: strip.pal.accent
                    font.pixelSize: 12
                    RotationAnimator on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: cell.modelData.loading }
                }
                Text {
                    Layout.fillWidth: true
                    text: (cell.modelData.isPrivate ? "\u25cf " : "") + cell.modelData.title
                    elide: Text.ElideRight
                    color: cell.isCurrent ? strip.pal.fgBright : strip.pal.fgDark
                    font.family: strip.pal.font
                    font.pixelSize: strip.pal.fontSize
                }
                Text {
                    visible: cell.modelData.audible
                    text: "\u266a"
                    color: strip.pal.fgDark
                    font.pixelSize: 12
                }
                AbstractButton {
                    id: x
                    visible: cell.hovered || cell.isCurrent
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                    Layout.rightMargin: 6
                    focusPolicy: Qt.NoFocus
                    hoverEnabled: true
                    onClicked: strip.closeTab(cell.index)
                    background: Rectangle { color: x.hovered ? strip.pal.muted : "transparent" }
                    contentItem: Text {
                        text: "\u00d7"
                        color: x.hovered ? strip.pal.fgBright : strip.pal.fgDark
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    AbstractButton {
        id: plus
        width: strip.vertical ? strip.width : 30
        height: strip.vertical ? 30 : strip.height
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        focusPolicy: Qt.NoFocus
        hoverEnabled: true
        onClicked: strip.newTab()
        background: Rectangle { color: plus.hovered ? strip.pal.bgLighter : "transparent" }
        contentItem: Text {
            text: strip.vertical ? "+  New tab" : "+"
            color: plus.hovered ? strip.pal.fgBright : strip.pal.fgDark
            font.family: strip.pal.font
            font.pixelSize: strip.vertical ? strip.pal.fontSize : 16
            horizontalAlignment: strip.vertical ? Text.AlignLeft : Text.AlignHCenter
            leftPadding: strip.vertical ? 12 : 0
            verticalAlignment: Text.AlignVCenter
        }
    }
}
