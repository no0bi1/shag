local _G = ShaguTweaks.GetGlobalEnv()
local GetExpansion = ShaguTweaks.GetExpansion
local L = ShaguTweaks.L

local units = { players = {}, mobs = {} }
local queue = { }
local whoRequestedName = nil
local whoBlockedLog = {}
local whoOutputSuppressName = nil
local whoOutputSuppressUntil = 0
local whoOutputLineSuppressed = false
local WHO_OUTPUT_SUPPRESS_WINDOW = 5

local libunitscan = CreateFrame("Frame", "ShaguTweaksUnitScan", UIParent)

-- Hide only chat output belonging to this addon's automated WHO request.
-- WHO_LIST_UPDATE is still processed below so the class cache is populated.
function ShaguTweaks.ShouldSuppressUnitScanWhoMessage(text)
  if not text or not whoOutputSuppressName or GetTime() > whoOutputSuppressUntil then
    return false
  end

  if string.find(text, whoOutputSuppressName, 1, true)
    and string.find(text, "Level ", 1, true)
    and string.find(text, " - ", 1, true) then
    whoOutputLineSuppressed = true
    return true
  end

  if whoOutputLineSuppressed and string.find(text, "player total", 1, true) then
    return true
  end

  return false
end

function ShaguTweaks.GetUnitData(name, active)
  local player = units["players"][name]
  if player and player.class then
    return player.class, player.level, player.elite, true
  end

  local mob = units["mobs"][name]
  if mob then
    return mob.class, mob.level, mob.elite, nil
  end

  -- A player record without a class is not a successful cache hit.
  -- This can happen when WHO returns partial data; allow another lookup.
  if active then
    if not (whoRequestedName and string.lower(whoRequestedName) == string.lower(name)) then
      if not queue[name] then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[UnitScan]|r queued WHO lookup for " .. tostring(name))
      end
      queue[name] = true
      libunitscan:Show()
    end
  end

  if player then
    return player.class, player.level, player.elite, true
  end
end

local function AddData(db, name, class, level, elite)
  if not name then return end
  units[db][name] = units[db][name] or {}
  units[db][name].class = class or units[db][name].class
  units[db][name].level = level or units[db][name].level
  units[db][name].elite = elite or units[db][name].elite
  queue[name] = nil
end

local function RequestWho(name)
  -- Don't replace a WHO query the user is actively viewing.
  if WhoFrame and WhoFrame.IsShown and WhoFrame:IsShown() then
    if whoBlockedLog[name] ~= "WhoFrame is open" then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[UnitScan]|r WHO blocked for " .. tostring(name) .. ": WhoFrame is open.")
      whoBlockedLog[name] = "WhoFrame is open"
    end
    return false
  end
  if whoRequestedName then
    if whoBlockedLog[name] ~= "another WHO request is pending" then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[UnitScan]|r WHO blocked for " .. tostring(name) .. ": waiting for " .. tostring(whoRequestedName) .. ".")
      whoBlockedLog[name] = "another WHO request is pending"
    end
    return false
  end

  whoBlockedLog[name] = nil
  local now = GetTime()
  whoRequestedName = name
  whoOutputSuppressName = name
  whoOutputSuppressUntil = now + WHO_OUTPUT_SUPPRESS_WINDOW
  whoOutputLineSuppressed = false
  DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[UnitScan]|r trying WHO lookup for " .. tostring(name))
  SendWho("n-" .. name)
  return true
end

