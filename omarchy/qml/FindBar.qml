// Ctrl+F. Enter finds the next match, Shift+Enter the previous, Esc closes.
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtWebEngine

Rectangle {
    id: bar
    property QtObject pal
    property var view: null
    property int matches: 0
    property int active: 0
    visible: false
    implicitHeight: visible ? 34 : 0
    color: pal.bgDark

    function open() { visible = true; input.forceActiveFocus(); input.selectAll() }
    function openWith(t) { visible = true; input.text = t; if (view && t.length) view.findText(t) }
    function close() {
        visible = false
        if (view) { view.findText(""); view.forceActiveFocus() }
    }
    function next(back) {
        if (!view || !input.text.length) { open(); return }
        view.findText(input.text, back ? WebEngineView.FindBackward : 0)
    }

    Connections {
        target: bar.view ? bar.view : null
        ignoreUnknownSignals: true
        function onFindTextFinished(result) { bar.matches = result.numberOfMatches; bar.active = result.activeMatch }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 8
        Text { text: "find"; color: bar.pal.accent; font.family: bar.pal.font; font.pixelSize: bar.pal.fontSize }
        TextField {
            id: input
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            color: bar.pal.fgBright
            selectionColor: bar.pal.selection
            font.family: bar.pal.font
            font.pixelSize: bar.pal.fontSize
            background: Rectangle { color: bar.pal.bgDarker; border.color: input.activeFocus ? bar.pal.accent : bar.pal.muted; border.width: 1 }
            onTextChanged: if (bar.view) bar.view.findText(text)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    bar.next(event.modifiers & Qt.ShiftModifier); event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                    bar.close(); event.accepted = true
                }
            }
        }
        Text {
            text: input.text.length ? (bar.matches ? bar.active + "/" + bar.matches : "no matches") : ""
            color: bar.matches || !input.text.length ? bar.pal.fgDark : bar.pal.red
            font.family: bar.pal.font
            font.pixelSize: bar.pal.fontSize - 1
        }
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: bar.pal.muted; opacity: 0.35 }
}
