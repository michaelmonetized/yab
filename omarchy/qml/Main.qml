// Qi's window. QML draws; Rust (the Browser object) decides.
//
// The sidebar's shape (spaces, folders, favorites, pinned and today tabs,
// the archive) is one workspace object `ws`; every structural change goes
// through browser.wsApply() (src/workspace.rs). Live pages are BrowserTab
// items in `live`, by tab uid, made the first time a tab is shown.
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Window
import QtWebEngine
import app.qi
import app.qi.native

ApplicationWindow {
    id: win
    width: 1440
    height: 900
    visible: true
    color: pal.bg
    flags: frameless ? (Qt.Window | Qt.FramelessWindowHint) : Qt.Window
    title: (currentTab && currentTab.title ? currentTab.title + " — " : "") + "Qi"

    // ---- Rust core -------------------------------------------------------
    Browser {
        id: browser
        onOpenRequested: (url, isPrivate, profile) => win.openFromOutside(url, isPrivate, profile)
        onFocusRequested: { win.raise(); win.requestActivate() }
        onAgentDelta: (id, text) => agentPanel.onDelta(id, text)
        onAgentFinished: (id, result) => win.agentFinished(id, result)
        onAgentFailed: (id, error) => win.agentFailed(id, error)
        onExtensionReady: (profile, dir, name, error) => win.extensionReady(profile, dir, name, error)
        onImportFinished: (profile, report) => settings.importDone(profile, report)
        onBlocklistReady: (path, hosts) => WebTools.loadBlocklist(path)
    }

    readonly property var theme: browser.themeJson.length ? JSON.parse(browser.themeJson) : null
    readonly property var cfg: browser.configJson.length ? JSON.parse(browser.configJson) : ({})
    readonly property var profiles: browser.profilesJson.length ? JSON.parse(browser.profilesJson) : []
    readonly property string defaultProfile: cfg.default_profile || "Default"
    readonly property bool sidebarMode: cfg.tabs !== "top"
    readonly property bool frameless: cfg.frameless !== false
    readonly property bool xcb: Qt.platform.pluginName === "xcb"
    property bool sidebarPinned: false
    property bool sidebarPeek: false
    property bool compact: false
    property bool chromePeek: false
    readonly property bool chromeShown: !compact || chromePeek
    // A secret only our own isolated-world scripts know: page scripts can't
    // fake the console messages that carry it.
    readonly property string token: "\u0001qi" + Math.floor(Math.random() * 1e12).toString(36) + Date.now().toString(36) + ":"

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

    // A space's accent: a key of the Omarchy theme, so it follows theme swaps.
    function spaceColor(key) {
        const n = { red: "color1", green: "color2", yellow: "color3", blue: "color4", magenta: "color5", cyan: "color6" }
        if (!key || key === "accent") return pal.accent
        return pal.c(key, pal.c(n[key] || "accent", pal.accent))
    }

    // ---- Profiles ----------------------------------------------------------
    // One persistent web engine profile per Qi profile (cookies, storage,
    // cache, extensions), made when first needed; one shared private one.
    Component { id: profileProto; WebEngineProfilePrototype {} }
    WebEngineProfilePrototype { id: privateProto }
    property WebEngineProfile privateProfile: null
    property var engineProfiles: ({})
    property int extRev: 0

    function infoOf(name) {
        for (const p of profiles) if (p.name === name) return p
        return null
    }
    function engineProfile(name) {
        if (name === "private") return privateProfile
        if (engineProfiles[name]) return engineProfiles[name]
        let info = infoOf(name)
        if (!info) { browser.addProfile(name); info = infoOf(name) || { name: name, storage_name: "qi", storage_path: "", cache_path: "" } }
        const props = {
            storageName: info.storage_name,
            httpCacheType: WebEngineProfile.DiskHttpCache,
            persistentCookiesPolicy: WebEngineProfile.AllowPersistentCookies
        }
        if (info.storage_path.length) props.persistentStoragePath = info.storage_path
        if (info.cache_path.length) props.cachePath = info.cache_path
        const proto = profileProto.createObject(win, props)
        const p = proto.instance()
        const m = Object.assign({}, engineProfiles)
        m[name] = p
        engineProfiles = m
        setUpProfile(p, name)
        return p
    }
    function setUpProfile(p, name) {
        WebTools.attachProfile(p, name)
        p.downloadRequested.connect(d => win.acceptDownload(d))
        p.downloadFinished.connect(d => win.downloadDone(d))
        installUserScripts(p)
        if (name !== "private" && p.extensionManager) {
            const em = p.extensionManager
            em.installFinished.connect(info => { if (!info.error.length && !info.isEnabled) em.setExtensionEnabled(info, true); win.extRev++; status.show(info.error.length ? "Couldn't install " + info.name + ": " + info.error : "Installed " + info.name); settings.extensionMessage(info.error.length ? info.error : "Installed " + info.name) })
            em.loadFinished.connect(info => { if (!info.error.length && !info.isEnabled && JSON.parse(browser.disabledExtensions(name)).indexOf(info.id) < 0) em.setExtensionEnabled(info, true); win.extRev++; if (info.error.length) status.show(info.name + ": " + info.error) })
            em.uninstallFinished.connect(info => { win.extRev++; status.show("Removed " + info.name) })
            em.unloadFinished.connect(info => win.extRev++)
            for (const dir of JSON.parse(browser.loadedExtensions(name))) em.loadExtension(dir)
            extRev++
        }
    }
    function installUserScripts(p) {
        const s = WebEngine.script()
        s.name = "qi-login-capture"
        s.injectionPoint = WebEngineScript.DocumentReady
        s.worldId = WebEngineScript.ApplicationWorld
        s.runsOnSubframes = false
        s.sourceCode = "(function(){var T=" + JSON.stringify(token) + ";" +
            "document.addEventListener('submit',function(e){var f=e.target;if(!f||!f.querySelector)return;" +
            "var pw=f.querySelector('input[type=password]');if(!pw||!pw.value)return;var user='';" +
            "var ins=Array.prototype.slice.call(f.querySelectorAll('input'));" +
            "for(var i=ins.indexOf(pw)-1;i>=0;i--){var t=(ins[i].type||'text').toLowerCase();if((t==='text'||t==='email'||t==='tel')&&ins[i].value){user=ins[i].value;break;}}" +
            "console.log(T+'login:'+JSON.stringify({url:location.href,username:user,password:pw.value}));},true);})();"
        p.userScripts.insert(s)
    }
    function profileOfCurrent() {
        if (currentTab) return currentTab.profileName
        return currentSpace ? currentSpace.profile : defaultProfile
    }

    // ---- Downloads ---------------------------------------------------------
    property var downloads: []
    property int activeDownloads: 0
    function countDownloads() {
        let n = 0
        for (const d of downloads) if (d.state === WebEngineDownloadRequest.DownloadInProgress) n++
        activeDownloads = n
    }
    function acceptDownload(d) {
        d.accept()
        downloads = [d].concat(downloads).slice(0, 100)
        countDownloads()
        status.show("Downloading " + d.downloadFileName + " to " + d.downloadDirectory)
    }
    function downloadDone(d) {
        countDownloads()
        downloads = downloads.slice()
        if (d.state === WebEngineDownloadRequest.DownloadCompleted)
            browser.notify("Downloaded " + d.downloadFileName, d.downloadDirectory)
        else
            browser.notify("Download failed", d.downloadFileName + ": " + d.interruptReasonString)
    }

    // ---- Workspace ---------------------------------------------------------
    property var ws: ({ spaces: [], favorites: [], current_space: "", current_favorite: "", archive: [], watches: [] })
    property int rev: 0
    property int liveRev: 0
    property var live: ({})
    property var closed: []
    property var fullscreenTab: null
    property bool started: false
    property string splitUid: ""
    property real splitRatio: 0.5
    property int uidCounter: 0

    readonly property var currentSpace: {
        rev
        for (const s of ws.spaces) if (s.id === ws.current_space) return s
        return ws.spaces.length ? ws.spaces[0] : null
    }
    readonly property string currentUid: { rev; return ws.current_favorite && ws.current_favorite.length ? ws.current_favorite : (currentSpace ? currentSpace.current : "") }
    readonly property var currentTab: { rev; liveRev; return currentUid.length && live[currentUid] ? live[currentUid] : null }
    readonly property bool currentBookmarked: { rev; return currentTab && !currentTab.blank && !currentTab.isPrivate ? browser.isBookmarked(currentTab.profileName, currentTab.url.toString()) : false }
    onCurrentUidChanged: activateCurrent()
    onSplitUidChanged: applyTabStates()

    function nowSecs() { return browser.now() }
    function genUid() { uidCounter++; return "t" + Date.now().toString(36) + uidCounter.toString(36) }

    function find(uid) {
        for (const f of ws.favorites) if (f.uid === uid) return { rec: f, space: null }
        for (const s of ws.spaces) for (const t of s.tabs) if (t.uid === uid) return { rec: t, space: s }
        return null
    }
    function profileFor(found) {
        if (!found) return defaultProfile
        if (found.rec.private) return "private"
        return found.space ? found.space.profile : defaultProfile
    }

    function op(o) {
        const r = JSON.parse(browser.wsApply(JSON.stringify(ws), JSON.stringify(o)))
        if (r.error) { status.show(r.error); return false }
        ws = r.ws
        rev++
        reconcile()
        saveSoon()
        return true
    }

    // Drops live pages whose tab is gone or moved to another profile.
    function reconcile() {
        const m = Object.assign({}, live)
        let changed = false
        for (const uid in m) {
            const f = find(uid)
            if (!f || profileFor(f) !== m[uid].profileName) {
                if (!f && !m[uid].isPrivate && m[uid].url.toString().length) closed = closed.concat([m[uid].url.toString()]).slice(-25)
                m[uid].destroy()
                delete m[uid]
                changed = true
            }
        }
        if (changed) { live = m; liveRev++ }
        if (splitUid.length && !find(splitUid)) splitUid = ""
        activateCurrent()
    }

    Component { id: tabComponent; BrowserTab {} }

    function ensureLive(uid) {
        if (live[uid]) return live[uid]
        const f = find(uid)
        if (!f) return null
        const pname = profileFor(f)
        const t = tabComponent.createObject(viewArea, {
            pal: pal, browser: browser, uid: uid,
            profile: engineProfile(pname), profileName: pname,
            isPrivate: !!f.rec.private, zoom: cfg.zoom || 1.0,
            lazyUrl: f.rec.url, lazyTitle: f.rec.title, token: token
        })
        t.forceDark = Qt.binding(() => !!win.cfg.force_dark)
        t.newTabRequested.connect(request => win.handleNewWindow(t, request))
        t.closeRequested.connect(() => win.closeUid(t.uid))
        t.fullScreenChanged.connect(on => {
            win.fullscreenTab = on ? t : null
            if (on) win.showFullScreen(); else win.showNormal()
        })
        t.changed.connect(() => win.syncRec(t))
        t.liveChanged.connect(() => win.liveRev++)
        t.pageLoaded.connect(() => win.afterLoad(t))
        t.pageMessage.connect((kind, payload) => win.pageMessage(t, kind, payload))
        const m = Object.assign({}, live)
        m[uid] = t
        live = m
        liveRev++
        return t
    }

    function syncRec(t) {
        const f = find(t.uid)
        if (!f || !t.started) return
        const u = t.view.url.toString()
        if (u.length && u !== "about:blank") f.rec.url = u
        if (t.view.title.length) f.rec.title = t.view.title
        rev++
        saveSoon()
        if (t.uid === currentUid) storeButton.check()
    }

    function applyTabStates() {
        const split = splitUid.length && splitUid !== currentUid && live[splitUid] ? splitUid : ""
        for (const uid in live) {
            const t = live[uid]
            t.active = uid === currentUid
            t.splitSide = split.length ? (uid === currentUid ? 1 : (uid === split ? 2 : 0)) : 0
            t.splitRatio = splitRatio
        }
    }

    function activateCurrent() {
        if (!started) return
        const uid = currentUid
        if (uid.length) ensureLive(uid)
        if (splitUid.length) ensureLive(splitUid)
        applyTabStates()
        const t = live[uid]
        if (!t) return
        if (t.blank && !t.lazyUrl.length) Qt.callLater(focusOmnibox)
        else t.view.forceActiveFocus()
        storeButton.check()
        loginBar.check(t)
    }

    function selectUid(uid) {
        if (uid === splitUid && currentUid.length) splitUid = currentUid
        op({ op: "select", uid: uid, now: nowSecs() })
    }

    // The tabs of the current space in sidebar order (for keys and closing).
    function orderedUids() {
        const out = []
        if (!currentSpace) return out
        for (const f of currentSpace.folders) for (const t of currentSpace.tabs) if (t.folder === f.id) out.push(t.uid)
        for (const t of currentSpace.tabs) if (t.pinned && !t.folder.length) out.push(t.uid)
        for (const t of currentSpace.tabs) if (!t.pinned) out.push(t.uid)
        return out
    }
    function selectIndex(i) {
        const list = ws.favorites.map(f => f.uid).concat(orderedUids())
        if (!list.length) return
        if (i < 0) i = list.length - 1
        selectUid(list[Math.min(i, list.length - 1)])
    }
    function stepTab(d) {
        const list = ws.favorites.map(f => f.uid).concat(orderedUids())
        if (!list.length) return
        const i = list.indexOf(currentUid)
        selectUid(list[(i + d + list.length) % list.length])
    }

    function newTab(url, focus, isPrivate, afterUid, spaceId) {
        const uid = genUid()
        const after = afterUid === undefined ? "" : afterUid
        if (!op({ op: "new_tab", uid: uid, url: "", space: spaceId || "", after: after, private: !!isPrivate, now: nowSecs() })) return null
        const t = ensureLive(uid)
        if (url && url.length) t.load(url); else t.started = true
        const fg = focus === undefined || focus
        if (fg) op({ op: "select", uid: uid, now: nowSecs() })
        else applyTabStates()
        if ((!url || !url.length) && fg) Qt.callLater(focusOmnibox)
        return t
    }

    function unload(uid) {
        if (!live[uid]) return
        const m = Object.assign({}, live)
        m[uid].destroy()
        delete m[uid]
        live = m
        liveRev++
    }

    function closeUid(uid) {
        const f = find(uid)
        if (!f) return
        const wasCurrent = uid === currentUid
        let next = ""
        if (wasCurrent) {
            const list = orderedUids().filter(u => u === uid || !find(u).rec.pinned || live[u])
            const i = list.indexOf(uid)
            next = i >= 0 ? (list[i + 1] || list[i - 1] || "") : (list[0] || "")
        }
        if (uid === splitUid) splitUid = ""
        if (f.rec.pinned) {
            // Pinned tabs and favorites stay in the sidebar; closing unloads them.
            unload(uid)
            if (wasCurrent && next.length && next !== uid) selectUid(next)
            else if (wasCurrent) { ws.current_favorite = ""; if (currentSpace) currentSpace.current = ""; rev++ }
            return
        }
        op({ op: "close_tab", uid: uid })
        if (wasCurrent && next.length && next !== uid) selectUid(next)
    }

    function reopenClosed() {
        if (!closed.length) return
        const list = closed.slice()
        const url = list.pop()
        closed = list
        newTab(url, true, false, currentUid)
    }
    function duplicate(uid) {
        const f = find(uid)
        if (f) newTab(f.rec.url, true, !!f.rec.private, uid)
    }
    function resetPinned(uid) {
        op({ op: "reset_pinned", uid: uid })
        const f = find(uid)
        if (live[uid] && f) live[uid].load(f.rec.url)
    }

    function switchSpace(id) {
        if (!op({ op: "switch_space", id: id })) return
        splitUid = ""
        if (currentSpace && !currentSpace.current.length) {
            const list = orderedUids()
            if (list.length) selectUid(list[list.length - 1]); else newTab("", true)
        }
    }
    function stepSpace(d) {
        const i = ws.spaces.findIndex(s => s.id === ws.current_space)
        if (i < 0 || ws.spaces.length < 2) return
        switchSpace(ws.spaces[(i + d + ws.spaces.length) % ws.spaces.length].id)
    }
    function newSpace(name, profile) {
        const id = "s" + genUid()
        if (op({ op: "add_space", id: id, name: name || ("Space " + (ws.spaces.length + 1)), profile: profile || (currentSpace ? currentSpace.profile : defaultProfile) })) {
            newTab("", true)
            if (!name) Qt.callLater(() => { palette.close(); win.sidebarPeek = true; sidebar.renameSpace() })
        }
    }
    function setSpaceProfile(id, name) { op({ op: "update_space", id: id, profile: name }) }
    function newFolder(moveUid) {
        const id = "f" + genUid()
        if (!op({ op: "add_folder", id: id, name: "New folder" })) return
        if (moveUid && moveUid.length) op({ op: "move_tab", uid: moveUid, folder: id })
        Qt.callLater(() => sidebar.renameFolderRequested(id))
    }
    function openFolder(id) {
        if (!currentSpace) return
        for (const t of currentSpace.tabs) if (t.folder === id) ensureLive(t.uid).wake()
    }
    function splitWith(uid) {
        if (splitUid === uid || (uid === currentUid && splitUid.length)) { splitUid = ""; return }
        if (uid === currentUid) {
            const list = orderedUids()
            const i = list.indexOf(uid)
            const other = list[i + 1] || list[i - 1]
            if (!other) { status.show("Open another tab to split with"); return }
            uid = other
        }
        ensureLive(uid)
        splitUid = uid
        applyTabStates()
    }
    function togglePinCurrent() {
        if (!currentTab || currentTab.isPrivate) return
        const f = find(currentUid)
        if (f && f.space) op({ op: "pin", uid: currentUid, on: !f.rec.pinned })
    }
    function bookmarkUid(uid) {
        const t = live[uid]
        const f = find(uid)
        if (!f || f.rec.private || !f.rec.url.length) return
        const pname = profileFor(f)
        if (browser.isBookmarked(pname, f.rec.url)) { browser.removeBookmarkUrl(pname, f.rec.url); status.show("Bookmark removed") }
        else { browser.addBookmark(pname, f.rec.url, t ? t.title : f.rec.title, ""); status.show("Bookmarked " + (t ? t.title : f.rec.title)) }
        rev++
    }
    function copyText(t) { clip.text = t; clip.selectAll(); clip.copy(); status.show("Copied " + t) }

    function openFromOutside(url, isPrivate, profile) {
        if (profile && profile.length) {
            const name = browser.addProfile(profile)
            const s = ws.spaces.find(x => x.profile === name)
            if (s) op({ op: "switch_space", id: s.id }); else op({ op: "add_space", id: "s" + genUid(), name: name, profile: name })
        }
        newTab(url, true, isPrivate)
    }

    // Shift+click and pop-ups go to Peek; Ctrl+click and middle-click to a tab.
    function handleNewWindow(t, request) {
        const dest = request.destination
        if (cfg.peek !== false && (dest === WebEngineNewWindowRequest.InNewWindow || dest === WebEngineNewWindowRequest.InNewDialog)) {
            peek.openRequest(request, t.profile, t.isPrivate, t.profileName)
            return
        }
        const bg = dest === WebEngineNewWindowRequest.InNewBackgroundTab
        const f = find(t.uid)
        const nt = newTab("", !bg, t.isPrivate, t.uid, f && f.space ? f.space.id : "")
        if (nt) request.openIn(nt.view)
    }

    function go(text) {
        const url = browser.resolve(text)
        if (!url.length) return
        if (!currentTab) { newTab(url, true); return }
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

    // ---- What the sidebar draws ---------------------------------------------
    function rowOf(rec, indent) {
        const t = live[rec.uid]
        let watch = ""
        for (const w of ws.watches) if (w.tab_uid === rec.uid && !w.done) watch = "Watching: " + w.condition + (w.last_result.length ? " · " + w.last_result : "")
        return {
            kind: "tab", rec: rec, uid: rec.uid, indent: indent, url: t ? t.url.toString() : rec.url,
            title: t ? t.title : (rec.title.length ? rec.title : (rec.url.length ? rec.url : (rec.private ? "Private tab" : "New tab"))),
            icon: t ? t.icon : "", loading: t ? t.loading : false, audible: t ? t.audible : false,
            isPrivate: !!rec.private, pinned: rec.pinned, live: !!t, watch: watch
        }
    }
    readonly property var favoriteRows: { rev; liveRev; return ws.favorites.map(f => rowOf(f, false)) }
    readonly property var sidebarRows: {
        rev; liveRev
        const out = []
        const s = currentSpace
        if (!s) return out
        for (const f of s.folders) {
            const inside = s.tabs.filter(t => t.folder === f.id)
            out.push({ kind: "folder", folder: f, count: inside.length })
            if (!f.collapsed) for (const t of inside) out.push(rowOf(t, true))
        }
        for (const t of s.tabs) if (t.pinned && !t.folder.length) out.push(rowOf(t, false))
        out.push({ kind: "pinhint" })
        const today = s.tabs.filter(t => !t.pinned)
        out.push({ kind: "divider", today: today.length })
        out.push({ kind: "new" })
        for (const t of today) out.push(rowOf(t, false))
        return out
    }
    // Every tab in every space, for Ctrl+K.
    readonly property var allTabRows: {
        rev; liveRev
        const out = ws.favorites.map(f => rowOf(f, false))
        for (const s of ws.spaces) for (const t of s.tabs) { const r = rowOf(t, false); if (s.id !== ws.current_space) r.title = r.title + "  · " + s.name; out.push(r) }
        return out
    }
    readonly property var spaceTabRows: { rev; liveRev; return orderedUids().map(u => rowOf(find(u).rec, false)) }

    // Extension toolbar buttons for the current profile.
    // (Read imperatively: the manager's extension list isn't bindable.)
    property var extensionButtons: []
    function extensionsOf(name) {
        if (name === "private") return []
        const p = engineProfiles[name]
        if (!p || !p.extensionManager) return []
        // Qt WebEngine's own component extensions (PDF viewer, Hangouts) aren't the user's.
        const builtIn = ["mhjfbmdgcfjbbpaeojofohoefgiehjai", "nkeimhogjdpnpccoofpliimaahmaaome"]
        return p.extensionManager.extensions.filter(e => builtIn.indexOf(e.id) < 0)
    }
    // Turns back on every loaded extension the person didn't switch off.
    function restoreEnabled() {
        for (const name in engineProfiles) {
            if (name === "private") continue
            const em = engineProfiles[name].extensionManager
            if (!em) continue
            const off = JSON.parse(browser.disabledExtensions(name))
            for (const e of extensionsOf(name))
                if (e.isLoaded && !e.isEnabled && off.indexOf(e.id) < 0) { em.setExtensionEnabled(e, true); extRev++ }
        }
    }
    function setExtensionOn(name, e, on) {
        browser.rememberDisabled(name, e.id, !on)
        engineProfiles[name].extensionManager.setExtensionEnabled(e, on)
        extRev++
    }
    function refreshExtensionButtons() {
        const out = []
        for (const e of extensionsOf(profileOfCurrent()))
            if (e.isEnabled && e.isLoaded) out.push({ id: e.id, name: e.name, popup: e.actionPopupUrl.toString(), icon: browser.extensionIcon(e.path) })
        extensionButtons = out
    }
    onExtRevChanged: Qt.callLater(refreshExtensionButtons)
    // Installed extensions come up a moment after the profile, with no signal.
    Timer { interval: 4000; running: win.started; repeat: true; onTriggered: { win.restoreEnabled(); const n = win.extensionButtons.length; win.refreshExtensionButtons(); if (win.extensionButtons.length !== n) win.extRev++ } }
    onCurrentTabChanged: Qt.callLater(refreshExtensionButtons)
    function openExtensionPopup(ext, profileName) {
        if (!ext.popup.length) { status.show(ext.name + " has no popup; Qt WebEngine can't send toolbar clicks to an extension"); return }
        extPopup.show(ext, engineProfile(typeof profileName === "string" && profileName.length ? profileName : profileOfCurrent()))
    }

    // ---- Saving ------------------------------------------------------------
    Timer { id: saveTimer; interval: 800; onTriggered: win.saveNow() }
    function saveSoon() { if (started) saveTimer.restart() }
    function saveNow() { browser.saveWorkspace(JSON.stringify(ws)) }
    onClosing: saveNow()

    // Auto-archive: today tabs untouched for archive_after_hours.
    Timer {
        interval: 10 * 60 * 1000
        running: win.started
        repeat: true
        triggeredOnStart: true
        onTriggered: if ((win.cfg.archive_after_hours || 0) > 0) win.op({ op: "archive_due", now: win.nowSecs(), hours: win.cfg.archive_after_hours })
    }

    Component.onCompleted: {
        privateProfile = privateProto.instance()
        setUpProfile(privateProfile, "private")
        browser.start()
        compact = !!cfg.compact
        sidebarPinned = !!cfg.pin_sidebar
        ws = JSON.parse(browser.initialJson)
        rev++
        engineProfile(currentSpace ? currentSpace.profile : defaultProfile)
        started = true
        activateCurrent()
        // Tabs from the command line load now, current or not.
        for (const s of ws.spaces) for (const t of s.tabs) if (t.uid.startsWith("c") && t.uid !== currentUid) ensureLive(t.uid).wake()
        WebTools.setBlocking(cfg.blocker ? cfg.blocker.enabled !== false : true, cfg.blocker ? cfg.blocker.allow : [])
        browser.refreshBlocklist(false)
    }
    onCfgChanged: if (started) WebTools.setBlocking(cfg.blocker ? cfg.blocker.enabled !== false : true, cfg.blocker ? cfg.blocker.allow : [])

    Connections {
        target: WebTools
        function onBlocked(host, count) {
            for (const uid in win.live) if (win.live[uid].host === host) win.live[uid].blockedCount = count
        }
    }

    // ---- After a page loads: hidden elements, saved logins, the Web Store ----
    function afterLoad(t) {
        const css = browser.hideCss(t.host)
        if (css.length)
            t.view.runJavaScript("(function(){var s=document.getElementById('qi-hide')||document.createElement('style');s.id='qi-hide';s.textContent=" + JSON.stringify(css) + ";(document.head||document.documentElement).appendChild(s);})()", WebEngineScript.ApplicationWorld)
        if (t.uid === currentUid) { loginBar.check(t); storeButton.check() }
        agentPanel.pageLoaded(t)
        watcher.pageLoaded(t)
    }
    function pageMessage(t, kind, payload) {
        if (kind === "hide") {
            if (browser.addHideRule(t.host, payload)) { afterLoad(t); status.show("Hidden on " + t.host + " (Ctrl+E to bring it back)") }
        } else if (kind === "login") {
            if (t.isPrivate) return
            try { loginBar.offerSave(t, JSON.parse(payload)) } catch (e) {}
        }
    }

    // ---- Agent -------------------------------------------------------------
    property bool agentOpen: false
    function toggleAgent() { agentOpen = !agentOpen; if (agentOpen) agentPanel.focusInput() }
    // What the agent sees of the current tab. Never a private one.
    readonly property string pageScript: "(function(){var sel=String(window.getSelection?window.getSelection():'');" +
        "var t=document.body?document.body.innerText:'';return JSON.stringify({title:document.title,url:location.href,selection:sel,text:t});})()"
    function readPage(t, cb) {
        if (!t || t.blank) { cb(null); return }
        if (t.isPrivate) { cb({ title: "", url: "", selection: "", text: "", private: true }); return }
        t.view.runJavaScript(pageScript, WebEngineScript.ApplicationWorld, r => {
            let p = null
            try { p = JSON.parse(r) } catch (e) { p = { title: t.title, url: t.url.toString(), selection: "", text: "" } }
            p.private = false
            cb(p)
        })
    }
    function agentFinished(id, result) {
        if (watcher.owns(id)) watcher.finished(id, JSON.parse(result)); else agentPanel.onFinished(id, JSON.parse(result))
    }
    function agentFailed(id, error) {
        if (watcher.owns(id)) watcher.failed(id, error); else agentPanel.onFailed(id, error)
    }
    Component { id: oneShot; Timer { repeat: false } }
    function after(ms, fn) {
        const tm = oneShot.createObject(win, { interval: ms })
        tm.triggered.connect(() => { fn(); tm.destroy() })
        tm.start()
    }
    function waitForLoad(t, cb) {
        if (!t) { cb(); return }
        let done = false
        const finish = () => { if (done) return; done = true; t.pageLoaded.disconnect(finish); cb() }
        t.pageLoaded.connect(finish)
        after(1500, () => { if (!t.loading) finish() })
        after(15000, finish)
    }
    // The agent's tools, run on the current tab.
    function runTool(name, args, cb) {
        const t = currentTab
        const js = (code, then) => { if (!t) { cb("No page is open."); return } t.view.runJavaScript(code, WebEngineScript.ApplicationWorld, then) }
        switch (name) {
        case "open_url": {
            const url = browser.resolve(args.url || "")
            if (!url.length) { cb("Not an address: " + args.url); return }
            let nt = t
            if (args.new_tab || !t || t.isPrivate) nt = newTab(url, true); else t.load(url)
            waitForLoad(nt, () => cb("Opened " + url + (nt ? " (title: " + nt.title + ")" : "")))
            return
        }
        case "search_web": {
            const nt = newTab(browser.resolve(args.query || ""), true)
            waitForLoad(nt, () => cb("Searched for " + args.query + " in a new tab; it is now the current tab."))
            return
        }
        case "click":
            js("(function(q){q=q.toLowerCase().trim();var els=document.querySelectorAll('a,button,[role=button],input[type=submit],input[type=button],summary,label');" +
               "var best=null;for(var i=0;i<els.length;i++){var e=els[i];var s=(e.innerText||e.value||e.getAttribute('aria-label')||e.title||'').toLowerCase().trim();" +
               "if(!s)continue;if(s===q){best=e;break;}if(!best&&s.indexOf(q)>=0)best=e;}" +
               "if(!best)return 'No link or button with the text \"'+q+'\"';best.scrollIntoView({block:'center'});best.click();return 'Clicked \"'+(best.innerText||best.value||q).trim().slice(0,80)+'\"';})(" + JSON.stringify(args.text || "") + ")",
               r => after(1500, () => cb(String(r))))
            return
        case "type_text":
            js("(function(f,v,sub){f=f.toLowerCase();var ins=document.querySelectorAll('input,textarea,[contenteditable=true]');var el=null;" +
               "for(var i=0;i<ins.length;i++){var e=ins[i];var lab='';if(e.labels&&e.labels.length)lab=e.labels[0].innerText;" +
               "var s=[lab,e.placeholder,e.name,e.id,e.getAttribute('aria-label')].join(' ').toLowerCase();if(s.indexOf(f)>=0){el=e;break;}}" +
               "if(!el)return 'No field like \"'+f+'\"';el.focus();if(el.isContentEditable){el.innerText=v;}else{var d=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el),'value');if(d&&d.set)d.set.call(el,v);else el.value=v;}" +
               "el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));" +
               "if(sub){if(el.form){if(el.form.requestSubmit)el.form.requestSubmit();else el.form.submit();}else{el.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true}));}}" +
               "return 'Typed into '+(el.name||el.id||f);})(" + JSON.stringify(args.field || "") + "," + JSON.stringify(args.text || "") + "," + (args.submit ? "true" : "false") + ")",
               r => after(args.submit ? 2000 : 200, () => cb(String(r))))
            return
        case "scroll":
            js("(function(d){if(d==='top')scrollTo(0,0);else if(d==='bottom')scrollTo(0,document.body.scrollHeight);else scrollBy(0,(d==='up'?-1:1)*innerHeight*0.85);return 'Scrolled '+d;})(" + JSON.stringify(args.direction || "down") + ")", r => cb(String(r)))
            return
        case "find_in_page":
            if (!t) { cb("No page is open."); return }
            findBar.openWith(args.text || "")
            cb("Highlighted \"" + (args.text || "") + "\" on the page")
            return
        case "watch_page": {
            if (!t || t.isPrivate) { cb("The agent can't watch a private tab."); return }
            const id = "w" + genUid()
            const every = Math.max(1, args.every_minutes || 30)
            if (op({ op: "add_watch", id: id, tab_uid: t.uid, condition: args.condition || "", every_minutes: every })) {
                op({ op: "update_watch", id: id, now: nowSecs(), result: "" })
                agentPanel.addWatchCard({ condition: args.condition || "", title: t.title, host: t.host })
                cb("Now watching " + t.title + " every " + every + " minutes for: " + args.condition)
            } else cb("Couldn't watch this tab")
            return
        }
        default:
            cb("Unknown tool " + name)
        }
    }

    // Watches: re-read a tab every few minutes; say when the condition holds.
    QtObject {
        id: watcher
        property var pending: ({})     // agent request id -> watch id
        property var waitingLoad: ({}) // tab uid -> watch id
        property int nextId: 1000000
        function owns(id) { return pending[id] !== undefined }
        function tick() {
            const now = win.nowSecs()
            for (const w of win.ws.watches.slice()) {
                if (w.done || now - w.last_checked < w.every_minutes * 60) continue
                if (!win.find(w.tab_uid)) { win.op({ op: "update_watch", id: w.id, now: now, result: "The tab is gone", done: true }); continue }
                const t = win.ensureLive(w.tab_uid)
                waitingLoad[w.tab_uid] = w.id
                win.op({ op: "update_watch", id: w.id, now: now, result: w.last_result })
                if (!t.started) t.wake(); else t.view.reload()
            }
        }
        function pageLoaded(t) {
            const wid = waitingLoad[t.uid]
            if (wid === undefined) return
            delete waitingLoad[t.uid]
            const w = win.ws.watches.find(x => x.id === wid)
            if (!w) return
            win.readPage(t, p => {
                if (!p || p.private) return
                const id = nextId++
                pending[id] = wid
                browser.agentWatch(id, w.condition, JSON.stringify(p))
            })
        }
        function finished(id, r) {
            const wid = pending[id]; delete pending[id]
            const w = win.ws.watches.find(x => x.id === wid)
            if (!w) return
            const text = (r.text || "").trim()
            const met = /^MET\b/i.test(text)
            const said = text.replace(/^(NOT )?MET:\s*/i, "")
            win.op({ op: "update_watch", id: wid, now: win.nowSecs(), result: said, done: met })
            if (met) {
                browser.notify("Qi: " + w.condition, said)
                agentPanel.addNote("\ud83d\udc41 " + w.condition + " — " + said)
            }
        }
        function failed(id, e) { delete pending[id] }
    }
    Timer { interval: 60000; running: win.started && win.ws.watches.length > 0; repeat: true; onTriggered: watcher.tick() }

    // ---- Extensions from the Web Store -------------------------------------
    function installExtension(profile, input) {
        status.show("Fetching the extension\u2026")
        settings.extensionMessage("Fetching\u2026")
        browser.fetchExtension(profile, input)
    }
    function extensionReady(profile, dir, name, error) {
        if (error.length) { status.show(error); settings.extensionMessage(error); return }
        const p = engineProfile(profile)
        if (!p.extensionManager) { status.show("This Qt WebEngine was built without extension support"); return }
        p.extensionManager.installExtension(dir)
        settings.extensionMessage("Installing " + name + "\u2026")
    }
    function openSettings(section) { settings.show(section) }
    function openLibrary(tab) { library.show(tab) }

    // Reading mode: the article alone, in the theme's colours and font.
    function readerMode() {
        if (!currentTab || currentTab.blank) return
        const t = currentTab
        t.view.runJavaScript("(function(){var c=document.querySelector('article')||document.querySelector('main');" +
            "if(!c){var best=null,score=0;document.querySelectorAll('div,section').forEach(function(d){var n=d.querySelectorAll(':scope > p').length;if(n>score){score=n;best=d;}});c=best||document.body;}" +
            "var x=c.cloneNode(true);x.querySelectorAll('script,style,noscript,iframe,form,nav,aside,button,svg,[aria-hidden=true]').forEach(function(e){e.remove();});" +
            "x.querySelectorAll('*').forEach(function(e){for(var i=e.attributes.length-1;i>=0;i--){var a=e.attributes[i].name;if(a!=='href'&&a!=='src'&&a!=='alt')e.removeAttribute(a);}});" +
            "return JSON.stringify({title:document.title,html:x.innerHTML});})()", WebEngineScript.ApplicationWorld, r => {
                let p = null
                try { p = JSON.parse(r) } catch (e) { return }
                const css = "body{background:" + pal.bg + ";color:" + pal.fg + ";font-family:'" + pal.font + "',serif;max-width:44em;margin:3em auto;padding:0 1.5em;line-height:1.65;font-size:17px}" +
                    "h1,h2,h3{color:" + pal.fgBright + ";line-height:1.25}a{color:" + pal.accent + "}img{max-width:100%;height:auto}pre,code{background:" + pal.bgDark + ";padding:.1em .3em}" +
                    "blockquote{border-left:3px solid " + pal.accent + ";margin-left:0;padding-left:1em;color:" + pal.fgDark + "}"
                peek.openHtml("<!doctype html><meta charset=utf-8><style>" + css + "</style><h1>" + p.title.replace(/</g, "&lt;") + "</h1>" + p.html, t.url, t.profile, "Reading: " + p.title)
            })
    }
    // Hide something: pick an element; it stays hidden on this site.
    function pickToHide() {
        if (!currentTab || currentTab.blank) return
        status.show("Click what to hide · Esc to stop")
        currentTab.view.runJavaScript("(function(T){if(window.__qiPick)return;window.__qiPick=1;var box=document.createElement('div');" +
            "box.style.cssText='position:fixed;pointer-events:none;z-index:2147483647;border:2px solid " + pal.accent + ";background:rgba(122,162,247,.15);border-radius:3px';document.documentElement.appendChild(box);var cur=null;" +
            "function sel(e){if(e.id&&!/\\d{3,}/.test(e.id))return '#'+CSS.escape(e.id);var p=[];while(e&&e.nodeType===1&&e!==document.body&&p.length<5){var s=e.tagName.toLowerCase();" +
            "var cl=Array.prototype.filter.call(e.classList,function(c){return !/\\d{3,}|^(is|has)-/.test(c)}).slice(0,2);if(cl.length)s+='.'+cl.map(CSS.escape).join('.');" +
            "var par=e.parentElement;if(par&&!cl.length){var same=Array.prototype.filter.call(par.children,function(c){return c.tagName===e.tagName});if(same.length>1)s+=':nth-of-type('+(same.indexOf(e)+1)+')';}p.unshift(s);if(e.id)break;e=par;}return p.join(' > ');}" +
            "function mv(ev){cur=ev.target;var r=cur.getBoundingClientRect();box.style.left=r.left+'px';box.style.top=r.top+'px';box.style.width=r.width+'px';box.style.height=r.height+'px';}" +
            "function end(){document.removeEventListener('mousemove',mv,true);document.removeEventListener('click',ck,true);document.removeEventListener('keydown',kd,true);box.remove();window.__qiPick=0;}" +
            "function ck(ev){ev.preventDefault();ev.stopPropagation();var s=sel(cur);end();console.log(T+'hide:'+s);}" +
            "function kd(ev){if(ev.key==='Escape'){end();}}" +
            "document.addEventListener('mousemove',mv,true);document.addEventListener('click',ck,true);document.addEventListener('keydown',kd,true);})(" + JSON.stringify(token) + ")",
            WebEngineScript.ApplicationWorld)
    }

    // ---- Keyboard: Ctrl/Alt only, so Super stays Hyprland's ----------------
    component Key: Shortcut { context: Qt.ApplicationShortcut }
    Key { sequences: ["Ctrl+L", "Alt+D", "F6"]; onActivated: win.focusOmnibox() }
    Key { sequences: ["Ctrl+K"]; onActivated: win.focusOmnibox(true) }
    Key { sequences: ["Ctrl+T"]; onActivated: win.newTab("", true, false, win.currentUid) }
    Key { sequences: ["Ctrl+Shift+N"]; onActivated: win.newTab("", true, true, win.currentUid) }
    Key { sequences: ["Ctrl+W", "Ctrl+F4"]; onActivated: if (win.currentUid.length) win.closeUid(win.currentUid) }
    Key { sequences: ["Ctrl+Shift+T"]; onActivated: win.reopenClosed() }
    Key { sequences: ["Ctrl+Tab", "Ctrl+PgDown"]; onActivated: win.stepTab(1) }
    Key { sequences: ["Ctrl+Shift+Tab", "Ctrl+PgUp"]; onActivated: win.stepTab(-1) }
    Key { sequences: ["Ctrl+Shift+PgDown"]; onActivated: win.moveCurrent(1) }
    Key { sequences: ["Ctrl+Shift+PgUp"]; onActivated: win.moveCurrent(-1) }
    Repeater {
        model: 9
        delegate: Item {
            required property int index
            Shortcut { sequences: ["Ctrl+" + (index + 1), "Alt+" + (index + 1)]; context: Qt.ApplicationShortcut; onActivated: win.selectIndex(index === 8 ? -1 : index) }
            Shortcut { sequences: ["Ctrl+Alt+" + (index + 1)]; context: Qt.ApplicationShortcut; onActivated: if (index < win.ws.spaces.length) win.switchSpace(win.ws.spaces[index].id) }
        }
    }
    Key { sequences: ["Ctrl+Alt+Right", "Ctrl+Alt+]"]; onActivated: win.stepSpace(1) }
    Key { sequences: ["Ctrl+Alt+Left", "Ctrl+Alt+["]; onActivated: win.stepSpace(-1) }
    Key { sequences: ["Ctrl+Alt+N"]; onActivated: win.newSpace() }
    Key { sequences: ["Alt+Left", "Back"]; onActivated: if (win.currentTab) win.currentTab.view.goBack() }
    Key { sequences: ["Alt+Right", "Forward"]; onActivated: if (win.currentTab) win.currentTab.view.goForward() }
    Key { sequences: ["Ctrl+R", "F5"]; onActivated: if (win.currentTab) win.currentTab.view.reload() }
    Key { sequences: ["Ctrl+Shift+R", "Shift+F5"]; onActivated: if (win.currentTab) win.currentTab.view.reloadAndBypassCache() }
    Shortcut { sequences: ["Escape"]; enabled: win.currentTab !== null && win.currentTab.loading && !palette.visible && !peek.visible; onActivated: win.currentTab.view.stop() }
    Key { sequences: ["Ctrl+F"]; onActivated: findBar.open() }
    Key { sequences: ["Ctrl+G", "F3"]; onActivated: findBar.next(false) }
    Key { sequences: ["Ctrl+Shift+G", "Shift+F3"]; onActivated: findBar.next(true) }
    Key { sequences: ["Ctrl+=", "Ctrl++"]; onActivated: if (win.currentTab) win.currentTab.zoomBy(0.1) }
    Key { sequences: ["Ctrl+-"]; onActivated: if (win.currentTab) win.currentTab.zoomBy(-0.1) }
    Key { sequences: ["Ctrl+0"]; onActivated: if (win.currentTab) win.currentTab.zoom = (win.cfg.zoom || 1.0) }
    Key { sequences: ["Ctrl+Shift+B", "Ctrl+S"]; onActivated: win.toggleSidebar() }
    Key { sequences: ["F11"]; onActivated: win.visibility === Window.FullScreen ? win.showNormal() : win.showFullScreen() }
    Key { sequences: ["Ctrl+U"]; onActivated: if (win.currentTab) win.newTab("view-source:" + win.currentTab.url, true, win.currentTab.isPrivate, win.currentUid) }
    Key { sequences: ["F12", "Ctrl+Shift+I"]; onActivated: if (win.currentTab) win.currentTab.toggleDevTools() }
    Key { sequences: ["Ctrl+Shift+C"]; onActivated: if (win.currentTab) win.copyText(win.currentTab.url.toString()) }
    Key { sequences: ["Ctrl+Shift+V"]; onActivated: { clip.text = ""; clip.paste(); if (clip.text.trim().length) win.go(clip.text.trim()) } }
    Key { sequences: ["Ctrl+Q"]; onActivated: { win.saveNow(); Qt.quit() } }
    Key { sequences: ["Ctrl+Shift+A"]; onActivated: win.toggleAgent() }
    Key { sequences: ["Ctrl+D"]; onActivated: win.togglePinCurrent() }
    Key { sequences: ["Ctrl+Shift+D"]; onActivated: if (win.currentUid.length) win.bookmarkUid(win.currentUid) }
    Key { sequences: ["Ctrl+Alt+B"]; onActivated: win.openLibrary("bookmarks") }
    Key { sequences: ["Ctrl+H", "Ctrl+Y"]; onActivated: win.openLibrary("history") }
    Key { sequences: ["Ctrl+Shift+J", "Ctrl+J"]; onActivated: win.openLibrary("downloads") }
    Key { sequences: ["Ctrl+Alt+A"]; onActivated: win.openLibrary("archive") }
    Key { sequences: ["Ctrl+,"]; onActivated: win.openSettings("general") }
    Key { sequences: ["Ctrl+Alt+S"]; onActivated: if (win.currentUid.length) win.splitWith(win.currentUid) }
    Key { sequences: ["Ctrl+Alt+R"]; onActivated: win.readerMode() }
    Key { sequences: ["Ctrl+Shift+H"]; onActivated: win.pickToHide() }
    Key { sequences: ["Ctrl+E"]; onActivated: siteControls.visible ? siteControls.close() : siteControls.open() }
    Key { sequences: ["Ctrl+Alt+L"]; onActivated: loginBar.fillNow() }
    TextEdit { id: clip; visible: false }

    function moveCurrent(d) {
        const list = orderedUids()
        const i = list.indexOf(currentUid)
        const j = i + d
        if (i < 0 || j < 0 || j >= list.length) return
        const other = find(list[j]).rec
        const me = find(currentUid).rec
        if (other.pinned !== me.pinned || other.folder !== me.folder) return
        op({ op: "move_tab", uid: currentUid, before: d > 0 ? (list[j + 1] || "") : list[j], pinned: me.pinned, folder: me.folder })
    }

    // ---- Layout ------------------------------------------------------------
    // Default (tabs = "sidebar"): no frame, no toolbar, the page edge to
    // edge. The sidebar slides over the page from the left edge, or sits
    // beside it when pinned; the agent panel sits on the right.
    readonly property int sidebarWidth: 260
    readonly property int agentWidth: Math.min(420, Math.max(320, width * 0.28))
    readonly property bool sidebarOpen: sidebarMode && fullscreenTab === null && (sidebarPinned || sidebarPeek)
    readonly property bool resizable: frameless && visibility === Window.Windowed && fullscreenTab === null

    function toggleSidebar() {
        if (!sidebarMode) { compact = !compact; return }
        if (sidebarPinned) { sidebarPinned = false; sidebarPeek = sidebar.hovered }
        else { sidebarPinned = true; sidebarPeek = false }
    }
    function toggleMaximized() { if (visibility === Window.Maximized) showNormal(); else showMaximized() }

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
            tabs: win.spaceTabRows
            current: win.spaceTabRows.findIndex(r => r.uid === win.currentUid)
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            onActivate: i => win.selectUid(win.spaceTabRows[i].uid)
            onCloseTab: i => win.closeUid(win.spaceTabRows[i].uid)
            onNewTab: win.newTab("", true)
            DragHandler { target: null; enabled: win.frameless; onActiveChanged: if (active) win.startSystemMove() }
        }
        Rectangle {
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
                NavButton { glyph: win.currentTab && win.currentTab.loading ? "\u2715" : "\u21bb"; tip: "Reload (Ctrl+R)"; enabled: win.currentTab !== null; onClicked: win.reloadOrStop() }
                Omnibox {
                    id: omnibox
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                    pal: pal
                    browser: browser
                    tabs: win.allTabRows
                    currentTab: win.currentTab
                    profileName: win.profileOfCurrent()
                    onGo: text => win.go(text)
                    onSwitchTo: i => win.selectUid(win.allTabRows[i].uid)
                    onDismissed: { win.chromePeek = false; if (win.currentTab) win.currentTab.view.forceActiveFocus() }
                }
                NavButton { glyph: win.currentBookmarked ? "\u2605" : "\u2606"; tip: "Bookmark (Ctrl+Shift+D)"; onClicked: win.bookmarkUid(win.currentUid) }
                Repeater {
                    model: win.extensionButtons
                    delegate: NavButton {
                        required property var modelData
                        tip: modelData.name
                        glyph: modelData.icon.length ? "" : modelData.name.charAt(0)
                        Image { anchors.centerIn: parent; width: 16; height: 16; source: parent.modelData.icon; visible: source.toString().length > 0 }
                        onClicked: win.openExtensionPopup(modelData)
                    }
                }
                NavButton { glyph: "\u2726"; tip: "Agent (Ctrl+Shift+A)"; onClicked: win.toggleAgent() }
                NavButton { glyph: "\u2699"; tip: "Settings (Ctrl+,)"; onClicked: win.openSettings("general") }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: pal.muted; opacity: 0.35 }
        }
    }

    // The page, edge to edge.
    Item {
        id: pageArea
        anchors.top: topChrome.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: win.sidebarMode && win.sidebarPinned && win.fullscreenTab === null ? win.sidebarWidth : 0
        anchors.rightMargin: win.agentOpen && win.fullscreenTab === null ? win.agentWidth : 0
        Behavior on anchors.leftMargin { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on anchors.rightMargin { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Item {
            id: viewArea
            anchors.fill: parent
            clip: true
            StartPage {
                anchors.fill: parent
                visible: win.currentTab !== null && win.currentTab.blank && !win.splitUid.length
                pal: pal
                browser: browser
                isPrivate: win.currentTab !== null && win.currentTab.isPrivate
                profileName: win.profileOfCurrent()
                onOpen: url => win.go(url)
                z: 5
            }
            // Split view: drag the divider; click a side to make it current.
            Rectangle {
                id: divider
                z: 6
                visible: win.splitUid.length > 0 && win.splitUid !== win.currentUid
                x: parent.width * win.splitRatio - 3
                width: 6
                height: parent.height
                color: dividerMouse.containsMouse || dividerMouse.pressed ? pal.accent : pal.muted
                MouseArea {
                    id: dividerMouse
                    anchors.fill: parent
                    anchors.margins: -3
                    hoverEnabled: true
                    cursorShape: Qt.SplitHCursor
                    onPositionChanged: m => { if (pressed) { win.splitRatio = Math.max(0.2, Math.min(0.8, (divider.x + m.x) / viewArea.width)); win.applyTabStates() } }
                    onDoubleClicked: win.splitUid = ""
                }
            }
        }

        Rectangle {
            z: 15
            anchors.top: parent.top
            anchors.left: parent.left
            height: 2
            color: win.currentSpace ? win.spaceColor(win.currentSpace.color) : pal.accent
            width: win.currentTab && win.currentTab.loading ? parent.width * win.currentTab.progress / 100 : 0
            visible: width > 0
            Behavior on width { NumberAnimation { duration: 120 } }
        }

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

        // "Add to Qi" on Chrome Web Store pages.
        Rectangle {
            id: storeButton
            z: 26
            property string extId: ""
            function check() {
                const u = win.currentTab ? win.currentTab.url.toString() : ""
                extId = u.length && browser.isStorePage(u) ? browser.storeId(u) : ""
            }
            visible: extId.length > 0 && !win.currentTab.isPrivate
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 64
            anchors.rightMargin: 16
            width: storeText.implicitWidth + 28
            height: 34
            radius: 17
            color: storeMouse.containsMouse ? pal.fgBright : pal.accent
            Text { id: storeText; anchors.centerIn: parent; text: "Add to Qi (" + win.profileOfCurrent() + ")"; color: pal.onAccent; font.family: pal.font; font.bold: true }
            MouseArea { id: storeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.installExtension(win.profileOfCurrent(), storeButton.extId) }
        }

        // Saved logins: offer to fill, or to save one just typed.
        Rectangle {
            id: loginBar
            z: 27
            property var saved: []
            property var offer: null
            property var tab: null
            function check(t) {
                tab = t
                offer = null
                saved = t && !t.isPrivate && !t.blank && browser.passwordsAvailable() ? JSON.parse(browser.passwords(t.profileName, t.url.toString())) : []
            }
            function offerSave(t, login) {
                if (!browser.passwordsAvailable() || !login.password) return
                tab = t
                const known = JSON.parse(browser.passwords(t.profileName, login.url)).some(p => p.username === login.username)
                if (!known) offer = login
            }
            function fill(entry) {
                const pw = browser.passwordFor(tab.profileName, entry.origin, entry.username)
                if (!pw.length) { status.show("The keyring didn't give the password"); return }
                tab.view.runJavaScript("(function(u,p){var pw=document.querySelector('input[type=password]');if(!pw)return;" +
                    "var set=function(e,v){var d=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(e),'value');d.set.call(e,v);e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));};" +
                    "var ins=Array.prototype.slice.call(document.querySelectorAll('input'));for(var i=ins.indexOf(pw)-1;i>=0;i--){var t=(ins[i].type||'text').toLowerCase();if(t==='text'||t==='email'||t==='tel'){set(ins[i],u);break;}}set(pw,p);})(" +
                    JSON.stringify(entry.username) + "," + JSON.stringify(pw) + ")", WebEngineScript.ApplicationWorld)
                saved = []
            }
            function fillNow() { if (saved.length) fill(saved[0]); else status.show("No saved login for this site") }
            visible: tab === win.currentTab && (offer !== null || saved.length > 0)
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 18
            width: loginRow.implicitWidth + 24
            height: 40
            radius: 10
            color: pal.bgDark
            border.color: pal.accent
            RowLayout {
                id: loginRow
                anchors.centerIn: parent
                spacing: 8
                Text {
                    color: pal.fg
                    font.family: pal.font
                    text: loginBar.offer ? "Save the password for " + (loginBar.offer.username || "this site") + " in the keyring?" : "Saved login: " + (loginBar.saved.length ? loginBar.saved[0].username : "")
                }
                Widgets.Btn { pal: pal; text: loginBar.offer ? "Save" : "Fill (Ctrl+Alt+L)"; primary: true
                    onClicked: {
                        if (loginBar.offer) { const o = loginBar.offer; browser.savePassword(loginBar.tab.profileName, o.url, o.username, o.password); loginBar.offer = null; status.show("Saved to the keyring") }
                        else loginBar.fill(loginBar.saved[0])
                    } }
                Widgets.Btn { pal: pal; text: loginBar.offer ? "Never mind" : "\u2715"; onClicked: { loginBar.offer = null; loginBar.saved = [] } }
            }
        }

        // Site controls (Ctrl+E): blocking, hidden elements, permissions.
        Rectangle {
            id: siteControls
            z: 28
            visible: false
            function open() { if (win.currentTab && !win.currentTab.blank) { visible = true; rules = JSON.parse(browser.hiddenRules(win.currentTab.host)) } }
            function close() { visible = false }
            property var rules: []
            readonly property string host: win.currentTab ? win.currentTab.host : ""
            readonly property bool allowed: win.cfg.blocker && win.cfg.blocker.allow ? win.cfg.blocker.allow.indexOf(host) >= 0 : false
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 12
            width: 320
            height: scCol.implicitHeight + 24
            radius: 10
            color: pal.bgDark
            border.color: pal.muted
            MouseArea { anchors.fill: parent }
            ColumnLayout {
                id: scCol
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8
                Widgets.Label { pal: pal; text: siteControls.host; font.bold: true; color: pal.fgBright }
                Widgets.Label { pal: pal; text: (win.currentTab ? win.currentTab.blockedCount : 0) + " ads and trackers blocked on this page" }
                Widgets.Toggle {
                    pal: pal
                    text: "Block ads and trackers here"
                    checked: !siteControls.allowed
                    onToggled: {
                        let allow = (win.cfg.blocker && win.cfg.blocker.allow ? win.cfg.blocker.allow : []).filter(h => h !== siteControls.host)
                        if (!checked) allow.push(siteControls.host)
                        const err = browser.setSetting("blocker.allow", JSON.stringify(allow))
                        if (err.length) status.show(err); else win.currentTab.view.reload()
                    }
                }
                Widgets.Label { pal: pal; text: siteControls.rules.length ? siteControls.rules.length + " hidden element(s)" : "Nothing hidden (Ctrl+Shift+H to hide something)" }
                RowLayout {
                    Widgets.Btn { pal: pal; text: "Hide something"; onClicked: { siteControls.close(); win.pickToHide() } }
                    Widgets.Btn { pal: pal; text: "Show all again"; visible: siteControls.rules.length > 0; onClicked: { browser.clearHideRules(siteControls.host); siteControls.rules = []; win.currentTab.view.reload() } }
                }
                RowLayout {
                    Widgets.Btn { pal: pal; text: "Reader (Ctrl+Alt+R)"; onClicked: { siteControls.close(); win.readerMode() } }
                    Widgets.Btn { pal: pal; text: "Clear cookies"; onClicked: { WebTools.clearCookies(win.currentTab.profileName); status.show("Cookies cleared for this profile") } }
                }
                Widgets.Btn { pal: pal; text: "Close"; onClicked: siteControls.close() }
            }
        }

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
            Text { id: statusText; anchors.centerIn: parent; width: parent.width - 16; elide: Text.ElideMiddle; text: status.shown; color: pal.fg; font.family: pal.font; font.pixelSize: pal.fontSize - 1 }
            Timer { id: statusTimer; interval: 3500; onTriggered: status.message = "" }
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
        host: win
        currentTab: win.currentTab
        pinned: win.sidebarPinned
        onOpenPalette: win.focusOmnibox()
        onTogglePin: win.toggleSidebar()
        onWindowMove: win.startSystemMove()
        onWindowToggleMaximized: win.toggleMaximized()
    }

    // ---- Agent panel, on the right -------------------------------------------
    AgentPanel {
        id: agentPanel
        z: 45
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: win.agentWidth
        x: win.agentOpen && win.fullscreenTab === null ? win.width - width : win.width + 16
        visible: x < win.width
        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        pal: pal
        browser: browser
        host: win
        accent: win.currentSpace ? win.spaceColor(win.currentSpace.color) : pal.accent
    }

    // ---- Command palette: the address field, on demand -----------------------
    Item {
        id: palette
        anchors.fill: parent
        z: 100
        visible: false
        function open(tabsOnly) { visible = true; paletteBox.focusField(tabsOnly) }
        function close() {
            if (!visible) return
            visible = false
            if (win.currentTab && !win.currentTab.blank) win.currentTab.view.forceActiveFocus()
            if (!sidebar.hovered) peekTimer.restart()
        }
        Rectangle { anchors.fill: parent; color: "black"; opacity: 0.28 }
        MouseArea { anchors.fill: parent; onClicked: palette.close() }
        Rectangle {
            width: Math.min(680, parent.width - 60)
            height: 48
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height * 0.16)
            radius: 10
            color: pal.bgDark
            border.width: 1
            border.color: win.currentSpace ? win.spaceColor(win.currentSpace.color) : pal.accent
            MouseArea { anchors.fill: parent }
            Omnibox {
                id: paletteBox
                anchors.fill: parent
                anchors.margins: 6
                pal: pal
                browser: browser
                tabs: win.allTabRows
                currentTab: win.currentTab
                profileName: win.profileOfCurrent()
                onGo: text => { palette.close(); win.go(text) }
                onSwitchTo: i => { const u = win.allTabRows[i].uid; palette.close(); win.selectUid(u) }
                onDismissed: palette.close()
                onEditingChanged: if (!editing) Qt.callLater(() => { if (!paletteBox.editing) palette.close() })
            }
        }
    }

    // ---- Peek, library, settings, extension popups ----------------------------
    Peek {
        id: peek
        z: 110
        anchors.fill: parent
        pal: pal
        host: win
    }
    Library {
        id: library
        z: 120
        anchors.fill: parent
        pal: pal
        browser: browser
        host: win
    }
    Settings {
        id: settings
        z: 130
        anchors.fill: parent
        pal: pal
        browser: browser
        host: win
    }
    Item {
        id: extPopup
        z: 140
        anchors.fill: parent
        visible: false
        property var ext: null
        function show(e, profile) {
            ext = e
            popupView.profile = profile
            popupView.url = e.popup
            visible = true
        }
        function close() { visible = false; popupView.url = "about:blank" }
        MouseArea { anchors.fill: parent; onClicked: extPopup.close() }
        Rectangle {
            x: win.sidebarPinned ? win.sidebarWidth + 8 : parent.width - width - 12
            y: 48
            width: 380
            height: Math.min(560, parent.height - 80)
            radius: 10
            color: pal.bgDark
            border.color: pal.accent
            clip: true
            MouseArea { anchors.fill: parent }
            Text { id: popupTitle; x: 12; y: 8; text: extPopup.ext ? extPopup.ext.name : ""; color: pal.fgBright; font.family: pal.font; font.bold: true }
            WebEngineView {
                id: popupView
                anchors.fill: parent
                anchors.topMargin: 30
                anchors.margins: 2
                onWindowCloseRequested: extPopup.close()
                onNewWindowRequested: request => { const nt = win.newTab("", true); if (nt) request.openIn(nt.view); extPopup.close() }
            }
        }
    }
    Shortcut { sequences: ["Escape"]; enabled: extPopup.visible; onActivated: extPopup.close() }

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
