--[[
    Shine No Rookies - Server
]]

local Shine = Shine

local Plugin = Plugin

local Notify = Shared.Message
local StringFormat = string.format
local HTTPRequest = Shared.SendHTTPRequest

Plugin.Version = "1.5"
Plugin.DefaultState = false

Plugin.HasConfig = true

Plugin.ConfigName = "norookies.json"
Plugin.DefaultConfig =
{
    Ns2StatsUrl = "http://ns2stats.com",
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
    HTTPMaxWaitTime = 20,
    WaitMessage = "Please wait while your player data is retrieved",
}
Plugin.CheckConfig = true

Shine.Hook.SetupClassHook( "CommandStructure", "OnUse", "CheckComLogin","ActivePre")

local Enabled = true
local HiveData = {}
local Ns2StatsData = {}
local PlayTime = {}
local SteamTime = {}

function Plugin:ClientConnect( Client )
    if not Shine:IsValidClient( Client ) or Shine:HasAccess(Client, "sh_ignorestatus" ) then return end
    
    local steamid = Client:GetUserId()
    if not steamid or steamid <= 0 then return end
    local steamid64 = StringFormat("%s%s",76561,steamid + 197960265728)  
    
    local Player = Client:GetControllingPlayer()
    
    if PlayTime[steamid] then return end
    
    if not self:TimerExists(StringFormat("Wait_%s", steamid)) then
        self:CreateTimer(StringFormat("Wait_%s", steamid), self.Config.HTTPMaxWaitTime, 1, function()
            if PlayTime[steamid] then return 
            elseif Ns2StatsData[steamid] and Ns2StatsData[steamid] ~= 0 then
                PlayTime[steamid] = Ns2StatsData[steamid].time_played and tonumber(Ns2StatsData[steamid].time_played) or 0
            elseif HiveData[steamid] and HiveData[steamid] ~= 0 then
                PlayTime[steamid] = HiveData[steamid].playTime and tonumber(HiveData[steamid].playTime) or 0
            else    
                PlayTime[steamid] = -1
            end
            local playtime = SteamTime[steamid] or PlayTime[steamid]
            if self.Config.InformAtConnect and playtime >= 0 and playtime < self.Config.MinPlaytime * 3600 then
                self:Notify(Player, self.Config.InformMessage)
            end  
        end)
    end
    
    if self.Config.UseSteamTime and not SteamTime[steamid] then
        HTTPRequest(StringFormat("http://api.steampowered.com/IPlayerService/GetRecentlyPlayedGames/v0001/?key=2EFCCE2AF701859CDB6BBA3112F95972&steamid=%s&format=json",steamid64),"GET",function(response)
            local temp = json.decode(response)
            temp = temp and temp.response and temp.response.games
            if not temp then return end
            for i = 1, #temp do
                if temp[i].appid == 4920 then
                    SteamTime[steamid] = temp[i].playtime_forever and temp[i].playtime_forever * 60
                    return
                end
            end
        end)
    end
    
    if not Ns2StatsData[steamid] then
        local SURL = self.Config.Ns2StatsUrl .. "/api/player?ns2_id=" .. steamid
        HTTPRequest( SURL, "GET", function(response)
            Ns2StatsData[steamid] = json.decode(response) and json.decode(response)[1] or 0
            if HiveData[steamid] then
                if HiveData[steamid] == 0 then
                    if Ns2StatsData[steamid] == 0 then
                        PlayTime[steamid] = -1
                    else 
                        PlayTime[steamid] = Ns2StatsData[steamid].time_played and tonumber(Ns2StatsData[steamid].time_played) or 0    
                    end                    
                else
                    local splaytime = Ns2StatsData[steamid].time_played and tonumber(Ns2StatsData[steamid].time_played) or 0
                    local hplaytime = HiveData[steamid].playTime and tonumber(HiveData[steamid].playTime) or 0
                    PlayTime[steamid] = splaytime > hplaytime and splaytime or hplaytime
                end
                local playtime = SteamTime[steamid] or PlayTime[steamid]
                if self.Config.InformAtConnect and playtime >= 0 and playtime < self.Config.MinPlaytime * 3600 then
                    self:Notify(Player, self.Config.InformMessage)
                end
                self:DestroyTimer(StringFormat("Wait_%s", steamid))
            end
        end)
    end
    
    if not HiveData[steamid] then
        local HURL = StringFormat("http://sabot.herokuapp.com/api/get/playerData/%s",steamid)    
        HTTPRequest( HURL, "GET", function(response)
            HiveData[steamid] = json.decode(response) or 0
            if Ns2StatsData[steamid] then
                if Ns2StatsData[steamid] == 0 then
                    if HiveData[steamid] == 0 then
                        PlayTime[steamid] = -1
                    else
                        PlayTime[steamid] = HiveData[steamid].playTime and tonumber(HiveData[steamid].playTime) or 0   
                    end                    
                else
                    local splaytime = Ns2StatsData[steamid].time_played and tonumber(Ns2StatsData[steamid].time_played) or 0
                    local hplaytime = HiveData[steamid].playTime and tonumber(HiveData[steamid].playTime) or 0
                    PlayTime[steamid] = splaytime > hplaytime and splaytime or hplaytime
                end
                local playtime = SteamTime[steamid] or PlayTime[steamid]
                if self.Config.InformAtConnect and playtime >= 0 and playtime < self.Config.MinPlaytime * 3600 then
                    self:Notify(Player, self.Config.InformMessage)
                end
                self:DestroyTimer(StringFormat("Wait_%s", steamid))
            end
        end)
    end
    
    self:SimpleTimer(5,function() self:ClientConnect( Client ) end)
