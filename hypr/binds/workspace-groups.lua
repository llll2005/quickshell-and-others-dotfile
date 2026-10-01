-- Workspace Groups 動態分組管理
-- 使用 ~/.config/hypr/scripts/workspace-group.py

local wsg = "python3 ~/.config/hypr/scripts/workspace-group.py"

-- ═══ 分組導航 ═══
-- 在同組內切換（保持在相關 workspace 中）
hl.bind("SUPER + CTRL + Right", hl.dsp.exec_cmd(wsg .. " next-in-group"))
hl.bind("SUPER + CTRL + Left",  hl.dsp.exec_cmd(wsg .. " prev-in-group"))

-- ═══ 快速切換分組 ═══
hl.bind("SUPER + ALT + D", hl.dsp.exec_cmd(wsg .. " switch dev"))       -- 💻 開發
hl.bind("SUPER + ALT + R", hl.dsp.exec_cmd(wsg .. " switch research"))  -- 📚 研究
hl.bind("SUPER + ALT + S", hl.dsp.exec_cmd(wsg .. " switch standalone"))-- 📌 獨立

-- ═══ 動態管理 ═══
-- 將當前 workspace 加入特定分組（快速分類）
hl.bind("SUPER + SHIFT + D", hl.dsp.exec_cmd(wsg .. " set-current dev"))
hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd(wsg .. " set-current research"))
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd(wsg .. " set-current standalone"))

-- 開啟管理介面（需要 rofi）
hl.bind("SUPER + G", hl.dsp.exec_cmd(wsg .. " ui"))

-- 列出所有分組（通知）
hl.bind("SUPER + ALT + G", hl.dsp.exec_cmd(
    wsg .. " list | xargs -0 notify-send 'Workspace Groups' -t 3000"
))
