--[[
Shine Killstreak Plugin - Shared
]]

local Plugin = {}
Plugin.Version = "1.0"

function Plugin:SetupDataTable()
    local Sound = {
        Name = "string(255)",
    }
    self:AddNetworkMessage( "PlaySound", Sound, "Client" )
end

Shine:RegisterExtension( "killstreak", Plugin )