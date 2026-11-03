local E, L, V, P, G = unpack(ElvUI); --Import: Engine, Locales, PrivateDB, ProfileDB, GlobalDB

if not E then return end

local CPLK = E:GetModule("ConsolePortLK")

--[[
	Small public API so other addons (or macros) can drive the skin.

	/run ElvUI[1]:GetModule("ConsolePortLK"):SkinAll()
]]

-------------------------------------------------------------------------------
-- Per button access
-------------------------------------------------------------------------------
--[[ Skins a single action button.
	@param button  ConsolePortBar action button (the frame in wrapper.Buttons)
	@param modifier  "" / "SHIFT-" / "CTRL-" / "CTRL-SHIFT-" (optional)
	@param tab  "square" or "round" (optional)
]]
function CPLK:SkinActionButton(button, modifier, tab)
	if not (button and button.icon) then return end
	return self:SkinButton(button, modifier or button.mod or "", tab)
end

--[[ Returns true when the button is currently skinned. ]]
function CPLK:IsSkinned(button)
	return self.skinned[button] ~= nil
end

--[[ Restores a single button to the ConsolePort art. ]]
function CPLK:UnskinActionButton(button)
	self:RestoreButton(button)
end

-------------------------------------------------------------------------------
-- Whole bar access
-------------------------------------------------------------------------------
--[[ Skins every ConsolePort action button, the satellites and the pet ring. ]]
function CPLK:SkinAll()
	local count = self:ApplySkin()
	if count then
		self:Refresh()
	end

	return count
end

--[[ Restores the original ConsolePort look and turns the plugin off. ]]
function CPLK:Unskin()
	self:SetEnabled(false)
end

function CPLK:SetEnabled(enable)
	local db = CPLK:DB()
	if not db then return end

	db.enabled = enable and true or false
	self:UpdateState()
end

function CPLK:IsEnabled()
	local db = CPLK:DB()
	return (db and db.enabled) and true or false
end

--[[ Re-reads every option and applies it without a reload. ]]
function CPLK:UpdateState()
	local db = CPLK:DB()
	if not db then return end

	if db.enabled and self:IsConsolePortLoaded() then
		self:SkinAll()

		-- Polling is what actually keeps cooldown text alive; start it whenever
		-- the skin is live and stop it when the skin is switched off.
		if db.cooldownText then
			self:CooldownDriver()
		else
			self:StopCooldownDriver()
		end

		for button, state in pairs(self.skinned) do
			-- Text visibility and the cooldown mode are applied here so the
			-- options take effect immediately, without a reload.
			pcall(self.StyleTexts, self, button, state)
			pcall(self.SyncCooldownMode, self, button, state)

			if state.holder then
				local holder = state.holder
				if db.cooldownText then
					self:UpdateTextStyle(button)
				else
					holder.endTime = nil
					holder:Hide()
				end

				if state.icon and not db.desaturate then
					state.icon:SetDesaturated(false)
				end
			end

			self:ApplySwipe(state)
		end
	else
		self:StopCooldownDriver()
		self:RestoreAll()
	end

	self:ApplyCooldownOwner()
end

