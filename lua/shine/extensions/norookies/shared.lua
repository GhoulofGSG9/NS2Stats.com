--[[
    Shine No Rookies - Shared
]]
local Shine = Shine

local Plugin = {}

function Plugin:SetupDataTable()
    self:AddNetworkMessage("ShowSwitch", {}, "Client" )
end

Shine:RegisterExtension( "norookies", Plugin )

if Server then return end

function Plugin:ReceiveShowSwitch()
   local Votemenu = Shine.VoteMenu
   local Switch = Shine.Plugins.serverswitch
   if Votemenu and Switch and next( Switch.ServerList ) then
      Shared.ConsoleCommand("sh_votemenu")
      Votemenu:SetPage("ServerSwitch")
   end
end