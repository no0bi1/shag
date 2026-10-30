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
local tooltip_owner = nil
local decorated_key = nil
local refresh_pending = false
local updating = false

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
  local title = GameTooltipTextLeft1:GetText()

  if not title then
    return "none"
  end

  -- Prefer the live mouseover when it matches the tooltip currently shown.
  -- Cached unit state is only trusted when it still matches the tooltip title.
  if MatchUnit("mouseover", title) then
    return "mouseover"
  end

  if target_frame_tooltip and MatchUnit("target", title) then
    return "target"
  end

  if current_unit ~= "none" and MatchUnit(current_unit, title) then
    return current_unit
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

  -- Hide health bars for party members.
  if string.find(unit, "^party%d+$") then
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

  -- Tooltip updates can run more than once while Blizzard is still
  -- populating an NPC tooltip. Avoid appending the same target line twice.
  local targetLine = "Targeting: " .. target
  for i = 1, GameTooltip:NumLines() do
    local line = _G["GameTooltipTextLeft" .. i]
    local text = line and line:GetText()

    if text and string.find(text, targetLine, 1, true) then
      return
    end
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
    GameTooltip:AddLine(text .. " (Player)", 1, 1, 1)
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
    return
  end

  updating = true
  current_unit = unit

  local name = UnitName(unit)
  local _, class = UnitClass(unit)
  local target_name = UnitName(unit .. "target")
  local key = table.concat({
    unit,
    name or "",
    target_name or "",
    target_frame_tooltip and "target-frame" or "world"
  }, ":")

  -- Tooltip refreshes can occur repeatedly while the cursor remains still.
  -- Only decorate once for the current tooltip content.
  if decorated_key == key then
    updating = false
    UpdateBarVisibility()
    return
  end

  ------------------------------------------------
  -- Blizzard original-expansion player tooltip layout
  ------------------------------------------------

  if UnitIsPlayer(unit) then
    GameTooltip:ClearLines()

    if name then
      local pvpname = UnitPVPName(unit)
      local title = ""

      if pvpname and pvpname ~= name then
        title = string.gsub(pvpname, " " .. name, "", 1)
      end

      -- Color the title and character name independently. SetText's
      -- color arguments tint the entire line, so use inline color codes.
      local color = class and RAID_CLASS_COLORS[class]
      local display_name = name

      if color then
        display_name = rgbhex(
          color.r, color.g, color.b, color.a
        ) .. name .. "|r"

        GameTooltipStatusBar:SetStatusBarColor_orig(
          color.r, color.g, color.b
        )
      else
        display_name = "|cffffffff" .. name .. "|r"
      end

      if title ~= "" then
        display_name = "|cffaaaaaa" .. title .. " |r" .. display_name
      end

      GameTooltip:SetText(display_name, 1, 1, 1)

      AddRaceClassLine(unit)
      AddGuildLine(unit)
      AddTargetLine(unit)
    end

  ------------------------------------------------
  -- Preserve Blizzard's original NPC tooltip
  ------------------------------------------------

  else
    if name then
      local reaction = UnitReaction(unit, "player")

      if reaction then
        local color = UnitReactionColor[reaction]

        if color then
          GameTooltipStatusBar:SetStatusBarColor_orig(
            color.r, color.g, color.b
          )
        end
      end

      -- Retain the existing target detail for NPC tooltips.
      AddTargetLine(unit)
    end
  end

  decorated_key = key
  refresh_pending = false
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
  tooltip_owner = nil
  decorated_key = nil
  refresh_pending = false
  updating = false
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
    "TOPLEFT", GameTooltip, "BOTTOMLEFT", 4, -2
  )

  GameTooltipStatusBar:SetPoint(
    "TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -4, -2
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
  -- Explicit tooltip state tracking
  ----------------------------------------------

  -- Track who anchored the tooltip. The wrapper preserves Blizzard's call
  -- and arguments; it only records state for GameTooltip.
  local originalSetDefaultAnchor = _G.GameTooltip_SetDefaultAnchor
  if originalSetDefaultAnchor and not _G.ShaguTweaksTooltipDetailsAnchorHooked then
    _G.GameTooltip_SetDefaultAnchor = function(tooltip, parent, ...)
      if tooltip == GameTooltip then
        tooltip_owner = parent
        decorated_key = nil
        refresh_pending = true
      end
      return originalSetDefaultAnchor(tooltip, parent, ...)
    end
    _G.ShaguTweaksTooltipDetailsAnchorHooked = true
  end

  -- Blizzard clears lines when reusing a tooltip for different content.
  -- Treat that as a new content generation so our added lines can be rebuilt.
  if not GameTooltip.tooltipDetailsClearLinesHooked then
    local originalClearLines = GameTooltip.ClearLines
    GameTooltip.ClearLines = function(...)
      decorated_key = nil
      refresh_pending = true
      return originalClearLines(...)
    end
    GameTooltip.tooltipDetailsClearLinesHooked = true
  end

  ----------------------------------------------
  -- Tooltip events
  ----------------------------------------------

  local oldTooltipShow = GameTooltip:GetScript("OnShow")

  GameTooltip:SetScript("OnShow", function()
    if oldTooltipShow then
      oldTooltipShow()
    end

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
      if oldEnter then
        oldEnter()
      end

      -- The original handler may hide/recreate the tooltip, firing our
      -- OnHide reset and clearing target_frame_tooltip. Set target state
      -- after Blizzard's handler so an NPC mouseover cannot win detection.
      target_frame_tooltip = true
      current_unit = "target"
      decorated_key = nil
      refresh_pending = false

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
  -- Event-driven tooltip and health-bar updates
  ----------------------------------------------

  local driver = CreateFrame("Frame")
  driver:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
  driver:RegisterEvent("PLAYER_TARGET_CHANGED")
  driver:RegisterEvent("UNIT_HEALTH")
  driver:RegisterEvent("UNIT_MAXHEALTH")
  driver:RegisterEvent("UNIT_FLAGS")
  driver:RegisterEvent("PLAYER_ENTERING_WORLD")

  driver:SetScript("OnEvent", function()
    if not GameTooltip:IsVisible() then
      return
    end

    if event == "UPDATE_MOUSEOVER_UNIT" or event == "PLAYER_TARGET_CHANGED" then
      -- Let Blizzard finish changing the tooltip content first. The one-shot
      -- refresh below resolves the unit against the updated title.
      decorated_key = nil
      refresh_pending = true
    else
      UpdateBarVisibility()
    end
  end)

  driver:SetScript("OnUpdate", function()
    -- Fallback for tooltip content that changes after its event fires.
    -- This runs only while a refresh is pending, not every frame.
    if refresh_pending and GameTooltip:IsVisible() then
      refresh_pending = false
      UpdateTooltip()
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
