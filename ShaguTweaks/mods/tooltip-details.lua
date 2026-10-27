local _G = ShaguTweaks.GetGlobalEnv()
local T = ShaguTweaks.T
local round = ShaguTweaks.round
local rgbhex = ShaguTweaks.rgbhex
local Abbreviate = ShaguTweaks.Abbreviate

local module = ShaguTweaks:register({
  title = T["Tooltip Details"],
  description = T["Display health, class color, guild name, guild rank and current target on unit tooltips."],
  expansions = { ["vanilla"] = true, ["tbc"] = true },
  category = T["Tooltip & Items"],
  enabled = true,
})

local backdrop = {
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true,
  tileSize = 8,
  edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
}

local units = {
  "mouseover", "player", "pet", "target",
  "party", "partypet", "raid", "raidpet"
}

local current_unit = "none"
local target_frame_tooltip = false
local updating = false

-- Explicit tooltip lifecycle state. The anchor hook identifies normal world
-- tooltips; target-frame hooks remain authoritative for the compact target view.
local tooltip_source = "none"
local tooltip_owner = nil
local anchor_event = false
local anchor_parent = nil
local anchor_time = 0
local ANCHOR_WINDOW = 0.25

-- Prevent the same visible tooltip from receiving the extra lines twice.
local decorated_unit = nil
local decorated_source = nil
local decorated_title = nil

local oldDefaultAnchor = _G.GameTooltip_SetDefaultAnchor
if oldDefaultAnchor then
  _G.GameTooltip_SetDefaultAnchor = function(tooltip, parent)
    local r1, r2, r3 = oldDefaultAnchor(tooltip, parent)
    if tooltip == GameTooltip then
      anchor_event = true
      anchor_parent = parent
      anchor_time = GetTime()
    end
    return r1, r2, r3
  end
end

--------------------------------------------------
-- Unit detection
--------------------------------------------------

local function MatchUnit(unit, title)
  if not UnitExists(unit) or not title then
    return false
  end

  return UnitName(unit) == title or UnitPVPName(unit) == title
end

local function GetUnit()
  -- A target-frame tooltip is explicitly tied to the current target.
  if tooltip_source == "target-frame" and UnitExists("target") then
    return "target"
  end

  -- Never trust a cached unit for a world tooltip: mouseover may have changed
  -- while the tooltip frame remained visible.
  local title = GameTooltipTextLeft1:GetText()

  if not title then
    return "none"
  end

  if MatchUnit("mouseover", title) then
    return "mouseover"
  end

  for _, unit in ipairs(units) do
    if unit == "party" or unit == "partypet" then
      for i = 1, 4 do
        local u = unit .. i

        if MatchUnit(u, title) then
          return u
        end
      end

    elseif unit == "raid" or unit == "raidpet" then
      for i = 1, 40 do
        local u = unit .. i

        if MatchUnit(u, title) then
          return u
        end
      end

    elseif MatchUnit(unit, title) then
      return unit
    end
  end

  return "none"
end

--------------------------------------------------
-- Health bar visibility
--------------------------------------------------

local function UpdateBarVisibility()
  local unit = current_unit

  if unit == "none" or not UnitExists(unit) then
    unit = UnitExists("mouseover") and "mouseover" or "none"
  end

  if unit == "none" or not UnitExists(unit) then
    GameTooltipStatusBar:Hide()
    return
  end

  local hp = UnitHealth(unit)
  local hpmax = UnitHealthMax(unit)

  if hpmax > 0
    and hp < hpmax
    and not UnitIsDead(unit)
    and not UnitIsUnit(unit, "target") then
    GameTooltipStatusBar:Show()
  else
    GameTooltipStatusBar:Hide()
  end
end

--------------------------------------------------
-- Target line
--------------------------------------------------

local function AddTargetLine(unit)
  local targetunit = unit .. "target"
  local target = UnitName(targetunit)

  if not target then
    return
  end

  local _, targetClass = UnitClass(targetunit)
  local targetReaction = UnitReaction("player", targetunit)

  if UnitIsPlayer(targetunit) and targetClass then
    local color = RAID_CLASS_COLORS[targetClass]

    if color then
      GameTooltip:AddLine(
        "Targeting: " .. target,
        color.r, color.g, color.b
      )
      return
    end
  end

  if targetReaction then
    local color = UnitReactionColor[targetReaction]

    if color then
      GameTooltip:AddLine(
        "Targeting: " .. target,
        color.r, color.g, color.b
      )
      return
    end
  end

  GameTooltip:AddLine(
    "Targeting: " .. target,
    0.8, 0.8, 0.8
  )
