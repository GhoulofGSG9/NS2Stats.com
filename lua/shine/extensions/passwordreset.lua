--[[
    Shine PasswordReset
]]

local Shine = Shine
local Notify = Shared.Message

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "PasswordReset.json"
Plugin.DefaultConfig =
{
    MinPlayer = 0,
    ResetTime = 10,
    DefaultPassword = ""    
}

function Plugin:ClientConnect( Client )
    self:DestroyAllTimers()
end

function Plugin:ClientDisconnect( Client )
    if #Shine.GetAllClients() > self.Config.MinPlayers + 1 then return end
    self:SimpleTimer( self.Config.ResetTime * 60, function()
        Notify( "[PasswordReset] Reseting password to default one" )
        Server.SetPassword( tostring( self.Config.DefaultPassword ) or "" )
    end )
end

Shine:RegisterExtension( "passwordreset", Plugin )