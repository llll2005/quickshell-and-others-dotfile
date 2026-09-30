-- Window Rules (Hyprland 0.55 unified syntax)

-- ── Smart Gaps: no gaps or border when only one tiled window ─
hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
hl.window_rule({
    name        = "no-gaps-solo",
    match       = { float = false, workspace = "w[tv1]" },
    border_size = 0,
    rounding    = 0,
})

-- ── Universal ────────────────────────────────────────────────
hl.window_rule({
    name           = "suppress-maximize",
    match          = { class = ".*" },
    suppress_event = "maximize",
})

-- XWayland drag fix (avoids ghost focus on unfocused XWayland float popups)
hl.window_rule({
    name       = "fix-xwayland-drags",
    match      = { class = "^$", title = "^$", xwayland = true,
                   float = true, fullscreen = false, pin = false },
    no_focus   = true,
})

-- ── Chromium / Edge ─────────────────────────────────────────
-- xdg_popup (tooltip / dropdown) causes parent window set_window_geometry,
-- which Hyprland animates as a resize flash. no_anim suppresses that.
-- WaylandWindowDecorations in edge-flags reduces xdg_popup reconfigures.
hl.window_rule({
    name           = "edge-suppress-fullscreen",
    match          = { class = "^microsoft%-edge%-beta$" },
    suppress_event = "fullscreen",
})
hl.window_rule({
    name    = "edge-no-anim",
    match   = { class = "^microsoft%-edge%-beta$" },
    no_anim = true,
})

-- ── HDR (MSI) ────────────────────────────────────────────────
-- VSCode is native Wayland Electron and gets the MSI's PQ image description.
-- If it tags its output with the full PQ range, Hyprland tonemaps it down to
-- the panel peak and the whole window darkens. clamp = clip at the peak only.
hl.window_rule({
    name    = "code-no-tonemap",
    match   = { class = "^code$" },
    tonemap = "clamp",
})

-- ── System Tools ────────────────────────────────────────────
hl.window_rule({
    name   = "float-audio-ime",
    match  = { class = "^(pavucontrol|org%.fcitx%.fcitx5%-config%-qt|fcitx5%-config%-qt)$" },
    float  = true,
    center = true,
    size   = "800 500",
})

-- ── Auth & Polkit ────────────────────────────────────────────
hl.window_rule({
    name   = "float-polkit",
    match  = { class = "^(polkit%-.*|authentication%-agent%.*)$" },
    float  = true,
    center = true,
    size   = "600 350",
})

hl.window_rule({
    name   = "float-sudo-tui",
    match  = { title = "^(.*SUDO AUTHENTICATION.*)$" },
    float  = true,
    center = true,
    size   = "600 200",
})

-- Browser SSO popups (Google/Microsoft login dialogs)
hl.window_rule({
    name   = "float-sso",
    match  = { title = "^(Sign in.*|Login.*|登入.*)$" },
    float  = true,
    center = true,
    size   = "600 700",
})

-- ── Media Viewers ────────────────────────────────────────────
hl.window_rule({
    name   = "float-media",
    match  = { class = "^(imv|mpv|vlc)$" },
    float  = true,
    center = true,
    size   = "1200 800",
})

-- Picture-in-Picture: pin to bottom-right corner
hl.window_rule({
    name  = "pip",
    match = { title = "^(Picture%-in%-Picture)$" },
    float = true,
    pin   = true,
    move  = "100%-w-20 100%-h-20",
})

-- ── Development GUIs ────────────────────────────────────────
hl.window_rule({
    name   = "float-matplotlib",
    match  = { class = "^(matplotlib)$" },
    float  = true,
    center = true,
})

hl.window_rule({
    name   = "float-tkinter",
    match  = { class = "^(Tk|python3)$" },
    float  = true,
    center = true,
})

hl.window_rule({
    name  = "float-qt",
    match = { class = "^(Qt.*)$" },
    float = true,
})

-- CG / graphics dev windows (OpenGL, Vulkan, CG renders)
hl.window_rule({
    name  = "float-graphics",
    match = { title = "^(.*(CG|openGL|Vulkan).*)$" },
    float = true,
})

hl.layer_rule({
    name   = "noanim-quickshell",
    match  = { namespace = "^quickshell$" },
    no_anim = true,
})