#!/bin/sh
# Emit 5 lines: wifiSSID, wifiSignal, wifiIP, ethDevice, ethIP
# Ethernet ignores virtual interfaces (docker/veth/bridge/vpn/loopback).
# One `nmcli dev` call feeds all three device lookups (CONNECTION last + -e no,
# so SSIDs containing ':' survive). `--rescan no`: without it every poll forces
# a Wi-Fi scan once the AP list is >30 s old; NM still refreshes the in-use
# AP's signal by itself every few seconds.
dev=$(nmcli -t -e no -f TYPE,STATE,DEVICE,CONNECTION dev 2>/dev/null)
ssid=$(printf '%s\n' "$dev" | awk -F: '$1=="wifi"&&$2=="connected"{sub(/^[^:]*:[^:]*:[^:]*:/,"");print;exit}')
sig=$(nmcli -t -f IN-USE,SIGNAL dev wifi list --rescan no 2>/dev/null | awk -F: '/^\*/{print $2;exit}')
wdev=$(printf '%s\n' "$dev" | awk -F: '$1=="wifi"&&$2=="connected"{print $3;exit}')
wip=$(ip -br addr show "$wdev" 2>/dev/null | awk '{print $3}' | cut -d/ -f1)
edev=$(printf '%s\n' "$dev" | awk -F: '$1=="ethernet"&&$2=="connected"&&$3!~/^(docker|veth|br|virbr|lo|tun|tap|wg)/{print $3;exit}')
eip=$(ip -br addr show "$edev" 2>/dev/null | awk '{print $3}' | cut -d/ -f1)
printf '%s\n%s\n%s\n%s\n%s\n' "$ssid" "${sig:-0}" "$wip" "$edev" "$eip"
