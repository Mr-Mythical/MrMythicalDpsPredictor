--[[
DemoScene.lua - Shared /mmui layout constants
Generated from design/tokens.json — prefer editing tokens, not this file.
]]

local MAJOR = "LibMrMythicalUI-1.0"
local lib = LibStub(MAJOR)

lib.DemoScene = {
	width = 520,
	height = 360,
	title = "LibMrMythicalUI Demo",
	logo = { size = 40, x = 16, y = -16 },
	close = { x = -10, y = -10 },
	tabs = {
		{ id = "nav", text = "Nav tabs", x = 16, y = -60 },
		{ id = "actions", text = "Buttons", x = 16, y = -96 },
		{ id = "status", text = "Progress", x = 16, y = -132 },
	},
	buttons = {
		{ id = "primary", text = "Primary", x = 160, y = -60 },
		{ id = "active", text = "Active", x = 160, y = -100, active = true },
		{ id = "disabled", text = "Disabled", x = 160, y = -140, disabled = true },
	},
	progress = { x = -40, y = -70, size = 72, percent = 0.72, feather = 0.125 },
	statusOffset = { x = 16, y = 16 },
}