libunitscan:RegisterEvent("PLAYER_ENTERING_WORLD")
libunitscan:RegisterEvent("FRIENDLIST_UPDATE")
libunitscan:RegisterEvent("GUILD_ROSTER_UPDATE")
libunitscan:RegisterEvent("RAID_ROSTER_UPDATE")
libunitscan:RegisterEvent("PARTY_MEMBERS_CHANGED")
libunitscan:RegisterEvent("PLAYER_TARGET_CHANGED")
libunitscan:RegisterEvent("WHO_LIST_UPDATE")
libunitscan:RegisterEvent("CHAT_MSG_SYSTEM")
libunitscan:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
libunitscan:SetScript("OnEvent", function()
  if event == "PLAYER_ENTERING_WORLD" then
    -- load database
    ShaguTweaks_cache = ShaguTweaks_cache or {}
    ShaguTweaks_cache["players"] = ShaguTweaks_cache["players"] or {}
    units.players = ShaguTweaks_cache["players"]

    -- update own character details
    local name = UnitName("player")
    local _, class = UnitClass("player")
    local level = UnitLevel("player")
    AddData("players", name, class, level)

  elseif event == "FRIENDLIST_UPDATE" then
    local name, class, level
    for i = 1, GetNumFriends() do
      name, level, class = GetFriendInfo(i)
      class = L["class"][class] or nil
      -- friendlist updates due to friend going off-line return level 0, let's not overwrite good older values
      level = level > 0 and level or nil
      AddData("players", name, class, level)
    end

  elseif event == "GUILD_ROSTER_UPDATE" then
    local name, class, level, _
    for i = 1, GetNumGuildMembers() do
      name, _, _, level, class = GetGuildRosterInfo(i)
      local rawClass = class
      class = L["class"][class] or nil
      AddData("players", name, class, level)

      -- Diagnostic: report roster entries whose class could not be cached.
      if name and not class then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[UnitScan]|r guild roster has no translated class for "
          .. tostring(name) .. " (raw class: " .. tostring(rawClass) .. ").")
      end
    end

  elseif event == "RAID_ROSTER_UPDATE" then
    local name, class, SubGroup, level, _
    for i = 1, GetNumRaidMembers() do
      name, _, SubGroup, level, class = GetRaidRosterInfo(i)
      class = L["class"][class] or nil
      AddData("players", name, class, level)
    end

  elseif event == "PARTY_MEMBERS_CHANGED" then
    local name, class, level, unit, _
    for i = 1, GetNumPartyMembers() do
      unit = "party" .. i
      _, class = UnitClass(unit)
      name = UnitName(unit)
      level = UnitLevel(unit)
      AddData("players", name, class, level)
    end

  elseif event == "WHO_LIST_UPDATE" or event == "CHAT_MSG_SYSTEM" then
    local name, class, level, _
    local matchedRequestedName = false
    for i = 1, GetNumWhoResults() do
      name, _, level, _, class, _ = GetWhoInfo(i)
      class = L["class"][class] or nil
      AddData("players", name, class, level)
      if whoRequestedName and name and string.lower(name) == string.lower(whoRequestedName) and class then
        matchedRequestedName = true
      end
    end

    -- Some Vanilla server/client combinations report the WHO result through
    -- system chat without reliably delivering WHO_LIST_UPDATE. Treat the
    -- final "player total" line as completion too, so the queue cannot stall.
    local whoFinished = event == "WHO_LIST_UPDATE"
      or (event == "CHAT_MSG_SYSTEM" and arg1 and string.find(arg1, "player total", 1, true))

    if whoFinished and whoRequestedName then
      local requestedName = whoRequestedName
      if matchedRequestedName then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ff66[UnitScan]|r WHO found " .. requestedName .. ".")
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff6666[UnitScan]|r WHO returned no class match for " .. requestedName .. ".")
      end
      whoRequestedName = nil
      if next(queue) then libunitscan:Show() end
    end

  elseif event == "UPDATE_MOUSEOVER_UNIT" or event == "PLAYER_TARGET_CHANGED" then
    local scan = event == "PLAYER_TARGET_CHANGED" and "target" or "mouseover"
    local name, class, level, elite, _
    if UnitIsPlayer(scan) then
      _, class = UnitClass(scan)
      level = UnitLevel(scan)
      name = UnitName(scan)
      AddData("players", name, class, level)
    else
      _, class = UnitClass(scan)
      elite = UnitClassification(scan)
      level = UnitLevel(scan)
      name = UnitName(scan)
      AddData("mobs", name, class, level, elite)
    end
  end
end)

-- Resolve unknown chat senders through WHO only. Never change the player's target.
libunitscan:SetScript("OnUpdate", function()
  local name = next(queue)
  if name then
    if RequestWho(name) then
      queue[name] = nil
    end
  end

  if next(queue) then
    this:Show()
  else
    this:Hide()
  end
end)