end

--------------------------------------------------
-- Guild line
--------------------------------------------------

local function AddGuildLine(unit)
  local guild, rankstr, rankid = GetGuildInfo(unit)

  if not guild then
    return
  end

  local rank = ""
  local lead = ""

  if rankstr then
    rank = " |cffaaaaaa(" .. rankstr .. ")"
  end

  if rankid == 0 then
    lead = "|cffffcc00*|r"
  end

  GameTooltip:AddLine(
    "<" .. guild .. ">" .. lead .. rank,
    0.3, 1, 0.5
  )
end

--------------------------------------------------
-- PvP title
--------------------------------------------------

local function AddPvPTitle(unit, name)
  local pvpname = UnitPVPName(unit)

  if not pvpname or not name or pvpname == name then
    return
  end

  local title = string.gsub(pvpname, " " .. name, "", 1)

  if title ~= "" then
    GameTooltip:AddLine(title, 0.65, 0.65, 0.65)
  end
end

--------------------------------------------------
-- Player level, race and class
--------------------------------------------------

local function AddRaceClassLine(unit)
  if not UnitIsPlayer(unit) then
    return
  end

  local level = UnitLevel(unit)
  local race = UnitRace(unit)
  local _, class = UnitClass(unit)

  local text = ""

  if level and level > 0 then
    text = "Level " .. level
  end

  if race then
    if text ~= "" then
      text = text .. " "
    end
    text = text .. race
  end

  if class then
    if text ~= "" then
      text = text .. " "
    end
    text = text .. string.upper(string.sub(class, 1, 1))
  .. string.lower(string.sub(class, 2))
  end

  if text ~= "" then
    GameTooltip:AddLine(text, 1, 1, 1)
  end
end

--------------------------------------------------
-- Tooltip update
--------------------------------------------------

local function UpdateTooltip()
  if updating or not GameTooltip:IsVisible() then
    return
  end

  local unit

  if target_frame_tooltip then
    unit = "target"
  else
    unit = GetUnit()
  end

  if unit == "none" or not UnitExists(unit) then
    current_unit = "none"
    GameTooltipStatusBar:Hide()
    return
  end

  local title = GameTooltipTextLeft1:GetText()
  if decorated_unit == unit
    and decorated_source == tooltip_source then
    current_unit = unit
    UpdateBarVisibility()
    return
  end

  updating = true
  current_unit = unit
  decorated_unit = unit
  decorated_source = tooltip_source
  decorated_title = title

  local name = UnitName(unit)
  local _, class = UnitClass(unit)

  ------------------------------------------------
  -- Compact tooltip: players only
  ------------------------------------------------

  if target_frame_tooltip and UnitIsPlayer(unit) then
    GameTooltip:ClearLines()

    if name then
      local color = class and RAID_CLASS_COLORS[class]

      if color then
        GameTooltip:SetText(
          name,
          color.r, color.g, color.b
        )

        GameTooltipStatusBar:SetStatusBarColor_orig(
          color.r, color.g, color.b
        )
      else
        GameTooltip:SetText(name, 1, 1, 1)
      end

      AddRaceClassLine(unit)
      AddPvPTitle(unit, name)
      AddGuildLine(unit)
      AddTargetLine(unit)
    end

  ------------------------------------------------
  -- Original tooltip: NPCs and ordinary tooltips
  ------------------------------------------------

  else
    -- Do not clear or rebuild the original NPC tooltip.
    -- Only modify the name color for players.
    if name then
      if UnitIsPlayer(unit) and class then
        local color = RAID_CLASS_COLORS[class]

        if color then
          GameTooltipStatusBar:SetStatusBarColor_orig(
            color.r, color.g, color.b
          )

          GameTooltipTextLeft1:SetText(
            rgbhex(color.r, color.g, color.b, color.a) .. name
          )
        else
          GameTooltipTextLeft1:SetText(
            "|cff999999" .. name .. "|r"
          )
        end

      else
        -- Preserve NPC name and its original tooltip text.
        local reaction = UnitReaction(unit, "player")

        if reaction then
          local color = UnitReactionColor[reaction]

          if color then
            GameTooltipStatusBar:SetStatusBarColor_orig(
              color.r, color.g, color.b
            )
          end
        end
      end

      AddPvPTitle(unit, name)
      AddGuildLine(unit)
      AddTargetLine(unit)
    end
  end

  updating = false

  GameTooltip:Show()
  UpdateBarVisibility()
