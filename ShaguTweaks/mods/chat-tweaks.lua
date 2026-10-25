local _G = ShaguTweaks.GetGlobalEnv()
local T = ShaguTweaks.T
local scrollspeed = 1

local module = ShaguTweaks:register({
  title = T["Chat Tweaks"],
  description = T["Allows to scroll using the mouse wheel, enables sticky chat channels and repeats message on arrow up."],
  expansions = { ["vanilla"] = true, ["tbc"] = true },
  category = T["Social & Chat"],
  enabled = true,
})

local function ChatOnMouseWheel()
  if arg1 > 0 then
    if IsShiftKeyDown() then
      this:ScrollToTop()
    else
      for i = 1, scrollspeed do
        this:ScrollUp()
      end
    end
  elseif arg1 < 0 then
    if IsShiftKeyDown() then
      this:ScrollToBottom()
    else
      for i = 1, scrollspeed do
        this:ScrollDown()
      end
    end
  end
end

module.enable = function(self)
  -- Sticky chat types
  ChatTypeInfo.WHISPER.sticky = 1
  ChatTypeInfo.OFFICER.sticky = 1
  ChatTypeInfo.RAID_WARNING.sticky = 1
  ChatTypeInfo.CHANNEL.sticky = 1

  -- Repeat messages with arrow keys without holding ALT
  ChatFrameEditBox:SetAltArrowKeyMode(false)

  -- Mouse-wheel scrolling for chat frames
  for i = 1, NUM_CHAT_WINDOWS do
    local frame = _G["ChatFrame" .. i]
    if frame then
      frame:EnableMouseWheel(true)
      frame:SetScript("OnMouseWheel", ChatOnMouseWheel)
    end
  end

  -- Independent chat-menu button beside TargetFrame
  local target = _G.TargetFrame
  local chatMenu = _G.ChatMenu
  local originalButton = _G.ChatFrameMenuButton

  if not target or not chatMenu then
    return
  end

  -- Store position in ShaguTweaks_config
  ShaguTweaks_config = ShaguTweaks_config or {}
  ShaguTweaks_config.chatTweaksButton =
    ShaguTweaks_config.chatTweaksButton or {}

  local buttonConfig = ShaguTweaks_config.chatTweaksButton

  local offsetX = buttonConfig.offsetX or 185
  local offsetY = buttonConfig.offsetY or 22

  -- Dragging limits relative to TargetFrame's bottom-left
  local MIN_X, MAX_X = -30, 230
  local MIN_Y, MAX_Y = -30, 140

  local function Clamp(value, minimum, maximum)
    if value < minimum then
      return minimum
    elseif value > maximum then
      return maximum
    end
    return value
  end

  -- Create the button only once
  local btn = _G.ShaguTargetEmoteButton

  if not btn then
    btn = CreateFrame(
      "Button",
      "ShaguTargetEmoteButton",
      target
    )

    local width, height = 32, 32

    -- Copy the original button's dimensions and textures.
    -- This reads the original button but never modifies it.
    if originalButton then
      if originalButton:GetWidth() > 0 then
        width = originalButton:GetWidth()
      end

      if originalButton:GetHeight() > 0 then
        height = originalButton:GetHeight()
      end

      local function CopyTexture(getter, setter)
        local getFunction = originalButton[getter]
        if not getFunction then
          return
        end

        local texture = getFunction(originalButton)
        local texturePath =
          texture and texture.GetTexture and texture:GetTexture()

        if texturePath then
          btn[setter](btn, texturePath)
        end
      end

      CopyTexture("GetNormalTexture", "SetNormalTexture")
      CopyTexture("GetPushedTexture", "SetPushedTexture")
      CopyTexture("GetHighlightTexture", "SetHighlightTexture")
    end

    btn:SetWidth(width)
    btn:SetHeight(height)
  end

  local function AnchorButton()
    btn:ClearAllPoints()
    btn:SetPoint(
      "TOPLEFT",
      target,
      "BOTTOMLEFT",
      offsetX,
      offsetY
    )
  end

  local function RaiseButton()
    btn:SetFrameStrata("BACKGROUND")
    btn:SetFrameLevel(target:GetFrameLevel() + 20)
  end

  AnchorButton()
  RaiseButton()

  -- Alt-click your own PlayerFrame to hide/show this button.
  -- Persist the state with the button's other configuration.
  if buttonConfig.hidden then
    btn:Hide()
  else
    btn:Show()
  end

  local playerFrame = _G.PlayerFrame
  if playerFrame and not playerFrame.ShaguChatTweaksAltToggleInstalled then
    local oldPlayerMouseDown = playerFrame:GetScript("OnMouseDown")

    playerFrame:SetScript("OnMouseDown", function()
      if IsAltKeyDown() and arg1 == "LeftButton" then
        buttonConfig.hidden = not buttonConfig.hidden

        if buttonConfig.hidden then
          btn:Hide()
        else
          btn:Show()
        end
      end

      if oldPlayerMouseDown then
        oldPlayerMouseDown()
      end
    end)

    playerFrame.ShaguChatTweaksAltToggleInstalled = true
  end

  btn:EnableMouse(true)
  btn:RegisterForClicks("LeftButtonUp")
  btn:RegisterForDrag("LeftButton")

  btn:SetScript("OnShow", function()
    RaiseButton()
  end)

  -- Save Blizzard's original menu behavior and layout.
  local oldShow = chatMenu:GetScript("OnShow")
  local oldHide = chatMenu:GetScript("OnHide")

  local originalHeight = chatMenu:GetHeight()

  local originalMenuPoints = {}

  for p = 1, chatMenu:GetNumPoints() do
    local point, relativeTo, relativePoint, x, y = chatMenu:GetPoint(p)
    table.insert(originalMenuPoints, {
      point, relativeTo, relativePoint, x, y
    })
  end

  local originalButtons = {}

  for i = 1, 10 do
    local b = getglobal("ChatMenuButton" .. i)
    if b then
      originalButtons[i] = {
        button = b,
        shown = b:IsShown(),
        points = {}
      }

      for p = 1, b:GetNumPoints() do
        local point, relativeTo, relativePoint, x, y = b:GetPoint(p)
        table.insert(originalButtons[i].points, {
          point, relativeTo, relativePoint, x, y
        })
      end
    end
  end

  local customMenuActive = false

  -- Restore Blizzard's original layout and visibility.
  local function RestoreBlizzardMenu()
    for i = 1, 10 do
      local saved = originalButtons[i]
      if saved then
        local b = saved.button
        b:ClearAllPoints()

        for _, p in ipairs(saved.points) do
          b:SetPoint(p[1], p[2], p[3], p[4], p[5])
        end

        if saved.shown then
          b:Show()
        else
          b:Hide()
        end
      end
    end

    chatMenu:ClearAllPoints()

    for _, p in ipairs(originalMenuPoints) do
      chatMenu:SetPoint(p[1], p[2], p[3], p[4], p[5])
    end

    chatMenu:SetHeight(originalHeight)
    customMenuActive = false
  end

  -- Custom Say / Yell entries -------------------------------------------
  local customEntries = {
    { key = "sayText",  prefix = "Say",  channel = "SAY"  },
    { key = "yellText", prefix = "Yell", channel = "YELL" },
  }

  local customButtons = {}
  local editEntry -- which entry the popup is editing

  local function RefreshCustomLabels()
    for _, e in ipairs(customEntries) do
      if e.button then
        local text = buttonConfig[e.key]
        local label
        if text and strlen(text) > 0 then
          if strlen(text) > 20 then
            text = strsub(text, 1, 20) .. "..."
          end
          label = e.prefix .. ": " .. text
        else
          label = e.prefix .. ": (click to set)"
        end
        e.button.text:SetText(label)
      end
    end
  end

  local function SaveCustomText(text)
    if not editEntry then return end
    if text and strlen(text) > 0 then
      buttonConfig[editEntry.key] = text
    else
      buttonConfig[editEntry.key] = nil
    end
    RefreshCustomLabels()
  end

  -- Find our visible popup (looked up by name, not by `this`,
  -- since `this` differs between clients and callbacks).
  local function FindPopupEditBox()
    for i = 1, 4 do
      local dlg = getglobal("StaticPopup" .. i)
      local eb = getglobal("StaticPopup" .. i .. "EditBox")
      if dlg and eb and dlg:IsShown() and dlg.which == "SHAGU_CHATTWEAKS_CUSTOM" then
        return eb
      end
    end
  end

  StaticPopupDialogs["SHAGU_CHATTWEAKS_CUSTOM"] = {
    text = "Enter the text to %s:",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 255,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    OnShow = function()
      local eb = FindPopupEditBox()
      if eb then
        eb:SetText((editEntry and buttonConfig[editEntry.key]) or "")
        eb:HighlightText()
        eb:SetFocus()
      end
    end,
    OnAccept = function()
      local eb = FindPopupEditBox()
      if eb then
        SaveCustomText(eb:GetText())
      end
    end,
    EditBoxOnEnterPressed = function()
      SaveCustomText(this:GetText())
      this:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function()
      this:GetParent():Hide()
    end,
  }

  for i, loopEntry in ipairs(customEntries) do
    -- Lua 5.0 shares loop variables between closures (and they are nil
    -- after the loop ends), so copy the entry into a fresh local.
    local e = loopEntry
    local b = CreateFrame("Button", "ShaguChatTweaksCustom" .. i, chatMenu)
    b:SetHeight(16)
    b:SetWidth(chatMenu:GetWidth() - 8)
    b:SetFrameLevel(chatMenu:GetFrameLevel() + 1)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    b.text = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")

    b.text:SetPoint("LEFT", b, "LEFT", 4, 0)

    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    local hl = b:GetHighlightTexture()
    if hl then hl:SetBlendMode("ADD") end

    b:SetScript("OnClick", function()
      local text = buttonConfig[e.key]
      if arg1 == "RightButton" or not text or strlen(text) == 0 then
        editEntry = e
        chatMenu:Hide()
        StaticPopup_Show("SHAGU_CHATTWEAKS_CUSTOM", strlower(e.prefix))
      else
        SendChatMessage(text, e.channel)
        chatMenu:Hide()
      end
    end)

    b:Hide()
    e.button = b
    table.insert(customButtons, b)
  end

  RefreshCustomLabels()

  -- Apply the temporary custom layout.
  chatMenu:SetScript("OnShow", function()
    if oldShow then oldShow() end

    -- Opened from Blizzard's default button: hide our custom entries
    if not customMenuActive then
      for _, b in ipairs(customButtons) do b:Hide() end
      return
    end

    -- Menu order, top to bottom
    local wanted = {
      customEntries[1].button,  -- custom Say
      customEntries[2].button,  -- custom Yell
      ChatMenuButton6,          -- Emote
      ChatMenuButton9,          -- Voice Emote
    }

    -- Hide all Blizzard buttons first
    for i = 1, 10 do
      local b = getglobal("ChatMenuButton" .. i)
      if b then b:Hide() end
    end

    -- Show and stack the ones we want
    local previous
    local totalHeight = 8

    for _, b in ipairs(wanted) do
      if b then
        b:ClearAllPoints()
        if previous then
          b:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, 0)
        else
          b:SetPoint("TOPLEFT", chatMenu, "TOPLEFT", 4, -4)
        end
        b:Show()
        previous = b
        totalHeight = totalHeight + b:GetHeight()
      end
    end

    chatMenu:SetHeight(totalHeight)
  end)

  -- Restore the original layout when the menu closes.
  chatMenu:SetScript("OnHide", function()
    RestoreBlizzardMenu()
    if oldHide then oldHide() end
  end)

  -- Toggle the Blizzard menu from your custom button.
  btn:SetScript("OnClick", function()
    if chatMenu:IsShown() then
      chatMenu:Hide()
    else
      customMenuActive = true
      chatMenu:ClearAllPoints()
      chatMenu:SetPoint("BOTTOMLEFT", btn, "TOPRIGHT", 0, 0)
      chatMenu:Show()
    end
  end)

  -- SHIFT + drag to reposition
  btn:SetScript("OnDragStart", function()
    if not IsShiftKeyDown() then
      return
    end

    local scale = btn:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()

    cursorX = cursorX / scale
    cursorY = cursorY / scale

    btn.grabX = cursorX - btn:GetLeft()
    btn.grabY = cursorY - btn:GetTop()
    btn.dragging = true
  end)

  btn:SetScript("OnUpdate", function()
    if not btn.dragging then
      return
    end

    local targetLeft = target:GetLeft()
    local targetBottom = target:GetBottom()

    if not targetLeft or not targetBottom then
      return
    end

    local scale = btn:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()

    cursorX = cursorX / scale
    cursorY = cursorY / scale

    offsetX = Clamp(
      cursorX - btn.grabX - targetLeft,
      MIN_X,
      MAX_X
    )

    offsetY = Clamp(
      cursorY - btn.grabY - targetBottom,
      MIN_Y,
      MAX_Y
    )

    AnchorButton()
  end)

  -- Save position when dragging ends
  btn:SetScript("OnDragStop", function()
    btn.dragging = false

    buttonConfig.offsetX = offsetX
    buttonConfig.offsetY = offsetY
  end)

  btn:SetScript("OnHide", function()
    btn.dragging = false
  end)

  -- Tooltip
  btn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(btn, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPLEFT", btn, "BOTTOMRIGHT", 4, -4)
    GameTooltip:SetText("Emotes")
    GameTooltip:AddLine("Alt-click your portrait to toggle", 1, 1, 1)
    GameTooltip:Show()
  end)

  btn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
end