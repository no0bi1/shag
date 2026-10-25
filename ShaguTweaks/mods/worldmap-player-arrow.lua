local _G = ShaguTweaks.GetGlobalEnv()
local T = ShaguTweaks.T

local module = ShaguTweaks:register({
  title = T["Large World Map Player Arrow"],
  description = T["Displays a larger player arrow on the World Map."],
  expansions = { ["vanilla"] = true, ["tbc"] = true },
  category = T["World & MiniMap"],
  enabled = nil,
})

local addonpath
local tocs = { "", "-master", "-tbc", "-wotlk" }

for _, name in pairs(tocs) do
  local current = string.format("ShaguTweaks%s", name)
  local _, title = GetAddOnInfo(current)

  if title then
    addonpath = "Interface\\AddOns\\" .. current
    break
  end
end

local arrow = CreateFrame("Frame", nil, WorldMapFrame)
arrow:SetWidth(32)
arrow:SetHeight(32)
arrow:SetFrameStrata("TOOLTIP")
arrow:SetFrameLevel(999)

local texture = arrow:CreateTexture(nil, "OVERLAY")
texture:SetTexture(addonpath .. "\\img\\worldmap_player_arrow")
texture:SetAllPoints(arrow)
texture:Hide()
arrow.texture = texture

local function UpdateArrow()
  local x, y = GetPlayerMapPosition("player")

  if not x or not y or (x == 0 and y == 0) then
    texture:Hide()          -- was arrow:Hide()
    return
  end

  local width = WorldMapDetailFrame:GetWidth()
  local height = WorldMapDetailFrame:GetHeight()

  arrow:ClearAllPoints()
  arrow:SetPoint("CENTER", WorldMapDetailFrame, "TOPLEFT", x * width, -y * height)

  if GetPlayerFacing then   -- guard in case the client lacks it
    local facing = GetPlayerFacing()
    if facing then
      local s = math.sin(facing)
      local c = math.cos(facing)
      texture:SetTexCoord(
        0.5 + (-0.5*c + 0.5*s), 0.5 + (-0.5*s - 0.5*c),
        0.5 + (-0.5*c - 0.5*s), 0.5 + (-0.5*s + 0.5*c),
        0.5 + ( 0.5*c + 0.5*s), 0.5 + ( 0.5*s - 0.5*c),
        0.5 + ( 0.5*c - 0.5*s), 0.5 + ( 0.5*s + 0.5*c)
      )
    end
  end

  texture:Show()
end





module.enable = function(self)
  arrow:Show()

  arrow:SetScript("OnUpdate", function()
    this.elapsed = (this.elapsed or 0) + arg1

    if this.elapsed < 0.05 then
      return
    end

    this.elapsed = 0
    UpdateArrow()
  end)

  UpdateArrow()
end

module.disable = function(self)
  arrow:Hide()
  arrow:SetScript("OnUpdate", nil)
end