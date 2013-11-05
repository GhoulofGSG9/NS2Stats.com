--[[
    Shine Ns2Stats Badges - Shared
]]
local Shine = Shine

local Plugin = {}

Plugin.Version = "1.0"
Plugin.DefaultState = false

function Plugin:SetupDataTable()
    local Badge = {
        Name = "string(255)",
    }
    self:AddNetworkMessage("Ns2statsBagdes", Badge, "Client" )
end

Shine:RegisterExtension( "ns2statsbadges", Plugin )