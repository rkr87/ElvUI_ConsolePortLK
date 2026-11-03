local E, L, V, P, G = unpack(ElvUI) --Import: Engine, Locales, PrivateDB, ProfileDB, GlobalDB

if not E then return end

-- Every option lives in your ElvUI profile (ElvDB), so a profile copy also
-- carries the ConsolePort skin with it.
P.consolePortLK = {
	enabled = true,

	-- Text
	hideMacroText = true,
	hideCount = false,
	font = true,
	fontSize = 10,
	fontOutline = "OUTLINE",

	-- Border
	borderSize = 1,
	backdropTemplate = "auto",
	borderAutoContrast = true,
	borderColor = nil,
	hoverUseClassColor = true,
	hoverColor = nil,

	-- Cooldown text
	cooldownText = true,
	cooldownUseElvUI = true,
	-- Only used when cooldownUseElvUI is disabled.
	cooldownFontSize = 12,
	cooldownThreshold = 3,

	-- Misc
	swipe = true,
	desaturate = false,
	skinPetRing = true,
}

-- Private (per character, shared across profiles): the one time install flag.
V.consolePortLK = {
	installed = false,
}
