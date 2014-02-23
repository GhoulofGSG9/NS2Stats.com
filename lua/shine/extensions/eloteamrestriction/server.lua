--[[
    Shine Ns2Stats EloTeamRestriction - Server
]]
Script.Load( "lua/shine/core/server/playerinfohub.lua" )

local Shine = Shine

local InfoHub = Shine.PlayerInfoHub

local Notify = Shared.Message
local StringFormat = string.format

local JsonDecode = json.decode
local HTTPRequest = Shared.SendHTTPRequest

local Plugin = Plugin

Plugin.Version = "1.6"
Plugin.DefaultState = false

Plugin.HasConfig = true
Plugin.ConfigName = "eloteamrestriction.json"

Plugin.DefaultConfig = {
    UseSteamTime = false,
    ForceSteamTime = false,
    RestrictionMode = 0,
    AllowSpectating = true,
    ShowSwitchAtBlock = false,
    TeamStats = true,
    MinElo = 1300, 
    MaxElo = 2000,
    MinKD = 0.5,
    MaxKD = 3,
    ShowInform = true,
    InformMessage = "This Server is Elo rating restricted",
    BlockMessage = "You don't fit to the Elo rating limit on this server. Your ELO:  %s Server: Min %s , Max %s",
    KickMessage = "You will be kicked in %s seconds",
    BlockNewPlayers = false,
    MinPlayTime = 0,
    MaxPlayTime = 99999,
    KickBlockedPlayers = false,
    Kicktime = 60,
}

Plugin.CheckConfig = true

function Plugin:Initialise()
    local Gamemode = Shine.GetGamemode()
    if Gamemode ~= "ns2" then        
        return false, StringFormat( "The eloteamrestriction plugin does not work with %s.", Gamemode )
    end
  
    self.Enabled = true
    return true
end

local Kicktimes = {}

function Plugin:ClientConfirmConnect( Client )
    local Player = Client:GetControllingPlayer()
    if self.Config.ShowInform and Player then self:Notify( Player, self.Config.InformMessage ) end
end

function Plugin:ClientDisconnect(Client)
    local SteamId = Client:GetUserId()
    if not SteamId or SteamId <= 0 then return end
    
    self:DestroyTimer(StringFormat( "Kick_%s", SteamId ))
    Kicktimes[ SteamId ] = nil
end

