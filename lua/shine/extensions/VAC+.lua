local Shine = Shine
local InfoHub = Shine.PlayerInfoHub

local Plugin = {}

local Notify = Shared.Message

Plugin.Version = "1.0"
Plugin.HasConfig = true

Plugin.ConfigName = "Ns2StatsBadges.json"
Plugin.DefaultConfig =
{
    CheckVACBans = true,
    CheckCommunityBans = true,
    CheckEconomyBans = true,
    AutoBan = true,
    BanTime = 60,
    MaxDaysSinceLastSteamBan = 180,
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:Initialise()
    self.Enabled = true

    InfoHub:Request( "VAC+", "STEAMBANS")

    return true
end

function Plugin:OnReceiveSteamData( Client, Data )
    if Shine:HasAccess( Client, "sh_ignorevacbans" ) then return end

    if type(Data.Bans) ~= "table" or Data.Bans.DaysSinceLastBan == 0 or
            Data.Bans.DaysSinceLastBan > self.Config.MaxDaysSinceLastSteamBan then
        return
    end

    if Data.Bans.VACBanned and self.Config.CheckVACBans then
        self:Kick( Client, 1)
    end

    if Data.Bans.CommunityBanned and self.Config.CheckCommunityBans then
        self:Kick( Client, 2)
    end

    if Data.Bans.EconomyBan ~= "none" and self.Config.CheckEconomyBans then
        self:Kick( Client, 3)
    end
end

local BanTypes = {
    "VAC banned", "Steam Community banned", "Steam Economy banned"
}

function Plugin:Kick( Client, BanType )
    local reason = string.format("The given user has been %s less than %s days ago", BanTypes[BanType],
        self.Config.MaxDaysSinceLastSteamBan)
    if self.Config.Autoban then
        Shared.ConsoleCommand( string.format("sh_ban %s %s %s",Client:GetUserId(), self.Config.BanTime, reason ))
    else
        Shared.ConsoleCommand( string.format("sh_kick %s %s",Client:GetUserId(), reason ))
    end
end

function Plugin:CleanUp()
    InfoHub:RemoveRequest( "VAC+" )
    self.BaseClass.Cleanup( self )
end