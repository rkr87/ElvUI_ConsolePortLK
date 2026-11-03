local E, L, V, P, G = unpack(ElvUI); --Import: Engine, Locales, PrivateDB, ProfileDB, GlobalDB

if not E then return end

local CPLK = E:GetModule("ConsolePortLK")
local EP = E.Libs.EP

local AddOnName = ...
local ADDON_LOADED_NAME = AddOnName

-- Expose the module so macros, other addons and the settings panel can find
-- it without knowing the module name.
_G.ElvUIConsolePortLK = CPLK

-- AceLocale resolves unknown keys to the key itself, so a missing translation
-- can be a boolean. Never hand that to format().
local function SafeStr(key)
	local value = L[key]
	if type(value) == "string" then return value end
	return key
end

local FONT_FLAGS = {
	["NONE"] = "NONE",
	["OUTLINE"] = "OUTLINE",
	["MONOCHROMEOUTLINE"] = "MONOCHROMEOUTLINE",
	["THICKOUTLINE"] = "THICKOUTLINE",
}

local function Refresh(popup)
	if InCombatLockdown() then
		E:Print(SafeStr("Not in combat."))
		return
	end

	E:Delay(0, function()
		CPLK:UpdateState()
	end)

	if popup then
		E:StaticPopup_Show("PRIVATE_RL")
	end
end

