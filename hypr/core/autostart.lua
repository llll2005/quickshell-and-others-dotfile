-- Autostart
-- All exec-once equivalents go in hl.on("hyprland.start").
-- hyprshade is applied at module level so it re-runs on every reload.

local G = require("globals")

hl.on("hyprland.start", function()
    -- polkit: Quickshell's AuthPrompt is the agent (it starts the KDE one itself if it can't register)
    hl.exec_cmd("fcitx5 -d --replace")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("blueman-applet")

    -- Clipboard history
    hl.exec_cmd("wl-paste --type text  --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- DBus environment (needed for portal and XDG integration)
    hl.exec_cmd("dbus-update-activation-environment --systemd LANG LC_CTYPE")
    hl.exec_cmd("dbus-update-activation-environment --systemd HYPRLAND_INSTANCE_SIGNATURE")

    -- Cursor must be set after compositor is ready
    hl.exec_cmd("hyprctl setcursor peachy_cursor 12")

    -- Quickshell shell (notifications, player, menu, control center)
    hl.exec_cmd("qs -p ~/.config/quickshell/shell.qml")

    -- Wallpaper via awww (sleep ensures daemon is ready before img command)
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("sleep 1 && awww img " .. G.wallpaper)

    -- Bind workspaces 11-20 to the MSI external after compositor init.
    hl.timer(function()
        for i = 11, 20 do
            hl.dispatch(hl.dsp.workspace.move({ workspace = i, monitor = G.monitor_main }))
        end
    end, { timeout = 2000, type = "oneshot" })

    -- imecaret plugin: `hyprctl caret` = the focused text input's cursor box, which the
    -- Quickshell candidate window needs (fcitx5 gets no caret from Wayland apps).
    -- Refuses to load after a Hyprland update until rebuilt:
    --   make -C ~/.config/quickshell/hypr-plugin/imecaret
    -- pcall: a refused load must not stop anything else here. It has been seen to fail
    -- silently at boot, so the shell also loads it when missing (quickshell
    -- services/Health.qml); a failure here is logged to find out why.
    local ok, err = pcall(hl.plugin.load, os.getenv("HOME") .. "/.config/quickshell/hypr-plugin/imecaret/imecaret.so")
    if not ok then
        local f = io.open(os.getenv("HOME") .. "/.cache/imecaret-load.log", "a")
        if f then f:write(os.date("%Y-%m-%d %H:%M:%S "), tostring(err), "\n"); f:close() end
    end
end)

-- Re-applied on every reload (not exec-once)
hl.exec_cmd("hyprshade on vibrance")