function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )    
    local Client = Player:GetClient()
    
    if ShineForce or not Shine:IsValidClient( Client ) or Shine:HasAccess( Client, "sh_ignoreelo" ) or NewTeam == kTeamReadyRoom then return end
    
    local SteamId = Client:GetUserId()
    if not SteamId or SteamId <= 0 then return end
    
    if self.Config.AllowSpectating and NewTeam == kSpectatorIndex then self:DestroyTimer( StringFormat( "Kick_%s", SteamId )) return end
    
    if not InfoHub:GetIsRequestFinished( SteamId ) then
        self:Notify( Player, self.Config.WaitMessage )
        return false
    end
    
    local Playerdata = InfoHub:GetNs2StatsData( SteamId )
    
    --check ns2stats timeouts
    if Playerdata == -1 then return end
    
    --check if datas exist
    if not Playerdata or Playerdata == 0 then
        if self.Config.BlockNewPlayers then
            self:Notify( Player, self.Config.BlockMessage:sub( 1, self.Config.BlockMessage:find( ".", 1, true )))
            if self.Config.ShowSwitchAtBlock then
                self:SendNetworkMessage( Client, "ShowSwitch", {}, true )
            end
            self:Kick( Player )
            return false
        else
            return
        end 
    end
    
    --check if Player fits to MinPlayTime
    local SteamTime = tonumber( InfoHub:GetSteamData( SteamId ).PlayTime )
    local Ns2StatsPlaytime = tonumber( Playerdata.time_played ) / 60 or 0
    
    local Playtime = Ns2StatsPlaytime
    
    if self.Config.UseSteamTime and SteamTime and SteamTime > Ns2StatsPlaytime then
        Playtime = SteamTime
    end
    
    if self.Config.ForceSteamTime and not SteamTime or Playtime / 60 < self.Config.MinPlayTime or Playtime / 60 > self.Config.MaxPlayTime then
        self:Notify( Player, self.Config.BlockMessage:sub( 1, self.Config.BlockMessage:find( ".", 1, true )))
        if self.Config.ShowSwitchAtBlock then
           self:SendNetworkMessage( Client, "ShowSwitch", {}, true )
        end
        self:Kick( Player )
        return false
    end
    
    local MarineElo = tonumber( Playerdata.marine.elo.rating ) or 1500
    local AlienElo = tonumber( Playerdata.alien.elo.rating ) or 1500
    local Elo = ( MarineElo + AlienElo ) * 0.5
    local Deaths = tonumber( Playerdata.deaths ) or 1
    if Deaths <= 0 then Deaths = 1 end
    local Kills = tonumber( Playerdata.kills ) or 1
    local KD = Kills / Deaths
    
    if self.Config.TeamStats then
        if NewTeam == 1 then
            Elo = MarineElo
            Deaths = tonumber( Playerdata.marine.deaths ) or 1
            if Deaths <= 0 then Deaths = 1 end
            Kills = tonumber( Playerdata.marine.kills ) or 1
            KD = Kills / Deaths
        else
            Elo = AlienElo
            Deaths = tonumber( Playerdata.alien.deaths ) or 1
            if Deaths <= 0 then Deaths = 1 end
            Kills = tonumber( Playerdata.alien.kills ) or 1
            KD = Kills / Deaths
        end
    end
    
    -- now check if Player fits to config
    if self.Config.RestrictionMode == 0 and ( Elo < self.Config.MinElo or Elo > self.Config.MaxElo ) then
        self:Notify( Player, StringFormat( self.Config.BlockMessage, Elo, self.Config.MinElo, self.Config.MaxElo ))
        if self.Config.ShowSwitchAtBlock then
           self:SendNetworkMessage( Client, "ShowSwitch", {}, true )
        end
        self:Kick(Player)
        return false
    elseif self.Config.RestrictionMode == 1 and ( KD < self.Config.MinKD or KD > self.Config.MaxKD ) then
        self:Notify( Player, StringFormat( self.Config.BlockMessage,KD,self.Config.MinKD,self.Config.MaxKD ))
        if self.Config.ShowSwitchAtBlock then
           self:SendNetworkMessage( Client, "ShowSwitch", {}, true )
        end
        self:Kick(Player)
        return false 
    elseif self.Config.RestrictionMode == 2 and ( KD < self.Config.MinKD or KD > self.Config.MaxKD ) and ( Elo< self.Config.MinElo or Elo > self.Config.MaxElo ) then
        self:Notify(Player, StringFormat( self.Config.BlockMessage, Elo, KD, self.Config.MinElo, self.Config.MaxElo, self.Config.MinKD, self.Config.MaxKD ))
        if self.Config.ShowSwitchAtBlock then
           self:SendNetworkMessage( Client, "ShowSwitch", {}, true )
        end
        self:Kick( Player )
        return false
    end
end

function Plugin:Notify( Player, Message, Format, ... )
   if not Player or not Message then return end
   
   local TempBoolean = false
   repeat
       local TempMessage = Message
       if TempMessage:len() > kMaxChatLength then
            TempMessage = TempMessage:sub( 1, kMaxChatLength - 2 )
            TempMessage = StringFormat( "%s-", TempMessage )
            Message = Message:sub( kMaxChatLength - 1 )
       else TempBoolean = true end
       Shine:NotifyDualColour( Player, 100, 255, 100, "[Elo Restriction]", 255, 255, 255, TempMessage, Format, ... )
   until TempBoolean
end

function Plugin:Kick( Player )
    if not self.Config.KickBlockedPlayers then return end
    
    local Client = Player:GetClient()
    if not Shine:IsValidClient( Client ) then return end
    
    local SteamId = Client:GetUserId() or 0
    if SteamId <= 0 then return end
    
    if self:TimerExists( StringFormat( "Kick_%s", SteamId )) then return end
    
    self:Notify( Player, StringFormat( self.Config.KickMessage, self.Config.Kicktime ))
    
    Kicktimes[ SteamId ] = self.Config.Kicktime
    
    self:CreateTimer( StringFormat( "Kick_%s", SteamId ),1, self.Config.Kicktime, function()
        if not Shine:IsValidClient( Client ) then
            Plugin:DestroyTimer( StringFormat( "Kick_%s", SteamId ))
            return
        end
        local Player = Client:GetControllingPlayer()
        
        Kicktimes[ SteamId ] = Kicktimes[SteamId] - 1
        if Kicktimes[ SteamId ] == 10 then self:Notify(Player, StringFormat( self.Config.KickMessage, Kicktimes[ SteamId ] )) end
        if Kicktimes[ SteamId ] <= 5 then self:Notify( Player, StringFormat( self.Config.KickMessage, Kicktimes[ SteamId ] )) end
        if Kicktimes[ SteamId ] <= 0 then
            Shine:Print( "Client %s[%s] was kicked by Elorestriction. Kicking...", true, Player:GetName(), SteamId)
            Client.DisconnectReason = "You didn't fit to the set skill level"
            Server.DisconnectClient( Client )
        end    
    end)    
end