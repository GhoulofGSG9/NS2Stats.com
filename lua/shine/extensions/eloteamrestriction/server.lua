--[[
    Shine Ns2Stats EloTeamRestriction - Server
]]

local Shine = Shine

local Notify = Shared.Message
local StringFormat = string.format

local Decode = json.decode
local HTTPRequest = Shared.SendHTTPRequest

local Plugin = Plugin

Plugin.Version = "1.5"
Plugin.DefaultState = false

Plugin.HasConfig = true
Plugin.ConfigName = "eloteamrestriction.json"

Plugin.DefaultConfig = {
    WebsiteUrl = "http://ns2stats.com",
    UseSteamTime = false,
    HTTPMaxWaitTime = 20,
    RestrictionMode = 0,
    AllowSpectating = true,
    ShowSwitchAtBlock = false,
    TeamStats = true,
    MinElo = 1300, 
    MaxElo = 2000,
    MinKD = 0.5,
    MaxKD = 3,
    showinform = true,
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
local Ns2statsData = {}
local SteamTime = {}

function Plugin:ClientConfirmConnect(Client)
    local player = Client:GetControllingPlayer()
    if self.Config.showinform and player then self:Notify( player, self.Config.InformMessage) end
end

function Plugin:ClientConnect( Client )
    if not Shine:IsValidClient( Client ) or Shine:HasAccess(Client, "sh_ignoreelo" ) then return end
    
    local steamid = Client:GetUserId()
    if not steamid or steamid <= 0 then return end   
    local steamid64 = StringFormat("%s%s",76561,steamid + 197960265728)

    if Ns2statsData[steamid] or not Shine:IsValidClient(Client) then return
    elseif not self:TimerExists(StringFormat("Wait_%s",steamid)) then
        self:CreateTimer(StringFormat("Wait_%s",steamid),self.Config.HTTPMaxWaitTime, 1, function()
            Ns2statsData[steamid] = 0
        end)
    end
    
    if self.Config.UseSteamTime and not SteamTime[steamid] then
        HTTPRequest(StringFormat("http://api.steampowered.com/IPlayerService/GetRecentlyPlayedGames/v0001/?key=2EFCCE2AF701859CDB6BBA3112F95972&steamid=%s&format=json",steamid64),"GET",function(response)
            local temp = json.decode(response)
            temp = temp and temp.response and temp.response.games
            if not temp then return end
            for i = 1, #temp do
                if temp[i].appid == 4920 then
                    SteamTime[steamid] = temp[i].playtime_forever * 60
                    return
                end
            end
        end)
    end
    
    local URL = StringFormat("%s/api/player?ns2_id=%s",self.Config.WebsiteUrl,steamid)    
    Shine.TimedHTTPRequest( URL, "GET",function(response)
        Ns2statsData[steamid] = Decode(response) and Decode(response)[1] or 1
        self:DestroyTimer(StringFormat("Wait_%s",steamid))
    end,function()
        self:ClientConnect( Client ) 
    end)
end

function Plugin:ClientDisconnect(Client)
    local steamid = Client:GetUserId()
    if not steamid or steamid <= 0 then return end
    
    self:DestroyTimer(StringFormat("Kick_%s",steamid))
    Kicktimes[steamid] = nil
end

function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )    
    local client = Player:GetClient()
    
    if ShineForce or not Shine:IsValidClient( client ) or Shine:HasAccess(client, "sh_ignoreelo" ) or NewTeam == kTeamReadyRoom then return end
    
    local steamid = client:GetUserId()
    if not steamid or steamid <= 0 then return end
    
    if self.Config.AllowSpectating and NewTeam == kSpectatorIndex then self:DestroyTimer(StringFormat("Kick_%s",steamid)) return end
    
    if self:TimerExists(StringFormat("Wait_%s", steamid)) then
        self:Notify( Player, self.Config.WaitMessage )
        return false
    end
    
    local playerdata = Ns2statsData[steamid]
    
    --check ns2stats timeouts
    if playerdata == 0 then return end
    
    --check if datas exist
    if not playerdata or playerdata == 1 then
        if self.Config.BlockNewPlayers then
            self:Notify( Player, self.Config.BlockMessage:sub(1, self.Config.BlockMessage:find(".", 1, true)))
            if self.Config.ShowSwitchAtBlock then
                self:SendNetworkMessage(client, "ShowSwitch", {}, true )
            end
            self:Kick(Player)
            return false
        else
            return
        end 
    end
          
    --check if player fits to MinPlayTime
    local playtime = SteamTime[steamid] or tonumber(playerdata.time_played) or 0
    if playtime / 60 < self.Config.MinPlayTime or playtime / 60 > self.Config.MaxPlayTime then
        self:Notify( Player, self.Config.BlockMessage:sub(1, self.Config.BlockMessage:find(".",1,true)))
        if self.Config.ShowSwitchAtBlock then
           self:SendNetworkMessage(client, "ShowSwitch", {}, true )
        end
        self:Kick(Player)
        return false
    end
    
    local marineelo = tonumber(playerdata.marine.elo.rating) or 1500
    local alienelo = tonumber(playerdata.alien.elo.rating) or 1500
    local elo = (marineelo + alienelo) * 0.5
    local deaths = tonumber(playerdata.deaths) or 1
    if deaths <= 0 then death = 1 end
    local kills = tonumber(playerdata.kills) or 1
    local kd = kills / deaths
    
    if self.Config.TeamStats then
        if NewTeam == 1 then
            elo = marineelo
            deaths = tonumber(playerdata.marine.deaths) or 1
            if deaths <= 0 then death = 1 end
            kills = tonumber(playerdata.marine.kills) or 1
            kd = kills / deaths
        else
            elo = alienelo
            deaths = tonumber(playerdata.alien.deaths) or 1
            if deaths <= 0 then death = 1 end
            kills = tonumber(playerdata.alien.kills) or 1
            kd = kills / deaths
        end
    end
    
    -- now check if player fits to config
    if self.Config.RestrictionMode == 0 and (elo < self.Config.MinElo or elo > self.Config.MaxElo) then
        self:Notify( Player, StringFormat(self.Config.BlockMessage,elo,self.Config.MinElo,self.Config.MaxElo))
        if self.Config.ShowSwitchAtBlock then
           self:SendNetworkMessage(client, "ShowSwitch", {}, true )
        end
        self:Kick(Player)
        return false
    elseif self.Config.RestrictionMode == 1 and (kd < self.Config.MinKD or kd > self.Config.MaxKD) then
        self:Notify( Player, StringFormat(self.Config.BlockMessage,kd,self.Config.MinKD,self.Config.MaxKD ))
        if self.Config.ShowSwitchAtBlock then
           self:SendNetworkMessage(client, "ShowSwitch", {}, true )
        end
        self:Kick(Player)
        return false 
    elseif self.Config.RestrictionMode == 2 and (kd < self.Config.MinKD or kd > self.Config.MaxKD) and (elo< self.Config.MinElo or elo > self.Config.MaxElo) then
        self:Notify(Player, StringFormat(self.Config.BlockMessage,elo,kd,self.Config.MinElo,self.Config.MaxElo,self.Config.MinKD,self.Config.MaxKD) )
        if self.Config.ShowSwitchAtBlock then
           self:SendNetworkMessage(client, "ShowSwitch", {}, true )
        end
        self:Kick(Player)
        return false
    end
