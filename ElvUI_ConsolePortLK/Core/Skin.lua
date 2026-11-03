local E, L, V, P, G = unpack(ElvUI); --Import: Engine, Locales, PrivateDB, ProfileDB, GlobalDB

if not E then return end

local CPLK = E:GetModule("ConsolePortLK")
local LSM = E.Libs.LSM

--Lua functions
local format, floor, ceil = string.format, math.floor, math.ceil
local pairs, ipairs, unpack, type, tonumber = pairs, ipairs, unpack, type, tonumber
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local CreateFrame = CreateFrame
local GetTime = GetTime

-- How much of the button the icon covers, as a fraction that is trimmed from
-- every edge. ConsolePort's square art leaves a margin around the icon, the
-- round art does not. Everything else is derived from this.
local INSET_MAIN = 0.055
local INSET_SATELLITE = 0.0

-- Minimum duration before cooldown text shows up (same as ElvUI and CPCC).
-- ElvUI's own floor (Core/Cooldowns.lua): anything shorter - the global
-- cooldown included - gets no numbers, exactly like an ElvUI action button.
local MIN_DURATION = 1.5

-- How often the cooldown driver re-reads the cooldown frames. ConsolePort's own
-- CPCC uses the same 0.05s tick.
local POLL_INTERVAL = 0.05

local GetButtonTab
do
	-- ConsolePortBar stores the button family on the frame; fall back to the
	-- ConsolePort settings if it has not been stamped yet.
	function GetButtonTab(button)
		local setup = CPLK:GetSettings()
		local useSquare = (setup and setup.useSquareButtons) or (button and button.isSquareMode)
		return useSquare and "square" or "round"
	end
end

-------------------------------------------------------------------------------
-- Text styling helpers
-------------------------------------------------------------------------------
local function FetchFont()
	local db = CPLK:DB()
	local actionbar = E.db.actionbar or {}

	if db.font then
		return LSM:Fetch("font", actionbar.font, true) or LSM:Fetch("font", "PT Sans Narrow", true)
	end

	return _G.STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]]
end

--[[ Clear a FontString without tripping over "Font not set".

	On 3.3.5a `SetText` on a FontString that has no font throws, and the error
	aborts the calling function - which meant our own holder text could prevent
	ElvUI's timer from ever being created. Every place that clears text goes
	through here, and a font is attached first if one is missing.
]]
function CPLK:SafeSetText(fontString, text)
	if not fontString or not fontString.SetText then return end

	if fontString.GetFont and not fontString:GetFont() then
		local ok = pcall(function() CPLK:StyleFont(fontString, 10) end)
		if not ok then return end
	end

	pcall(fontString.SetText, fontString, text)
end

function CPLK:StyleFont(fontString, size)
	if not fontString then return end

	local db = CPLK:DB()
	local outline = db.fontOutline or "OUTLINE"
	if outline == "NONE" then outline = nil end

	local font = FetchFont()
	if fontString.SetFont then
		fontString:SetFont(font, size or db.fontSize or 10, outline)
	else
		return
	end

	if fontString.SetShadowOffset then
		if outline then
			fontString:SetShadowOffset(0, 0)
		else
			local mult = E.mult or 1
			fontString:SetShadowOffset(mult, -mult)
		end
	end
end

-------------------------------------------------------------------------------
-- ElvUI cooldown text formatting
-------------------------------------------------------------------------------
local function ManualFormat(remaining, db)
	local threshold = tonumber(db.cooldownThreshold) or 3

	if remaining < 60 then
		if remaining >= threshold then
			return format("%ds", floor(remaining)), 3
		end
		return format("%.1fs", remaining), 4
	elseif remaining < 3600 then
		return format("%dm", ceil(remaining / 60)), 2
	end

	return format("%dh", ceil(remaining / 3600)), 1
end

function CPLK:FormatCooldownText(remaining)
	local db = CPLK:DB()

	if db.cooldownUseElvUI and E.GetTimeInfo and E.TimeFormats then
		local actionbar = E.db.actionbar or {}
		local abCooldown = actionbar.cooldown or {}
		local threshold = abCooldown.threshold or (E.db.cooldown and E.db.cooldown.threshold) or 3

		local value, styleID, _, remainder = E:GetTimeInfo(remaining, threshold, nil, nil)
		local style = styleID and E.TimeFormats[styleID]
		if value and style then
			local useIndicator = E.db.cooldown and E.db.cooldown.useIndicatorColor
			local indicator = useIndicator and E.TimeIndicatorColors and E.TimeIndicatorColors[styleID]

			local text
			if indicator then
				text = format(style[2], value, indicator, remainder)
			else
				text = format(style[1], value, remainder)
			end

			local color
			if not indicator and E.TimeColors then
				color = E.TimeColors[styleID]
			end

			return text, color
		end
	end

	-- Manual mode, or ElvUI internals were unavailable.
	local text, styleID = ManualFormat(remaining, db)
	local color = E.TimeColors and E.TimeColors[styleID]
	return text, color
end

--[[ ElvUI's own cooldown text, driven by ElvUI's OnUpdate.

	This is the whole point of the "use ElvUI cooldown timers" option: the text
	is not merely formatted the way ElvUI formats it, it is written by ElvUI's
	own handler, so the global cooldown settings (enable, threshold, seconds,
	indicator colours, custom font) all apply for real and change live without
	a reload.
]]
function CPLK:OnElvUICooldownUpdate(holder, elapsed)
	-- ElvUI's own timer has its own OnUpdate; the holder must not compete.
	if holder.cplkElvUI then return end

	-- Our own holder, formatted with ElvUI's settings.
	holder.elapsed = (holder.elapsed or 0) + elapsed
	if holder.elapsed < 0.1 then return end
	holder.elapsed = 0

	local endTime = holder.endTime
	if not endTime then
		holder:Hide()
		return
	end

	local remaining = endTime - GetTime()
	if remaining <= 0 then
		holder.endTime = nil
		holder:Hide()
	else
		local text, color = CPLK:FormatCooldownText(remaining)
		if text then
			holder.text:SetText(text)
			if color then
				holder.text:SetTextColor(color.r, color.g, color.b)
			end
		end
	end

	local button = holder.button
	if button and CPLK:DB().desaturate and button.icon then
		button.icon:SetDesaturated(remaining > 0)
	end
end

function CPLK:OnTextUpdate(holder, elapsed)
	self:OnElvUICooldownUpdate(holder, elapsed)
end

--[[ A cooldown text frame for one button.

	Two modes, both drawn on top of ConsolePort's own cooldown frame:
	  * ElvUI mode - ElvUI's cooldown timer is nested inside our holder and the
	    holder carries ElvUI's `parent` fields, so ElvUI's own OnUpdate writes
	    the text. Nothing else in the addon touches it.
	  * Manual mode - our own OnUpdate formats the text.
	The holder is transparent and empty, so ignoring mouse input on it is safe.
]]
function CPLK:TextHolder(button)
	local state = self.skinned[button]
	if not state then return end
	if state.holder then return state.holder end

	if not self.textHolders then self.textHolders = {} end

	local parent = state.owner or button
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetAllPoints(parent)
	holder:SetFrameLevel(parent:GetFrameLevel() + 12)
	holder.button = button

	local text = holder:CreateFontString(nil, "OVERLAY")
	text:SetPoint("CENTER", holder, "CENTER", 0, 1)
	text:SetJustifyH("CENTER")
	-- Give it a font immediately: on 3.3.5a a font-less FontString throws on
	-- SetText ("Font not set") and that error escapes the caller.
	pcall(self.StyleFont, self, text, (self:DB() and self:DB().cooldownFontSize) or 10)
	holder.text = text

	holder:SetScript("OnUpdate", function(self2, elapsed)
		CPLK:OnTextUpdate(self2, elapsed)
	end)
	holder:EnableMouse(false)
	holder:Hide()

	state.holder = holder
	self.textHolders[button] = holder
	return holder
end

-- ElvUI scales its cooldown font with the button size (FONT_SIZE units at a
-- 36 pixel icon). ConsolePort buttons are bigger, so the same ratio is applied
-- here with a sane clamp. A custom size is used as-is.
local function CooldownFontSize(button)
	local db = CPLK:DB()

	if not db.cooldownUseElvUI then
		return tonumber(db.cooldownFontSize) or 12
	end

	local base = (E.db.actionbar and E.db.actionbar.fontSize) or 10
	local width = button and button.GetWidth and button:GetWidth() or 36
	local scale = math.min(math.max((width or 36) / 36, 0.5), 1.8)

	return math.max(6, base * scale)
end

function CPLK:UpdateTextStyle(button)
	local state = self.skinned[button]
	if not state or not state.holder then return end

	local holder = state.holder

	-- In ElvUI mode the nested ElvUI timer owns the font; touching it here
	-- would only fight ElvUI (and its own holder text must stay empty).
	if holder.cplkElvUI then
		self:SafeSetText(holder.text, "")
		return
	end

	self:StyleFont(holder.text, CooldownFontSize(state.owner or button))
end

