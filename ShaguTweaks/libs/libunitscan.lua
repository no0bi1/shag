local _G = ShaguTweaks.GetGlobalEnv()
local GetExpansion = ShaguTweaks.GetExpansion
local L = ShaguTweaks.L

local units = { players = {}, mobs = {} }
local queue = { }
local whoRequestedName = nil
local whoRequestedAt = 0
local WHO_REQUEST_TIMEOUT = 8
local whoUIHookInstalled = false

local libunitscan = CreateFrame("Frame", "ShaguTweaksUnitScan", UIParent)

-- Quiet automated WHO requests using the native UI result path. Blizzard's
-- FriendsFrame handler also receives WHO_LIST_UPDATE and can open the Who UI,
-- so let our own handler process that event while skipping the Blizzard handler
-- only for the duration of an automated lookup.
local function InstallWhoUIHook()
  if whoUIHookInstalled then return true end
  if type(FriendsFrame_OnEvent) ~= "function" then return false end

  local originalFriendsFrameOnEvent = FriendsFrame_OnEvent
  FriendsFrame_OnEvent = function(...)
    if whoRequestedName and event == "WHO_LIST_UPDATE" then
      return
    end
    return originalFriendsFrameOnEvent(...)
  end

  whoUIHookInstalled = true
  return true
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

  if units[db][name].class and ShaguTweaks.ResolveSocialColorMessages then
    ShaguTweaks.ResolveSocialColorMessages(name, units[db][name].class)
  end
end

local function FinishWho(found, timedOut)
  if not whoRequestedName then return end

  local requestedName = whoRequestedName
  if not found then
    if timedOut then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff6666[UnitScan]|r WHO timed out for " .. tostring(requestedName) .. ".")
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffff6666[UnitScan]|r Could not resolve class for " .. tostring(requestedName) .. ".")
    end
    if ShaguTweaks.ResolveSocialColorMessages then
      ShaguTweaks.ResolveSocialColorMessages(requestedName, nil)
    end
  end

  -- Always restore normal WHO routing, including timeout and failed lookups.
  SetWhoToUI(0)
  whoRequestedName = nil
  whoRequestedAt = 0
  if next(queue) then libunitscan:Show() end
end

local function RequestWho(name)
  -- Don't replace a WHO query the user is actively viewing.
  if WhoFrame and WhoFrame.IsShown and WhoFrame:IsShown() then
    return false
  end
  if whoRequestedName then
    return false
  end
  if not InstallWhoUIHook() then
    return false
  end

  whoRequestedName = name
  whoRequestedAt = GetTime()
  -- Route results to WHO_LIST_UPDATE rather than normal WHO chat output.
  SetWhoToUI(1)
  SendWho('n-"' .. name .. '"')
  return true
end

libunitscan:RegisterEvent("PLAYER_ENTERING_WORLD")
libunitscan:RegisterEvent("FRIENDLIST_UPDATE")
libunitscan:RegisterEvent("GUILD_ROSTER_UPDATE")
libunitscan:RegisterEvent("RAID_ROSTER_UPDATE")
libunitscan:RegisterEvent("PARTY_MEMBERS_CHANGED")
libunitscan:RegisterEvent("PLAYER_TARGET_CHANGED")
libunitscan:RegisterEvent("WHO_LIST_UPDATE")
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
      class = L["class"][class] or nil
      AddData("players", name, class, level)
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

  elseif event == "WHO_LIST_UPDATE" then
    local name, class, level, _
    local matchedRequestedName = false

    -- Only WHO_LIST_UPDATE contains the current structured result set.
    -- CHAT_MSG_SYSTEM can arrive with stale GetWhoInfo data from a prior query;
    -- using it here can finish the request before the client's chat lines arrive.
    for i = 1, GetNumWhoResults() do
      name, _, level, _, class, _ = GetWhoInfo(i)
      class = L["class"][class] or nil
      AddData("players", name, class, level)
      if whoRequestedName and name and string.lower(name) == string.lower(whoRequestedName) and class then
        matchedRequestedName = true
      end
    end

    if whoRequestedName and matchedRequestedName then
      FinishWho(true)
    elseif whoRequestedName then
      -- SetWhoToUI(1) routed a response to the UI, but it did not contain
      -- the requested player.
      FinishWho(false)
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
  -- Never let a missing WHO event block every queued sender indefinitely.
  if whoRequestedName and GetTime() - whoRequestedAt >= WHO_REQUEST_TIMEOUT then
    FinishWho(false, true)
  end

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
