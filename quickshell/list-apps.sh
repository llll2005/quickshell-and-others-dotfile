#!/bin/bash
# Launcher entries for widgets/Menu.qml — see scripts/list-apps.py for the format.
exec python3 "$(dirname "$(readlink -f "$0")")/scripts/list-apps.py"
