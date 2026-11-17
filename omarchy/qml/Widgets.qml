// Small Omarchy-coloured controls shared by the panels: Widgets.Btn,
// Widgets.Field, Widgets.Toggle, Widgets.Label, Widgets.OMenu, Widgets.OMenuItem.
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

QtObject {
    component Btn: AbstractButton {
        id: b
        property QtObject pal
        property bool primary: false
        property bool danger: false
        property string tip: ""
        focusPolicy: Qt.NoFocus
        hoverEnabled: true
        implicitWidth: Math.max(28, t.implicitWidth + 22)
        implicitHeight: 28
        opacity: enabled ? 1 : 0.4
        ToolTip.visible: hovered && tip.length > 0
        ToolTip.text: tip
        ToolTip.delay: 600
        background: Rectangle {
            radius: 7
            color: b.primary ? b.pal.accent : (b.down ? b.pal.selection : (b.hovered ? b.pal.bgLighter : "transparent"))
            border.width: b.primary ? 0 : 1
            border.color: b.danger ? b.pal.red : Qt.rgba(b.pal.muted.r, b.pal.muted.g, b.pal.muted.b, 0.8)
        }
        contentItem: Text {
            id: t
            text: b.text
            color: b.primary ? b.pal.onAccent : (b.danger ? b.pal.red : b.pal.fg)
            font.family: b.pal.font
            font.pixelSize: b.pal.fontSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    component Field: TextField {
        id: f
        property QtObject pal
        color: pal.fgBright
        placeholderTextColor: pal.fgDark
        selectionColor: pal.selection
        selectedTextColor: pal.fgBright
        font.family: pal.font
        font.pixelSize: pal.fontSize
        implicitHeight: 30
        leftPadding: 10
        rightPadding: 10
        background: Rectangle {
            radius: 7
            color: f.pal.bgDarker
            border.width: 1
            border.color: f.activeFocus ? f.pal.accent : Qt.rgba(f.pal.muted.r, f.pal.muted.g, f.pal.muted.b, 0.8)
        }
    }

    component Toggle: Switch {
        id: sw
        property QtObject pal
        focusPolicy: Qt.NoFocus
        implicitHeight: 24
        indicator: Rectangle {
            implicitWidth: 34
            implicitHeight: 18
            x: sw.leftPadding
            y: (sw.height - height) / 2
            radius: 9
            color: sw.checked ? sw.pal.accent : sw.pal.bgLighter
            border.color: sw.pal.muted
            border.width: sw.checked ? 0 : 1
            Rectangle {
                x: sw.checked ? parent.width - width - 2 : 2
                y: 2
                width: 14
                height: 14
                radius: 7
                color: sw.checked ? sw.pal.onAccent : sw.pal.fg
                Behavior on x { NumberAnimation { duration: 120 } }
            }
        }
        contentItem: Text {
            text: sw.text
            leftPadding: sw.indicator.width + 8
            color: sw.pal.fg
            font.family: sw.pal.font
            font.pixelSize: sw.pal.fontSize
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
        }
    }

    component Label: Text {
        property QtObject pal
        property bool dim: false
        property bool heading: false
        color: heading ? pal.fgBright : (dim ? pal.fgDark : pal.fg)
        font.family: pal.font
        font.pixelSize: heading ? pal.fontSize + 3 : pal.fontSize
        font.bold: heading
        wrapMode: Text.WordWrap
    }

    component OMenu: Menu {
        id: m
        property QtObject pal
        padding: 4
        background: Rectangle {
            implicitWidth: 220
            radius: 9
            color: m.pal.bgDark
            border.color: m.pal.muted
            border.width: 1
        }
        delegate: OMenuItem { pal: m.pal }
    }

    component OMenuItem: MenuItem {
        id: mi
        property QtObject pal
        implicitHeight: 28
        implicitWidth: 220
        background: Rectangle { radius: 6; color: mi.highlighted ? mi.pal.selection : "transparent" }
        contentItem: Text {
            leftPadding: 6
            text: mi.text
            color: mi.enabled ? (mi.highlighted ? mi.pal.fgBright : mi.pal.fg) : mi.pal.fgDark
            font.family: mi.pal.font
            font.pixelSize: mi.pal.fontSize
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        arrow: Text {
            x: mi.width - width - 8
            anchors.verticalCenter: parent.verticalCenter
            visible: mi.subMenu
            text: "\u203a"
            color: mi.pal.fgDark
            font.pixelSize: 14
        }
        indicator: Item {}
    }
}
