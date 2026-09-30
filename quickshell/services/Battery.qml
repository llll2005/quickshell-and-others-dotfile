pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower

// Battery — native UPower display device. `available` is false on desktops (no
// laptop battery), so consumers can hide the indicator entirely.
QtObject {
    id: root

    readonly property var  dev:       UPower.displayDevice
    readonly property bool available: dev !== null && dev.isLaptopBattery
    // Quickshell reports percentage as a 0–1 fraction → expose 0–100.
    readonly property real percent:   dev ? dev.percentage * 100 : 0
    // UPowerDeviceState: 1 Charging, 2 Discharging, 4 FullyCharged, 5 PendingCharge.
    // Treat anything that isn't actively discharging as "on AC" (⚡).
    readonly property bool charging:  dev ? (dev.state === 1 || dev.state === 4 || dev.state === 5) : false
}
