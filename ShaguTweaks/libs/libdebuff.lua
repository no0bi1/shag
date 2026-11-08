local _G = ShaguTweaks.GetGlobalEnv()
local GetExpansion = ShaguTweaks.GetExpansion

-- return instantly if we're not on a vanilla client
if GetExpansion() ~= "vanilla" then return end

local libdebuff = {}

-- Convert ClassicAPI AuraData into libdebuff's established return tuple:
-- effect, rank, texture, stacks, dtype, duration, timeleft, caster
local function AuraToLegacy(aura)
  if not aura then return nil end

  local duration = aura.duration or 0
  local timeleft = -1

  -- Only report a timer for genuinely timed auras. ClassicAPI owns the
  -- expiration data; this library does not reconstruct or override it.
  if duration > 0 and aura.expirationTime and aura.expirationTime > 0 then
    timeleft = aura.expirationTime - GetTime()
    if timeleft < 0 then timeleft = 0 end
  end

  -- Aura spellId identifies the specific cast rank.
  local rank
  local subtext = aura.spellId and C_Spell.GetSpellSubtext(aura.spellId)
  if subtext and subtext ~= "" then
    rank = tonumber((string.gsub(subtext, RANK, "")))
  end

  local dtype = aura.dispelName
  if dtype == "" then dtype = nil end

  local caster = aura.isFromPlayerOrPlayerPet and "player" or "other"

  return aura.name, rank, aura.icon, aura.applications or 0, dtype,
    duration, timeleft, caster
end

-- Report the active aura for spellName on guid.
-- Returns startTime, duration, timeleft, rank, casterGuid or nil.
function libdebuff:GetBestAuraCast(guid, spellName)
  if not guid or not spellName then return nil end

  local aura = C_UnitAuras.GetAuraDataBySpellName(guid, spellName)
  if not aura or not aura.expirationTime or aura.expirationTime == 0 then return nil end

  local timeleft = aura.expirationTime - GetTime()
  if timeleft <= 0 then return nil end

  local duration = (aura.duration and aura.duration > 0) and aura.duration or timeleft
  local startTime = aura.expirationTime - duration
  local rank = aura.spellId and tonumber((string.gsub(C_Spell.GetSpellSubtext(aura.spellId) or "", RANK, ""))) or nil

  return startTime, duration, timeleft, rank, aura.sourceGUID
end

-- id is a 1-based harmful-aura index, matching ClassicAPI's compacted slots.
function libdebuff:UnitDebuff(unit, id)
  return AuraToLegacy(C_UnitAuras.GetAuraDataByIndex(unit, id, "HARMFUL"))
end

-- Player-cast harmful auras only.
function libdebuff:UnitOwnDebuff(unit, id)
  return AuraToLegacy(C_UnitAuras.GetAuraDataByIndex(unit, id, "HARMFUL|PLAYER"))
end

ShaguTweaks.libdebuff = libdebuff
