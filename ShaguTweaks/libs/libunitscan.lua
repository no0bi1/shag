local _G = ShaguTweaks.GetGlobalEnv()
local GetExpansion = ShaguTweaks.GetExpansion
local L = ShaguTweaks.L

local units = { players = {}, mobs = {} }
local queue = { }
local scanBlockedLogged = {}
local lastWhoRequest = 0
local whoRequestedName = nil
local WHO_REQUEST_INTERVAL = 10

local libunitscan = CreateFrame("Frame", "ShaguTweaksUnitScan", UIParent)

function ShaguTweaks.GetUnitData(name, active)
  if units["players"][name] then
    local ret = units["players"][name]
    return ret.class, ret.level, ret.elite, true
  elseif units["mobs"][name] then
    local ret = units["mobs"][name]
    return ret.class, ret.level, ret.elite, nil
  elseif active then
    if not queue[name] then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[UnitScan]|r queued class lookup for " .. tostring(name))
    end
    queue[name] = true
    libunitscan:Show()
  end
end

local function AddData(db, name, class, level, elite)
  if not name then return end
  units[db][name] = units[db][name] or {}
  units[db][name].class = class or units[db][name].class
  units[db][name].level = level or units[db][name].level
  units[db][name].elite = elite or units[db][name].elite
  queue[name] = nil
  scanBlockedLogged[name] = nil
end

local function RequestWho(name)
  -- Don't replace a WHO query the user is actively viewing.
  if WhoFrame and WhoFrame.IsShown and WhoFrame:IsShown() then return end
  if whoRequestedName then return end

  local now = GetTime()
  if now - lastWhoRequest < WHO_REQUEST_INTERVAL then return end

  whoRequestedName = name
  lastWhoRequest = now
  DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[UnitScan]|r trying WHO lookup for " .. tostring(name))
  SendWho("n-" .. name)
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

    if event == "WHO_LIST_UPDATE" and whoRequestedName then
      if matchedRequestedName then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ff66[UnitScan]|r WHO found " .. whoRequestedName .. ".")
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff6666[UnitScan]|r WHO returned no class match for " .. whoRequestedName .. ".")
      end
      whoRequestedName = nil
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

-- since TargetByName can only be triggered within vanilla,
-- we can't auto-scan targets on further expansions.
if GetExpansion() == "vanilla" then
  -- setup sound function switches
  local SoundOn = PlaySound
  local SoundOff = function() return end

  libunitscan:SetScript("OnUpdate", function()
    -- Don't disturb an existing target; log this blocker once per queued name.
    if UnitExists("target") or UnitName("target") then
      for queuedName in pairs(queue) do
        if not scanBlockedLogged[queuedName] then
          scanBlockedLogged[queuedName] = true
          DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[UnitScan]|r cannot scan " .. tostring(queuedName) .. " because you already have a target.")
        end
      end
      return
    end

    local name = next(queue)
    if name then
      DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[UnitScan]|r attempting target lookup for " .. tostring(name))
      -- disable sound
      _G.PlaySound = SoundOff

      -- try to target the unknown unit
      TargetByName(name, true)
      local foundName = UnitName("target")
      local isPlayer = UnitIsPlayer("target")
      local _, foundClass = UnitClass("target")
      if foundName and foundName == name and isPlayer and foundClass then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ff66[UnitScan]|r found " .. tostring(name) .. " as player class " .. tostring(foundClass))
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff6666[UnitScan]|r target lookup failed for " .. tostring(name) .. "; trying WHO fallback.")
        RequestWho(name)
      end
      ClearTarget()

      -- enable sound again
      _G.PlaySound = SoundOn

      queue[name] = nil
    end

    this:Hide()
  end)
end
