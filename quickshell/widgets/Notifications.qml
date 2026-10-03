// notifications.qml
// Daemon de notifications style NieR / YoRHa
//
// Installation :
//   1. Tuer tout autre daemon : pkill dunst; pkill mako; pkill swaync
//   2. qs -p notifications.qml
//
// Tests :
//   notify-send "Test" "Ceci est une notification"
//   notify-send -u critical "ATTENTION" "Niveau critique"
//   notify-send -u low "Info" "Niveau bas"

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
import "../components"
import "../services"
import "../theme"
import "../settings"

Scope {
    id: root

    readonly property int topOffsetPercent: 6
    readonly property int leftMargin: 24
    readonly property int notifWidth: 360
    readonly property int notifSpacing: 10
    readonly property int defaultTimeout: Settings.notifyTimeout
    readonly property int criticalTimeout: Settings.notifyCriticalTimeout

    NotificationServer {
        id: notifServer

        actionsSupported: true
        bodyMarkupSupported: true
        bodyImagesSupported: true
        bodyHyperlinksSupported: false
        imageSupported: true
        keepOnReload: true

        onNotification: (n) => {
            Notifs.restore()
            // Carried over a reload: it already popped up once — relink its history
            // entry (actions work again) and keep it quiet
            if (n.lastGeneration) {
                root._quiet[n.id] = true
                n.tracked = true
                if (Notifs.relink(n)) return
            } else {
                if (Notifs.dndEnabled) root._quiet[n.id] = true   // DND: into the history, no popup
                n.tracked = true
            }

            // Récupérer les actions sous forme de noms (pour l'affichage)
            var actionNames = []
            try {
                if (n.actions) {
                    for (var ai = 0; ai < n.actions.length; ai++) {
                        var a = n.actions[ai]
                        actionNames.push({
                            id: a.identifier || "",
                            text: a.text || ""
                        })
                    }
                }
            } catch(e) {}

            // Hints / catégorie / urgency level
            var urgencyLabel = "normal"
            if (n.urgency === 0) urgencyLabel = "low"
            else if (n.urgency === 2) urgencyLabel = "critical"

            // Ajouter à l'historique (FIFO 50)
            var entry = {
                id: n.id,
                summary: n.summary || "",
                body: n.body || "",
                app: n.appName || "",
                appIcon: n.appIcon || "",
                category: n.category || "",
                urgency: urgencyLabel,
                timeout: n.expireTimeout >= 0 ? n.expireTimeout : -1,
                desktopEntry: n.desktopEntry || "",
                hasImage: n.hasImage || false,
                actions: actionNames,
                ts: Date.now(),
                ref: null
            }
            Notifs.add(entry, n)    // the shared history (services/Notifs.qml)
        }
    }

    readonly property var tracked: notifServer.trackedNotifications

    property var _quiet: ({})          // ids that arrive without a popup (DND, reload carry-over)

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property ShellScreen modelData
            screen: modelData

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "notifications"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.exclusionMode: ExclusionMode.Ignore

            anchors {
                top: true
                left: true
                bottom: true
            }
            implicitWidth: root.notifWidth + root.leftMargin + 160   // + room for the confirm burst
            color: "transparent"

            // ═══════════════════════════════════════════════════════════
            // MASQUE D'INPUT : ne capture les clics QUE dans la zone
            // qui entoure la pile de notifs. Quand il n'y en a aucune,
            // la région fait 0x0 → tout passe à travers.
            // ═══════════════════════════════════════════════════════════
            mask: Region {
                x: column.x
                y: column.y
                width: notifRepeater.count > 0 ? root.notifWidth : 0
                height: {
                    // Dépendance explicite pour forcer le recalcul
                    column.layoutTrigger;
                    let h = 0;
                    for (let i = 0; i < column.children.length; i++) {
                        const c = column.children[i];
                        if (c && c.isNotifItem === true && c.height > 0) {
                            h += c.height + root.notifSpacing;
                        }
                    }
                    return Math.max(0, h - root.notifSpacing);
                }
            }

            Item {
                id: column
                anchors.left: parent.left
                anchors.leftMargin: root.leftMargin
                anchors.top: parent.top
                anchors.topMargin: parent.height * root.topOffsetPercent / 100
                width: root.notifWidth
                height: parent.height - anchors.topMargin

                // Trigger pour forcer la re-évaluation du mask de la fenêtre
                property int layoutTrigger: 0

                // confirm impact (components/HitBurst.qml), drawn over the cards
                HitBurst { id: popBurst; z: 100 }

                Repeater {
                    id: notifRepeater
                    model: root.tracked

                    onItemAdded: column.layoutTrigger++
                    onItemRemoved: column.layoutTrigger++

                    delegate: NotifItem {
                        required property var modelData
                        required property int index

                        notification: modelData
                        width: root.notifWidth
                        itemIndex: index
                        burst: popBurst

                        onHeightChanged: column.layoutTrigger++
                    }
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════
    // Composant notif — animation deux phases (rideau yorha-dots)
    // ════════════════════════════════════════════════════════════════
    component NotifItem: Item {
        id: notif

        property var notification: null
        property int itemIndex: 0
        property var burst: null          // the window's HitBurst
        // a timed-out popup is only shelved: hidden and out of the stack, while its
        // Notification stays open for the ControlCenter history
        property bool _shelved: false
        readonly property bool isNotifItem: !_shelved
        visible: !_shelved

        readonly property int urgency: notification ? notification.urgency : 1

        // Couleurs vives façon yorha-dots dark ($accent / $accent2 / $brown)
        readonly property color accentColor: {
            if (urgency === 2) return Theme.urgent;   // critical — orange-rouge
            if (urgency === 0) return Theme.calm;   // low      — vert
            return Theme.ink;                       // normal   — encre sombre
        }

        readonly property string urgencyLabel: {
            if (urgency === 2) return "CRITICAL";
            if (urgency === 0) return "INFO";
            return "NOTICE";
        }
        readonly property string urgencyJp: {
            if (urgency === 2) return "緊急";
            if (urgency === 0) return "情報";
            return "通知";
        }

        // Flags d'état
        property bool _entering: false
        property bool _closing:  false

        // Position Y empilée
        y: {
            let acc = 0;
            const p = parent;
            if (!p) return 0;
            for (let i = 0; i < p.children.length; i++) {
                const c = p.children[i];
                if (c === notif) break;
                if (c && c.isNotifItem === true) acc += c.height + root.notifSpacing;
            }
            return acc;
        }
        Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

        // Hauteur — collapsible
        property real heightFactor: 1.0
        height: card.implicitHeight * heightFactor
        width: root.notifWidth
        clip: _closing || heightFactor < 1   // coupe card + hider pendant l'effondrement (not during the hit pop)

        // ── Carte ──────────────────────────────────────────────────
        Rectangle {
            id: card
            anchors.left: parent.left
            width: parent.width
            implicitHeight: contentCol.implicitHeight + 12
            height: implicitHeight
            color: Theme.paper
            border.color: Theme.ink; border.width: 1
            opacity: 0.0   // invisible jusqu'à la phase 2 du rideau
            scale: 1 + 0.03 * notif.hitT
            transform: Translate { id: cardShift }

            Rectangle {   // hit-stop flash
                anchors.fill: parent; z: 5
                color: Theme.light; opacity: 0.45 * notif.hitT
            }

            // Barre d'accentuation gauche — animée large→fine à l'entrée
            Rectangle {
                id: accentBar
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: 3
                color: notif.accentColor
            }

            // Scan-line post-entrée
            Rectangle {
                id: scanLine
                property real prog: 0
                x: prog * parent.width - 40; y: 0
                width: 80; height: parent.height
                opacity: prog > 0 && prog < 1 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 80 } }
                z: 2; clip: true
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: Theme.alpha(Theme.urgent, 0.28) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // Grille décorative
            Canvas {
                anchors.fill: parent; anchors.leftMargin: 3
                opacity: 0.18; z: 0
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.strokeStyle = "rgba(70,63,46,0.25)"; ctx.lineWidth = 1;
                    for (let x = 0; x < width;  x += 16) { ctx.beginPath(); ctx.moveTo(x,0); ctx.lineTo(x,height); ctx.stroke(); }
                    for (let y = 0; y < height; y += 16) { ctx.beginPath(); ctx.moveTo(0,y); ctx.lineTo(width,y);  ctx.stroke(); }
                }
            }

            ColumnLayout {
                id: contentCol
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.leftMargin: 14; anchors.rightMargin: 12; anchors.topMargin: 10
                spacing: 6; z: 1

                // ── En-tête ────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true; spacing: 8

                    Rectangle {
                        Layout.preferredWidth: urgLabel.implicitWidth + 10
                        Layout.preferredHeight: 14
                        color: notif.accentColor
                        Text {
                            id: urgLabel; anchors.centerIn: parent
                            text: notif.urgencyLabel; color: Theme.paper
                            font.family: Theme.mono; font.pixelSize: Theme.fs(8)
                            font.weight: Font.Medium; font.letterSpacing: 2
                        }
                    }
                    Text { text: notif.urgencyJp; color: Theme.inkSoft; font.family: Theme.cjk; font.pixelSize: Theme.fs(9) }
                    Text {
                        Layout.fillWidth: true
                        text: notif.notification ? (notif.notification.appName || "SYSTEM").toUpperCase() : "SYSTEM"
                        color: Theme.inkSoft; font.family: Theme.mono; font.pixelSize: Theme.fs(8)
                        font.letterSpacing: 2; elide: Text.ElideRight
                    }
                    Text {
                        text: { const d=new Date(),p=n=>String(n).padStart(2,'0'); return `${p(d.getHours())}:${p(d.getMinutes())}` }
                        color: Theme.inkSoft; font.family: Theme.mono; font.pixelSize: Theme.fs(8); font.letterSpacing: 1
                    }

                    // Bouton fermer — zone de clic élargie
                    Item {
                        id: closeBtn
                        Layout.preferredWidth: 28; Layout.preferredHeight: 24
                        Layout.alignment: Qt.AlignVCenter
                        Rectangle {
                            anchors.centerIn: parent; width: 18; height: 16
                            color: closeMouse.containsMouse ? notif.accentColor : "transparent"
                            border.color: Theme.ink; border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                anchors.centerIn: parent; text: "✕"
                                color: closeMouse.containsMouse ? Theme.paper : Theme.ink
                                font.family: Theme.mono; font.pixelSize: Theme.fs(9)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                        }
                        MouseArea {
                            id: closeMouse; anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: notif._hit(closeBtn, closeBtn.width / 2, closeBtn.height / 2, 0.5, notif._doClose)
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.ink; opacity: 0.2 }

                // ── Contenu image + texte ──────────────────────────
                RowLayout {
                    Layout.fillWidth: true; spacing: 12

                    Item {
                        id: imageWrap
                        Layout.preferredWidth: 64; Layout.preferredHeight: 64
                        Layout.alignment: Qt.AlignTop
                        readonly property string imageSource: {
                            if (!notif.notification) return "";
                            const img = notif.notification.image || "";
                            if (img.length > 0) return img;
                            const ic = notif.notification.appIcon || "";
                            if (ic.length > 0) {
                                if (ic.startsWith("/") || ic.startsWith("file://")) return ic;
                                return Quickshell.iconPath(ic, true);
                            }
                            return "";
                        }
                        visible: imageSource.length > 0
                        Rectangle { anchors.fill: parent; color: "transparent"; border.color: Theme.ink; border.width: 1 }
                        Rectangle {
                            anchors.top: parent.top; anchors.left: parent.left
                            width: 14; height: 10; color: notif.accentColor; z: 2
                            Text { anchors.centerIn: parent; text: String(notif.itemIndex+1).padStart(2,'0')
                                color: Theme.paper; font.family: Theme.mono; font.pixelSize: Theme.fs(7) }
                        }
                        Image {
                            anchors.fill: parent; anchors.margins: 2
                            source: imageWrap.imageSource; fillMode: Image.PreserveAspectCrop
                            asynchronous: true; cache: true
                            sourceSize.width: 128; sourceSize.height: 128
                            smooth: true; visible: status === Image.Ready
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true; Layout.alignment: Qt.AlignTop; spacing: 4
                        Text {
                            Layout.fillWidth: true
                            text: notif.notification ? notif.notification.summary : ""
                            color: Theme.inkStrong; font.family: Theme.mono; font.pixelSize: Theme.fs(13)
                            font.weight: Font.Medium; font.letterSpacing: 0.8
                            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                            visible: text.length > 0
                        }
                        Text {
                            Layout.fillWidth: true
                            text: notif.notification ? notif.notification.body : ""
                            color: Theme.ink; font.family: Theme.mono; font.pixelSize: Theme.fs(11)
                            font.weight: Font.Light; font.letterSpacing: 0.3
                            wrapMode: Text.WordWrap; maximumLineCount: 4; elide: Text.ElideRight
                            textFormat: Text.PlainText; visible: text.length > 0; lineHeight: 1.4
                        }
                    }
                }

                // ── Actions — hauteur augmentée (28px) + marges ────
                RowLayout {
                    id: actionsRow
                    Layout.fillWidth: true; Layout.topMargin: 4
                    spacing: 8; visible: actionRepeater.count > 0
                    Repeater {
                        id: actionRepeater
                        model: notif.notification ? notif.notification.actions : null
                        delegate: Rectangle {
                            id: actBtn
                            required property var modelData
                            Layout.preferredHeight: 28
                            Layout.preferredWidth: actionText.implicitWidth + 24
                            color: actMouse.containsMouse ? Theme.ink : "transparent"
                            border.color: Theme.ink; border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                id: actionText; anchors.centerIn: parent
                                text: `▸ ${(modelData && modelData.text ? modelData.text : "").toUpperCase()}`
                                color: actMouse.containsMouse ? Theme.paper : Theme.ink
                                font.family: Theme.mono; font.pixelSize: Theme.fs(9); font.letterSpacing: 1.5
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            MouseArea {
                                id: actMouse
                                // Zone de clic plus grande que le rectangle visible
                                anchors { fill: parent; margins: -6 }
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var act = modelData
                                    notif._hit(actBtn, 10, actBtn.height / 2, 1.0, function() { notif._run(act) })
                                }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 4 }
            }

            // Barre de progression timeout
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                anchors.leftMargin: 3; height: 1; color: notif.accentColor; opacity: 0.3; z: 1
                Rectangle {
                    id: progressBar
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: parent.width; color: notif.accentColor
                    NumberAnimation on width {
                        from: progressBar.parent.width; to: 0
                        duration: closeTimer.interval
                        running: !notif._entering && !notif._closing
                    }
                }
            }
        } // card

        // ── Rideau (hider) — couleur papier, glisse R→C→G ──────────
        Rectangle {
            id: hider
            anchors.top: parent.top
            width: parent.width
            height: card.implicitHeight   // hauteur fixe, ne s'effondre pas avec notif
            x: parent.width               // part hors cadre à droite
            color: Theme.paper
            border.color: Theme.ink; border.width: 1
            z: 10; visible: false
        }

        // ── Interaction souris — survol + glisser-rejeter ──────────
        MouseArea {
            id: bodyMA
            anchors.fill: parent
            z: 1
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            propagateComposedEvents: true

            property real _px: 0   // X au moment du press

            onEntered: closeTimer.stop()
            onExited:  { if (!notif._entering && !notif._closing) closeTimer.restart() }

            function _over(item, m) {
                if (!item || !item.visible) return false
                var p = mapToItem(item, m.x, m.y)
                return p.x >= 0 && p.y >= 0 && p.x <= item.width && p.y <= item.height
            }
            onPressed: (m) => {
                _px = m.x
                // Laisser les boutons (✕, actions) traiter leurs événements
                if (m.button === Qt.LeftButton && (_over(closeBtn, m) || _over(actionsRow, m))) m.accepted = false
            }
            onPositionChanged: (m) => {
                if (!pressed) return
                const dx = m.x - _px
                if (dx > 0 && !notif._closing) {
                    // Formule yorha-dots : expansion exponentielle de la barre d'accent
                    accentBar.width = 3 + 100*(1 - Math.pow(Math.E, -dx/100)) + dx/100
                }
            }
            onReleased: (m) => {
                const dx = m.x - _px
                if (dx > 160 && !notif._closing) {
                    notif._hit(bodyMA, m.x, m.y, 0.5, notif._doClose)
                } else if (dx > 0) {
                    accentResetAnim.restart()
                }
            }
            onClicked: (m) => {
                if (Math.abs(m.x - _px) > 6) return
                if (m.button === Qt.MiddleButton || m.button === Qt.RightButton)
                    notif._hit(bodyMA, m.x, m.y, 0.5, notif._doClose)
                else   // left: open it (its default action) if it offers one, else close it
                    notif._hit(bodyMA, m.x, m.y, notif._defaultAction() ? 1.0 : 0.5,
                               function() { var a = notif._defaultAction(); if (a) notif._run(a); else notif._doClose() })
            }
        }

        // ── Timer auto-dismiss ─────────────────────────────────────
        Timer {
            id: closeTimer; running: false; repeat: false
            interval: {
                if (!notif.notification) return root.defaultTimeout;
                const t = notif.notification.expireTimeout;
                if (t <= 0) return notif.urgency === 2 ? root.criticalTimeout : root.defaultTimeout;
                return t;
            }
            onTriggered: {
                if (notif.notification && notif.notification.transient) notif._doClose()
                else notif._shelve()
            }
        }

        // ── Animations ─────────────────────────────────────────────

        // Barre d'accent : rebond après glissement annulé
        NumberAnimation {
            id: accentResetAnim
            target: accentBar; property: "width"; to: 3
            duration: 220; easing.type: Easing.OutExpo
        }
        // Barre d'accent : large → fine après entrée
        NumberAnimation {
            id: accentSettleAnim
            target: accentBar; property: "width"; to: 3
            duration: 250; easing { type: Easing.OutBack; overshoot: 1.2 }
        }

        // ENTRÉE : rideau entre de droite (couvre) → sort à gauche (révèle)
        SequentialAnimation {
            id: enterAnim
            ScriptAction { script: {
                notif._entering = true
                hider.x = notif.width; hider.visible = true
                accentBar.width = 3
            }}
            // Phase 1 — rideau glisse de droite vers centre (300ms OutExpo)
            NumberAnimation {
                target: hider; property: "x"; to: 0
                duration: 300; easing.type: Easing.OutExpo
            }
            // Carte apparaît, barre d'accent flash large
            ScriptAction { script: { card.opacity = 1; accentBar.width = 50 } }
            // Phase 2 — rideau glisse vers la gauche avec léger overshoot (300ms OutBack)
            NumberAnimation {
                target: hider; property: "x"; to: -notif.width
                duration: 300; easing { type: Easing.OutBack; overshoot: 0.6 }
            }
            // Fin d'entrée
            ScriptAction { script: {
                hider.visible = false
                accentSettleAnim.restart()
                scanAnim.restart()
                notif._entering = false
                closeTimer.restart()
            }}
        }

        // Scan-line post-entrée
        SequentialAnimation {
            id: scanAnim
            NumberAnimation { target: scanLine; property: "prog"; from: 0; to: 1; duration: 500; easing.type: Easing.OutQuad }
            ScriptAction { script: scanLine.prog = 0 }
        }

        // SORTIE : rideau recouvre → effondrement
        SequentialAnimation {
            id: exitAnim
            ScriptAction { script: { hider.x = notif.width; hider.visible = true } }
            // Phase 1 — rideau recouvre la carte (280ms InOutQuart)
            NumberAnimation {
                target: hider; property: "x"; to: 0
                duration: 280; easing.type: Easing.InOutQuart
            }
            // Effacer la carte derrière le rideau
            ScriptAction { script: { card.opacity = 0; hider.visible = false } }
            // Phase 2 — effondrement de l'espace (200ms)
            NumberAnimation {
                target: notif; property: "heightFactor"; to: 0
                duration: 200; easing.type: Easing.OutCubic
            }
            ScriptAction { script: {
                if (notif._shelving) notif._shelved = true
                else if (notif.notification) notif.notification.dismiss()
            } }
        }

        // ── Hit (as the ControlCenter): the card pops and flashes for a beat while the
        // burst flies, then `after` runs ──
        property real hitT: 0
        property var  _after: null
        SequentialAnimation {
            id: hitAnim
            NumberAnimation { target: notif; property: "hitT"; from: 0; to: 1; duration: 45; easing.type: Easing.OutQuad }
            PauseAnimation { duration: 65 }
            ScriptAction { script: { var f = notif._after; notif._after = null; if (f) f() } }
            NumberAnimation { target: notif; property: "hitT"; to: 0; duration: 200; easing.type: Easing.OutCubic }
        }
        function _hit(item, ix, iy, strength, after) {
            if (_closing || hitAnim.running) return
            closeTimer.stop()
            if (burst) burst.playAt(item, ix, iy, strength)
            _after = after
            hitAnim.restart()
        }
        function _defaultAction() {
            var acts = notification ? notification.actions : null
            if (!acts || acts.length === 0) return null
            for (var i = 0; i < acts.length; i++) if (acts[i].identifier === "default") return acts[i]
            return acts[0]
        }
        // Run an action. Quickshell closes a non-resident notification the moment its
        // action is invoked, which destroys this row on the spot — so the card cuts out
        // first (~0.13 s) and the invoke is the very last thing this row does.
        property var _pendingAct: null
        function _run(act) {
            _closing = true; closeTimer.stop()
            _pendingAct = act
            cutAnim.start()
        }
        SequentialAnimation {
            id: cutAnim
            ParallelAnimation {
                NumberAnimation { target: card; property: "opacity"; to: 0; duration: 130; easing.type: Easing.InQuad }
                NumberAnimation { target: cardShift; property: "x"; to: 28; duration: 130; easing.type: Easing.InCubic }
            }
            ScriptAction { script: {
                var a = notif._pendingAct; notif._pendingAct = null
                // resident: it stays open after its action; only the popup goes
                if (notif.notification && notif.notification.resident) { notif.heightFactor = 0; notif._shelved = true }
                try { a.invoke() } catch (e) {}
            } }
        }

        property bool _shelving: false
        function _shelve() {
            if (_closing) return
            _shelving = true
            _doClose()
        }

        function _doClose() {
            if (_closing) return
            _closing = true
            closeTimer.stop()
            enterAnim.stop()
            accentSettleAnim.stop()
            accentResetAnim.stop()
            exitAnim.start()
        }

        Component.onCompleted: {
            // DND / carried over a reload: straight to the history, no popup
            if (notification && root._quiet[notification.id]) {
                delete root._quiet[notification.id]
                _closing = true; _shelving = true; heightFactor = 0; _shelved = true
                return
            }
            Qt.callLater(() => enterAnim.start())
        }
    }
}