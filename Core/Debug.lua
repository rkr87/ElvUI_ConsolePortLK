local E, L, V, P, G = unpack(ElvUI); --Import: Engine, Locales, PrivateDB, ProfileDB, GlobalDB

if not E then return end

local CPLK = E:GetModule("ConsolePortLK")
local unpack = unpack or table.unpack

-- The folder this file was loaded from. Every released zip is extracted into a
-- versioned folder, so if more than one of them is installed both copies load
-- and fight over the same buttons. Reporting this makes that visible.
local ADDON_NAME = ...
CPLK.debugAddonName = ADDON_NAME

-- Bumped in every release. Read from the file that is actually running, so it
-- cannot be stale the way an addon folder name can: WoW only re-reads the TOC
-- metadata on a full client restart, but this string travels with the code.
CPLK.build = "1.1.4"

-------------------------------------------------------------------------------
-- Diagnostics for the ConsolePort action bar skin
--
--   /cplk debug          toggle the colour overlay on/off
--   /cplk debug on|off   same, explicit
--   /cplk debug report   print a detailed report without the overlay
--
-- Every element the plugin adds or controls is painted in a colour that is
-- impossible to confuse with the game's own art, so a single screenshot says
-- which element is where, and whether it exists at all.
-------------------------------------------------------------------------------

-- Element -> colour. Deliberately garish.
CPLK.DebugColors = {
	border     = {1.00, 0.00, 1.00, 1.00},  -- magenta : our border edge
	backdrop   = {0.00, 1.00, 0.00, 0.55},  -- green   : our backdrop fill
	icon       = {1.00, 0.55, 0.00, 0.35},  -- orange  : the icon region we keep
	hover      = {0.00, 0.60, 1.00, 1.00},  -- blue    : hover highlight
	cooldown   = {1.00, 0.00, 0.00, 1.00},  -- red     : cooldown text / holder
	text       = {1.00, 1.00, 0.00, 1.00},  -- yellow  : count / macro text
}

--[[ An unmistakable marker around each button.

	Drawn as its own child frame at a high frame level with a magenta 1px edge
	and a translucent green fill. Whatever the real border and backdrop are
	doing, this shows exactly where the plugin thinks the button is. ]]
local function ShowMarker(button)
	local marker = button.cplkDebugMarker
	if not marker then
		marker = CreateFrame("Frame", nil, button)
		marker:SetAllPoints(button)
		marker:SetFrameLevel(button:GetFrameLevel() + 20)
		marker:SetBackdrop({
			bgFile = (E.media and (E.media.blankTex or E.media.blank)) or [[Interface\Buttons\WHITE8X8]],
			edgeFile = (E.media and (E.media.blankTex or E.media.blank)) or [[Interface\Buttons\WHITE8X8]],
			tile = false, tileSize = 0, edgeSize = 1,
			insets = {left = 0, right = 0, top = 0, bottom = 0},
		})
		marker:SetBackdropColor(0, 1, 0, 0.25)
		marker:SetBackdropBorderColor(1, 0, 1, 1)
		button.cplkDebugMarker = marker
	end

	marker:Show()
	marker:SetAllPoints(button)
end

local function HideMarker(button)
	if button.cplkDebugMarker then button.cplkDebugMarker:Hide() end
end

local function out(msg)
	E:Print("|cffff8000[cplk debug]|r " .. tostring(msg))
end

