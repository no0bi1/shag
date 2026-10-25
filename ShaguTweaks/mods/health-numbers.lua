local T = ShaguTweaks.T
local Abbreviate = ShaguTweaks.Abbreviate

local module = ShaguTweaks:register({
  title = T["Real Health Numbers"],
  description = T["Estimates health numbers and shows them on the target unit frame."],
  expansions = { ["vanilla"] = true },
  category = T["Unit Frames"],
  enabled = true,
})

-- true for yourself, your pet, party/raid members and party pets
local function IsGroupUnit(unit)
  if UnitIsUnit(unit, "player") or UnitIsUnit(unit, "pet") then return true end
  if UnitInParty(unit) or UnitInRaid(unit) then return true end
  for i = 1, 4 do
    if UnitIsUnit(unit, "partypet" .. i) then return true end
  end
  return nil
end

-- add "Health " in front of any "cur / max" text that doesn't have it yet
local function PrefixHealth(string)
  local text = string:GetText()
  if text and strfind(text, "/") and not strfind(text, "^Health") then
    string:SetText("Health " .. text)
  end
end

module.enable = function(self)
  -- target health text (mana is left to Blizzard)
  TargetFrame.StatusTexts = CreateFrame("Frame", nil, TargetFrame)
  TargetFrame.StatusTexts:SetAllPoints(TargetFrame)

  TargetFrameHealthBar.TextString = TargetFrame.StatusTexts:CreateFontString("TargetFrameHealthBarText", "OVERLAY")
  TargetFrameHealthBar.TextString:SetPoint("TOP", TargetFrameHealthBar, "BOTTOM", -2, 23)
  TargetFrameHealthBar.TextString:SetFontObject("GameFontWhite")
  TargetFrameHealthBar.TextString:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
  TargetFrameHealthBar.TextString:SetHeight(32)

  -- pet frame cosmetics
  PetFrameHealthBar.TextString:SetPoint("CENTER", PetFrameHealthBar, "CENTER", -2, 0)
  PetFrameManaBar.TextString:SetPoint("CENTER", PetFrameManaBar, "CENTER", -2, -2)

  for _, frame in pairs({ PetFrameHealthBar, PetFrameManaBar }) do
    frame.TextString:SetFontObject("GameFontWhite")
    frame.TextString:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    frame.TextString:SetHeight(32)
    frame.TextString:SetJustifyH("LEFT")
  end

  local HookTextStatusBar_UpdateTextString = TextStatusBar_UpdateTextString
  function TextStatusBar_UpdateTextString(sb)
    if not sb then sb = this end

    HookTextStatusBar_UpdateTextString(sb)

    local name = sb:GetName()
    local string = sb.TextString
    if not name or not string or not sb.unit then return end

    -- pet bars: keep Blizzard's text, keep it visible, prefix health
    if name == "PetFrameHealthBar" or name == "PetFrameManaBar" then
      if name == "PetFrameHealthBar" then PrefixHealth(string) end
      sb.lockShow = 42
      sb:Show()
      string:Show()
      return
    end

    -- anything else (player, party, mana, ...) is left completely alone
    if name ~= "TargetFrameHealthBar" then return end

    -- group members and pets have real health from Blizzard
    if IsGroupUnit("target") then
      PrefixHealth(string)
      sb.lockShow = 0
      return
    end

    sb.lockShow = 42
    sb:Show()

    if UnitIsDead("target") or UnitIsGhost("target") then
      string:Hide()
      string:SetText("")
      return
    end

    local _, barMax = sb:GetMinMaxValues()
    local percent = barMax > 0 and floor(sb:GetValue() / barMax * 100) or 0
    local cur, max = ShaguTweaks.libhealth:GetUnitHealth(sb.unit)

    -- no real number yet (nothing returned, or libhealth only has the percentage)
    if not cur or not max or max <= 0 or (cur == percent and max == 100) then
      string:Hide()
      string:SetText("")
      return
    end

    string:SetText("Health " .. Abbreviate(cur) .. " / " .. Abbreviate(max))
    string:Show()
  end
end