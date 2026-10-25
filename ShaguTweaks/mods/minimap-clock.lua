local _G = ShaguTweaks.GetGlobalEnv()
local T = ShaguTweaks.T

local module = ShaguTweaks:register({
  title = T["MiniMap Clock"],
  description = T["Adds a small 12h clock to the mini map."],
  expansions = { ["vanilla"] = true, ["tbc"] = nil },
  category = T["World & MiniMap"],
  enabled = true,
})

MinimapClock = CreateFrame("Frame", "Clock", Minimap)
MinimapClock:Hide()
MinimapClock:SetFrameLevel(64)
MinimapClock:SetPoint("BOTTOM", MinimapCluster, "BOTTOM", 8, 18)
MinimapClock:SetWidth(50)
MinimapClock:SetHeight(23)
MinimapClock:SetBackdrop({
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 8, edgeSize = 16,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
MinimapClock:SetBackdropBorderColor(.9,.8,.5,1)
MinimapClock:SetBackdropColor(.4,.4,.4,1)

module.enable = function(self)
  MinimapClock:Show()
  MinimapClock:EnableMouse(true)

  MinimapClock.text = MinimapClock:CreateFontString("Status", "LOW", "GameFontNormal")
  MinimapClock.text:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
  MinimapClock.text:SetAllPoints(MinimapClock)
  MinimapClock.text:SetFontObject(GameFontWhite)
  MinimapClock:SetScript("OnUpdate", function()
    if ( this.tick or 1) > GetTime() then return else this.tick = GetTime() + 1 end

    local h = tonumber(date("%I"))
    this.text:SetText(h .. date(":%M"))
  end)

  MinimapClock:SetScript("OnEnter", function()
    local h, m = GetGameTime()

    -- Convert server time to 12-hour format
    local suffix = "AM"
    if h >= 12 then
      suffix = "PM"
    end

    if h == 0 then
      h = 12
    elseif h > 12 then
      h = h - 12
    end

    local servertime = string.format("%d:%.2d %s", h, m, suffix)
    local time = tonumber(date("%I")) .. date(":%M %p")

    GameTooltip:ClearLines()
    GameTooltip:SetOwner(this, ANCHOR_BOTTOMLEFT)

    GameTooltip:AddLine(T["Clock"])
    GameTooltip:AddDoubleLine(T["Localtime"], time, 1,1,1,1,1,1)
    GameTooltip:AddDoubleLine(T["Servertime"], servertime, 1,1,1,1,1,1)
    GameTooltip:Show()
  end)

  MinimapClock:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
end