pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth

// Net — shared network state (Wi-Fi / Ethernet / Bluetooth) for CornerHud, straight
// from NetworkManager and BlueZ through Quickshell's native modules: every value
// below is a binding that updates on their D-Bus signals — nothing polls.
//
// It used to spawn scripts/netinfo.sh every 5 s, a busctl-based BT script every 8 s
// and an upower pipeline for the BT battery, plus a resident `nmcli monitor`: ~250
// short-lived processes a minute. The only thing the native modules don't expose
// is the IP address; that's one `ip -j addr` when the connection changes (and once a
// minute in case DHCP moves it).
QtObject {
    id: root

    // ── Wi-Fi ──
    readonly property var wifiDev: {
        var ds = Networking.devices.values
        for (var i = 0; i < ds.length; i++) if (ds[i] && ds[i].type === DeviceType.Wifi) return ds[i]
        return null
    }
    readonly property var wifiNet: {
        var ns = wifiDev ? wifiDev.networks.values : []
        for (var i = 0; i < ns.length; i++) if (ns[i] && ns[i].connected) return ns[i]
        return null
    }
    readonly property bool   wifiOn:   wifiNet !== null
    readonly property string wifiSSID: wifiNet ? wifiNet.name : ""
    readonly property int    wifiSig:  wifiNet ? Math.round(Math.min(1, wifiNet.signalStrength) * 100) : 0   // 0-100
    property string          wifiIP:   ""

    // ── Ethernet (NM's wired devices only: docker/veth/bridges aren't listed) ──
    readonly property var ethDev: {
        var ds = Networking.devices.values
        for (var i = 0; i < ds.length; i++) if (ds[i] && ds[i].type === DeviceType.Wired && ds[i].connected) return ds[i]
        return null
    }
    readonly property bool   ethOn:   ethDev !== null
    readonly property string ethName: ethDev ? ethDev.name : ""
    property string          ethIP:   ""

    // ── Bluetooth ──
    readonly property var  btAdapter: Bluetooth.defaultAdapter
    readonly property bool btOn: btAdapter ? btAdapter.enabled : false
    readonly property var  btConn: {
        var ds = btAdapter ? btAdapter.devices.values : []
        for (var i = 0; i < ds.length; i++) if (ds[i] && ds[i].connected) return ds[i]
        return null
    }
    readonly property string btDev: btConn ? (btConn.name || btConn.deviceName || btConn.address) : ""
    readonly property string btBat: btConn && btConn.batteryAvailable ? Math.round(btConn.battery * 100) + "%" : ""

    // ── IP addresses: read when the link changes ──
    readonly property string linkKey:  (wifiDev ? wifiDev.name : "") + "|" + wifiSSID + "|" + ethName
    onLinkKeyChanged: _ipDebounce.restart()
    property Timer _ipDebounce: Timer { interval: 1500; onTriggered: root._ipP.running = true }   // DHCP needs a moment
    property Timer _ipSlow: Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root._ipP.running = true }
    property Process _ipP: Process {
        running: false
        command: ["ip", "-j", "-4", "addr", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                var map = ({})
                try {
                    var ifs = JSON.parse(this.text || "[]")
                    for (var i = 0; i < ifs.length; i++) {
                        var a = ifs[i].addr_info || []
                        if (a.length) map[ifs[i].ifname] = a[0].local
                    }
                } catch (e) {}
                root.wifiIP = root.wifiOn && root.wifiDev ? (map[root.wifiDev.name] || "") : ""
                root.ethIP  = root.ethOn ? (map[root.ethName] || "") : ""
            }
        }
    }
}