end

function Plugin:SetGameState( Gamerules, NewState, OldState )
    if NewState == kGameState.Started and self.Config.DisableAfterRoundtime > 0 then        
        self:CreateTimer("Disable", self.Config.DisableAfterRoundtime * 60 , 1, function() Enabled = false end)
    end
end

function Plugin:EndGame( Gamerules, WinningTeam )
    self:DestroyTimer("Disable")
    Enabled = true
end
    
function Plugin:CheckComLogin( Chair, Player )
    if not Enabled or not self.Config.BlockCC or not Player or not Player.GetClient or #Shine.GetAllPlayers() < self.Config.MinPlayer then return end
    
    local client = Player:GetClient()
    if not Shine:IsValidClient(client) or Shine:HasAccess(client, "sh_ignorestatus" ) then return end
    
    local steamid = client:GetUserId()
    if not steamid or steamid <= 0 then return end
    
    if self:TimerExists(StringFormat("Wait_%s", steamid)) then self:Notify(Player, self.Config.WaitMessage) return false end
        
    local playtime = SteamTime[steamid] or PlayTime[steamid]
    if playtime >= 0 and playtime < self.Config.MinPlaytime * 3600 then
        self:Notify(Player, self.Config.BlockMessage)
        if self.Config.ShowSwitchAtBlock then
           self:SendNetworkMessage(client, "ShowSwitch", {}, true )
        end
        self:Kick(Player)
        return false
    end
end

function Plugin:Notify( Player, Message )
    Shine:NotifyDualColour( Player, 100, 255, 100, "[No Rookies]", 255, 255, 255, Message)
end

function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )    
    if not Enabled or ShineForce or not self.Config.BlockTeams or #Shine.GetAllPlayers() < self.Config.MinPlayer or NewTeam == kTeamReadyRoom then return end    
    
    local client = Player:GetClient()
    if not Shine:IsValidClient(client) or Shine:HasAccess(client, "sh_ignorestatus" ) then return end
    
    local steamid = client:GetUserId()
    if not steamid or steamid <= 0 then return end
    
    if self.Config.AllowSpectating and NewTeam == kSpectatorIndex then
        self:DestroyTimer("Kick_" .. tostring(steamid))
        return 
    end
    
    if self:TimerExists(StringFormat("Wait_%s",steamid)) then self:Notify(Player, self.Config.WaitMessage) return false end
    
    local playtime = SteamTime[steamid] or PlayTime[steamid]
    if playtime >= 0 and playtime < self.Config.MinPlaytime * 3600 then
        self:Notify(Player, self.Config.BlockMessage)
        if self.Config.ShowSwitchAtBlock then
           self:SendNetworkMessage(client, "ShowSwitch", {}, true )
        end
        self:Kick(Player)
        return false 
    end    
end    

local Kicktimes = {}

function Plugin:Kick(player)
    if not self.Config.Kick then return end
    
    local client = player:GetClient()
    if not Shine:IsValidClient(client) then return end
    
    local steamid = client:GetUserId() or 0
    if steamid <= 0 then return end
    
    if self:TimerExists("Kick_" .. tostring(steamid)) then return end
    self:Notify(player, StringFormat(self.Config.KickMessage, self.Config.Kicktime/60))
    Kicktimes[steamid] = self.Config.Kicktime
    self:CreateTimer("Kick_" .. tostring(steamid), 1, self.Config.Kicktime, function()
        if not Shine:IsValidClient( client ) then
            Plugin:DestroyTimer("Kick_" .. tostring(steamid))
            return
        end
        local player = client:GetControllingPlayer()
        
        Kicktimes[steamid] = Kicktimes[steamid]-1
        if Kicktimes[steamid] == 10 then self:Notify(player, StringFormat(self.Config.KickMessage, Kicktimes[steamid])) end
        if Kicktimes[steamid] <= 5 then self:Notify(player, StringFormat(self.Config.KickMessage, Kicktimes[steamid])) end        
        if Kicktimes[steamid] <= 0 then
            Shine:Print( "Client %s[%s] (%s h) was kicked by No Rookies. Kicking...", true, player:GetName(), steamid,(SteamTime[steamid] or PlayTime[steamid])/3600)
            client.DisconnectReason = "You didn't fit to the set min playtime"
            Server.DisconnectClient( client )
        end    
    end)    
end

function Plugin:ClientDisconnect(Client)
    local steamid = Client:GetUserId()
    if not steamid or steamid <= 0 then return end
    
    self:DestroyTimer("Kick_" .. tostring(steamid))
end