-- Single Source of Truth
-- All other modules require("globals") to access these.

G = {
    mainMod     = "SUPER",
    terminal    = "kitty",
    -- Unset LIBVA_DRIVER_NAME so Edge auto-detects VA-API driver from its
    -- render node, instead of crashing with the nvidia VA-API driver in an
    -- Intel GPU context. Native Wayland like the .desktop entry: under
    -- XWayland on the NVIDIA-composited MSI it stuttered badly.
    browser     = "env -u LIBVA_DRIVER_NAME GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx microsoft-edge-beta --ozone-platform=wayland --enable-wayland-ime",
    fileManager = "dolphin",
    menu        = "pkill rofi || rofi -show drun -theme ~/.config/rofi/theme.rasi",
    screenshot  = "lua5.4 ~/.config/hypr/scripts/screenshot.lua",

    -- wpctl sink IDs — run `wpctl status` to verify if audio device changes
    sink_main = 59,
    sink_sec  = 61,

    -- Wallpaper path
    wallpaper = "/home/LnoArch/Pictures/桌布/9c2e12b8243335d79512e07cff6cbf2e.jpg",

    -- Monitor selectors — desc: survives connector renames (e.g. DP-2 → HDMI-A-1)
    monitor_main   = "desc:Microstep MSI MP275Q PC3M385A00141",
    monitor_laptop = "desc:AU Optronics 0xD7A7",
}

return G