--[[ Every installed addon whose name looks like a copy of this one. ]]
local function FindAddonCopies()
	local copies = {}

	local counter = GetNumAddOns
	local info = GetAddOnInfo
	if type(counter) ~= "function" or type(info) ~= "function" then return copies end

	local ok, total = pcall(counter)
	if not ok or type(total) ~= "number" then return copies end

	for i = 1, total do
		local okName, name = pcall(info, i)
		if okName and type(name) == "string" and name:lower():find("consoleportlk", 1, true) then
			copies[#copies + 1] = name
		end
	end

	return copies
end

local function fmt(...)
	local parts = {}
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		parts[#parts + 1] = tostring(v)
	end
	return table.concat(parts, " ")
end

-------------------------------------------------------------------------------
-- Report
-------------------------------------------------------------------------------
function CPLK:GetDebugReport()
	local db = CPLK:DB()
	local bar = self:GetBar()
	local lines = {}

	local function add(...) lines[#lines + 1] = fmt(...) end

	add("=== ElvUI_ConsolePortLK debug ===")

	local version = "?"
	if GetAddOnMetadata then
		local ok, value = pcall(GetAddOnMetadata, ADDON_NAME, "Version")
		if ok and value then version = value end
	end
	add("|cff00ff00BUILD:|r " .. tostring(self.build) .. "  (hardcoded in Core/Debug.lua - always current)")
	add("folder:", tostring(ADDON_NAME), "| toplevel version:", tostring(version) .. " (may be stale if you overwrote files)")
	add("enabled:", tostring(db.enabled))

	local copies = FindAddonCopies()
	if #copies > 1 then
		add("|cffff0000!! " .. #copies .. " COPIES INSTALLED:|r " .. table.concat(copies, ", "))
		add("|cffff0000!! Remove all but one - they all load and fight.|r")
	elseif #copies == 1 then
		add("copies: 1 (" .. copies[1] .. ")")
	else
		add("copies: (could not enumerate)")
	end
	add("E.mult:", tostring(E.mult), "| E.Border:", tostring(E.Border), "| E.PixelMode:", tostring(E.PixelMode), "| scale:", tostring(E.global and E.global.general and E.global.general.UIScale))
	add("E.TexCoords:", fmt(unpack(E.TexCoords or {})))
	add("E.media.blankTex:", tostring(E.media and E.media.blankTex))
	local bc = (E.media and E.media.backdropcolor) or {}
	local ec = (E.media and E.media.bordercolor) or {}
	add("E.media.backdropcolor:", fmt(bc[1], bc[2], bc[3], bc[4]))
	add("E.media.bordercolor:", fmt(ec[1], ec[2], ec[3], ec[4]))
	add("E.db.general.backdropcolor:", E.db and E.db.general and E.db.general.backdropcolor and fmt(E.db.general.backdropcolor.r, E.db.general.backdropcolor.g, E.db.general.backdropcolor.b) or "nil")
	add("")

	add("--- options ---")
	for _, key in ipairs({"borderSize", "borderOutside", "hideMacroText", "hideCount", "font", "fontSize", "cooldownText", "cooldownUseElvUI", "desaturate", "skinPetRing"}) do
		add(" ", key, "=", tostring(db[key]))
	end
	add("")

	add("--- ConsolePort ---")
	add("bar:", tostring(bar), "| setup:", tostring(_G.ConsolePortBarSetup))
	add("ConsolePort:", tostring(_G.ConsolePort), "| ConsolePortBar:", tostring(_G.ConsolePortBar))
	add("walker found:", tostring(#self:GetActionButtons()), "| pet:", tostring(#self:GetPetButtons()))
	local skinned = 0
	for _ in pairs(self.skinned) do skinned = skinned + 1 end
	add("skinned:", tostring(skinned))
	add("")

	-- Per-button detail, including the icon texture path so empty slots can be
	-- told apart from slots whose art went missing.
	add("--- buttons ---")
	local index = 0
	for button, state in pairs(self.skinned) do
		index = index + 1
		if index > 20 then break end

		local w, h = button:GetWidth(), button:GetHeight()
		local iw = state.icon and state.icon:GetWidth()
		local backdrop = button.cplkBackdrop
		local bd = backdrop and backdrop.GetBackdrop and backdrop:GetBackdrop()

		add(button:GetName() or "(unnamed)")
		add("  size:", fmt(w, "x", h), "| icon:", tostring(iw), "| modifier:", tostring(state.modifier), "| tab:", tostring(state.tab))
		add("  backdrop on:", tostring(backdrop == button and "button" or tostring(backdrop)))
		add("  GetBackdrop:", bd and fmt("edge=", tostring(bd.edgeSize), " bg=", tostring(bd.bgFile)) or "|cffff0000nil|r")
		add("  edgeSize opt:", tostring((tonumber(db.borderSize) or 0)), "-> snapped:", tostring(self:GetBorderSize()))
		local points
		if state.icon and state.icon.GetNumPoints then points = state.icon:GetNumPoints() end
		add("  icon points:", tostring(points))

		-- Cooldown diagnosis: the driver, the frame, and what it reports.
		add("  cooldown driver:", self.cdDriver and (self.cdDriver:GetScript("OnUpdate") and "|cff00ff00running|r" or "|cffff0000no OnUpdate|r") or "|cffff0000not created|r")
		local cd = state.cooldown or (button and button.cooldown)
		add("  cooldown frame:", cd and (cd.GetName and tostring(cd:GetName()) or "unnamed") or "|cffff0000nil|r",
			" hooked=", tostring(cd and cd.cplkHooked or false),
			" noCDCount=", tostring(cd and cd.noCooldownCount or false))
		if cd and self.ReadCooldown then
			local ok, cds, cdd = pcall(function()
				local a, b = self:ReadCooldown(state)
				return a, b
			end)
			local start, duration = cds, cdd
			add("  GetCooldownTimes:", ok and fmt(tostring(start), " + ", tostring(duration)) or "|cffff0000error|r")
			if start and duration then
				add("    remaining:", fmt(tostring(math.max(0, start + duration - GetTime())), "s  active=",
					tostring((duration > 1.5) and (start + duration > GetTime()))))
			end
		end
		local timer = cd and cd.timer
		add("  elvui timer:", timer and (timer:IsShown() and "|cff00ff00shown|r" or "hidden") or "|cffff0000nil|r",
			" text=", tostring(timer and timer.text and timer.text.GetText and timer.text:GetText() or ""))
		add("  elvui mode:", tostring(self:IsElvUICooldownMode()))
		local cdb = E.db.cooldown or {}
		local abcd = (E.db.actionbar and E.db.actionbar.cooldown) or {}
		add("  elvui cd settings:", "enable=", tostring(cdb.enable),
			" threshold=", tostring(cdb.threshold),
			" actionbar.override=", tostring(abcd.override),
			" reverse=", tostring(abcd.reverse))
		-- E:Cooldown_BelowScale hides the text outright when the font scale is
		-- under 0.5 (frames smaller than 18px). Worth seeing in the report.
		local fs = cd and cd.timer and cd.timer.fontScale
		add("  elvui fontScale:", tostring(fs),
			fs and fs < 0.5 and " |cffff0000(<0.5: ElvUI hides this text)|r" or "")
		add("  holder:", state.holder and (state.holder:IsShown() and "|cff00ff00shown|r" or "hidden") or "|cffff0000nil|r",
			" text=", tostring(state.holder and state.holder.text and state.holder.text:GetText() or ""))
		-- Geometry in *screen* pixels: this is what decides whether a border
		-- renders as one pixel or as two half-lit ones.
		local sc = self:ScaleFactor(button)
		local ui = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
		local bw = (button.GetWidth and button:GetWidth()) or 0
		local bh = (button.GetHeight and button:GetHeight()) or 0
		local pw, ph = self:PixelRect(button)
		add("  button:", fmt("w=", tostring(bw), " h=", tostring(bh), " scale=", tostring(sc)))
		add("  pixel grid:", fmt("w=", tostring(pw), " h=", tostring(ph),
			" -> ", tostring(math.floor((pw or bw) * sc / ui + 0.5)), "x",
			tostring(math.floor((ph or bh) * sc / ui + 0.5)), " px"))
		local iw, ih = 0, 0
		if state.icon and state.icon.GetWidth then iw, ih = state.icon:GetWidth() or 0, state.icon:GetHeight() or 0 end
		add("  icon size:", fmt("w=", tostring(iw), " h=", tostring(ih), " (units)"))
		if bd and bd.edgeSize and bd.edgeSize > 0 then
			add("  edge:", fmt(tostring(bd.edgeSize), " units = ",
				tostring(math.floor(bd.edgeSize * sc / ui + 0.5)), " screen px"))
		end
		local tc
		if state.icon and state.icon.GetTexCoord then
			local ok, a, b, c, d = pcall(state.icon.GetTexCoord, state.icon)
			if ok then tc = fmt(a, b, c, d) end
		end
		add("  icon texcoord:", tc or "nil")
			add("  border colour drawn:", fmt(backdrop and backdrop.GetBackdropBorderColor and backdrop:GetBackdropBorderColor() or "?"))
		if backdrop and backdrop ~= button then
			add("  border frame: parent=", tostring(backdrop:GetParent() == button), " level=", tostring(backdrop:GetFrameLevel()), " vs button level=", tostring(button:GetFrameLevel()))
			add("  border shown:", tostring(backdrop:IsShown()), " alpha=", tostring(backdrop:GetAlpha()))
		else
			add("  |cffff0000border frame is the button itself|r")
		end
		add("  textures hidden:", tostring(#state.textures))

		local tex
		if state.icon and state.icon.GetTexture then
			local ok, value = pcall(state.icon.GetTexture, state.icon)
			if ok then tex = value end
		end
		local texName = tostring(tex)
		if texName:find("ability%-empty") or texName:find("EmptyIcon") then
			texName = "|cffff8000EMPTY SLOT|r"
		end
		add("  icon tex:", texName)
	end

	return lines
end

--[[ Shows the report in a scrollable, selectable EditBox.

	Chat scrollback is unreliable here: a long report scrolls away instantly, and
	`E:Print` is easy to lose. A window can be scrolled, and the text can be
	selected and copied with ctrl+a / ctrl+c. ]]
function CPLK:ShowDebugWindow(lines)
	if type(lines) ~= "table" then return end

	local frame = self.debugFrame
	if not frame then
		frame = CreateFrame("Frame", "ElvUI_ConsolePortLK_Debug", UIParent)
		frame:SetSize(620, 420)
		frame:SetPoint("CENTER")
		frame:SetFrameStrata("DIALOG")
		frame:EnableMouse(true)
		frame:SetMovable(true)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", frame.StartMoving)
		frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

		if frame.SetBackdrop then
			frame:SetBackdrop({
				bgFile = "Interface\ChatFrame\ChatFrameBackground",
				edgeFile = "Interface\ChatFrame\ChatFrameBackground",
				tile = false, tileSize = 0, edgeSize = 1,
				insets = {left = 0, right = 0, top = 0, bottom = 0},
			})
			frame:SetBackdropColor(0, 0, 0, 0.9)
			frame:SetBackdropBorderColor(1, 0.5, 0, 1)
		end

		local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		title:SetPoint("TOPLEFT", 10, -10)
		title:SetText("|cffff8000ElvUI_ConsolePortLK|r debug report")
		frame.title = title

		local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -2, -2)

		local scroll = CreateFrame("ScrollFrame", "ElvUI_ConsolePortLK_DebugScroll", frame, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 10, -34)
		scroll:SetPoint("BOTTOMRIGHT", -30, 10)

		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetAutoFocus(false)
		edit:SetFontObject("ChatFontNormal")
		edit:SetWidth(560)
		edit:SetHeight(2000)
		edit:SetScript("OnEscapePressed", function() frame:Hide() end)
		scroll:SetScrollChild(edit)

		frame.edit = edit
		frame.scroll = scroll
		self.debugFrame = frame
	end

	local text = table.concat(lines, "\n")
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
	frame.edit:SetText(text)
	frame.edit:HighlightText()
	frame.edit:SetCursorPosition(0)
	frame:Show()
end

function CPLK:PrintDebugReport()
	local ok, lines = pcall(self.GetDebugReport, self)
	if not ok or type(lines) ~= "table" then
		E:Print("|cffff0000[cplk]|r report failed: " .. tostring(lines))
		return
	end

	-- Always emit one chat line first, so this command can never look silent.
	E:Print("|cffff8000[cplk debug]|r build " .. tostring(self.build) .. " / " .. #lines .. " lines")

	self.lastReport = lines

	-- Window: cannot be lost to chat scrollback.
	local shown, windowErr = pcall(self.ShowDebugWindow, self, lines)
	if shown then
		E:Print("|cffff8000[cplk debug]|r report is in the window - ctrl+a then ctrl+c to copy")
	else
		-- Fall back to chat if the window cannot be built.
		for i = 1, #lines do
			E:Print("|cffaaaaaa" .. tostring(lines[i]) .. "|r")
		end
	end
end

-------------------------------------------------------------------------------
-- Colour overlay
-------------------------------------------------------------------------------
function CPLK:ApplyDebugColors()
	local c = self.DebugColors
	local db = CPLK:DB()

	for button, state in pairs(self.skinned) do
		-- Border: magenta edge, green fill. Both are forced to full alpha so a
		-- border that exists but is invisible shows up immediately.
		local backdrop = button.cplkBackdrop
		if backdrop and backdrop.SetBackdropBorderColor then
			backdrop:SetBackdropBorderColor(unpack(c.border))
		end
		if button.SetBackdropColor then
			button:SetBackdropColor(unpack(c.backdrop))
		end

		-- Icon: keep the art, tint the region so its bounds are obvious.
		if state.icon then
			if state.icon.SetVertexColor then state.icon:SetVertexColor(c.icon[1], c.icon[2], c.icon[3]) end
			state.icon:SetAlpha(1)
		end

		if state.hover then
			state.hover:SetTexture(c.hover[1], c.hover[2], c.hover[3], 0.5)
			if state.hover.SetVertexColor then state.hover:SetVertexColor(unpack(c.hover)) end
			state.hover:SetAlpha(0.35)
		end

		if state.name and state.name.SetTextColor then state.name:SetTextColor(unpack(c.text)) end
		if state.count and state.count.SetTextColor then state.count:SetTextColor(unpack(c.text)) end
		if state.holder and state.holder.SetTextColor then state.holder:SetTextColor(unpack(c.cooldown)) end

		ShowMarker(button)
	end

	-- Buttons that are found but NOT skinned are the interesting case: mark them
	-- in red so a screenshot shows them too.
	for _, button in ipairs(self:GetAllButtons()) do
		if not self.skinned[button] then
			ShowMarker(button)
			if button.cplkDebugMarker then
				button.cplkDebugMarker:SetBackdropBorderColor(1, 0, 0, 1)
				button.cplkDebugMarker:SetBackdropColor(1, 0, 0, 0.25)
			end
		end
	end
end

function CPLK:ClearDebugColors()
	for button in pairs(self.skinned) do HideMarker(button) end
	for _, button in ipairs(self:GetAllButtons()) do HideMarker(button) end

	for button, state in pairs(self.skinned) do
		if state.icon and state.icon.SetVertexColor then state.icon:SetVertexColor(1, 1, 1) end
		if state.hover then
			state.hover:SetTexture(1, 1, 1, 0.3)
			state.hover:SetAlpha(0)
		end
	end

	-- Re-apply the real skin colours.
	self:Refresh()
end

function CPLK:IsDebugOn()
	return self.debugOn == true
end

function CPLK:SetDebug(on)
	on = on and true or false
	if self.debugOn == on then
		out("debug overlay already " .. (on and "on" or "off"))
		return
	end

	self.debugOn = on

	if on then
		self:ApplyDebugColors()
		local painted = 0
		for _ in pairs(self.skinned) do painted = painted + 1 end
		out("painted " .. painted .. " buttons")
		out("|cff00ff00ON|r - magenta = border edge, green = backdrop fill,")
		out("orange = icon bounds, blue = hover, red = cooldown text, yellow = count/macro text")
		out("every button is outlined |cffff00ffmagenta|r (skinned) or |cffff0000red|r (not skinned)")
		out("the outline is drawn on top of everything - it is the button's real bounds")
		out("Take a screenshot, then run |cffffd100/cplk debug off|r")
	else
		self:ClearDebugColors()
		out("|cffff0000OFF|r - colours restored")
	end
end

-- Keep the colours on while the overlay is active, and make sure buttons picked
-- up later are painted too.
function CPLK:HookDebugIntoSkin()
	if self.debugHooked then return end
	self.debugHooked = true

	local apply = self.ApplySkin
	self.ApplySkin = function(module, ...)
		local result = apply(module, ...)
		if module.debugOn then module:ApplyDebugColors() end
		return result
	end
end

function CPLK:HandleDebugCommand(rest)
	local arg = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

	if arg == "window" then
		if not self.lastReport then self:GetDebugReport() end
		self:PrintDebugReport()
		return
	elseif arg == "saved" then
		if not self.lastReport then
			out("no saved report - run |cffffd100/cplk debug report|r first")
			return
		end
		for i = 1, #self.lastReport do
			E:Print("|cffaaaaaa" .. tostring(self.lastReport[i]) .. "|r")
		end
	elseif arg == "on" then
		self:HookDebugIntoSkin()
		self:SetDebug(true)
	elseif arg == "off" then
		self:SetDebug(false)
	elseif arg == "report" then
		self:PrintDebugReport()
	else
		self:HookDebugIntoSkin()
		self:SetDebug(not self.debugOn)
	end
end
