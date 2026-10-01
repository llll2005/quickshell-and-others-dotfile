pragma Singleton
import QtQuick
import Quickshell

// Ime — the current fcitx5 input method, as reported by the kimpanel bridge
// (scripts/imepanel.py via widgets/ImePanel.qml). switched() fires on a real
// change (not on the repeats fcitx5 sends on every focus change).
Singleton {
    property string name: ""       // e.g. 小麥注音 / Keyboard - English (US)
    property string label: ""      // short form, e.g. 麥 / en
    signal switched()
}
