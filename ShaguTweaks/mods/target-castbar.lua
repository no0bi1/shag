local T = ShaguTweaks.T

local module = ShaguTweaks:register({
  title = T["Enemy Castbars"],
  description = T["Shows an enemy castbar on target unit frame."],
  expansions = { ["vanilla"] = true, ["tbc"] = nil },
  category = T["Unit Frames"],
  enabled = true,
})

local castbar = CreateFrame("StatusBar", "ShaguTargetCastbar", TargetFrame)
castbar:SetPoint("BOTTOM", TargetFrame, "BOTTOM", -12, -4)
castbar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
castbar:SetStatusBarColor(1, .8, 0, 1)
castbar:SetWidth(140)
castbar:SetHeight(10)
castbar:Hide()

castbar.texture = CreateFrame("Frame", nil, castbar)
castbar.texture:SetPoint("RIGHT", castbar, "LEFT", -2, 0)
castbar.texture:SetHeight(20)
castbar.texture:SetWidth(20)

castbar.texture.icon = castbar.texture:CreateTexture(nil, "BACKGROUND")
castbar.texture.icon:SetPoint("CENTER", 0, 0)
castbar.texture.icon:SetWidth(16)
castbar.texture.icon:SetHeight(16)
castbar.texture:SetBackdrop({
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 8, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
})

castbar.bg = castbar:CreateTexture(nil, "BACKGROUND")
castbar.bg:SetTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
castbar.bg:SetVertexColor(.1, .1, 0, .8)
castbar.bg:SetAllPoints(true)

castbar.spark = castbar:CreateTexture(nil, "OVERLAY")
castbar.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
castbar.spark:SetWidth(20)
castbar.spark:SetHeight(20)
castbar.spark:SetBlendMode("ADD")

castbar.backdrop = CreateFrame("Frame", nil, castbar)
castbar.backdrop:SetFrameStrata("BACKGROUND")
castbar.backdrop:SetPoint("TOPLEFT", castbar, "TOPLEFT", -3, 3)
castbar.backdrop:SetPoint("BOTTOMRIGHT", castbar, "BOTTOMRIGHT", 3, -3)
castbar.backdrop:SetBackdrop({
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 8, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
})

castbar.text = castbar:CreateFontString(nil, "HIGH", "GameFontWhite")
castbar.text:SetPoint("CENTER", castbar, "CENTER", 0, 0)
local font, size, opts = castbar.text:GetFont()
castbar.text:SetFont(font, size - 2, "THINOUTLINE")

module.enable = function(self)
  local duration = C_DurationUtil.CreateDuration()
  local expiry

  local function HideCastbar()
    if expiry then
      expiry:Cancel()
      expiry = nil
    end
    castbar:Hide()
  end

  local function UpdatePosition()
    castbar:ClearAllPoints()
    castbar:SetPoint("BOTTOM", TargetFrame, "BOTTOM", -12, -4)

    local targetOfTarget = TargetofTargetFrame and TargetofTargetFrame:IsShown()
    local debuff11 = TargetFrameDebuff11 and TargetFrameDebuff11:IsShown()
    local debuff7 = TargetFrameDebuff7 and TargetFrameDebuff7:IsShown()
    local buff1 = TargetFrameBuff1 and TargetFrameBuff1:IsShown()

    if targetOfTarget then
      castbar:SetPoint("BOTTOM", TargetFrame, "BOTTOM", -12, -24)
      if debuff11 then
        castbar:SetPoint("BOTTOM", TargetFrame, "BOTTOM", -12, -45)
        if buff1 then
          castbar:SetPoint("BOTTOM", TargetFrame, "BOTTOM", -12, -65)
        end
      end
    elseif debuff7 then
      castbar:SetPoint("BOTTOM", TargetFrame, "BOTTOM", -12, -24)
    end
  end

  local function RefreshCastbar()
    local unit = "target"
    if not UnitExists(unit) then
      HideCastbar()
      return
    end

    local name, _, texture, startMs, endMs, _, _, noInterrupt, spellID =
      C_Spell.UnitCastingInfo(unit)
    local isChannel

    if not name then
      name, _, texture, startMs, endMs, _, noInterrupt, spellID =
        C_Spell.UnitChannelInfo(unit)
      isChannel = true
    end

    if not name or not startMs or not endMs then
      HideCastbar()
      return
    end

    duration:SetTimeSpan(startMs / 1000, endMs / 1000)
    castbar:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate,
      isChannel and Enum.StatusBarTimerDirection.RemainingTime or Enum.StatusBarTimerDirection.ElapsedTime)

    castbar.text:SetText(name)
    if texture then
      castbar.texture.icon:SetTexture(texture)
      castbar.texture.icon:Show()
    else
      castbar.texture.icon:Hide()
    end

    UpdatePosition()
    castbar:Show()

    if expiry then expiry:Cancel() end
    expiry = C_Timer.NewTimer(duration:GetRemainingDuration(), function()
      expiry = nil
      castbar:Hide()
    end)
  end

  -- Cast events are unit-token based. Include player events so a self-targeted
  -- cast can still be displayed when target resolves to the player.
  castbar:RegisterUnitEvent("UNIT_SPELLCAST_START", "target", "player")
  castbar:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "target", "player")
  castbar:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "target", "player")
  castbar:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "target", "player")
  castbar:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "target", "player")
  castbar:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "target", "player")
  castbar:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "target", "player")
  castbar:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "target", "player")
  castbar:RegisterEvent("PLAYER_TARGET_CHANGED")

  castbar:SetScript("OnEvent", function()
    if event == "PLAYER_TARGET_CHANGED" then
      RefreshCastbar()
      return
    end

    if arg1 ~= "target" and not (arg1 == "player" and UnitIsUnit("target", "player")) then
      return
    end

    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
      RefreshCastbar()
    else
      -- A stop for the previous cast can arrive after a replacement has begun.
      -- Re-poll before hiding so the current cast remains visible.
      RefreshCastbar()
    end
  end)

  -- Keep the original target-frame placement responsive to buff/debuff layout.
  local oldUpdate = TargetFrame:GetScript("OnUpdate")
  TargetFrame:SetScript("OnUpdate", function(arg)
    if oldUpdate then oldUpdate(arg) end
    if castbar:IsShown() then UpdatePosition() end
  end)

  RefreshCastbar()
end
