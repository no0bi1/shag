local _G = ShaguTweaks.GetGlobalEnv()
local T = ShaguTweaks.T

local module = ShaguTweaks:register({
  title = T["Item Compare"],
  description = T["Shows the equipped items and the stat changes on tooltips while the shift key is pressed (always on the auction house)."],
  expansions = { ["vanilla"] = true, ["tbc"] = nil },
  category = T["Tooltip & Items"],
  enabled = true,
})

module.enable = function(self)
  local sides = { "Left", "Right" }
  local GREEN, RED = "|cff20ff20", "|cffff4040"
  local EQUIP = ITEM_SPELL_TRIGGER_ONEQUIP or "Equip:"

  ---------------------------------------------------------------- item types

  local itemtypes = {
    ["deDE"] = {
      ["INVTYPE_WAND"] = "Zauberstab",
      ["INVTYPE_THROWN"] = "Wurfwaffe",
      ["INVTYPE_GUN"] = "Schusswaffe",
      ["INVTYPE_CROSSBOW"] = "Armbrust",
      ["INVTYPE_PROJECTILE"] = "Projektil",
    },
    ["enUS"] = {
      ["INVTYPE_WAND"] = "Wand",
      ["INVTYPE_THROWN"] = "Thrown",
      ["INVTYPE_GUN"] = "Gun",
      ["INVTYPE_CROSSBOW"] = "Crossbow",
      ["INVTYPE_PROJECTILE"] = "Projectile",
    },
    ["esES"] = {
      ["INVTYPE_WAND"] = "Varita",
      ["INVTYPE_THROWN"] = "Arma arrojadiza",
      ["INVTYPE_GUN"] = "Arma de fuego",
      ["INVTYPE_CROSSBOW"] = "Ballesta",
      ["INVTYPE_PROJECTILE"] = "Proyectil",
    },
    ["frFR"] = {
      ["INVTYPE_WAND"] = "Baguette",
      ["INVTYPE_THROWN"] = "Armes de jet",
      ["INVTYPE_GUN"] = "Arme à feu",
      ["INVTYPE_CROSSBOW"] = "Arbalète",
      ["INVTYPE_PROJECTILE"] = "Projectile",
    },
    ["koKR"] = {
      ["INVTYPE_WAND"] = "마법봉",
      ["INVTYPE_THROWN"] = "투척 무기",
      ["INVTYPE_GUN"] = "총",
      ["INVTYPE_CROSSBOW"] = "석궁",
      ["INVTYPE_PROJECTILE"] = "투사체",
    },
    ["ruRU"] = {
      ["INVTYPE_WAND"] = "Жезл",
      ["INVTYPE_THROWN"] = "Метательное",
      ["INVTYPE_GUN"] = "Огнестрельное",
      ["INVTYPE_CROSSBOW"] = "Арбалет",
      ["INVTYPE_PROJECTILE"] = "Боеприпасы",
    },
    ["zhCN"] = {
      ["INVTYPE_WAND"] = "魔杖",
      ["INVTYPE_THROWN"] = "投掷武器",
      ["INVTYPE_GUN"] = "枪械",
      ["INVTYPE_CROSSBOW"] = "弩",
      ["INVTYPE_PROJECTILE"] = "弹药",
    }
  }

  -- set globals for all inventory types
  for key, value in pairs(itemtypes[GetLocale()] or itemtypes["enUS"]) do setglobal(key, value) end

  -- tooltip text -> what to compare against
  local simple = {}   -- one slot
  local pairs_ = {}   -- two slots (rings, trinkets)
  local hands = {}    -- weapons, shields, held items

  local function map(tbl, key, value) if key then tbl[key] = value end end

  map(simple, INVTYPE_HEAD, "HeadSlot")
  map(simple, INVTYPE_NECK, "NeckSlot")
  map(simple, INVTYPE_SHOULDER, "ShoulderSlot")
  map(simple, INVTYPE_CHEST, "ChestSlot")
  map(simple, INVTYPE_ROBE, "ChestSlot")
  map(simple, INVTYPE_WAIST, "WaistSlot")
  map(simple, INVTYPE_LEGS, "LegsSlot")
  map(simple, INVTYPE_FEET, "FeetSlot")
  map(simple, INVTYPE_WRIST, "WristSlot")
  map(simple, INVTYPE_HAND, "HandsSlot")
  map(simple, INVTYPE_CLOAK, "BackSlot")
  map(simple, INVTYPE_RANGED, "RangedSlot")
  map(simple, INVTYPE_RELIC, "RangedSlot")
  map(simple, INVTYPE_WAND, "RangedSlot")
  map(simple, INVTYPE_GUN, "RangedSlot")
  map(simple, INVTYPE_CROSSBOW, "RangedSlot")
  map(simple, INVTYPE_THROWN, "RangedSlot")

  map(pairs_, INVTYPE_FINGER, { "Finger0Slot", "Finger1Slot" })
  map(pairs_, INVTYPE_TRINKET, { "Trinket0Slot", "Trinket1Slot" })

  map(hands, INVTYPE_2HWEAPON, "2H")
  map(hands, INVTYPE_WEAPON, "1H")
  map(hands, INVTYPE_WEAPONMAINHAND, "MH")
  map(hands, INVTYPE_WEAPONOFFHAND, "OH")
  map(hands, INVTYPE_SHIELD, "SHIELD")
  map(hands, INVTYPE_HOLDABLE, "HOLD")

  -- find out what kind of item a tooltip shows: returns kind, slot(s)
  local function Identify(tooltip)
    local name = tooltip:GetName()
    for i = 2, tooltip:NumLines() do
      local line = _G[name .. "TextLeft" .. i]
      local text = line and line:GetText()
      if text then
        if simple[text] then return "SIMPLE", simple[text] end
        if pairs_[text] then return "PAIR", pairs_[text] end
        if hands[text] then return hands[text] end
      end
    end
  end

  ---------------------------------------------------------------- tooltip reader
  -- Reads a tooltip and keeps EVERYTHING it finds, nothing is hard-coded per stat:
  --   "Equip: <sentence with a number>"     -> keyed by the sentence, the number is the value
  --   "+5 Stamina" / "9 Block" / "22 Armor" -> keyed by the label, the number is the value

  local BASE = {
    { key = "armor", label = "Armor" },
    { key = "str",   label = "Strength" },
    { key = "agi",   label = "Agility" },
    { key = "sta",   label = "Stamina" },
    { key = "int",   label = "Intellect" },
    { key = "spi",   label = "Spirit" },
    { key = "hp",    label = "Health" },
    { key = "mana",  label = "Mana" },
    { key = "res1",  label = "Holy Resistance" },
    { key = "res2",  label = "Fire Resistance" },
    { key = "res3",  label = "Nature Resistance" },
    { key = "res4",  label = "Frost Resistance" },
    { key = "res5",  label = "Shadow Resistance" },
    { key = "res6",  label = "Arcane Resistance" },
    { key = "dps",   label = "Damage Per Second", dec = true },
  }

  local PRIMARY = { Strength = "str", Agility = "agi", Stamina = "sta", Intellect = "int",
                    Spirit = "spi", Health = "hp", Mana = "mana" }
  local RES = { Holy = "res1", Fire = "res2", Nature = "res3", Frost = "res4",
                Shadow = "res5", Arcane = "res6" }
  local SCHOOLS = { arcane = true, fire = true, frost = true, holy = true, nature = true, shadow = true }

  -- a random-suffix line ("+20 Healing Spells") lines up with the "Equip:" sentence of the same effect
  local ALIAS = {
    ["healing spells"] = "Increases healing done by spells and effects by up to #.",
    ["spell damage"] = "Increases damage and healing done by magical spells and effects by up to #.",
    ["attack power"] = "Increases attack power by #.",
    ["ranged attack power"] = "Increases ranged attack power by #.",
  }

  local function NewStats()
    return { fx = {}, order = {}, gen = {}, pct = {} }
  end

  local function AddFx(s, label, val, generic, pct)
    if s.fx[label] then
      s.fx[label] = s.fx[label] + val
    else
      s.fx[label] = val
      tinsert(s.order, label)
    end
    if generic then s.gen[label] = true end
    if pct then s.pct[label] = true end
  end

  local function BaseKey(label)
    if PRIMARY[label] then return PRIMARY[label] end
    if label == "Armor" then return "armor" end
    local _, _, school = strfind(label, "^(%a+) Resistance$")
    if school then return RES[school] end
    return nil
  end

  local function Parse(tooltip)
    local name = tooltip:GetName()
    local s = NewStats()
    local dmin, dmax, speed
    local prefix = strlen(EQUIP) + 1

    for i = 2, tooltip:NumLines() do -- line 1 is the item name
      local l = _G[name .. "TextLeft" .. i]
      local r = _G[name .. "TextRight" .. i]
      local text = l and l:GetText()
      local rtext = r and r:IsShown() and r:GetText()

      if text then
        if strsub(text, 1, prefix) == EQUIP .. " " then
          local sentence = strsub(text, prefix + 1)
          local _, _, sign, num = strfind(sentence, "([%+%-]?)([%d%.]*%d)")
          if num then
            -- only the first number becomes "#" (so "5 mana per 5 sec" keeps its 2nd number) and the sign
            -- goes with the value, so "+32 attack power" and "32 attack power" are the same stat
            local key = gsub(sentence, "[%+%-]?[%d%.]*%d", "#", 1)
            local val = tonumber(num)
            if sign == "-" then val = -val end
            AddFx(s, key, val, true)
          end
        else
          -- any "<number> <words>" or "<words> +<number>" line is a stat, whatever the words are:
          -- "+5 Stamina", "9 Block", "+1% Dodge", "+4 mana every 5 sec", "Defense +3", "Fire Resistance: +10"
          local sign, num, pct, label
          local _, _, sg, nm, pc, lb = strfind(text, "^([%+%-]?)([%d%.]*%d)(%%?) (%a.*)$")
          if nm and (sg ~= "" or not strfind(lb, "%d")) then
            sign, num, pct, label = sg, nm, pc, lb
          else
            local _, _, lb2, sg2, nm2, pc2 = strfind(text, "^(%a[^%d]-):? ([%+%-])([%d%.]*%d)(%%?)$")
            if nm2 then sign, num, pct, label = sg2, nm2, pc2, lb2 end
          end

          if num then
            local val = tonumber(num)
            if sign == "-" then val = -val end
            label = gsub(label, "[%.:%s]+$", "")
            local low = strlower(label)
            local bk = BaseKey(label)
            if bk then
              s[bk] = (s[bk] or 0) + val
            elseif low == "all stats" or low == "to all stats" then
              local all = { "str", "agi", "sta", "int", "spi" }
              for i2 = 1, getn(all) do s[all[i2]] = (s[all[i2]] or 0) + val end
            elseif low ~= "charges" and low ~= "charge" then
              local _, _, sch = strfind(low, "^(%a+) spell damage$")
              if not sch then _, _, sch = strfind(low, "^(%a+) damage$") end
              if sch and SCHOOLS[sch] then
                AddFx(s, "Increases damage done by " .. strupper(strsub(sch, 1, 1)) .. strsub(sch, 2)
                  .. " spells and effects by up to #.", val, true)
              elseif ALIAS[low] then
                AddFx(s, ALIAS[low], val, true)
              else
                AddFx(s, label, val, false, pct == "%")
              end
            end
          end

          local _, _, a, b = strfind(text, "^(%d+) %- (%d+) %a* ?Damage$")
          if a then dmin, dmax = tonumber(a), tonumber(b) end
          if rtext then
            local _, _, sp = strfind(rtext, "^Speed ([%d%.]+)$")
            if sp then speed = tonumber(sp) end
          end
        end
      end
    end

    if dmin and speed and speed > 0 then
      s.dps = (dmin + dmax) / 2 / speed
    end
    return s
  end

  local function Combine(a, b)
    local s = NewStats()
    for i = 1, getn(BASE) do
      local k = BASE[i].key
      s[k] = (a[k] or 0) + (b[k] or 0)
    end
    local src = { a, b }
    for n = 1, 2 do
      local t = src[n]
      for i = 1, getn(t.order) do
        local label = t.order[i]
        AddFx(s, label, t.fx[label], t.gen[label], t.pct[label])
      end
    end
    return s
  end

  ---------------------------------------------------------------- differences

  -- Shortens an "Equip:" sentence (number replaced by "#") into "<number> <short label>":
  --   "Increases attack power by #."       -> "+5 Attack power"
  --   "Improves your chance to hit by #%." -> "+1% Hit"
  -- Anything that doesn't fit these shapes returns nil and the full sentence is shown.
  local VERBS = { "Increases your ", "Increases ", "Improves your ", "Improves ", "Restores ", "Increased ", "Adds ", "Grants ", "Gives " }

  -- plain-English filler to drop from the label (edit/add to taste)
  local FILLER = {
    { "^damage done by (%a+) spells and effects$", "%1 damage" },
    { "^damage and healing done by magical spells and effects$", "spell damage and healing" },
    { "^healing done by spells and effects$", "healing" },
    { "^the block value of your shield$", "block value" },
    { "^chance to get an? (.+)$", "%1" },
    { "^chance to (.+)$", "%1" },
    { " an attack$", "" },
    { " attacks with a shield$", "" },
  }

  local function Condense(sentence)
    local t = gsub(sentence, "%.$", "")
    local stripped
    for i = 1, getn(VERBS) do
      local v = VERBS[i]
      if strsub(t, 1, strlen(v)) == v then
        t = strsub(t, strlen(v) + 1)
        stripped = true
        break
      end
    end
    if not stripped and strsub(t, 1, 1) == "#" then stripped = true end
    if not stripped then return nil end

    local subject, pct
    local _, _, a, b = strfind(t, "^(.-) by up to #(%%?)$")
    if not a then _, _, a, b = strfind(t, "^(.-) by #(%%?)$") end
    if not a then _, _, a, b = strfind(t, "^(.-) #(%%?)$") end
    if a then
      subject, pct = a, b
    else
      local _, _, p2, rest = strfind(t, "^#(%%?) (.+)$")
      if rest then subject, pct = rest, p2 end
    end
    if not subject or subject == "" then return nil end

    for i = 1, getn(FILLER) do
      subject = gsub(subject, FILLER[i][1], FILLER[i][2])
    end
    subject = strupper(strsub(subject, 1, 1)) .. strsub(subject, 2)
    return subject, (pct == "%")
  end

  local function Num(d, dec)
    if dec then return format("%+.1f", d) end
    return format("%+d", d)
  end

  local function Diff(new, old)
    local out = {}
    for i = 1, getn(BASE) do
      local b = BASE[i]
      local d = (new[b.key] or 0) - (old[b.key] or 0)
      if abs(d) > 0.05 then
        local col = d > 0 and GREEN or RED
        tinsert(out, col .. Num(d, b.dec) .. " " .. b.label .. "|r")
      end
    end

    local seen = {}
    local lists = { new, old }
    for n = 1, 2 do
      local t = lists[n]
      for i = 1, getn(t.order) do
        local label = t.order[i]
        if not seen[label] then
          seen[label] = true
          local d = (new.fx[label] or 0) - (old.fx[label] or 0)
          if abs(d) > 0.05 then
            local col = d > 0 and GREEN or RED
            local n1 = Num(d, d ~= floor(d))
            if new.gen[label] or old.gen[label] then
              local short, pct = Condense(label)
              if short then
                tinsert(out, col .. n1 .. (pct and "%" or "") .. " " .. short .. "|r")
              else
                tinsert(out, col .. EQUIP .. " " .. gsub(label, "#", n1, 1) .. "|r")
              end
            else
              local pct = new.pct[label] or old.pct[label]
              tinsert(out, col .. n1 .. (pct and "%" or "") .. " " .. label .. "|r")
            end
          end
        end
      end
    end
    return out
  end

  ---------------------------------------------------------------- equipped items

  local scan = CreateFrame("GameTooltip", "ItemCompareScanTip", nil, "GameTooltipTemplate")
  local cache = {}

  local function SlotID(slotName)
    local id = GetInventorySlotInfo(slotName)
    return id
  end

  -- what you are wearing in a slot: { kind, stats }, read from its own tooltip and cached per item link
  local function Equipped(slotName)
    local id = SlotID(slotName)
    local link = GetInventoryItemLink("player", id)
    if not link then return nil end

    local e = cache[link]
    if not e then
      scan:SetOwner(WorldFrame, "ANCHOR_NONE")
      scan:ClearLines()
      scan:SetInventoryItem("player", id)
      e = { kind = Identify(scan), stats = Parse(scan) }
      cache[link] = e
    end
    return e
  end

  local function IsWeapon(e)
    return e and (e.kind == "1H" or e.kind == "MH" or e.kind == "OH")
  end

  -- which equipped items does the hovered item replace?
  local function Targets(kind, slot)
    local shown = {}
    local function add(slotName)
      local e = Equipped(slotName)
      if e then tinsert(shown, { slot = slotName, stats = e.stats }) end
      return e
    end

    if kind == "SIMPLE" then
      add(slot)
    elseif kind == "PAIR" then
      add(slot[1])
      add(slot[2])
    else
      local mh, oh = Equipped("MainHandSlot"), Equipped("SecondaryHandSlot")
      if kind == "2H" then
        if mh and IsWeapon(oh) then
          -- dual wielding: compare against each weapon separately
          add("MainHandSlot")
          add("SecondaryHandSlot")
        elseif mh and oh then
          -- shield / held item goes away too: one combined change
          tinsert(shown, { slot = "MainHandSlot", stats = Combine(mh.stats, oh.stats), plural = true })
          tinsert(shown, { slot = "SecondaryHandSlot" })
        elseif mh then
          add("MainHandSlot")
        elseif oh then
          add("SecondaryHandSlot")
        end
      elseif kind == "1H" or kind == "MH" or kind == "OH" then
        -- one-handers: show BOTH equipped weapons, each with its own change list
        local offOnly = (kind == "OH")
        if mh and (not offOnly or IsWeapon(oh) or mh.kind == "2H") then
          add("MainHandSlot")
        end
        if oh and (IsWeapon(oh) or offOnly) then
          add("SecondaryHandSlot")
        end
      elseif kind == "SHIELD" or kind == "HOLD" then
        -- offhand slot; a two-hander in the mainhand has to come off first
        if mh and mh.kind == "2H" then
          add("MainHandSlot")
        elseif oh then
          add("SecondaryHandSlot")
        end
      end
    end
    return shown
  end

  ---------------------------------------------------------------- display

  ShoppingTooltip1:SetClampedToScreen(true)
  ShoppingTooltip2:SetClampedToScreen(true)
  local tips = { ShoppingTooltip1, ShoppingTooltip2 }

  -- put the compare tooltips on a side of the hovered tooltip where they all fit side by side
  local function Place(tooltip, count)
    local ui = UIParent:GetEffectiveScale()
    local screenR = (UIParent:GetRight() or 0) * ui
    local sc = tooltip:GetEffectiveScale()
    local tipL = (tooltip:GetLeft() or 0) * sc
    local tipR = (tooltip:GetRight() or 0) * sc

    local total, first = 0, 0
    for i = 1, count do
      local w = tips[i]:GetWidth() * tips[i]:GetEffectiveScale()
      total = total + w
      if i == 1 then first = w end
    end

    local mode
    if tipR + total <= screenR then
      mode = "right"
    elseif tipL - total >= 0 then
      mode = "left"
    elseif tipR + first <= screenR then
      mode = "stackright"
    else
      mode = "stackleft"
    end

    local prev = tooltip
    for i = 1, count do
      local tip = tips[i]
      tip:ClearAllPoints()
      if mode == "right" then
        tip:SetPoint("TOPLEFT", prev, "TOPRIGHT", 0, 0)
      elseif mode == "left" then
        tip:SetPoint("TOPRIGHT", prev, "TOPLEFT", 0, 0)
      elseif i == 1 then
        if mode == "stackright" then
          tip:SetPoint("TOPLEFT", tooltip, "TOPRIGHT", 0, 0)
        else
          tip:SetPoint("TOPRIGHT", tooltip, "TOPLEFT", 0, 0)
        end
      else
        -- not enough width for all of them: stack the rest underneath the first
        if mode == "stackright" then
          tip:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 0)
        else
          tip:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, 0)
        end
      end
      prev = tip
    end
  end

  -- forward declaration: Fill uses AddWrapped before its implementation below
  local AddWrapped

  -- hidden font string with the tooltip font, used to measure text in pixels
  local meter = UIParent:CreateFontString(nil, "OVERLAY", "GameTooltipText")
  meter:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -2000, -2000)
  meter:Show()

  -- word-wrap text to `limit` pixels, keeping the |cffxxxxxx ... |r colour on every line
  local function Wrap(text, limit)
    local out = {}
    local _, _, col, body = strfind(text, "^(|c%x%x%x%x%x%x%x%x)(.-)|r$")
    if not col then col, body = "", text end
    local tail = (col ~= "") and "|r" or ""

    local line = ""
    for word in gfind(body, "%S+") do
      local try = (line == "") and word or (line .. " " .. word)
      meter:SetText(try)
      if line ~= "" and meter:GetStringWidth() > limit then
        tinsert(out, col .. line .. tail)
        line = word
      else
        line = try
      end
    end
    if line ~= "" then tinsert(out, col .. line .. tail) end
    return out
  end

  AddWrapped = function(tip, text, limit, r, g, b)
    local lines = Wrap(text, limit)
    for i = 1, getn(lines) do
      tip:AddLine(lines[i], r or 1, g or 1, b or 1, false)
    end
  end

  -- rebuild the equipped item's tooltip into `tip`, wrapped to `limit` pixels,
  -- with the "Currently equipped" label on top (no line shifting)
  local function Fill(tip, slotName, limit)
    local id = SlotID(slotName)
    scan:SetOwner(WorldFrame, "ANCHOR_NONE")
    scan:ClearLines()
    scan:SetInventoryItem("player", id)

    tip:ClearLines()
    tip:AddLine(CURRENTLY_EQUIPPED, .5, .5, .5, false)

    local sname = scan:GetName()
    for i = 1, scan:NumLines() do
      local l = _G[sname .. "TextLeft" .. i]
      local r = _G[sname .. "TextRight" .. i]
      local text = l and l:GetText()
      local rtext = r and r:IsShown() and r:GetText()

      if text then
        local lr, lg, lb = l:GetTextColor()
        if rtext and rtext ~= "" then
          local rr, rg, rb = r:GetTextColor()
          tip:AddDoubleLine(text, rtext, lr, lg, lb, rr, rg, rb)
        else
          AddWrapped(tip, text, limit, lr, lg, lb)
        end
      end
    end
  end

  local function Render(tooltip, shown, new)
    local count = getn(shown)
    if count > 2 then count = 2 end

    for i = 1, count do
      local tip, sh = tips[i], shown[i]
      tip:SetOwner(tooltip, "ANCHOR_NONE")
      tip:ClearAllPoints()
      tip:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

      -- width limit = the hovered tooltip's width (minus 10px padding each side)
      local limit = max(tooltip:GetWidth() * tooltip:GetEffectiveScale() / tip:GetEffectiveScale() - 20, 150)

      Fill(tip, sh.slot, limit)

      -- the change list, only when something actually changes
      if sh.stats then
        local lines = Diff(new, sh.stats)
        if getn(lines) > 0 then
          tip:AddLine(" ")
          if sh.plural then
            AddWrapped(tip, T["If you replace these items, the following stat changes will occur:"], limit, 1, .82, 0)
          else
            AddWrapped(tip, T["If you replace this item, the following stat changes will occur:"], limit, 1, .82, 0)
          end
          for m = 1, getn(lines) do AddWrapped(tip, lines[m], limit, 1, 1, 1) end
        end
      end
      tip:Show()
    end

    for i = count + 1, 2 do tips[i]:Hide() end
    Place(tooltip, count)
    return count
  end

  ---------------------------------------------------------------- when to compare

  -- the auction house always compares (like the game's own tooltip), everything else needs shift
  local function InAuction()
    if not (AuctionFrame and AuctionFrame:IsVisible()) then return false end
    local f = GetMouseFocus()
    local depth = 0
    while f and depth < 8 do
      if f == AuctionFrame then return true end
      f = f:GetParent()
      depth = depth + 1
    end
    return false
  end

  -- hovering your own paperdoll: nothing to compare
  local function OnPaperdoll()
    local f = GetMouseFocus()
    local n = f and f:GetName()
    return n and strfind(n, "^Character.+Slot$") and true or false
  end

  local state = { sig = nil, count = 0, lines = 0, lines2 = 0 }

  local function HideCompare()
    ShoppingTooltip1:Hide()
    ShoppingTooltip2:Hide()
    state.sig, state.count, state.lines, state.lines2 = nil, 0, 0, 0
  end

  local function ShowCompare(tooltip)
    local auction = InAuction()
    if not (IsShiftKeyDown() or auction) or OnPaperdoll() then
      if state.sig then HideCompare() end
      return
    end

    -- cheap signature so the tooltip is only re-read when it actually changed
    local name = tooltip:GetName()
    local n = tooltip:NumLines()
    local l1, l2, ln = _G[name .. "TextLeft1"], _G[name .. "TextLeft2"], _G[name .. "TextLeft" .. n]
    local sig = name .. (auction and "A" or "S") .. n .. (l1 and l1:GetText() or "")
      .. "|" .. (l2 and l2:GetText() or "") .. "|" .. (ln and ln:GetText() or "")

    if state.sig == sig then
      if state.count == 0 then return end
      -- something else (e.g. the game's own compare) overwrote our tooltip: draw it again
      if ShoppingTooltip1:IsShown() and ShoppingTooltip1:NumLines() == state.lines
        and (state.count < 2 or (ShoppingTooltip2:IsShown() and ShoppingTooltip2:NumLines() == state.lines2)) then
        return
      end
    end

    local kind, slot = Identify(tooltip)
    local shown = kind and Targets(kind, slot)
    if not shown or getn(shown) == 0 then
      HideCompare()
      state.sig = sig
      return
    end

    local count = Render(tooltip, shown, Parse(tooltip))
    state.sig, state.count, state.lines = sig, count, ShoppingTooltip1:NumLines()
    state.lines2 = (count == 2) and ShoppingTooltip2:NumLines() or 0
  end

  -- the game's own compare would fight with ours
  if GameTooltip_ShowCompareItem then
    GameTooltip_ShowCompareItem = function() end
  end

  -- show item compare on default tooltips
  local default = CreateFrame("Frame", nil, GameTooltip)
  default:SetScript("OnUpdate", function()
    ShowCompare(GameTooltip)
  end)
  default:SetScript("OnHide", function()
    if not ItemRefTooltip:IsShown() then HideCompare() end
  end)

  -- show compare on clicked chat links (only while no other tooltip is up)
  local ref = CreateFrame("Frame", nil, ItemRefTooltip)
  ref:SetScript("OnUpdate", function()
    if GameTooltip:IsShown() then return end
    ShowCompare(ItemRefTooltip)
  end)
  ref:SetScript("OnHide", function()
    if not GameTooltip:IsShown() then HideCompare() end
  end)

  -- show compare on atlas tooltips
  ShaguTweaks.HookAddonOrVariable("AtlasLoot", function()
    local atlas = CreateFrame("Frame", nil, AtlasLootTooltip)
    atlas:SetScript("OnUpdate", function()
      ShowCompare(AtlasLootTooltip)
      if AtlasLootTooltip2 then ShowCompare(AtlasLootTooltip2) end
    end)
  end)
end
