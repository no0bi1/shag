local module = ShaguTweaks:register({
  title = "Map Speed Readout",
  description = "Adds /mapspeed to print your movement speed in yards per second",
  expansions = { ["vanilla"] = true },
  category = "interface",
  enabled = true,
})

local _G = ShaguTweaks.GetGlobalEnv()

module.enable = function(self)
  local frame = nil

  _G.SLASH_SHAGUMAPSPEED1 = "/mapspeed"
  _G.SlashCmdList["SHAGUMAPSPEED"] = function()
    -- toggle off
    if frame then
      frame:SetScript("OnUpdate", nil)
      frame = nil
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00Map speed readout: OFF|r")
      return
    end

    -- Astrolabe comes from Questie
    if not _G.Astrolabe then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Map speed readout needs Questie (Astrolabe) loaded.|r")
      return
    end

    frame = CreateFrame("Frame")
    frame.elapsed = 0
    frame.c, frame.z, frame.x, frame.y = _G.Astrolabe:GetCurrentPlayerPosition()

    frame:SetScript("OnUpdate", function()
      this.elapsed = this.elapsed + arg1
      if this.elapsed < 1 then return end

      local c, z, x, y = _G.Astrolabe:GetCurrentPlayerPosition()

      if c and this.c then
        local d = _G.Astrolabe:ComputeDistance(this.c, this.z, this.x, this.y, c, z, x, y)
        if d then
          DEFAULT_CHAT_FRAME:AddMessage(
            "|cffffff00Speed: " .. floor(d / this.elapsed * 10) / 10 .. " yd/s|r"
          )
        end
      end

      this.c, this.z, this.x, this.y = c, z, x, y
      this.elapsed = 0
    end)

    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00Map speed readout: ON|r")
  end
end