#!/bin/sh
# Lightweight BlueZ status for the Quickshell bar.
#
# Replaces the old `bluetoothctl show / bluetoothctl devices` polling. Each
# `bluetoothctl` invocation registered a BlueZ *advertisement monitor* on the
# system D-Bus and then disconnected; running it every 6-8s flooded the bus
# (~2,000,000 connections over ~9 days) and intermittently reset other apps'
# D-Bus connections — notably VS Code, which aborts at window creation when its
# D-Bus connection drops.
#
# `busctl get-property` is a plain property read: no advertisement monitor, no
# scan, clean connect/disconnect. Output format is kept byte-compatible with the
# old command so the QML parsers (TopBar.qml / services/Net.qml) need no change:
#   Powered: yes|no
#   Device <MAC> <Name>      (only when a device is connected)
B="busctl --system"

ADAPTER=$($B tree org.bluez 2>/dev/null | grep -oE '/org/bluez/hci[0-9]+' | sort -u | head -1)
[ -z "$ADAPTER" ] && { echo "Powered: no"; exit 0; }

powered=$($B get-property org.bluez "$ADAPTER" org.bluez.Adapter1 Powered 2>/dev/null)
case "$powered" in
  *true*) echo "Powered: yes" ;;
  *)      echo "Powered: no"; exit 0 ;;
esac

# Powered on: print the first connected device as "Device <MAC> <Name>".
for d in $($B tree org.bluez 2>/dev/null | grep -oE "$ADAPTER/dev_[0-9A-F_]+"); do
  case "$($B get-property org.bluez "$d" org.bluez.Device1 Connected 2>/dev/null)" in
    *true*)
      name=$($B get-property org.bluez "$d" org.bluez.Device1 Alias 2>/dev/null | sed -E 's/^s "//; s/"$//')
      mac=$(printf '%s' "$d" | sed -E 's#.*/dev_##; s/_/:/g')
      echo "Device $mac $name"
      break ;;
  esac
done
