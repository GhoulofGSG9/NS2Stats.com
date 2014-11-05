--[[
Shine Killstreak Plugin - Shared
]]

local Plugin = {}
Plugin.Version = "1.0"

function Plugin:SetupDataTable()
	local Command ={
		Name = "string(255)",
		Value = "integer (0 to 200)",
	}
	self:AddNetworkMessage( "Command", Command, "Client" )
	
    local Sound = {
        Name = "string(255)",
    }
    self:AddNetworkMessage( "PlaySound", Sound, "Client" )
end

Shine:RegisterExtension( "killstreak", Plugin )