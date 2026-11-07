local _G = ShaguTweaks.GetGlobalEnv()
local T = ShaguTweaks.T

local module = ShaguTweaks:register({
  title = T["Item Compare"] or "Item Compare",
  description = T["Shows equipped-item comparisons while holding Shift, and in merchant/auction tooltips."],
  expansions = { ["vanilla"] = true, ["tbc"] = true },
  category = T["Tooltip & Items"] or "Tooltip & Items",
  enabled = true,
})

module.enable = function(self)
  -- Vanilla's ShoppingTooltip comparison API does the actual equipped-item
  -- selection. This module only hooks item tooltips and positions the results.
  if not (ShoppingTooltip1 and ShoppingTooltip2
      and ShoppingTooltip1.SetHyperlinkCompareItem
      and ShoppingTooltip2.SetHyperlinkCompareItem) then
    return
  end

  local links = {}

  local function IsEquippedItem(link)
    if not link then return false end
    for slot = 1, 19 do
      if GetInventoryItemLink("player", slot) == link then
        return true
      end
    end
    return false
  end

  local function HideCompare(tooltip)
    local shopping1, shopping2 = unpack(tooltip and tooltip.shoppingTooltips
      or { ShoppingTooltip1, ShoppingTooltip2 })
    if shopping1 then shopping1:Hide() end
    if shopping2 then shopping2:Hide() end
  end

  local function ShowCompareItem(tooltip, link, shift)
    tooltip = tooltip or GameTooltip
    shift = shift
    if shift == nil then shift = IsShiftKeyDown() end

    if not link or (not shift and IsEquippedItem(link)) then
      HideCompare(tooltip)
      return
    end
    if not shift then
      HideCompare(tooltip)
      return
    end

    local shopping1, shopping2 = unpack(tooltip.shoppingTooltips
      or { ShoppingTooltip1, ShoppingTooltip2 })
    if not shopping1 or not shopping2 then return end

    local item1 = shopping1:SetHyperlinkCompareItem(link, 1, shift, tooltip)
    local item2 = shopping2:SetHyperlinkCompareItem(link, 2, shift, tooltip)
    if not item1 then
      HideCompare(tooltip)
      return
    end

    local left = tooltip:GetLeft() or 0
    local right = tooltip:GetRight() or 0
    local rightDistance = GetScreenWidth() - right
    local side = rightDistance < left and "left" or "right"
    local gap = 6

    -- Include the tooltip border width when the client exposes it.
    local backdrop = shopping1.GetBackdrop and shopping1:GetBackdrop()
    if type(backdrop) == "table" and backdrop.edgeSize then
      gap = gap + backdrop.edgeSize
    end

    -- Shift the parent tooltip inward if the comparison would leave the screen.
    if tooltip.GetAnchorType and tooltip.SetAnchorType then
      local anchor = tooltip:GetAnchorType()
      if anchor and anchor ~= "ANCHOR_PRESERVE" then
        local totalWidth = shopping1:GetWidth()
        if item2 then totalWidth = totalWidth + shopping2:GetWidth() end
        if side == "left" and totalWidth > left then
          tooltip:SetAnchorType(anchor, totalWidth - left, 0)
        elseif side == "right" and right + totalWidth > GetScreenWidth() then
          tooltip:SetAnchorType(anchor, -(right + totalWidth - GetScreenWidth()), 0)
        end
      end
    end

    shopping1:SetOwner(tooltip, "ANCHOR_NONE")
    shopping1:ClearAllPoints()
    if side == "left" then
      shopping1:SetPoint("TOPRIGHT", tooltip, "TOPLEFT", -gap, -10)
    else
      shopping1:SetPoint("TOPLEFT", tooltip, "TOPRIGHT", gap, -10)
    end
    shopping1:SetHyperlinkCompareItem(link, 1, shift, tooltip)
    shopping1:Show()

    if item2 then
      shopping2:SetOwner(shopping1, "ANCHOR_NONE")
      shopping2:ClearAllPoints()
      if side == "left" then
        shopping2:SetPoint("TOPRIGHT", shopping1, "TOPLEFT", -gap, 0)
      else
        shopping2:SetPoint("TOPLEFT", shopping1, "TOPRIGHT", gap, 0)
      end
      shopping2:SetHyperlinkCompareItem(link, 2, shift, tooltip)
      shopping2:Show()
    else
      shopping2:Hide()
    end
  end

  local TooltipHooks = {
    SetLootRollItem = GetLootRollItemLink,
    SetLootItem = GetLootSlotLink,
    SetQuestLogItem = GetQuestLogItemLink,
    SetQuestItem = GetQuestItemLink,
    SetHyperlink = function(link) return link end,
    SetBagItem = GetContainerItemLink,
    SetInventoryItem = GetInventoryItemLink,
    SetTradeSkillItem = function(skillIndex, reagentIndex)
      if reagentIndex and GetTradeSkillReagentItemLink then
        return GetTradeSkillReagentItemLink(skillIndex, reagentIndex)
      elseif GetTradeSkillItemLink then
        return GetTradeSkillItemLink(skillIndex)
      end
    end,
    SetAuctionSellItem = GetAuctionSellItemLink,
    SetTradePlayerItem = GetTradePlayerItemLink,
    SetTradeTargetItem = GetTradeTargetItemLink,
    SetInboxItem = GetInboxItemLink,
  }

  local function HookTooltip(tooltip)
    if not tooltip then return end
    for method, getter in pairs(TooltipHooks) do
      if getter then
        -- Lua 5.0 has no vararg table. Use a small explicit wrapper for the
        -- arguments accepted by the tooltip setters.
        if type(tooltip[method]) == "function" then
          local methodName, linkGetter = method, getter
          local original = tooltip[methodName]
          tooltip[methodName] = function(frame, a1, a2, a3)
            local link = linkGetter(a1, a2, a3)
            local result = original(frame, a1, a2, a3)
            links[frame] = link
            ShowCompareItem(frame, link)
            return result
          end
        end
      end
    end

    if tooltip.HookScript then
      tooltip:HookScript("OnHide", function()
        links[tooltip] = nil
        HideCompare(tooltip)
      end)
      tooltip:HookScript("OnTooltipCleared", function()
        links[tooltip] = nil
      end)
    end
  end

  -- Merchant and auction comparisons are requested by the Blizzard UI without
  -- Shift. Route the first comparison through the same positioning routine.
  if ShoppingTooltip1.SetMerchantCompareItem then
    local original = ShoppingTooltip1.SetMerchantCompareItem
    local function MerchantCompare(frame, index, compareItem)
      if compareItem == 1 then
        ShowCompareItem(GameTooltip, GetMerchantItemLink(index), true)
        return false
      end
      if original then return original(frame, index, compareItem) end
    end
    ShoppingTooltip1.SetMerchantCompareItem = MerchantCompare
    ShoppingTooltip2.SetMerchantCompareItem = MerchantCompare
  end

  if ShoppingTooltip1.SetAuctionCompareItem then
    local original = ShoppingTooltip1.SetAuctionCompareItem
    local function AuctionCompare(frame, auctionType, index, compareItem)
      if compareItem == 1 then
        ShowCompareItem(GameTooltip, GetAuctionItemLink(auctionType, index), true)
        return false
      end
      if original then return original(frame, auctionType, index, compareItem) end
    end
    ShoppingTooltip1.SetAuctionCompareItem = AuctionCompare
    ShoppingTooltip2.SetAuctionCompareItem = AuctionCompare
  end

  HookTooltip(GameTooltip)
  if ItemRefTooltip then HookTooltip(ItemRefTooltip) end

  -- Refresh comparisons immediately when Shift is pressed or released.
  local events = CreateFrame("Frame")
  events:RegisterEvent("MODIFIER_STATE_CHANGED")
  events:SetScript("OnEvent", function()
    local shift = IsShiftKeyDown()
    for tooltip, link in pairs(links) do
      if tooltip and tooltip.IsShown and tooltip:IsShown() then
        if shift then
          ShowCompareItem(tooltip, link, true)
        else
          HideCompare(tooltip)
        end
      end
    end
  end)
end