-------------------------------------------------------------------------------
-- Cooldown driving
--
-- Hooking ConsolePort's cooldown frame is not enough to make text appear: the
-- frame is created and handed over by ConsolePort after the skin is applied,
-- ConsolePort re-points `button.cooldown` when it rebuilds a bar, and cooldowns
-- that are already running when the hooks land never fire SetCooldown at all.
-- ConsolePort's own cooldown text abandoned hooks for the same reason ("the
-- previous implementation ... meant square/slice modes had no reliable text
-- driver") and now polls one throttled driver frame.
--
-- So this does the same: one driver frame reads the cooldown frames directly
-- (GetCooldownTimes), which is authoritative whatever set them, and only
-- (re)starts a text timer when the cooldown actually changed.
-------------------------------------------------------------------------------
function CPLK:ReadCooldown(state)
	local cd = state and state.cooldown
	if not cd then return end

	-- Authoritative when available: this reports what the frame is *actually*
	-- showing, whoever set it.
	if cd.GetCooldownTimes then
		local ok, start, duration, enable = pcall(cd.GetCooldownTimes, cd)
		if ok and duration then
			-- 3.3.5a reports milliseconds here; some builds report seconds.
			if duration > 1000 then start, duration = start / 1000, duration / 1000 end

			if duration > 0 and (enable == nil or enable == true or enable == 1) then
				return start, duration
			end
		end
	end

	-- Fallback: the last values the frame was given, which ConsolePort and
	-- ElvUI both cache on the frame.
	local start, duration = cd.cplkStart, cd.cplkDuration
	if not duration or duration <= 0 then
		start, duration = cd.start, cd.duration
	end

	if not start or not duration or duration <= 0 then return end
	if cd.noCooldownCount and cd.cplkStart == nil then return end

	return start, duration
end

function CPLK:PollCooldowns()
	local db = self:DB()
	if not db then return end

	local button, state

	for button, state in pairs(self.skinned) do
		local cd = state.cooldown or button.cooldown
		if cd and not state.cooldown then state.cooldown = cd end

		if cd and not cd.cplkHooked then
			-- ConsolePort swapped or created the frame after we skinned it.
			self:HookCooldown(cd, button)
		end

		local start, duration = self:ReadCooldown(state)

		if cd then cd.cplkStart, cd.cplkDuration = start, duration end

		local active = start and duration and duration > MIN_DURATION
			and (start + duration) > GetTime()

		if active then
			-- Only restart the timer when this is a different cooldown, so the
			-- text is not rebuilt every tick.
			if state.cdStart ~= start or state.cdDuration ~= duration then
				state.cdStart, state.cdDuration = start, duration
				self:StartCooldownText(button, start, duration, true)
			end
		elseif state.cdStart then
			state.cdStart, state.cdDuration = nil, nil
			self:StopCooldownText(button)
			if db.desaturate and state.icon then state.icon:SetDesaturated(false) end
		end
	end
end

function CPLK:CooldownDriver()
	if self.cdDriver then
		self.cdDriver:Show()
		return self.cdDriver
	end

	local driver = CreateFrame("Frame", nil, UIParent)
	driver.elapsed = 0
	driver:SetScript("OnUpdate", function(frame, elapsed)
		frame.elapsed = frame.elapsed + elapsed
		if frame.elapsed < POLL_INTERVAL then return end
		frame.elapsed = 0
		-- One bad button must not stop the driver for the whole bar.
		pcall(CPLK.PollCooldowns, CPLK)
	end)

	self.cdDriver = driver
	return driver
end

function CPLK:StopCooldownDriver()
	if self.cdDriver then
		self.cdDriver:SetScript("OnUpdate", nil)
		self.cdDriver:Hide()
		self.cdDriver = nil
	end
end

-------------------------------------------------------------------------------
-- Cooldown handling
-------------------------------------------------------------------------------
--[[ Switches one button between ElvUI's cooldown text and our own.

	Called when the option changes so the switch is immediate - a running
	cooldown is restarted in the new mode instead of waiting for the next one.
]]
function CPLK:SyncCooldownMode(button, state)
	local cd = state and state.cooldown
	if not cd then return end

	local want = self:IsElvUICooldownMode()
	local holder = self.textHolders and self.textHolders[button]
	if not holder then return end
	if (want and holder.cplkElvUI) or (not want and not holder.cplkElvUI) then return end

	local start, duration = cd.cplkStart, cd.cplkDuration
	self:StopCooldownText(button)
	holder.cplkElvUI = nil

	if start and duration and (start + duration) > GetTime() then
		self:StartCooldownText(button, start, duration)
	end
end

function CPLK:StopCooldownText(button)
	local holder = self.textHolders[button]
	if not holder or not holder.text then return end

	holder.endTime = nil
	if holder.cplkElvUI then
		local timer = holder.cplkCooldown and holder.cplkCooldown.timer
		if timer then
			timer.endTime = nil
			timer.enabled = nil
			if timer.text then self:SafeSetText(timer.text, "") end
			timer:Hide()
		end
		holder:Hide()
	else
		self:SafeSetText(holder.text, "")
		holder:Hide()
	end
end

--[[ Does this option want ElvUI to draw the cooldown text?

	Required before anything else: ConsolePort sets `cooldown.noCooldownCount`
	from its own setting, and ElvUI refuses to register a cooldown frame with
	`noCooldownCount` set. Whoever owns the text clears it, so it has to be
	cleared before ElvUI is asked to draw anything.
]]
function CPLK:IsElvUICooldownMode()
	local db = self:DB()
	return (db and db.cooldownUseElvUI) and true or false
end

function CPLK:ClearNoCooldownCount(button, cooldown)
	if not self:IsElvUICooldownMode() then return end

	local cd = cooldown or (self.skinned[button] and self.skinned[button].cooldown)
	if cd then cd.noCooldownCount = nil end
	if button and button.cooldown then button.cooldown.noCooldownCount = nil end
end

--[[ Hand the cooldown frame to ElvUI.

	This mirrors ElvUI's own `E:CreateCooldownTimer(parent)` (Core/Cooldowns.lua)
	and `E:OnSetCooldown` so the text is produced by ElvUI's own cooldown
	machinery - the same code path as every ElvUI action button. The timer is
	parented to our transparent holder so it sits above ConsolePort's swipe and
	cannot draw over a satellite.

	Returns the timer frame, or nil if ElvUI's cooldown module is unavailable.
]]
function CPLK:UseElvUICooldown(button, cooldown)
	if not (E.Cooldown_OnUpdate and E.Cooldown_Options and E.TimeFormats and E.GetTimeInfo) then return end

	local cd = cooldown or (self.skinned[button] and self.skinned[button].cooldown)
	if not cd or not cd.SetCooldown then return end

	local holder = self:TextHolder(button)
	if not holder then return end

	-- ElvUI skips `noCooldownCount` frames entirely; ConsolePort sets it from
	-- its own "cooldown text" setting. ElvUI owns the text from here on.
	cd.noCooldownCount = nil

	local timer = cd.timer
	if not timer then
		timer = CreateFrame("Frame", nil, holder) --[[@as Frame]]
		timer:SetFrameLevel(holder:GetFrameLevel() + 1)

		local text = timer:CreateFontString(nil, "OVERLAY")
		text:SetJustifyH("CENTER")
		text:SetJustifyV("MIDDLE")
		text:SetPoint("CENTER", timer, "CENTER", 1, 1)
		-- ElvUI's FontTemplate is mixed into every font string; calling it now
		-- means the string has a font even if ElvUI's sizing never runs.
		if text.FontTemplate then
			pcall(text.FontTemplate, text, nil, 12, "OUTLINE")
		else
			pcall(self.StyleFont, self, text, 12)
		end
		timer.text = text

		cd.timer = timer
	end

	timer:ClearAllPoints()
	timer:SetParent(holder)
	timer:SetAllPoints(holder)
	timer.parent = cd
	timer:SetScript("OnUpdate", E.Cooldown_OnUpdate)

	holder.cplkElvUI = true
	holder.cplkCooldown = cd
	holder.endTime = nil

	-- Same order as ElvUI's CreateCooldownTimer: options, then the size driven
	-- font, then the update loop.
	local parentDb = (cd.CooldownOverride and E.db[cd.CooldownOverride])
		or (E.db.actionbar and E.db.actionbar.cooldown)
		or (E.db.cooldown)

	-- ElvUI sizes the font from the frame width; a zero width would make it
	-- hide the text outright, so fall back to the button's own width.
	local width = holder:GetWidth()
	if not width or width <= 0 then width = button.GetWidth and button:GetWidth() end
	if not width or width <= 0 then width = 32 end

	pcall(E.Cooldown_Options, E, timer, parentDb or {}, cd)
	pcall(E.Cooldown_OnSizeChanged, E, timer, width, true)
	timer.noCooldownCount = nil

	holder:Show()
	return timer
end

