
local module = ShaguTweaks:register({
  title = "Equipment Compare",
  description = "Shows equipped item comparisons when holding Shift.",
  expansions = { ["vanilla"] = true, ["tbc"] = true },
  category = nil,
  enabled = true,
})

-- Global code:
local _G = ShaguTweaks.GetGlobalEnv()

module.enable = function(self)

  local links = {}

  local function ShowCompareItem(tooltip, link, shift)
    tooltip = tooltip or GameTooltip
    shift = shift or IsShiftKeyDown()

    if not link or not shift
      or (C_Item and C_Item.IsEquippedItem
        and C_Item.IsEquippedItem(link)) then
      return
    end

    local shoppingTooltip1, shoppingTooltip2 =
      unpack(tooltip.shoppingTooltips or {
        ShoppingTooltip1,
        ShoppingTooltip2,
      })

    local separation = -20
    local backdrop = shoppingTooltip1.GetBackdrop
      and shoppingTooltip1:GetBackdrop()

    local gap = separation +
      ((type(backdrop) == "table" and backdrop.edgeSize) or 0)

    local item1 = shoppingTooltip1:SetHyperlinkCompareItem(
      link, 1, shift, tooltip
    )

    local item2 = shoppingTooltip2:SetHyperlinkCompareItem(
      link, 2, shift, tooltip
    )

    if not item1 and not item2 then
      return
    end

    -- Determine which side has more available screen space.
    local leftPos = tooltip:GetLeft() or 0
    local rightPos = tooltip:GetRight() or 0

    local rightDist = GetScreenWidth() - rightPos
    local side = rightDist < leftPos and "left" or "right"

    -- Move the main tooltip if necessary.
    if tooltip:GetAnchorType()
      and tooltip:GetAnchorType() ~= "ANCHOR_PRESERVE" then

      local totalWidth = 0

      if item1 then
        totalWidth = totalWidth + shoppingTooltip1:GetWidth()
      end

      if item2 then
        totalWidth = totalWidth + shoppingTooltip2:GetWidth()
      end

      if side == "left" and totalWidth > leftPos then
        tooltip:SetAnchorType(
          tooltip:GetAnchorType(),
          totalWidth - leftPos,
          0
        )

      elseif side == "right"
        and rightPos + totalWidth > GetScreenWidth() then

        tooltip:SetAnchorType(
          tooltip:GetAnchorType(),
          -((rightPos + totalWidth) - GetScreenWidth()),
          0
        )
      end
    end

    -- First comparison tooltip.
    if item1 then
      shoppingTooltip1:SetOwner(tooltip, "ANCHOR_NONE")
      shoppingTooltip1:ClearAllPoints()

      if side == "left" then
        shoppingTooltip1:SetPoint(
          "TOPRIGHT", tooltip, "TOPLEFT", -gap, 0
        )
      else
        shoppingTooltip1:SetPoint(
          "TOPLEFT", tooltip, "TOPRIGHT", gap, 0
        )
      end

      shoppingTooltip1:SetHyperlinkCompareItem(
        link, 1, shift, tooltip
      )

      shoppingTooltip1:Show()

      -- Second comparison tooltip.
      if item2 then
        shoppingTooltip2:SetOwner(
          shoppingTooltip1, "ANCHOR_NONE"
        )

        shoppingTooltip2:ClearAllPoints()

        if side == "left" then
          shoppingTooltip2:SetPoint(
            "TOPRIGHT", shoppingTooltip1, "TOPLEFT", -gap, 0
          )
        else
          shoppingTooltip2:SetPoint(
            "TOPLEFT", shoppingTooltip1, "TOPRIGHT", gap, 0
          )
        end

        shoppingTooltip2:SetHyperlinkCompareItem(
          link, 2, shift, tooltip
        )

        shoppingTooltip2:Show()
      end
    end
  end

  local function HideCompareItem(tooltip)
    local shoppingTooltip1, shoppingTooltip2 =
      unpack(tooltip.shoppingTooltips or {
        ShoppingTooltip1,
        ShoppingTooltip2,
      })

    shoppingTooltip1:Hide()
    shoppingTooltip2:Hide()
  end

  --------------------------------------------------
  -- Merchant and auction comparisons
  --------------------------------------------------

  local prevMerchant = ShoppingTooltip1.SetMerchantCompareItem

  local function SetMerchantCompareItem(self, index, compareItem)
    if compareItem == 1 then
      ShowCompareItem(
        nil,
        GetMerchantItemLink(index),
        true
      )
      return false
    end

    return prevMerchant
      and prevMerchant(self, index, compareItem)
  end

  local prevAuction = ShoppingTooltip1.SetAuctionCompareItem

  local function SetAuctionCompareItem(
    self, auctionType, index, compareItem
  )
    if compareItem == 1 then
      ShowCompareItem(
        nil,
        GetAuctionItemLink(auctionType, index),
        true
      )
      return false
    end

    return prevAuction
      and prevAuction(self, auctionType, index, compareItem)
  end

  ShoppingTooltip1.SetMerchantCompareItem = SetMerchantCompareItem
  ShoppingTooltip2.SetMerchantCompareItem = SetMerchantCompareItem

  ShoppingTooltip1.SetAuctionCompareItem = SetAuctionCompareItem
  ShoppingTooltip2.SetAuctionCompareItem = SetAuctionCompareItem

  --------------------------------------------------
  -- Tooltip item link getters
  --------------------------------------------------

  local TooltipHooks = {
    SetLootRollItem = GetLootRollItemLink,
    SetLootItem = GetLootSlotLink,
    SetQuestLogItem = GetQuestLogItemLink,
    SetQuestItem = GetQuestItemLink,

    SetHyperlink = function(link)
      return link
    end,

    SetBagItem = GetContainerItemLink,
    SetInboxItem = GetInboxItemLink,
    SetInventoryItem = GetInventoryItemLink,

    SetTradeSkillItem = function(skillIndex, reagentIndex)
      if reagentIndex then
        return GetTradeSkillReagentItemLink(
          skillIndex, reagentIndex
        )
      else
        return GetTradeSkillItemLink(skillIndex)
      end
    end,

    SetAuctionSellItem = GetAuctionSellItemLink,
    SetTradePlayerItem = GetTradePlayerItemLink,
    SetTradeTargetItem = GetTradeTargetItemLink,
  }

  --------------------------------------------------
  -- Tooltip hooks
  --------------------------------------------------

  local function ForgetTooltip(self)
    links[self] = nil
  end

  local function MakeHook(getter)
    return function(tooltip, arg1, arg2, arg3)
      local link = getter(arg1, arg2, arg3)

      links[tooltip] = link

      ShowCompareItem(tooltip, link)
    end
  end

  local function HookTooltip(tooltip)
    for setter, getter in pairs(TooltipHooks) do
      if tooltip[setter] and hooksecurefunc then
        hooksecurefunc(
          tooltip,
          setter,
          MakeHook(getter)
        )
      end
    end

    tooltip:HookScript("OnTooltipCleared", function()
      links[tooltip] = nil
    end)
    tooltip:HookScript("OnHide", function()
      links[tooltip] = nil
    end)
  end

  --------------------------------------------------
  -- Shift key toggling
  --------------------------------------------------

  local eventFrame = CreateFrame("Frame")

  eventFrame:RegisterEvent("MODIFIER_STATE_CHANGED")

  eventFrame:SetScript("OnEvent", function()
    local shift = IsShiftKeyDown()

    for tooltip, link in pairs(links) do
      if tooltip:IsShown() then
        if shift then
          ShowCompareItem(tooltip, link, true)
        else
          HideCompareItem(tooltip)
        end
      end
    end
  end)

  --------------------------------------------------
  -- Initialize
  --------------------------------------------------

  HookTooltip(GameTooltip)

  --------------------------------------------------
  -- Chat item hyperlinks
  --------------------------------------------------

  local function HookChatFrame(chatFrame)
    if not chatFrame or not chatFrame.HookScript then
      return
    end

    chatFrame:HookScript("OnHyperlinkEnter", function(self, link)
      if not link or not string.find(link, "^item:") then
        return
      end

      links[GameTooltip] = link

      -- SetHyperlink may already have displayed the comparisons.
      if not ShoppingTooltip1:IsShown()
        and not ShoppingTooltip2:IsShown() then
        ShowCompareItem(GameTooltip, link)
      end
    end)

    chatFrame:HookScript("OnHyperlinkLeave", function(self, link)
      if link and string.find(link, "^item:") then
        links[GameTooltip] = nil
        HideCompareItem(GameTooltip)
      end
    end)
  end

  for i = 1, (NUM_CHAT_WINDOWS or 0) do
    HookChatFrame(_G["ChatFrame" .. i])
  end

end
