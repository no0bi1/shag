local libspell = {}

-- [ GetSpellMaxRank ]
-- Returns the maximum rank of a player's spell.
-- 'name'       [string]            spell name to query (case-insensitive)
-- return:      [string],[number]   maximum rank text and numeric rank
--                                  e.g. "Rank 1" and 1
local spellmaxrank = {}
function libspell.GetSpellMaxRank(name)
  if not name then return end

  local key = string.lower(name)
  local cache = spellmaxrank[key]
  if cache then return cache[1], cache[2] end

  local rank = { 0, nil }
  for i = 1, GetNumSpellTabs() do
    local _, _, offset, num = GetSpellTabInfo(i)
    local bookType = BOOKTYPE_SPELL
    for id = offset + 1, offset + num do
      local spellName, spellRank = GetSpellName(id, bookType)
      if spellName and key == string.lower(spellName) then
        if not rank[2] then rank[2] = spellRank end

        local _, _, numRank = string.find(spellRank or "", " (%d+)$")
        if numRank and tonumber(numRank) > rank[1] then
          rank = { tonumber(numRank), spellRank }
        end
      end
    end
  end

  spellmaxrank[key] = { rank[2], rank[1] }
  return rank[2], rank[1]
end

-- [ GetSpellIndex ]
-- Returns the spellbook slot and book type for the given spell.
-- 'name'       [string]            spell name to query (case-insensitive)
-- 'rank'       [string]            rank to query (optional)
-- return:      [number],[string]   spellbook slot and spellbook type
local spellindex = {}
function libspell.GetSpellIndex(name, rank)
  if not name then return end

  name = string.lower(name)
  local key = name .. (rank and ("(" .. rank .. ")") or "")
  local cache = spellindex[key]
  if cache then return cache[1], cache[2] end

  if not rank then rank = libspell.GetSpellMaxRank(name) end

  for i = 1, GetNumSpellTabs() do
    local _, _, offset, num = GetSpellTabInfo(i)
    local bookType = BOOKTYPE_SPELL
    for id = offset + 1, offset + num do
      local spellName, spellRank = GetSpellName(id, bookType)
      if spellName and rank and rank == spellRank and name == string.lower(spellName) then
        spellindex[name .. "(" .. rank .. ")"] = { id, bookType }
        return id, bookType
      elseif spellName and not rank and name == string.lower(spellName) then
        spellindex[name] = { id, bookType }
        return id, bookType
      end
    end
  end

  spellindex[key] = { nil }
  return nil
end

-- [ GetSpellInfo ]
-- Returns spell information using ClassicAPI rather than parsing tooltip text.
-- 'index'      [string/number]     Spell name (optionally with rank) or spellbook slot
-- 'bookType'   [string]            BOOKTYPE_SPELL or BOOKTYPE_PET for numeric slots
-- return:
--              [string]            Spell name
--              [string]            Rank / secondary text
--              [string]            Icon texture
--              [number]            Casting time in milliseconds
--              [number]            Minimum range
--              [number]            Maximum range
--              [number]            Spellbook slot
--              [string]            Spellbook type
--              [number]            Numeric spell ID
local spellinfo = {}
function libspell.GetSpellInfo(index, bookType)
  local cache = spellinfo[index]
  if cache then
    return unpack(cache, 1, cache.n)
  end

  local slot
  if type(index) == "string" then
    local _, _, sname, srank = string.find(index, '(.+)%((.+)%)')
    local name = sname or index
    local rank = srank or libspell.GetSpellMaxRank(name)
    slot, bookType = libspell.GetSpellIndex(name, rank)
  else
    if not bookType or (bookType ~= BOOKTYPE_SPELL and bookType ~= BOOKTYPE_PET) then
      return nil
    end
    slot = index
  end

  if not slot or not bookType then return nil end

  -- ClassicAPI returns: name, rank, icon, cost, isFunnel, powerType,
  -- castTime(ms), minRange, maxRange, spellID.
  -- Preserve libspell's original first six return positions.
  local name, rank, icon, _, _, _, castingTime, minRange, maxRange, spellId =
    GetSpellInfo(slot, bookType)

  local result = {
    name, rank, icon, castingTime, minRange, maxRange, slot, bookType, spellId,
    n = 9,
  }
  spellinfo[index] = result
  return unpack(result, 1, result.n)
end

-- Reset spell caches whenever spells are learned or unlearned.
local resetCache = CreateFrame("Frame")
resetCache:RegisterEvent("LEARNED_SPELL_IN_TAB")
resetCache:SetScript("OnEvent", function()
  for key in pairs(spellmaxrank) do spellmaxrank[key] = nil end
  for key in pairs(spellindex) do spellindex[key] = nil end
  for key in pairs(spellinfo) do spellinfo[key] = nil end
end)

ShaguTweaks.libspell = libspell
