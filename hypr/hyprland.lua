-- Entry Point
-- Load order matters: globals → core (hardware) → ui (visuals) → binds
require("globals")

require("core.env")
require("core.display")
require("core.input")
require("core.autostart")

require("ui.theme")
require("ui.animations")
require("ui.rules")

require("binds.dispatchers")
require("binds.wm")
require("binds.submaps")
require("binds.workspace-groups")