function CPLK:StartCooldownText(button, start, duration, fromPoll)
	local state = self.skinned[button]
	if not state then return end

	local db = CPLK:DB()
	if not db.enabled or not db.cooldownText or not start or not duration or duration <= MIN_DURATION then
		self:StopCooldownText(button)
		if db.desaturate and state.icon then state.icon:SetDesaturated(false) end
		return
	end

	-- Remember the raw values: ElvUI may be hooked up after ConsolePort already
	-- started the cooldown, and the manual mode needs them too.
	local cooldown = state.cooldown
	if cooldown then
		cooldown.cplkStart = start
		cooldown.cplkDuration = duration
	end

	if self:IsElvUICooldownMode() then
		local timer = self:UseElvUICooldown(button, cooldown)
		if timer then
			-- The same fields and order as E:OnSetCooldown.
			local holder = self.textHolders[button]
			if holder then
				holder.start, holder.duration = start, duration
				holder.endTime = start + duration
			end

			timer.start = start
			timer.duration = duration
			timer.endTime = start + duration
			timer.endCooldown = timer.endTime - 0.05
			timer.nextUpdate = -1
			timer:Show()

			-- Paint the first value right away instead of waiting a frame.
			local painted = pcall(E.Cooldown_OnUpdate, timer, 0.2)
			local drew = timer.text and timer.text.GetText and (timer.text:GetText() or "") ~= ""
			if not painted or not drew then
				-- ElvUI's handler failed or drew nothing: fall back to our own
				-- formatter so the player still sees the timer.
				local text = self:FormatCooldownText((start + duration) - GetTime())
				if text then self:SafeSetText(timer.text, text) end
			end

			if db.desaturate and state.icon then state.icon:SetDesaturated(true) end
			return
		end
		-- ElvUI's cooldown module is unavailable: fall through to manual text.
	end

	local holder = self:TextHolder(button)
	if not holder then return end
	holder.cplkElvUI = nil

	holder.start = start
	holder.duration = duration
	holder.endTime = start + duration
	holder.elapsed = 1 -- force an immediate update
	holder:Show()
	self:UpdateTextStyle(button)
	self:OnTextUpdate(holder, 0)

	if db.desaturate and state.icon then
		state.icon:SetDesaturated(true)
	end
end

function CPLK:OwnerOf(cooldown)
	local button = cooldown and cooldown.CPCCOwner or (cooldown and cooldown:GetParent())
	if button and self.skinned[button] then return button end

	-- Satellites can hand the cooldown frame to a different action button.
	local parent = cooldown and cooldown:GetParent()
	while parent do
		if self.skinned[parent] then return parent end
		parent = parent.GetParent and parent:GetParent()
	end
end

--[[ ConsolePort never calls SetSwipeColor itself, so the stock swipe is
	white. Only touch the colour when the option actually flips, so a reload or
	a ConsolePort restyle does not fight us. ]]
function CPLK:ApplySwipe(state)
	local cooldown = state and state.cooldown
	if not cooldown or not cooldown.SetSwipeColor then return end

	if CPLK:DB().swipe then
		if cooldown.cplkSwipeHidden then
			cooldown:SetSwipeColor(1, 1, 1, 1)
			cooldown.cplkSwipeHidden = nil
		end
	elseif not cooldown.cplkSwipeHidden then
		cooldown:SetSwipeColor(0, 0, 0, 0)
		cooldown.cplkSwipeHidden = true
	end
end

--[[ SetCooldown fired on a ConsolePort cooldown frame.

	Deliberately does *not* start the text from the hook's own arguments: the
	frame may not be the one the button is using (`OwnerOf` can fail), and the
	arguments may belong to a different button sharing the frame. The driver
	re-reads the frame instead, so the text always matches what the button is
	actually showing.
]]
function CPLK:OnCooldownSet(cooldown, start, duration, enable)
	local button = self:OwnerOf(cooldown)

	if not button then
		-- Unknown owner: make sure the driver is running so it is picked up on
		-- the next tick (this is the common case for satellites and flyouts).
		self:CooldownDriver()
		return
	end

	-- Cheap path: show/refresh immediately instead of waiting up to 50ms.
	if enable ~= nil and (enable == 0 or enable == false) then
		if self.skinned[button] then self.skinned[button].cdStart = nil end
		self:StopCooldownText(button)
		return
	end

	self:StartCooldownText(button, start, duration, true)
end

function CPLK:HookCooldown(cooldown, button)
	if not cooldown or cooldown.cplkHooked then return end
	cooldown.cplkHooked = true
	cooldown.CPCCOwner = button

	hooksecurefunc(cooldown, "SetCooldown", function(cd, start, duration, enable)
		CPLK:OnCooldownSet(cd, start, duration, enable)
	end)

	hooksecurefunc(cooldown, "Hide", function(cd)
		local owner = CPLK:OwnerOf(cd)
		if owner then CPLK:StopCooldownText(owner) end
	end)
end

