import QtQuick

// The login screen in the Void (quickshell/CLAUDE.md, "Design language"): black, its own
// white ink, a diamond, one hairline, the password as a diamond per character — the same
// composition as the shell's lock (quickshell/lockscreen/LockFace.qml) and its power exit.
// No glass: at boot there is nothing on screen yet to shatter; the face fades in from the
// dark, and a login that succeeds fades back into it.
//   type · ↵ log in · ←→ user · ↑↓ session · F11 restart · F12 shut down (each twice)
// Installed by ../sddm-void.sh, which also copies the fonts in (fonts/: Josefin Sans and
// Operator Mono from ~/.local/share/fonts; not in the repo). Try it without logging out:
//   sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/void
Rectangle {
    id: root
    width: 1920; height: 1080
    color: "#000000"

    // SDDM's context: sddm, userModel, sessionModel, keyboard, config, primaryScreen
    readonly property bool primary: typeof primaryScreen === "undefined" ? true : primaryScreen
    readonly property color light: (config && config.light) || "#ffffff"
    readonly property color warn: (config && config.warn) || "#b8403c"
    readonly property real u: Math.max(0.7, height / 1080)
    readonly property real base: Number((config && config.voidBase) || 12)
    readonly property real ratio: Number((config && config.voidRatio) || 1.618)
    function step(k) { return base * Math.pow(ratio, k) * u }
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    FontLoader { id: fVoid; source: "fonts/void.ttf" }
    FontLoader { id: fMono; source: "fonts/mono-Book.otf" }
    readonly property string voidFont: fVoid.status === FontLoader.Ready ? fVoid.name : "sans-serif"
    readonly property string monoFont: fMono.status === FontLoader.Ready ? fMono.name : "monospace"
    readonly property int voidWeight: fVoid.status === FontLoader.Ready ? Number((config && config.voidWeight) || 300) : Font.Normal

    // ── users and sessions, out of SDDM's models ──
    property var users: []          // [{ name, real }]
    property var sessions: []       // names
    property int userIdx: 0
    property int sessionIdx: 0
    Repeater {
        model: typeof userModel !== "undefined" ? userModel : null
        Item {
            Component.onCompleted: {
                var a = root.users.slice()
                a[index] = { name: model.name, real: model.realName || model.name }
                root.users = a
                if (typeof userModel !== "undefined" && userModel.lastIndex >= 0) root.userIdx = userModel.lastIndex
            }
        }
    }
    Repeater {
        model: typeof sessionModel !== "undefined" ? sessionModel : null
        Item {
            Component.onCompleted: {
                var a = root.sessions.slice()
                a[index] = model.name
                root.sessions = a
                if (typeof sessionModel !== "undefined" && sessionModel.lastIndex >= 0) root.sessionIdx = sessionModel.lastIndex
            }
        }
    }
    readonly property string userName: users.length ? users[Math.min(userIdx, users.length - 1)].name : ""
    readonly property string sessionName: sessions.length ? sessions[Math.min(sessionIdx, sessions.length - 1)] : ""

    // ── one attempt ──
    property string pw: ""
    property string phase: "idle"       // idle · verifying · failed · authorized
    property int    fails: 0
    property string armed: ""           // "reboot" · "poweroff": pressed once, waiting for the second
    property real   inT: 0

    function submit() {
        if (pw === "" || phase === "verifying" || phase === "authorized" || typeof sddm === "undefined") return
        phase = "verifying"
        sddm.login(userName, pw, sessionIdx)
    }
    function power(what) {
        if (typeof sddm === "undefined") return
        if (armed !== what) { armed = what; armT.restart(); return }
        armed = ""
        if (what === "reboot") sddm.reboot(); else sddm.powerOff()
    }
    Timer { id: armT; interval: 2400; onTriggered: root.armed = "" }

    Connections {
        target: typeof sddm !== "undefined" ? sddm : null
        ignoreUnknownSignals: true
        function onLoginFailed() { root.pw = ""; root.phase = "failed"; root.fails++; field.fail() }
        function onLoginSucceeded() { root.phase = "authorized"; field.ok(); outAnim.start() }
    }

    Component.onCompleted: {
        if (typeof keyboard !== "undefined") keyboard.numLock = true
        inAnim.start()
    }
    SequentialAnimation {
        id: inAnim
        PauseAnimation { duration: 300 }
        NumberAnimation { target: root; property: "inT"; to: 1; duration: 900; easing.type: Easing.OutCubic }
    }
    SequentialAnimation {
        id: outAnim
        PauseAnimation { duration: 260 }
        NumberAnimation { target: root; property: "inT"; to: 0; duration: 520; easing.type: Easing.InCubic }
    }

    // stepped caret blink (a resting screen idles)
    property real blink: 1
    Timer { interval: 530; running: root.primary; repeat: true; onTriggered: root.blink = root.blink > 0.5 ? 0.15 : 1 }
    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }

    FocusScope {
        anchors.fill: parent
        focus: root.primary
        Keys.onPressed: (e) => {
            var k = e.key
            var busy = root.phase === "verifying" || root.phase === "authorized"
            if (k === Qt.Key_Return || k === Qt.Key_Enter) root.submit()
            else if (k === Qt.Key_F11) root.power("reboot")
            else if (k === Qt.Key_F12) root.power("poweroff")
            else if (busy) {}
            else if (k === Qt.Key_Left && root.users.length > 1) { root.userIdx = (root.userIdx + root.users.length - 1) % root.users.length; root.pw = "" }
            else if (k === Qt.Key_Right && root.users.length > 1) { root.userIdx = (root.userIdx + 1) % root.users.length; root.pw = "" }
            else if (k === Qt.Key_Up && root.sessions.length > 1) root.sessionIdx = (root.sessionIdx + root.sessions.length - 1) % root.sessions.length
            else if (k === Qt.Key_Down && root.sessions.length > 1) root.sessionIdx = (root.sessionIdx + 1) % root.sessions.length
            else if (k === Qt.Key_Escape || (k === Qt.Key_U && (e.modifiers & Qt.ControlModifier))) root.pw = ""
            else if (k === Qt.Key_Backspace) {
                root.pw = (e.modifiers & Qt.ControlModifier) ? "" : root.pw.slice(0, -1)
                if (root.phase === "failed") root.phase = "idle"
            }
            else if (e.text !== "" && e.text.charCodeAt(0) >= 32 && !(e.modifiers & (Qt.ControlModifier | Qt.MetaModifier)) && root.pw.length < 256) {
                root.pw += e.text
                if (root.phase === "failed") root.phase = "idle"
            }
            e.accepted = true
        }

        // ── a screen other than the primary: just the diamond ──
        Rectangle {
            visible: !root.primary
            anchors.centerIn: parent
            width: 12 * root.u; height: width; rotation: 45
            color: "transparent"; border.color: root.alpha(root.light, 0.35); border.width: 1
            opacity: root.inT
        }

        // ── the face, at the optical centre (46 %) ──
        Column {
            visible: root.primary
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.46 - height / 2 + (1 - root.inT) * 14 * root.u
            width: 640 * root.u
            spacing: 0

            Item {   // the diamond: an outline and a core that pulses while verifying
                anchors.horizontalCenter: parent.horizontalCenter
                width: 12 * root.u; height: width
                opacity: Math.min(1, root.inT * 2)
                Rectangle {
                    anchors.fill: parent; rotation: 45; color: "transparent"; border.width: 1
                    border.color: root.phase === "failed" ? root.warn : root.light
                }
                Rectangle {
                    anchors.centerIn: parent; width: 5 * root.u; height: width; rotation: 45
                    color: root.phase === "failed" ? root.warn : root.light
                    opacity: root.phase === "verifying" ? 0.35 + 0.65 * root.blink : 0.9
                }
            }
            Item { width: 1; height: 26 * root.u }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: root.inT
                text: ({ idle: "SYSTEM LOGIN", verifying: "VERIFYING", failed: "ACCESS DENIED", authorized: "WELCOME" })[root.phase]
                font.family: root.voidFont; font.weight: root.voidWeight
                font.pixelSize: Math.round(root.step(2)); font.letterSpacing: 0.26 * root.step(2)
                color: root.phase === "failed" ? root.warn : root.light
            }
            Item { width: 1; height: 22 * root.u }
            Item {   // the hairline
                anchors.horizontalCenter: parent.horizontalCenter
                width: 260 * root.u; height: 1
                Rectangle { width: parent.width * root.inT; x: (parent.width - width) / 2; height: 1; color: root.alpha(root.light, 0.45) }
            }
            Item { width: 1; height: 20 * root.u }
            Text {   // the mono line: the time, the date, this machine
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: 0.6 * root.inT
                text: Qt.formatTime(root.now, "HH:mm") + "  ·  " + Qt.formatDate(root.now, "ddd dd MMM").toUpperCase()
                      + (typeof sddm !== "undefined" && sddm.hostName ? "  ·  " + String(sddm.hostName).toUpperCase() : "")
                font.family: root.monoFont; font.pixelSize: Math.round(root.step(0)); font.letterSpacing: 0.06 * root.step(0)
                color: root.light
            }
            Item { width: 1; height: 44 * root.u }
            Row {    // as whom (←→ when there are several)
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: root.inT
                spacing: 12 * root.u
                readonly property bool many: root.users.length > 1
                Text { text: "AS"; font.family: root.voidFont; font.weight: root.voidWeight; font.pixelSize: Math.round(root.step(0)); font.letterSpacing: 0.3 * root.step(0); color: root.alpha(root.light, 0.45) }
                Text { visible: parent.many; text: "◂"; font.pixelSize: Math.round(root.step(0)); color: root.alpha(root.light, 0.6) }
                Text { text: root.userName.toUpperCase(); font.family: root.voidFont; font.weight: root.voidWeight; font.pixelSize: Math.round(root.step(0)); font.letterSpacing: 0.3 * root.step(0); color: root.light }
                Text { visible: parent.many; text: "▸"; font.pixelSize: Math.round(root.step(0)); color: root.alpha(root.light, 0.6) }
            }
            Item { width: 1; height: 18 * root.u }
            Item {   // the password: a diamond per character on a hairline
                id: field
                anchors.horizontalCenter: parent.horizontalCenter
                width: 380 * root.u; height: 28 * root.u
                opacity: root.inT * (root.pw === "" && root.phase === "idle" ? 0.55 : 1)
                property real shake: 0
                property real okT: 0
                function fail() { shakeAnim.restart() }
                function ok() { okAnim.restart() }
                NumberAnimation { id: shakeAnim; target: field; property: "shake"; from: 0; to: 1; duration: 460 }
                NumberAnimation { id: okAnim; target: field; property: "okT"; from: 0; to: 1; duration: 120; easing.type: Easing.OutQuad }
                Item {
                    anchors.fill: parent
                    transform: Translate { x: 12 * root.u * Math.sin(field.shake * Math.PI * 5) * (1 - field.shake) }
                    Row {
                        anchors.centerIn: parent
                        spacing: 12 * root.u
                        Repeater {
                            model: Math.min(root.pw.length, 24)
                            Rectangle {
                                width: 8 * root.u; height: width; rotation: 45
                                anchors.verticalCenter: parent.verticalCenter
                                color: root.light
                                opacity: root.phase === "verifying" ? 0.45 : 1
                                scale: 1 + 0.35 * field.okT
                            }
                        }
                        Rectangle {   // caret
                            visible: root.phase !== "verifying" && root.phase !== "authorized"
                            width: 8 * root.u; height: width; rotation: 45
                            anchors.verticalCenter: parent.verticalCenter
                            color: "transparent"; border.color: root.light; border.width: 1
                            opacity: root.blink
                        }
                        Text {
                            visible: root.pw === "" && root.phase === "idle"
                            anchors.verticalCenter: parent.verticalCenter
                            text: "TYPE TO LOG IN"
                            font.family: root.voidFont; font.weight: root.voidWeight
                            font.pixelSize: Math.round(root.step(0)); font.letterSpacing: 0.3 * root.step(0)
                            color: root.alpha(root.light, 0.4)
                        }
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom; width: parent.width; height: 1
                        color: root.phase === "failed" ? root.warn : root.alpha(root.light, 0.4)
                    }
                }
            }
            Item { width: 1; height: 16 * root.u }
            Text {   // caps lock · failures · a power key waiting for its second press
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: root.inT
                readonly property bool caps: typeof keyboard !== "undefined" && keyboard.capsLock
                text: root.armed === "reboot" ? "PRESS F11 AGAIN TO RESTART"
                    : root.armed === "poweroff" ? "PRESS F12 AGAIN TO SHUT DOWN"
                    : caps ? "CAPS LOCK ON"
                    : root.fails > 0 ? root.fails + " FAILED ATTEMPT" + (root.fails > 1 ? "S" : "") : " "
                font.family: root.voidFont; font.weight: root.voidWeight
                font.pixelSize: Math.round(root.step(0)); font.letterSpacing: 0.3 * root.step(0)
                color: root.armed !== "" || caps ? root.light : root.warn
            }
        }

        // ── the session and the keys, low on the screen ──
        Column {
            visible: root.primary
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: parent.height * 0.06
            spacing: 18 * root.u
            opacity: 0.8 * root.inT
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12 * root.u
                Text { text: "SESSION"; font.family: root.voidFont; font.weight: root.voidWeight; font.pixelSize: Math.round(root.step(0)); font.letterSpacing: 0.3 * root.step(0); color: root.alpha(root.light, 0.45) }
                Text { text: root.sessionName.toUpperCase(); font.family: root.voidFont; font.weight: root.voidWeight; font.pixelSize: Math.round(root.step(0)); font.letterSpacing: 0.3 * root.step(0); color: root.light }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 18 * root.u
                Repeater {
                    model: [["↵", "LOG IN"]].concat(root.users.length > 1 ? [["←→", "USER"]] : [])
                                            .concat(root.sessions.length > 1 ? [["↑↓", "SESSION"]] : [])
                                            .concat([["F11", "RESTART"], ["F12", "SHUT DOWN"]])
                    Row {
                        spacing: 6 * root.u
                        Rectangle {
                            width: kk.implicitWidth + root.step(0) * 0.7; height: root.step(0) * 1.5
                            color: "transparent"; border.color: root.alpha(root.light, 0.35); border.width: 1
                            Text { id: kk; anchors.centerIn: parent; text: modelData[0]; font.family: root.voidFont; font.weight: root.voidWeight; font.pixelSize: Math.round(root.step(0) * 0.85); color: root.light }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1]; font.family: root.voidFont; font.weight: root.voidWeight
                            font.pixelSize: Math.round(root.step(0)); font.letterSpacing: 0.26 * root.step(0)
                            color: root.alpha(root.light, 0.55)
                        }
                    }
                }
            }
        }
    }
}
