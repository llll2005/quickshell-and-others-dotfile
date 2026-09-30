-- Display: Monitors, Rendering, Misc
-- Monitor data sourced from: hyprctl monitors -j + edid-decode
--
-- Tuned for this machine: compositing runs on the Intel iGPU (it owns the
-- primary DRM node), while the MSI hangs off the NVIDIA card — so every MSI
-- frame is rendered on the iGPU and then copied across GPUs. Keep the
-- per-frame cost low; see render{} below.
--
-- Color (verified against Hyprland v0.56.2 source):
--   cm = "edid"                map sRGB content onto each panel's EDID primaries
--   sdr_eotf = "gamma22"       both EDIDs declare gamma 2.2; the Lua default is
--                              sRGB piecewise and ignores render.cm_sdr_eotf
--   supports_wide_color = -1   REQUIRED with "edid": the preset tags primaries as
--                              BT2020, and wide color would then signal BT2020
--                              colorimetry to an SDR monitor → washed out colors
--   supports_hdr = -1          no HDR: the MSI is 351 nits with a ~sRGB gamut, and
--                              auto-switching blanks the HDMI link for ~1s

local G = require("globals")

-- ┌─────────────────────────────────────────────────────────┐
-- │  Monitor 1 — MSI MP275Q  (External, Left, 0x0)          │
-- │  HDMI-A-1 · 2560x1440 · 100Hz · 10-bit · 600×330mm      │
-- └─────────────────────────────────────────────────────────┘
hl.monitor({
	output = G.monitor_main,
	-- 100Hz: 410.5 MHz clock → 513 MHz TMDS at 10-bit (HDMI 2.0 max 600).
	-- Fall back to @85 (433 MHz) if the picture glitches.
	mode = "2560x1440@100",
	position = "0x0",
	scale = 1,
	bitdepth = 10, -- HDMI sink supports DC_30bit; fewer gradient steps
	cm = "edid", -- EDID gamut ≈ 102% sRGB
	sdr_eotf = "gamma22",
	supports_hdr = -1,
	supports_wide_color = -1,
	vrr = 0, -- HDMI + NVIDIA: toggling adaptive sync blanks the link
})

-- ┌─────────────────────────────────────────────────────────┐
-- │  Monitor 2 — AU Optronics Laptop Panel (Right, 2560x0)  │
-- │  eDP-2 · 1920x1200 · 165Hz · 8-bit panel · 340×220mm    │
-- └─────────────────────────────────────────────────────────┘
hl.monitor({
	output = G.monitor_laptop,
	mode = "1920x1200@165",
	position = "2560x0",
	scale = 1,
	bitdepth = 10, -- panel is 8 bpc; no gain, no harm
	cm = "edid", -- EDID gamut ≈ 116% sRGB; "srgb" would oversaturate
	sdr_eotf = "gamma22",
	supports_hdr = -1,
	supports_wide_color = -1,
	-- VRR follows misc:vrr (eDP handles it cleanly)
})

-- Compositor behaviour
hl.config({
	misc = {
		force_default_wallpaper = 0,
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
		animate_manual_resizes = true,
		animate_mouse_windowdragging = true,
		vrr = 2, -- fullscreen only; the MSI opts out above
	},

	render = {
		-- Performance. The iGPU composites both screens and copies every MSI
		-- frame to the NVIDIA card, so per-frame cost matters more than usual.
		-- FP16 is what makes translucency blend in linear light (kitty's
		-- transparent background looks lighter / more see-through). It costs
		-- bandwidth on the iGPU — the answer to that is moving compositing to the
		-- NVIDIA card (see core/env.lua), not turning this off.
		use_fp16 = 2, -- auto → on, because "edid" primaries are not plain sRGB
		direct_scanout = false, -- cross-GPU scanout keeps failing on plane format
		new_render_scheduling = false, -- experimental; uneven pacing on a busy GPU
		use_shader_blur_blend = false, -- experimental

		-- Color
		cm_sdr_eotf = "gamma22force", -- treat sRGB-tagged clients as gamma 2.2 too
		cm_auto_hdr = 0, -- never switch the MSI into HDR
		fp16_sdr_tf = 1, -- linear blending for translucency / blur / shadows

		-- Left at default on purpose:
		--   non_shader_cm = 3   fullscreen KMS CTM converts primaries without
		--                       linearizing first → slight color error
		--   xp_mode = false     true skips background layers (hides wallpaper)
	},

	dwindle = {
		preserve_split = true,
	},
})

-- workspace_rule monitor field is not guaranteed in 0.55 Lua;
-- actual binding is done in autostart via moveworkspacetomonitor
