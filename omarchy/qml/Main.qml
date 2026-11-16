// Omaweb's window. QML draws; Rust (the Browser object) decides.
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Window
import QtWebEngine
import app.omaweb

ApplicationWindow {
    id: win
    width: 1280
    height: 820
    visible: true
    color: pal.bg
    flags: frameless ? (Qt.Window | Qt.FramelessWindowHint) : Qt.Window
    title: (currentTab && currentTab.title ? currentTab.title + " — " : "") + "Omaweb"

    // ---- Rust core -------------------------------------------------------
    Browser {
        id: browser
        onOpenRequested: (url, isPrivate) => win.openTab(url, true, isPrivate)
        onFocusRequested: { win.raise(); win.requestActivate() }
    }

    readonly property var theme: browser.themeJson.length ? JSON.parse(browser.themeJson) : null
    readonly property var cfg: browser.configJson.length ? JSON.parse(browser.configJson) : ({})
    // Chromeless by default: tabs = "sidebar" unless the config says "top".
    readonly property bool sidebarMode: cfg.tabs !== "top"
    readonly property bool frameless: cfg.frameless !== false
    readonly property bool xcb: Qt.platform.pluginName === "xcb"
    property bool sidebarPinned: false
    property bool sidebarPeek: false
    property bool compact: false
    property bool chromePeek: false
    readonly property bool chromeShown: !compact || chromePeek

    // ---- Omarchy palette, live --------------------------------------------
    QtObject {
        id: pal
        function c(k, d) { return win.theme && win.theme.colors[k] ? win.theme.colors[k] : d }
        readonly property bool dark: win.theme ? win.theme.dark : true
        readonly property string font: win.theme ? win.theme.font : "monospace"
        readonly property string name: win.theme ? win.theme.name : ""
        property color bg: c("background", "#1a1b26")
        readonly property color bgDark: c("dark_background", "#13141c")
        readonly property color bgDarker: c("darker_background", "#0e0e14")
        readonly property color bgLighter: c("lighter_background", "#24283b")
        property color fg: c("foreground", "#a9b1d6")
        readonly property color fgDark: c("dark_foreground", "#565f89")
        readonly property color fgBright: c("bright_foreground", "#c0caf5")
        property color accent: c("accent", "#7aa2f7")
        readonly property color onAccent: c("on_accent", "#1a1b26")
        readonly property color selection: c("selection", "#292e42")
        readonly property color muted: c("muted", "#414868")
        readonly property color red: c("red", "#f7768e")
        readonly property color green: c("green", "#9ece6a")
        readonly property color yellow: c("yellow", "#e0af68")
        readonly property int fontSize: 12
        Behavior on bg { ColorAnimation { duration: 180 } }
        Behavior on accent { ColorAnimation { duration: 180 } }
        Behavior on fg { ColorAnimation { duration: 180 } }
    }

    font.family: pal.font
    font.pixelSize: pal.fontSize

    // ---- Profiles ----------------------------------------------------------
    WebEngineProfilePrototype {
        id: persistentProto
        storageName: "omaweb"
        httpCacheType: WebEngineProfile.DiskHttpCache
        persistentCookiesPolicy: WebEngineProfile.AllowPersistentCookies
    }
    WebEngineProfilePrototype { id: privateProto }
    // instance() only works once the prototypes are complete, so the
    // profiles are fetched when the window finishes loading.
    property WebEngineProfile profile: null
    property WebEngineProfile privateProfile: null

    Connections {
        target: win.profile
        function onDownloadRequested(download) { win.acceptDownload(download) }
        function onDownloadFinished(download) { win.downloadDone(download) }
    }
    Connections {
        target: win.privateProfile
        function onDownloadRequested(download) { win.acceptDownload(download) }
        function onDownloadFinished(download) { win.downloadDone(download) }
    }
    function acceptDownload(d) {
        d.accept()
        status.show("Downloading " + d.downloadFileName + " to " + d.downloadDirectory)
    }
    function downloadDone(d) {
        if (d.state === WebEngineDownloadRequest.DownloadCompleted)
            browser.notify("Downloaded " + d.downloadFileName, d.downloadDirectory)
        else
            browser.notify("Download failed", d.downloadFileName + ": " + d.interruptReasonString)
    }

    // ---- Tabs --------------------------------------------------------------
    property var tabs: []
    property int current: -1
    readonly property var currentTab: current >= 0 && current < tabs.length ? tabs[current] : null
    property var closed: []
    property var fullscreenTab: null
    property bool started: false

    Component { id: tabComponent; BrowserTab {} }

    function openTab(url, focus, isPrivate, at) {
        const t = tabComponent.createObject(viewArea, {
            pal: pal, browser: browser,
            profile: isPrivate ? privateProfile : profile,
            isPrivate: !!isPrivate, zoom: cfg.zoom || 1.0
        })
        t.newTabRequested.connect((request) => {
            const bg = request.destination === WebEngineNewWindowRequest.InNewBackgroundTab
            const nt = win.openTab("", !bg, t.isPrivate, win.tabs.indexOf(t) + 1)
            request.openIn(nt.view)
        })
        t.closeRequested.connect(() => win.closeTab(win.tabs.indexOf(t)))
        t.fullScreenChanged.connect((on) => {
            win.fullscreenTab = on ? t : null
            if (on) win.showFullScreen(); else win.showNormal()
        })
        t.changed.connect(win.saveSoon)
        const list = tabs.slice()
        const idx = at === undefined ? list.length : Math.min(at, list.length)
        list.splice(idx, 0, t)
        tabs = list
        if (focus || current < 0) select(idx)
        else if (idx <= current) current += 1
        if (url && url.length) t.load(url)
        else if (focus) Qt.callLater(focusOmnibox)
        saveSoon()
        return t
    }

    function select(i) {
        if (i < 0 || i >= tabs.length) return
        current = i
        for (let k = 0; k < tabs.length; ++k) tabs[k].active = (k === i)
        if (!tabs[i].url.toString().length || tabs[i].url.toString() === "about:blank") focusOmnibox()
        else tabs[i].view.forceActiveFocus()
        saveSoon()
    }

    function closeTab(i) {
        if (i < 0 || i >= tabs.length) return
        const t = tabs[i]
        if (!t.isPrivate && t.url.toString().length) {
            closed = closed.concat([t.url.toString()]).slice(-25)
        }
        const list = tabs.slice()
        list.splice(i, 1)
        tabs = list
        t.destroy()
        if (tabs.length === 0) { Qt.quit(); return }
        select(Math.min(i, tabs.length - 1))
    }

    function reopenClosed() {
        if (!closed.length) return
        const list = closed.slice()
        const url = list.pop()
        closed = list
        openTab(url, true, false, current + 1)
    }

    function moveTab(from, to) {
        if (to < 0 || to >= tabs.length || from === to) return
        const list = tabs.slice()
        const t = list.splice(from, 1)[0]
        list.splice(to, 0, t)
        tabs = list
        current = to
        saveSoon()
    }

    function go(text) {
        const url = browser.resolve(text)
        if (!url.length || !currentTab) return
        currentTab.load(url)
        currentTab.view.forceActiveFocus()
        chromePeek = false
    }

    function focusOmnibox(tabsOnly) {
        if (sidebarMode) { palette.open(tabsOnly); return }
        chromePeek = compact
        omnibox.focusField(tabsOnly)
    }
    function reloadOrStop() {
        if (!currentTab) return
        if (currentTab.loading) currentTab.view.stop(); else currentTab.view.reload()
    }

    Timer { id: saveTimer; interval: 800; onTriggered: win.saveNow() }
    function saveSoon() { if (started) saveTimer.restart() }
    function saveNow() {
        const out = { tabs: [], current: 0 }
        let cur = 0
        for (let i = 0; i < tabs.length; ++i) {
            const t = tabs[i]
            if (t.isPrivate) continue
            if (i === current) cur = out.tabs.length
            out.tabs.push({ url: t.url.toString(), title: t.title })
        }
        out.current = cur
        browser.saveSession(JSON.stringify(out))
    }
    onClosing: saveNow()

    Component.onCompleted: {
        profile = persistentProto.instance()
        privateProfile = privateProto.instance()
        browser.start()
        compact = !!cfg.compact
        sidebarPinned = !!cfg.pin_sidebar
        const init = JSON.parse(browser.initialJson)
        for (const t of init.tabs) openTab(t.url, false, !!t.private)
        select(Math.min(init.current, tabs.length - 1))
        started = true
    }

    // ---- Keyboard: Ctrl-based, so Super stays Hyprland's -----------------
    Shortcut { sequences: ["Ctrl+L", "Alt+D", "F6"]; context: Qt.ApplicationShortcut; onActivated: win.focusOmnibox() }
    Shortcut { sequences: ["Ctrl+K"]; context: Qt.ApplicationShortcut; onActivated: win.focusOmnibox(true) }
    Shortcut { sequences: ["Ctrl+T"]; context: Qt.ApplicationShortcut; onActivated: win.openTab("", true, false, win.current + 1) }
    Shortcut { sequences: ["Ctrl+Shift+N"]; context: Qt.ApplicationShortcut; onActivated: win.openTab("", true, true, win.current + 1) }
    Shortcut { sequences: ["Ctrl+W", "Ctrl+F4"]; context: Qt.ApplicationShortcut; onActivated: win.closeTab(win.current) }
    Shortcut { sequences: ["Ctrl+Shift+T"]; context: Qt.ApplicationShortcut; onActivated: win.reopenClosed() }
    Shortcut { sequences: ["Ctrl+Tab", "Ctrl+PgDown"]; context: Qt.ApplicationShortcut; onActivated: win.select((win.current + 1) % win.tabs.length) }
    Shortcut { sequences: ["Ctrl+Shift+Tab", "Ctrl+PgUp"]; context: Qt.ApplicationShortcut; onActivated: win.select((win.current - 1 + win.tabs.length) % win.tabs.length) }
    Shortcut { sequences: ["Ctrl+Shift+PgDown"]; context: Qt.ApplicationShortcut; onActivated: win.moveTab(win.current, win.current + 1) }
    Shortcut { sequences: ["Ctrl+Shift+PgUp"]; context: Qt.ApplicationShortcut; onActivated: win.moveTab(win.current, win.current - 1) }
    Repeater {
        model: 9
        delegate: Item {
            required property int index
            Shortcut {
                sequences: ["Ctrl+" + (index + 1), "Alt+" + (index + 1)]
                context: Qt.ApplicationShortcut
                onActivated: win.select(index === 8 ? win.tabs.length - 1 : index)
            }
        }
    }
    Shortcut { sequences: ["Alt+Left", "Back"]; context: Qt.ApplicationShortcut; onActivated: if (win.currentTab) win.currentTab.view.goBack() }
    Shortcut { sequences: ["Alt+Right", "Forward"]; context: Qt.ApplicationShortcut; onActivated: if (win.currentTab) win.currentTab.view.goForward() }
    Shortcut { sequences: ["Ctrl+R", "F5"]; context: Qt.ApplicationShortcut; onActivated: if (win.currentTab) win.currentTab.view.reload() }
    Shortcut { sequences: ["Ctrl+Shift+R", "Shift+F5"]; context: Qt.ApplicationShortcut; onActivated: if (win.currentTab) win.currentTab.view.reloadAndBypassCache() }
    Shortcut { sequences: ["Escape"]; enabled: win.currentTab !== null && win.currentTab.loading && !palette.visible; onActivated: win.currentTab.view.stop() }
    Shortcut { sequences: ["Ctrl+F"]; context: Qt.ApplicationShortcut; onActivated: findBar.open() }
    Shortcut { sequences: ["Ctrl+G", "F3"]; context: Qt.ApplicationShortcut; onActivated: findBar.next(false) }
    Shortcut { sequences: ["Ctrl+Shift+G", "Shift+F3"]; context: Qt.ApplicationShortcut; onActivated: findBar.next(true) }
    Shortcut { sequences: ["Ctrl+=", "Ctrl++"]; context: Qt.ApplicationShortcut; onActivated: if (win.currentTab) win.currentTab.zoomBy(0.1) }
    Shortcut { sequences: ["Ctrl+-"]; context: Qt.ApplicationShortcut; onActivated: if (win.currentTab) win.currentTab.zoomBy(-0.1) }
    Shortcut { sequences: ["Ctrl+0"]; context: Qt.ApplicationShortcut; onActivated: if (win.currentTab) win.currentTab.zoom = (win.cfg.zoom || 1.0) }
    Shortcut { sequences: ["Ctrl+Shift+B"]; context: Qt.ApplicationShortcut; onActivated: win.toggleSidebar() }
    Shortcut { sequences: ["F11"]; context: Qt.ApplicationShortcut; onActivated: win.visibility === Window.FullScreen ? win.showNormal() : win.showFullScreen() }
    Shortcut { sequences: ["Ctrl+U"]; context: Qt.ApplicationShortcut; onActivated: if (win.currentTab) win.openTab("view-source:" + win.currentTab.url, true, win.currentTab.isPrivate, win.current + 1) }
    Shortcut { sequences: ["F12", "Ctrl+Shift+I"]; context: Qt.ApplicationShortcut; onActivated: if (win.currentTab) win.currentTab.toggleDevTools() }
    Shortcut { sequences: ["Ctrl+Shift+C"]; context: Qt.ApplicationShortcut; onActivated: if (win.currentTab) { clip.text = win.currentTab.url.toString(); clip.selectAll(); clip.copy(); status.show("Copied " + clip.text) } }
    Shortcut { sequences: ["Ctrl+Q"]; context: Qt.ApplicationShortcut; onActivated: { win.saveNow(); Qt.quit() } }
    TextEdit { id: clip; visible: false }

    // ---- Layout ------------------------------------------------------------
    // Default (tabs = "sidebar"): no frame, no toolbar, the page edge to
    // edge. The sidebar slides over the page from the left edge, or sits
    // beside it when pinned; addresses go through the palette (Ctrl+L).
    // tabs = "top" keeps the classic tab strip and address bar.
    readonly property int sidebarWidth: 248
    readonly property bool sidebarOpen: sidebarMode && fullscreenTab === null && (sidebarPinned || sidebarPeek)
    readonly property bool resizable: frameless && visibility === Window.Windowed && fullscreenTab === null

    function toggleSidebar() {
        if (!sidebarMode) { compact = !compact; return }
        if (sidebarPinned) { sidebarPinned = false; sidebarPeek = sidebar.hovered }
        else { sidebarPinned = true; sidebarPeek = false }
    }
    function toggleMaximized() {
        if (visibility === Window.Maximized) showNormal(); else showMaximized()
    }

    Timer {
        id: peekTimer
        interval: 350
        onTriggered: if (!sidebar.hovered && !leftEdge.containsMouse && !palette.visible) win.sidebarPeek = false
    }
    Connections {
        target: sidebar
        function onHoveredChanged() { if (!sidebar.hovered) peekTimer.restart() }
    }

    // Classic chrome, tabs = "top" only.
    ColumnLayout {
        id: topChrome
        visible: !win.sidebarMode && win.chromeShown && win.fullscreenTab === null
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: visible ? implicitHeight : 0
        spacing: 0
        z: 10

        TabStrip {
            vertical: false
            pal: pal
            tabs: win.tabs
            current: win.current
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            onActivate: i => win.select(i)
            onCloseTab: i => win.closeTab(i)
            onNewTab: win.openTab("", true, false)
            // Frameless: drag the strip's empty space to move the window.
            DragHandler {
                target: null
                enabled: win.frameless
                onActiveChanged: if (active) win.startSystemMove()
            }
        }

        Rectangle {
            id: toolbar
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            color: pal.bg

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                spacing: 2

                NavButton { glyph: "\u2190"; tip: "Back (Alt+Left)"; enabled: win.currentTab && win.currentTab.canGoBack; onClicked: win.currentTab.view.goBack() }
                NavButton { glyph: "\u2192"; tip: "Forward (Alt+Right)"; enabled: win.currentTab && win.currentTab.canGoForward; onClicked: win.currentTab.view.goForward() }
                NavButton {
                    glyph: win.currentTab && win.currentTab.loading ? "\u2715" : "\u21bb"
                    tip: win.currentTab && win.currentTab.loading ? "Stop (Esc)" : "Reload (Ctrl+R)"
                    enabled: win.currentTab !== null
                    onClicked: win.reloadOrStop()
                }

                Omnibox {
                    id: omnibox
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                    pal: pal
                    browser: browser
                    tabs: win.tabs
                    currentTab: win.currentTab
                    onGo: text => win.go(text)
                    onSwitchTo: i => win.select(i)
                    onDismissed: { win.chromePeek = false; if (win.currentTab) win.currentTab.view.forceActiveFocus() }
                }

                Text {
                    visible: win.currentTab && Math.abs(win.currentTab.zoom - 1.0) > 0.01
                    text: win.currentTab ? Math.round(win.currentTab.zoom * 100) + "%" : ""
                    color: pal.fgDark
                    font.family: pal.font
                    font.pixelSize: pal.fontSize - 1
                    Layout.leftMargin: 6
                }
                Text {
                    visible: win.currentTab && win.currentTab.isPrivate
                    text: "private"
                    color: pal.accent
                    font.family: pal.font
                    font.pixelSize: pal.fontSize - 1
                    Layout.leftMargin: 6
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: pal.muted; opacity: 0.35 }
        }
    }

    // The page, edge to edge.
    Item {
        id: pageArea
        anchors.top: topChrome.bottom
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.left: parent.left
        anchors.leftMargin: win.sidebarMode && win.sidebarPinned && win.fullscreenTab === null ? win.sidebarWidth : 0
        Behavior on anchors.leftMargin { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Item {
            id: viewArea
            anchors.fill: parent
            clip: true

            StartPage {
                anchors.fill: parent
                visible: win.currentTab !== null && win.currentTab.blank
                pal: pal
                browser: browser
                isPrivate: win.currentTab !== null && win.currentTab.isPrivate
                onOpen: url => win.go(url)
                z: 5
            }
        }

        // Load progress: a hairline in the accent along the top of the page.
        Rectangle {
            z: 15
            anchors.top: parent.top
            anchors.left: parent.left
            height: 2
            color: pal.accent
            width: win.currentTab && win.currentTab.loading ? parent.width * win.currentTab.progress / 100 : 0
            visible: width > 0
            Behavior on width { NumberAnimation { duration: 120 } }
        }

        // Find floats over the page, top right.
        FindBar {
            id: findBar
            z: 30
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 10
            width: Math.min(460, parent.width - 20)
            height: 38
            radius: 8
            border.color: pal.muted
            border.width: 1
            pal: pal
            view: win.currentTab ? win.currentTab.view : null
        }

        // Private / zoom badge, top right, only in the chromeless layout.
        Rectangle {
            z: 25
            visible: win.sidebarMode && !win.sidebarOpen && !findBar.visible && badge.text.length > 0
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 10
            width: badge.implicitWidth + 16
            height: badge.implicitHeight + 8
            radius: 6
            color: pal.bgDark
            opacity: 0.9
            Text {
                id: badge
                anchors.centerIn: parent
                text: [
                    win.currentTab && win.currentTab.isPrivate ? "private" : "",
                    win.currentTab && Math.abs(win.currentTab.zoom - 1.0) > 0.01 ? Math.round(win.currentTab.zoom * 100) + "%" : ""
                ].filter(s => s.length).join("  ")
                color: pal.accent
                font.family: pal.font
                font.pixelSize: pal.fontSize - 1
            }
        }

        // Hover link / status line, bottom-left like every browser.
        Rectangle {
            id: status
            z: 20
            property string message: ""
            readonly property string shown: message.length ? message : (win.currentTab ? win.currentTab.hoveredLink : "")
            function show(m) { message = m; statusTimer.restart() }
            visible: shown.length > 0
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.leftMargin: win.sidebarPeek && !win.sidebarPinned ? win.sidebarWidth : 0
            width: Math.min(statusText.implicitWidth + 16, parent.width * 0.7)
            height: statusText.implicitHeight + 8
            color: pal.bgDark
            border.color: pal.muted
            border.width: 1
            Text {
                id: statusText
                anchors.centerIn: parent
                width: parent.width - 16
                elide: Text.ElideMiddle
                text: status.shown
                color: pal.fg
                font.family: pal.font
                font.pixelSize: pal.fontSize - 1
            }
            Timer { id: statusTimer; interval: 2500; onTriggered: status.message = "" }
        }
    }

    // ---- Sidebar ------------------------------------------------------------
    Sidebar {
        id: sidebar
        z: 50
        visible: win.sidebarMode && win.fullscreenTab === null && x > -width
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: win.sidebarWidth
        x: win.sidebarOpen ? 0 : -width - 16
        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        floating: !win.sidebarPinned
        pal: pal
        tabs: win.tabs
        current: win.current
        currentTab: win.currentTab
        pinned: win.sidebarPinned
        onActivate: i => win.select(i)
        onCloseTab: i => win.closeTab(i)
        onNewTab: win.openTab("", true, false, win.current + 1)
        onOpenPalette: win.focusOmnibox()
        onTogglePin: win.toggleSidebar()
        onBack: if (win.currentTab) win.currentTab.view.goBack()
        onForward: if (win.currentTab) win.currentTab.view.goForward()
        onReload: win.reloadOrStop()
        onWindowMove: win.startSystemMove()
        onWindowToggleMaximized: win.toggleMaximized()
    }

    // ---- Command palette: the address field, on demand -----------------------
    Item {
        id: palette
        anchors.fill: parent
        z: 100
        visible: false
        function open(tabsOnly) {
            visible = true
            paletteBox.focusField(tabsOnly)
        }
        function close() {
            if (!visible) return
            visible = false
            if (win.currentTab && !win.currentTab.blank) win.currentTab.view.forceActiveFocus()
            if (!sidebar.hovered) peekTimer.restart()
        }

        Rectangle { anchors.fill: parent; color: "black"; opacity: 0.28 }
        MouseArea { anchors.fill: parent; onClicked: palette.close() }

        Rectangle {
            id: card
            width: Math.min(680, parent.width - 60)
            height: 48
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height * 0.16)
            radius: 10
            color: pal.bgDark
            border.width: 1
            border.color: pal.accent
            MouseArea { anchors.fill: parent }  // clicks on the card stay here

            Omnibox {
                id: paletteBox
                anchors.fill: parent
                anchors.margins: 6
                pal: pal
                browser: browser
                tabs: win.tabs
                currentTab: win.currentTab
                onGo: text => { palette.close(); win.go(text) }
                onSwitchTo: i => { palette.close(); win.select(i) }
                onDismissed: palette.close()
                onEditingChanged: if (!editing) Qt.callLater(() => { if (!paletteBox.editing) palette.close() })
            }
        }
    }

    // ---- Frameless window: edges resize (and the left edge reveals tabs) ----
    MouseArea {
        id: leftEdge
        z: 200
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: win.resizable && win.xcb ? 4 : 2
        visible: (win.sidebarMode && !win.sidebarPinned && win.fullscreenTab === null) || win.resizable
        hoverEnabled: true
        acceptedButtons: win.resizable && win.xcb ? Qt.LeftButton : Qt.NoButton
        cursorShape: win.resizable && win.xcb ? Qt.SizeHorCursor : Qt.ArrowCursor
        onEntered: if (win.sidebarMode && !win.sidebarPinned && win.fullscreenTab === null) { win.sidebarPeek = true; peekTimer.stop() }
        onExited: peekTimer.restart()
        onPressed: win.startSystemResize(Qt.LeftEdge)
    }
    Repeater {
        // Right, top, bottom and the corners. X11 only: Hyprland tiles and
        // resizes with Super+drag, and these would steal page clicks there.
        model: win.resizable && win.xcb ? [
            { e: Qt.RightEdge, c: Qt.SizeHorCursor }, { e: Qt.TopEdge, c: Qt.SizeVerCursor },
            { e: Qt.BottomEdge, c: Qt.SizeVerCursor },
            { e: Qt.TopEdge | Qt.LeftEdge, c: Qt.SizeFDiagCursor }, { e: Qt.BottomEdge | Qt.RightEdge, c: Qt.SizeFDiagCursor },
            { e: Qt.TopEdge | Qt.RightEdge, c: Qt.SizeBDiagCursor }, { e: Qt.BottomEdge | Qt.LeftEdge, c: Qt.SizeBDiagCursor }
        ] : []
        delegate: MouseArea {
            required property var modelData
            readonly property int e: modelData.e
            readonly property int g: 4
            readonly property int corner: 10
            z: 201
            x: (e & Qt.RightEdge) ? win.width - (e === Qt.RightEdge ? g : corner) : 0
            y: (e & Qt.BottomEdge) ? win.height - (e === Qt.BottomEdge ? g : corner) : 0
            width: (e === Qt.TopEdge || e === Qt.BottomEdge) ? win.width : (e === Qt.RightEdge ? g : corner)
            height: (e === Qt.RightEdge) ? win.height : ((e === Qt.TopEdge || e === Qt.BottomEdge) ? g : corner)
            cursorShape: modelData.c
            onPressed: win.startSystemResize(e)
        }
    }

    component NavButton: AbstractButton {
        id: nb
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
        background: Rectangle { color: nb.hovered ? pal.bgLighter : "transparent"; radius: 0 }
        contentItem: Text {
            text: nb.glyph
            color: nb.hovered ? pal.fgBright : pal.fg
            font.family: pal.font
            font.pixelSize: 15
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
