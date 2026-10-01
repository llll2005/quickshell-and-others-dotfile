-- Input: Keyboard, Mouse, Touchpad, Cursor

hl.config({
    input = {
        kb_layout    = "us",
        follow_mouse = 1,
        mouse_refocus = false,  -- stops the refocus churn that flickers Chromium/Edge tooltips (keeps follow_mouse=1 feel)
        sensitivity  = 0.7,
        touchpad = {
            natural_scroll = true,
        },
    },

    cursor = {
        -- NVIDIA does not support hardware cursors on Wayland
        no_hardware_cursors = true,
    },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "up",   action = function() hl.dispatch(hl.dsp.focus({ workspace = "+5" })) end })
hl.gesture({ fingers = 3, direction = "down", action = function() hl.dispatch(hl.dsp.focus({ workspace = "-5" })) end })
