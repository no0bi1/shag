local T = ShaguTweaks.T

local module = ShaguTweaks:register({
  title = T["Nameplate Castbar"],
  description = T["Adds a castbar to the nameplate using ClassicAPI cast data."],
  expansions = { ["vanilla"] = true, ["tbc"] = false },
  category = T["Nameplates"],
  enabled = true,
})

module.enable = function(self)
  if ShaguPlates then return end

  local backdrop = {
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  }

  local function create_castbar(plate)
    -- create the castbar
    plate.castbar = CreateFrame("StatusBar", nil, plate)
    plate.castbar:SetPoint("BOTTOM", plate, "BOTTOM", 8, -11)
    plate.castbar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    plate.castbar:SetStatusBarColor(1, .8, 0, 1)
    plate.castbar:SetWidth(plate:GetWidth() - 22)
    plate.castbar:SetHeight(10)

    -- create the spell icon
    plate.castbar.texture = CreateFrame("Frame", nil, plate.castbar)
    plate.castbar.texture:SetPoint("RIGHT", plate.castbar, "LEFT", 0, 0)
    plate.castbar.texture:SetHeight(18)
    plate.castbar.texture:SetWidth(18)
    plate.castbar.texture.icon = plate.castbar.texture:CreateTexture(nil, "BACKGROUND")
    plate.castbar.texture.icon:SetPoint("CENTER", 0, 0)
    plate.castbar.texture.icon:SetWidth(12)
    plate.castbar.texture.icon:SetHeight(12)
    plate.castbar.texture:SetBackdrop(backdrop)
    plate.castbar.texture:SetBackdropBorderColor(1,.8,0)

    -- castbar background
    plate.castbar.bg = plate.castbar:CreateTexture(nil, "BACKGROUND")
    plate.castbar.bg:SetTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    plate.castbar.bg:SetVertexColor(.1, .1, 0, .8)
    plate.castbar.bg:SetAllPoints(true)

    -- castbar spark
    plate.castbar.spark = plate.castbar:CreateTexture(nil, "OVERLAY")
    plate.castbar.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    plate.castbar.spark:SetWidth(20)
    plate.castbar.spark:SetHeight(20)
    plate.castbar.spark:SetBlendMode("ADD")

    -- castbar border
    plate.castbar.backdrop = CreateFrame("Frame", nil, plate.castbar)
    plate.castbar.backdrop:SetFrameLevel(plate.castbar:GetFrameLevel())
    plate.castbar.backdrop:SetPoint("TOPLEFT", plate.castbar, "TOPLEFT", -3, 3)
    plate.castbar.backdrop:SetPoint("BOTTOMRIGHT", plate.castbar, "BOTTOMRIGHT", 3, -3)
    plate.castbar.backdrop:SetBackdrop(backdrop)
    plate.castbar.backdrop:SetBackdropBorderColor(1,.8,0)

    -- castbar spellname
    plate.castbar.text = plate.castbar:CreateFontString(nil, "HIGH", "GameFontWhite")
    plate.castbar.text:SetPoint("CENTER", plate.castbar, "CENTER", 0, 0)
    local font, size, opts = plate.castbar.text:GetFont()
    plate.castbar.text:SetFont(font, size - 3, "THINOUTLINE")

    -- hide castbar by default
    plate.castbar:Hide()
  end

  -- ClassicAPI binds each visible engine nameplate to its unit token.
  -- Shagu's libnameplate discovers these same engine frames as its "plate".
  local plateUnits = {}
  local unitPlates = {}

  local events = CreateFrame("Frame")
  events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
  events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
  events:RegisterEvent("PLAYER_ENTERING_WORLD")

  local function BindNamePlate(unit)
    if not unit or not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end

    local previous = plateUnits[plate]
    if previous then unitPlates[previous] = nil end

    plateUnits[plate] = unit
    unitPlates[unit] = plate
  end

  local function UnbindNamePlate(unit)
    local plate = unitPlates[unit]
    if plate then
      plateUnits[plate] = nil
      unitPlates[unit] = nil
      if plate.castbar then plate.castbar:Hide() end
    end
  end

  local function RefreshNamePlates()
    plateUnits = {}
    unitPlates = {}
    if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return end
    for i = 1, 100 do
      BindNamePlate("nameplate" .. i)
    end
  end

  events:SetScript("OnEvent", function()
    if event == "NAME_PLATE_UNIT_ADDED" then
      BindNamePlate(arg1)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
      UnbindNamePlate(arg1)
    elseif event == "PLAYER_ENTERING_WORLD" then
      RefreshNamePlates()
    end
  end)

  -- Read cast data directly from ClassicAPI. The timestamps are milliseconds;
  -- duration objects keep the bar synchronized without manual time arithmetic.
  local function GetCastInfo(unit)
    local name, _, texture, _, _, _, _, _, spellID =
      C_Spell.UnitCastingInfo(unit)
    local duration, isChannel

    if name then
      duration = UnitCastingDuration(unit)
    else
      name, _, texture, _, _, _, _, spellID = C_Spell.UnitChannelInfo(unit)
      if name then
        duration = UnitChannelDuration(unit)
        isChannel = true
      end
    end

    if not name or not duration then return end
    return name, texture, spellID, duration, isChannel, noInterrupt
  end

  -- Create the visual once, then only restamp it when the active cast changes.
  table.insert(ShaguTweaks.libnameplate.OnUpdate, function()
    if not this.castbar then create_castbar(this) end

    local unit = plateUnits[this]
    if not unit or not UnitExists(unit) then
      this.castbar:Hide()
      this.castbar.castKey = nil
      return
    end

    local cast, texture, spellID, duration, isChannel = GetCastInfo(unit)
    if not cast then
      this.castbar:Hide()
      this.castbar.castKey = nil
      return
    end

    local startMs = duration:GetStartTime() * 1000
    local endMs = duration:GetEndTime() * 1000
    local castKey = tostring(spellID or cast) .. ":" .. tostring(startMs) .. ":" .. tostring(endMs) .. ":" .. tostring(isChannel)

    if this.castbar.castKey ~= castKey then
      this.castbar.castKey = castKey
      this.castbar:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate,
        isChannel and Enum.StatusBarTimerDirection.RemainingTime or Enum.StatusBarTimerDirection.ElapsedTime)
      this.castbar.text:SetText(cast)

      if texture then
        this.castbar.texture.icon:SetTexture(texture)
        this.castbar.texture.icon:Show()
      else
        this.castbar.texture.icon:Hide()
      end
    end

    local percent = isChannel and duration:GetRemainingPercent() or duration:GetElapsedPercent()
    local x = this.castbar:GetWidth() * percent
    this.castbar.spark:ClearAllPoints()
    this.castbar.spark:SetPoint("CENTER", this.castbar, "LEFT", x, 0)
    this.castbar:SetAlpha(this:GetAlpha())
    this.castbar:Show()
  end)
end
