--[[
    Shine Ns2Stats EloTeamRestriction - Server
]]
Script.Load( "lua/shine/core/server/playerinfohub.lua" )

local Shine = Shine
local InfoHub = Shine.PlayerInfoHub

local StringFormat = string.format

local Plugin = Plugin

Plugin.Version = "1.6"

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
    BlockMessage = "You don't fit to the Elo rating limit on this server. Your ELO: %s Server: Min %s , Max %s",
    KickMessage = "You will be kicked in %s seconds",
	WaitMessage = "Please wait while your Player data is retrieved",
    BlockNewPlayers = false,
    MinPlayTime = 0,
    MaxPlayTime = 99999,
    Kick = true,
    Kicktime = 60,
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.Name = "Elo Restriction"

function Plugin:Initialise()
    local Gamemode = Shine.GetGamemode()
    if Gamemode ~= "ns2" then        
        return false, StringFormat( "The eloteamrestriction plugin does not work with %s.", Gamemode )
    end

    InfoHub:Request( self.Name, "NS2STATS" )
    if self.Config.UseSteamTime or self.Config.ForceSteamTime then
        InfoHub:Request( self.Name, "STEAMPLAYTIME" )
    end

    self.Enabled = true
    return true
end

function Plugin:ClientConfirmConnect( Client )
    local Player = Client:GetControllingPlayer()
    if self.Config.ShowInform and Player then self:Notify( Player, self.Config.InformMessage ) end

    self:AutoCheck( Client )
end

function Plugin:ClientDisconnect( Client )
    local SteamId = Client:GetUserId()
    if not SteamId or SteamId <= 0 then return end

    self:DestroyTimer(StringFormat( "Kick_%s", SteamId ))
end

function Plugin:JoinTeam( _, Player, NewTeam, _, ShineForce )
    if ShineForce or self.Config.AllowSpectating and NewTeam == kSpectatorIndex or NewTeam == kTeamReadyRoom then
        self:DestroyTimer( StringFormat( "Kick_%s", SteamId ))
        return
    end

	return self:Check( Player )
end

function Plugin:OnReceiveSteamData( Client )
    self:AutoCheck( Client )
end

function Plugin:OnReceiveHiveData( Client )
    self:AutoCheck( Client )
end

function Plugin:OnReceiveNs2StatsData( Client )
    self:AutoCheck( Client )
end

function Plugin:AutoCheck( Client )
    local Player = Client:GetControllingPlayer()
    local SteamId = Client:GetUserId()

    if not Player or not InfoHub:GetIsRequestFinished( SteamId ) then return end

    self:Check( Player )
end

function Plugin:Check( Player )
    PROFILE("EloTeamRestriction:Check()")
    if not Player then return end

	local Client = Player:GetClient()
    if not Shine:IsValidClient( Client ) or Shine:HasAccess( Client, "sh_ignoreelo" ) then return end
    
    local SteamId = Client:GetUserId()
    if not SteamId or SteamId <= 0 then return end
	
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
    local Ns2StatsPlaytime = tonumber( Playerdata.time_played ) or 0
    
    local Playtime = Ns2StatsPlaytime / 60
    
    if self.Config.UseSteamTime and SteamTime and SteamTime > Playtime then
        Playtime = SteamTime
    end
    
    if self.Config.ForceSteamTime then
		if not SteamTime or SteamTime < 0 or SteamTime / 60 < self.Config.MinPlayTime or SteamTime / 60 > self.Config.MaxPlayTime then
			self:Notify( Player, self.Config.BlockMessage:sub( 1, self.Config.BlockMessage:find( ".", 1, true )))
			if self.Config.ShowSwitchAtBlock then
			   self:SendNetworkMessage( Client, "ShowSwitch", {}, true )
			end
			self:Kick( Player )
			return false
		end
    elseif not Playtime or Playtime < 0 or Playtime / 60 < self.Config.MinPlayTime or Playtime / 60 > self.Config.MaxPlayTime then
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
    if Deaths < 1 then Deaths = 1 end
    local Kills = tonumber( Playerdata.kills ) or 1
    --noinspection UnusedDef
    local KD = Kills / Deaths
    
    if self.Config.TeamStats then
        if NewTeam == 1 then
            Elo = MarineElo
            Deaths = tonumber( Playerdata.marine.deaths ) or 1
            if Deaths < 1 then Deaths = 1 end
            Kills = tonumber( Playerdata.marine.kills ) or 1
            --noinspection UnusedDef
            KD = Kills / Deaths
        else
            Elo = AlienElo
            Deaths = tonumber( Playerdata.alien.deaths ) or 1
            if Deaths < 1 then Deaths = 1 end
            Kills = tonumber( Playerdata.alien.kills ) or 1
            --noinspection UnusedDef
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
	
	self:DestroyTimer( StringFormat( "Kick_%s", SteamId ))
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
       Shine:NotifyDualColour( Player, 100, 255, 100, StringFormat("[%s]", self.Name), 255, 255, 255, TempMessage, Format, ... )
   until TempBoolean
end

Plugin.DisconnectReason = "You didn't fit to the set skill level"
function Plugin:Kick( Player )
    if not self.Config.Kick then return end
    
    local Client = Player:GetClient()
    if not Shine:IsValidClient( Client ) then return end
    
    local SteamId = Client:GetUserId() or 0
    if SteamId <= 0 then return end
    
    if self:TimerExists( StringFormat( "Kick_%s", SteamId )) then return end
    
    self:Notify( Player, StringFormat( self.Config.KickMessage, self.Config.Kicktime ))
        
    self:CreateTimer( StringFormat( "Kick_%s", SteamId ), 1, self.Config.Kicktime, function( Timer )
        if not Shine:IsValidClient( Client ) then
            Timer:Destroy()
            return
        end
		
		local Player = Client:GetControllingPlayer()
		
        local Kicktimes = Timer:GetReps()
        if Kicktimes == 10 then self:Notify( Player, StringFormat( self.Config.KickMessage, Kicktimes ) ) end
        if Kicktimes <= 5 then self:Notify( Player, StringFormat( self.Config.KickMessage, Kicktimes ) ) end
        if Kicktimes <= 0 then
            Shine:Print( "Client %s [ %s ] was kicked by %s. Kicking...", true, Player:GetName(), SteamId, self.Name)
            Client.DisconnectReason = self.DisconnectReason
            Server.DisconnectClient( Client )
        end    
    end)    
end

function Plugin:CleanUp()
    InfoHub:RemoveRequest(self.Name)
    self.BaseClass.Cleanup( self )
end