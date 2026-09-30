-- Environment Variables
-- NVIDIA / Wayland / Input Method / Locale / Cursor

-- Render GPU selection (takes effect on the NEXT Hyprland start, not on reload)
--
-- By default aquamarine picks the Intel iGPU as the primary DRM node, so the
-- iGPU composites both screens and every MSI frame is copied to the NVIDIA card
-- (which otherwise idles at 0%). Uncommenting this makes the RTX 4050 the
-- render GPU instead: much more headroom for the 1440p screen, at the cost of
-- battery life — and NVIDIA-as-primary has its own quirks (cursor, flicker).
--
-- AQ_DRM_DEVICES is ':'-separated, so /dev/dri/by-path/pci-0000:01:00.0-card
-- can't be used (that is what broke startup before). The colon-free names come
-- from /etc/udev/rules.d/61-gpu-offload.rules. If the symlinks are missing,
-- nothing is set and aquamarine falls back to iGPU compositing.
-- ENABLED 2026-09-25: the iGPU was pinned at max clock with the CPU package at
-- ~90C while the 4050 idled; NVreg DynamicPowerManagement=0 keeps it awake anyway.
--
-- Chosen per login: the 4050 composites only when a screen is plugged into it
-- (the MSI on HDMI, or eDP-1 if the MUX is ever switched to dGPU-only).
-- Laptop panel alone → iGPU composites. Hotplugging after login still works
-- (cross-GPU copy, as before); relogin to switch the render GPU.
local function exists(path)
	local f = io and io.open(path, "r")
	if f then f:close() return true end
	return false
end

local function dgpu_has_display()
	if not io then return false end
	for n = 0, 3 do
		for _, conn in ipairs({ "HDMI-A-1", "DP-1", "DP-2", "eDP-1" }) do
			local f = io.open(("/sys/bus/pci/devices/0000:01:00.0/drm/card%d/card%d-%s/status"):format(n, n, conn), "r")
			if f then
				local status = f:read("l")
				f:close()
				if status == "connected" then return true end
			end
		end
	end
	return false
end

local nvidia_composites = dgpu_has_display() and exists("/dev/dri/nvidia-dgpu") and exists("/dev/dri/intel-igpu")
if nvidia_composites then
	hl.env("AQ_DRM_DEVICES", "/dev/dri/nvidia-dgpu:/dev/dri/intel-igpu")
end

-- NVIDIA rendering
-- The GL/GBM vendor must match the compositing GPU: Chromium/Electron apps
-- (Spotify, Edge, VSCode) fail GPU init on a mismatch and fall back to CPU
-- rasterization (~100% CPU in the gpu-process, laggy windows). On iGPU logins
-- glvnd/GBM pick Mesa on their own.
if nvidia_composites then
	hl.env("LIBVA_DRIVER_NAME", "nvidia")
	hl.env("GBM_BACKEND", "nvidia-drm")
	hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
end
hl.env("NVD_BACKEND", "direct")
hl.env("NVPRESENT_SMOOTH_MOTION", "1")

-- Wayland session
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("GDK_BACKEND", "wayland,x11")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")

-- Input method (fcitx5)
hl.env("XMODIFIERS", "@im=fcitx")
hl.env("SDL_IM_MODULE", "fcitx")
hl.env("INPUT_METHOD", "fcitx")
hl.env("GLFW_IM_MODULE", "ibus")

-- Locale — prevents square boxes in Waybar/Dunst with CJK fonts
hl.env("LANG", "zh_TW.UTF-8")
hl.env("LANGUAGE", "zh_TW:en_US")
hl.env("LC_ALL", "zh_TW.UTF-8")

-- Qt scaling
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("QT_SCALE_FACTOR", "1.10")

-- Cursor: both XCursor (XWayland) and Hyprcursor (native Wayland)
hl.env("XCURSOR_THEME", "peachy_cursor")
hl.env("XCURSOR_SIZE", "12")
hl.env("HYPRCURSOR_THEME", "peachy_cursor")
hl.env("HYPRCURSOR_SIZE", "12")
