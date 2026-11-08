local _G = ShaguTweaks.GetGlobalEnv()
local L = ShaguTweaks.L
local GetExpansion = ShaguTweaks.GetExpansion
local libtipscan = ShaguTweaks.libtipscan
local libspell = ShaguTweaks.libspell
local hooksecurefunc = ShaguTweaks.hooksecurefunc

-- return instantly if we're not on a vanilla client
if GetExpansion() ~= "vanilla" then return end

local lastcasttex, lastrank
local scanner = libtipscan:GetScanner("libcast")
local player = UnitName("player")

local libcast = CreateFrame("Frame", "ShaguTweaksEnemyCast")
libcast.db = { [player] = {} }

-- ClassicAPI is the authoritative source for unit cast and channel data.
-- Keep Shagu's seven-value interface for the existing castbar consumers:
-- name, rank, text, texture, startTimeMs, endTimeMs, isTradeSkill.
ShaguTweaks.UnitCastingInfo = function(unit)
  if not unit or not UnitExists(unit) then return end

  local name, _, texture, startTime, endTime, isTradeSkill, _, _, spellID =
    C_Spell.UnitCastingInfo(unit)

  if name and startTime and endTime then
    local rank = spellID and C_Spell.GetSpellSubtext(spellID) or ""
    return name, rank, name, texture, startTime, endTime, isTradeSkill
  end

  -- Shagu's custom Aimed Shot / Multi-Shot bars are synthetic player casts.
  -- Keep these separate because ClassicAPI reports the engine's actual casts.
  if UnitIsUnit(unit, "player") then
    local db = libcast.db[player]
    if db and db.cast and db.start and db.casttime
        and db.start + db.casttime / 1000 > GetTime() and not db.channel then
      return db.cast, db.rank or "", "", db.icon,
        db.start * 1000, db.start * 1000 + db.casttime, nil
    end
  end
end

ShaguTweaks.UnitChannelInfo = function(unit)
  if not unit or not UnitExists(unit) then return end

  local name, _, texture, startTime, endTime, isTradeSkill, _, spellID =
    C_Spell.UnitChannelInfo(unit)

  -- Remote channels whose start was not observed can have no timing data.
  -- The existing Shagu castbar needs both timestamps to calculate progress.
  if not name or not startTime or not endTime then return end

  local rank = spellID and C_Spell.GetSpellSubtext(spellID) or ""
  return name, rank, name, texture, startTime, endTime, isTradeSkill
end

--[[ Custom Casts
  Enable Castbars for spells that don't have a castbar by default
  (e.g Multi-Shot and Aimed Shot)
]]--
local aimedshot = L["customcast"]["AIMEDSHOT"]
local multishot = L["customcast"]["MULTISHOT"]

libcast.customcast = {}
libcast.customcast[strlower(aimedshot)] = function(begin, duration)
  if begin then
    local duration = duration or 3000

    for i=1,32 do
      if UnitBuff("player", i) == "Interface\\Icons\\Racial_Troll_Berserk" then
        local berserk = 0.3
        if((UnitHealth("player")/UnitHealthMax("player")) >= 0.40) then
          berserk = (1.30 - (UnitHealth("player") / UnitHealthMax("player"))) / 3
        end
        duration = duration / (1 + berserk)
      elseif UnitBuff("player", i) == "Interface\\Icons\\Ability_Hunter_RunningShot" then
        duration = duration / 1.4
      elseif UnitBuff("player", i) == "Interface\\Icons\\Ability_Warrior_InnerRage" then
        duration = duration / 1.3
      elseif UnitBuff("player", i) == "Interface\\Icons\\Inv_Trinket_Naxxramas04" then
        duration = duration / 1.2
      end
    end

    local _,_, lag = GetNetStats()
    local start = GetTime() + lag/1000

    -- add cast action to the database
    libcast.db[player].cast = aimedshot
    libcast.db[player].rank = lastrank
    libcast.db[player].start = start
    libcast.db[player].casttime = duration
    libcast.db[player].icon = "Interface\\Icons\\Inv_spear_07"
    libcast.db[player].channel = nil
  else
    -- remove cast action to the database
    libcast.db[player].cast = nil
    libcast.db[player].rank = nil
    libcast.db[player].start = nil
    libcast.db[player].casttime = nil
    libcast.db[player].icon = nil
    libcast.db[player].channel = nil
  end
end

libcast.customcast[strlower(multishot)] = function(begin, duration)
  if begin then
    local duration = duration or 500

    for i=1,32 do
      if UnitBuff("player", i) == "Interface\\Icons\\Racial_Troll_Berserk" then
        local berserk = 0.3
        if((UnitHealth("player")/UnitHealthMax("player")) >= 0.40) then
          berserk = (1.30 - (UnitHealth("player") / UnitHealthMax("player"))) / 3
        end
        duration = duration / (1 + berserk)
      elseif UnitBuff("player", i) == "Interface\\Icons\\Ability_Hunter_RunningShot" then
        duration = duration / 1.4
      elseif UnitBuff("player", i) == "Interface\\Icons\\Ability_Warrior_InnerRage" then
        duration = duration / 1.3
      elseif UnitBuff("player", i) == "Interface\\Icons\\Inv_Trinket_Naxxramas04" then
        duration = duration / 1.2
      end
    end

    local _,_, lag = GetNetStats()
    local start = GetTime() + lag/1000

    -- add cast action to the database
    libcast.db[player].cast = multishot
    libcast.db[player].rank = lastrank
    libcast.db[player].start = start
    libcast.db[player].casttime = duration
    libcast.db[player].icon = "Interface\\Icons\\Ability_upgrademoonglaive"
    libcast.db[player].channel = nil
  else
    -- remove cast action to the database
    libcast.db[player].cast = nil
    libcast.db[player].rank = nil
    libcast.db[player].start = nil
    libcast.db[player].casttime = nil
    libcast.db[player].icon = nil
    libcast.db[player].channel = nil
  end
end

local function CastCustom(spell)
  if not spell then return end
  if not ShaguTweaks.UnitCastingInfo("player") then
    for custom, func in pairs(libcast.customcast) do
      if strfind(strlower(spell), custom) or strlower(spell) == custom then
        func(true)
      end
    end
  end
end

hooksecurefunc("UseContainerItem", function(id, index)
  lastcasttex = GetContainerItemInfo(id, index)
end)

hooksecurefunc("CastSpell", function(id, bookType)
  _, lastrank = libspell.GetSpellInfo(id, bookType)
  lastcasttex = GetSpellTexture(id, bookType)

  if GetSpellCooldown(id, bookType) ~= 0 then
    local spellName = GetSpellName(id, bookType)
    CastCustom(spellName)
  end
end)

hooksecurefunc("CastSpellByName", function(spell, target)
  _, lastrank = libspell.GetSpellInfo(spell)

  for i=1,120 do
    -- detect if any cast is ongoing
    if IsCurrentAction(i) then
      CastCustom(spell)
      return
    end
  end
end)

hooksecurefunc("UseAction", function(slot, target, button)
  scanner:SetAction(slot)
  local spellName, rank = scanner:Line(1)

  lastcasttex = GetActionTexture(slot)
  lastrank = rank

  if GetActionText(slot) or not IsCurrentAction(slot) then return end
  CastCustom(spellName)
end)

ShaguTweaks.libcast = libcast
