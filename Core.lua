local E, L, V, P, G = unpack(ElvUI); --Import: Engine, Locales, PrivateDB, ProfileDB, GlobalDB

if not E then return end

local CPLK = E:GetModule("ConsolePortLK")
local PI = E:GetModule("PluginInstaller")

local AddOnName, AddOnTable = ...

--[[ AceLocale resolves an unknown key to the key itself, so a missing
	translation can be a boolean. Keep the installer text safe. ]]
local function Str(key)
	local value = L[key]
	if type(value) == "string" then return value end
	return key
end

-------------------------------------------------------------------------------
-- First time install (ElvUI plugin installer)
-------------------------------------------------------------------------------
local function PageOne()
	PluginInstallFrame.SubTitle:SetText("|cff1784d1E|r|cffe5e3e3lvUI|r |cff1784d1C|r|cffe5e3e3onsolePort|r")
	PluginInstallFrame.Desc1:SetText(Str("This plugin skins the ConsolePortLK-Enhanced action bar so it matches your ElvUI action bar buttons."))
	PluginInstallFrame.Desc2:SetText(Str("It hides the macro text, moves the cooldown text over to ElvUI's style and lets you control the border size."))
	PluginInstallFrame.Desc3:SetText(Str("All options can be changed later under ElvUI > Plugins > ConsolePort."))

	PluginInstallFrame.Option1:Show()
	PluginInstallFrame.Option1:SetText(ACCEPT)
	PluginInstallFrame.Option1:SetScript("OnClick", function()
		CPLK:Private().installed = true
		CPLK:DB().enabled = true
		CPLK:UpdateState()

		PluginInstallFrame.Option1:Hide()
		PluginInstallFrame.Option2:Hide()
		PluginInstallFrame.Desc1:SetText("|cff00ff00" .. Str("Done!") .. "|r")
		PluginInstallFrame.Desc2:SetText("")
		PluginInstallFrame.Desc3:SetText("")
	end)

	PluginInstallFrame.Option2:Show()
	PluginInstallFrame.Option2:SetText(Str("Not now"))
	PluginInstallFrame.Option2:SetScript("OnClick", function()
		CPLK:Private().installed = true
		CPLK:DB().enabled = false
		CPLK:UpdateState()

		PluginInstallFrame.Option1:Hide()
		PluginInstallFrame.Option2:Hide()
		PluginInstallFrame.Desc1:SetText(Str("No problem. You can enable the plugin any time under ElvUI > Plugins > ConsolePort."))
		PluginInstallFrame.Desc2:SetText("")
		PluginInstallFrame.Desc3:SetText("")
	end)
end

function CPLK:QueueInstall()
	if type(PI) ~= "table" or type(PI.Queue) ~= "function" then return end
	if CPLK:Private().installed then return end
	if not (IsAddOnLoaded("ConsolePortBar") or IsAddOnLoaded("ConsolePort")) then return end

	PI:Queue({
		Title = "|cff1784d1E|r|cffe5e3e3lvUI|r |cff1784d1C|r|cffe5e3e3onsolePort|r",
		Name = "ElvUI_ConsolePortLK",
		Pages = {
			[1] = PageOne,
		},
		StepTitles = {
			[1] = L["Welcome"],
		},
	})
end

-------------------------------------------------------------------------------
-- Boot
-------------------------------------------------------------------------------
function CPLK:OnInitialize()
	-- A plugin must never be able to break ElvUI's own initialisation, so each
	-- step is isolated. Any failure only disables that piece of the plugin.
	local ok, err = pcall(self.SetupOptions, self)
	if not ok and not self.warnedOptions then
		self.warnedOptions = true
		E:Print("|cffff0000ConsolePort Skin: the options page could not be registered.|r " .. tostring(err))
	end

	ok, err = pcall(self.RegisterCommands, self)
	if not ok and not self.warnedCommands then
		self.warnedCommands = true
		E:Print("|cffff0000ConsolePort Skin: slash commands could not be registered.|r " .. tostring(err))
	end

	-- Everything in Skin.lua (event registrations, the initial apply and the
	-- geometry watchdog) lives in Initialize(). It has to be called explicitly;
	-- forgetting this is why the skin only ever appeared after `/cplk skin`.
	ok, err = pcall(self.Initialize, self)
	if not ok and not self.warnedInit then
		self.warnedInit = true
		E:Print("|cffff0000ConsolePort Skin: the skin engine could not start.|r " .. tostring(err))
	end

	-- AceEvent callbacks receive (event, ...), never `self`.
	ok, err = pcall(self.RegisterEvent, self, "PLAYER_LOGIN", function()
		E:Delay(2, function()
			pcall(CPLK.QueueInstall, CPLK)
		end)
	end)
	if not ok then
		-- No AceEvent (unexpected for an ElvUI module), fall back to a frame.
		local frame = CreateFrame("Frame")
		frame:RegisterEvent("PLAYER_LOGIN")
		frame:SetScript("OnEvent", function()
			E:Delay(2, function()
				pcall(CPLK.QueueInstall, CPLK)
			end)
			frame:UnregisterAllEvents()
		end)
	end
end

local function InitializeCallback()
	CPLK:OnInitialize()

	-- A plugin loaded into an already-running session never sees
	-- PLAYER_ENTERING_WORLD fire again.
	if _G.IsLoggedIn and _G.IsLoggedIn() and not _G.InCombatLockdown() then
		E:Delay(1, function()
			pcall(CPLK.ApplySkin, CPLK)
		end)
	end
end

E:RegisterModule(CPLK:GetName(), InitializeCallback)
