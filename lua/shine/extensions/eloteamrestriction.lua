--[[
    Shine Ns2Stats EloTeamRestriction
]]

local Shine = Shine

local Notify = Shared.Message
local StringFormat = string.format

local Plugin = {}

Plugin.Version = "1.5"
Plugin.DefaultState = false

Plugin.HasConfig = true
Plugin.ConfigName = "eloteamrestriction.json"

Plugin.DefaultConfig = {
    WebsiteUrl = "http://ns2stats.com",
    HTTPRequestTimeout = 10,
    RestrictionMode = 0,
    TeamStats = true,
    MinElo = 1300, 
    MaxElo = 2000,
    MinKD = 0.5,
    MaxKD = 3,
    showinform = true,
    InformMessage = "This Server is Elo rating restricted",
    BlockMessage = "You don't fit to the Elo rating limit on this server. Your ELO: %s Server: Min %s , Max %s",
    WaitMessage = "Getting your NS2 Elo rating now, please wait",
    KickMessage = "You will be kicked in %s min",
    BlockNewPlayers = false,
    MinPlayTime = 10,
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

local JoinTime= {}
local Kicktimes = {}

function Plugin:ClientConfirmConnect(Client)
    local player = Client:GetControllingPlayer()
    if self.Config.showinform and player then self:Notify( player, self.Config.InformMessage) end
end

function Plugin:ClientDisconnect(Client)
    local steamid = Client:GetUserId()
    if not steamid or steamid <= 0 then return end
    
    self:DestroyTimer("Player_" .. tostring(steamid))
    JoinTime[steamid] = nil
    Kicktimes[steamid] = nil
end

function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )
    
    -- check if mapvote is running
    local Mapvote = Shine.Plugins.mapvote
    if Mapvote and Mapvote.Enabled and Mapvote:VoteStarted() then return end
    
    local client = Server.GetOwner(Player)
    if not Shine:IsValidClient(client) or Shine:HasAccess(client, "sh_ignoreelo" ) then return end
    
    local steamid = client:GetUserId()
    if not steamid or steamid <= 0 then return end
    
    if ShineForce or NewTeam == 0 or NewTeam > 2 then JoinTime[steamid]= nil self:DestroyTimer("Player_" .. tostring(client:GetUserId())) return end
    
    if not JoinTime[steamid] then JoinTime[steamid] = {} end
    if not JoinTime[steamid][NewTeam] then JoinTime[steamid][NewTeam] = Shared.GetTime()
    elseif JoinTime[steamid][NewTeam] == -1 then self:Notify( Player, self.Config.BlockMessage:sub(1,self.Config.BlockMessage:find(".",1,true))) return false
    elseif Shared.GetTime() - JoinTime[steamid][NewTeam] > 5 then JoinTime[steamid][NewTeam] = nil end
    
    local URL = self.Config.WebsiteUrl .. "/api/player?ns2_id=" .. steamid
    
    Shine.TimedHTTPRequest( URL, "GET",function(response)
        if not response then Gamerules:JoinTeam(Player,NewTeam,nil,true) end
        local Data = json.decode(response)
        local elo = 1500
        local kd = 1
        
        local playerdata
        if Data then playerdata = Data[1] end
        
        --player still connected?
        if not Shine:IsValidClient(client) or Player and Player:GetTeamNumber() ~= 0 then return end
        
        if playerdata then
            --check if player fits to MinPlayTime
            local playtime = playerdata.time_played or 0
            if self.Config.BlockNewPlayers and  playtime / 60 < self.Config.MinPlayTime then
                self:Notify( Player, self.Config.BlockMessage:sub(1,self.Config.BlockMessage:find(".",1,true)))
                JoinTime[steamid][NewTeam]= -1 -- -1 = banned
                self:Kick(Player)
                return
            end
            if self.Config.TeamStats then
                if NewTeam == 1 then
                    elo = playerdata.marine.elo.rating
                    local deaths = tonumber(playerdata.marine.deaths)
                    if deaths == 0 then death = 1 end
                    local kills = tonumber(playerdata.marine.kills)
                    kd = kills / deaths
                elseif NewTeam == 2 then
                    elo = playerdata.alien.elo.rating
                    local deaths = tonumber(playerdata.alien.deaths)
                    if deaths == 0 then death = 1 end
                    local kills = tonumber(playerdata.alien.kills)
                    kd = kills / deaths
                end
                if elo == "" or elo == "-" then elo = 1500 end  
                elo = tonumber(elo)                         
            else
                    elo = playerdata.elo.rating
                    local deaths = tonumber(playerdata.deaths)
                    if deaths == 0 then death = 1 end
                    local kills = tonumber(playerdata.kills)
                    kd = kills / deaths
            end
        else
            -- should we block people without entry at ns2stats?
             if self.Config.BlockNewPlayers then 
                self:Notify( Player, self.Config.BlockMessage:sub(1,self.Config.BlockMessage:find(".",1,true)))
                JoinTime[steamid][NewTeam]= -1 -- -1 = banned
                self:Kick(Player)
                return
            end
        end
        
        -- now check if player fits to config      
        if self.Config.RestrictionMode == 0 and (elo< self.Config.MinElo or elo > self.Config.MaxElo) then
            self:Notify( Player, StringFormat(self.Config.BlockMessage,elo,self.Config.MinElo,self.Config.MaxElo))
            JoinTime[steamid][NewTeam]= -1 -- -1 = banned
            self:Kick(Player) 
        elseif self.Config.RestrictionMode == 1 and (kd< self.Config.MinKD or kd > self.Config.MaxKD) then
            self:Notify( Player, StringFormat(self.Config.BlockMessage,kd,self.Config.MinKD,self.Config.MaxKD ))
            JoinTime[steamid][NewTeam]= -1 -- -1 = banned
            self:Kick(Player) 
        elseif self.Config.RestrictionMode == 2 and (kd< self.Config.MinKD or kd > self.Config.MaxKD) and (elo< self.Config.MinElo or elo > self.Config.MaxElo) then
            self:Notify(Player, StringFormat(self.Config.BlockMessage,elo,kd,self.Config.MinElo,self.Config.MaxElo,self.Config.MinKD,self.Config.MaxKD) )
            JoinTime[steamid][NewTeam]= -1 -- -1 = banned
            self:Kick(Player)
        else
            Gamerules:JoinTeam(Player,NewTeam,nil,true) 
        end
    end,function()
         --player still connected?
        if not Shine:IsValidClient(client) or Player and Player:GetTeamNumber() ~= 0 then return end
        
        if self.Config.BlockNewPlayers then 
                self:Notify( Player, self.Config.BlockMessage:sub(1,self.Config.BlockMessage:find(".",1,true)))
                JoinTime[steamid][NewTeam]= -1 -- -1 = banned
                self:Kick(Player)
        else Gamerules:JoinTeam(Player,NewTeam,nil,true) end
    end,self.Config.HTTPRequestTimeout)
    
    self:Notify( Player, self.Config.WaitMessage )
    return false
end

function Plugin:Notify( Player, Message, Format, ... )
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
    
    self:DestroyTimer("Player_" .. tostring(steamid))
    self:Notify(player, StringFormat(self.Config.KickMessage,self.Config.Kicktime/60))
    Kicktimes[steamid] = self.Config.Kicktime
    self:CreateTimer("Player_" .. tostring(steamid),1, self.Config.Kicktime, function()        
        Kicktimes[steamid] = Kicktimes[steamid]-1
        if Kicktimes[steamid] == 10 then self:Notify(player, StringFormat(self.Config.KickMessage, Kicktimes[steamid])) end
        if Kicktimes[steamid] <= 5 then self:Notify(player, StringFormat(self.Config.KickMessage, Kicktimes[steamid])) end        
        if Kicktimes[steamid] <= 0 then
            Shine:Print( "Client %s[%s] was kicked by Elorestriction. Kicking...", true, player:GetName(), steamid)
            client.DisconnectReason = "You didn't fit to the set skill level"
            Server.DisconnectClient( client )
        end    
    end)    
end

function Plugin:Cleanup()
    self.Enabled = false
end

Shine:RegisterExtension( "eloteamrestriction", Plugin )