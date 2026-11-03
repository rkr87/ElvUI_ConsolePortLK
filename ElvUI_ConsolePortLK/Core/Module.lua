local E, L, V, P, G = unpack(ElvUI); --Import: Engine, Locales, PrivateDB, ProfileDB, GlobalDB

if not E then return end

-- The plugin is a proper ElvUI module so that other addons (and the user) can
-- reach it with E:GetModule("ConsolePortLK"). AceEvent-3.0 has to be embedded
-- explicitly, otherwise the module has no RegisterEvent/UnregisterEvent.
local CPLK = E:NewModule("ConsolePortLK", "AceEvent-3.0")

--[[ Returns the profile table for this plugin.

	ElvUI merges P.consolePortLK into the profile on login, but an ElvUI
	profile that was copied before this plugin existed (or a profile reset)
	will not have the new keys. Filling them in here keeps old profiles and
	addon updates working without a reload. ]]
function CPLK:DB()
	local db = E.db and E.db.consolePortLK
	if not db then
		db = {}
		E.db.consolePortLK = db
	end

	for key, value in pairs(P.consolePortLK) do
		if type(value) ~= "table" and db[key] == nil then
			db[key] = value
		end
	end

	return db
end

--[[ Returns the per character settings (ElvPrivateDB profile).

	`V` is only the defaults table (privateVars.profile); the live profile is
	E.private and is what actually gets saved. ]]
function CPLK:Private()
	local private = E.private
	if type(private) ~= "table" then return V.consolePortLK end

	if type(private.consolePortLK) ~= "table" then
		private.consolePortLK = {}
		for key, value in pairs(V.consolePortLK or {}) do
			private.consolePortLK[key] = value
		end
	end

	return private.consolePortLK
end

CPLK.skinned = {} -- [button] = private per button state
CPLK.textHolders = {} -- [cooldown frame] = our countdown holder frame

-- ConsolePort (base addon) and ConsolePortBar are optional, so every entry
-- point resolves them lazily instead of caching at file load.
function CPLK:GetConsolePort()
	return _G.ConsolePort
end

function CPLK:GetBar()
	return _G.ConsolePortBar
end

function CPLK:GetCPDB()
	local api = _G.ConsolePort
	if not api then return nil end

	local ok, db = pcall(api.GetData, api)
	if ok and type(db) == "table" then return db end
end

function CPLK:GetCPCC()
	local db = self:GetCPDB()
	local api = db and db.CPAPI
	return api and api.CPCC
end

function CPLK:GetSettings()
	local setup = _G.ConsolePortBarSetup
	if not setup then return nil, (self:GetBar() ~= nil) end
	return setup
end

function CPLK:IsConsolePortLoaded()
	return (self:GetBar() and self:GetCPDB()) ~= nil
end