end

function Plugin:Notify( Player, Message, Format, ... )
   if not Player or not Message then return end
   
   local a = false
   repeat
       local m = Message
       if m:len() > kMaxChatLength then
            m = m:sub( 1, kMaxChatLength-2 )
            m = m .."-"
            Message = Message:sub(kMaxChatLength-1)
       else a= true end
       Shine:NotifyDualColour( Player, 100, 255, 100, "[Elo Restriction]", 255, 255, 255,m, Format, ... )
   until a
end

function Plugin:Kick(player)
    if not self.Config.KickBlockedPlayers then return end
    
    local client = player:GetClient()
    if not Shine:IsValidClient(client) then return end
    
    local steamid = client:GetUserId() or 0
    if steamid<= 0 then return end
    
    if self:TimerExists(StringFormat("Kick_%s",steamid)) then return end
    
    self:Notify(player, StringFormat(self.Config.KickMessage,self.Config.Kicktime/60))
    Kicktimes[steamid] = self.Config.Kicktime
    self:CreateTimer(StringFormat("Kick_%s",steamid),1, self.Config.Kicktime, function()
        if not Shine:IsValidClient( client ) then
            Plugin:DestroyTimer("Player_" .. tostring(steamid))
            return
        end
        local player = client:GetControllingPlayer()
        
        Kicktimes[steamid] = Kicktimes[steamid] - 1
        if Kicktimes[steamid] == 10 then self:Notify(player, StringFormat(self.Config.KickMessage, Kicktimes[steamid])) end
        if Kicktimes[steamid] <= 5 then self:Notify(player, StringFormat(self.Config.KickMessage, Kicktimes[steamid])) end        
        if Kicktimes[steamid] <= 0 then
            Shine:Print( "Client %s[%s] was kicked by Elorestriction. Kicking...", true, player:GetName(), steamid)
            client.DisconnectReason = "You didn't fit to the set skill level"
            Server.DisconnectClient( client )
        end    
    end)    
end