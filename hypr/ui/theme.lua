-- Theme: Holographic Y2K / 全息棱鏡
-- Palette: 深宇宙黑 / 全息粉 / 光譜青 / 薰衣紫 / 電光青
--
-- Active border  : 粉 → 青 → 紫  3色光譜漸層 (45°)
-- Inactive border: 近透明深藍 (結構感但不搶眼)
-- Shadow         : 全息青光暈
-- Rounding       : 4px squircle (保留方框感)

local C = {
	-- 3-stop holographic gradient (棱鏡光譜)
	holo_pink = "rgba(ff6eb4ee)", -- 全息粉
	holo_cyan = "rgba(7effffee)", -- 光譜青
	holo_lavender = "rgba(b8a8ffee)", -- 薰衣紫

	-- Inactive / background
	ghost_navy = "rgba(0d0d2266)", -- 近透明深藍

	-- Shadow  0xAARRGGBB
	shadow_active = 0x2aff6eb4, -- 全息粉光暈, alpha ~17%
	shadow_idle = 0x08200010, -- 極淡深粉黑
}

-- Quickshell 主題同步：~/.config/quickshell/scripts/theme-sync.py 依目前的 Quickshell 主題
-- 產生 ui/qs_theme.lua（邊框漸層、非作用中邊框、光暈）。同步開著（shell.conf 的
-- [sync] hyprland = true）且檔案可讀才套用；否則照上面的全息 Y2K 配色。
-- 換主題時腳本也會用 `hyprctl eval` 即時套用，不必 reload。
local ok, QS = pcall(dofile, os.getenv("HOME") .. "/.config/hypr/ui/qs_theme.lua")
if not (ok and type(QS) == "table" and QS.enabled) then
	QS = nil
end

hl.config({
	general = {
		gaps_in = 3,
		gaps_out = 8,
		border_size = 2,
		resize_on_border = true,
		allow_tearing = false,
		layout = "dwindle",

		col = {
			active_border = QS and { colors = QS.active, angle = QS.angle or 45 }
				or { colors = { C.holo_pink, C.holo_cyan, C.holo_lavender }, angle = 45 },
			inactive_border = QS and QS.inactive or C.ghost_navy,
		},
	},

	decoration = {
		rounding = 4,
		rounding_power = 3,

		active_opacity = 1.0,
		inactive_opacity = 1.0,

		shadow = {
			enabled = true,
			range = 14,
			render_power = 2,
			color = QS and QS.shadow or C.shadow_active,
			color_inactive = QS and QS.shadow_idle or C.shadow_idle,
		},

		blur = {
			enabled = true,
			-- Quality over cost, restored on request. Blur is the most expensive
			-- effect (cost ≈ area × passes). If the iGPU starts stuttering again,
			-- move compositing to the NVIDIA card (see core/env.lua) instead of
			-- cutting these down.
			size = 8,
			passes = 3,
			vibrancy = 0.28,
			contrast = 1.05,
			brightness = 0.92,
		},
		motion_blur = {
			enabled = false,
			samples = 44, -- default; 1–64, higher = smoother trails
		},
	},
})
