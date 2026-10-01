pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../settings"

// Notifs — the notification history, shared in-process by the popups
// (widgets/Notifications.qml, which owns the NotificationServer) and the Control
// Center. The Control Center used to read it by spawning `qs ipc call notifs
// getHistory` every 1.5 s; now it binds to `history` / `revision` directly.
//
// A popup that times out only hides: its Notification stays tracked (its sender
// still listening) until it's dismissed — from the popup, the Control Center, or by
// falling off the end of the history — so its actions can still run later. An
// entry's `ref` is nulled when its Notification closes (`revision` bumps then).
//
// The history (minus the live objects) and DND survive a config reload; entries
// whose notifications are still open are relinked as those are carried over.
Singleton {
    id: root

    property var  history: []          // newest first: {id, summary, body, app, …, ts, ref}
    property bool dndEnabled: false
    property int  revision: 0          // bumps when an entry's Notification closes

    function keyOf(h) { return h.id + "@" + h.ts }
    // its sender still listens (the Notification object is alive) and offers an action
    function canOpen(h) {
        try { return !!(h.ref && h.ref.actions && h.ref.actions.length > 0) } catch (e) { return false }
    }
    // plain copies with `key` / `live`, for lists that compare snapshots
    function snapshot() {
        var out = []
        for (var i = 0; i < history.length; i++) {
            var h = history[i]
            out.push({
                id: h.id, summary: h.summary, body: h.body, app: h.app,
                appIcon: h.appIcon || "", category: h.category || "", urgency: h.urgency || "normal",
                timeout: h.timeout >= 0 ? h.timeout : -1, desktopEntry: h.desktopEntry || "",
                hasImage: h.hasImage || false, actions: h.actions || [], ts: h.ts,
                key: keyOf(h), live: canOpen(h)
            })
        }
        return out
    }

    function link(entry, n) {
        entry.ref = n
        // once it closes (dismissed, expired, its sender) it can't be opened or closed again
        try { n.closed.connect(function() { entry.ref = null; root.revision++ }) } catch (e) {}
    }
    // a new notification arrives (Notifications.qml); FIFO: what falls off is closed for good
    function add(entry, n) {
        link(entry, n)
        var list = history.slice()
        list.unshift(entry)
        while (list.length > Settings.notifyHistory) {
            var old = list.pop()
            if (old.ref) { try { old.ref.dismiss() } catch (e) {} }
        }
        history = list
    }
    // carried over a reload: relink its entry (actions work again); false = not in the history
    function relink(n) {
        restore()
        for (var i = 0; i < history.length; i++)
            if (history[i].id === n.id && !history[i].ref) { link(history[i], n); revision++; return true }
        return false
    }
    // dismiss, or run its default action (invoke) — by key id@ts, never by index
    function removeKey(key, invoke) {
        for (var i = 0; i < history.length; i++) {
            var h = history[i]
            if (keyOf(h) !== key) continue
            if (h.ref) {
                try {
                    if (invoke && h.ref.actions && h.ref.actions.length > 0) {
                        var act = h.ref.actions[0]
                        for (var k = 0; k < h.ref.actions.length; k++)
                            if (h.ref.actions[k].identifier === "default") { act = h.ref.actions[k]; break }
                        var resident = h.ref.resident
                        act.invoke()                             // closes it unless it's resident…
                        if (resident && h.ref) h.ref.dismiss()   // …which we close too: it leaves the history
                    } else {
                        h.ref.dismiss()
                    }
                } catch (e) {}
            }
            var list = history.slice()
            list.splice(i, 1)
            history = list
            return
        }
    }
    function clearAll() {
        for (var i = 0; i < history.length; i++) {
            var h = history[i]
            if (h.ref) { try { h.ref.dismiss() } catch (e) {} }
        }
        history = []
    }

    PersistentProperties {
        id: persist
        reloadableId: "nierNotifHistory"
        property string json: "[]"
        property bool   dnd: false
        onLoaded: root.restore()
    }
    property bool _restored: false
    function restore() {
        if (_restored) return
        _restored = true
        dndEnabled = persist.dnd
        if (history.length > 0) return
        try {
            var list = JSON.parse(persist.json || "[]")
            for (var i = 0; i < list.length; i++) list[i].ref = null
            history = list
        } catch (e) {}
    }
    onHistoryChanged: if (_restored) persist.json = JSON.stringify(history, function(k, v) { return k === "ref" ? undefined : v })
    onDndEnabledChanged: if (_restored) persist.dnd = dndEnabled

    // ── CLI: qs ipc call notifs … ──
    IpcHandler {
        target: "notifs"
        function getHistory(): string { return JSON.stringify(root.snapshot()) }
        function getCount(): int { return root.history.length }
        function dismissKey(key: string): void { root.removeKey(key, false) }
        function invokeKey(key: string): void  { root.removeKey(key, true) }
        function clearAll(): void { root.clearAll() }
        function setDnd(state: bool): void { root.dndEnabled = state }
        function getDnd(): bool { return root.dndEnabled }
        function toggleDnd(): bool { root.dndEnabled = !root.dndEnabled; return root.dndEnabled }
    }
}
