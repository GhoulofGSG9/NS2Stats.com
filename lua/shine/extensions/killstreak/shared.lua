--[[
Shine Killstreak Plugin - Shared
]]

local Plugin = {}

function Plugin:SetupDataTable()

    local Sound = {
        Name = "string(255)",
    }
    self:AddNetworkMessage("PlaySound", Sound, "Client" )
end

function Plugin:Initialise()
    self.Enabled = true
end

function Plugin:Cleanup()
    self.Enabled = false
end    
Shine:RegisterExtension( "Killstreak", Plugin )