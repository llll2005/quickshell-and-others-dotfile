import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Networking
import Quickshell.Hyprland
import Quickshell.Bluetooth
import "../services"
import "../components"
import "../theme"
import "../settings"

// ═════════════════════════════════════════════════════════════════════
//   NieR Control Center — Quickshell module
//   Portage 1:1 du mockup HTML v4
//   Asset requis : ~/.config/quickshell/assets/nier-arrow.png
//   IPC : qs ipc call ctrl toggle
// ═════════════════════════════════════════════════════════════════════

// Window, lifecycle, glass backdrop, warm-up and rhythm: components/Popup.qml.
Popup {
    id: root
    dimAmount: Math.min(1, Settings.backdropDim + 0.12)   // a touch darker than the other popups
    autoPanelGone: true      // the cross fades with `live`; the triangles' scatter is the longer part

    // ── Paths ──
    property string home:          Quickshell.env("HOME")
    property string xdgConfigHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
    property string assetsDir:     xdgConfigHome + "/quickshell/assets"
    property string arrowPng:      "file://" + assetsDir + "/nier-arrow.png"

    // ── Palette NieR (shared with ScreenCapture / Menu) ──
    readonly property color colCard:     Theme.paper   // paper
    readonly property color colCardSoft: Theme.alpha(Theme.paper, 0.4)
    readonly property color colInk:      Theme.ink   // ink
    readonly property color colInkSoft:  Theme.inkSoft
    readonly property color colHi:       Theme.inkStrong   // ink strong
    readonly property color colLight:    Theme.light   // glints
    readonly property color colAccent:   Theme.accent

    // ── Layout ──
    readonly property int  slotGapV: 150
    readonly property int  slotGapH: 350
    readonly property int  panShiftV: 320   // vertical (top/bottom) : centre l'ensemble sub+settings
    readonly property int  panShiftH: 700   // horizontal (left/right) : sub-menu traverse l'écran

    // ── État ──
    readonly property bool closing: phase === "closing"   // the slots fold back to the centre, then fade
    property int    level:   1
    property string slot:    "center"
    property string sub:     ""
    property string action:  ""
    property bool   atAction: false  // true = action-navigation mode (user's level 3)

    // ── Power mode ──
    // ↵ on the centre turns the cross over: the arms become the power actions (top Lock ·
    // Sleep, left Log out, right Reboot · UEFI, bottom Shut down · Hibernate) and the
    // centre leads back. ↵ on one runs it: Lock at once, the rest through `exitKey` (the
    // triangles collapse, the screen goes dark, the command runs), and all but Sleep ask
    // first on a YES / NO card (NO by default).
    property string mode: "main"            // "main" · "power"
    readonly property bool power: mode === "power"
    property bool   folded: false           // the arms tucked into the centre while the cross turns over
    property string _nextMode: "main"
    property string confirmKey: ""          // the action the YES / NO card asks about
    property bool   confirmYes: false
    property double _cardAt: 0
    property string exitKey: ""             // the action under way (the dark screen)
    property string exitError: ""
    property real   exitFade: 0

    // `ready`: the frame for the glass backdrop has been captured. The cross stays
    // hidden until then so it never ends up refracted in its own backdrop.
    property bool ready: false
    readonly property bool live: phase === "open" && ready

    // ── Hit feel ──
    // kick: a short shove along kickDir whenever the depth changes (enter / back)
    property real  kick: 0
    property point kickDir: Qt.point(0, 0)
    SequentialAnimation {
        id: kickAnim
        NumberAnimation { target: root; property: "kick"; from: 0; to: 1; duration: 70;  easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "kick"; to: 0;          duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
    }
    // depthPop: the nav bar's depth diamond clicks on every depth change
    property real depthPop: 0
    SequentialAnimation {
        id: depthPopAnim
        NumberAnimation { target: root; property: "depthPop"; from: 0; to: 1; duration: 60;  easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "depthPop"; to: 0;          duration: 340; easing.type: Easing.OutBack }
    }
    property int _prevDepth: 1
    onDepthChanged: {
        var sd = ({top: Qt.point(0, -1), bottom: Qt.point(0, 1), left: Qt.point(-1, 0), right: Qt.point(1, 0)})[slot] || Qt.point(0, 0)
        var deep = Qt.point(deeperDir() === "left" ? -1 : 1, 0)
        var d = depth, pd = _prevDepth
        if (pd === 1 && d === 2)      kickDir = sd                                   // into the section
        else if (pd === 2 && d === 3) kickDir = deep                                 // into its actions
        else if (pd === 3 && d === 2) kickDir = Qt.point(-deep.x, 0)                 // back out of them
        else if (pd === 2 && d === 1) kickDir = Qt.point(-sd.x, -sd.y)               // back to the cross
        else kickDir = Qt.point(0, 0)
        _prevDepth = d
        if (isOpen) { kickAnim.restart(); depthPopAnim.restart() }
    }
    // press: every focus move squashes the newly focused item and springs it back
    property real press: 0
    SequentialAnimation {
        id: pressAnim
        NumberAnimation { target: root; property: "press"; from: 0; to: 1; duration: 45;  easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "press"; to: 0;          duration: 230; easing.type: Easing.OutBack; easing.overshoot: 2.6 }
    }
    // bump: pressing past the end of a list pushes the selector that way and back
    property real bump: 0
    property int  bumpDir: 0
    SequentialAnimation {
        id: bumpAnim
        NumberAnimation { target: root; property: "bump"; from: 0; to: 1; duration: 60;  easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "bump"; to: 0;          duration: 280; easing.type: Easing.OutBack; easing.overshoot: 3 }
    }
    function bumpAt(d) { bumpDir = d; bumpAnim.restart() }
    function focusScale(d) { return depth === d ? 1 - 0.07 * press + (hitDepth === d ? 0.06 * hitT : 0) : 1 }
    // hit-stop on ↵ / click: the focused item pops and holds for a beat, throws an
    // impact (shards + a ring through the backdrop), then the action runs
    property real hitT: 0
    property int  hitDepth: 0           // the depth whose focused item is being hit
    property bool _hitting: false
    signal confirmPulse(real strength)                          // the focused item answers with impactAt
    signal impactAt(var win, real x, real y, real strength)     // its window draws the burst
    SequentialAnimation {
        id: hitAnim
        NumberAnimation { target: root; property: "hitT"; from: 0; to: 1; duration: 45; easing.type: Easing.OutQuad }
        PauseAnimation { duration: 55 }
        ScriptAction { script: root._afterHit() }
        NumberAnimation { target: root; property: "hitT"; to: 0; duration: 220; easing.type: Easing.OutCubic }
        ScriptAction { script: { root._hitting = false; root.hitDepth = 0 } }
    }

    // ── Données ──
    readonly property var subs: ({
        top:    [ {key:"wifi",      label:"Wi-Fi"},
                  {key:"bluetooth", label:"Bluetooth"} ],
        bottom: [ {key:"output",    label:"Output"},
                  {key:"volume",    label:"Volume"} ],
        left:   [ {key:"send",      label:"Send"},
                  {key:"receive",   label:"Receive"} ],
        right:  [ {key:"history",   label:"History"},
                  {key:"dnd",       label:"Do Not Disturb"} ]
    })

    readonly property var details: ({
        "top.wifi":         {h3:"Wi-Fi",               status:"—",    on:false,
                              actions:[{key:"toggle",label:"Toggle Wi-Fi"}]},
        "top.bluetooth":    {h3:"Bluetooth",           status:"—",    on:false,
                              actions:[{key:"toggle",label:"Toggle Bluetooth"}]},
        "bottom.output":    {h3:"Audio Output",        status:"—",    on:false,
                              actions:[{key:"placeholder",label:"Sub-menu coming"}]},
        "bottom.volume":    {h3:"Volume",              status:"—",    on:false,
                              actions:[{key:"placeholder",label:"Sub-menu coming"}]},
        "left.send":        {h3:"Send Files",          status:"Ready", on:false,
                              actions:[{key:"placeholder",label:"Sub-menu coming"}]},
        "left.receive":     {h3:"Receive Files",       status:"—",    on:false,
                              actions:[{key:"placeholder",label:"Sub-menu coming"}]},
        "right.history":    {h3:"Notification History",status:"—",    on:false,
                              actions:[{key:"placeholder",label:"Sub-menu coming"}]},
        "right.dnd":        {h3:"Do Not Disturb",      status:"—",    on:false,
                              actions:[{key:"placeholder",label:"Sub-menu coming"}]}
    })

    // ── Power actions ──
    readonly property var powerSubs: ({
        top:    [ {key:"lock",      label:"Lock"},
                  {key:"sleep",     label:"Sleep"} ],
        left:   [ {key:"logout",    label:"Log out"} ],
        right:  [ {key:"reboot",    label:"Reboot"},
                  {key:"firmware",  label:"Reboot to UEFI"} ],
        bottom: [ {key:"poweroff",  label:"Shut down"},
                  {key:"hibernate", label:"Hibernate"} ]
    })
    // ask: the YES / NO card's question (none: runs at once) · exit: the dark screen's
    // line (none: Lock, which just closes the panel)
    readonly property var powerActs: ({
        lock:      { h3:"Lock", zh:"鎖定螢幕", exit:"", ask:"",
                     cmd:["sh", "-c", "~/.config/quickshell/scripts/lock.sh"],
                     hint:"鎖定螢幕（同 SUPER+L）；鎖屏起不來時自動改用 hyprlock。立即執行。" },
        sleep:     { h3:"Sleep", zh:"睡眠 · 暫停到記憶體", exit:"SLEEP MODE", ask:"",
                     cmd:["systemctl", "suspend"],
                     hint:"關掉螢幕、保留所有視窗；按鍵或開蓋喚醒，醒來先解鎖。立即執行。" },
        logout:    { h3:"Log out", zh:"登出 Hyprland", exit:"LOGGING OUT", ask:"登出？",
                     cmd:["hyprctl", "dispatch", "hl.dsp.exit()"],
                     hint:"關閉所有視窗並結束工作階段，回到登入畫面。",
                     warn:"所有視窗都會關閉，未儲存的工作會遺失。" },
        reboot:    { h3:"Reboot", zh:"重新開機", exit:"REBOOTING", ask:"重新開機？",
                     cmd:["systemctl", "reboot"],
                     hint:"關閉所有程式後重新開機。",
                     warn:"所有視窗都會關閉，未儲存的工作會遺失。" },
        firmware:  { h3:"Reboot to UEFI", zh:"重開進 BIOS / UEFI", exit:"ENTERING FIRMWARE SETUP", ask:"重開進 BIOS / UEFI？",
                     cmd:["systemctl", "reboot", "--firmware-setup"],
                     hint:"重新開機，並在下次開機時直接進入韌體設定畫面。",
                     warn:"會直接重開，未儲存的工作會遺失。" },
        poweroff:  { h3:"Shut down", zh:"關機", exit:"SYSTEM SHUTDOWN", ask:"關機？",
                     cmd:["systemctl", "poweroff"],
                     hint:"關閉所有程式後關機。",
                     warn:"所有視窗都會關閉，未儲存的工作會遺失。" },
        hibernate: { h3:"Hibernate", zh:"休眠 · 存到磁碟後斷電", exit:"HIBERNATING", ask:"休眠？",
                     cmd:["systemctl", "hibernate"],
                     hint:"把目前的工作狀態寫進 swap 後完全斷電，下次開機原樣還原。",
                     warn:"工作狀態會寫入 swap 後斷電。第一次使用前先存好工作。" }
    })

    function detailKey() { return slot + "." + sub }
    function subList(s)  { return (power ? root.powerSubs : root.subs)[s] || [] }
    function hasDetail() { return power ? (sub in root.powerActs) : (detailKey() in root.details) }

    // ── Construit la liste d'actions dynamique selon le sub focus ──
    function actList() {
        if (power) return []        // a power sub runs on ↵ itself: no action list
        var key = detailKey()
        // Wi-Fi : toggle + un bouton par réseau scanné
        if (key === "top.wifi") {
            var acts = [{key:"toggle", label: wifiEnabled ? "Disable Wi-Fi" : "Enable Wi-Fi"}]
            if (wifiEnabled) {
                for (var i = 0; i < wifiNetworks.length; i++) {
                    var n = wifiNetworks[i]
                    // ✓ connected · … connecting · saved profile · ⚿ needs a password
                    var prefix = n.active ? "✓ " : n.busy ? "… " : n.known ? "· " : "  "
                    var sigBars = ["▱▱▱", "▰▱▱", "▰▰▱", "▰▰▰"][n.bars]
                    var lock = n.secured && !n.known ? " ⚿" : "  "
                    acts.push({
                        key: "connect:" + n.ssid,
                        label: prefix + n.ssid + "  " + sigBars + lock
                    })
                }
            }
            return acts
        }
        // Bluetooth
        if (key === "top.bluetooth") {
            var acts2 = [{key:"toggle", label: btBlocked ? "Unblock Bluetooth" : btEnabled ? "Disable Bluetooth" : "Enable Bluetooth"}]
            if (btEnabled) {
                acts2.push({key: "scan", label: btScanning ? "◉ Scanning… (tap to stop)" : "⌕ Scan for new devices"})
                for (var j = 0; j < btDevices.length; j++) {
                    var d = btDevices[j]
                    var prefix = d.busy ? "… " : d.connected ? "✓ " : (d.paired ? "· " : "+ ")
                    var label = prefix + d.name + (d.battery >= 0 ? "  " + d.battery + "%" : "")
                    var aKey
                    if (d.connected)      aKey = "disconnect:" + d.mac
                    else if (d.paired)    aKey = "connect:"    + d.mac
                    else                  aKey = "pair:"       + d.mac
                    acts2.push({key: aKey, label: label})
                    if (d.paired) {
                        acts2.push({key: "remove:" + d.mac, label: "    × Remove " + d.name})
                    }
                }
            }
            return acts2
        }
        // Audio Output : liste des sinks
        if (key === "bottom.output") {
            var acts3 = []
            for (var k = 0; k < audioSinks.length; k++) {
                var s = audioSinks[k]
                var pre = s.isDefault ? "✓ " : "  "
                acts3.push({key: "set-sink:" + s.name, label: pre + s.description})
            }
            if (acts3.length === 0) acts3.push({key:"none", label:"No outputs found"})
            return acts3
        }
        // Audio Volume : pas de liste, juste le slider (rendu séparément)
        if (key === "bottom.volume") {
            return [{key:"mute-toggle", label: audioMuted ? "Unmute" : "Mute"}]
        }
        // Quickshare Send (qshare.py) — pick in a real file browser, then show a QR.
        // "Show QR" leads when something is picked so Enter twice = share.
        if (key === "left.send") {
            var acts4 = []
            if (pendingFiles.length > 0) {
                acts4.push({key:"start-send",   label: "▶ Show download QR"})
                acts4.push({key:"pick-files",   label: "⌕ Choose other files…"})
                acts4.push({key:"clear-files",  label: "× Clear selection"})
            } else {
                acts4.push({key:"pick-files",   label: "⌕ Choose files…"})
                acts4.push({key:"pick-folder",  label: "⌕ Choose a folder…"})
            }
            acts4.push({key:"toggle-net", label: qshareNetLabel()})
            return acts4
        }
        // Quickshare Receive (qshare.py)
        if (key === "left.receive") {
            var acts5 = []
            acts5.push({key:"start-recv",   label: "▶ Show upload QR"})
            acts5.push({key:"cycle-output", label: "Save to: " + qshareOutputShort() + " ▸"})
            acts5.push({key:"open-output",  label: "⌂ Open that folder"})
            acts5.push({key:"toggle-net",   label: qshareNetLabel()})
            return acts5
        }
        // Notifications History
        if (key === "right.history") {
            var acts6 = []
            for (var p = 0; p < notifications.length; p++) {
                var n2 = notifications[p]
                var nk = n2.key || (n2.id + "@" + n2.ts)
                acts6.push({
                    key: "notif:" + nk,
                    nkey: nk,
                    live: !!n2.live,
                    ts: n2.ts || 0,
                    label: n2.summary || "(empty)",
                    body: n2.body || "",
                    app: n2.app || "",
                    appIcon: n2.appIcon || "",
                    category: n2.category || "",
                    urgency: n2.urgency || "normal",
                    timeout: n2.timeout >= 0 ? n2.timeout : -1,
                    desktopEntry: n2.desktopEntry || "",
                    actions: n2.actions || []
                })
            }
            return acts6
        }
        // Notifications DND
        if (key === "right.dnd") {
            return [{key:"toggle-dnd", label: dndEnabled ? "Disable DND" : "Enable DND"}]
        }
        // Autres : actions statiques du dictionnaire details
        var dd = root.details[key]
        return dd ? dd.actions : []
    }

    function detailH3() {
        if (power) { var pa = root.powerActs[sub]; return pa ? pa.h3 : "" }
        var key = detailKey()
        if (key === "top.wifi")          return "Wi-Fi"
        if (key === "top.bluetooth")     return "Bluetooth"
        if (key === "bottom.output")     return "Audio Output"
        if (key === "bottom.volume")     return "Volume"
        if (key === "left.send")         return "Send Files"
        if (key === "left.receive")      return "Receive Files"
        if (key === "right.history")     return "Notifications"
        if (key === "right.dnd")         return "Do Not Disturb"
        var d = root.details[key]
        return d ? d.h3 : ""
    }
    function detailStatus() {
        if (power) { var pa = root.powerActs[sub]; return pa ? pa.zh : "" }
        var key = detailKey()
        if (key === "top.wifi") {
            if (!wifiEnabled) return "Disabled"
            if (wifiCurrentSSID) return "Connected · " + wifiCurrentSSID
            return "Enabled · Scanning"
        }
        if (key === "top.bluetooth") {
            if (!btEnabled) return "Disabled"
            var connected = btDevices.filter(function(d){return d.connected})
            if (connected.length) return "Connected · " + connected[0].name
            return "Enabled · " + btDevices.length + " device" + (btDevices.length !== 1 ? "s" : "")
        }
        if (key === "bottom.output") {
            // Trouver la description du default sink
            for (var i = 0; i < audioSinks.length; i++) {
                if (audioSinks[i].isDefault) return audioSinks[i].description
            }
            return audioDefaultSink || "—"
        }
        if (key === "bottom.volume") {
            if (audioMuted) return "Muted"
            return Math.round(audioVolume * 100) + "%"
        }
        if (key === "left.send") {
            if (pendingFiles.length === 0) return "Nothing picked yet"
            var n = pendingFiles.length
            var what = n === 1 ? fileName(pendingFiles[0])
                               : n + " items"
            return pendingSize !== "" ? what + " · " + pendingSize : what
        }
        if (key === "left.receive") {
            return "Phone → " + qshareOutputShort()
        }
        if (key === "right.history") {
            return notifications.length + " notification" + (notifications.length !== 1 ? "s" : "")
        }
        if (key === "right.dnd") {
            return dndEnabled ? "Active" : "Off"
        }
        var d2 = root.details[key]
        return d2 ? d2.status : ""
    }
    function detailOn() {
        if (power) return false
        var key = detailKey()
        if (key === "top.wifi")          return wifiEnabled
        if (key === "top.bluetooth")     return btEnabled
        if (key === "bottom.output")     return true
        if (key === "bottom.volume")     return !audioMuted
        if (key === "left.send")         return pendingFiles.length > 0
        if (key === "left.receive")      return qshareUrl !== ""
        if (key === "right.history")     return notifications.length > 0
        if (key === "right.dnd")         return dndEnabled
        var d3 = root.details[key]
        return d3 ? d3.on : false
    }

    // One-line plain-language explanation shown under the status dot.
    // Empty string = no hint row for this panel.
    function detailHint() {
        if (power) { var pa = root.powerActs[sub]; return pa ? pa.hint : "" }
        var key = detailKey()
        if (key === "left.send") {
            return qshareTunnel
                ? "Opens a page on your phone listing these files. Internet mode: works on mobile data, goes through Cloudflare."
                : "Opens a page on your phone listing these files. LAN mode: phone must be on the same Wi-Fi."
        }
        if (key === "left.receive") {
            return qshareTunnel
                ? "Scan, then pick files on your phone — they land in " + qshareOutputShort() + ". Internet mode: works on mobile data."
                : "Scan, then pick files on your phone — they land in " + qshareOutputShort() + ". LAN mode: same Wi-Fi required."
        }
        return ""
    }
    // ── Wi-Fi: native NetworkManager (Quickshell.Networking) ──
    // Event-driven, no nmcli polling. A network NM already knows (a saved profile) or
    // an open one connects straight away; only a new secured one asks for a password,
    // and a known one whose saved secret stopped working asks again (NoSecrets).
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property var  wifiDev: {
        var ds = Networking.devices.values
        for (var i = 0; i < ds.length; i++) if (ds[i] && ds[i].type === DeviceType.Wifi) return ds[i]
        return null
    }
    property string wifiCurrentSSID: ""
    property var    wifiNetworks: []   // [{ssid, signal, bars, secured, known, active, busy}]
    property string wifiPromptSSID: ""   // SSID en cours de saisie de mot de passe (vide = pas de prompt)
    property string wifiError: ""        // message d'erreur après échec connexion
    property string wifiPasswordInput: ""
    property string _wifiTriedPsk: ""    // the SSID a password was just sent for
    property string _wifiSig: ""

    function wifiNetObj(ssid) {
        var ns = wifiDev ? wifiDev.networks.values : []
        for (var i = 0; i < ns.length; i++) if (ns[i] && ns[i].name === ssid) return ns[i]
        return null
    }
    function wifiSecured(n) { return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe }
    // The rows are rebuilt only when what they show changes (signal as 0-3 bars), so
    // signal jitter doesn't replay the list's entrance
    function _wifiSnapshot() {
        var ns = wifiDev ? wifiDev.networks.values : []
        var out = [], cur = ""
        for (var i = 0; i < ns.length; i++) {
            var n = ns[i]
            if (!n || !n.name) continue
            if (n.connected) cur = n.name
            out.push({ ssid: n.name, signal: Math.round(n.signalStrength * 100),
                       bars: Math.min(3, Math.floor(n.signalStrength * 4)),
                       secured: wifiSecured(n), known: n.known, active: n.connected, busy: n.stateChanging })
        }
        out.sort(function(a, b) {
            if (a.active !== b.active) return a.active ? -1 : 1
            if (a.known !== b.known) return a.known ? -1 : 1
            return b.signal - a.signal
        })
        var sig = JSON.stringify(out.map(function(o) { return [o.ssid, o.bars, o.secured, o.known, o.active, o.busy] }))
        if (sig !== _wifiSig) { _wifiSig = sig; wifiNetworks = out }
        wifiCurrentSSID = cur
    }
    Timer { id: wifiSnapT; interval: 120; onTriggered: root._wifiSnapshot() }
    Timer {   // signal strengths drift; refresh the bars now and then while it's on screen
        interval: 3000; running: root.isOpen && root.slot === "top" && !root.power; repeat: true; triggeredOnStart: true
        onTriggered: root._wifiSnapshot()
    }
    // scan while the Wi-Fi list is on screen
    Binding { target: root.wifiDev; property: "scannerEnabled"; value: root.isOpen && root.slot === "top" && !root.power; when: root.wifiDev !== null }
    Connections { target: Networking; function onWifiEnabledChanged() { wifiSnapT.restart() } }
    Instantiator {
        model: root.wifiDev ? root.wifiDev.networks : null
        onObjectAdded: wifiSnapT.restart()
        onObjectRemoved: wifiSnapT.restart()
        delegate: Connections {
            required property var modelData
            target: modelData
            function onConnectedChanged() {
                wifiSnapT.restart()
                if (modelData.connected && modelData.name === root.wifiPromptSSID) root.cancelWifiPrompt()
            }
            function onStateChangingChanged() { wifiSnapT.restart() }
            function onKnownChanged()         { wifiSnapT.restart() }
            function onConnectionFailed(reason) {
                wifiSnapT.restart()
                if (reason === ConnectionFailReason.NoSecrets) {
                    // needs a password: new network, or the saved one no longer works
                    var again = root._wifiTriedPsk === modelData.name
                    root.wifiPromptSSID = modelData.name
                    // NM reports a failed handshake the same way as a wrong key, so say both
                    root.wifiError = again ? "Auth failed · wrong password or dropped link" : ""
                } else if (root.wifiPromptSSID === modelData.name) {
                    root.wifiError = "Connection failed · " + ConnectionFailReason.toString(reason)
                }
                root._wifiTriedPsk = ""
            }
        }
    }

    // ── Bluetooth: native BlueZ (Quickshell.Bluetooth) ──
    // Power, discovery, pair / connect / forget straight on BlueZ's D-Bus objects — no
    // bluetoothctl processes (those queued up behind each other, and a slow `pair` or
    // `connect` left the next command stuck). Events keep the list live.
    readonly property var  btAdapter: Bluetooth.defaultAdapter
    readonly property bool btEnabled: btAdapter ? btAdapter.enabled : false
    readonly property bool btBlocked: btAdapter ? btAdapter.state === BluetoothAdapterState.Blocked : false
    readonly property bool btScanning: btAdapter ? btAdapter.discovering : false
    // what was asked for: the adapter's `discovering` only follows once BlueZ answers,
    // and StartDiscovery can bounce ("Operation already in progress") while it's busy
    property bool _btWantScan: false
    function btSetScan(on) {
        _btWantScan = on
        if (!btAdapter) return
        btAdapter.discovering = on
        if (on) { btScanStopTimer.restart(); btScanRetryT.restart() }
        else    { btScanStopTimer.stop();    btScanRetryT.stop() }
    }
    property var    btDevices: []   // [{name, mac, connected, paired, trusted, busy, battery}]
    property string _btSig: ""
    property var    _btConnectAfterPair: ({})

    function btDevObj(mac) {
        var ds = btAdapter ? btAdapter.devices.values : []
        for (var i = 0; i < ds.length; i++) if (ds[i] && ds[i].address === mac) return ds[i]
        return null
    }
    function _btSnapshot() {
        var ds = btAdapter ? btAdapter.devices.values : []
        var out = []
        for (var i = 0; i < ds.length; i++) {
            var d = ds[i]
            if (!d) continue
            var name = d.name || d.deviceName || ""
            // discovery turns up plenty of nameless beacons: list only named or paired ones
            if (!d.paired && (!name || name.replace(/-/g, ":") === d.address)) continue
            out.push({ name: name || d.address, mac: d.address, connected: d.connected, paired: d.paired,
                       trusted: d.trusted,
                       busy: d.pairing || d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting,
                       battery: d.batteryAvailable ? Math.round(d.battery * 100) : -1 })
        }
        out.sort(function(a, b) {
            if (a.connected !== b.connected) return a.connected ? -1 : 1
            if (a.paired !== b.paired) return a.paired ? -1 : 1
            return a.name.localeCompare(b.name)
        })
        var sig = JSON.stringify(out.map(function(o) { return [o.mac, o.name, o.connected, o.paired, o.busy, o.battery] }))
        if (sig !== _btSig) { _btSig = sig; btDevices = out }
    }
    Timer { id: btSnapT; interval: 120; onTriggered: root._btSnapshot() }
    Timer { interval: 3000; running: root.isOpen && root.slot === "top" && !root.power; repeat: true; triggeredOnStart: true; onTriggered: root._btSnapshot() }
    Connections {
        target: root.btAdapter
        function onEnabledChanged()     { btSnapT.restart() }
        function onDiscoveringChanged() { btSnapT.restart() }
        function onStateChanged()       { btSnapT.restart() }
    }
    Instantiator {
        model: root.btAdapter ? root.btAdapter.devices : null
        onObjectAdded: btSnapT.restart()
        onObjectRemoved: btSnapT.restart()
        delegate: Connections {
            required property var modelData
            target: modelData
            function onConnectedChanged() { btSnapT.restart() }
            function onPairingChanged()   { btSnapT.restart() }
            function onStateChanged()     { btSnapT.restart() }
            function onNameChanged()      { btSnapT.restart() }
            function onBatteryChanged()   { btSnapT.restart() }
            function onPairedChanged() {
                btSnapT.restart()
                // pair → connect, as one gesture
                if (modelData.paired && root._btConnectAfterPair[modelData.address]) {
                    delete root._btConnectAfterPair[modelData.address]
                    modelData.connect()
                }
            }
        }
    }
    // discovery stops on its own after 30 s; a start that bounced gets one retry
    Timer { id: btScanStopTimer; interval: 30000; onTriggered: root.btSetScan(false) }
    Timer { id: btScanRetryT; interval: 800; onTriggered: if (root._btWantScan && root.btAdapter && !root.btAdapter.discovering) root.btAdapter.discovering = true }
    // after an rfkill unblock, power the adapter on
    Timer { id: btPowerT; interval: 500; onTriggered: if (root.btAdapter) root.btAdapter.enabled = true }

    // ── Données système : Audio ──
    // Outputs and volume come from the shared Audio service (native Pipewire): live,
    // no pactl polling.
    readonly property var audioSinks: Audio.sinks.map(function(n) {
        return { name: n.name, description: n.description || n.nickname || n.name,
                 isDefault: Audio.sink !== null && n.id === Audio.sink.id }
    })
    readonly property string audioDefaultSink: Audio.sink ? Audio.sink.name : ""
    readonly property real audioVolume: Audio.volume   // 0.0 - 1.5 (1.0 == 100%)
    readonly property bool audioMuted:  Audio.muted

    // ── Notifications: the shared history (services/Notifs.qml), in-process ──
    readonly property bool dndEnabled: Notifs.dndEnabled
    property var notifications: []     // [{id, summary, body, app, ts, key, live}]
    property string expandedNotif: ""  // key of the expanded notification ("" = none)
    property string _notifJson: ""     // last list applied: an unchanged poll leaves the rows alone
    property var  _seenNotif: ({})     // rows already shown — a rebuilt list doesn't replay their entrance
    property var  _notifRows: ({})     // key → its row (NotifBtn), for heights
    property int  _gapAt: -1           // after a removal the rows from here start _gapH lower…
    property real _gapH:  0            // …and slide up into the gap
    property double nowMs: Date.now()  // for "3m" ages
    Timer { interval: 20000; running: root.isOpen && root.slot === "right"; repeat: true; onTriggered: root.nowMs = Date.now() }
    Timer { id: gapReset; interval: 450; onTriggered: root._gapAt = -1 }
    // a row flies out: order = its stagger slot, strength > 0 = it throws the impact
    signal notifLeave(string key, int order, real strength)

    // The list is only reassigned when its content changes (a JSON signature), so
    // the rows don't rebuild; not while removals are still flying out.
    function _syncNotifs() {
        var txt = JSON.stringify(Notifs.snapshot())
        if (txt === _notifJson || _pendingRm.length > 0 || _flushing) return
        notifications = JSON.parse(txt)
        _notifJson = txt
        _keepNotifFocus()
    }
    Connections {
        target: Notifs
        function onHistoryChanged()  { root._syncNotifs() }
        function onRevisionChanged() { root._syncNotifs() }
    }
    Component.onCompleted: _syncNotifs()

    // Helpers — by key id@ts, never by index
    function notifIndexOf(key) {
        for (var i = 0; i < notifications.length; i++) if (notifications[i].key === key) return i
        return -1
    }
    function focusedNotif() {
        if (action.indexOf("notif:") !== 0) return null
        var i = notifIndexOf(action.substring(6))
        return i >= 0 ? notifications[i] : null
    }
    function notifAge(ts) {
        var s = Math.max(0, (nowMs - ts) / 1000)
        return s < 60 ? "now" : s < 3600 ? Math.floor(s / 60) + "m" : s < 86400 ? Math.floor(s / 3600) + "h" : Math.floor(s / 86400) + "d"
    }
    function _setNotifs(list, gapAt, gapH) {
        _gapAt = gapAt; _gapH = gapH
        notifications = list
        _notifJson = JSON.stringify(list)
        if (gapAt >= 0) gapReset.restart()
        _keepNotifFocus()
    }
    // the focused notification vanished (dismissed here or elsewhere): take its
    // neighbour, or step back to the sub list when none are left
    property int _lastNotifIdx: 0
    onActionChanged: {
        if (live && depth === 3) pressAnim.restart()
        var i = action.indexOf("notif:") === 0 ? notifIndexOf(action.substring(6)) : -1
        if (i >= 0) _lastNotifIdx = i
    }
    function _keepNotifFocus() {
        if (expandedNotif !== "" && notifIndexOf(expandedNotif) < 0) expandedNotif = ""
        if (!(slot === "right" && sub === "history" && level === 3)) return
        if (action.indexOf("notif:") === 0 && notifIndexOf(action.substring(6)) >= 0) return
        if (action === "clear-all" && notifications.length > 0) return
        if (notifications.length === 0) { action = ""; if (atAction) atAction = false; return }
        action = "notif:" + notifications[Math.min(_lastNotifIdx, notifications.length - 1)].key
    }

    // Dismiss (or open = invoke its default action) one notification: its row
    // flies out, then it's removed and the rows below slide up into the gap
    property var _pendingRm: []
    property bool _closeAfterRm: false
    Timer { id: rmTimer; interval: 200; onTriggered: root._flushRemovals() }
    function dismissNotif(key, invoke) {
        if (notifIndexOf(key) < 0) return
        for (var j = 0; j < _pendingRm.length; j++) if (_pendingRm[j].key === key) return
        _pendingRm.push({key: key, invoke: !!invoke})
        notifLeave(key, 0, invoke ? 0 : 0.7)       // ↵ already threw its impact in the hit-stop
        rmTimer.interval = 200; rmTimer.restart()
    }
    function invokeNotif(key) {
        _closeAfterRm = true                        // the app comes forward: get out of its way
        dismissNotif(key, true)
    }
    function clearAllNotifs() {
        if (notifications.length === 0) { blocked(); return }
        var n = notifications.length
        for (var i = 0; i < n; i++) _pendingRm.push({key: notifications[i].key, invoke: false, all: true})
        notifLeave("*", 0, 1)
        rmTimer.interval = Math.min(n, 8) * 45 + 210; rmTimer.restart()
    }
    property bool _flushing: false     // removing from the store: its change signals wait
    function _flushRemovals() {
        var rm = _pendingRm; _pendingRm = []
        _flushing = true
        var list = notifications.slice(), gapAt = -1, gapH = 0, all = false
        for (var j = 0; j < rm.length; j++) {
            if (rm[j].all) { all = true; continue }
            var i = -1
            for (var q = 0; q < list.length; q++) if (list[q].key === rm[j].key) { i = q; break }
            if (i < 0) continue
            var row = _notifRows[rm[j].key]
            gapH += (row ? row.height : 48) + 8
            if (gapAt < 0 || i < gapAt) gapAt = i
            list.splice(i, 1)
            Notifs.removeKey(rm[j].key, rm[j].invoke)
        }
        if (all) {
            Notifs.clearAll()
            list = []; gapAt = -1
        }
        _flushing = false
        _setNotifs(list, gapAt, gapH)
        if (_closeAfterRm) { _closeAfterRm = false; close() }
    }
    // ↵ / → that leads nowhere: the list nudges that way and springs back
    function blocked() {
        kickDir = Qt.point(deeperDir() === "left" ? -1 : 1, 0)
        kickAnim.restart()
    }
    function setDnd(state) { Notifs.dndEnabled = state }

    // ── Données système : Quickshare (qshare.py) ──
    // Sélection multi-fichiers en attente d'envoi (chemins absolus).
    property var    pendingFiles: []
    property string pendingSize:  ""      // taille totale humaine, ex. "24.5 MB"

    // ── État qshare ──
    // Le serveur reste allumé jusqu'à ce qu'on ferme le modal : le téléphone
    // peut donc télécharger/téléverser plusieurs fois depuis un seul QR.
    // Il n'y a donc plus de toggle "keep alive".
    property bool   qshareTunnel:    false  // false = LAN (même Wi-Fi), true = Internet (tunnel)
    property string qshareOutputDir: home + "/Downloads"
    property string qshareMode:      ""     // "send" | "recv" — mode du transfert en cours
    property string qshareUrl:       ""     // URL active (modal visible si non vide)
    property string qshareQrPath:    ""     // chemin du PNG QR
    property string qshareLabel:     ""     // ex. "3 items → phone"
    property var    qshareTicks:     []     // journal des fichiers transférés
    property string qshareStatus:    ""     // message transitoire (ex. démarrage du tunnel)
    property bool   qshareCancelled: false
    readonly property string qshareScriptPath: xdgConfigHome + "/quickshell/scripts/qshare.py"
    readonly property string qshareEventFile:  "/tmp/qshare-events"
    readonly property string qshareQrFile:     "/tmp/qshare-qr.png"

    readonly property var qshareOutputDirs: [
        home + "/Downloads",
        home + "/Pictures",
        home + "/Documents",
        "/tmp"
    ]

    function fileName(p)         { return p.split("/").pop() }
    function qshareOutputShort()  { return qshareOutputDir.replace(home, "~") }
    function qshareNetLabel() {
        return qshareTunnel ? "Net: Internet (tunnel)" : "Net: LAN (same wi-fi)"
    }


    // ── Sélecteur de fichiers ────────────────────────────────────────────
    // Ouvre un vrai navigateur de fichiers (zenity → kdialog → yazi) en
    // multi-sélection. Le picker écrit les chemins choisis sur stdout, un par
    // ligne : plus besoin de polling sur un fichier temporaire.
    function openPicker(dirMode) {
        var title = dirMode ? "qshare · choose a folder to send"
                            : "qshare · choose files to send"
        var zenArgs = dirMode ? "--directory" : "--multiple --separator='\n'"
        var kdeArgs = dirMode ? "--getexistingdirectory \"$HOME\""
                              : "--getopenfilename \"$HOME\" --multiple --separate-output"
        var script =
            "sleep 0.35\n" +
            "if command -v zenity >/dev/null 2>&1; then\n" +
            "  exec zenity --file-selection " + zenArgs + " --title='" + title + "'\n" +
            "elif command -v kdialog >/dev/null 2>&1; then\n" +
            "  exec kdialog " + kdeArgs + " --title '" + title + "'\n" +
            "elif command -v yazi >/dev/null 2>&1; then\n" +
            // Dernier recours : yazi dans un terminal. Bloquant, donc on peut
            // lire le chooser-file dès que le terminal se ferme.
            "  out=$(mktemp); \n" +
            "  for t in foot kitty alacritty wezterm; do\n" +
            "    command -v $t >/dev/null 2>&1 || continue\n" +
            "    case $t in\n" +
            "      foot)     foot --app-id qs-file-picker yazi --chooser-file=\"$out\" ;;\n" +
            "      kitty)    kitty --class qs-file-picker yazi --chooser-file=\"$out\" ;;\n" +
            "      alacritty) alacritty --class qs-file-picker -e yazi --chooser-file=\"$out\" ;;\n" +
            "      wezterm)  wezterm start --class qs-file-picker -- yazi --chooser-file=\"$out\" ;;\n" +
            "    esac\n" +
            "    break\n" +
            "  done\n" +
            "  cat \"$out\" 2>/dev/null; rm -f \"$out\"\n" +
            "else\n" +
            "  notify-send 'qshare' 'No file picker found (install zenity)' >/dev/null 2>&1\n" +
            "fi\n"
        pickerProc.command = ["sh","-c", script]
        pickerProc.running = true
        // Libère le focus clavier exclusif pour que le dialogue le récupère.
        close()
    }

    Process {
        id: pickerProc
        running: false
        command: ["sh","-c","true"]
        stdout: StdioCollector {
            onStreamFinished: {
                var picked = this.text.split("\n")
                                 .map(function(s){ return s.trim() })
                                 .filter(function(s){ return s !== "" })
                // Dialogue annulé (stdout vide) : on garde la sélection actuelle,
                // mais on rouvre quand même le panneau pour ne pas laisser
                // l'utilisateur devant un écran vide.
                if (picked.length > 0) {
                    root.pendingFiles = picked
                    root.pendingSize = ""
                    root.measureSelection()
                }
                // Rouvre le ControlCenter sur left.send, focus sur la 1re action
                root.isOpen = true
                root.closing = false
                root.level = 3
                root.slot = "left"
                root.sub = "send"
                root.atAction = true
                root.action = root.firstAction()
            }
        }
    }

    // Taille totale de la sélection, pour l'afficher dans le panneau
    function measureSelection() {
        if (pendingFiles.length === 0) { pendingSize = ""; return }
        // --apparent-size : la taille réelle, pas l'occupation disque (sinon un
        // fichier de 10 octets s'affiche "4.0K"). "$@" évite tout quoting.
        var argv = ["sh","-c",
            "du -shcL --apparent-size -- \"$@\" 2>/dev/null | tail -1 | cut -f1","sh"]
        sizeProc.command = argv.concat(pendingFiles)
        sizeProc.running = true
    }
    Process {
        id: sizeProc
        running: false
        command: ["sh","-c","true"]
        stdout: StdioCollector {
            onStreamFinished: {
                var s = this.text.trim()
                root.pendingSize = s === "" ? "" : s + "B"
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //   qshare.py — process + event polling + lancement/arrêt
    // ═══════════════════════════════════════════════════════════════════

    // mode = "send" (files → phone) | "recv" (phone → qshareOutputDir)
    function startQshare(mode) {
        // Reset state
        root.qshareMode = mode
        root.qshareUrl = ""
        root.qshareQrPath = ""
        root.qshareTicks = []
        root.qshareCancelled = false

        // Cleanup ancien event/QR file (sync via touch)
        cleanupQshareProc.command = ["sh","-c",
            "rm -f " + qshareEventFile + " " + qshareQrFile + "; " +
            "touch " + qshareEventFile]
        cleanupQshareProc.running = true

        // Construit la commande
        var args = ["python3", qshareScriptPath, mode]
        if (mode === "send") {
            if (pendingFiles.length === 0) return
            args = args.concat(pendingFiles)
            qshareLabel = pendingFiles.length === 1
                ? fileName(pendingFiles[0])
                : pendingFiles.length + " items"
        } else {
            args.push("-o"); args.push(qshareOutputDir)
            qshareLabel = qshareOutputShort()   // le modal préfixe déjà "PHONE → PC"
        }
        if (qshareTunnel) args.push("--tunnel")
        args.push("--qr-out");     args.push(qshareQrFile)
        args.push("--event-file"); args.push(qshareEventFile)

        qshareProc.command = args
        qshareProc.running = true
        qshareWatching = true
    }

    function stopQshare() {
        qshareCancelled = true
        qshareProc.running = false   // SIGTERM → le script nettoie ses zips temporaires
        qshareWatching = false
        qshareUrl = ""
        qshareQrPath = ""
        // La sélection a été partagée : on repart de zéro
        if (qshareMode === "send") { pendingFiles = []; pendingSize = "" }
    }

    Process { id: cleanupQshareProc; command: ["sh","-c","true"]; running: false }

    Process {
        id: qshareProc
        running: false
        command: ["sh","-c","true"]
        // stdout/stderr ignorés — on s'en remet à l'event-file
        onRunningChanged: {
            if (!running) {
                // Process terminé → ferme le modal après un petit délai pour
                // laisser le temps de voir le tick final
                qshareWatching = false
                qshareCloseTimer.restart()
            }
        }
    }

    Timer {
        id: qshareCloseTimer
        interval: qshareCancelled ? 0 : 600
        repeat: false
        onTriggered: {
            qshareUrl = ""
            qshareQrPath = ""
            qshareTicks = []
            // Reset de la sélection après un envoi terminé
            if (!qshareCancelled && root.qshareMode === "send") {
                pendingFiles = []
                pendingSize = ""
            }
        }
    }

    // qshare.py appends one line per event (URL/QR/TICK/STATUS/…): the file is
    // watched (inotify) while a transfer runs, and re-read whole on each change —
    // state is rebuilt from it, not accumulated, so TICKs never double.
    property bool qshareWatching: false
    FileView {
        id: qshareEvents
        path: root.qshareWatching ? root.qshareEventFile : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root._parseQshareEvents(text())
    }
    function _parseQshareEvents(txt) {
                var lines = txt.split("\n")
                var ticks = []
                var status = ""
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim()
                    if (!line) continue
                    if (line.indexOf("URL ") === 0) {
                        root.qshareUrl = line.substring(4)
                    } else if (line.indexOf("QR ") === 0) {
                        root.qshareQrPath = line.substring(3)
                    } else if (line.indexOf("TICK ") === 0) {
                        ticks.push(line.substring(5))
                    } else if (line.indexOf("STATUS ") === 0) {
                        status = line.substring(7)
                    } else if (line.indexOf("ERROR ") === 0) {
                        status = "✗ " + line.substring(6)
                    } else if (line === "READY") {
                        status = ""
                    } else if (line === "DONE") {
                        // Le process va s'arrêter tout seul, le onRunningChanged gère
                    } else if (line === "CANCELLED") {
                        root.qshareCancelled = true
                    }
                }
                root.qshareTicks = ticks
                root.qshareStatus = status
    }


    // Refresh state quand on change de slot
    onSlotChanged: {
        if (live) pressAnim.restart()
        cancelWifiPrompt()
        if (slot === "top" && !power) { _wifiSnapshot(); _btSnapshot() }
    }
    onSubChanged: {
        if (power && sub === "hibernate") hibCheck()    // its readiness line in the detail panel
        _seenNotif = ({})
        if (live && sub !== "") pressAnim.restart()
        cancelWifiPrompt()
    }
    onLevelChanged: { if (level !== 3) cancelWifiPrompt() }
    onIsOpenChanged:  { if (!isOpen) { cancelWifiPrompt(); if (_btWantScan || btScanning) btSetScan(false) } }

    // Cancel le prompt Wi-Fi proprement (fermeture du TextInput, reset focus au keyHandler)
    function cancelWifiPrompt() {
        if (wifiPromptSSID === "") return
        wifiPromptSSID = ""
        wifiPasswordInput = ""
        wifiError = ""
    }

    function firstSub(s) { var l = subList(s); return l.length ? l[0].key : "" }
    function firstAction() { var l = actList(); return l.length ? l[0].key : "" }

    // ── Dispatcher des actions de boutons ──
    function dispatchAction(slotKey, subKey, actionKey) {
        console.log("[ControlCenter] action:", slotKey + "." + subKey + "." + actionKey)
        var cmd = ""

        // ── Wi-Fi (native) ──
        if (slotKey === "top" && subKey === "wifi") {
            if (actionKey === "toggle") {
                Networking.wifiEnabled = !Networking.wifiEnabled
                return
            } else if (actionKey.indexOf("connect:") === 0) {
                var wn = wifiNetObj(actionKey.substring(8))
                if (!wn) return
                if (wn.connected) { wn.disconnect(); return }
                // saved profile or open network: no password needed
                if (wn.known || !wifiSecured(wn)) { wn.connect(); wifiSnapT.restart(); return }
                wifiPromptSSID = wn.name
                wifiError = ""
                return
            } else if (actionKey === "submit-password") {
                var pn = wifiNetObj(wifiPromptSSID)
                if (!pn) { wifiError = "Network out of range"; return }
                _wifiTriedPsk = pn.name
                wifiError = "Connecting…"
                pn.connectWithPsk(wifiPasswordInput)
                return
            } else if (actionKey === "cancel-prompt") {
                cancelWifiPrompt()
                return
            }
        }
        // ── Bluetooth (native) ──
        else if (slotKey === "top" && subKey === "bluetooth") {
            if (!btAdapter) return
            if (actionKey === "toggle") {
                if (btBlocked) {                 // rfkill soft block: lift it, then power on
                    Quickshell.execDetached(["rfkill", "unblock", "bluetooth"])
                    btPowerT.restart()
                } else {
                    btAdapter.enabled = !btAdapter.enabled
                }
                return
            } else if (actionKey === "scan") {
                btSetScan(!(btScanning || _btWantScan))
                return
            }
            var bd = btDevObj(actionKey.substring(actionKey.indexOf(":") + 1))
            if (!bd) return
            if (actionKey.indexOf("connect:") === 0) {
                bd.trusted = true
                bd.connect()
            } else if (actionKey.indexOf("disconnect:") === 0) {
                bd.disconnect()
            } else if (actionKey.indexOf("pair:") === 0) {
                bd.trusted = true
                _btConnectAfterPair[bd.address] = true
                bd.pair()
            } else if (actionKey.indexOf("remove:") === 0) {
                bd.forget()
            }
            btSnapT.restart()
            return
        }
        // ── Audio Output ──
        else if (slotKey === "bottom" && subKey === "output") {
            if (actionKey.indexOf("set-sink:") === 0) { Audio.setDefaultSink(actionKey.substring(9)); return }
        }
        // ── Audio Volume ── (route through shared Audio service → native
        // Pipewire property write; no subprocess, smooth during slider drag)
        else if (slotKey === "bottom" && subKey === "volume") {
            if (actionKey === "mute-toggle") {
                Audio.toggleMute(); return
            } else if (actionKey.indexOf("set-volume:") === 0) {
                Audio.setVolume(parseInt(actionKey.substring(11)) / 100); return
            }
        }
        // ── Quickshare Send (qshare.py) ──
        else if (slotKey === "left" && subKey === "send") {
            if (actionKey === "pick-files") {
                openPicker(false)
                return
            } else if (actionKey === "pick-folder") {
                openPicker(true)
                return
            } else if (actionKey === "clear-files") {
                pendingFiles = []
                pendingSize = ""
                return
            } else if (actionKey === "toggle-net") {
                qshareTunnel = !qshareTunnel
                return
            } else if (actionKey === "start-send") {
                if (pendingFiles.length === 0) return
                root.startQshare("send")
                return
            }
        }
        // ── Quickshare Receive (qshare.py) ──
        else if (slotKey === "left" && subKey === "receive") {
            if (actionKey === "toggle-net") {
                qshareTunnel = !qshareTunnel
                return
            } else if (actionKey === "cycle-output") {
                var dirs = qshareOutputDirs
                var idx = dirs.indexOf(qshareOutputDir)
                qshareOutputDir = dirs[(idx + 1) % dirs.length]
                return
            } else if (actionKey === "open-output") {
                Quickshell.execDetached(["xdg-open", qshareOutputDir])
                close()
                return
            } else if (actionKey === "start-recv") {
                root.startQshare("recv")
                return
            }
        }
        // ── Notifications History ──
        else if (slotKey === "right" && subKey === "history") {
            if (actionKey === "clear-all") {
                clearAllNotifs()
                return
            } else if (actionKey.indexOf("notif:") === 0) {
                invokeNotif(actionKey.substring(6))
                return
            } else if (actionKey === "none") {
                return
            }
        }
        // ── Notifications DND ──
        else if (slotKey === "right" && subKey === "dnd") {
            if (actionKey === "toggle-dnd") {
                setDnd(!dndEnabled)
                return
            }
        }

        if (cmd) {
            // detached: each command runs on its own (a shared Process that was still busy
            // silently dropped the next one)
            Quickshell.execDetached(["sh", "-c", cmd])
        }
    }

    function activateCurrent() {
        if (_hitting || folded) return
        if (depth === 2 && !power && actList().length === 0) { blocked(); return }
        if (depth === 2 && power && sub === "hibernate" && hib && !hib.ok) { blocked(); hibDenied(); hibCheck(); return }   // no confirm burst for a refusal
        _hitting = true
        hitDepth = depth
        confirmPulse(depth === 3 || (power && depth === 2) ? 1.0 : 0.6)
        hitAnim.restart()
    }
    function _afterHit() {
        if (depth === 1) {
            if (slot === "center") setMode(power ? "main" : "power")
            else enterSlot()
            return
        }
        if (depth === 2) { if (power) powerRun(sub); else enterActions(); return }
        if (level === 3 && action) {
            // Notifications: ↵ opens one whose app still listens (its default action),
            // otherwise it shows / hides the details
            if (slot === "right" && sub === "history" && action.indexOf("notif:") === 0) {
                var nk = action.substring(6), nf = focusedNotif()
                if (nf && nf.live) invokeNotif(nk)
                else expandedNotif = expandedNotif === nk ? "" : nk
                return
            }
            dispatchAction(slot, sub, action)
        }
    }

    // ── Power mode ──
    // The cross turns over: the arms tuck into the centre, swap their labels behind it
    // and spring back out.
    function setMode(m) {
        if (mode === m || morphT.running) return
        _nextMode = m
        folded = true
        morphT.restart()
    }
    Timer { id: morphT; interval: 200; onTriggered: { root.mode = root._nextMode; root.folded = false } }

    function powerRun(key) {
        var a = powerActs[key]
        if (!a) return
        if (key === "hibernate") { _hibAsk = true; hibCheck(); return }   // only once it can fit
        if (a.ask) { confirmYes = false; _cardAt = Date.now(); confirmKey = key; return }
        _powerGo(key)
    }

    // Hibernate is refused up front when the image can't fit in the disk swap
    // (scripts/hibernate-check.sh): that hibernation fails half-way ("Image saving failed:
    // -28"), and coming back from the failure has left the NVIDIA display dead.
    property var  hib: null                 // {ok, swap, image, need} in GiB
    property bool _hibAsk: false            // ↵ is waiting for the check
    function hibCheck() { if (!hibProc.running) hibProc.running = true }
    Process {
        id: hibProc
        command: ["sh", Quickshell.shellDir + "/scripts/hibernate-check.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.hib = JSON.parse(text) } catch (e) { root.hib = null }
                if (!root._hibAsk) return
                root._hibAsk = false
                if (root.hib && root.hib.ok) { root.confirmYes = false; root._cardAt = Date.now(); root.confirmKey = "hibernate" }
                else { root.blocked(); root.hibDenied() }
            }
        }
    }
    signal hibDenied()                      // the readiness line shakes
    function hibLine() {
        if (!hib) return ""
        return hib.ok ? "可以休眠 · swap " + hib.swap.toFixed(1) + " GiB，映像約 " + hib.image.toFixed(1) + " GiB"
                      : "無法休眠：swap 只有 " + hib.swap.toFixed(1) + " GiB，映像約 " + hib.image.toFixed(1)
                        + " GiB，至少要 " + hib.need.toFixed(1) + " GiB"
    }
    // the YES / NO card: the chosen button pops and throws its burst, then the answer lands
    property real cHitT: 0
    SequentialAnimation {
        id: cHitAnim
        NumberAnimation { target: root; property: "cHitT"; from: 0; to: 1; duration: 45; easing.type: Easing.OutQuad }
        PauseAnimation { duration: 75 }
        ScriptAction { script: root._confirmDone() }
        NumberAnimation { target: root; property: "cHitT"; to: 0; duration: 220; easing.type: Easing.OutCubic }
    }
    function confirmChoose(yes) { if (confirmYes !== yes && !cHitAnim.running) { confirmYes = yes; pressAnim.restart() } }
    function confirmActivate() {
        if (confirmKey === "" || cHitAnim.running) return
        var b = confirmYes ? yesBtn : noBtn
        burst.playAt(b, b.width / 2, b.height / 2, confirmYes ? 1.25 : 0.5)
        cHitAnim.restart()
    }
    function confirmCancel() { if (!cHitAnim.running) confirmKey = "" }
    function _confirmDone() {
        var k = confirmKey, yes = confirmYes
        confirmKey = ""
        if (yes) _powerGo(k)
    }

    // Exit: the triangles collapse and the arms tuck in while the screen fades to black,
    // then the command runs. A failure (an inhibitor…) shows its message and brings the
    // menu back. Sleep / Hibernate return as soon as logind has queued them, so the dark
    // holds until logind says the system is back (PrepareForSleep false, watched with
    // gdbus), and the unit's Result then tells a resume from a failed attempt.
    readonly property bool _sleepKind: exitKey === "sleep" || exitKey === "hibernate"
    function _powerGo(key) {
        var a = powerActs[key]
        if (!a.exit) { Quickshell.execDetached(a.cmd); close(); return }    // Lock
        exitError = ""
        exitKey = key
        collapse = true
        folded = true
        if (_sleepKind && !_exitPreview) { _slept = false; _sleepSince = Math.floor(Date.now() / 1000); sleepWatch.running = true }
        exitAnim.restart()
    }
    // `qs ipc call ctrl exitPreview <key>`: the exit's look, nothing run — it fades back
    property bool _exitPreview: false
    function previewExit(key) {
        var k = (key in powerActs) && powerActs[key].exit ? key : "poweroff"
        if (!isOpen) { openPower(); previewT.key = k; previewT.start(); return }
        _exitPreview = true
        _powerGo(k)
    }
    Timer { id: previewT; property string key: ""; interval: 1000; onTriggered: { root._exitPreview = true; root._powerGo(key) } }
    Timer { id: previewBackT; interval: 1800; onTriggered: { root._exitPreview = false; root._exitBack(true) } }
    SequentialAnimation {
        id: exitAnim
        ParallelAnimation {
            // the dark rises under the triangles as they scatter, so they fly off into it
            NumberAnimation { target: root; property: "underlay"; from: 0; to: 1; duration: 260; easing.type: Easing.OutQuad }
            SequentialAnimation {
                PauseAnimation { duration: 140 }
                NumberAnimation { target: root; property: "exitFade"; from: 0; to: 1; duration: 820; easing.type: Easing.InOutQuad }
            }
        }
        PauseAnimation { duration: 120 }
        ScriptAction {
            script: {
                if (root._exitPreview) { previewBackT.start(); return }
                powerProc.command = root.powerActs[root.exitKey].cmd
                powerProc.running = true
            }
        }
    }
    property int _exitCode: 0
    Process {
        id: powerProc
        stderr: StdioCollector { id: powerErr }
        onExited: (code) => { root._exitCode = code; exitCheckT.restart() }
    }
    Timer {   // the stderr collector may finish just after the exit
        id: exitCheckT; interval: 120
        onTriggered: {
            if (root.exitKey === "") return
            if (root._exitCode !== 0) {
                var err = (powerErr.text || "").trim().split("\n")[0]
                root.exitError = err !== "" ? err : "exit code " + root._exitCode
                exitFailT.restart()
            } else if (root._sleepKind) { if (!root._slept) sleepStartT.restart() }
            else exitStuckT.restart()
        }
    }
    Timer { id: exitFailT;   interval: 3600;  onTriggered: root._exitBack(false) }
    Timer { id: exitStuckT;  interval: 20000; onTriggered: root._exitBack(true) }   // still here: don't stay dark

    // ── Sleep / Hibernate: wait for the system to come back ──
    property bool _slept: false
    property int  _sleepSince: 0
    Process {
        id: sleepWatch
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1"]
        stdout: SplitParser {
            onRead: (line) => {
                if (line.indexOf("PrepareForSleep") < 0 || root.exitKey === "") return
                if (line.indexOf("true") >= 0) { root._slept = true; sleepStartT.stop(); sleepBackT.restart() }
                else if (root._slept) root._sleepOver()
            }
        }
    }
    // these timers don't run while the system sleeps: they only count time awake
    Timer { id: sleepStartT; interval: 30000;  onTriggered: root._sleepOver() }    // logind never started it
    Timer { id: sleepBackT;  interval: 180000; onTriggered: root._sleepOver() }    // hibernate entry alone took 47 s once
    function _sleepOver() {
        sleepStartT.stop(); sleepBackT.stop()
        sleepWatch.running = false
        if (exitKey === "" || sleepResult.running) return
        var unit = exitKey === "hibernate" ? "systemd-hibernate.service" : "systemd-suspend.service"
        sleepResult.command = ["sh", "-c",
            "systemctl show -p Result --value " + unit + "; " +
            "journalctl -b -u " + unit + " --since @" + _sleepSince + " -o cat --no-pager | grep -iE 'fail|error' | tail -n 1"]
        sleepResult.running = true
    }
    Process {
        id: sleepResult
        stdout: StdioCollector { onStreamFinished: root._sleepResultIs(text) }
    }
    // the unit's Result, then the last failure line it logged since the command
    function _sleepResultIs(text) {
        if (exitKey === "") return
        var l = text.split("\n"), result = (l[0] || "").trim(), why = (l[1] || "").trim()
        if (result === "success" && why === "") { _exitBack(true); return }      // it slept and came back
        if (why.indexOf("No space left") >= 0) why = "swap 空間不足，休眠映像寫不下（" + why + "）"
        exitError = why !== "" ? why : (_slept ? "沒有成功（" + result + "）" : "系統沒有開始睡眠")
        exitFailT.restart()
    }
    property bool _exitThenClose: false
    function _exitBack(thenClose) {
        _exitThenClose = thenClose
        if (!thenClose) collapse = false        // the triangles unfold under the fading black
        exitBackAnim.restart()
    }
    ParallelAnimation {
        id: exitBackAnim
        NumberAnimation { target: root; property: "exitFade"; to: 0; duration: 420; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "underlay"; to: 0; duration: 520; easing.type: Easing.OutCubic }
        onFinished: {
            if (root._exitThenClose) root.close()
            root.exitKey = ""; root.exitError = ""
            root.folded = false
        }
    }
    function _resetPower() {
        morphT.stop(); cHitAnim.stop(); exitAnim.stop(); exitBackAnim.stop()
        exitCheckT.stop(); exitFailT.stop(); exitStuckT.stop(); sleepStartT.stop(); sleepBackT.stop()
        sleepWatch.running = false; _hibAsk = false; _exitPreview = false; previewT.stop(); previewBackT.stop()
        mode = "main"; folded = false; confirmKey = ""; confirmYes = false
        exitKey = ""; exitError = ""; exitFade = 0; cHitT = 0
    }

    // ── Lifecycle (components/Popup.qml) ──
    onOpening: { _resetPower(); if (_openPower) { _openPower = false; mode = "power" }; ready = false; level = 1; slot = "center"; sub = ""; action = ""; atAction = false }
    onIntro:   ready = true
    // phase is already "closing" here, so the depth reset doesn't kick or pop
    // (the mode stays: the arms fold in with the labels they had)
    onOutro:   { confirmKey = ""; level = 1; slot = "center"; sub = ""; action = ""; atAction = false }
    function back() {
        if (depth === 3)      atAction = false
        else if (depth === 2) { level = 1; sub = ""; action = "" }   // stay on this section
        else if (power)       { slot = "center"; setMode("main") }
        else close()
    }

    // the power key (XF86PowerOff) opens straight into the power menu
    property bool _openPower: false
    function openPower() {
        if (isOpen) { if (!power) { slot = "center"; level = 1; sub = ""; atAction = false; setMode("power") } return }
        _openPower = true
        open()
    }
    // while the shell runs, logind leaves the power key to us (it would power off at once);
    // if Quickshell dies the inhibitor goes with it and logind's own handling is back
    Process {
        running: true
        command: ["systemd-inhibit", "--what=handle-power-key", "--who=Quickshell", "--mode=block",
                  "--why=The power key opens the Control Center's power menu", "sleep", "infinity"]
    }

    IpcHandler {
        target: "ctrl"
        function toggle(): void { root.toggle() }
        function power(): void  { root.openPower() }
        function exitPreview(key: string): void { root.previewExit(key) }
        function show(): void   { root.open() }
        function hide(): void   { root.close() }
    }

    // ── Navigation ──
    // depth 1 = the cross (pick a section), 2 = that section's sub-list, 3 = the
    // actions of the focused sub (the detail panel). Arrows only move focus;
    // ↵ — or the direction toward the detail panel — goes one deeper; Esc — or the
    // direction away from it — goes one back. Lists stop at their ends.
    readonly property int depth: level === 1 ? 1 : (atAction ? 3 : 2)
    // the detail panel opens left of the left section, right of the others
    function deeperDir() { return slot === "left" ? "left" : "right" }
    function awayDir()   { return slot === "left" ? "right" : "left" }
    function enterSlot() {
        if (slot === "center") return
        level = 3; sub = firstSub(slot); action = firstAction(); atAction = false
    }
    function enterActions() {
        var keys = actList().map(function(a){ return a.key })
        if (keys.length === 0) return
        if (keys.indexOf(action) < 0) action = keys[0]
        atAction = true
    }
    function navigate(dir) {
        if (depth === 1) {
            var t = ({up:"top", down:"bottom", left:"left", right:"right"})[dir]
            if (!t) return
            if (slot === t) { activateCurrent(); return }                // same way again → open
            var opp = ({top:"bottom", bottom:"top", left:"right", right:"left"})
            if (slot !== "center" && opp[slot] === t) { slot = "center"; return }
            slot = t
            return
        }
        if (depth === 2) {
            // Back is the way to the cross centre: ← / → for the side sections; for
            // the top (bottom) section the centre is below (above), so ↓ past the
            // last sub (↑ past the first) returns to it.
            var subKeys = subList(slot).map(function(s){ return s.key })
            var si = subKeys.indexOf(sub)
            if (dir === "up") {
                if (si > 0) { sub = subKeys[si - 1]; action = firstAction() }
                else if (slot === "bottom") back()
                else bumpAt(-1)
            } else if (dir === "down") {
                if (si < subKeys.length - 1) { sub = subKeys[si + 1]; action = firstAction() }
                else if (slot === "top") back()
                else bumpAt(1)
            } else if (dir === deeperDir()) activateCurrent()
            else if (dir === awayDir() && (slot === "left" || slot === "right")) back()
            return
        }
        // depth 3 — the volume sub uses ↑↓ for the level itself
        if (slot === "bottom" && sub === "volume" && (dir === "up" || dir === "down")) {
            // native Pipewire (the Audio service): every press counts, however fast
            Audio.setVolume(Math.max(0, Math.min(1.5, Audio.volume + (dir === "up" ? 0.03 : -0.03))))
            return
        }
        if (slot === "right" && sub === "history" && action.indexOf("notif:") === 0) {
            var fk = action.substring(6)
            if (dir === deeperDir()) {
                if (expandedNotif !== fk) expandedNotif = fk
                else blocked()
                return
            }
            if (dir === awayDir() && expandedNotif === fk) { expandedNotif = ""; return }
        }
        var actKeys = actList().map(function(a){ return a.key })
        // the notification list ends in CLEAR ALL: ↓ past the last one selects it
        if (slot === "right" && sub === "history" && actKeys.length > 0) actKeys.push("clear-all")
        var ai = actKeys.indexOf(action)
        if (dir === "up") {
            if (ai > 0) action = actKeys[ai - 1]
            else bumpAt(-1)
        } else if (dir === "down") {
            if (ai < actKeys.length - 1) action = actKeys[ai + 1]
            else bumpAt(1)
        } else if (dir === awayDir()) back()
    }

    // ── Nav bar text ──
    function slotTitle(k) {
        return (power ? {top:"Standby", bottom:"Shutdown", left:"Session", right:"Restart"}
                      : {top:"Connexion", bottom:"Audio", left:"Quickshare", right:"Notifications"})[k] || ""
    }
    function slotSubtitle(k) {
        return (power ? {top:"Lock · Sleep", bottom:"Power off · Hibernate", left:"Log out", right:"Reboot · UEFI"}
                      : {top:"Wi-Fi · Bluetooth", bottom:"Output · Volume", left:"File transfer", right:"History · DND"})[k] || ""
    }
    function subLabel() {
        var l = subList(slot).filter(function(s){ return s.key === sub })
        return l.length ? l[0].label : ""
    }
    function crumbs() {
        var c = ["MENU"]
        if (power) c.push("POWER")
        if (slot !== "center") c.push(slotTitle(slot))
        if (depth >= 2) c.push(subLabel())
        if (depth === 3) c.push("ACTION")
        if (confirmKey !== "") c.push("CONFIRM")
        return c
    }
    function navHints() {
        var deep = deeperDir() === "left" ? "←" : "→", away = awayDir() === "left" ? "←" : "→"
        if (confirmKey !== "") return [["←→", "SELECT"], ["↵", "CONFIRM"], ["Y / N", "YES / NO"], ["ESC", "CANCEL"]]
        if (depth === 1) {
            if (power) return slot === "center"
                ? [["↑↓←→", "SELECT"], ["↵ / ESC", "MENU"]]
                : [["↑↓←→", "SELECT"], ["↵", "OPEN"], ["ESC", "MENU"]]
            return slot === "center"
                ? [["↑↓←→", "SELECT"], ["↵", "POWER"], ["ESC", "CLOSE"]]
                : [["↑↓←→", "SELECT"], ["↵", "OPEN"], ["ESC", "CLOSE"]]
        }
        if (depth === 2) {
            var backKey = slot === "top" ? "↓ / ESC" : slot === "bottom" ? "↑ / ESC" : away + " / ESC"
            if (power) {
                var pa = powerActs[sub]
                return [["↑↓", "SELECT"], [deep + " / ↵", pa && pa.ask ? "RUN…" : "RUN"], [backKey, "BACK"]]
            }
            return [["↑↓", "SELECT"], [deep + " / ↵", "ENTER"], [backKey, "BACK"]]
        }
        var h = [[slot === "bottom" && sub === "volume" ? "↑↓" : "↑↓", slot === "bottom" && sub === "volume" ? "VOLUME" : "SELECT"],
                 ["↵", "RUN"], [away + " / ESC", "BACK"]]
        if (slot === "right" && sub === "history") {
            var nf = focusedNotif()
            if (action === "clear-all") return [["↑", "SELECT"], ["↵", "CLEAR ALL"], [away + " / ESC", "BACK"]]
            return [["↑↓", "SELECT"], ["↵", nf && nf.live ? "OPEN" : "DETAILS"], [deep, "DETAILS"],
                    ["DEL", "DISMISS"], [away + " / ESC", "BACK"]]
        }
        return h
    }


    // ═══════════════════════════════════
    //   PANEL
    // ═══════════════════════════════════
    // ── Conteneur clavier + croix ──
    Item {
        id: keyHandler
        z: 2
        anchors.fill: parent
        opacity: root.live && root.exitKey === "" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220 } }
        // Cède le focus au TextInput Wi-Fi quand le prompt est ouvert
        focus: root.isOpen && root.wifiPromptSSID === ""

        // Reprendre le focus clavier quand le prompt Wi-Fi se ferme
        Connections {
            target: root
            function onWifiPromptSSIDChanged() {
                if (root.wifiPromptSSID === "") {
                    keyHandler.forceActiveFocus()
                }
            }
        }

        Keys.onPressed: function(e) {
            var k = e.key
            if (root.exitKey !== "") { e.accepted = true; return }     // the screen is going dark
            if (root.confirmKey !== "") {                               // the YES / NO card
                if (k === Qt.Key_Escape || k === Qt.Key_N)              root.confirmCancel()
                else if (k === Qt.Key_Y)                                { root.confirmChoose(true); root.confirmActivate() }
                else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) root.confirmActivate()
                else if (k === Qt.Key_Left)                             root.confirmChoose(true)
                else if (k === Qt.Key_Right)                            root.confirmChoose(false)
                else if (k === Qt.Key_Tab)                              root.confirmChoose(!root.confirmYes)
                e.accepted = true
                return
            }
            if (k === Qt.Key_Escape)                          { root.back();          e.accepted = true }
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
                root.activateCurrent(); e.accepted = true
            }
            else if (k === Qt.Key_Delete || k === Qt.Key_Backspace || k === Qt.Key_X) {
                var dn = root.depth === 3 && root.slot === "right" && root.sub === "history" ? root.focusedNotif() : null
                if (dn) root.dismissNotif(dn.key, false)
                e.accepted = true
            }
            else if (k === Qt.Key_Up)    { root.navigate("up");    e.accepted = true }
            else if (k === Qt.Key_Down)  { root.navigate("down");  e.accepted = true }
            else if (k === Qt.Key_Left)  { root.navigate("left");  e.accepted = true }
            else if (k === Qt.Key_Right) { root.navigate("right"); e.accepted = true }
        }

        // ── Croix avec pan ──
        Item {
            id: cross
            anchors.centerIn: parent
            width: 1; height: 1

            // Pan global : le cross glisse pour amener le slot focusé vers le centre
            anchors.horizontalCenterOffset: {
                if (root.level !== 3) return 0
                if (root.slot === "left")  return  root.panShiftH
                if (root.slot === "right") return -root.panShiftH
                return 0
            }
            anchors.verticalCenterOffset: {
                if (root.level !== 3) return 0
                if (root.slot === "top")    return  root.panShiftV
                if (root.slot === "bottom") return -root.panShiftV
                return 0
            }
            Behavior on anchors.horizontalCenterOffset {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }
            Behavior on anchors.verticalCenterOffset {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }

            NierArrow { axis: "top" }
            NierArrow { axis: "bottom" }
            NierArrow { axis: "left" }
            NierArrow { axis: "right" }

            Slot {
                slotKey: "center"
                title: root.power ? "POWER" : "MENU"
                subtitle: root.power ? "↵  BACK TO MENU" : "CONTROL CENTER"
                anchors.centerIn: parent
                isCenter: true
            }
            Slot {
                slotKey: "top"
                title: root.slotTitle("top")
                subtitle: root.slotSubtitle("top")
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: root.live && !root.folded ? -root.slotGapV : 0
                Behavior on anchors.verticalCenterOffset {
                    NumberAnimation { duration: root.live && !root.folded ? 420 : 200; easing.type: root.live && !root.folded ? Easing.OutBack : Easing.InCubic }
                }
            }
            Slot {
                slotKey: "bottom"
                title: root.slotTitle("bottom")
                subtitle: root.slotSubtitle("bottom")
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: root.live && !root.folded ? root.slotGapV : 0
                Behavior on anchors.verticalCenterOffset {
                    NumberAnimation { duration: root.live && !root.folded ? 420 : 200; easing.type: root.live && !root.folded ? Easing.OutBack : Easing.InCubic }
                }
            }
            Slot {
                slotKey: "left"
                title: root.slotTitle("left")
                subtitle: root.slotSubtitle("left")
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: root.live && !root.folded ? -root.slotGapH : 0
                Behavior on anchors.horizontalCenterOffset {
                    NumberAnimation { duration: root.live && !root.folded ? 420 : 200; easing.type: root.live && !root.folded ? Easing.OutBack : Easing.InCubic }
                }
            }
            Slot {
                slotKey: "right"
                title: root.slotTitle("right")
                subtitle: root.slotSubtitle("right")
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: root.live && !root.folded ? root.slotGapH : 0
                Behavior on anchors.horizontalCenterOffset {
                    NumberAnimation { duration: root.live && !root.folded ? 420 : 200; easing.type: root.live && !root.folded ? Easing.OutBack : Easing.InCubic }
                }
            }
        }

        // ── Confirm impact: shards + rings here, a shock ring through the triangles ──
        HitBurst { id: burst; z: 55; backdrop: root.backdrop }   // components/HitBurst.qml
        Connections {
            target: root
            function onImpactAt(win, x, y, s) {
                if (win !== keyHandler.Window.window) return
                burst.play(x, y, s)
            }
        }

        // ── Nav bar: depth · path · the keys that work here ──
        Rectangle {
            id: navBar
            z: 60
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 34
            width: navRow.implicitWidth + 32; height: 34
            color: Theme.alpha(Theme.inkStrong, 0.92)
            border.color: Theme.alpha(Theme.paper, 0.3); border.width: 1
            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Row {
                id: navRow
                anchors.centerIn: parent
                spacing: 16
                Row {   // depth meter
                    spacing: 6; anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: 3
                        Rectangle {
                            id: depthGem
                            width: 7; height: 7; rotation: 45
                            anchors.verticalCenter: parent.verticalCenter
                            color: index < root.depth ? root.colLight : "transparent"
                            border.color: Theme.alpha(Theme.light, 0.7); border.width: 1
                            scale: index === root.depth - 1 ? 1 + 0.35 * root.pulse + 0.9 * root.depthPop : 1
                            Behavior on color { ColorAnimation { duration: 180 } }
                            Rectangle {   // ring thrown off when this becomes the depth
                                id: depthRing
                                anchors.centerIn: parent; width: 7; height: 7
                                color: "transparent"; border.color: root.colLight; border.width: 1
                                opacity: 0
                            }
                            ParallelAnimation {
                                id: depthRingAnim
                                NumberAnimation { target: depthRing; property: "scale";   from: 1;   to: 3.6; duration: 460; easing.type: Easing.OutCubic }
                                NumberAnimation { target: depthRing; property: "opacity"; from: 0.9; to: 0;   duration: 460; easing.type: Easing.OutQuad }
                            }
                            Connections {
                                target: root
                                function onDepthChanged() { if (index === root.depth - 1 && root.live) depthRingAnim.restart() }
                            }
                        }
                    }
                }
                Row {   // path
                    spacing: 8; anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: root.crumbs()
                        Row {
                            spacing: 8
                            readonly property bool last: index === root.crumbs().length - 1
                            Text {
                                visible: index > 0; text: "▸"; font.pixelSize: 9
                                color: Theme.alpha(Theme.paper, 0.45)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: modelData; font.pixelSize: 10; font.letterSpacing: 2
                                font.weight: parent.last ? Font.Medium : Font.Normal
                                color: parent.last ? root.colLight : Theme.alpha(Theme.paper, 0.6)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
                Rectangle { width: 1; height: 14; color: Theme.alpha(Theme.paper, 0.25); anchors.verticalCenter: parent.verticalCenter }
                Repeater {   // keys
                    model: root.navHints()
                    Row {
                        spacing: 6; anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            width: nk.implicitWidth + 8; height: 16; color: "transparent"
                            border.color: Theme.alpha(Theme.paper, 0.35); border.width: 1
                            anchors.verticalCenter: parent.verticalCenter
                            Text { id: nk; anchors.centerIn: parent; text: modelData[0]; font.pixelSize: 8; font.letterSpacing: 1; color: root.colCard }
                        }
                        Text { text: modelData[1]; font.pixelSize: 9; font.letterSpacing: 2; color: Theme.alpha(Theme.paper, 0.75); anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════
        //   YES / NO card (power actions that ask first)
        //   under the HitBurst (z 55) and the nav bar (z 60)
        // ═══════════════════════════════════════════════════════
        Rectangle {
            id: confirmDim
            anchors.fill: parent
            z: 48
            color: "black"
            opacity: root.confirmKey !== "" ? 0.42 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 200 } }
            MouseArea { anchors.fill: parent; enabled: root.confirmKey !== ""; onClicked: root.confirmCancel() }
        }
        Item {
            id: confirmCard
            z: 50
            anchors.centerIn: parent
            width: 440; height: confirmCol.implicitHeight + 48
            readonly property bool on: root.confirmKey !== ""
            property string shownKey: ""       // keeps the text while the card fades out
            onOnChanged: if (on) { shownKey = root.confirmKey; cTitleScramble.start() }
            readonly property var pa: root.powerActs[shownKey] || ({h3: "", ask: "", warn: ""})
            opacity: on ? 1 : 0
            scale: on ? 1 : 0.94
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2 } }
            MouseArea { anchors.fill: parent; enabled: confirmCard.on }   // a click on the card isn't one outside

            Rectangle { anchors.fill: parent; color: root.colCard; border.color: root.colInk; border.width: 1 }
            Rectangle {
                anchors.fill: parent; anchors.margins: 4
                color: "transparent"; border.color: root.colInk; border.width: 1; opacity: 0.35
            }
            Item {   // diamond corners + glass rim (as the other cards)
                anchors.fill: parent; z: 3
                Rectangle {
                    x: 1; y: 1; width: parent.width - 2; height: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.35 + 0.05 * Math.sin(root.t * 0.8); color: Theme.alpha(Theme.light, 0.9) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
                Repeater {
                    model: 4
                    Rectangle {
                        width: 7; height: 7; rotation: 45; color: root.colInk
                        x: (index % 2 === 0 ? 0 : parent.width) - 3.5
                        y: (index < 2 ? 0 : parent.height) - 3.5
                    }
                }
            }

            Column {
                id: confirmCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                spacing: 0
                Row {
                    spacing: 8
                    Rectangle {
                        width: 6; height: 6; rotation: 45; color: Theme.warn
                        anchors.verticalCenter: parent.verticalCenter
                        scale: 1 + 0.35 * root.pulse
                    }
                    Text { text: "CONFIRM"; font.pixelSize: 11; font.letterSpacing: 5; font.weight: Font.Medium; color: root.colInk; opacity: 0.6 }
                }
                Item { width: 1; height: 8 }
                Rectangle { width: 36; height: 1; color: root.colInk; opacity: 0.5 }
                Item { width: 1; height: 14 }
                Text {
                    id: cTitle
                    property string targetText: confirmCard.pa.h3.toUpperCase()
                    text: targetText
                    font.pixelSize: 20; font.letterSpacing: 6; font.weight: Font.Medium
                    color: root.colInk
                    ScrambleAnim { id: cTitleScramble; target: cTitle; duration: 320 }
                }
                Item { width: 1; height: 10 }
                Text { text: confirmCard.pa.ask; font.pixelSize: 15; color: root.colInk }
                Item { width: 1; height: 4 }
                Text {
                    width: confirmCol.width
                    text: confirmCard.pa.warn || ""
                    font.pixelSize: 11; color: root.colInkSoft; wrapMode: Text.WordWrap; lineHeight: 1.2
                }
                Item { width: 1; height: 22 }
                Item {   // YES · NO, one ink selector springing between them (an afterimage trailing)
                    id: cBtns
                    width: confirmCol.width; height: 38
                    readonly property real bw: (width - 16) / 2
                    readonly property real selX: root.confirmYes ? 0 : bw + 16
                    Rectangle {
                        width: cBtns.bw; height: cBtns.height; color: root.colInk; opacity: 0.22
                        x: cBtns.selX
                        Behavior on x { SpringAnimation { spring: 3.2; damping: 0.34; epsilon: 0.3 } }
                    }
                    Item {
                        width: cBtns.bw; height: cBtns.height
                        x: cBtns.selX
                        Behavior on x { SpringAnimation { spring: 5.5; damping: 0.30; epsilon: 0.25 } }
                        scale: 1 - 0.05 * root.press + 0.06 * root.cHitT
                        Rectangle { anchors.fill: parent; color: root.colInk }
                        Rectangle {   // the edge: brick on YES
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: 3 + 2 * root.pulse
                            color: root.confirmYes ? Theme.warn : root.colAccent
                        }
                        Rectangle { anchors.fill: parent; color: root.colLight; opacity: 0.45 * root.cHitT }
                    }
                    ConfirmBtn { id: yesBtn; yes: true;  x: 0;              width: cBtns.bw }
                    ConfirmBtn { id: noBtn;  yes: false; x: cBtns.bw + 16;  width: cBtns.bw }
                }
            }
        }

        // ═══════════════════════════════════════════════════════
        //   QR Modal qshare (visible quand qshareUrl !== "")
        // ═══════════════════════════════════════════════════════
        Rectangle {
            id: qrBackdrop
            anchors.fill: parent
            color: "#000000"
            opacity: root.qshareUrl !== "" ? 0.55 : 0
            visible: opacity > 0
            z: 100
            Behavior on opacity { NumberAnimation { duration: 280 } }
            MouseArea {
                anchors.fill: parent
                onClicked: root.stopQshare()
                enabled: root.qshareUrl !== ""
            }
        }

        Item {
            id: qrModal
            anchors.centerIn: parent
            width: 380; height: 560
            z: 101
            opacity: root.qshareUrl !== "" ? 1 : 0
            visible: opacity > 0
            scale: root.qshareUrl !== "" ? 1.0 : 0.92
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            // Fond carte
            Rectangle {
                anchors.fill: parent
                color: root.colCard
                border.color: root.colInk
                border.width: 1
            }
            // Bordure interne décalée
            Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                color: "transparent"
                border.color: root.colInk
                border.width: 1
                opacity: 0.35
            }
            // Diamond corners + glass rim (as ScreenCapture / Menu)
            Item {
                anchors.fill: parent; z: 3
                visible: true
                Rectangle {
                    x: 1; y: 1; width: parent.width - 2; height: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.35 + 0.05 * Math.sin(root.t * 0.8); color: Theme.alpha(Theme.light, 0.9) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
                Repeater {
                    model: 4
                    Rectangle {
                        width: 7; height: 7; rotation: 45; color: root.colInk
                        x: (index % 2 === 0 ? 0 : parent.width) - 3.5
                        y: (index < 2 ? 0 : parent.height) - 3.5
                    }
                }
            }

            Column {
                anchors.fill: parent
                anchors.margins: 24
                anchors.bottomMargin: 52   // place pour le bouton STOP
                spacing: 10

                // Header
                Text {
                    text: "QSHARE"
                    font.pixelSize: 11
                    font.letterSpacing: 5
                    font.weight: Font.Medium
                    color: root.colInk
                    opacity: 0.6
                }
                Rectangle { width: 36; height: 1; color: root.colInk; opacity: 0.5 }

                Item { width: 1; height: 4 }

                // Direction + cible du transfert
                Text {
                    width: parent.width
                    text: (root.qshareMode === "recv" ? "PHONE → PC   " : "PC → PHONE   ")
                          + root.qshareLabel
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: root.colInk
                    elide: Text.ElideMiddle
                }
                // Mode réseau, en clair
                Text {
                    width: parent.width
                    text: root.qshareTunnel
                          ? "Internet · works on mobile data"
                          : "LAN · phone must share this Wi-Fi"
                    font.pixelSize: 10
                    color: root.colInkSoft
                }

                // QR area
                Item {
                    width: parent.width
                    height: 280
                    Rectangle {
                        anchors.centerIn: parent
                        width: 280; height: 280
                        color: root.colHi
                        Image {
                            anchors.fill: parent
                            anchors.margins: 8
                            source: root.qshareQrPath !== ""
                                    ? "file://" + root.qshareQrPath + "?t=" + Date.now()
                                    : ""
                            fillMode: Image.PreserveAspectFit
                            smooth: false
                            cache: false
                            asynchronous: true
                        }
                        // Loading state — le tunnel Cloudflare prend
                        // quelques secondes, on dit pourquoi ça attend
                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 24
                            visible: root.qshareQrPath === ""
                            text: root.qshareStatus !== ""
                                  ? root.qshareStatus.toUpperCase()
                                  : "GENERATING…"
                            font.pixelSize: 10
                            font.letterSpacing: 3
                            color: root.colCard
                            opacity: 0.6
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // URL en petit
                Text {
                    width: parent.width
                    text: root.qshareUrl
                    font.family: Theme.mono
                    font.pixelSize: 9
                    color: root.colInk
                    opacity: 0.55
                    elide: Text.ElideMiddle
                    horizontalAlignment: Text.AlignHCenter
                }

                // Journal des transferts (le serveur reste allumé, donc
                // il peut y en avoir plusieurs pour un seul QR)
                Text {
                    width: parent.width
                    visible: root.qshareTicks.length === 0
                    text: root.qshareMode === "recv"
                          ? "Scan, then pick files on your phone"
                          : "Scan to open the file list on your phone"
                    font.pixelSize: 10
                    font.letterSpacing: 1.5
                    color: root.colInk
                    opacity: 0.7
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
                Column {
                    width: parent.width
                    spacing: 1
                    visible: root.qshareTicks.length > 0
                    Repeater {
                        // Les 3 derniers transferts, plus récent en haut
                        model: root.qshareTicks.slice(-3).reverse()
                        Text {
                            width: parent.width
                            text: "✓ " + modelData
                            font.family: Theme.mono
                            font.pixelSize: 10
                            color: root.colInk
                            opacity: 0.85
                            elide: Text.ElideMiddle
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                    Text {
                        width: parent.width
                        visible: root.qshareTicks.length > 3
                        text: root.qshareTicks.length + " transfers total"
                        font.pixelSize: 9
                        color: root.colInkSoft
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            // Bouton Cancel/Stop en bas-droite
            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 14
                width: 90; height: 26
                color: cancelMA.containsMouse ? root.colInk : "transparent"
                border.color: root.colInk
                border.width: 1
                Behavior on color { ColorAnimation { duration: 180 } }

                Text {
                    anchors.centerIn: parent
                    // Le serveur tourne tant que ce modal est ouvert
                    text: "× STOP"
                    font.pixelSize: 10
                    font.letterSpacing: 2.5
                    font.weight: Font.Medium
                    color: cancelMA.containsMouse ? root.colCard : root.colInk
                    Behavior on color { ColorAnimation { duration: 180 } }
                }
                MouseArea {
                    id: cancelMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.stopQshare()
                }
            }
        }
    }

    // ── Power exit: the triangles collapse, the screen goes dark, the command runs ──
    Item {
        id: exitLayer
        anchors.fill: parent
        z: 300
        visible: root.exitKey !== ""
        // nothing behind it reacts any more
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }
        Rectangle { anchors.fill: parent; color: "black"; opacity: root.exitFade }
        property string line: root.exitKey !== "" ? (root.powerActs[root.exitKey] || {exit: ""}).exit : ""
        Column {
            anchors.centerIn: parent
            spacing: 16
            opacity: Math.min(1, root.exitFade * 1.5)
            Item {
                width: 18; height: 18
                anchors.horizontalCenter: parent.horizontalCenter
                Rectangle {
                    anchors.centerIn: parent; width: 12; height: 12; rotation: 45
                    color: "transparent"; border.color: root.exitError !== "" ? Theme.voidWarn : Theme.voidLight; border.width: 1
                }
                Rectangle {
                    anchors.centerIn: parent; width: 5; height: 5; rotation: 45
                    color: root.exitError !== "" ? Theme.voidWarn : Theme.voidLight
                    opacity: 0.35 + 0.65 * root.pulse
                }
            }
            Text {
                id: exitTitle
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.exitError !== "" ? "FAILED" : exitLayer.line   // no typing: it fades in with the dark
                font.family: Theme.voidFont
                font.pixelSize: Theme.voidStep(2); font.letterSpacing: 0.26 * Theme.voidStep(2)
                font.weight: Theme.voidWeight
                color: root.exitError !== "" ? Theme.voidWarn : Theme.voidLight
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 260 * root.exitFade; height: 1
                color: Theme.voidLight; opacity: 0.45
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(implicitWidth, 640)
                wrapMode: Text.Wrap; maximumLineCount: 3
                horizontalAlignment: Text.AlignHCenter
                text: root.exitError !== "" ? root.exitError
                    : root.exitKey !== "" ? "$ " + (root.powerActs[root.exitKey] || {cmd: []}).cmd.join(" ") : ""
                font.family: Theme.mono; font.pixelSize: Theme.voidStep(0)
                color: Theme.alpha(Theme.voidLight, 0.6)
                elide: Text.ElideRight
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //   COMPOSANTS
    // ═══════════════════════════════════════════════════════════════════

    // ── Flèche NieR ──
    component NierArrow: Item {
        id: ar
        property string axis: "top"
        width: 36; height: 36

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter:   parent.verticalCenter
        anchors.horizontalCenterOffset: {
            if (axis === "left")  return -root.slotGapH / 2
            if (axis === "right") return  root.slotGapH / 2
            return 0
        }
        anchors.verticalCenterOffset: {
            if (axis === "top")    return -root.slotGapV / 2
            if (axis === "bottom") return  root.slotGapV / 2
            return 0
        }

        readonly property bool isFocused:
              (root.slot === axis) && (root.level === 1 || root.level === 3)

        readonly property real restRotation:
              axis === "top"    ? 180 :
              axis === "bottom" ? 0   :
              axis === "left"   ? 90  : -90
        readonly property real focusRotation:
              axis === "top"    ? 0   :
              axis === "bottom" ? 180 :
              axis === "left"   ? -90 : 90

        Image {
            id: arrowImg
            anchors.fill: parent
            source: root.arrowPng
            sourceSize.width: 256
            sourceSize.height: 256
            fillMode: Image.PreserveAspectFit
            smooth: true
            rotation: ar.isFocused ? ar.focusRotation : ar.restRotation
        }
        // assets/nier-arrow.png (the game's glyph) isn't in the repo: a diamond and a
        // chevron in the theme's ink stand in for it
        Item {
            anchors.fill: parent
            visible: arrowImg.status !== Image.Ready
            rotation: arrowImg.rotation
            Rectangle {
                width: parent.width * 0.16; height: width; rotation: 45; antialiasing: true
                anchors.horizontalCenter: parent.horizontalCenter; y: parent.height * 0.1
                color: Theme.ink
            }
            Canvas {
                anchors.fill: parent
                onPaint: {
                    var c = getContext("2d"), w = width, h = height
                    c.reset(); c.fillStyle = Theme.ink
                    c.beginPath(); c.moveTo(w * 0.2, h * 0.36); c.lineTo(w * 0.5, h * 0.94)
                    c.lineTo(w * 0.8, h * 0.36); c.lineTo(w * 0.5, h * 0.56); c.closePath(); c.fill()
                }
            }
        }

        opacity: {
            if (!root.isOpen && !root.closing) return 0
            if (root.closing) return 0.55  // toutes au repos pendant la fermeture
            if (isFocused)  return 1.0
            if (root.level >= 2) return 0.18
            return 0.55
        }
        Behavior on opacity { NumberAnimation { duration: 320 } }
    }

    // ── YES / NO button (the selector under it is drawn by the card) ──
    component ConfirmBtn: Item {
        id: cb
        property bool yes: false
        readonly property bool sel: root.confirmYes === yes
        height: 38
        scale: sel ? 1 - 0.05 * root.press + 0.06 * root.cHitT : 1
        Rectangle {
            anchors.fill: parent; color: "transparent"
            border.color: root.colInk; border.width: cb.sel ? 2 : 1
            opacity: cb.sel ? 1 : 0.55
        }
        Rectangle {
            width: 6; height: 6; rotation: cb.sel ? 225 : 45
            Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            color: cb.sel ? root.colCard : root.colInk
            opacity: cb.sel ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }
        Text {
            anchors.centerIn: parent
            text: cb.yes ? "YES" : "NO"
            font.pixelSize: 13; font.letterSpacing: 4; font.weight: Font.Medium
            color: cb.sel ? root.colCard : root.colInk
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            // a card that opens under a resting pointer doesn't pick for it
            onPositionChanged: if (Date.now() - root._cardAt > 250) root.confirmChoose(cb.yes)
            onClicked: { root.confirmChoose(cb.yes); root.confirmActivate() }
        }
    }

    // ── Slot ──
    component Slot: Item {
        id: sl
        property string slotKey: ""
        property string title: ""
        property string subtitle: ""
        property bool   isCenter: false

        readonly property bool isFocus:    root.slot === slotKey
        readonly property bool isOpposite: !isCenter && (
              (slotKey === "top"    && root.slot === "bottom") ||
              (slotKey === "bottom" && root.slot === "top")    ||
              (slotKey === "left"   && root.slot === "right")  ||
              (slotKey === "right"  && root.slot === "left"))
        readonly property bool isInL3: isFocus && root.level === 3
        readonly property bool inverted: isCenter && root.power    // the turned-over cross: an ink centre

        width: 280; height: 56
        z: isFocus ? 5 : 2

        opacity: {
            if (!root.isOpen && !root.closing) return 0
            if (root.level === 3) {
                if (isFocus) return 1.0
                if (isCenter) return 0.4
                return 0.28
            }
            // L1 (et closing) : tous les slots clairs
            return 1.0
        }
        Behavior on opacity { NumberAnimation { duration: 320 } }

        // Marqueur focus à gauche
        // Focus mark ◆› — on the outer side, pointing the way the section lies
        // (the inner gap already holds the cross's own arrow)
        Item {
            id: focusMark
            width: 20; height: 18
            readonly property point at: sl.slotKey === "left"   ? Qt.point(-24, sl.height / 2)
                                      : sl.slotKey === "top"    ? Qt.point(sl.width / 2, -17)
                                      : sl.slotKey === "bottom" ? Qt.point(sl.width / 2, sl.height + 17)
                                      :                           Qt.point(sl.width + 24, sl.height / 2)
            x: at.x - width / 2; y: at.y - height / 2
            rotation: sl.slotKey === "left" ? 180 : sl.slotKey === "top" ? -90 : sl.slotKey === "bottom" ? 90 : 0
            opacity: (sl.isFocus && !sl.isInL3 && !sl.isCenter) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }

            Rectangle {   // light with an ink rim: reads on dark and light panes alike
                width: 8; height: 8; rotation: 45
                color: root.colLight
                border.color: root.colInk; border.width: 1
                scale: 1 + 0.3 * root.pulse + (sl.isFocus ? 0.8 * root.press : 0)
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
            }
            Canvas {
                anchors.left: parent.left
                anchors.leftMargin: 12
                width: 8; height: 12
                anchors.verticalCenter: parent.verticalCenter
                onPaint: {
                    var ctx = getContext("2d"); ctx.reset()
                    ctx.lineJoin = "miter"
                    for (var pass = 0; pass < 2; pass++) {       // ink rim, then light stroke
                        ctx.strokeStyle = pass === 0 ? root.colInk : root.colLight
                        ctx.lineWidth = pass === 0 ? 3.2 : 1.4
                        ctx.beginPath()
                        ctx.moveTo(1, 2)
                        ctx.lineTo(width - 2, height / 2)
                        ctx.lineTo(1, height - 2)
                        ctx.stroke()
                    }
                }
            }
        }

        // ↵ on this section: the impact comes out of the focus mark
        Connections {
            target: root
            function onConfirmPulse(s) {
                if (!sl.isFocus || root.depth !== 1) return
                var p = sl.isCenter ? box.mapToItem(null, box.width / 2, box.height / 2)    // the centre: from its middle
                                    : focusMark.mapToItem(null, 4, focusMark.height / 2)
                root.impactAt(sl.Window.window, p.x, p.y, s)
            }
        }

        // ── Box wrapper ──
        Item {
            id: boxWrap
            anchors.fill: parent
            opacity: sl.isInL3 ? 0 : 1
            scale: sl.isFocus ? root.focusScale(1) : 1
            // a focused section steps out along its own direction
            transform: Translate {
                x: sl.isFocus && !sl.isCenter ? (sl.slotKey === "left" ? -8 : sl.slotKey === "right" ? 8 : 0) : 0
                y: sl.isFocus && !sl.isCenter ? (sl.slotKey === "top" ? -8 : sl.slotKey === "bottom" ? 8 : 0) : 0
                Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }
            Behavior on opacity { NumberAnimation { duration: 240 } }

            Rectangle {
                id: box
                anchors.fill: parent
                color: sl.inverted ? root.colHi : root.colCard
                border.color: root.colInk
                border.width: 1
                Behavior on color { ColorAnimation { duration: 200 } }

                // Onglet asymétrique — on the edge facing the centre
                Rectangle {
                    visible: !sl.isCenter
                    readonly property bool vert: sl.slotKey === "top" || sl.slotKey === "bottom"
                    x: sl.slotKey === "left" ? parent.width - 4 : 0
                    y: sl.slotKey === "top" ? parent.height - 4 : 0
                    width:  vert ? parent.width : 4
                    height: vert ? 4 : parent.height
                    color: sl.isFocus ? root.colHi : root.colInk
                    Behavior on color { ColorAnimation { duration: 220 } }
                    z: 2
                }

                // Bordure interne
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 4
                    color: "transparent"
                    border.color: sl.inverted ? root.colCard : root.colInk
                    border.width: 1
                    opacity: sl.isFocus ? 0.6 : (sl.isCenter ? 0.5 : 0.35)
                    Behavior on opacity { NumberAnimation { duration: 220 } }
                    z: 2
                }

                // Diamond corners + glass rim (as ScreenCapture / Menu)
                Item {
                    anchors.fill: parent; z: 3
                    visible: !(sl.isCenter)
                    Rectangle {
                        x: 1; y: 1; width: parent.width - 2; height: 1
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.35 + 0.05 * Math.sin(root.t * 0.8); color: Theme.alpha(Theme.light, 0.9) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }
                    Repeater {
                        model: 4
                        Rectangle {
                            width: 7; height: 7; rotation: 45; color: root.colInk
                            x: (index % 2 === 0 ? 0 : parent.width) - 3.5
                            y: (index < 2 ? 0 : parent.height) - 3.5
                        }
                    }
                }

                // Curtain wipe
                Rectangle {
                    id: curtain
                    anchors.fill: parent
                    color: root.colCard
                    transform: Scale {
                        readonly property bool vert: sl.slotKey === "top" || sl.slotKey === "bottom"
                        origin.x: sl.slotKey === "left" ? box.width : 0
                        origin.y: sl.slotKey === "top" ? box.height : 0
                        xScale: vert ? 1 : (sl.isFocus && !sl.isCenter ? 1 : 0)
                        yScale: vert ? (sl.isFocus && !sl.isCenter ? 1 : 0) : 1
                        Behavior on xScale { NumberAnimation { duration: 380; easing.type: Easing.InOutQuint } }
                        Behavior on yScale { NumberAnimation { duration: 380; easing.type: Easing.InOutQuint } }
                    }
                    z: 1
                    visible: !sl.isCenter
                }

                Rectangle {   // hit-stop flash
                    anchors.fill: parent; z: 5
                    color: root.colLight
                    opacity: sl.isFocus && root.hitDepth === 1 ? 0.45 * root.hitT : 0
                }

                // Indicateur (carré sombre à gauche)
                Rectangle {
                    visible: !sl.isCenter
                    width: 14; height: 14
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.colInk
                    opacity: sl.isFocus ? 0 : 0.85
                    transform: Scale {
                        origin.x: 7; origin.y: 7
                        xScale: sl.isFocus ? 0 : 1
                        yScale: sl.isFocus ? 0 : 1
                        Behavior on xScale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        Behavior on yScale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    }
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    z: 3
                }

                // Label
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: sl.isCenter ? 0 : 42
                    anchors.right: parent.right
                    anchors.rightMargin: sl.isCenter ? 0 : 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    z: 4
                    Text {
                        id: slotTitleTxt
                        property string targetText: sl.title
                        text: targetText
                        onTargetTextChanged: titleScramble.start()    // the cross turning over
                        font.pixelSize: sl.isCenter ? 15 : 13
                        font.weight: Font.Medium
                        font.letterSpacing: sl.isCenter ? 6 : 0.3
                        color: sl.inverted ? root.colCard : root.colInk
                        horizontalAlignment: sl.isCenter ? Text.AlignHCenter : Text.AlignLeft
                        anchors.horizontalCenter: sl.isCenter ? parent.horizontalCenter : undefined
                        ScrambleAnim { id: titleScramble; target: slotTitleTxt; duration: 300 }
                    }
                    Text {
                        text: sl.subtitle
                        font.pixelSize: sl.isCenter ? 9 : 10
                        color: sl.inverted ? Theme.alpha(root.colCard, 0.7) : root.colInkSoft
                        font.letterSpacing: sl.isCenter ? 1 : 0.2
                        horizontalAlignment: sl.isCenter ? Text.AlignHCenter : Text.AlignLeft
                        anchors.horizontalCenter: sl.isCenter ? parent.horizontalCenter : undefined
                    }
                }
            }
        }

        // Losanges aux coins du center
        Repeater {
            model: sl.isCenter ? 4 : 0
            Rectangle {
                width: 5; height: 5
                color: root.colInk
                rotation: 45
                x: (index === 0 || index === 2) ? -3 : (sl.width - 3)
                y: (index < 2) ? -3 : (sl.height - 3)
                z: 6
                opacity: sl.isFocus ? 1 : 0
                transform: Scale {
                    origin.x: 2.5; origin.y: 2.5
                    xScale: sl.isFocus ? 1 : 0
                    yScale: sl.isFocus ? 1 : 0
                    Behavior on xScale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                    Behavior on yScale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                }
                Behavior on opacity { NumberAnimation { duration: 220 } }
            }
        }

        // Sub-items (dimmed while the keys are on the actions: depth 3). Cards, then
        // one ink selector that springs between them (afterimages trailing), then
        // the labels on top — so the selection slides instead of each row filling.
        Item {
            id: subBox
            anchors.centerIn: parent
            readonly property var  items: sl.isInL3 ? root.subList(sl.slotKey) : []
            readonly property real rowH: 36 + 12
            readonly property int  focusIdx: {
                for (var i = 0; i < items.length; i++) if (items[i].key === root.sub) return i
                return -1
            }
            width: 220; height: items.length ? items.length * rowH - 12 : 0
            opacity: sl.isInL3 ? (root.depth === 3 ? 0.5 : 1) : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 280 } }
            // depth push: shoved the way you went, springs back
            transform: Translate { x: root.kick * root.kickDir.x * 12; y: root.kick * root.kickDir.y * 12 }

            // the selector waits for the rows to slide in
            property bool entered: false
            readonly property bool on: sl.isInL3
            onOnChanged: { entered = false; if (on) subEnterT.restart() }
            Timer { id: subEnterT; interval: 300; onTriggered: subBox.entered = true }

            Repeater {
                model: subBox.items
                SubItem { part: "card"; y: index * subBox.rowH; subItem: modelData; parentSlot: sl.slotKey; enterDelay: 280 + index * 80 }
            }
            SlideSel {
                width: subBox.width
                targetY: Math.max(0, subBox.focusIdx) * subBox.rowH
                targetH: 36
                shown: subBox.entered && subBox.focusIdx >= 0
                solid: root.depth === 2
                bounce: root.depth === 2
                pop: root.focusScale(2)
                flash: root.hitDepth === 2 ? root.hitT : 0
            }
            Repeater {
                model: subBox.items
                SubItem { part: "face"; y: index * subBox.rowH; subItem: modelData; parentSlot: sl.slotKey; enterDelay: 280 + index * 80 }
            }
        }

        // Détails
        Item {
            id: detailsItem
            visible: sl.isInL3 && root.hasDetail()
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 280 } }

            anchors.left: sl.slotKey === "left" ? undefined : parent.right
            anchors.right: sl.slotKey === "left" ? parent.left : undefined
            anchors.leftMargin: 30
            anchors.rightMargin: 30
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: {
                if (root.power) return 0      // a short card: level with its section
                if (sl.slotKey === "top")    return -200
                if (sl.slotKey === "bottom") return  100
                return 0
            }
            width: 360
            height: detailsCol.implicitHeight + 36
            transform: Translate { x: root.kick * root.kickDir.x * 12; y: root.kick * root.kickDir.y * 12 }

            // Box stylisée style NieR (fond opaque + bordure + onglet)
            Rectangle {
                anchors.fill: parent
                color: root.colCard
                border.color: root.colInk
                border.width: 1
            }
            // Bordure interne décalée
            Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                color: "transparent"
                border.color: root.colInk
                border.width: 1
                opacity: 0.35
            }
            // Diamond corners + glass rim (as ScreenCapture / Menu)
            Item {
                anchors.fill: parent; z: 3
                visible: true
                Rectangle {
                    x: 1; y: 1; width: parent.width - 2; height: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.35 + 0.05 * Math.sin(root.t * 0.8); color: Theme.alpha(Theme.light, 0.9) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
                Repeater {
                    model: 4
                    Rectangle {
                        width: 7; height: 7; rotation: 45; color: root.colInk
                        x: (index % 2 === 0 ? 0 : parent.width) - 3.5
                        y: (index < 2 ? 0 : parent.height) - 3.5
                    }
                }
            }

            Column {
                id: detailsCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                anchors.topMargin: 18
                spacing: 0

                Text {
                    id: detailH3
                    property string targetText: root.detailH3().toUpperCase()
                    text: targetText
                    onTargetTextChanged: scrambleH3.start()
                    font.pixelSize: 11
                    font.letterSpacing: 5
                    font.weight: Font.Medium
                    color: root.colInk
                    opacity: 0.7

                    ScrambleAnim {
                        id: scrambleH3
                        target: detailH3
                        duration: 320
                    }
                }

                Item { width: 1; height: 8 }

                Rectangle {
                    width: 36
                    height: 1
                    color: root.colInk
                    opacity: 0.5
                }

                Item { width: 1; height: 14 }

                Row {
                    spacing: 10
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.detailOn() ? root.colHi : root.colInkSoft
                        SequentialAnimation on opacity {
                            running: root.detailOn()
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.4; duration: 1100 }
                            NumberAnimation { to: 1.0; duration: 1100 }
                        }
                    }
                    Text {
                        id: detailStatus
                        property string targetText: root.detailStatus()
                        text: targetText
                        onTargetTextChanged: scrambleStatus.start()
                        font.pixelSize: 12
                        color: root.colInk
                        anchors.verticalCenter: parent.verticalCenter
                        // largeur max : panneau total - dot - margin
                        width: detailsCol.width - 26
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap

                        ScrambleAnim {
                            id: scrambleStatus
                            target: detailStatus
                            duration: 380
                        }
                    }
                }

                // ── Explication en clair (qshare : ce que fait le mode réseau) ──
                Item {
                    width: 1
                    height: root.detailHint() !== "" ? 8 : 0
                }
                Text {
                    width: detailsCol.width
                    visible: root.detailHint() !== ""
                    text: root.detailHint()
                    font.pixelSize: root.power ? 11 : 10
                    color: root.colInkSoft
                    lineHeight: 1.25
                    wrapMode: Text.WordWrap
                }
                // ── Hibernate: can the image fit in the swap? ──
                Item { width: 1; height: hibRow.visible ? 10 : 0 }
                Row {
                    id: hibRow
                    visible: root.power && root.sub === "hibernate" && root.hib !== null
                    width: detailsCol.width
                    spacing: 8
                    readonly property bool ok: root.hib !== null && root.hib.ok
                    property real shake: 0
                    transform: Translate { x: 6 * Math.sin(hibRow.shake * Math.PI * 4) * (1 - hibRow.shake) }
                    NumberAnimation { id: hibShake; target: hibRow; property: "shake"; from: 0; to: 1; duration: 420 }
                    Connections { target: root; function onHibDenied() { hibShake.restart() } }
                    Rectangle {
                        width: 6; height: 6; rotation: 45
                        anchors.verticalCenter: hibTxt.verticalCenter
                        color: hibRow.ok ? root.colInk : Theme.warn
                    }
                    Text {
                        id: hibTxt
                        width: parent.width - 14
                        text: root.hibLine()
                        font.pixelSize: 11; lineHeight: 1.2
                        wrapMode: Text.WordWrap
                        color: hibRow.ok ? root.colInk : Theme.warn
                    }
                }
                // ── Power: what runs, and whether it asks first ──
                Item { width: 1; height: root.power ? 12 : 0 }
                Row {
                    visible: root.power && (root.sub in root.powerActs)
                    width: detailsCol.width
                    spacing: 8
                    readonly property var pa: root.powerActs[root.sub] || ({cmd: [], ask: ""})
                    Text {
                        text: "$ " + parent.pa.cmd.join(" ").replace("sh -c ", "")
                        font.family: Theme.mono; font.pixelSize: 10
                        color: root.colInk; opacity: 0.7
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle {
                        width: askTag.implicitWidth + 10; height: 16
                        color: "transparent"; border.color: root.colInk; border.width: 1; opacity: 0.6
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            id: askTag; anchors.centerIn: parent
                            text: parent.parent.pa.ask ? "ASKS FIRST" : "RUNS AT ONCE"
                            font.pixelSize: 8; font.letterSpacing: 1.5; color: root.colInk
                        }
                    }
                }

                // ── Liste des fichiers sélectionnés (left.send) ──
                Item {
                    width: 1
                    height: selectedFiles.visible ? 10 : 0
                }
                Column {
                    id: selectedFiles
                    width: detailsCol.width
                    spacing: 2
                    visible: sl.slotKey === "left" && root.sub === "send"
                             && root.pendingFiles.length > 0
                    Repeater {
                        // 4 max, puis un compteur pour le reste
                        model: selectedFiles.visible
                               ? root.pendingFiles.slice(0, 4) : []
                        Row {
                            spacing: 6
                            Text {
                                text: "▪"
                                font.pixelSize: 9
                                color: root.colInk
                                opacity: 0.55
                            }
                            Text {
                                width: selectedFiles.width - 16
                                text: root.fileName(modelData)
                                font.family: Theme.mono
                                font.pixelSize: 10
                                color: root.colInk
                                opacity: 0.8
                                elide: Text.ElideMiddle
                            }
                        }
                    }
                    Text {
                        visible: root.pendingFiles.length > 4
                        text: "+ " + (root.pendingFiles.length - 4) + " more"
                        font.pixelSize: 9
                        color: root.colInkSoft
                        leftPadding: 16
                    }
                }

                Item { width: 1; height: 14 }

                // Liste scrollable des actions
                // Pour les notifs (right.history) : composant NotifBtn avec expand
                // Pour le reste : ActionBtn standard
                Item {
                    id: actListContainer
                    width: parent.width
                    opacity: root.depth === 3 ? 1 : 0.55   // dimmed until you step in (depth 3)
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    property bool isNotifList: sl.slotKey === "right" && root.sub === "history"
                    property int actCount: root.actList().length
                    // Hauteur adaptative max 8 visibles, mais hauteur d'item plus grande pour notifs expanded
                    height: isNotifList
                        ? Math.max(56, Math.min(actCol.implicitHeight, 5 * 56 + 110))
                        : Math.min(actCount, 8) * 40
                    Behavior on height { enabled: actListContainer.isNotifList; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    visible: actCount > 0 || isNotifList   // toujours visible pour notifs (pour msg vide)

                    // Message si liste vide (notifs)
                    Row {
                        anchors.centerIn: parent
                        spacing: 10
                        visible: actListContainer.isNotifList && actListContainer.actCount === 0
                        Rectangle { width: 6; height: 6; rotation: 45; color: "transparent"; border.color: root.colInkSoft; border.width: 1; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "ALL CLEAR"; font.pixelSize: 10; font.letterSpacing: 3; color: root.colInkSoft }
                        Rectangle { width: 6; height: 6; rotation: 45; color: "transparent"; border.color: root.colInkSoft; border.width: 1; anchors.verticalCenter: parent.verticalCenter }
                    }

                    Flickable {
                        id: actFlick
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: actCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        // Auto-scroll vers la notif focusée
                        function scrollToFocus() {
                            var acts = root.actList()
                            for (var i = 0; i < acts.length; i++) {
                                if (acts[i].key === root.action) {
                                    var it = actRep.itemAt(i)
                                    if (!it) return
                                    var itemH = it.height, itemY = it.y
                                    if (itemY < contentY) {
                                        contentY = Math.max(0, itemY - 4)
                                    } else if (itemY + itemH > contentY + height) {
                                        contentY = Math.min(contentHeight - height, itemY + itemH - height + 4)
                                    }
                                    return
                                }
                            }
                        }

                        Connections {
                            target: root
                            function onActionChanged() { actFlick.scrollToFocus() }
                        }

                        SlideSel {
                            id: actSel
                            z: -1
                            width: actCol.width
                            readonly property int idx: {
                                var l = root.actList()
                                for (var i = 0; i < l.length; i++) if (l[i].key === root.action) return i
                                return -1
                            }
                            readonly property Item row: actRep.count > 0 && idx >= 0 ? actRep.itemAt(idx) : null
                            targetY: row ? row.y : 0
                            targetH: row ? row.height : 32
                            shown: root.depth === 3 && row !== null
                            solid: true
                            bounce: true
                            pop: root.focusScale(3)
                            flash: root.hitDepth === 3 ? root.hitT : 0
                        }
                        Column {
                            id: actCol
                            width: parent.width
                            spacing: 8
                            Repeater {
                                id: actRep
                                model: sl.isInL3 ? root.actList() : []
                                Loader {
                                    width: actCol.width
                                    sourceComponent: actListContainer.isNotifList ? notifBtnComp : actionBtnComp
                                    property var actionData: modelData
                                    property bool isFocus: root.action === modelData.key && root.depth === 3
                                    property int enterDelay: 200 + Math.min(index, 5) * 60
                                    property int rowIndex: index
                                }
                            }
                        }
                    }

                    // Indicateur de scroll visible (track + thumb)
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 2
                        color: root.colInk
                        opacity: 0.15
                        visible: actFlick.contentHeight > actFlick.height

                        Rectangle {
                            x: 0
                            width: 2
                            color: root.colInk
                            opacity: 0.7
                            y: actFlick.contentHeight > 0
                                ? (actFlick.contentY / actFlick.contentHeight) * parent.height
                                : 0
                            height: actFlick.contentHeight > 0
                                ? Math.max(20, (actFlick.height / actFlick.contentHeight) * parent.height)
                                : 0
                        }
                    }
                }

                // ── Footer pinned : "Clear All" pour les notifs (visible si notifs > 0) ──
                Item {
                    width: parent.width
                    visible: sl.slotKey === "right" && root.sub === "history" && root.notifications.length > 0
                    height: visible ? 48 : 0

                    Item { width: 1; height: 14 }

                    Rectangle {
                        id: clearAllBtn
                        // selected with ↓ past the last notification (↵ clears), or hovered
                        readonly property bool sel: root.depth === 3 && root.action === "clear-all"
                        readonly property bool lit: sel || clearAllMA.containsMouse
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: 14
                        height: 32
                        color: lit ? root.colInk : "transparent"
                        border.color: root.colInk
                        border.width: sel ? 2 : 1
                        scale: sel ? root.focusScale(3) : 1
                        transform: Translate { y: clearAllBtn.sel ? root.bump * root.bumpDir * 7 : 0 }
                        Behavior on color { ColorAnimation { duration: 160 } }

                        Rectangle {   // accent edge, as the selector's
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: clearAllBtn.sel ? 3 + 2 * root.pulse : 0
                            color: root.colAccent
                        }
                        Rectangle {
                            id: clearGem
                            width: 6; height: 6; rotation: clearAllBtn.sel ? 225 : 45
                            Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            color: root.colCard
                            opacity: clearAllBtn.sel ? 1 : 0
                        }
                        Rectangle { anchors.fill: parent; color: root.colLight; opacity: clearAllBtn.sel && root.hitDepth === 3 ? 0.45 * root.hitT : 0 }
                        Text {
                            anchors.centerIn: parent
                            text: "× CLEAR ALL"
                            font.pixelSize: 11
                            font.letterSpacing: 2.5
                            font.weight: Font.Medium
                            color: clearAllBtn.lit ? root.colCard : root.colInk
                            Behavior on color { ColorAnimation { duration: 160 } }
                        }
                        Connections {
                            target: root
                            function onConfirmPulse(s) {
                                if (!clearAllBtn.sel) return
                                var p = clearGem.mapToItem(null, 3, 3)
                                root.impactAt(clearAllBtn.Window.window, p.x, p.y, s)
                            }
                        }

                        MouseArea {
                            id: clearAllMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.clearAllNotifs()
                        }
                    }
                }

                // ── Composants pour la liste ──
                Component {
                    id: actionBtnComp
                    ActionBtn {
                        actionData: parent.actionData
                        isFocus: parent.isFocus
                        enterDelay: parent.enterDelay
                    }
                }
                Component {
                    id: notifBtnComp
                    NotifBtn {
                        notifData: parent.actionData
                        isFocus: parent.isFocus
                        enterDelay: parent.enterDelay
                        rowIndex: parent.rowIndex
                    }
                }

                // ── Slider Volume (visible quand bottom.volume) ──
                Item {
                    width: parent.width
                    visible: sl.slotKey === "bottom" && root.sub === "volume"
                    height: visible ? 60 : 0

                    Item { width: 1; height: 14 }

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: 14
                        spacing: 6

                        // Track + thumb
                        Rectangle {
                            id: volTrack
                            width: parent.width
                            height: 24
                            color: "transparent"
                            border.color: root.colInk
                            border.width: 1

                            // Bordure interne
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 3
                                color: "transparent"
                                border.color: root.colInk
                                border.width: 1
                                opacity: 0.35
                            }

                            // Fill (volume actuel)
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.margins: 3
                                width: (parent.width - 6) * (root.audioMuted ? 0 : root.audioVolume)
                                color: root.colInk
                                opacity: root.audioMuted ? 0.3 : 1.0
                                Behavior on width { NumberAnimation { duration: 120 } }
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                            }

                            // MouseArea : clic = mute toggle, drag = set volume
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                property bool dragging: false
                                property real lastX: 0

                                onPressed: function(e) {
                                    if (e.button === Qt.RightButton) {
                                        root.dispatchAction("bottom","volume","mute-toggle")
                                        return
                                    }
                                    dragging = true
                                    lastX = e.x
                                    setVol(e.x)
                                }
                                onReleased: dragging = false
                                onPositionChanged: function(e) {
                                    if (dragging) setVol(e.x)
                                }
                                onClicked: function(e) {
                                    // Click simple sans drag : mute/unmute si sur la cellule à droite (au-delà de la ligne actuelle)
                                    // Sinon set vol
                                    if (Math.abs(e.x - lastX) < 3) {
                                        // C'était juste un click : on a déjà appelé setVol, c'est ok
                                    }
                                }
                                onWheel: function(e) {
                                    var delta = e.angleDelta.y > 0 ? 5 : -5
                                    var newVol = Math.max(0, Math.min(100, Math.round(root.audioVolume * 100) + delta))
                                    root.dispatchAction("bottom","volume","set-volume:" + newVol)
                                }

                                function setVol(x) {
                                    var w = volTrack.width - 6
                                    var v = Math.max(0, Math.min(1, (x - 3) / w))
                                    var pct = Math.round(v * 100)
                                    root.dispatchAction("bottom","volume","set-volume:" + pct)
                                }
                            }
                        }

                        // Indication mute clickable
                        Text {
                            text: root.audioMuted ? "Muted · Click track to unmute" : "Right-click track to mute · Scroll to adjust"
                            font.pixelSize: 9
                            color: root.colInk
                            opacity: 0.5
                            font.letterSpacing: 1
                        }
                    }
                }

                // ── Prompt mot de passe Wi-Fi (visible quand wifiPromptSSID est set) ──
                Item {
                    width: parent.width
                    visible: sl.slotKey === "top" && root.sub === "wifi" && root.wifiPromptSSID !== ""
                    height: visible ? 110 : 0

                    Item { width: 1; height: 14 }

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: 14
                        spacing: 8

                        Text {
                            text: "PASSWORD · " + root.wifiPromptSSID
                            font.pixelSize: 10
                            font.letterSpacing: 3
                            font.weight: Font.Medium
                            color: root.colInk
                            opacity: 0.7
                        }

                        Rectangle {
                            width: parent.width
                            height: 32
                            color: root.colCard
                            border.color: root.colInk
                            border.width: 1

                            // the secret as a diamond per character, like the Void's VoidField
                            // (the TextInput below only takes the keys; its glyphs are hidden)
                            Row {
                                id: pwDiamonds
                                anchors.left: parent.left; anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                property real blink: 1
                                Timer {
                                    interval: 530; repeat: true; running: pwInput.activeFocus
                                    onTriggered: pwDiamonds.blink = pwDiamonds.blink > 0.5 ? 0.2 : 1
                                    onRunningChanged: pwDiamonds.blink = 1
                                }
                                Repeater {
                                    model: Math.min(pwInput.length, 28)
                                    Rectangle {
                                        width: 7; height: 7; rotation: 45
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: root.colInk
                                    }
                                }
                                Rectangle {   // caret
                                    width: 7; height: 7; rotation: 45
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: "transparent"; border.color: root.colInk; border.width: 1
                                    opacity: pwInput.activeFocus ? pwDiamonds.blink : 0.35
                                }
                                Text {
                                    visible: pwInput.length === 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "TYPE PASSWORD"
                                    font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 2.5
                                    color: root.colInk; opacity: 0.35
                                }
                            }

                            TextInput {
                                id: pwInput
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                color: "transparent"
                                selectionColor: "transparent"
                                selectedTextColor: "transparent"
                                cursorDelegate: Item {}
                                font.pixelSize: 13
                                echoMode: TextInput.Password
                                clip: true
                                activeFocusOnTab: true
                                focus: root.wifiPromptSSID !== ""
                                onTextChanged: root.wifiPasswordInput = text
                                onAccepted: root.dispatchAction("top","wifi","submit-password")
                                Keys.onEscapePressed: root.dispatchAction("top","wifi","cancel-prompt")

                                // Timer pour forcer le focus après que le widget soit rendu
                                // (le focus immédiat est volé par le keyHandler parent)
                                Timer {
                                    id: pwFocusTimer
                                    interval: 50
                                    repeat: false
                                    onTriggered: {
                                        if (root.wifiPromptSSID !== "") {
                                            pwInput.text = ""
                                            pwInput.forceActiveFocus()
                                        }
                                    }
                                }
                                Connections {
                                    target: root
                                    function onWifiPromptSSIDChanged() {
                                        if (root.wifiPromptSSID !== "") {
                                            pwFocusTimer.restart()
                                        }
                                    }
                                }
                                // Au cas où le widget devient visible avant que la propriété change
                                onVisibleChanged: {
                                    if (visible && root.wifiPromptSSID !== "") {
                                        pwFocusTimer.restart()
                                    }
                                }
                            }
                        }

                        // Erreur si applicable
                        Text {
                            visible: root.wifiError !== ""
                            text: root.wifiError
                            width: parent.width; elide: Text.ElideRight
                            font.pixelSize: 10
                            color: Theme.warn
                        }

                        // Boutons Connect / Cancel
                        Row {
                            spacing: 8
                            Rectangle {
                                width: 110; height: 28
                                color: root.colInk
                                Text {
                                    anchors.centerIn: parent
                                    text: "CONNECT"
                                    font.pixelSize: 10
                                    font.letterSpacing: 2
                                    font.weight: Font.Medium
                                    color: root.colCard
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.dispatchAction("top","wifi","submit-password")
                                }
                            }
                            Rectangle {
                                width: 80; height: 28
                                color: "transparent"
                                border.color: root.colInk
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: "CANCEL"
                                    font.pixelSize: 10
                                    font.letterSpacing: 2
                                    font.weight: Font.Medium
                                    color: root.colInk
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.dispatchAction("top","wifi","cancel-prompt")
                                }
                            }
                        }
                    }
                }
            }
        }

        // Hover / clic sur la box
        MouseArea {
            anchors.fill: boxWrap
            hoverEnabled: true
            enabled: root.confirmKey === "" && root.exitKey === ""
            onEntered: if (root.level === 1) root.slot = sl.slotKey
            onClicked: {
                if (root.level === 1) {
                    root.slot = sl.slotKey
                    root.activateCurrent()
                }
            }
            visible: !sl.isInL3
        }
    }

    // ── Sub-item ──
    component SubItem: Item {
        id: si
        property var    subItem
        property string parentSlot: ""
        property int    enterDelay: 0
        property string part: "face"    // "card": the paper under the selector · "face": border, marker, label

        readonly property bool isFocus: root.sub === subItem.key
        readonly property bool isActive: isFocus && root.depth === 2   // the keys are on this list

        width: 220
        height: 36

        opacity: 0
        scale: part === "face" && isFocus ? root.focusScale(2) : 1
        // slide in from the side the cross centre is on; the focused face rides the edge bump
        transform: [
            Translate {
                id: subT
                x: si.parentSlot === "left" ? 12 : si.parentSlot === "right" ? -12 : 0
                y: si.parentSlot === "top" ? 12 : si.parentSlot === "bottom" ? -12 : 0
            },
            Translate { y: si.part === "face" && si.isActive ? root.bump * root.bumpDir * 7 : 0 }
        ]
        Component.onCompleted: enterAnim.start()
        SequentialAnimation {
            id: enterAnim
            PauseAnimation { duration: si.enterDelay }
            ParallelAnimation {
                NumberAnimation { target: si; property: "opacity"; to: 1; duration: 200; easing.type: Easing.InOutQuint }
                NumberAnimation { target: subT; property: "x"; to: 0; duration: 200; easing.type: Easing.OutCubic }
                NumberAnimation { target: subT; property: "y"; to: 0; duration: 200; easing.type: Easing.OutCubic }
            }
        }

        Rectangle {
            visible: si.part === "card"
            anchors.fill: parent
            color: root.colCard
        }

        // Bordure : fine en repos, épaisse au focus
        Rectangle {
            visible: si.part === "face"
            anchors.fill: parent
            color: "transparent"
            border.color: root.colInk
            border.width: si.isFocus ? 2 : 1
            opacity: si.isFocus ? 1.0 : 0.55
            Behavior on border.width { NumberAnimation { duration: 180 } }
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }

        Rectangle {
            id: subGem
            visible: si.part === "face"
            width: 6; height: 6
            color: si.isActive ? root.colCard : root.colInk
            Behavior on color { ColorAnimation { duration: 120 } }
            rotation: 45
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            opacity: si.isFocus ? 1 : 0
            transform: Scale {
                origin.x: 3; origin.y: 3
                xScale: si.isFocus ? 1 : 0
                yScale: si.isFocus ? 1 : 0
                Behavior on xScale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                Behavior on yScale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
            }
            Behavior on opacity { NumberAnimation { duration: 200 } }
            z: 3
        }

        // ↵ on this sub: the impact comes out of its marker
        Connections {
            target: root
            enabled: si.part === "face"
            function onConfirmPulse(s) {
                if (!si.isActive) return
                var p = subGem.mapToItem(null, 3, 3)
                root.impactAt(si.Window.window, p.x, p.y, s)
            }
        }

        Text {
            id: subTxt
            visible: si.part === "face"
            property string targetText: si.subItem.label
            text: targetText
            onTargetTextChanged: subScramble.start()
            anchors.centerIn: parent
            font.pixelSize: 13
            font.weight: Font.Medium
            color: si.isActive ? root.colCard : root.colInk
            Behavior on color { ColorAnimation { duration: 120 } }
            z: 3

            ScrambleAnim {
                id: subScramble
                target: subTxt
                duration: 280
            }
        }

        // Re-scramble quand devient focus
        onIsFocusChanged: if (isFocus && part === "face") subScramble.start()

        MouseArea {
            enabled: si.part === "face" && root.confirmKey === "" && root.exitKey === ""
            anchors.fill: parent
            hoverEnabled: true
            // the pointer's list is the active one: hovering a sub puts you on depth 2
            onEntered: {
                if (root.level === 3 && root.slot === si.parentSlot) {
                    if (root.sub !== si.subItem.key) { root.sub = si.subItem.key; root.action = root.firstAction() }
                    root.atAction = false
                }
            }
            onClicked: {
                if (root.level === 3 && root.slot === si.parentSlot) {
                    root.sub = si.subItem.key
                    root.atAction = false
                    root.activateCurrent()
                }
            }
        }
    }

    // ── Bouton d'action ──
    component ActionBtn: Item {
        id: btn
        property var    actionData
        property bool   isFocus: false
        property int    enterDelay: 0

        height: 32

        opacity: 0
        scale: isFocus ? root.focusScale(3) : 1
        transform: [
            Translate { id: btnT; x: -8 },
            Translate { y: btn.isFocus ? root.bump * root.bumpDir * 7 : 0 }
        ]
        Component.onCompleted: enterAnim2.start()
        SequentialAnimation {
            id: enterAnim2
            PauseAnimation { duration: btn.enterDelay }
            ParallelAnimation {
                NumberAnimation { target: btn; property: "opacity"; to: 1; duration: 200; easing.type: Easing.InOutQuint }
                NumberAnimation { target: btnT; property: "x"; to: 0; duration: 200; easing.type: Easing.OutCubic }
            }
            ScriptAction { script: btnScramble.start() }
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: root.colInk
            border.width: 1
            opacity: btn.isFocus ? 1 : 0.5
            Behavior on opacity { NumberAnimation { duration: 220 } }
        }

        // ↵ on this action: the impact comes out of its marker
        Connections {
            target: root
            function onConfirmPulse(s) {
                if (!btn.isFocus || root.depth !== 3) return
                var p = btnGem.mapToItem(null, 3, 3)
                root.impactAt(btn.Window.window, p.x, p.y, s)
            }
        }

        // Marqueur losange à gauche au focus (spins in)
        Rectangle {
            id: btnGem
            width: 6; height: 6; rotation: btn.isFocus ? 225 : 45
            Behavior on rotation { NumberAnimation { duration: 420; easing.type: Easing.OutBack } }
            color: root.colCard
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            opacity: btn.isFocus ? 1 : 0
            transform: Scale {
                origin.x: 3; origin.y: 3
                xScale: btn.isFocus ? 1 : 0
                yScale: btn.isFocus ? 1 : 0
                Behavior on xScale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                Behavior on yScale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
            }
            Behavior on opacity { NumberAnimation { duration: 200 } }
            z: 3
        }

        Text {
            id: btnTxt
            property string targetText: btn.actionData.label.toUpperCase()
            text: targetText
            onTargetTextChanged: btnScramble.start()
            anchors.left: parent.left
            anchors.leftMargin: 22
            anchors.right: parent.right
            anchors.rightMargin: 8
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: 11
            font.weight: Font.Medium
            font.letterSpacing: 2.5
            color: btn.isFocus ? root.colCard : root.colInk
            Behavior on color { ColorAnimation { duration: 120 } }
            z: 2

            ScrambleAnim {
                id: btnScramble
                target: btnTxt
                duration: 280
            }
        }

        // Re-scramble quand on devient focus
        onIsFocusChanged: if (isFocus) btnScramble.start()

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: if (root.level === 3) { root.action = btn.actionData.key; root.atAction = true }
            onClicked: {
                root.action = btn.actionData.key
                root.atAction = true
                root.activateCurrent()
            }
        }
    }

    // ── Notification row ──
    // Collapsed: app · age, summary. Expanded (→ / ▾ / ↵ when it can't open): body,
    // details and what it offers. ↵ opens it (its default action) when its app still
    // listens; DEL / × dismisses it — the row flies out and the rest slide up.
    component NotifBtn: Item {
        id: nbtn
        property var  notifData
        property bool isFocus: false
        property int  enterDelay: 0
        property int  rowIndex: 0
        readonly property string nkey: notifData && notifData.nkey ? notifData.nkey : ""
        readonly property bool expanded: root.expandedNotif === nkey
        readonly property bool critical: !!notifData && notifData.urgency === "critical"
        readonly property color fg: isFocus ? root.colCard : root.colInk

        height: expanded ? Math.max(48, info.implicitHeight + 14) : 48
        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        clip: true

        scale: isFocus ? root.focusScale(3) : 1
        transform: [
            Translate { id: nbtnT; x: 0 },
            Translate { id: gapT; y: 0 },
            Translate { y: nbtn.isFocus ? root.bump * root.bumpDir * 7 : 0 }
        ]

        // Entrance once per showing; a list rebuilt by a poll or a dismissal keeps
        // its rows still, and the ones below a removed row slide up into its gap
        Component.onCompleted: {
            root._notifRows[nkey] = nbtn
            if (root._gapAt >= 0 && rowIndex >= root._gapAt) { gapT.y = root._gapH; gapAnim.start() }
            if (root._seenNotif[nkey]) { opacity = 1; return }
            root._seenNotif[nkey] = true
            opacity = 0; nbtnT.x = -8
            nbtnEnter.start()
        }
        Component.onDestruction: if (root._notifRows[nkey] === nbtn) delete root._notifRows[nkey]
        SequentialAnimation {
            id: nbtnEnter
            PauseAnimation { duration: nbtn.enterDelay }
            ParallelAnimation {
                NumberAnimation { target: nbtn; property: "opacity"; to: 1; duration: 300; easing.type: Easing.InOutQuint }
                NumberAnimation { target: nbtnT; property: "x"; to: 0; duration: 300; easing.type: Easing.OutCubic }
            }
        }
        NumberAnimation { id: gapAnim; target: gapT; property: "y"; to: 0; duration: 280; easing.type: Easing.OutCubic }

        // Leaving: cut out to the right (staggered for CLEAR ALL)
        Connections {
            target: root
            function onNotifLeave(key, order, strength) {
                if (key !== nbtn.nkey && key !== "*") return
                var slot = key === "*" ? Math.min(nbtn.rowIndex, 8) : order
                if (strength > 0 && (key !== "*" || nbtn.rowIndex === 0)) {
                    var p = nbtnGem.mapToItem(null, 2.5, 2.5)
                    root.impactAt(nbtn.Window.window, p.x, p.y, strength)
                }
                nbtnEnter.stop()
                leavePause.duration = slot * 45
                leaveAnim.restart()
            }
        }
        SequentialAnimation {
            id: leaveAnim
            PauseAnimation { id: leavePause; duration: 0 }
            ParallelAnimation {
                NumberAnimation { target: nbtnT; property: "x"; to: 90; duration: 190; easing.type: Easing.InCubic }
                NumberAnimation { target: nbtn; property: "opacity"; to: 0; duration: 190; easing.type: Easing.InQuad }
            }
        }

        // Frame (the fill is the list's sliding selector)
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: root.colInk
            border.width: 1
            opacity: nbtn.isFocus ? 1 : 0.5
            Behavior on opacity { NumberAnimation { duration: 220 } }
        }
        // urgent: a standing accent edge
        Rectangle {
            visible: nbtn.critical && !nbtn.isFocus
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 3; color: root.colAccent
        }

        // ↵ on this notification: the impact comes out of its marker
        Connections {
            target: root
            function onConfirmPulse(s) {
                if (!nbtn.isFocus || root.depth !== 3) return
                var p = nbtnGem.mapToItem(null, 2.5, 2.5)
                root.impactAt(nbtn.Window.window, p.x, p.y, s)
            }
        }

        // Marker: ◆ when it can be opened, ◇ when it can only be read
        Rectangle {
            id: nbtnGem
            x: 8; y: 24 - 2.5
            width: 5; height: 5; rotation: nbtn.isFocus ? 225 : 45
            Behavior on rotation { NumberAnimation { duration: 420; easing.type: Easing.OutBack } }
            color: nbtn.notifData.live ? nbtn.fg : "transparent"
            border.color: nbtn.fg; border.width: 1
            opacity: nbtn.isFocus || nbtn.notifData.live ? 1 : 0.45
            z: 3
        }

        // Contenu
        Column {
            id: info
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors { leftMargin: 20; rightMargin: 44; topMargin: nbtn.expanded ? 8 : Math.max(4, (48 - implicitHeight) / 2) }
            spacing: 1
            z: 2

            Item {   // app · age
                width: parent.width; height: 11
                Text {
                    text: nbtn.notifData.app ? nbtn.notifData.app.toUpperCase() : "—"
                    font.pixelSize: 8; font.letterSpacing: 1.5
                    color: nbtn.critical && !nbtn.isFocus ? root.colAccent : nbtn.fg
                    opacity: nbtn.critical ? 0.95 : 0.6
                    width: parent.width - 40; elide: Text.ElideRight
                }
                Text {
                    anchors.right: parent.right
                    text: nbtn.notifData.ts ? root.notifAge(nbtn.notifData.ts) : ""
                    font.pixelSize: 8; font.letterSpacing: 1
                    color: nbtn.fg; opacity: 0.55
                }
            }
            Text {   // summary
                width: parent.width
                text: nbtn.notifData.label
                font.pixelSize: 11; font.weight: Font.Medium
                color: nbtn.fg
                elide: Text.ElideRight
                wrapMode: nbtn.expanded ? Text.WordWrap : Text.NoWrap
                maximumLineCount: nbtn.expanded ? 3 : 1
            }
            Item { width: 1; height: nbtn.expanded ? 4 : 0 }
            Text {   // body
                width: parent.width
                visible: nbtn.expanded && text !== ""
                text: nbtn.notifData.body || ""
                textFormat: Text.PlainText
                font.pixelSize: 10
                color: nbtn.fg; opacity: 0.85
                wrapMode: Text.WordWrap
                maximumLineCount: 6
                elide: Text.ElideRight
            }
            Item { width: 1; height: nbtn.expanded ? 4 : 0 }
            Flow {   // what it offers (↵ runs the first / "default")
                width: parent.width; spacing: 4
                visible: nbtn.expanded && !!nbtn.notifData.live && (nbtn.notifData.actions || []).length > 0
                Repeater {
                    model: nbtn.expanded ? (nbtn.notifData.actions || []).slice(0, 4) : []
                    Rectangle {
                        width: at.implicitWidth + 10; height: 15
                        color: "transparent"; border.color: nbtn.fg; border.width: 1
                        opacity: index === 0 ? 0.9 : 0.5
                        Text { id: at; anchors.centerIn: parent; text: (index === 0 ? "↵ " : "") + (modelData.text || modelData.id || "").toUpperCase(); font.pixelSize: 7; font.letterSpacing: 1; color: nbtn.fg }
                    }
                }
            }
            Text {   // details
                width: parent.width
                visible: nbtn.expanded
                text: {
                    var bits = []
                    var d = nbtn.notifData
                    if (d.urgency && d.urgency !== "normal") bits.push(d.urgency.toUpperCase())
                    if (d.category) bits.push("cat:" + d.category)
                    if (d.desktopEntry) bits.push(d.desktopEntry)
                    if (!d.live) bits.push("read-only")
                    return bits.join(" · ")
                }
                font.pixelSize: 8; font.letterSpacing: 1
                color: nbtn.fg; opacity: 0.55
                wrapMode: Text.WordWrap
            }
        }

        // ▾ details · × dismiss
        Row {
            anchors { right: parent.right; top: parent.top; rightMargin: 4 }
            height: 48
            z: 4
            Repeater {
                model: ["exp", "del"]
                Item {
                    width: 20; height: 48
                    Text {
                        anchors.centerIn: parent
                        text: modelData === "exp" ? (nbtn.expanded ? "▾" : "▸") : "×"
                        font.pixelSize: modelData === "exp" ? 12 : 14
                        color: nbtn.fg
                        opacity: bma.containsMouse ? 1 : 0.6
                        scale: bma.containsMouse ? 1.2 : 1
                        Behavior on scale { NumberAnimation { duration: 120 } }
                    }
                    MouseArea {
                        id: bma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData === "exp") root.expandedNotif = nbtn.expanded ? "" : nbtn.nkey
                            else root.dismissNotif(nbtn.nkey, false)
                        }
                    }
                }
            }
        }

        // Body: hover takes the focus, a click is ↵ (open, or show the details)
        MouseArea {
            anchors.fill: parent
            anchors.rightMargin: 44
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            z: 0
            onEntered: { root.action = nbtn.notifData.key; root.atAction = true }
            onClicked: {
                root.action = nbtn.notifData.key; root.atAction = true
                root.activateCurrent()
            }
        }
    }

    // The ink selector of a list: springs to the focused row with two afterimages
    // on slower springs, squashes/pops with root.press / hit-stop, rides edge bumps.
    component SlideSel: Item {
        id: ss
        property real targetY: 0
        property real targetH: 32
        property bool shown:  false
        property bool solid:  true     // false: a faint trace (the keys are on another list)
        property bool bounce: false    // this list has the keys: edge bumps move it
        property real pop:    1
        property real flash:  0
        opacity: shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }

        Rectangle {
            width: ss.width; height: ss.targetH; color: root.colInk
            opacity: ss.solid ? 0.12 : 0
            y: ss.targetY
            Behavior on y { SpringAnimation { spring: 2.2; damping: 0.36; epsilon: 0.3 } }
        }
        Rectangle {
            width: ss.width; height: ss.targetH; color: root.colInk
            opacity: ss.solid ? 0.24 : 0
            y: ss.targetY
            Behavior on y { SpringAnimation { spring: 3.4; damping: 0.34; epsilon: 0.3 } }
        }
        Item {
            id: head
            width: ss.width; height: ss.targetH
            y: ss.targetY
            Behavior on y { SpringAnimation { spring: 5.5; damping: 0.30; epsilon: 0.25 } }
            scale: ss.pop
            transform: Translate { y: ss.bounce ? root.bump * root.bumpDir * 7 : 0 }
            Rectangle {
                anchors.fill: parent; color: root.colInk
                opacity: ss.solid ? 1 : 0.14
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }
            Rectangle {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: ss.solid ? 2 + 3 * root.pulse : 0; color: root.colAccent
            }
            Item {
                anchors.fill: parent; clip: true
                Rectangle {
                    id: selSheen
                    width: 60; height: parent.height * 2; y: -parent.height / 2; rotation: 18; x: -120
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.5; color: Theme.alpha(Theme.light, 0.26) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
                NumberAnimation { id: selSheenAnim; target: selSheen; property: "x"; from: -120; to: head.width + 40; duration: 560; easing.type: Easing.OutCubic }
            }
            Rectangle { anchors.fill: parent; color: root.colLight; opacity: 0.4 * ss.flash }
        }
        onTargetYChanged: if (shown && solid) selSheenAnim.restart()
        onSolidChanged:   if (shown && solid) selSheenAnim.restart()
    }

    component ScrambleAnim: QtObject {
        id: anim
        property Item target: null   // doit avoir une property "targetText"
        property int duration: 280
        property string chars: "▸◆▪▫░▒▓█/\\|-_=+*"
        property int _elapsed: 0
        property int _step: 16

        property var _timer: Timer {
            interval: anim._step
            repeat: true
            running: false
            onTriggered: {
                if (!anim.target) { running = false; return }
                anim._elapsed += anim._step
                var t = Math.min(1, anim._elapsed / anim.duration)
                var finalText = anim.target.targetText
                var len = finalText.length
                var result = ""
                for (var i = 0; i < len; i++) {
                    var reveal = i / len
                    if (t > reveal + 0.15) {
                        result += finalText[i]
                    } else if (t > reveal) {
                        result += anim.chars[Math.floor(Math.random() * anim.chars.length)]
                    } else {
                        result += "\u00A0"
                    }
                }
                anim.target.text = result
                if (t >= 1) {
                    anim.target.text = finalText
                    running = false
                }
            }
        }

        function start() {
            if (!target) return
            _elapsed = 0
            _timer.running = true
        }
    }
}