end

--------------------------------------------------
-- Reset state
--------------------------------------------------

local function ResetTooltip()
  current_unit = "none"
  target_frame_tooltip = false
  updating = false
  tooltip_source = "none"
  tooltip_owner = nil
  anchor_event = false
  anchor_parent = nil
  decorated_unit = nil
  decorated_source = nil
  decorated_title = nil
end

--------------------------------------------------
-- Module setup
--------------------------------------------------

module.enable = function(self)
  ----------------------------------------------
  -- Health bar appearance
  ----------------------------------------------

  GameTooltipStatusBar:SetHeight(10)
  GameTooltipStatusBar:ClearAllPoints()

  GameTooltipStatusBar:SetPoint(
    "BOTTOMLEFT", GameTooltip, "TOPLEFT", 4, 2
  )

  GameTooltipStatusBar:SetPoint(
    "BOTTOMRIGHT", GameTooltip, "TOPRIGHT", -4, 2
  )

  GameTooltipStatusBar.bg =
    GameTooltipStatusBar:CreateTexture(nil, "BACKGROUND")

  GameTooltipStatusBar.bg:SetTexture(
    "Interface\\TARGETINGFRAME\\UI-StatusBar"
  )

  GameTooltipStatusBar.bg:SetVertexColor(0.1, 0.1, 0, 0.8)
  GameTooltipStatusBar.bg:SetAllPoints(true)

  GameTooltipStatusBar.backdrop = CreateFrame(
    "Frame",
    "GameTooltipStatusBarBackdrop",
    GameTooltipStatusBar
  )

  GameTooltipStatusBar.backdrop:SetPoint(
    "TOPLEFT", GameTooltipStatusBar, "TOPLEFT", -3, 3
  )

  GameTooltipStatusBar.backdrop:SetPoint(
    "BOTTOMRIGHT", GameTooltipStatusBar, "BOTTOMRIGHT", 3, -3
  )

  GameTooltipStatusBar.backdrop:SetBackdrop(backdrop)

  GameTooltipStatusBar.backdrop:SetBackdropBorderColor(
    0.8, 0.8, 0.8, 1
  )

  GameTooltipStatusBar.backdrop.health =
    GameTooltipStatusBar.backdrop:CreateFontString(
      "Status", "DIALOG", "GameFontWhite"
    )

  GameTooltipStatusBar.backdrop.health:SetFont(
    STANDARD_TEXT_FONT, 12, "OUTLINE"
  )

  GameTooltipStatusBar.backdrop.health:SetPoint("TOP", 0, 4)
  GameTooltipStatusBar.backdrop.health:SetNonSpaceWrap(false)

  ----------------------------------------------
  -- Preserve Blizzard's original status-bar setter
  ----------------------------------------------

  GameTooltipStatusBar.SetStatusBarColor_orig =
    GameTooltipStatusBar.SetStatusBarColor

  GameTooltipStatusBar.SetStatusBarColor = function()
    return
  end

  ----------------------------------------------
  -- Tooltip events
  ----------------------------------------------

  local oldTooltipShow = GameTooltip:GetScript("OnShow")

  GameTooltip:SetScript("OnShow", function()
    if oldTooltipShow then
      oldTooltipShow()
    end

    decorated_unit = nil
    decorated_source = nil
    decorated_title = nil

    if target_frame_tooltip then
      tooltip_source = "target-frame"
    elseif anchor_event and (GetTime() - anchor_time) <= ANCHOR_WINDOW then
      tooltip_source = "world"
      tooltip_owner = anchor_parent
    else
      tooltip_source = "unknown"
      tooltip_owner = nil
    end

    anchor_event = false
    anchor_parent = nil

    if not target_frame_tooltip then
      UpdateTooltip()
    end
  end)

  local oldTooltipHide = GameTooltip:GetScript("OnHide")

  GameTooltip:SetScript("OnHide", function()
    if oldTooltipHide then
      oldTooltipHide()
    end

    ResetTooltip()
  end)

  ----------------------------------------------
  -- Target-frame hooks
  ----------------------------------------------

  local function HookUnitFrame(frame)
    if not frame or frame.tooltipDetailsHooked then
      return
    end

    frame.tooltipDetailsHooked = true

    local oldEnter = frame:GetScript("OnEnter")

    frame:SetScript("OnEnter", function()
      target_frame_tooltip = true
      tooltip_source = "target-frame"
      tooltip_owner = frame
      current_unit = "target"

      if oldEnter then
        oldEnter()
      end

      if UnitExists("target") and GameTooltip:IsVisible() then
        UpdateTooltip()
      end
    end)

    local oldLeave = frame:GetScript("OnLeave")

    frame:SetScript("OnLeave", function()
      if oldLeave then
        oldLeave()
      end

      ResetTooltip()
    end)
  end

  HookUnitFrame(TargetFrame)
  HookUnitFrame(TargetFramePortrait)

  ----------------------------------------------
  -- Tooltip context events
  ----------------------------------------------

  local context = CreateFrame("Frame")
  context:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
  context:RegisterEvent("PLAYER_TARGET_CHANGED")
  context:SetScript("OnEvent", function()
    -- Mouseover/target events are signals, not proof that the visible tooltip
    -- has changed. Do not re-append lines to an already decorated tooltip.
    if target_frame_tooltip and not UnitExists("target") then
      GameTooltip:Hide()
    elseif event == "PLAYER_TARGET_CHANGED" and target_frame_tooltip
      and GameTooltip:IsVisible() then
      decorated_unit = nil
      decorated_source = nil
      decorated_title = nil
      UpdateTooltip()
    end
  end)

  ----------------------------------------------
  -- Health-bar visibility driver
  ----------------------------------------------

  local driver = CreateFrame("Frame")

  driver:SetScript("OnUpdate", function()
    if GameTooltip:IsVisible() then
      UpdateBarVisibility()
    end
  end)

  ----------------------------------------------
  -- Mouseover health estimation
  ----------------------------------------------

  local statusbar = CreateFrame(
    "Frame", nil, GameTooltipStatusBar
  )

  statusbar:RegisterEvent("UPDATE_MOUSEOVER_UNIT")

  statusbar:SetScript("OnEvent", function()
    this.name = UnitName("mouseover")
    this.level = UnitLevel("mouseover")
  end)

  statusbar:SetScript("OnUpdate", function()
    if not GameTooltipStatusBar:IsVisible() then
      GameTooltipStatusBar.backdrop.health:SetText("")
      return
    end

    if target_frame_tooltip or current_unit ~= "mouseover" then
      GameTooltipStatusBar.backdrop.health:SetText("")
      return
    end

    local hp = GameTooltipStatusBar:GetValue()
    local _, hpmax = GameTooltipStatusBar:GetMinMaxValues()

    local rhp, rhpmax, estimated
    local normalized = false

    if hpmax > 100 or round(hpmax / 100 * hp) ~= hp then
      rhp, rhpmax = hp, hpmax
    else
      normalized = true

      rhp, rhpmax, estimated =
        ShaguTweaks.libhealth:GetUnitHealthByName(
          this.name,
          this.level,
          tonumber(hp),
          tonumber(hpmax)
        )
    end

    if not rhp or not rhpmax or (normalized and not estimated) then
      GameTooltipStatusBar.backdrop.health:SetText("")
      return
    end

    local text = "Health " .. Abbreviate(rhp)
      .. " / " .. Abbreviate(rhpmax)

    if estimated then
      text = "Health ~" .. Abbreviate(rhp)
        .. " / ~" .. Abbreviate(rhpmax)
    end

    GameTooltipStatusBar.backdrop.health:SetText(text)
  end)
end