--[[
Shine ns2stats plugin. - Shared 
]]
local Plugin = {}
Plugin.DefaultState = true

function Plugin:SetupDataTable()
	local AwardMessage = {
		Message = "string (800)",
		Duration = "integer (0 to 1800)",
		ColourR = "integer (0 to 255)",
		ColourG = "integer (0 to 255)",
		ColourB = "integer (0 to 255)",
	}
	self:AddNetworkMessage("StatsAwards", AwardMessage, "Client" )

	self:AddDTVar( "boolean", "SendMapData", false )
	self:AddDTVar( "string (255)", "WebsiteUrl", "http://ns2stats.com" )
end

Shine:RegisterExtension( "ns2stats", Plugin )