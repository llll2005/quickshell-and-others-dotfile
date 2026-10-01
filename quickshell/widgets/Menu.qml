import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../components"
import "../theme"

// App launcher. Window, lifecycle, glass backdrop, warm-up and rhythm come from
// components/Popup.qml; the diamond iris reveal (reveal.frag) is this panel's own.
Popup {
    id: root

    readonly property int lw: 780
    readonly property int lh: 540

    IpcHandler {
        target: "menu"
        function toggle(): void { root.toggle() }
    }
    burst.spreadX: 1.5
    burst.spreadY: 0.7

    property real   revealP:    1      // diamond iris: 0 hidden → 1 open
    property bool   _masking:   false
    property string currentCat: "all"
    property string searchQuery: ""
    property int    focusIdx:   0
    property string clockStr:   "--:--:--"

    // Palette
    readonly property color paper:     Theme.paper
    readonly property color ink:       Theme.ink
    readonly property color inkStrong: Theme.inkStrong
    readonly property color inkSoft:   Theme.inkSoft
    readonly property color lineSoft:  Theme.alpha(Theme.ink, 0.25)
    readonly property color lineVsoft: Theme.alpha(Theme.ink, 0.12)
    readonly property color accent:    Theme.accent
    readonly property color light:     Theme.light
    function paperA(a) { return Theme.alpha(Theme.paper, a) }
    function inkA(a)   { return Theme.alpha(Theme.ink, a) }

    // ── Category transitions follow the gesture (+1 = → / swipe left) ──
    property int    catDir:  1
    property string listCat: "all"   // what the list shows; trails currentCat by the swap-out
    property real   listOut: 0
    readonly property real rowH: 46
    onCurrentCatChanged: {
        if (!root.shown) { swapAnim.stop(); root.listOut = 0; root.listCat = root.currentCat; return }
        swapAnim.restart()
    }
    signal rowsEnter()
    property bool _entering: false     // rows created now slide in (open / category swap)
    Timer { id: enteringT; interval: 700; onTriggered: root._entering = false }
    function _startEntering() { root._entering = true; enteringT.restart(); root.rowsEnter() }

    // ── Launch flourish ──
    property real   flashV: 0
    property real   hitT:   0     // launch hit-stop: the selector pops and holds
    property bool   _busy:  false
    property string _launchCmd: ""

    // Apps
    property var  apps: []
    property bool appsLoaded: false

    readonly property var catLabels: ({
        "all":"ALL","dev":"DEVELOP","sys":"SYSTEM","net":"NETWORK",
        "media":"MEDIA","office":"OFFICE","graphics":"GRAPHICS",
        "games":"GAMES","other":"OTHER"
    })

    readonly property var catOrder: ["all","dev","sys","net","media","office","graphics","games","other"]

    readonly property var catKeys: {
        var present = {"all": true}
        for (var i = 0; i < apps.length; i++) present[apps[i].cat] = true
        return catOrder.filter(function(k) { return present[k] })
    }

    readonly property var filteredApps: {
        var q = searchQuery.toLowerCase().trim()
        return apps.filter(function(a) {
            var catOk = listCat === "all" || a.cat === listCat
            var qOk = !q || a.name.toLowerCase().indexOf(q) >= 0 || a.meta.toLowerCase().indexOf(q) >= 0
            return catOk && qOk
        })
    }

    // The app's own icon: Icon= (a path, or a name in the icon theme — see the
    // IconTheme pragma in shell.qml), else the real binary's name, the desktop id,
    // or a -symbolic variant. "" = none; the row falls back to its glyph.
    function resolveIcon(icon, bin, desktopId) {
        if (icon.charAt(0) === "/") return "file://" + icon
        var cands = [icon, bin, desktopId, desktopId.toLowerCase(), icon ? icon + "-symbolic" : ""]
        for (var i = 0; i < cands.length; i++) {
            if (!cands[i]) continue
            var p = Quickshell.iconPath(cands[i], true)
            if (p) return p
        }
        return ""
    }

    // ── Lecture .desktop ──
    Process {
        id: desktopReader
        command: ["python3", Quickshell.shellDir + "/scripts/list-apps.py"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n")
                var result = []
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim()
                    if (!line) continue
                    // name|desktop-id|categories|icon|binary|exec (scripts/list-apps.py)
                    var parts = line.split("|")
                    if (parts.length < 6) continue
                    var name      = parts[0].trim()
                    var desktopId = parts[1].trim()
                    var cats      = parts[2] || ""
                    var iconName  = parts[3].trim()
                    var binName   = parts[4].trim()
                    var rawExec   = parts.slice(5).join("|").replace(/%[A-Za-z]/g,"").trim()
                    if (!name || !desktopId) continue
                    // Utiliser l'exec brut si dispo, sinon le desktop ID
                    var launchCmd = rawExec || desktopId

                    var cat = "other"
                    if (/Development|IDE|TextEditor|Debugger/i.test(cats))          cat = "dev"
                    else if (/WebBrowser|Email|Chat|Network|FileTransfer/i.test(cats)) cat = "net"
                    else if (/Audio|Video|Player|Music/i.test(cats))                cat = "media"
                    else if (/Office|Spreadsheet|WordProcessor|Presentation/i.test(cats)) cat = "office"
                    else if (/Graphics|Photography|2DGraphics/i.test(cats))         cat = "graphics"
                    else if (/Game|Emulator/i.test(cats))                           cat = "games"
                    else if (/System|Utility|Monitor|Settings/i.test(cats))         cat = "sys"

                    var nl = name.toLowerCase()
                    var ico = "·"
                    if (/terminal|kitty|alacritty|console/.test(nl)) ico = "▸"
                    else if (/firefox|chromium|browser/.test(nl))     ico = "○"
                    else if (/nvim|vim|editor|code|helix/.test(nl))   ico = "⌥"
                    else if (/file|yazi|ranger/.test(nl))             ico = "▤"
                    else if (/btop|htop|monitor/.test(nl))            ico = "▲"
                    else if (/music|audio|pulse/.test(nl))            ico = "♪"
                    else if (/video|mpv|vlc/.test(nl))                ico = "▶"
                    else if (/lock|hyprlock/.test(nl))                ico = "⬡"
                    else if (/libre|office|calc|writer/.test(nl))     ico = "≡"
                    else if (/gimp|inkscape|image/.test(nl))          ico = "⬜"
                    else if (cat === "dev")      ico = "⌥"
                    else if (cat === "net")      ico = "○"
                    else if (cat === "media")    ico = "▶"
                    else if (cat === "sys")      ico = "◈"
                    else if (cat === "office")   ico = "≡"

                    result.push({
                        id:        String(i+1).padStart(2,"0"),
                        name:      name,
                        cat:       cat,
                        meta:      desktopId,
                        desktopId: launchCmd,
                        cmd:       launchCmd,
                        icon:      ico,     // glyph, shown when no real icon resolves
                        iconSrc:   root.resolveIcon(iconName, binName, desktopId)
                    })
                }
                root.apps = result
                root.appsLoaded = true
            }
        }
    }

    // Un seul Process — commande fixée impérativement (pas de binding pour éviter les races)
    Process {
        id: launchProc
        running: false
    }

    function launchApp(cmd) {
        if (!cmd) return
        launchProc.running = false
        launchProc.command = ["sh", "-c", "nohup " + cmd + " >/dev/null 2>&1 &"]
        launchProc.running = true
        root.close()
    }
    function launch(cmd) { root.launchApp(cmd) }

    // Only ticks while open (hidden full-screen surface would redraw each second).
    Timer {
        interval: 1000; running: root.isOpen; repeat: true; triggeredOnStart: true
        onTriggered: {
            var d = new Date()
            root.clockStr = String(d.getHours()).padStart(2,"0") + ":"
                + String(d.getMinutes()).padStart(2,"0") + ":"
                + String(d.getSeconds()).padStart(2,"0")
        }
    }

    Timer {
        id: focusTimer; interval: 50; repeat: true; running: false
        property int attempts: 0
        onTriggered: {
            searchInput.forceActiveFocus()
            attempts++
            if (attempts >= 8) { running = false; attempts = 0 }
        }
    }

    Component.onCompleted: {
        var d = new Date()
        clockStr = String(d.getHours()).padStart(2,"0") + ":"
            + String(d.getMinutes()).padStart(2,"0") + ":"
            + String(d.getSeconds()).padStart(2,"0")
        desktopReader.running = true
    }

    // ── Panel host (clip + wipe) ──
    Item {
        id: panelHost
        z: 2
        x: (root.screenW - root.lw) / 2
        y: (root.screenH - root.lh) / 2
        width:  root.lw
        height: root.lh
        clip:   true
        visible: root.shown || root.warming
        layer.enabled: root._masking || root.warming
        layer.effect: ShaderEffect {
            property real  progress: root.revealP
            property real  mode:     0          // diamond iris
            property size  dims:     Qt.size(root.lw, root.lh)
            property color edge:     Theme.alpha(Theme.light, 0.75)
            fragmentShader: "../components/shaders/reveal.frag.qsb?v=2"   // bump ?v= after recompiling (see TriField.qml)
        }

        // Contenu
        Rectangle {
            id:     panelContent
            anchors.fill: parent
            color:  root.paper
            border.color: root.ink; border.width: 1

            // Grille fine
            Repeater {
                model: Math.floor(root.lw/20)+1
                Rectangle { x:index*20; y:0; width:1; height:root.lh; color:root.lineVsoft }
            }
            Repeater {
                model: Math.floor(root.lh/20)+1
                Rectangle { x:0; y:index*20; width:root.lw; height:1; color:root.lineVsoft }
            }

            // Glass rim + cut-diamond corners (as ScreenCapture)
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
                    width: 7; height: 7; rotation: 45
                    x: (index % 2 === 0 ? 0 : root.lw) - 3.5
                    y: (index < 2 ? 0 : root.lh) - 3.5
                    color: root.ink
                }
            }

            // Clic n'importe où → focus sur search
            MouseArea {
                anchors.fill: parent; z: -1
                onClicked: searchInput.forceActiveFocus()
                propagateComposedEvents: true
            }

            // Scan line
            Rectangle {
                id: scanLine; x:0; width:root.lw; height:2; z:20; opacity:0
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position:0.0; color:"transparent" }
                    GradientStop { position:0.5; color:root.accent }
                    GradientStop { position:1.0; color:"transparent" }
                }
                NumberAnimation on y {
                    id: scanAnim; from:0; to:root.lh; duration:700; running:false
                    easing.type: Easing.Linear
                    onStarted:  scanLine.opacity = 1
                    onFinished: scanLine.opacity = 0
                }
            }

            // ── HEADER ──
            Item {
                id: header; width:parent.width; height:52

                Row {
                    anchors { left:parent.left; right:parent.right; verticalCenter:parent.verticalCenter
                              leftMargin:28; rightMargin:28 }
                    Row {
                        id: hdrL
                        spacing:14; anchors.verticalCenter:parent.verticalCenter
                        Text { text:"SYSTEM"; font.pixelSize:11; font.letterSpacing:3.5; font.weight:Font.Medium; color:root.inkStrong }
                        Rectangle { width:24; height:1; color:root.inkSoft; anchors.verticalCenter:parent.verticalCenter }
                        Text { text:"システム"; font.pixelSize:10; font.letterSpacing:2; color:root.inkSoft }
                    }
                    Item { width: Math.max(0, parent.width - hdrL.width - hdrR.width); height:1 }
                    Row {
                        id: hdrR
                        spacing:14; anchors.verticalCenter:parent.verticalCenter
                        Item {
                            width:120; height:16; clip:true
                            Text {
                                id:lhTick
                                text: root.clockStr + " · " + root.apps.length + " APPS · "
                                font.pixelSize:9; font.letterSpacing:1.5; color:root.inkSoft; y:2
                                NumberAnimation on x {
                                    from:120; to:-lhTick.implicitWidth
                                    duration:12000; loops:Animation.Infinite; running:root.isOpen
                                }
                            }
                        }
                        Item {   // metronome
                            width: 12; height: 12; anchors.verticalCenter: parent.verticalCenter
                            Rectangle { anchors.centerIn: parent; width: 7; height: 7; rotation: 45; color: root.accent; scale: 1 + 0.45 * root.pulse }
                            Rectangle {
                                anchors.centerIn: parent; width: 7; height: 7; rotation: 45
                                color: "transparent"; border.color: root.accent; border.width: 1
                                scale: 1 + 1.4 * root.beatPhase; opacity: (1 - root.beatPhase) * 0.7
                            }
                        }
                        Text { text:"SESSION 0471"; font.pixelSize:9; font.letterSpacing:2.5; color:root.inkSoft }
                    }
                }
                Rectangle { anchors.bottom:parent.bottom; width:parent.width; height:1; color:root.lineSoft }
            }

            // ── BODY ──
            Item {
                id: body
                anchors { top:header.bottom; bottom:footer.top }
                width: parent.width

                // Sidebar
                Item {
                    id:sidebar; width:160; height:parent.height
                    Rectangle { anchors.right:parent.right; width:1; height:parent.height; color:root.lineSoft }
                    Column {
                        anchors { top:parent.top; topMargin:16 }
                        width:parent.width

                        Repeater {
                            model: root.catKeys
                            CatTab {
                                label:   root.catLabels[modelData] || modelData.toUpperCase()
                                sub:     root.apps.filter(function(a){ return modelData==="all"||a.cat===modelData }).length.toString().padStart(2,"0")
                                active:  root.currentCat === modelData
                                dir:     root.catDir
                                animate: root.shown
                                pulse:   root.pulse
                                onClicked: { root.setCat(modelData); searchInput.forceActiveFocus() }
                            }
                        }

                        Item {
                            width:160; height:48
                            Column {
                                anchors { left:parent.left; leftMargin:22; bottom:parent.bottom; bottomMargin:6 }
                                spacing:4
                                Text { text:root.filteredApps.length+"/"+root.apps.length+" NODES"; font.pixelSize:8; font.letterSpacing:2; color:root.inkSoft; opacity:0.6 }
                                Rectangle {
                                    width:72; height:2; color:root.lineSoft
                                    Rectangle {
                                        height:parent.height; color:root.accent
                                        SequentialAnimation on x { running:root.isOpen; loops:Animation.Infinite
                                            NumberAnimation { from:0; to:44; duration:1400; easing.type:Easing.InOutSine }
                                            NumberAnimation { from:44; to:0; duration:1400; easing.type:Easing.InOutSine } }
                                        SequentialAnimation on width { running:root.isOpen; loops:Animation.Infinite
                                            NumberAnimation { from:10; to:28; duration:1400; easing.type:Easing.InOutSine }
                                            NumberAnimation { from:28; to:10; duration:1400; easing.type:Easing.InOutSine } }
                                    }
                                }
                            }
                        }
                    }
                }

                // Right panel
                Item {
                    anchors { left:sidebar.right; right:parent.right; top:parent.top; bottom:parent.bottom }
                    clip: true

                    // Category name as a large watermark; slides in with the gesture
                    Text {
                        id: watermark
                        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 22; bottomMargin: -22 }
                        text: root.catLabels[root.listCat] || root.listCat.toUpperCase()
                        font.pixelSize: 96; font.weight: Font.Bold; font.letterSpacing: 4
                        color: root.inkA(0.07)
                        property real slide: 0
                        opacity: 1 - root.listOut
                        transform: Translate { x: watermark.slide - root.listOut * 60 * root.catDir }
                        NumberAnimation {
                            id: wmAnim; target: watermark; property: "slide"
                            from: 90 * root.catDir; to: 0; duration: 620; easing.type: Easing.OutQuart
                        }
                        Connections { target: root; function onListCatChanged() { wmAnim.restart() } function onRowsEnter() { wmAnim.restart() } }
                    }
                    Column {
                        anchors.fill:parent

                        // Search
                        Item {
                            width:parent.width; height:46
                            Row {
                                anchors { left:parent.left; right:parent.right; verticalCenter:parent.verticalCenter
                                          leftMargin:24; rightMargin:24 }
                                spacing:10
                                Text { anchors.verticalCenter:parent.verticalCenter; text:"▸"; font.pixelSize:12; color:root.accent }
                                FocusScope {
                                    id:searchScope; width:parent.width-60; height:30
                                    anchors.verticalCenter:parent.verticalCenter
                                    focus: root.isOpen

                                    TextInput {
                                        id:           searchInput
                                        anchors.fill: parent
                                        verticalAlignment: TextInput.AlignVCenter
                                        font.pixelSize:13; font.letterSpacing:0.5; font.weight:Font.Normal
                                        color:        root.inkStrong
                                        cursorVisible:activeFocus
                                        focus:        true
                                        selectByMouse:true
                                        text:         root.searchQuery

                                        onTextEdited: { root.searchQuery=text; root.focusIdx=0 }

                                        Keys.onEscapePressed: root.close()
                                        Keys.onUpPressed: {
                                            root.focusIdx=Math.max(0,root.focusIdx-1)
                                            appList.positionViewAtIndex(root.focusIdx, ListView.Contain)
                                        }
                                        Keys.onDownPressed: {
                                            root.focusIdx=Math.min(root.filteredApps.length-1,root.focusIdx+1)
                                            appList.positionViewAtIndex(root.focusIdx, ListView.Contain)
                                        }
                                        Keys.onReturnPressed: {
                                            var a=root.filteredApps[root.focusIdx]
                                            if(a) root.fireLaunch(a.desktopId)
                                        }
                                        Keys.onLeftPressed:  root.stepCat(-1)
                                        Keys.onRightPressed: root.stepCat(1)

                                        Text {
                                            visible:parent.text===""
                                            anchors.verticalCenter:parent.verticalCenter
                                            text:"search application..."
                                            font.pixelSize:13; font.italic:true; font.weight:Font.Light
                                            color:root.inkSoft; opacity:0.5
                                        }
                                    }
                                }
                            }
                            Rectangle { anchors.bottom:parent.bottom; width:parent.width; height:1; color:root.lineSoft }
                        }

                        // List
                        ListView {
                            id:appList; width:parent.width; height:parent.parent.height-46
                            clip:true; model:root.filteredApps; keyNavigationEnabled:false

                            // A ListView does NOT move declared children into its content (only a
                            // plain Flickable does), so each of these sets `parent: contentItem`
                            // itself — otherwise they stay put while the rows scroll away.
                            // Afterimages trail the selector on slower springs.
                            Rectangle {
                                parent: appList.contentItem
                                z: -2; width: appList.width; height: root.rowH; color: root.ink; opacity: 0.10
                                visible: root.filteredApps.length > 0
                                y: appSel.targetY
                                Behavior on y { SpringAnimation { spring: 2.2; damping: 0.36; epsilon: 0.3 } }
                            }
                            Rectangle {
                                parent: appList.contentItem
                                z: -2; width: appList.width; height: root.rowH; color: root.ink; opacity: 0.22
                                visible: root.filteredApps.length > 0
                                y: appSel.targetY
                                Behavior on y { SpringAnimation { spring: 3.4; damping: 0.34; epsilon: 0.3 } }
                            }
                            Item {
                                id: appSel
                                parent: appList.contentItem
                                z: -1
                                readonly property real targetY: root.focusIdx * root.rowH
                                width: appList.width; height: root.rowH
                                visible: root.filteredApps.length > 0
                                opacity: 1 - root.listOut
                                y: targetY
                                Behavior on y { SpringAnimation { spring: 5.5; damping: 0.30; epsilon: 0.25 } }
                                scale: 1 + 0.05 * root.hitT
                                Rectangle { anchors.fill: parent; color: root.ink }
                                Rectangle {
                                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                    width: 2 + 4 * root.pulse; color: root.accent
                                }
                                Item {
                                    anchors.fill: parent; clip: true
                                    Rectangle {
                                        id: sheen
                                        width: 80; height: parent.height * 2; y: -parent.height / 2
                                        rotation: 18; x: -140
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: "transparent" }
                                            GradientStop { position: 0.5; color: Theme.alpha(Theme.light, 0.26) }
                                            GradientStop { position: 1.0; color: "transparent" }
                                        }
                                    }
                                    NumberAnimation {
                                        id: sheenAnim; target: sheen; property: "x"
                                        from: -140; to: appSel.width + 60; duration: 640; easing.type: Easing.OutCubic
                                    }
                                }
                                Rectangle { anchors.fill: parent; color: root.light; opacity: root.flashV * 0.4 }
                            }
                            // where the launch burst comes from: the focused row's icon (its target row)
                            Item { id: burstAnchor; parent: appList.contentItem; x: 32 + 22 + 14 + 14; y: appSel.targetY + root.rowH / 2 }
                            Connections {
                                target: root
                                function onFocusIdxChanged() { sheenAnim.restart() }
                                function onBeatIndexChanged() { if (root.beatIndex > 0 && root.beatIndex % 8 === 0) sheenAnim.restart() }
                            }

                            delegate: Item {
                                id:appDelegate; width:appList.width; height:root.rowH
                                z: 1
                                property bool isFocused: index===root.focusIdx
                                scale: isFocused ? 1 + 0.05 * root.hitT : 1

                                // slide in from the gesture side (open / category swap), out the other way
                                property real enter: root._entering ? 0 : 1
                                opacity: enter * (1 - root.listOut)
                                transform: Translate { x: ((1 - appDelegate.enter) * 56 - root.listOut * 44) * root.catDir }
                                SequentialAnimation {
                                    id: enterAnim
                                    PropertyAction { target: appDelegate; property: "enter"; value: 0 }
                                    PauseAnimation { duration: 30 + Math.min(index, 9) * 40 }
                                    NumberAnimation { target: appDelegate; property: "enter"; to: 1; duration: 360; easing.type: Easing.OutCubic }
                                }
                                Component.onCompleted: if (root._entering) enterAnim.start()
                                Connections { target: root; function onRowsEnter() { enterAnim.restart() } }

                                Rectangle {
                                    anchors.bottom:parent.bottom
                                    visible: index<root.filteredApps.length-1
                                    x:24; width:parent.width-48; height:1; color:root.lineSoft; opacity:0.5
                                }

                                Row {
                                    anchors {
                                        left:parent.left; right:parent.right; verticalCenter:parent.verticalCenter
                                        leftMargin:  appDelegate.isFocused ? 32 : 24
                                        rightMargin: 24
                                    }
                                    spacing:14
                                    Behavior on anchors.leftMargin { NumberAnimation { duration:240; easing.type:Easing.OutBack } }

                                    Text {
                                        anchors.verticalCenter:parent.verticalCenter
                                        text:modelData.id; width:22; font.pixelSize:9; font.letterSpacing:1.5
                                        color: appDelegate.isFocused ? root.paperA(0.5) : root.inkSoft
                                        Behavior on color { ColorAnimation { duration:120 } }
                                    }
                                    // icon: a square that turns into a diamond when selected
                                    Item {
                                        width: 28; height: 28; anchors.verticalCenter: parent.verticalCenter
                                        Rectangle {   // beat ripple
                                            anchors.centerIn: parent; width: 20; height: 20; rotation: 45
                                            color: "transparent"; border.color: root.light; border.width: 1
                                            visible: appDelegate.isFocused
                                            scale: 1 + 0.9 * root.beatPhase
                                            opacity: (1 - root.beatPhase) * 0.55
                                        }
                                        Rectangle {
                                            anchors.centerIn: parent; width: 24; height: 24
                                            rotation: appDelegate.isFocused ? 45 : 0
                                            scale: appDelegate.isFocused ? 0.86 + 0.06 * root.pulse : 1
                                            color: appDelegate.isFocused ? root.paperA(0.08) : "transparent"
                                            border.width: 1
                                            border.color: appDelegate.isFocused ? root.paperA(0.85) : root.ink
                                            Behavior on rotation { NumberAnimation { duration: 340; easing.type: Easing.OutBack } }
                                            Behavior on border.color { ColorAnimation { duration: 120 } }
                                        }
                                        Image {   // the app's own icon, kept upright inside the frame
                                            id: appIcon
                                            anchors.centerIn: parent
                                            width: 20; height: 20
                                            sourceSize: Qt.size(48, 48)
                                            source: modelData.iconSrc
                                            asynchronous: true; cache: true; smooth: true; mipmap: true
                                            fillMode: Image.PreserveAspectFit
                                            visible: status === Image.Ready
                                            scale: appDelegate.isFocused ? 1.12 : 1
                                            Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                                        }
                                        Text {
                                            anchors.centerIn:parent; text:modelData.icon; font.pixelSize:12
                                            visible: appIcon.status !== Image.Ready
                                            color: appDelegate.isFocused ? root.paperA(0.95) : root.ink
                                            Behavior on color { ColorAnimation { duration:120 } }
                                        }
                                    }
                                    Column {
                                        anchors.verticalCenter:parent.verticalCenter; spacing:2
                                        Text {
                                            text:modelData.name; font.pixelSize:12; font.letterSpacing:1.2; font.weight:Font.Medium
                                            color: appDelegate.isFocused ? root.paper : root.ink
                                            Behavior on color { ColorAnimation { duration:120 } }
                                        }
                                        Text {
                                            text:modelData.meta; font.pixelSize:9; font.letterSpacing:1.5
                                            color: appDelegate.isFocused ? root.paperA(0.5) : root.inkSoft
                                            Behavior on color { ColorAnimation { duration:120 } }
                                        }
                                    }
                                    Item { width:appList.width-310; height:1 }
                                    Text {
                                        anchors.verticalCenter:parent.verticalCenter
                                        text:(root.catLabels[modelData.cat]||modelData.cat).toUpperCase()
                                        font.pixelSize:9; font.letterSpacing:2
                                        color: appDelegate.isFocused ? root.paperA(0.4) : root.inkSoft
                                        Behavior on color { ColorAnimation { duration:120 } }
                                    }
                                    Text {
                                        anchors.verticalCenter:parent.verticalCenter
                                        text:"▸"; font.pixelSize:14; color:root.light
                                        opacity: appDelegate.isFocused ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration:120 } }
                                    }
                                }

                                MouseArea {
                                    id:appMA; anchors.fill:parent; hoverEnabled:true
                                    onEntered: if (!root._busy) root.focusIdx=index
                                    onClicked: { root.focusIdx = index; root.fireLaunch(modelData.desktopId) }
                                }
                            }

                            Item {
                                visible: root.filteredApps.length===0 && root.appsLoaded
                                width:appList.width; height:60
                                Text { anchors.centerIn:parent; text:"▸ NO RESULTS"; font.pixelSize:10; font.letterSpacing:3; color:root.inkSoft; opacity:0.5 }
                            }
                        }
                    }
                }
            }

            // ── FOOTER ──
            Item {
                id:footer; anchors.bottom:parent.bottom; width:parent.width; height:44
                Rectangle { anchors.top:parent.top; width:parent.width; height:1; color:root.lineSoft }
                Row {
                    anchors { left:parent.left; right:parent.right; verticalCenter:parent.verticalCenter
                              leftMargin:28; rightMargin:28 }
                    Row {
                        id: quickRow
                        spacing:0
                        Repeater {
                            model:[
                                {l:"TERMINAL", cmd:"kitty"},
                                {l:"FILES",    cmd:"kitty -e yazi"},
                                {l:"LOCK",     cmd:"$HOME/.config/quickshell/lock.sh"},
                                {l:"SHUTDOWN", cmd:"systemctl poweroff", danger:true}
                            ]
                            delegate: Item {
                                height:44; width:faLbl.implicitWidth+24
                                Rectangle {
                                    visible:index>0
                                    anchors{left:parent.left;top:parent.top;bottom:parent.bottom}
                                    width:1; color:root.lineSoft
                                }
                                Text {
                                    id:faLbl; anchors.centerIn:parent
                                    text:modelData.l; font.pixelSize:9; font.letterSpacing:2.5
                                    color: faMA.containsMouse ? (modelData.danger===true ? root.accent : root.inkStrong) : root.inkSoft
                                    Behavior on color { ColorAnimation { duration:150 } }
                                }
                                Rectangle {
                                    anchors{bottom:parent.bottom;horizontalCenter:parent.horizontalCenter;bottomMargin:6}
                                    width:faMA.containsMouse?faLbl.implicitWidth:0; height:1; color:root.accent
                                    Behavior on width { NumberAnimation { duration:200; easing.type:Easing.OutQuart } }
                                }
                                MouseArea { id:faMA; anchors.fill:parent; hoverEnabled:true; onClicked:root.launch(modelData.cmd) }
                            }
                        }
                    }
                    Item { width: Math.max(0, parent.width - quickRow.width - hintRow.width); height:1 }
                    Row {
                        id: hintRow
                        spacing:14; anchors.verticalCenter:parent.verticalCenter
                        Repeater {
                            model:[["←→","CAT"],["↑↓","NAV"],["↵","OPEN"],["ESC","CLOSE"]]
                            Row {
                                spacing:5; anchors.verticalCenter:parent.verticalCenter
                                Rectangle {
                                    width:kbdT.implicitWidth+8; height:16; color:"transparent"
                                    border.color:root.lineSoft; border.width:1
                                    Text { id:kbdT; anchors.centerIn:parent; text:modelData[0]; font.pixelSize:9; font.letterSpacing:1; color:root.ink }
                                }
                                Text { text:modelData[1]; anchors.verticalCenter:parent.verticalCenter; font.pixelSize:9; font.letterSpacing:2; color:root.inkSoft }
                            }
                        }
                    }
                }
            }
        }

        // Two-finger horizontal swipe switches category (natural scrolling: fingers
        // left = next, like →). Vertical wheel goes on to the list.
        MouseArea {
            anchors.fill: parent; z: 40
            acceptedButtons: Qt.NoButton
            property real acc: 0
            onWheel: (wheel) => {
                var dx = wheel.pixelDelta.x !== 0 ? wheel.pixelDelta.x : wheel.angleDelta.x / 2
                var dy = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 2
                if (Math.abs(dx) <= Math.abs(dy)) { wheel.accepted = false; return }
                swipeIdle.restart()
                if (swipeCool.running) return
                acc += dx
                if (Math.abs(acc) >= 60) { root.stepCat(acc < 0 ? 1 : -1); acc = 0; swipeCool.restart() }
            }
            Timer { id: swipeIdle; interval: 180; onTriggered: parent.acc = 0 }
            Timer { id: swipeCool; interval: 320 }
        }

        // Wipe curtain — frère du contenu
        Rectangle {
            id:wipeCurtain
            anchors{top:parent.top;bottom:parent.bottom}
            color:Theme.sepia; z:50; width:0; x:0   // unused since the diamond iris; kept at 0
        }
    }

    SequentialAnimation {
        id: swapAnim
        NumberAnimation { target: root; property: "listOut"; to: 1; duration: 110; easing.type: Easing.InCubic }
        ScriptAction { script: { root.listCat = root.currentCat; root.listOut = 0; appList.positionViewAtBeginning(); root._startEntering() } }
    }
    function setCat(k) {
        if (k === root.currentCat || root._busy) return
        root.catDir = root.catKeys.indexOf(k) > root.catKeys.indexOf(root.currentCat) ? 1 : -1
        root.currentCat = k; root.focusIdx = 0
    }
    function stepCat(d) {
        var i = root.catKeys.indexOf(root.currentCat) + d
        if (i >= 0 && i < root.catKeys.length) root.setCat(root.catKeys[i])
    }

    // Launch (as ControlCenter): hit-stop — the selector pops, flashes and holds for a
    // beat while the impact flies (HitBurst + a ring through the triangles) — then the
    // app starts while the panel closes
    SequentialAnimation {
        id: launchConfirm
        ScriptAction { script: { root.flashV = 1; root.burst.playAt(burstAnchor, 0, 0, 1) } }
        ParallelAnimation {
            NumberAnimation { target: root; property: "flashV"; to: 0; duration: 420; easing.type: Easing.OutQuad }
            SequentialAnimation {
                NumberAnimation { target: root; property: "hitT"; from: 0; to: 1; duration: 45; easing.type: Easing.OutQuad }
                PauseAnimation { duration: 65 }
                ScriptAction { script: root.launchApp(root._launchCmd) }
                NumberAnimation { target: root; property: "hitT"; to: 0; duration: 220; easing.type: Easing.OutCubic }
            }
        }
    }
    function fireLaunch(cmd) {
        if (!cmd || root._busy || root.phase !== "open") return
        root._busy = true; root._launchCmd = cmd
        launchConfirm.restart()
    }

    // ── Diamond iris (reveal mask, components/shaders/reveal.frag) ──
    SequentialAnimation {
        id: maskIn
        ScriptAction { script: { root.revealP = 0; root._masking = true } }
        ParallelAnimation {
            NumberAnimation { target: root; property: "revealP"; to: 1; duration: 520; easing.type: Easing.OutQuart }
            SequentialAnimation {
                PauseAnimation { duration: 200 }
                ScriptAction { script: root._startEntering() }
            }
        }
        ScriptAction { script: { root._masking = false; scanAnim.start() } }
    }
    SequentialAnimation {
        id: maskOut
        ScriptAction { script: root._masking = true }
        NumberAnimation { target: root; property: "revealP"; to: 0; duration: 300; easing.type: Easing.InCubic }
        ScriptAction { script: root.panelGone() }
    }

    // ── Lifecycle (components/Popup.qml) ──
    onOpening: {
        searchQuery = ""; focusIdx = 0; catDir = 1; _busy = false; currentCat = "all"
        searchInput.text = ""
        if (!appsLoaded) desktopReader.running = true
        focusTimer.attempts = 0
        focusTimer.restart()
    }
    onIntro:  { maskOut.stop(); maskIn.start() }
    onOutro:  { maskIn.stop(); maskOut.start() }
    onFinished: { _masking = false; _busy = false }
}