local function getOptions()
	local db = function() return CPLK:DB() end

	local options = {
		order = 60,
		type = "group",
		name = "|cff1784d1C|r|cffe5e3e3onsolePort|r",
		args = {
			header = {
				order = 1,
				type = "header",
				name = "|cff1784d1ConsolePortLK-Enhanced|r",
			},
			info = {
				order = 2,
				type = "description",
				name = L["Skins the ConsolePortLK-Enhanced action bar so it matches your ElvUI action bar buttons."],
			},
			spacer1 = {
				order = 3,
				type = "description",
				name = " ",
			},
			enabled = {
				order = 4,
				type = "toggle",
				name = L["Enable Plugin"],
				desc = L["Disables the plugin and puts the ConsolePort art back."],
				get = function(info) return db()[info[#info]] end,
				set = function(info, value)
					db()[info[#info]] = value
					Refresh(true)
				end,
			},
			buttonGroup = {
				order = 5,
				type = "group",
				guiInline = true,
				name = L["Bar Options"],
				args = {
					apply = {
						order = 1,
						type = "execute",
						name = L["Apply Skin"],
						desc = L["Re-applies the skin and picks up new buttons. Safe to use in combat."],
						func = function()
							local count = CPLK:SkinAll()
							if count then
								E:Print(format(SafeStr("Skinned %d buttons."), count))
							else
								E:Print(SafeStr("The ConsolePort action bar was not found."))
							end
						end,
					},
					reset = {
						order = 2,
						type = "execute",
						name = L["Reset Settings"],
						desc = L["Resets every option of this plugin back to its default value."],
						confirmText = "Reset Settings",
						confirm = function() return SafeStr("Reset every option of the ConsolePort skin?") end,
						func = function()
							for key, value in pairs(P.consolePortLK) do
								if type(value) ~= "table" then
									db()[key] = value
								end
							end
							Refresh(true)
						end,
					},
				},
			},
			borderGroup = {
				order = 6,
				type = "group",
				guiInline = true,
				name = L["Border"],
				get = function(info) return db()[info[#info]] end,
				set = function(info, value)
					db()[info[#info]] = value
					CPLK:UpdateState()
				end,
				args = {
					borderSize = {
						order = 1,
						type = "range",
						name = L["Border Size"],
						desc = L["The border thickness is multiplied by ElvUI's pixel scale, so 1 is a crisp single pixel line."],
						min = 0, max = 6, step = 1,
					},
					borderOutside = {
						order = 2,
						type = "toggle",
						name = L["Border Outside"],
						desc = L["Draws the border outside of the button bounds instead of inside the ConsolePort art."],
						disabled = function() return db().borderSize == 0 end,
					},
					backdropTemplate = {
						order = 7,
						type = "select",
						name = L["Backdrop Template"],
						desc = L["Which ElvUI backdrop template to use for the button. 'Auto' follows your ElvUI action bar setting."],
						values = {
							auto = L["Auto"],
							Default = L["Default"],
							Transparent = L["Transparent"],
						},
					},
					borderAutoContrast = {
						order = 3,
						type = "toggle",
						name = L["Auto Border Contrast"],
						desc = L["ElvUI's border colour is often pure black, which is invisible on a dark backdrop. When on, the border is lightened (or darkened) until it is visible. Turn off to use the ElvUI border colour exactly."],
					},
					borderColor = {
						order = 4,
						type = "color",
						name = L["Border Colour"],
						desc = L["Overrides the colour of the button border. Leave unset to inherit ElvUI's border colour."],
						hasAlpha = false,
						get = function()
							local c = db().borderColor
							if type(c) == "table" then return c.r or c[1], c.g or c[2], c.b or c[3] end
							local e = E.media and E.media.bordercolor
							if type(e) == "table" then return e.r or e[1], e.g or e[2], e.b or e[3] end
							return 0, 0, 0
						end,
						set = function(info, r, g, b)
							db().borderColor = {r = r, g = g, b = b}
							CPLK:UpdateState()
						end,
					},
					hoverUseClassColor = {
						order = 5,
						type = "toggle",
						name = L["Class Colour on Hover"],
						desc = L["Highlights the border in your class colour while hovering or pressing the button."],
					},
					hoverColor = {
						order = 6,
						type = "color",
						name = L["Hover Colour"],
						desc = L["Overrides the hover and pressed highlight colour. Leave unset to use your class colour."],
						hasAlpha = false,
						get = function()
							local c = db().hoverColor
							if type(c) == "table" then return c.r or c[1], c.g or c[2], c.b or c[3] end
							local e = E.myclass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[E.myclass]
							if e then return e.r, e.g, e.b end
							return 1, 1, 1
						end,
						set = function(info, r, g, b)
							db().hoverColor = {r = r, g = g, b = b}
							CPLK:UpdateState()
						end,
					},
				},
			},
			textGroup = {
				order = 7,
				type = "group",
				guiInline = true,
				name = L["Font & Text"],
				get = function(info) return db()[info[#info]] end,
				set = function(info, value)
					db()[info[#info]] = value
					CPLK:UpdateState()
				end,
				args = {
					hideMacroText = {
						order = 1,
						type = "toggle",
						name = L["Hide Macro Text"],
						desc = L["Hides the macro name that ConsolePort prints at the bottom of the button."],
					},
					hideCount = {
						order = 2,
						type = "toggle",
						name = L["Hide Count Text"],
						desc = L["Hides the item and stack count text on the button."],
					},
					font = {
						order = 3,
						type = "toggle",
						name = L["ElvUI Font"],
						desc = L["Use the ElvUI action bar font for the count text, macro text and cooldown text."],
					},
					fontSize = {
						order = 4,
						type = "range",
						name = L["Text Size"],
						min = 6, max = 24, step = 1,
					},
					fontOutline = {
						order = 5,
						type = "select",
						name = L["Font Outline"],
						values = FONT_FLAGS,
					},
				},
			},
			cooldownGroup = {
				order = 8,
				type = "group",
				guiInline = true,
				name = L["Cooldown Text"],
				get = function(info) return db()[info[#info]] end,
				set = function(info, value)
					db()[info[#info]] = value
					CPLK:UpdateState()
				end,
				args = {
					cooldownText = {
						order = 1,
						type = "toggle",
						name = L["ElvUI CD Text"],
						desc = L["Replaces the ConsolePort cooldown text with ElvUI's action bar cooldown text."],
					},
					cooldownUseElvUI = {
						order = 2,
						type = "toggle",
						name = L["Use ElvUI Settings"],
						desc = L["Use ElvUI's global cooldown settings for the text instead of the options below."],
						disabled = function() return not db().cooldownText end,
					},
					cooldownFontSize = {
						order = 3,
						type = "range",
						name = L["Cooldown Text Size"],
						min = 6, max = 32, step = 1,
						disabled = function() return not db().cooldownText or db().cooldownUseElvUI end,
					},
					cooldownThreshold = {
						order = 4,
						type = "range",
						name = L["Cooldown Threshold"],
						desc = L["Cooldowns below this many seconds are shown with one decimal."],
						min = 0, max = 10, step = 1,
						disabled = function() return not db().cooldownText or db().cooldownUseElvUI end,
					},
				},
			},
			miscGroup = {
				order = 9,
				type = "group",
				guiInline = true,
				name = L["Misc Options"],
				get = function(info) return db()[info[#info]] end,
				set = function(info, value)
					db()[info[#info]] = value
					CPLK:UpdateState()
				end,
				args = {
					swipe = {
						order = 1,
						type = "toggle",
						name = L["Show Blizzard Swipe"],
						desc = L["Show the stock ConsolePort radial swipe underneath the ElvUI cooldown text."],
					},
					desaturate = {
						order = 2,
						type = "toggle",
						name = L["Desaturate on Cooldown"],
						desc = L["Greys out the spell icon while the ability is cooling down, just like ElvUI."],
					},
					skinPetRing = {
						order = 3,
						type = "toggle",
						name = L["Skin Pet Ring"],
						desc = L["Also skins the pet action ring around the ConsolePort bar."],
					},
				},
			},
		},
	}

	E.Options.args.consolePortLK = options
end

--[[ Registers the options panel with ElvUI.

	LibElvUIPlugin-1.0 registers our callback straight away when
	ElvUI_OptionsUI is already loaded, otherwise it waits for its own
	ADDON_LOADED listener. If that event arrives before ElvUI_OptionsUI has
	finished creating E.Options.args.plugins (which happens when the options
	addon is force loaded by a dependency, instead of through /elvui), the
	library errors inside *its* code and every plugin registered the same way
	reports that error. Wrapping the call in a pcall and retrying later means a
	bad load order can never break another author's plugin. ]]
function CPLK:SetupOptions()
	if type(EP) ~= "table" or type(EP.RegisterPlugin) ~= "function" then return end
	if self.optionsRegistered then return end

	local ok, err = pcall(EP.RegisterPlugin, EP, AddOnName, getOptions)
	if ok then
		self.optionsRegistered = true
		return
	end

	-- ElvUI_OptionsUI is not ready yet, try again when it is.
	if not self.optionRetry then
		local frame = CreateFrame("Frame")
		frame:RegisterEvent("ADDON_LOADED")
		frame:RegisterEvent("PLAYER_ENTERING_WORLD")
		frame:SetScript("OnEvent", function(_, _, addon)
			if addon and addon ~= "ElvUI_OptionsUI" and addon ~= ADDON_LOADED_NAME and addon ~= "PLAYER_ENTERING_WORLD" then return end
			if CPLK.optionsRegistered then return end

			local retryOk = pcall(EP.RegisterPlugin, EP, AddOnName, getOptions)
			if retryOk then
				CPLK.optionsRegistered = true
				frame:UnregisterAllEvents()
			end
		end)
		self.optionRetry = frame
	end

	self.optionsError = err
end