-------------------------------------------------------------------------------
-- CPCC (ConsolePort's own cooldown text) ownership
-------------------------------------------------------------------------------
function CPLK:IsOwningCooldownText()
	local db = CPLK:DB()
	return (db.enabled and db.cooldownText) and true or false
end

function CPLK:SuppressCPCC()
	local cpcc = self:GetCPCC()
	if not cpcc then return end

	if cpcc.db then cpcc.db.enabled = false end
	for _, holder in pairs(cpcc.texts or {}) do
		if holder then holder:Hide() end
	end
	for name, meta in pairs(cpcc.meta or {}) do
		if meta then meta.visible = false end
	end
end

function CPLK:RestoreCPCC()
	local cpcc = self:GetCPCC()
	if not cpcc then return end

	local setup = self:GetSettings()
	if setup and setup.enablecooldowntext then
		if cpcc.db then cpcc.db.enabled = true end
	else
		if cpcc.db then cpcc.db.enabled = false end
	end
end

function CPLK:HookCPCC()
	local cpcc = self:GetCPCC()
	if not cpcc or cpcc.cplkHooked then return end
	cpcc.cplkHooked = true

	hooksecurefunc(cpcc, "Enable", function()
		if CPLK:IsOwningCooldownText() then
			CPLK:SuppressCPCC()
		end
	end)

	hooksecurefunc(cpcc, "Disable", function()
		if not CPLK:IsOwningCooldownText() then
			CPLK:RestoreCPCC()
		end
	end)

	-- CPCC still *creates* its countdown frames while disabled (StartCooldown
	-- only checks meta, not db.enabled), so hide them again right away instead
	-- of letting an empty CPCC frame sit on top of our own text.
	if cpcc.StartCooldown then
		hooksecurefunc(cpcc, "StartCooldown", function()
			if CPLK:IsOwningCooldownText() then
				CPLK:SuppressCPCC()
			end
		end)
	end
end

function CPLK:ApplyCooldownOwner()
	self:HookCPCC()

	if self:IsOwningCooldownText() then
		self:SuppressCPCC()
	else
		self:RestoreCPCC()
	end
end

-------------------------------------------------------------------------------
-- Border / icon geometry
--
-- Mirrors how an ElvUI action button is built: a dark backdrop frame with a
-- one pixel (scaled) edge, and the spell icon sitting inside it. The border
-- itself is hidden from ConsolePort so nothing is drawn twice.
-------------------------------------------------------------------------------
--[[ ElvUI's `E.Border` is `E.mult * 2` unless pixel mode is on, so using it as
	an offset draws a two-pixel band on some edges and one pixel on others. Both
	the edge thickness and the outside offset are snapped through `E:Scale`
	instead, so a 1px border is 1px on all four sides. ]]
--[[ `E.media.blankTex` is the texture ElvUI itself uses for backdrops. It can be
	missing if ElvUI has not finished loading its media, and a backdrop with no
	background texture renders as a hole through to the world. ]]
local function BlankTex()
	return (E.media and (E.media.blankTex or E.media.blank)) or [[Interface\Buttons\WHITE8X8]]
end

local function MediaColour(...)
	local c = ...
	if type(c) ~= "table" then return 1, 1, 1 end
	return c[1] or c.r or 1, c[2] or c.g or 1, c[3] or c.b or 1
end

--[[ ElvUI's backdrop colour. `E.media.backdropcolor` only carries three values
	(no alpha), so alpha is supplied explicitly. ]]
local function BackdropRGB()
	local r, g, b = MediaColour(E.media and E.media.backdropcolor)
	return r, g, b, 1
end

local function Luminance(r, g, b)
	return (0.299 * r) + (0.587 * g) + (0.114 * b)
end

--[[ ElvUI's border colour, verbatim. This is what "inherit from ElvUI" means.

	It is pure black on many profiles - including the one this plugin was
	reported against - and the backdrop is near-black too, which is why the
	border looked like it was not being drawn at all. The user can override it
	with the Border Colour option.
]]
local function ElvUIBorderRGB()
	local db = CPLK:DB()
	local r, g, b = MediaColour(E.media and E.media.bordercolor)

	-- Inherit ElvUI's colour. If it is indistinguishable from the backdrop -
	-- which it is on a stock profile, where both are near-black - lift it to a
	-- visible grey. `borderAutoContrast = false` keeps the raw theme colour.
	if db.borderAutoContrast ~= false then
		local br, bg, bb = MediaColour(E.media and E.media.backdropcolor)
		local backdropLum = Luminance(br, bg, bb)

		if math.abs(Luminance(r, g, b) - backdropLum) < 0.15 then
			if backdropLum < 0.5 then
				r, g, b = 0.55, 0.55, 0.55
			else
				r, g, b = 0.08, 0.08, 0.08
			end
		end
	end

	return r, g, b, 1
end

--[[ The player's class colour, used for the hover / pressed highlight. ]]
local function ClassColourRGB()
	local db = CPLK:DB()

	if type(db.hoverColor) == "table" then
		local r, g, b = MediaColour(db.hoverColor)
		return r, g, b, 1
	end

	local classColour = (E.myclass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[E.myclass])
	if classColour then return classColour.r, classColour.g, classColour.b, 1 end

	local r, g, b = MediaColour(E.media and E.media.rgbvaluecolor)
	return r, g, b, 1
end

--[[ The border colour currently in effect for a button, honouring the override
	and the hover/pressed state. ]]
local function ActiveBorderRGB(state)
	local db = CPLK:DB()

	local function baseRGB()
		if type(db.borderColor) == "table" then
			local r, g, b = MediaColour(db.borderColor)
			return r, g, b, 1
		end

		return ElvUIBorderRGB()
	end

	if state and (state.hovered or state.pressed) then
		if db.hoverUseClassColor ~= false then return ClassColourRGB() end
		return baseRGB()
	end

	return baseRGB()
end

local function BorderSize()
	local db = CPLK:DB()
	local size = tonumber(db.borderSize) or 0
	if size < 0 then size = 0 end
	if size == 0 then return 0 end

	-- Never below one physical pixel. With E.mult < 1 and pixel mode on, a
	-- snapped 1px option becomes 0.96, and a backdrop edge thinner than one
	-- pixel does not render at all.
	return math.max(E:Scale(size), E.mult or 1, 1)
end

--[[ The border thickness in screen pixels, snapped the way ElvUI snaps. ]]
function CPLK:GetBorderSize()
	return BorderSize()
end

--[[ The edge thickness, converted from screen pixels to frame units.

	A frame's own units are multiplied by its effective scale, and ConsolePort
	scales its buttons (`cfg.scale`, plus ElvUI's own pixel scale). A 1-unit
	edge on a button at 0.96 scale renders as 0.96 of a pixel, which the GPU
	spreads over two - the "some borders are 2 pixels" report: the buttons that
	landed on a fraction of a pixel got a doubled border, the lucky ones did
	not.

	So the thickness is *chosen* in whole screen pixels and then divided by the
	button's effective scale, giving an edge that covers exactly that many real
	pixels on every side, on every button, at any bar scale.
]]
function CPLK:EdgeSizeFor(button, size)
	if not size or size <= 0 then return 0 end

	local scale = 1
	if button and button.GetEffectiveScale and UIParent and UIParent.GetEffectiveScale then
		local ui = UIParent:GetEffectiveScale()
		local own = button:GetEffectiveScale()
		if ui and own and ui > 0 and own > 0 then scale = own / ui end
	end
	if not scale or scale <= 0 then scale = 1 end

	-- Whole screen pixels: at least the requested size, never a fraction.
	local pixels = math.floor(size + 0.5)
	if pixels < 1 then pixels = 1 end

	local edge = pixels / scale
	if edge < 1 then edge = 1 end

	return edge, pixels
end

--[[ The button's size rounded to whole screen pixels, in frame units.

	ConsolePort sizes its buttons from its own layout (32, 18.4, 10.35 ...),
	which is rarely a whole number of screen pixels. A frame whose edges fall
	between two pixels anti-aliases its border across both of them, so a 1 pixel
	border *renders* as two half-lit pixels. That is why only some buttons
	looked 2 pixels thick: the ones that happened to land on a fraction.

	Rounding the size (and the icon inside it) onto the pixel grid makes every
	border cover exactly one pixel, on every button, at any bar scale.
]]
function CPLK:ScaleFactor(button)
	local scale = 1
	if button and button.GetEffectiveScale and UIParent and UIParent.GetEffectiveScale then
		local ui = UIParent:GetEffectiveScale()
		local own = button:GetEffectiveScale()
		if ui and own and ui > 0 and own > 0 then scale = own / ui end
	end
	return (scale and scale > 0) and scale or 1
end

function CPLK:PixelRect(button)
	local width, height = button:GetWidth(), button:GetHeight()
	if not width or not height or width <= 0 or height <= 0 then return end

	local scale = self:ScaleFactor(button)

	local w = math.floor(width * scale + 0.5) / scale
	local h = math.floor(height * scale + 0.5) / scale

	return w, h, scale
end

function CPLK:SetBackdropEdge(backdrop, size, edgeSize)
	if not backdrop then return end

	local edge = edgeSize or size
	local applied = backdrop.GetBackdrop and backdrop:GetBackdrop()
	if applied and applied.edgeSize == edge and backdrop.cplkEdgeSize == edge then return end
	backdrop.cplkEdgeSize = edge
	backdrop.cplkEdgePixels = edgeSize and math.floor((edge * (backdrop.GetScale and backdrop:GetScale() or 1)) + 0.5) or edge

	backdrop:SetBackdrop({
		bgFile = BlankTex(),
		edgeFile = BlankTex(),
		tile = false,
		tileSize = 0,
		edgeSize = (edge > 0) and edge or 1,
		insets = {left = 0, right = 0, top = 0, bottom = 0},
	})
end

--[[ The button backdrop, made exactly the way ElvUI makes its action buttons.

	ElvUI's own action button styling is, from Modules/ActionBars/ActionBars.lua:

		button:CreateBackdrop(template, true)
		button.backdrop:SetAllPoints()
		icon:SetTexCoord(unpack(E.TexCoords))
		icon:SetInside()
		button:StyleButton()

	so this uses `CreateBackdrop` and `SetAllPoints` rather than hand-built
	frames with invented insets. That is what "look exactly like ElvUI action
	buttons" means, and it is what the earlier hand-rolled attempts kept getting
	wrong.
]]
function CPLK:BackdropTemplate()
	local db = CPLK:DB()

	if db.backdropTemplate == "Transparent" then return "Transparent" end
	if db.backdropTemplate == "Default" then return "Default" end

	-- Follow the user's ElvUI action bar setting by default.
	local actionbar = E.db and E.db.actionbar
	if actionbar and actionbar.transparentButtons then return "Transparent" end

	return "Default"
end

function CPLK:CreateBorder(button)
	if button.cplkBackdrop then return button.cplkBackdrop end

	local template = self:BackdropTemplate()

	-- ElvUI's own path. `CreateBackdrop` is mixed into every frame by ElvUI's
	-- toolkit and creates `button.backdrop` sized to the button.
	if type(button.CreateBackdrop) == "function" then
		local ok = pcall(button.CreateBackdrop, button, template, true)

		if ok and button.backdrop and button.backdrop.SetBackdrop then
			button.backdrop:SetAllPoints(button)
			button.cplkBackdrop = button.backdrop
			button.backdrop.cplkElvUI = true
			return button.backdrop
		end
	end

	-- Fallback: identical construction, for when the mixin is unavailable.
	local backdrop = CreateFrame("Frame", nil, button)
	backdrop:SetAllPoints(button)
	backdrop:SetFrameLevel(math.max(0, button:GetFrameLevel() - 1))

	backdrop:SetBackdrop({
		bgFile = BlankTex(),
		edgeFile = BlankTex(),
		tile = false, tileSize = 0,
		edgeSize = (E.mult or 1),
		insets = {left = 0, right = 0, top = 0, bottom = 0},
	})
	backdrop:SetBackdropColor(BackdropRGB())
	backdrop:SetBackdropBorderColor(ElvUIBorderRGB())

	E.frames[backdrop] = true
	backdrop.template = template
	button.cplkBackdrop = backdrop

	return backdrop
end

--[[ The pet ring centre is a single frame with no wrappers under it, so it
	gets a real child frame like before. ]]
function CPLK:CreatePetBorder(pet)
	local backdrop = CreateFrame("Frame", nil, pet)
	backdrop:SetFrameLevel(math.max(0, pet:GetFrameLevel() - 1))
	backdrop:SetBackdropColor(unpack(E.media.backdropcolor))
	backdrop:SetBackdropBorderColor(unpack(E.media.bordercolor))

	E.frames[backdrop] = true
	backdrop.template = "Default"

	pet.cplkBackdrop = backdrop
	return backdrop
end

--[[ WoW's `GetRegions()` returns *multiple values*, not a table.

	The first version of this sweep did `local ok, regions = pcall(...)` and then
	iterated `regions` with `ipairs`, so in the live client it silently iterated a
	single frame and hid nothing: the ConsolePort borders stayed visible even
	though the test harness (which returned a table) said otherwise. ]]
local function ForEachRegion(frame, callback)
	if type(frame) ~= "table" or type(frame.GetRegions) ~= "function" then return 0 end

	local count = 0
	local max = (type(frame.GetNumRegions) == "function") and frame:GetNumRegions() or 100

	for i = 1, max do
		local region = select(i, frame:GetRegions())
		if region == nil then break end

		count = count + 1
		callback(region)
	end

	return count
end

--[[ Hides any texture region on the button that is not the icon.

	ConsolePort re-shows `Border`, `Shadow`, `Flash`, `FlyoutBorder`,
	`FlyoutBorderShadow`, `AutoCastable` and pet-only regions whenever it
	refreshes a button, and each one left visible reads as a second, internal
	border inside the ElvUI one.

	ElvUI's own `StripTextures` is used where available, because that is what
	every ElvUI skin uses and it removes the texture rather than only setting
	its alpha. ]]
function CPLK:HideStrayTextures(button, state)
	if not state or not state.icon then return end

	-- ConsolePort can hand the button a different icon region. The cached
	-- reference must never be trusted for the "do not hide" decision, or the
	-- sweep hides the live icon - which is exactly what made buttons lose their
	-- artwork entirely.
	local live = button.icon or state.icon
	state.icon = live
	state.iconTexture = live

	local function stripRegion(region)
		local isTexture = type(region) == "table"
			and type(region.SetAlpha) == "function"
			and (not region.IsObjectType or region:IsObjectType("Texture"))

		if isTexture and region ~= live and not region.cplkOwned then
			-- Only the icon art is spared. Everything else on the button is
			-- ConsolePort decoration: `Border` is an ADD-blended white ring,
			-- `Shadow`/`Flash`/`FlyoutBorder` are other artwork.
			local isHotkey = (button.texture == region) or (state.keepRegion == region)

			if not isHotkey then
				-- SetTexture(nil) as well as alpha 0: ConsolePort's `Border` is an
				-- ADD-blended white ring, and some of these regions are re-shown
				-- by name on every refresh, so clearing the texture as well as
				-- the alpha is what actually makes them go away.
				if region.SetTexture then pcall(region.SetTexture, region, nil) end
				region:SetAlpha(0)

				if not state.textureSet[region] then
					state.textureSet[region] = true
					state.textures[#state.textures + 1] = region
				end
			end
		end
	end

	ForEachRegion(button, stripRegion)

	-- ConsolePort draws the button art on a child frame
	-- (`CPUIActionButtonTextureOverlayTemplate`), which `GetRegions()` on the
	-- button does not see. That is where the white `Border` ring lives.
	if type(button.GetChildren) == "function" then
		local children = {button:GetChildren()}
		for i = 1, #children do
			local child = children[i]
			local name = child.GetName and child:GetName() or ""

			-- `CPUIActionButtonTextureOverlayTemplate` frames are named
			-- `$parent_HOTKEY` and hold `parentKey="texture"` - the icon overlay
			-- art, which must survive. Anything else inside them is decoration.
			if type(name) == "string" and name:upper():find("HOTKEY", 1, true) then
				state.keepRegion = child.texture
				ForEachRegion(child, stripRegion)
				state.keepRegion = nil
			end
		end
	end
end

--[[ ConsolePort frames are not uniform: `Count`, `Name` and `NewActionTexture`
	can be plain tables, or widgets that do not implement every method. Touching
	one of those threw `attempt to call method 'SetShown' (a nil value)` and
	aborted the whole apply, leaving the rest of the bar unskinned. ]]
local function IsWidget(region)
	return type(region) == "table"
		and type(region.ClearAllPoints) == "function"
		and type(region.SetPoint) == "function"
		and (type(region.SetShown) == "function" or type(region.SetAlpha) == "function")
end

function CPLK:UpdateSkin(button, state)
	state = state or self.skinned[button]
	if not state or not state.icon then return end

	if not button.cplkBackdrop then self:CreateBorder(button) end

	local db = CPLK:DB()
	local width, height = button:GetWidth(), button:GetHeight()
	if not width or width <= 0 or not height or height <= 0 then return end

	local size = BorderSize()
	local edgeSize, edgePixels = self:EdgeSizeFor(button, size)
	local backdrop = button.cplkBackdrop

	-- ElvUI's arrangement, exactly: the backdrop covers the whole button, the
	-- icon is trimmed and sits inside it, and the border is the backdrop's edge.
	--
	-- ConsolePort's button sizes are fractional (10.35, 17.999998 ...). A frame
	-- whose edges land between two pixels anti-aliases its border across both,
	-- which is what makes some borders look twice as thick as others. The
	-- backdrop is therefore snapped to whole *screen* pixels, so every border
	-- covers exactly one pixel on each side no matter what size the button is.
	-- Anchored top-left and explicitly sized (below) rather than
	-- `SetAllPoints`, so the size can be put on the pixel grid.
	backdrop:ClearAllPoints()
	backdrop:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

	local pixelW, pixelH = self:PixelRect(button)
	if pixelW and pixelH then
		backdrop:SetSize(pixelW, pixelH)
	end

	self:SetBackdropEdge(backdrop, size, edgeSize)

	if not self.debugOn then
		backdrop:SetBackdropColor(BackdropRGB())
	end

	-- The button frame itself must not paint anything; ElvUI's look is the
	-- backdrop frame underneath with the trimmed icon on top.
	if button.SetBackdrop and button ~= backdrop then
		local own = button.GetBackdrop and button:GetBackdrop()
		if own then button:SetBackdrop(nil) end
	end
	backdrop:SetBackdropBorderColor(ActiveBorderRGB(state))

	state.lastWidth = width

	-- Icon: ElvUI trims the icon and calls `icon:SetInside()`. It is inset by
	-- exactly the border thickness and sized to the same pixel grid as the
	-- backdrop, so the border keeps one pixel of width on every side.
	local icon = state.icon
	local inset = (edgeSize > 0) and edgeSize or 0

	local iconW = (pixelW or width) - 2 * inset
	local iconH = (pixelH or height) - 2 * inset
	if iconW <= 0 or iconH <= 0 then
		iconW, iconH, inset = width, height, 0
	end

	icon:ClearAllPoints()
	icon:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
	icon:SetSize(iconW, iconH)

	local tc = E.TexCoords or {0.08, 0.92, 0.08, 0.92}
	icon:SetTexCoord(tc[1] or 0.08, tc[2] or 0.92, tc[3] or 0.08, tc[4] or 0.92)

	if state.hover then
		state.hover:ClearAllPoints()
		state.hover:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
		state.hover:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
	end

	-- An empty slot shows ConsolePort's `ability-empty2` texture. Not every
	-- ConsolePortLK build ships that file, and when it is missing the icon
	-- region renders as a blank box. If the texture cannot be resolved it is
	-- cleared, so ElvUI's own background shows through instead of a blank.
	local iconTexture = icon.GetTexture and icon:GetTexture()
	if type(iconTexture) == "string" and iconTexture ~= "" then
		local empty = button.emptyIcon

		if (type(empty) == "string" and iconTexture == empty) or iconTexture:find("ability%-empty") then
			local resolves = true
			if GetFileIDFromPath then
				local ok, fileID = pcall(GetFileIDFromPath, iconTexture)
				resolves = ok and (fileID == nil or fileID ~= 0)
			end

			if not resolves and icon.SetColorTexture then
				icon:SetTexture(nil)
				icon:SetColorTexture(0, 0, 0, 0)
			end
		end
	end

	if state.hover then
		state.hover:ClearAllPoints()
		state.hover:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
		state.hover:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
	end

	-- An empty slot shows ConsolePort's `ability-empty2` texture. Not every
	-- ConsolePortLK build ships that file, and when it is missing the icon
	-- region renders as a blank box. If the texture cannot be resolved it is
	-- cleared, so ElvUI's own background shows through instead of a blank.
	local iconTexture = icon.GetTexture and icon:GetTexture()
	if type(iconTexture) == "string" and iconTexture ~= "" then
		local empty = button.emptyIcon

		if (type(empty) == "string" and iconTexture == empty) or iconTexture:find("ability%-empty") then
			local resolves = true
			if GetFileIDFromPath then
				local ok, fileID = pcall(GetFileIDFromPath, iconTexture)
				resolves = ok and (fileID == nil or fileID ~= 0)
			end

			if not resolves and icon.SetColorTexture then
				icon:SetTexture(nil)
				icon:SetColorTexture(0, 0, 0, 0)
			end
		end
	end

	icon:ClearAllPoints()
	icon:SetPoint("TOPLEFT", button, "TOPLEFT", size, -size)
	icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -size, size)
	local tc = E.TexCoords or {0.08, 0.92, 0.08, 0.92}
	icon:SetTexCoord(tc[1] or 0.08, tc[2] or 0.92, tc[3] or 0.08, tc[4] or 0.92)

	if state.hover then
		state.hover:ClearAllPoints()
		state.hover:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
		state.hover:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
	end

	-- An empty slot shows ConsolePort's `ability-empty2` texture. Not every
	-- ConsolePortLK build ships that file, and when it is missing the icon
	-- region renders as a blank box. If the texture cannot be resolved it is
	-- cleared, so ElvUI's own background shows through instead of a blank.
	local iconTexture = icon.GetTexture and icon:GetTexture()
	if type(iconTexture) == "string" and iconTexture ~= "" then
		local empty = button.emptyIcon

		if (type(empty) == "string" and iconTexture == empty) or iconTexture:find("ability%-empty") then
			local resolves = true
			if GetFileIDFromPath then
				local ok, fileID = pcall(GetFileIDFromPath, iconTexture)
				resolves = ok and (fileID == nil or fileID ~= 0)
			end

			if not resolves and icon.SetColorTexture then
				icon:SetTexture(nil)
				icon:SetColorTexture(0, 0, 0, 0)
			end
		end
	end

	if state.hover then
		state.hover:ClearAllPoints()
		state.hover:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
		state.hover:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
	end

	-- An empty slot shows ConsolePort's `ability-empty2` texture. Not every
	-- ConsolePortLK build ships that file, and when it is missing the icon
	-- region renders as a blank box. If the texture cannot be resolved it is
	-- cleared, so ElvUI's own background shows through instead of a blank.
	local iconTexture = icon.GetTexture and icon:GetTexture()
	if type(iconTexture) == "string" and iconTexture ~= "" then
		local empty = button.emptyIcon

		if (type(empty) == "string" and iconTexture == empty) or iconTexture:find("ability%-empty") then
			local resolves = true
			if GetFileIDFromPath then
				local ok, fileID = pcall(GetFileIDFromPath, iconTexture)
				resolves = ok and (fileID == nil or fileID ~= 0)
			end

			if not resolves and icon.SetColorTexture then
				icon:SetTexture(nil)
				icon:SetColorTexture(0, 0, 0, 0)
			end
		end
	end

	icon:ClearAllPoints()
	icon:SetPoint("TOPLEFT", button, "TOPLEFT", size, -size)
	icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -size, size)
	local tc = E.TexCoords or {0.08, 0.92, 0.08, 0.92}
	icon:SetTexCoord(tc[1] or 0.08, tc[2] or 0.92, tc[3] or 0.08, tc[4] or 0.92)

	-- ElvUI's own action buttons trim `icon` by `E.TexCoords` and show the whole
	-- of `texture`. ConsolePort draws a sliver into `texture` for the modifier
	-- satellites, and this plugin reports an untrimmed icon for them, so the two
	-- have to be kept consistent or a trimmed icon lands inside an untrimmed
	-- sliver and reads as a stray internal border.
	if button.texture and button.texture.SetTexCoord and button.texture ~= icon then
		local trim = (state.inset or 0) > 0
		if trim then
			pcall(button.texture.SetTexCoord, button.texture, unpack(E.TexCoords))
		else
			pcall(button.texture.SetTexCoord, button.texture, 0, 1, 0, 1)
		end
	end

	if state.hover then
		state.hover:ClearAllPoints()
		state.hover:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
		state.hover:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
	end

	-- Catch regions ConsolePort added or re-showed since the button was skinned.
	self:HideStrayTextures(button, state)

	-- The "new action" sparkle. Only an overlay - on frames where that region
	-- *is* the icon it must be left completely alone.
	if state.newAction and state.newAction ~= icon and state.newAction.SetAlpha then
		state.newAction:SetAlpha(0)
	end

	-- ConsolePort can swap these regions when it re-styles the bar.
	if button.cooldown then state.cooldown = button.cooldown end
	state.count = IsWidget(button.Count) and button.Count or nil
	state.name = IsWidget(button.Name) and button.Name or nil
	if button.NewActionTexture then state.newAction = button.NewActionTexture end
end

function CPLK:StyleTexts(button, state)
	local db = CPLK:DB()
	local actionbar = E.db.actionbar or {}

	-- ConsolePort can swap these regions when it re-styles the bar.
	state.count = IsWidget(button.Count) and button.Count or nil
	state.name = IsWidget(button.Name) and button.Name or nil

	-- Count / stack text
	local count = state.count
	if count then
		count:ClearAllPoints()
		local anchor = state.icon or button
		count:SetPoint(actionbar.countTextPosition or "BOTTOMRIGHT", anchor, actionbar.countTextPosition or "BOTTOMRIGHT", actionbar.countTextXOffset or 0, actionbar.countTextYOffset or 2)
		self:StyleFont(count, db.fontSize)
		local color = actionbar.fontColor
		if color then count:SetTextColor(color.r, color.g, color.b) end
	end

	-- Macro name (ConsolePort writes the action text at the bottom of the button)
	local name = state.name
	if name then
		name:ClearAllPoints()
		local anchor = state.icon or button
		name:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 1)
		self:StyleFont(name, db.fontSize)

		-- ConsolePort treats an empty macro name as "nothing to show" and skips
		-- its own SetText call, so the region can keep a stale string from an
		-- earlier action (an empty-button hint). Writing the name ourselves keeps
		-- the text correct whether or not it is hidden.
		local actionText
		if button.GetActionText then
			local ok, text = pcall(button.GetActionText, button)
			if ok then actionText = text end
		end
		if actionText == nil then actionText = name:GetText() end
		state.actionText = actionText

		local stackable = false
		if button.IsConsumableOrStackable then
			local ok, result = pcall(button.IsConsumableOrStackable, button)
			stackable = ok and result or false
		end

		if stackable then
			name:SetText("")
		else
			name:SetText(actionText or "")
		end

		local color = actionbar.fontColor
		if color then name:SetTextColor(color.r, color.g, color.b) end
	end

	self:ApplyTextVisibility(state)
end

--[[ Show or hide the count and macro text.

	Kept separate from StyleTexts so the options can flip it without restyling
	(or, historically, requiring a reload).
]]
function CPLK:ApplyTextVisibility(state)
	if not state then return end

	local db = CPLK:DB()
	local actionbar = E.db.actionbar or {}

	if state.count then
		if state.count.SetShown then
			state.count:SetShown(not db.hideCount)
		else
			state.count:SetAlpha(db.hideCount and 0 or 1)
		end
	end

	if state.name then
		if state.name.SetShown then
			state.name:SetShown(not db.hideMacroText)
		else
			state.name:SetAlpha(db.hideMacroText and 0 or 1)
		end
		-- ConsolePort's own styling hides this region again on every update.
		state.name:SetAlpha(db.hideMacroText and 0 or 1)

		local config = state.owner and state.owner.config
		if config then
			config.hideElements = config.hideElements or {}
			config.hideElements.macro = db.hideMacroText and true or false
		end
		local buttonConfig = state.button and state.button.config
		if buttonConfig then
			buttonConfig.hideElements = buttonConfig.hideElements or {}
			buttonConfig.hideElements.macro = db.hideMacroText and true or false
		end
	end
end

-------------------------------------------------------------------------------
-- Button skinning
-------------------------------------------------------------------------------
function CPLK:SkinButton(button, modifier, tab, owner)
	if not button or self.skinned[button] then return self.skinned[button] end

	local icon = button.icon
	if not icon then return end

	local db = CPLK:DB()
	local state = {
		modifier = modifier or "",
		tab = tab or "square",
		owner = owner or button,
		button = button,
		icon = icon,
		textures = {},
		textureSet = {},
	}

	local inset = (state.modifier == "") and INSET_MAIN or INSET_SATELLITE
	if state.tab == "round" then inset = 0 end
	state.inset = inset

	-- Collect everything ConsolePort draws over or around the icon.
	--
	-- The named fields below are not the whole story: ConsolePort also draws
	-- `Flash`, `FakeChecked` and pet-only regions, and which of them exist
	-- varies per frame. Anything left visible shows up as a second, internal
	-- border inside the ElvUI one, so every texture region on the button is
	-- collected, not just the known names.
	--
	-- NewActionTexture is deliberately NOT in this list. On some ConsolePort
	-- frames it is the region that carries the icon art, so hiding it blanked
	-- the button - that is what made a scattering of buttons lose their icons.
	-- The plugin hides the "new action" sparkle in UpdateSkin instead, and only
	-- when it is genuinely a separate overlay.
	local textures = {
		button.NormalTexture,
		button.PushedTexture,
		button.HighlightTexture,
		button.CheckedTexture,
		button.Border,
		button.Shadow,
	}

	state.newAction = button.NewActionTexture

	-- Everything else the frame carries as a texture, except the icon, our own
	-- regions and the hotkey glyphs (those are still wanted as labels).
	local function stripRegion(region)
		local isTexture = type(region) == "table"
			and type(region.SetAlpha) == "function"
			and (not region.IsObjectType or region:IsObjectType("Texture"))

		if isTexture then
			local name = region.GetName and region:GetName() or ""
			local isHotkey = type(name) == "string" and name:lower():find("hotkey", 1, true) ~= nil

			if not isHotkey and not region.cplkOwned then
				textures[#textures + 1] = region
			end
		end
	end

	ForEachRegion(button, stripRegion)

	for _, texture in pairs(textures) do
		-- Never touch the icon itself, and never touch the same region twice.
		if texture and texture.SetAlpha and texture ~= icon and not state.textureSet[texture] then
			state.textureSet[texture] = true
			state.textures[#state.textures + 1] = texture
			texture:SetAlpha(0)
			texture:SetDrawLayer("BACKGROUND", -1)
		end
	end

	-- ElvUI style hover highlight.
	if not state.hover then
		local hover = button:CreateTexture(nil, "HIGHLIGHT")
		hover.cplkOwned = true
		hover:SetTexture(1, 1, 1, 0.3)
		hover:SetAlpha(0)
		state.hover = hover
	end

	state.count = IsWidget(button.Count) and button.Count or nil
	state.name = IsWidget(button.Name) and button.Name or nil
	state.cooldown = button.cooldown
	state.iconTexture = icon
	button.cplkSkinned = true

	self.skinned[button] = state

	self:HookCooldown(button.cooldown, button)

	-- Keep the skin intact when ConsolePort (re)applies its own styling.
	local updateAction = button.UpdateAction
	if updateAction and not button.cplkUpdateActionHooked then
		button.cplkUpdateActionHooked = true
		button.UpdateAction = function(self2, ...)
			updateAction(self2, ...)

			local st = CPLK.skinned[self2]
			if not st then return end

			CPLK:UpdateSkin(self2, st)

			CPLK:ApplyTextVisibility(st)
		end
	end

	button:HookScript("OnSizeChanged", function(self2)
		if CPLK.skinned[self2] then
			pcall(CPLK.UpdateSkin, CPLK, self2)
			pcall(CPLK.UpdateTextStyle, CPLK, self2)
		end
	end)

	button:HookScript("OnEnter", function(self2)
		local st = CPLK.skinned[self2]
		if st then
			st.hovered = true
			if st.hover then st.hover:SetAlpha(1) end
			if st.backdrop and st.backdrop.SetBackdropBorderColor then
				st.backdrop:SetBackdropBorderColor(ActiveBorderRGB(st))
			end
		end
	end)

	-- Pressed: same class-colour highlight, so a press is visible too.
	button:HookScript("OnMouseDown", function(self2)
		local st = CPLK.skinned[self2]
		if st then
			st.pressed = true
			if st.backdrop and st.backdrop.SetBackdropBorderColor then
				st.backdrop:SetBackdropBorderColor(ActiveBorderRGB(st))
			end
		end
	end)

	button:HookScript("OnMouseUp", function(self2)
		local st = CPLK.skinned[self2]
		if st then
			st.pressed = false
			if st.backdrop and st.backdrop.SetBackdropBorderColor then
				st.backdrop:SetBackdropBorderColor(ActiveBorderRGB(st))
			end
		end
	end)

	button:HookScript("OnLeave", function(self2)
		local st = CPLK.skinned[self2]
		if st then
			st.hovered = false
			st.pressed = false
			if st.hover then st.hover:SetAlpha(0) end
			if st.backdrop and st.backdrop.SetBackdropBorderColor then
				st.backdrop:SetBackdropBorderColor(ActiveBorderRGB(st))
			end
		end
	end)

	self:UpdateSkin(button, state)
	self:StyleTexts(button, state)
	self:ApplySwipe(state)
	state.backdrop = button.cplkBackdrop
	state.isSkinned = true

	if db.cooldownText then
		self:UpdateTextStyle(button)
	end

	-- The cooldown text is driven by our own OnUpdate, so an ability that is
	-- already cooling down does not need UpdateAction() to be re-run here.
	-- Calling it per button made ConsolePort rebuild its art one button at a
	-- time, which showed up as a visible crawl when applying the skin.

	return state
end

function CPLK:RestoreButton(button)
	local state = self.skinned[button]
	if not state then return end

	for _, texture in pairs(state.textures) do
		if texture and texture.SetAlpha then texture:SetAlpha(1) end
	end

	if state.hover then state.hover:SetAlpha(0) state.hovered = false end

	-- Give the button frame its own background back. Leaving the backdrop on,
	-- or leaving a separate border frame behind, is what made the skin appear
	-- to survive a toggle with ConsolePort's icons punched out of it.
	local backdrop = button.cplkBackdrop
	if backdrop then
		backdrop:SetBackdrop(nil)
		E.frames[backdrop] = nil
	end
	button.cplkBackdrop = nil
	if state.holder then state.holder:Hide() end
	if state.count then
		pcall(function()
			if state.count.SetShown then state.count:SetShown(true) end
			state.count:SetAlpha(1)
		end)
	end
	if state.name then
		pcall(function()
			if state.name.SetShown then state.name:SetShown(true) end
			state.name:SetAlpha(1)
		end)
	end

	if button.config and button.config.hideElements then
		button.config.hideElements.macro = false
	end

	button.cplkSkinned = nil
	self.skinned[button] = nil
	self.textHolders[button] = nil

	-- RestoreAll() reloads the whole bar once at the end; doing it here as
	-- well would rebuild the bar art once per button.
end

--[[ A broken button should be reported once, not on every geometry tick. ]]
function CPLK:WarnOnce(button, err)
	self.warned = self.warned or {}
	if self.warned[button] then return end
	self.warned[button] = true

	E:Print("|cffff0000ConsolePort Skin: could not skin " .. tostring(button:GetName() or "a button") .. "|r " .. tostring(err))
end

-------------------------------------------------------------------------------
-- Finding the ConsolePort buttons
--
-- ConsolePortBar keeps its wrapper registry in its own addon table
-- (`local _, ab = ...` inside the .toc), which is NOT reachable through
-- ConsolePort:GetData() -- that returns the ConsolePort settings table, which
-- has no `libs`. What is reachable is the widget tree: every action button is
-- a plain child frame of the global `ConsolePortBar` frame (ConsolePort
-- implements `GetChildren()` in its XML, so a cached version must never be
-- used). Buttons are identified the same way ConsolePort itself identifies
-- them, by their `labtype-` attribute, plus the `CPB_` frame name.
-------------------------------------------------------------------------------
local function IsActionButton(frame)
	if not frame or not frame.GetAttribute then return false end
	if frame.locked or frame.blocked then return false end
	if frame:IsObjectType("Slider") or frame:IsObjectType("ScrollFrame") then return false end

	local attr = frame:GetAttribute("labtype-")
	if attr and (attr == "action" or attr == "pet" or attr == "spell" or attr == "item" or attr == "macro" or attr == "custom" or attr == "dummy") then
		return true
	end

	-- Fall back to the ConsolePortBar naming scheme: CPB_<slot>[_SHIFT|_CTRL|_CTRLSHIFT]
	local name = frame.GetName and frame:GetName()
	if name and name:find("^CPB_") and (frame.icon or frame.Icon) then
		return true
	end

	return false
end

--[[ Walks the ConsolePort bar and returns a flat list of action buttons.

	Important: in the Minimal layout ConsolePort re-parents the modifier
	satellites onto the *main button* (`button:SetParent(main)`), so the walk
	must descend into buttons as well instead of stopping at them. ]]
function CPLK:GetActionButtons()
	local bar = self:GetBar()
	if not bar or not bar.GetChildren then return {} end

	local pet = self:GetPetRing()
	local buttons, seen = {}, {}
	local pending = {bar}

	while #pending > 0 do
		local frame = pending[#pending]
		pending[#pending] = nil

		if frame and frame ~= pet and not seen[frame] then
			seen[frame] = true

			if IsActionButton(frame) then
				buttons[#buttons + 1] = frame
			end

			-- Always descend: satellites live inside their main button, and a
			-- frame can be both an action button and a container.
			local children = {frame:GetChildren()}
			for i = 1, #children do
				pending[#pending + 1] = children[i]
			end
		end
	end

	return buttons
end

--[[ Bar buttons plus pet-ring buttons, de-duplicated. ]]
function CPLK:GetAllButtons()
	local out, seen = {}, {}

	local lists = {self:GetActionButtons()}
	if CPLK:DB().skinPetRing then
		lists[#lists + 1] = self:GetPetButtons()
	end

	for _, list in ipairs(lists) do
		for _, button in ipairs(list) do
			if button and not seen[button] then
				seen[button] = true
				out[#out + 1] = button
			end
		end
	end

	return out
end

function CPLK:GetPetRing()
	local bar = self:GetBar()
	if not bar then return end
	if bar.Pet then return bar.Pet end

	return _G["ConsolePortBarPet"]
end

--[[ Collects the action buttons that live on the pet ring, which is a sibling
	of the bar's button clusters rather than a child of it in some layouts. ]]
function CPLK:GetPetButtons()
	local pet = self:GetPetRing()
	if not pet or not pet.GetChildren then return {} end

	local buttons, seen = {}, {}
	local pending = {pet}

	while #pending > 0 do
		local frame = pending[#pending]
		pending[#pending] = nil

		if frame and not seen[frame] then
			seen[frame] = true

			if frame ~= pet and IsActionButton(frame) then
				buttons[#buttons + 1] = frame
			end

			local children = {frame:GetChildren()}
			for i = 1, #children do
				pending[#pending + 1] = children[i]
			end
		end
	end

	return buttons
end

-------------------------------------------------------------------------------
-- Applying the skin to the bar
-------------------------------------------------------------------------------
function CPLK:ApplySkin()
	local db = CPLK:DB()
	if not db.enabled then return false end
	if not self:IsConsolePortLoaded() then return false end

	-- Cooldown text is driven by polling, not by hooks: start it as soon as
	-- there is anything to skin.
	if db.cooldownText then self:CooldownDriver() end

	local buttons = self:GetAllButtons()
	if not buttons then return false end

	local tab = GetButtonTab(self:GetBar())
	local pet = self:GetPetRing()
	local count = 0

	for _, button in ipairs(buttons) do
		local modifier = button.mod or (button.GetAttribute and button:GetAttribute("modifier")) or ""
		local isPet = pet and button:GetParent() == pet

		-- In the Classic (round) layout the modifier wings are drawn with
		-- ConsolePort's crescent art. Only the main buttons are skinned there,
		-- the square presets are skinned completely.
		local skip = (not isPet) and tab == "round" and modifier ~= ""
		if not skip and button.icon then
			-- One unexpected ConsolePort frame must never abort the whole pass.
			local ok, result = pcall(self.SkinButton, self, button, modifier, isPet and "square" or tab, button)
			if ok and result then
				count = count + 1
			elseif not ok then
				self:WarnOnce(button, result)
			end
		end
	end

	if CPLK:DB().skinPetRing then
		self:SkinPetRing()
	end

	self:ApplyCooldownOwner()

	return count
end

--[[ Rescues buttons ConsolePort created after we were initialised. ]]
function CPLK:SkinNewButtons()
	local count = 0
	local tab = GetButtonTab(self:GetBar())

	for _, button in ipairs(self:GetAllButtons()) do
		if button.icon and not self.skinned[button] then
			local modifier = button.mod or (button.GetAttribute and button:GetAttribute("modifier")) or ""
			local ok, result = pcall(self.SkinButton, self, button, modifier, tab, button)
			if ok and result then
				count = count + 1
			elseif not ok then
				self:WarnOnce(button, result)
			end
		end
	end

	return count
end

function CPLK:SkinPetRing()
	local pet = self:GetPetRing()
	if not pet then return end

	local size = BorderSize()
	local outside = (size > 0 and CPLK:DB().borderOutside) and size or 0

	-- The portrait in the middle of the pet ring.
	if pet.Portrait and not pet.cplkBackdrop then
		local backdrop = self:CreatePetBorder(pet)
		backdrop:SetFrameLevel(math.max(0, pet:GetFrameLevel() - 1))
		self:SetBackdropEdge(backdrop, size, edgeSize)
		pet.cplkBackdrop = backdrop
	end

	if pet.cplkBackdrop and pet.Portrait then
		local width = pet:GetWidth()
		if width and width > 0 then
			local inset = width * INSET_MAIN
			pet.cplkBackdrop:ClearAllPoints()
			pet.cplkBackdrop:SetPoint("TOPLEFT", pet, "TOPLEFT", inset - outside, -(inset - outside))
			pet.cplkBackdrop:SetPoint("BOTTOMRIGHT", pet, "BOTTOMRIGHT", -(inset - outside), inset - outside)
			pet.Portrait:ClearAllPoints()
			pet.Portrait:SetPoint("TOPLEFT", pet.cplkBackdrop, "TOPLEFT", size, -size)
			pet.Portrait:SetPoint("BOTTOMRIGHT", pet.cplkBackdrop, "BOTTOMRIGHT", -size, size)
			pet.Portrait:SetTexCoord(unpack(E.TexCoords))
		end

		if pet.Border then pet.Border:SetAlpha(0) end
		if pet.Shadow then pet.Shadow:SetAlpha(0) end
	end

	-- The pet action buttons themselves are skinned by ApplySkin/SkinNewButtons
	-- because they are children of the pet frame as well.
	for _, button in ipairs(self:GetPetButtons()) do
		if button.icon and not self.skinned[button] then
			local state = self:SkinButton(button, "", "square", button)
			if state then
				if button.NormalTexture then button.NormalTexture:SetAlpha(0) end
				if button.AutoCastable then button.AutoCastable:SetAlpha(0) end
				self:UpdateSkin(button, state)
			end
		end
	end
end

function CPLK:Refresh()
	local count = self:ApplySkin()
	if count then
		for button, state in pairs(self.skinned) do
			-- Guarded per button: one unusual frame must not abort the restyle
			-- of every other button in the bar.
			local ok, err = pcall(function()
				self:UpdateSkin(button, state)
				self:StyleTexts(button, state)
				self:UpdateTextStyle(button)
				self:ApplySwipe(state)
			end)

			if not ok then
				self:WarnOnce(button, err)
			end
		end
	end

	return count
end

function CPLK:RestoreAll()
	for button in pairs(self.skinned) do
		self:RestoreButton(button)
	end

	local bar = self:GetBar()
	local pet = bar and bar.Pet
	if pet then
		if pet.cplkBackdrop then pet.cplkBackdrop:Hide() pet.cplkBackdrop = nil end
		if pet.Portrait then pet.Portrait:SetTexCoord(0, 1, 0, 1) end
		if pet.Border then pet.Border:SetAlpha(1) end
		if pet.Shadow then pet.Shadow:SetAlpha(0.75) end
	end

	self:ApplyCooldownOwner()

	-- Let ConsolePort rebuild its own art. The wrapper registry is not
	-- reachable from outside the addon, so the bar is asked to redraw itself
	-- through its public settings entry point instead.
	if not InCombatLockdown() and self:GetBar() and self:GetBar().OnLoad then
		local setup = self:GetSettings()
		if setup then
			pcall(self:GetBar().OnLoad, self:GetBar(), setup)
		end
	end
end

-------------------------------------------------------------------------------
-- ConsolePortBar re-style detection
-------------------------------------------------------------------------------
function CPLK:HookConsolePort()
	local bar = self:GetBar()
	if not bar then return end

	if not bar.cplkHooked then
		bar.cplkHooked = true

		-- Fired on every layout save / preset change / bar reload.
		if bar.OnLoad then
			hooksecurefunc(bar, "OnLoad", function()
				E:Delay(0.2, function()
					CPLK:ApplySkin()
				end)
			end)
		end
	end

	-- The wrappers themselves are not reachable, but the buttons can change
	-- their size/anchor when ConsolePort re-orients a cluster, so poll the
	-- geometry cheaply and re-apply only when something actually moved.
	self:StartGeometryWatch()
end

--[[ ConsolePort rebuilds its art from several internal paths we cannot hook,
	so a light watchdog catches any case a hook missed. It costs nothing when
	nothing changes. ]]
function CPLK:StartGeometryWatch()
	if self.watcher then return end

	local watcher = CreateFrame("Frame")
	watcher.elapsed = 0
	watcher:SetScript("OnUpdate", function(frame, elapsed)
		frame.elapsed = frame.elapsed + elapsed
		if frame.elapsed < 1 then return end
		frame.elapsed = 0

		if InCombatLockdown() then return end
		if not CPLK:IsEnabled() then return end
		if not CPLK:IsConsolePortLoaded() then return end

		local changed = false
		for button, state in pairs(CPLK.skinned) do
			if button:IsShown() and state.icon then
				local width = button:GetWidth()
				if width and width > 0 and width ~= state.lastWidth then
					local ok, err = pcall(CPLK.UpdateSkin, CPLK, button, state)
					if not ok then CPLK:WarnOnce(button, err) end
					changed = true
				end
			end
		end

		-- A layout change can also add clusters that were never skinned.
		if not changed then
			local total = #CPLK:GetAllButtons()
			local skinnedCount = 0
			for _ in pairs(CPLK.skinned) do skinnedCount = skinnedCount + 1 end

			if total > skinnedCount then
				CPLK:SkinNewButtons()
			end
		end
	end)

	self.watcher = watcher
end

-------------------------------------------------------------------------------
-- Module lifecycle
-------------------------------------------------------------------------------
function CPLK:Initialize()
	if self.initialized then return end
	self.initialized = true

	self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		CPLK:ApplySkin()
		CPLK:HookConsolePort()
	end)

	-- ElvUI recoloured the theme (border/backdrop colour changed).
	hooksecurefunc(E, "UpdateMedia", function()
		for button in pairs(self.skinned) do
			self:UpdateSkin(button)
		end
	end)

	-- ConsolePortBar can load after us (load on demand) or re-style itself when
	-- one of its own settings changes.
	-- AceEvent callbacks receive (event, ...) - there is no `self` argument.
	self:RegisterEvent("ADDON_LOADED", function(event, addon)
		if addon == "ConsolePortBar" or addon == "ConsolePort" then
			E:Delay(0.5, function()
				if CPLK:IsConsolePortLoaded() then
					CPLK:HookConsolePort()
					CPLK:ApplySkin()
				end
			end)
		end
	end)

	E:Delay(1, function()
		CPLK:HookConsolePort()
		CPLK:ApplySkin()
	end)
end
