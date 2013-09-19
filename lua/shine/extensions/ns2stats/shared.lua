--[[
Shine ns2stats plugin. - Shared 
]]

local Plugin = {}

Plugin.DefaultState = true

function Plugin:SetupDataTable()

    local AwardMessage = {
    message = "string (255)",
    duration = "integer (0 to 1800)"
    }

   self:AddNetworkMessage("StatsAwards", AwardMessage, "Client" )

    local Config = {
        WebsiteApiUrl = "string(255)",
        SendMapData = "boolean",
    }
    self:AddNetworkMessage("StatsConfig", Config, "Client" )
end

Shine:RegisterExtension( "ns2stats", Plugin )