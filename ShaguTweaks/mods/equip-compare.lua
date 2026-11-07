local _G = ShaguTweaks.GetGlobalEnv()
local T = ShaguTweaks.T

-- Port of pfUI's eqcompare.lua. Needs the ClassicAPI DLL (hooksecurefunc,
-- C_Item.IsEquippedItem, GameTooltip:SetHyperlinkCompareItem, HookScript, ...).
-- Disable the "Item Compare" module while this one is enabled, or every item
-- gets compared twice.

local module = ShaguTweaks:register({
  title = T["Equipment Compare"],
  description = T["Shows the equipped items on tooltips while the shift key is pressed, using the client's own compare data (requires ClassicAPI)."],
  expansions = { ["vanilla"] = true, ["tbc"] = nil },
  category = T["Tooltip & Items"],
  enabled = true,
})

module.enable = function(self)
  -- pfUI's "tooltip.compare.showalways" option: true compares without shift
  -- for every item that is not already equipped
  local SHOW_ALWAYS = false

  -- everything below depends on ClassicAPI: bail out quietly if it is not loaded
  if not hooksecurefunc then return end
  if not (ShoppingTooltip1 and ShoppingTooltip1.SetHyperlinkCompareItem) then return end

  local function IsEquipped(link)
    if C_Item and C_Item.IsEquippedItem then
      return C_Item.IsEquippedItem(link)
    end
    return false
  end

  -- frame:HookScript comes from ClassicAPI; fall back to wrapping the script
  local function HookScript(frame, name, fn)
    if frame.HookScript then
      frame:HookScript(name, fn)
    else
      local old = frame:GetScript(name)
      frame:SetScript(name, function()
        if old then old() end
        fn(this)
      end)
    end
  end

  -- run a function on the next frame
  local queue = {}
  local runner = CreateFrame("Frame")
  runner:SetScript("OnUpdate", function()
    local n = getn(queue)
    if n == 0 then return end
    local run = queue
    queue = {}
    for i = 1, n do run[i]() end
  end)
  local function RunNextFrame(fn)
    tinsert(queue, fn)
  end

  -- the game's own compare would fight with ours
  if GameTooltip_ShowCompareItem then
    GameTooltip_ShowCompareItem = function() end
  end

  ---------------------------------------------------------------- compare

  local function ShowCompareItem(tooltip, link, shift)
    tooltip = tooltip or GameTooltip
    shift = shift or IsShiftKeyDown()

    if not link then return end
    if not shift and (not SHOW_ALWAYS or IsEquipped(link)) then return end

    local tips = tooltip.shoppingTooltips or { ShoppingTooltip1, ShoppingTooltip2 }
    local shopping1, shopping2 = tips[1], tips[2]

    local SEPARATION = 6
    local backdrop = shopping1.GetBackdrop and shopping1:GetBackdrop()
    local GAP = SEPARATION + ((type(backdrop) == "table" and backdrop.edgeSize) or 0)

    local item1, item2 = nil, nil
    local side = "left"
    if shopping1:SetHyperlinkCompareItem(link, 1, shift, tooltip) then item1 = true end
    if shopping2:SetHyperlinkCompareItem(link, 2, shift, tooltip) then item2 = true end

    -- find correct side
    local leftPos = tooltip:GetLeft() or 0
    local rightPos = tooltip:GetRight() or 0
    local rightDist = GetScreenWidth() - rightPos

    if leftPos and (rightDist < leftPos) then
      side = "left"
    else
      side = "right"
    end

    -- see if we should slide the tooltip
    local anchorType = tooltip.GetAnchorType and tooltip:GetAnchorType()
    if anchorType and anchorType ~= "ANCHOR_PRESERVE" and tooltip.SetAnchorType then
      local totalWidth = 0
      if item1 then totalWidth = totalWidth + shopping1:GetWidth() end
      if item2 then totalWidth = totalWidth + shopping2:GetWidth() end

      if side == "left" and totalWidth > leftPos then
        tooltip:SetAnchorType(anchorType, (totalWidth - leftPos), 0)
      elseif side == "right" and (rightPos + totalWidth) > GetScreenWidth() then
        tooltip:SetAnchorType(anchorType, -((rightPos + totalWidth) - GetScreenWidth()), 0)
      end
    end

    if item1 then
      shopping1:SetOwner(tooltip, "ANCHOR_NONE")
      shopping1:ClearAllPoints()
      if side == "left" then
        shopping1:SetPoint("TOPRIGHT", tooltip, "TOPLEFT", -GAP, -10)
      else
        shopping1:SetPoint("TOPLEFT", tooltip, "TOPRIGHT", GAP, -10)
      end
      shopping1:SetHyperlinkCompareItem(link, 1, shift, tooltip)
      shopping1:Show()

      if item2 then
        shopping2:SetOwner(shopping1, "ANCHOR_NONE")
        shopping2:ClearAllPoints()
        if side == "left" then
          shopping2:SetPoint("TOPRIGHT", shopping1, "TOPLEFT", -GAP, 0)
        else
          shopping2:SetPoint("TOPLEFT", shopping1, "TOPRIGHT", GAP, 0)
        end
        shopping2:SetHyperlinkCompareItem(link, 2, shift, tooltip)
        shopping2:Show()
      end
    end
  end

  local function HideCompareItem(tooltip)
    local tips = tooltip.shoppingTooltips or { ShoppingTooltip1, ShoppingTooltip2 }
    tips[1]:Hide()
    tips[2]:Hide()
  end

  ---------------------------------------------------------------- merchant / auction

  -- the game asks for these on shift-hover in the vendor and auction frames;
  -- they always compare, so they pass shift = 1
  local prevMerchant = ShoppingTooltip1.SetMerchantCompareItem
  local function SetMerchantCompareItem(tip, index, compareItem)
    if compareItem == 1 then
      ShowCompareItem(nil, GetMerchantItemLink(index), 1)
      return false
    end
    return prevMerchant and prevMerchant(tip, index, compareItem)
  end

  local prevAuction = ShoppingTooltip1.SetAuctionCompareItem
  local function SetAuctionCompareItem(tip, type, index, compareItem)
    if compareItem == 1 then
      ShowCompareItem(nil, GetAuctionItemLink(type, index), 1)
      return false
    end
    return prevAuction and prevAuction(tip, type, index, compareItem)
  end

  ShoppingTooltip1.SetMerchantCompareItem = SetMerchantCompareItem
  ShoppingTooltip2.SetMerchantCompareItem = SetMerchantCompareItem
  ShoppingTooltip1.SetAuctionCompareItem  = SetAuctionCompareItem
  ShoppingTooltip2.SetAuctionCompareItem  = SetAuctionCompareItem

  ---------------------------------------------------------------- tooltip hooks

  -- tooltip setter -> function that turns its arguments into an item link
  local TooltipHooks = {
    SetLootRollItem = GetLootRollItemLink,
    SetLootItem = GetLootSlotLink,
    SetQuestLogItem = GetQuestLogItemLink,
    SetQuestItem = GetQuestItemLink,
    SetHyperlink = function(link) return link end,
    SetBagItem = GetContainerItemLink,
    SetInboxItem = GetInboxItemLink,
    SetInventoryItem = GetInventoryItemLink,
    SetTradeSkillItem = function(skillIndex, reagentIndex)
      if reagentIndex then
        return GetTradeSkillReagentItemLink(skillIndex, reagentIndex)
      else
        return GetTradeSkillItemLink(skillIndex)
      end
    end,
    SetAuctionSellItem = GetAuctionSellItemLink,
    SetTradePlayerItem = GetTradePlayerItemLink,
    SetTradeTargetItem = GetTradeTargetItemLink,
  }

  -- Guda anchors its item tooltips with ANCHOR_NONE and its own SetPoint, and
  -- other tooltip modules then move every ANCHOR_NONE tooltip. Reading the rect
  -- inside the Set* call picks the side against the position the tooltip is
  -- about to leave, so place the compare a frame later.
  local deferred = false
  ShaguTweaks.HookAddonOrVariable("Guda", function()
    deferred = true
  end)

  -- the item each hooked tooltip shows, for MODIFIER_STATE_CHANGED. Every Set*
  -- clears the tooltip before it builds, so OnTooltipCleared drops the link of
  -- the previous content before the hook stores the new one.
  local links = {}
  local function forget(tip)
    tip = tip or this
    links[tip] = nil
  end

  local function makeHook(getter)
    return function(tooltip, arg1, arg2, arg3)
      local link = getter(arg1, arg2, arg3)
      links[tooltip] = link
      if not deferred then
        return ShowCompareItem(tooltip, link)
      end
      RunNextFrame(function()
        if tooltip:IsShown() then
          ShowCompareItem(tooltip, link)
        end
      end)
    end
  end

  local function HookTooltip(tooltip)
    for setter, getter in pairs(TooltipHooks) do
      -- skip setters or link getters this client does not have
      if getter and tooltip[setter] then
        hooksecurefunc(tooltip, setter, makeHook(getter))
      end
    end
    HookScript(tooltip, "OnTooltipCleared", forget)
    HookScript(tooltip, "OnHide", forget)
  end

  -- pressing or releasing shift over an item toggles its comparison at once.
  -- Merchant and auction comparisons show regardless of shift and never set
  -- a link, so they stay up.
  local modifier = CreateFrame("Frame")
  modifier:RegisterEvent("MODIFIER_STATE_CHANGED")
  modifier:SetScript("OnEvent", function()
    local key = arg1
    if key ~= "LSHIFT" and key ~= "RSHIFT" then return end

    local shift = IsShiftKeyDown()
    for tooltip, link in pairs(links) do
      -- a hidden tooltip got its item from a scan, not a hover
      if tooltip:IsShown() then
        if shift then
          ShowCompareItem(tooltip, link, shift)
        elseif not SHOW_ALWAYS or IsEquipped(link) then
          HideCompareItem(tooltip)
        end
      end
    end
  end)

  HookTooltip(GameTooltip)
end
