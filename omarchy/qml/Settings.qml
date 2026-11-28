// Settings (Ctrl+,): every config.toml key that makes sense to flip, plus
// profiles, extensions, saved passwords and the Chrome importer. Writes go
// through Rust (config::set_value), which keeps the file's comments. The
// agent's API key is never typed here: it comes from the environment.
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs
import app.qi.native

Item {
    id: set
    property QtObject pal
    property QtObject browser
    property var host
    visible: false
    property string section: "general"
    readonly property var cfg: host.cfg
    property string message: ""
    property string extMessage: ""
    property string extProfile: "Default"
    property var importReport: null
    property string importTarget: "Default"
    property bool importing: false

    function show(s) {
        section = s || "general"
        extProfile = host.profileOfCurrent() === "private" ? host.defaultProfile : host.profileOfCurrent()
        importTarget = extProfile
        visible = true
    }
    function close() { visible = false; if (host.currentTab) host.currentTab.view.forceActiveFocus() }
    function put(key, value) {
        const err = browser.setSetting(key, JSON.stringify(value))
        message = err.length ? err : "Saved to " + browser.configPath()
        msgTimer.restart()
    }
    function extensionMessage(t) { extMessage = t }
    function importDone(profile, report) {
        importing = false
        importReport = JSON.parse(report)
        const dirs = importReport.extensionDirs || []
        const em = host.engineProfile(profile).extensionManager
        if (em) for (const d of dirs) em.installExtension(d)
        host.rev++
    }
    Timer { id: msgTimer; interval: 4000; onTriggered: set.message = "" }
    Shortcut { sequences: ["Escape"]; enabled: set.visible; onActivated: set.close() }

    Rectangle { anchors.fill: parent; color: "black"; opacity: 0.35 }
    MouseArea { anchors.fill: parent; onClicked: set.close() }

    component Section: ColumnLayout { spacing: 10; Layout.fillWidth: true }
    component Row2: RowLayout { spacing: 10; Layout.fillWidth: true }
    component Name: Text {
        color: set.pal.fg; font.family: set.pal.font; font.pixelSize: set.pal.fontSize
        Layout.preferredWidth: 220; wrapMode: Text.WordWrap
    }
    component Note: Text {
        color: set.pal.fgDark; font.family: set.pal.font; font.pixelSize: set.pal.fontSize - 1
        Layout.fillWidth: true; wrapMode: Text.WordWrap
    }
    component Head: Text {
        color: set.pal.fgBright; font.family: set.pal.font; font.pixelSize: set.pal.fontSize + 3; font.bold: true
        Layout.topMargin: 4
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 60, 980)
        height: Math.min(parent.height - 60, 760)
        radius: 12
        color: set.pal.bgDark
        border.color: set.pal.accent
        MouseArea { anchors.fill: parent }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 14

            ColumnLayout {
                Layout.preferredWidth: 190
                Layout.fillHeight: true
                spacing: 4
                Text { text: "Settings"; color: set.pal.fgBright; font.family: set.pal.font; font.bold: true; font.pixelSize: set.pal.fontSize + 4; Layout.bottomMargin: 8 }
                Repeater {
                    model: [["general", "General"], ["spaces", "Spaces & profiles"], ["agent", "Agent"], ["privacy", "Privacy & blocking"],
                            ["extensions", "Extensions"], ["passwords", "Passwords"], ["import", "Import from Chrome"], ["keys", "Keyboard"], ["about", "About"]]
                    delegate: AbstractButton {
                        id: nav
                        required property var modelData
                        Layout.fillWidth: true
                        height: 30
                        hoverEnabled: true
                        onClicked: set.section = modelData[0]
                        background: Rectangle { radius: 7; color: set.section === nav.modelData[0] ? set.pal.bgLighter : (nav.hovered ? set.pal.selection : "transparent") }
                        contentItem: Text { leftPadding: 10; text: nav.modelData[1]; verticalAlignment: Text.AlignVCenter; color: set.section === nav.modelData[0] ? set.pal.accent : set.pal.fg; font.family: set.pal.font }
                    }
                }
                Item { Layout.fillHeight: true }
                Note { text: set.message; color: set.pal.green }
                Widgets.Btn { pal: set.pal; text: "Close (Esc)"; Layout.fillWidth: true; onClicked: set.close() }
            }

            Rectangle { Layout.fillHeight: true; width: 1; color: set.pal.muted; opacity: 0.5 }

            ScrollView {
                id: scroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: scroll.availableWidth - 12
                    spacing: 14

                    // ---- General ----
                    Section {
                        visible: set.section === "general"
                        Head { text: "General" }
                        Row2 { Name { text: "Home page" } Widgets.Field { pal: set.pal; Layout.fillWidth: true; text: set.cfg.homepage || ""; onEditingFinished: set.put("homepage", text) } }
                        Row2 { Name { text: "Search ({} is the query)" } Widgets.Field { pal: set.pal; Layout.fillWidth: true; text: set.cfg.search || ""; onEditingFinished: set.put("search", text) } }
                        Row2 {
                            Name { text: "Tabs" }
                            ComboBox { model: ["sidebar", "top"]; currentIndex: set.cfg.tabs === "top" ? 1 : 0; onActivated: i => set.put("tabs", model[i]) }
                            Note { text: "\u201ctop\u201d brings back a tab strip and address bar (restart)." }
                        }
                        Widgets.Toggle { pal: set.pal; text: "Keep the sidebar pinned open at start"; checked: !!set.cfg.pin_sidebar; onToggled: set.put("pin_sidebar", checked) }
                        Widgets.Toggle { pal: set.pal; text: "No window frame (chromeless)"; checked: set.cfg.frameless !== false; onToggled: set.put("frameless", checked) }
                        Widgets.Toggle { pal: set.pal; text: "Restore tabs at start"; checked: set.cfg.restore_session !== false; onToggled: set.put("restore_session", checked) }
                        Widgets.Toggle { pal: set.pal; text: "Peek: open pop-up links in a preview card"; checked: set.cfg.peek !== false; onToggled: set.put("peek", checked) }
                        Widgets.Toggle { pal: set.pal; text: "Dark pages (force dark mode on every site)"; checked: !!set.cfg.force_dark; onToggled: set.put("force_dark", checked) }
                        Row2 {
                            Name { text: "Archive today\u2019s tabs after (hours, 0 = never)" }
                            SpinBox { from: 0; to: 720; value: Math.round(set.cfg.archive_after_hours === undefined ? 12 : set.cfg.archive_after_hours); editable: true; onValueModified: set.put("archive_after_hours", value) }
                        }
                        Row2 {
                            Name { text: "Default zoom (%)" }
                            SpinBox { from: 25; to: 500; stepSize: 10; value: Math.round((set.cfg.zoom || 1) * 100); editable: true; onValueModified: set.put("zoom", value / 100) }
                        }
                        Note { text: "Everything here is in " + set.browser.configPath() + "; edits there apply live too." }
                    }

                    // ---- Spaces & profiles ----
                    Section {
                        visible: set.section === "spaces"
                        Head { text: "Spaces" }
                        Note { text: "Each space has its own tabs and folders and a colour from the Omarchy theme, and opens its tabs in one profile (like Arc). Ctrl+Alt+1\u20269 and Ctrl+Alt+Left/Right switch." }
                        Repeater {
                            model: { set.host.rev; return set.host.ws.spaces }
                            delegate: Row2 {
                                id: sr
                                required property var modelData
                                Rectangle { width: 14; height: 14; radius: 7; color: set.host.spaceColor(sr.modelData.color) }
                                Widgets.Field { pal: set.pal; Layout.preferredWidth: 180; text: sr.modelData.name; onEditingFinished: if (text !== sr.modelData.name) set.host.op({ op: "update_space", id: sr.modelData.id, name: text }) }
                                ComboBox {
                                    model: ["accent", "blue", "magenta", "green", "yellow", "cyan", "red"]
                                    currentIndex: Math.max(0, model.indexOf(sr.modelData.color))
                                    onActivated: i => set.host.op({ op: "update_space", id: sr.modelData.id, color: model[i] })
                                }
                                ComboBox {
                                    Layout.preferredWidth: 160
                                    model: set.host.profiles.map(p => p.name)
                                    currentIndex: Math.max(0, model.indexOf(sr.modelData.profile))
                                    onActivated: i => set.host.setSpaceProfile(sr.modelData.id, model[i])
                                }
                                Widgets.Btn { pal: set.pal; text: "Remove"; danger: true; enabled: set.host.ws.spaces.length > 1; onClicked: set.host.op({ op: "remove_space", id: sr.modelData.id, now: set.host.nowSecs() }) }
                            }
                        }
                        Widgets.Btn { pal: set.pal; text: "New space"; onClicked: set.host.newSpace("Space " + (set.host.ws.spaces.length + 1)) }

                        Head { text: "Profiles" }
                        Note { text: "Each profile is its own browser: cookies, storage, cache, history, bookmarks, passwords and extensions are kept apart. Start one with qi --profile NAME." }
                        Repeater {
                            model: set.host.profiles
                            delegate: Row2 {
                                id: pr
                                required property var modelData
                                Text { text: pr.modelData.name + (pr.modelData.name === set.host.defaultProfile ? "  (default)" : ""); color: set.pal.fgBright; font.family: set.pal.font; Layout.preferredWidth: 200 }
                                Note { text: pr.modelData.storage_path.length ? pr.modelData.storage_path : "~/.local/share/qi/qi/QtWebEngine/qi" }
                                Widgets.Btn { pal: set.pal; text: "Make default"; visible: pr.modelData.name !== set.host.defaultProfile; onClicked: set.put("default_profile", pr.modelData.name) }
                                Widgets.Btn {
                                    pal: set.pal; text: "Remove"; danger: true; visible: pr.modelData.name !== "Default"
                                    enabled: !set.host.ws.spaces.some(s => s.profile === pr.modelData.name)
                                    tip: "Spaces using it must move to another profile first. Its data stays on disk."
                                    onClicked: set.browser.removeProfile(pr.modelData.name)
                                }
                            }
                        }
                        Row2 {
                            Widgets.Field { id: newProfile; pal: set.pal; Layout.preferredWidth: 220; placeholderText: "New profile name" }
                            Widgets.Btn { pal: set.pal; text: "Add profile"; enabled: newProfile.text.trim().length > 0; onClicked: { set.browser.addProfile(newProfile.text.trim()); newProfile.text = "" } }
                            Widgets.Btn { pal: set.pal; text: "Add with a space"; enabled: newProfile.text.trim().length > 0; onClicked: { const n = set.browser.addProfile(newProfile.text.trim()); set.host.newSpace(n, n); newProfile.text = "" } }
                        }
                    }

                    // ---- Agent ----
                    Section {
                        visible: set.section === "agent"
                        Head { text: "Agent" }
                        property var st: { set.visible; set.cfg; return JSON.parse(set.browser.agentStatus()) }
                        Note {
                            text: parent.st.ready ? "Ready \u2014 key from " + parent.st.keySource + "." : "No API key found. Export " + (set.cfg.agent ? set.cfg.agent.api_key_env : "QI_AGENT_API_KEY") + " before starting Qi, or set an api_key_command (e.g. a pass/secret-tool lookup)."
                            color: parent.st.ready ? set.pal.green : set.pal.yellow
                        }
                        Row2 { Name { text: "Endpoint (OpenAI-compatible)" } Widgets.Field { pal: set.pal; Layout.fillWidth: true; text: set.cfg.agent ? set.cfg.agent.endpoint : ""; onEditingFinished: set.put("agent.endpoint", text) } }
                        Row2 { Name { text: "Model" } Widgets.Field { pal: set.pal; Layout.fillWidth: true; text: set.cfg.agent ? set.cfg.agent.model : ""; onEditingFinished: set.put("agent.model", text) } }
                        Row2 { Name { text: "API key environment variable" } Widgets.Field { pal: set.pal; Layout.fillWidth: true; text: set.cfg.agent ? set.cfg.agent.api_key_env : ""; onEditingFinished: set.put("agent.api_key_env", text) } }
                        Row2 { Name { text: "API key command" } Widgets.Field { pal: set.pal; Layout.fillWidth: true; placeholderText: "secret-tool lookup service openai"; text: set.cfg.agent ? set.cfg.agent.api_key_command : ""; onEditingFinished: set.put("agent.api_key_command", text) } }
                        Row2 { Name { text: "Page text sent (characters)" } SpinBox { from: 500; to: 200000; stepSize: 1000; editable: true; value: set.cfg.agent ? set.cfg.agent.max_page_chars : 12000; onValueModified: set.put("agent.max_page_chars", value) } }
                        Row2 { Name { text: "Extra instructions" } Widgets.Field { pal: set.pal; Layout.fillWidth: true; text: set.cfg.agent ? set.cfg.agent.instructions : ""; onEditingFinished: set.put("agent.instructions", text) } }
                        Widgets.Toggle { pal: set.pal; text: "Ask before the agent clicks or types on a page"; checked: !set.cfg.agent || set.cfg.agent.confirm_actions !== false; onToggled: set.put("agent.confirm_actions", checked) }
                        Note { text: "The key is never stored by this screen. Private tabs are never sent. Local servers (Ollama, llama.cpp, LM Studio on localhost) need no key." }
                    }

                    // ---- Privacy ----
                    Section {
                        visible: set.section === "privacy"
                        Head { text: "Ads and trackers" }
                        Widgets.Toggle { pal: set.pal; text: "Block ads and trackers"; checked: !set.cfg.blocker || set.cfg.blocker.enabled !== false; onToggled: set.put("blocker.enabled", checked) }
                        Note { text: WebTools.listSize + " blocked hosts loaded \u00b7 " + WebTools.blockedTotal + " requests blocked this session. Hosts files and the ||domain^ rules of adblock lists work; cosmetic rules don't (use Hide something, Ctrl+Shift+H)." }
                        Name { text: "Filter lists (one URL or file per line)" }
                        TextArea {
                            id: listsArea
                            Layout.fillWidth: true
                            Layout.preferredHeight: 90
                            text: set.cfg.blocker ? set.cfg.blocker.lists.join("\n") : ""
                            color: set.pal.fgBright; font.family: set.pal.font
                            background: Rectangle { radius: 7; color: set.pal.bgDarker; border.color: set.pal.muted }
                        }
                        Row2 {
                            Widgets.Btn { pal: set.pal; text: "Save lists"; onClicked: set.put("blocker.lists", listsArea.text.split("\n").map(s => s.trim()).filter(s => s.length)) }
                            Widgets.Btn { pal: set.pal; text: "Update lists now"; onClicked: { set.browser.refreshBlocklist(true); set.message = "Updating\u2026" } }
                        }
                        Name { text: "Allowed sites (not blocked)" }
                        Widgets.Field { pal: set.pal; Layout.fillWidth: true; text: set.cfg.blocker ? set.cfg.blocker.allow.join(", ") : ""; onEditingFinished: set.put("blocker.allow", text.split(",").map(s => s.trim()).filter(s => s.length)) }
                        Head { text: "Site data" }
                        Row2 {
                            Widgets.Btn { pal: set.pal; text: "Clear cookies (" + set.extProfile + ")"; danger: true; onClicked: { WebTools.clearCookies(set.extProfile); set.message = "Cookies cleared" } }
                            Widgets.Btn { pal: set.pal; text: "Clear history (" + set.extProfile + ")"; danger: true; onClicked: { set.browser.clearHistory(set.extProfile); set.message = "History cleared" } }
                        }
                    }

                    // ---- Extensions ----
                    Section {
                        id: extSec
                        visible: set.section === "extensions"
                        Head { text: "Extensions" }
                        Row2 {
                            Name { text: "Profile" }
                            ComboBox { model: set.host.profiles.map(p => p.name); currentIndex: Math.max(0, model.indexOf(set.extProfile)); onActivated: i => set.extProfile = model[i] }
                        }
                        readonly property var em: { set.visible; const p = set.visible ? set.host.engineProfile(set.extProfile) : null; return p ? p.extensionManager : null }
                        property var list: []
                        function refresh() { list = extSec.em ? set.host.extensionsOf(set.extProfile) : [] }
                        onEmChanged: refresh()
                        Connections { target: set.host; function onExtRevChanged() { extSec.refresh() } }
                        Note {
                            text: "Chrome extensions run through Qt WebEngine\u2019s extension support (Qt 6.10+): they install, content scripts run and popups open, but chrome.tabs, windows, contextMenus, sidePanel, blocking webRequest and native messaging are missing, so most extensions only partly work or not at all. See the README for the tested list."
                        }
                        Row2 {
                            Widgets.Field { id: storeField; pal: set.pal; Layout.fillWidth: true; placeholderText: "Chrome Web Store link or extension id" }
                            Widgets.Btn { pal: set.pal; text: "Install"; primary: true; enabled: storeField.text.trim().length > 0; onClicked: set.host.installExtension(set.extProfile, storeField.text.trim()) }
                            Widgets.Btn { pal: set.pal; text: "Open the Web Store"; onClicked: { const h = set.host; set.close(); h.newTab("https://chromewebstore.google.com/", true) } }
                        }
                        Row2 {
                            Widgets.Btn { pal: set.pal; text: "Load unpacked folder\u2026"; onClicked: folderDialog.open() }
                            Widgets.Btn { pal: set.pal; text: "Install .crx / .zip\u2026"; onClicked: crxDialog.open() }
                        }
                        Note { text: set.extMessage; color: set.pal.accent; visible: text.length > 0 }
                        Repeater {
                            model: extSec.list
                            delegate: Rectangle {
                                id: er
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: erCol.implicitHeight + 16
                                radius: 8
                                color: set.pal.bgDarker
                                RowLayout {
                                    id: erCol
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    Image { source: set.browser.extensionIcon(er.modelData.path); Layout.preferredWidth: 24; Layout.preferredHeight: 24; sourceSize: Qt.size(48, 48) }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Text { text: er.modelData.name; color: set.pal.fgBright; font.family: set.pal.font; font.bold: true }
                                        Note { text: er.modelData.description }
                                        Note { text: (er.modelData.isInstalled ? "installed" : "unpacked") + " \u00b7 " + er.modelData.id + (er.modelData.error.length ? " \u00b7 " + er.modelData.error : ""); color: er.modelData.error.length ? set.pal.red : set.pal.fgDark }
                                    }
                                    Widgets.Btn { pal: set.pal; visible: er.modelData.actionPopupUrl.toString().length > 0; text: "Open"; onClicked: { const e = { name: er.modelData.name, popup: er.modelData.actionPopupUrl.toString() }; const h = set.host; const p = set.extProfile; set.close(); h.openExtensionPopup(e, p) } }
                                    Widgets.Toggle { pal: set.pal; checked: er.modelData.isEnabled; onToggled: set.host.setExtensionOn(set.extProfile, er.modelData, checked) }
                                    Widgets.Btn {
                                        pal: set.pal; text: "Remove"; danger: true
                                        onClicked: {
                                            if (er.modelData.isInstalled) extSec.em.uninstallExtension(er.modelData)
                                            else { set.browser.rememberUnpacked(set.extProfile, er.modelData.path, false); extSec.em.unloadExtension(er.modelData) }
                                        }
                                    }
                                }
                            }
                        }
                        Note { visible: extSec.list.length === 0; text: extSec.em ? "No extensions in this profile yet." : "This Qt WebEngine has no extension support." }
                    }
                    FolderDialog {
                        id: folderDialog
                        title: "An unpacked extension (the folder with manifest.json)"
                        onAccepted: {
                            const dir = decodeURIComponent(selectedFolder.toString().replace(/^file:\/\//, ""))
                            const em = set.host.engineProfile(set.extProfile).extensionManager
                            if (!em) return
                            set.browser.rememberUnpacked(set.extProfile, dir, true)
                            em.loadExtension(dir)
                            set.extMessage = "Loading " + dir
                        }
                    }
                    FileDialog {
                        id: crxDialog
                        title: "A .crx or .zip extension"
                        nameFilters: ["Chrome extensions (*.crx *.zip)"]
                        onAccepted: set.host.installExtension(set.extProfile, decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, "")))
                    }

                    // ---- Passwords ----
                    Section {
                        id: pwSec
                        visible: set.section === "passwords"
                        Head { text: "Passwords" }
                        property int prev: 0
                        readonly property bool ok: set.browser.passwordsAvailable()
                        readonly property var list: { pwSec.prev; set.visible; return pwSec.ok ? JSON.parse(set.browser.passwords(set.extProfile, "")) : [] }
                        Note {
                            text: pwSec.ok ? "Passwords live only in your keyring (Secret Service), never in Qi\u2019s files. Qi offers to save a password when you sign in, and Ctrl+Alt+L fills it."
                                           : "Saving passwords needs secret-tool (libsecret) and a running keyring: sudo pacman -S libsecret gnome-keyring."
                            color: pwSec.ok ? set.pal.fgDark : set.pal.yellow
                        }
                        Repeater {
                            model: pwSec.list
                            delegate: Row2 {
                                id: pw
                                required property var modelData
                                Text { text: pw.modelData.origin; color: set.pal.fgBright; font.family: set.pal.font; Layout.fillWidth: true; elide: Text.ElideMiddle }
                                Text { text: pw.modelData.username; color: set.pal.fg; font.family: set.pal.font; Layout.preferredWidth: 220; elide: Text.ElideRight }
                                Widgets.Btn { pal: set.pal; text: "Remove"; danger: true; onClicked: { set.browser.removePassword(set.extProfile, pw.modelData.origin, pw.modelData.username); pwSec.prev++ } }
                            }
                        }
                    }

                    // ---- Import from Chrome ----
                    Section {
                        id: impSec
                        visible: set.section === "import"
                        Head { text: "Import from Chrome or Chromium" }
                        property var extra: []
                        readonly property var sources: (set.visible && set.section === "import" ? JSON.parse(set.browser.chromeProfiles()) : []).concat(extra)
                        property int pick: 0
                        Note { text: impSec.sources.length ? "Found these profiles in ~/.config. Close that browser first so its databases aren't locked mid-write." : "No Chrome, Chromium, Brave, Edge or Vivaldi profiles in ~/.config." }
                        Repeater {
                            model: impSec.sources
                            delegate: RadioButton {
                                required property var modelData
                                required property int index
                                checked: impSec.pick === index
                                onClicked: impSec.pick = index
                                text: modelData.browser + " \u2014 " + modelData.name + "  (" + modelData.dir + ")"
                                contentItem: Text { leftPadding: 28; text: parent.text; color: set.pal.fg; font.family: set.pal.font; verticalAlignment: Text.AlignVCenter }
                            }
                        }
                        Widgets.Btn { pal: set.pal; text: "A profile folder somewhere else\u2026"; tip: "For Chrome run with --user-data-dir: pick its Default or Profile N folder"; onClicked: chromeDirDialog.open() }
                        FolderDialog {
                            id: chromeDirDialog
                            title: "A Chrome profile folder (Default, Profile 1, \u2026)"
                            onAccepted: {
                                const dir = decodeURIComponent(selectedFolder.toString().replace(/^file:\/\//, ""))
                                impSec.extra = impSec.extra.concat([{ browser: "Chrome", name: dir.split("/").pop(), dir: dir, path: dir, keyring_app: "chrome" }])
                                impSec.pick = impSec.sources.length - 1
                            }
                        }
                        Row2 {
                            Name { text: "Into Qi profile" }
                            ComboBox { model: set.host.profiles.map(p => p.name); currentIndex: Math.max(0, model.indexOf(set.importTarget)); onActivated: i => set.importTarget = model[i] }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 12
                            CheckBox { id: iB; text: "Bookmarks"; checked: true }
                            CheckBox { id: iH; text: "History"; checked: true }
                            CheckBox { id: iC; text: "Cookies (stay signed in)"; checked: true }
                            CheckBox { id: iP; text: "Passwords"; checked: true }
                            CheckBox { id: iE; text: "Extensions"; checked: true }
                        }
                        Widgets.Btn {
                            pal: set.pal; primary: true; text: set.importing ? "Importing\u2026" : "Import"
                            enabled: impSec.sources.length > 0 && !set.importing
                            onClicked: {
                                const s = impSec.sources[impSec.pick]
                                set.importing = true
                                set.importReport = null
                                set.host.engineProfile(set.importTarget)
                                set.browser.importChrome(s.path, s.keyring_app, set.importTarget, JSON.stringify({ bookmarks: iB.checked, history: iH.checked, cookies: iC.checked, passwords: iP.checked, extensions: iE.checked }))
                            }
                        }
                        Note {
                            visible: set.importReport !== null
                            color: set.pal.fg
                            text: !set.importReport ? "" :
                                ["Bookmarks: " + (set.importReport.bookmarks || 0),
                                 "History pages: " + (set.importReport.historyVisits || 0),
                                 "Cookies: " + (set.importReport.cookies || 0) + (set.importReport.cookiesNotDecrypted ? " (" + set.importReport.cookiesNotDecrypted + " couldn't be decrypted)" : ""),
                                 "Passwords: " + (set.importReport.passwords || 0) + (set.importReport.passwordsNotDecrypted ? " (" + set.importReport.passwordsNotDecrypted + " couldn't be decrypted)" : ""),
                                 "Extensions: " + ((set.importReport.extensionDirs || []).length)].concat(set.importReport.notes || []).join("\n")
                        }
                    }

                    // ---- Keyboard ----
                    Section {
                        visible: set.section === "keys"
                        Head { text: "Keyboard" }
                        Note { text: "Ctrl and Alt only: Super stays Hyprland\u2019s." }
                        Repeater {
                            model: [
                                ["Address / command palette", "Ctrl+L, Alt+D, F6"], ["Find a tab", "Ctrl+K"], ["New tab / private tab", "Ctrl+T / Ctrl+Shift+N"],
                                ["Close / reopen tab", "Ctrl+W / Ctrl+Shift+T"], ["Next / previous tab", "Ctrl+Tab / Ctrl+Shift+Tab"], ["Tab 1\u20139", "Ctrl+1\u20269 or Alt+1\u20269"],
                                ["Space 1\u20139", "Ctrl+Alt+1\u20269"], ["Next / previous space", "Ctrl+Alt+Right / Left"], ["New space", "Ctrl+Alt+N"],
                                ["Sidebar show / pin", "Ctrl+Shift+B or Ctrl+S"], ["Pin / unpin tab", "Ctrl+D"], ["Bookmark", "Ctrl+Shift+D"],
                                ["Bookmarks / history / downloads / archive", "Ctrl+Alt+B / Ctrl+H / Ctrl+Shift+J / Ctrl+Alt+A"], ["Agent panel", "Ctrl+Shift+A"],
                                ["Split with next tab", "Ctrl+Alt+S"], ["Reading mode", "Ctrl+Alt+R"], ["Hide something", "Ctrl+Shift+H"], ["Site controls", "Ctrl+E"],
                                ["Fill saved password", "Ctrl+Alt+L"], ["Paste and go", "Ctrl+Shift+V"], ["Settings", "Ctrl+,"], ["Find in page", "Ctrl+F, Ctrl+G"],
                                ["Zoom", "Ctrl+= / Ctrl+- / Ctrl+0"], ["Back / forward / reload", "Alt+Left / Alt+Right / Ctrl+R"], ["Copy address", "Ctrl+Shift+C"],
                                ["Developer tools / source", "F12 / Ctrl+U"], ["Full screen / quit", "F11 / Ctrl+Q"]]
                            delegate: Row2 {
                                required property var modelData
                                Name { text: modelData[0]; Layout.preferredWidth: 320 }
                                Text { text: modelData[1]; color: set.pal.accent; font.family: set.pal.font }
                            }
                        }
                    }

                    // ---- About ----
                    Section {
                        visible: set.section === "about"
                        Head { text: "Qi" }
                        Note { text: "A chromeless, keyboard-first browser for Omarchy, in Rust and Qt WebEngine. Its sidebar, spaces, favorites, folders, Peek, split view, library and agent panel follow Yab (github.com/yetanotherbrowser/yab), Apache-2.0; see NOTICE and LICENSE." }
                        Note { text: "Theme: " + set.pal.name + " \u00b7 config: " + set.browser.configPath() }
                    }
                }
            }
        }
    }
}
