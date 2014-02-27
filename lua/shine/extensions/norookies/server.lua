--[[
    Shine No Rookies - Server
]]
Script.Load( "lua/shine/core/server/playerinfohub.lua" )

local Shine = Shine

local InfoHub = Shine.PlayerInfoHub

local Plugin = Plugin

local Notify = Shared.Message
local StringFormat = string.format

local HTTPRequest = Shared.SendHTTPRequest

local JsonDecode = json.decode

Plugin.Version = "1.5"
Plugin.DefaultState = false

Plugin.HasConfig = true

Plugin.ConfigName = "norookies.json"
Plugin.DefaultConfig =
{
    UseSteamTime = true,
    MinPlayer = 0,
    DisableAfterRoundtime = 0,
    MinPlaytime = 8,
    InformAtConnect = true,
    InformMessage = "This server is not rookie friendly",
    BlockTeams = true,
    ShowSwitchAtBlock = false,
    BlockCC = true,
    AllowSpectating = false,
    BlockMessage = "This server is not rookie friendly",
    Kick = true,
    Kicktime = 60,
    KickMessage = "You will be kicked in %s seconds",
    WaitMessage = "Please wait while your Player data is retrieved",
}
Plugin.CheckConfig = true

Shine.Hook.SetupClassHook( "CommandStructure", "OnUse", "CheckComLogin", "ActivePre" )

local Enabled = true

function Plugin:ClientConfirmConnect( Client )
    if self.Config.InformAtConnect then
        local Player = Client:GetControllingPlayer()
        if not Player then return end
        
        self:Notify( Player, self.Config.InformMessage )
    end  
end

function Plugin:SetGameState( Gamerules, NewState, OldState )
    if NewState == kGameState.Started and self.Config.DisableAfterRoundtime > 0 then        
        self:CreateTimer( "Disable", self.Config.DisableAfterRoundtime * 60 , 1, function() Enabled = false end )
    end
end

function Plugin:EndGame( Gamerules, WinningTeam )
    self:DestroyTimer( "Disable" )
    Enabled = true
end

function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )    
    if not Enabled or ShineForce or not self.Config.BlockTeams or Server.GetNumPlayers() < self.Config.MinPlayer or NewTeam == kTeamReadyRoom then return end
    
    return self:Check( Player )
end

function Plugin:CheckComLogin( Chair, Player )
    if not Enabled or not self.Config.BlockCC or not Player or not Player.GetClient or Server.GetNumPlayers() < self.Config.MinPlayer then return end

    return self:Check( Player )
end

function Plugin:Check( Player )
    local Client = Player:GetClient()
    if not Shine:IsValidClient( Client ) or Shine:HasAccess( Client, "sh_ignorestatus" ) then return end
    
    local SteamId = Client:GetUserId()
    if not SteamId or SteamId <= 0 then return end
    
    if not InfoHub:GetIsRequestFinished( SteamId ) then self:Notify( Player, self.Config.WaitMessage ) return false end
    
    local PlayTime
    
    local SteamData = InfoHub:GetSteamData( SteamId )    
    if self.Config.UseSteamTime and ( not PlayTime or SteamData.PlayTime > PlayTime ) then
        PlayTime = SteamData.PlayTime
    end
    
    local HiveData = InfoHub:GetHiveData( SteamId )    
    if type( HiveData ) == "table" and HiveData.playTime and ( not PlayTime or HiveData.playTime > PlayTime ) then
        PlayTime = tonumber( HiveData.playTime )
    elseif not PlayTime then
        PlayTime = HiveData
    end

    local Ns2StatsData = InfoHub:GetNs2StatsData( SteamId )
    if type( Ns2StatsData ) == "table" and Ns2StatsData.time_played and ( not PlayTime or tonumber( Ns2StatsData.time_played ) > PlayTime ) then
        PlayTime = tonumber( Ns2StatsData.time_played )
    elseif not PlayTime then
        PlayTime = Ns2StatsData
    end
    
    if not PlayTime or PlayTime < 0 then return end
    
    if PlayTime < self.Config.MinPlaytime * 3600 then
        self:Notify( Player, self.Config.BlockMessage )
        if self.Config.ShowSwitchAtBlock then
           self:SendNetworkMessage( Client, "ShowSwitch", {}, true )
        end
        self:Kick( Player )
        return false
    end
end

function Plugin:Notify( Player, Message )
    Shine:NotifyDualColour( Player, 100, 255, 100, "[No Rookies]", 255, 255, 255, Message )
end

local Kicktimes = {}

function Plugin:Kick( Player )
    if not self.Config.Kick then return end
    
    local Client = Player:GetClient()
    if not Shine:IsValidClient(Client) then return end
    
    local SteamId = Client:GetUserId() or 0
    if SteamId <= 0 then return end
    
    if self:TimerExists( StringFormat( "Kick_%s", SteamId )) then return end
    self:Notify(Player, StringFormat( self.Config.KickMessage, self.Config.Kicktime ))
    
    Kicktimes[ SteamId ] = self.Config.Kicktime
    self:CreateTimer(StringFormat( "Kick_%s", SteamId ), 1, self.Config.Kicktime, function()
        if not Shine:IsValidClient( Client ) then
            Plugin:DestroyTimer( StringFormat( "Kick_%s", SteamId ))
            return
        end
        
        local Player = Client:GetControllingPlayer()
        
        Kicktimes[ SteamId ] = Kicktimes[ SteamId ] - 1
        if Kicktimes[ SteamId ] == 10 then self:Notify(Player, StringFormat( self.Config.KickMessage, Kicktimes[ SteamId ] )) end
        if Kicktimes[ SteamId ] <= 5 then self:Notify(Player, StringFormat( self.Config.KickMessage, Kicktimes[ SteamId ] )) end        
        if Kicktimes[ SteamId ] <= 0 then
            Shine:Print( "Client %s [ %s ] was kicked by NoRookies. Kicking...", true, Player:GetName(), SteamId )
            Client.DisconnectReason = "You didn't fit to the set min playtime"
            Server.DisconnectClient( Client )
        end
    end )    
end

function Plugin:ClientDisconnect( Client )
    local SteamId = Client:GetUserId()
    if not SteamId or SteamId <= 0 then return end
    
    self:DestroyTimer( StringFormat( "Kick_%s", SteamId ))
end