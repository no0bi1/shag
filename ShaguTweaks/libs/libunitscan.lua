-- Player levels are keyed by name for modules that only have name references.
-- Player class identity is owned by ClassicAPI's C_PlayerCache.
local units = { players = {} }

local libunitscan = CreateFrame("Frame", "ShaguTweaksUnitScan", UIParent)

function ShaguTweaks.GetUnitData(name, active)
  if not name then return end

  local player = units.players[name]
  local class
  if C_PlayerCache and C_PlayerCache.GetPlayerInfoByName then
    _, class = C_PlayerCache.GetPlayerInfoByName(name)
  end

  -- Keep the legacy return shape used by ShaguTweaks modules:
  -- class, level, elite, confirmed-player.
  return class, player and player.level, player and player.elite, player and true or nil
end

local function AddPlayerData(name, level)
  if not name then return end

  units.players[name] = units.players[name] or {}
  local player = units.players[name]

  if level and level > 0 then player.level = level end
end

-- Unit tokens are authoritative. Ignore NPCs completely: they do not enter
-- the player cache and are never looked up by name.
local function RememberUnit(unit)
  if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return end

  local name = UnitName(unit)
  local guid = UnitGUID(unit)
  if not name then return end

  local _, class = UnitClass(unit)
  local level = UnitLevel(unit)
  AddPlayerData(name, level)

  -- UnitClass's second return is the English class token expected by
  -- ClassicAPI. Keep the call to the three required arguments; race and
  -- sex are optional and are not needed for class-color lookups.
  if guid and class and C_PlayerCache and C_PlayerCache.RememberPlayer then
    C_PlayerCache.RememberPlayer(guid, name, class)
  end
end

local function AddRosterLevel(name, level)
  if name and level and level > 0 then
    AddPlayerData(name, level)
  end
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
libunitscan:RegisterEvent("NAME_PLATE_UNIT_ADDED")

libunitscan:SetScript("OnEvent", function()
  if event == "PLAYER_ENTERING_WORLD" then
    ShaguTweaks_cache = ShaguTweaks_cache or {}
    ShaguTweaks_cache["players"] = ShaguTweaks_cache["players"] or {}
    units.players = ShaguTweaks_cache["players"]

    AddPlayerData(UnitName("player"), UnitLevel("player"))
    RememberUnit("player")

  elseif event == "FRIENDLIST_UPDATE" then
    for i = 1, GetNumFriends() do
      local info = C_FriendList.GetFriendInfoByIndex(i)
      if info then AddPlayerData(info.name, info.level) end
    end

  elseif event == "GUILD_ROSTER_UPDATE" then
    for i = 1, GetNumGuildMembers() do
      local name, _, _, level = GetGuildRosterInfo(i)
      AddPlayerData(name, level)
    end

  elseif event == "RAID_ROSTER_UPDATE" then
    for i = 1, GetNumRaidMembers() do
      local name, _, _, level = GetRaidRosterInfo(i)
      AddRosterLevel(name, level)
      RememberUnit("raid" .. i)
    end

  elseif event == "PARTY_MEMBERS_CHANGED" then
    for i = 1, GetNumPartyMembers() do
      local unit = "party" .. i
      AddRosterLevel(UnitName(unit), UnitLevel(unit))
      RememberUnit(unit)
    end

  elseif event == "WHO_LIST_UPDATE" or event == "CHAT_MSG_SYSTEM" then
    -- Consume results from a WHO query the user initiated; never issue one.
    for i = 1, C_FriendList.GetNumWhoResults() do
      local info = C_FriendList.GetWhoInfo(i)
      if info then AddRosterLevel(info.fullName, info.level) end
    end

  elseif event == "UPDATE_MOUSEOVER_UNIT"
      or event == "PLAYER_TARGET_CHANGED"
      or event == "NAME_PLATE_UNIT_ADDED" then
    local unit = event == "PLAYER_TARGET_CHANGED" and "target"
             or event == "NAME_PLATE_UNIT_ADDED" and arg1
             or "mouseover"
    RememberUnit(unit)
  end
end)
