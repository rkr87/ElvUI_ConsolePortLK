local E, L, V, P, G = unpack(ElvUI); --Import: Engine, Locales, PrivateDB, ProfileDB, GlobalDB

if not E then return end

local CPLK = E:GetModule("ConsolePortLK")

-- AceLocale resolves an unknown key to the key itself, so a missing
-- translation can be a boolean. Never concatenate or format those directly.
local function Str(key)
	local value = L[key]
	if type(value) == "string" then return value end
	return key
end

local function HandleCommand(input)
	local command = (input or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

	if command == "" or command == "help" then
		E:Print("|cff1784d1E|r|cffe5e3e3lvUI|r |cff1784d1C|r|cffe5e3e3onsolePort|r")
		E:Print("|cffffd100/cplk skin|r - " .. Str("Skin every ConsolePort action button now."))
		E:Print("|cffffd100/cplk toggle|r - " .. Str("Toggle the plugin on or off."))
		E:Print("|cffffd100/cplk config|r - " .. Str("Open the plugin options."))
		E:Print("|cffffd100/cplk debug|r - " .. Str("Colour-code the skin elements for screenshots."))
		E:Print("|cffffd100/cplk debug report|r - " .. Str("Print a diagnostic report."))
	elseif command == "skin" or command == "apply" then
		if InCombatLockdown() then
			E:Print(Str("Not in combat."))
			return
		end

		local count = CPLK:SkinAll()
		if count then
			E:Print(format(Str("Skinned %d buttons."), count))
		else
			E:Print(Str("The ConsolePort action bar was not found."))
		end
	elseif command == "toggle" then
		local db = CPLK:DB()
		db.enabled = not db.enabled
		CPLK:UpdateState()
		E:Print(format("%s: %s", Str("Enable Plugin"), Str(db.enabled and "Enabled" or "Disabled")))
	elseif command:sub(1, 5) == "debug" then
		-- `command` is already lowercased and trimmed, so the argument is
		-- everything from character 6 - and it must be trimmed again, because
		-- it still starts with the separating space ("debug report" -> " report").
		local rest = command:sub(6):gsub("^%s+", "")

		if CPLK.HandleDebugCommand then
			CPLK:HandleDebugCommand(rest)
		else
			E:Print("|cffff0000[cplk]|r Core\\Debug.lua did not load - check for a Lua error at login.")
		end
	elseif command == "config" or command == "options" then
		E:ToggleOptionsUI()
	else
		E:Print(format(Str("Unknown command: %s"), command))
	end
end

function CPLK:RegisterCommands()
	if type(E.RegisterChatCommand) ~= "function" then return end

	local ok = pcall(E.RegisterChatCommand, E, "cplk", HandleCommand)

	-- A plain slash fallback is registered either way. `/cplk` must always work,
	-- especially the debug command.
	_G.SLASH_CPLK1 = "/cplk"
	_G.SlashCmdList = _G.SlashCmdList or {}
	_G.SlashCmdList["CPLK"] = function(msg) HandleCommand(msg) end
end
