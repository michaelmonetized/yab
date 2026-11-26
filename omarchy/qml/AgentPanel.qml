// The agent: a chat on the right that can read the current tab (title,
// address, selection, visible text) and act on it with a few tools. The
// requests are built and sent by Rust (src/agent.rs); this draws the chat
// and runs the tool loop. Private tabs are never read.
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: panel
    property QtObject pal
    property QtObject browser
    property var host
    property color accent: pal.accent
    color: pal.bgDark

    property var status: ({})
    property var history: []        // OpenAI-style messages, without the system one
    property int reqId: 0
    property bool busy: false
    property bool readPage: true
    property int steps: 0
    readonly property int maxSteps: 6
    property var pendingCalls: []
    property var confirmCb: null

    function refreshStatus() { status = JSON.parse(browser.agentStatus()) }
    function focusInput() { refreshStatus(); input.forceActiveFocus() }
    Component.onCompleted: refreshStatus()

    ListModel { id: chat }
    function push(role, text) { chat.append({ role: role, text: text }); Qt.callLater(() => list.positionViewAtEnd()) }
    function addNote(text) { push("note", text) }
    function addWatchCard(w) { push("watch", "Watching " + (w.title || w.host) + "\n" + w.condition) }
    function pageLoaded(t) {}

    function send(text) {
        text = text.trim()
        if (!text.length || busy) return
        refreshStatus()
        push("user", text)
        history = history.concat([{ role: "user", content: text }])
        steps = 0
        ask()
    }
    function ask() {
        busy = true
        reqId = reqId + 1
        push("assistant", "")
        const t = host.currentTab
        const go = page => browser.agentSend(reqId, JSON.stringify(history), page ? JSON.stringify(page) : "", true)
        if (readPage && t && !t.blank) host.readPage(t, go); else go(null)
    }
    function onDelta(id, text) {
        if (id !== reqId || !chat.count) return
        const i = chat.count - 1
        chat.setProperty(i, "text", chat.get(i).text + text)
        list.positionViewAtEnd()
    }
    function onFailed(id, error) {
        if (id !== reqId) return
        busy = false
        if (chat.count && chat.get(chat.count - 1).role === "assistant" && !chat.get(chat.count - 1).text.length) chat.remove(chat.count - 1)
        push("error", error)
    }
    function onFinished(id, r) {
        if (id !== reqId) return
        const last = chat.count - 1
        if (r.text && r.text.length) chat.setProperty(last, "text", r.text)
        else if (!r.calls.length) chat.setProperty(last, "text", r.cancelled ? "(stopped)" : "(no answer)")
        else chat.remove(last)
        if (r.cancelled || !r.calls.length) {
            history = history.concat([{ role: "assistant", content: r.text || "" }])
            busy = false
            return
        }
        history = history.concat([{ role: "assistant", content: r.text && r.text.length ? r.text : null,
            tool_calls: r.calls.map(c => ({ id: c.id, type: "function", function: { name: c.name, arguments: c.arguments } })) }])
        pendingCalls = r.calls.slice()
        runNext()
    }
    function describe(name, a) {
        switch (name) {
        case "open_url": return "Open " + a.url
        case "search_web": return "Search the web for \u201c" + a.query + "\u201d"
        case "click": return "Click \u201c" + a.text + "\u201d"
        case "type_text": return "Type \u201c" + a.text + "\u201d into " + a.field + (a.submit ? " and submit" : "")
        case "scroll": return "Scroll " + a.direction
        case "find_in_page": return "Find \u201c" + a.text + "\u201d"
        case "watch_page": return "Watch this tab for: " + a.condition
        }
        return name
    }
    function runNext() {
        if (!pendingCalls.length) {
            steps++
            if (steps >= maxSteps) { push("note", "Stopped after " + maxSteps + " steps."); busy = false; return }
            ask()
            return
        }
        const c = pendingCalls[0]
        pendingCalls = pendingCalls.slice(1)
        let a = {}
        try { a = JSON.parse(c.arguments || "{}") } catch (e) {}
        const run = () => {
            push("tool", describe(c.name, a))
            host.runTool(c.name, a, result => {
                chat.setProperty(chat.count - 1, "text", describe(c.name, a) + "\n\u2192 " + result)
                history = history.concat([{ role: "tool", tool_call_id: c.id, content: String(result) }])
                runNext()
            })
        }
        const risky = c.name === "click" || c.name === "type_text"
        if (risky && status.confirmActions !== false) {
            push("confirm", describe(c.name, a))
            confirmCb = ok => {
                chat.remove(chat.count - 1)
                if (ok) run()
                else { history = history.concat([{ role: "tool", tool_call_id: c.id, content: "The user declined." }]); push("note", "Declined: " + describe(c.name, a)); runNext() }
            }
        } else run()
    }
    function stop() {
        browser.agentCancel(reqId)
        if (confirmCb) { const cb = confirmCb; confirmCb = null; pendingCalls = []; cb(false) }
        busy = false
    }
    function clear() { stop(); chat.clear(); history = [] }

    Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: panel.pal.muted; opacity: 0.5 }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Text { text: "\u2726 Agent"; color: panel.accent; font.family: panel.pal.font; font.bold: true; font.pixelSize: panel.pal.fontSize + 2 }
            Text { Layout.fillWidth: true; text: panel.status.model || ""; color: panel.pal.fgDark; font.family: panel.pal.font; font.pixelSize: panel.pal.fontSize - 2; elide: Text.ElideRight }
            Widgets.Btn { pal: panel.pal; text: "Clear"; onClicked: panel.clear() }
            Widgets.Btn { pal: panel.pal; text: "\u2715"; tip: "Close (Ctrl+Shift+A)"; onClicked: panel.host.toggleAgent() }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: panel.status.ready === false
            implicitHeight: notReady.implicitHeight + 16
            radius: 8
            color: panel.pal.bgDarker
            border.color: panel.pal.yellow
            Text {
                id: notReady
                anchors.fill: parent
                anchors.margins: 8
                wrapMode: Text.WordWrap
                color: panel.pal.fg
                font.family: panel.pal.font
                text: "Not set up yet. Put your API key in the " + (panel.status.envVar || "QI_AGENT_API_KEY") +
                      " environment variable (or set agent.api_key_command in config.toml), or point agent.endpoint at a local OpenAI-compatible server. Endpoint: " + (panel.status.endpoint || "")
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8
            model: chat
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                id: bubble
                required property string role
                required property string text
                required property int index
                width: list.width
                implicitHeight: body.implicitHeight + (role === "confirm" ? 52 : 16)
                radius: 8
                color: role === "user" ? panel.pal.bgLighter : (role === "assistant" ? "transparent" : panel.pal.bgDarker)
                border.width: role === "confirm" || role === "watch" ? 1 : 0
                border.color: role === "confirm" ? panel.pal.yellow : panel.accent
                TextEdit {
                    id: body
                    x: 8; y: 8
                    width: parent.width - 16
                    readOnly: true
                    selectByMouse: true
                    wrapMode: Text.Wrap
                    textFormat: bubble.role === "assistant" ? TextEdit.MarkdownText : TextEdit.PlainText
                    text: bubble.role === "confirm" ? "Allow the agent to " + bubble.text.charAt(0).toLowerCase() + bubble.text.slice(1) + "?"
                        : bubble.role === "assistant" && !bubble.text.length ? "\u2026" : bubble.text
                    color: bubble.role === "error" ? panel.pal.red : (bubble.role === "tool" || bubble.role === "note" ? panel.pal.fgDark : panel.pal.fg)
                    font.family: panel.pal.font
                    font.pixelSize: panel.pal.fontSize
                    onLinkActivated: link => panel.host.newTab(link, true)
                }
                RowLayout {
                    visible: bubble.role === "confirm"
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    anchors.margins: 8
                    Widgets.Btn { pal: panel.pal; text: "Allow"; primary: true; onClicked: { const cb = panel.confirmCb; panel.confirmCb = null; if (cb) cb(true) } }
                    Widgets.Btn { pal: panel.pal; text: "Don't"; onClicked: { const cb = panel.confirmCb; panel.confirmCb = null; if (cb) cb(false) } }
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 6
            visible: chat.count === 0
            Repeater {
                model: ["Summarize this page", "What are the key points?", "Explain the selection", "Find related reading", "Watch this page for a price drop"]
                delegate: Widgets.Btn { required property string modelData; pal: panel.pal; text: modelData; onClicked: panel.send(modelData) }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Widgets.Toggle { pal: panel.pal; text: "Read this tab"; checked: panel.readPage; onToggled: panel.readPage = checked }
            Item { Layout.fillWidth: true }
            Text {
                text: panel.host.currentTab && panel.host.currentTab.isPrivate ? "private tab: not shared" : ""
                color: panel.pal.fgDark; font.family: panel.pal.font; font.pixelSize: panel.pal.fontSize - 2
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.min(140, Math.max(40, input.implicitHeight + 14))
            radius: 9
            color: panel.pal.bgDarker
            border.color: input.activeFocus ? panel.accent : panel.pal.muted
            ScrollView {
                anchors.fill: parent
                anchors.margins: 4
                anchors.rightMargin: 64
                TextArea {
                    id: input
                    placeholderText: "Ask about this page\u2026"
                    placeholderTextColor: panel.pal.fgDark
                    color: panel.pal.fgBright
                    font.family: panel.pal.font
                    font.pixelSize: panel.pal.fontSize
                    wrapMode: TextEdit.Wrap
                    background: null
                    Keys.onReturnPressed: event => {
                        if (event.modifiers & Qt.ShiftModifier) { event.accepted = false; return }
                        panel.send(text); text = ""
                    }
                    Keys.onEscapePressed: panel.host.toggleAgent()
                }
            }
            Widgets.Btn {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: 6
                pal: panel.pal
                primary: !panel.busy
                text: panel.busy ? "Stop" : "Send"
                onClicked: if (panel.busy) panel.stop(); else { panel.send(input.text); input.text = "" }
            }
        }
    }
}
