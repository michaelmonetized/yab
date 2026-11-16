// What an empty tab shows: the theme, the time and your most visited sites.
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: page
    property QtObject pal
    property QtObject browser
    property bool isPrivate: false
    property var sites: []
    signal open(string url)
    color: pal.bg

    onVisibleChanged: if (visible) sites = JSON.parse(browser.topSites())

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 760)
        spacing: 22

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: clock.now
            color: page.pal.fgBright
            font.family: page.pal.font
            font.pixelSize: 44
            Timer { id: clock; property string now: Qt.formatTime(new Date(), "HH:mm"); interval: 10000; running: page.visible; repeat: true; triggeredOnStart: true; onTriggered: now = Qt.formatTime(new Date(), "HH:mm") }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: page.isPrivate ? "private tab — nothing is kept" : (page.pal.name.length ? page.pal.name : "omaweb")
            color: page.isPrivate ? page.pal.accent : page.pal.fgDark
            font.family: page.pal.font
            font.pixelSize: page.pal.fontSize
        }

        GridLayout {
            visible: !page.isPrivate && page.sites.length > 0
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            columns: Math.max(1, Math.min(4, Math.floor(page.width / 200)))
            columnSpacing: 10
            rowSpacing: 10
            Repeater {
                model: page.sites.slice(0, 8)
                delegate: AbstractButton {
                    id: tile
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 58
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    onClicked: page.open(modelData.url)
                    background: Rectangle {
                        color: tile.hovered ? page.pal.bgLighter : page.pal.bgDark
                        border.width: 1
                        border.color: tile.hovered ? page.pal.accent : "transparent"
                    }
                    contentItem: Column {
                        leftPadding: 12
                        topPadding: 10
                        spacing: 4
                        Text {
                            width: tile.width - 24
                            elide: Text.ElideRight
                            text: tile.modelData.title || tile.modelData.url
                            color: page.pal.fgBright
                            font.family: page.pal.font
                            font.pixelSize: page.pal.fontSize
                        }
                        Text {
                            width: tile.width - 24
                            elide: Text.ElideMiddle
                            text: tile.modelData.url.replace(/^https?:\/\/(www\.)?/, "")
                            color: page.pal.fgDark
                            font.family: page.pal.font
                            font.pixelSize: page.pal.fontSize - 2
                        }
                    }
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "ctrl+l address · ctrl+k tabs · ctrl+t new · ctrl+shift+n private · ctrl+f find · ctrl+shift+b compact"
            color: page.pal.muted
            font.family: page.pal.font
            font.pixelSize: page.pal.fontSize - 1
        }
    }
}
