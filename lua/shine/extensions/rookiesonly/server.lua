--[[
    Shine No Rookies - Server
]]
local Shine = Shine
local InfoHub = Shine.PlayerInfoHub
local Plugin = Plugin

local Notify = Shared.Message
local StringFormat = string.format

Plugin.Version = "1.0"
Plugin.HasConfig = true

Plugin.ConfigName = "rookiesonly.json"
Plugin.DefaultConfig =
{
    Mode = 1, -- 1: Level 2: Playtime
    MaxPlaytime = 20,
    MaxLevel = 5,
    ShowInform = false,
    InformMessage = "This server is rookies only",
    AllowSpectating = true,
    BlockMessage = "This server is rookies only",
    Kick = true,
    Kicktime = 20,
    KickMessage = "You will be kicked in %s seconds",
    WaitMessage = "Please wait while your data is retrieved",
    ShowSwitchAtBlock = false
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.Name = "Rookies Only"
Plugin.DisconnectReason = "You are not a rookie anymore"

function Plugin:Initialise()
    local Gamemode = Shine.GetGamemode()

    if Gamemode ~= "ns2" then
        return false, StringFormat( "The rookie-only plugin does not work with %s.", Gamemode )
    end

    self.Enabled = true
    self.Config.Mode = math.Clamp( self.Config.Mode, 1, 2 )
    return true
end

function Plugin:Check( Player )
    PROFILE("Rookies Only:Check()")
    if not Player then return end

    local Client = Player:GetClient()

    if not Shine:IsValidClient( Client ) or Shine:HasAccess( Client, "sh_mentor" ) then return end

    local SteamId = Client:GetUserId()
    if not SteamId or SteamId <= 0 then return end

    if not InfoHub:GetIsRequestFinished( SteamId ) then self:Notify( Player, self.Config.WaitMessage ) return false end

    local HiveData = InfoHub:GetHiveData(SteamId)
    if not HiveData then return end

    if self.Mode == 1 then
        if not HiveData.level or tonumber(HiveData.level) <= self.Config.MaxLevel then
            return
        end
    elseif not HiveData.playTime or tonumber(HiveData.playTime) <= self.Config.MaxPlaytime then
        return
    end

    self:Notify( Player, self.Config.BlockMessage )
    Notify( StringFormat("[Rookies Only]: %s failed the check", Shine.GetClientInfo( Client )))
    if self.Config.ShowSwitchAtBlock then
        self:SendNetworkMessage( Client, "ShowSwitch", {}, true )
    end
    self:Kick( Player )
    return false
end
