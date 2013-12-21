--[[
    Shine No Rookies
]]

local Shine = Shine

local Plugin = {}

local Notify = Shared.Message
local StringFormat = string.format

Plugin.Version = "1.0"
Plugin.DefaultState = false

Plugin.HasConfig = true

Plugin.ConfigName = "norookies.json"
Plugin.DefaultConfig =
{
    MinPlayer = 0,
    DisableAfterRoundtime = 0,
    MinPlaytime = 8,
    BlockTeams = true,
    BlockCC = true,
    BlockMessage = "This Server is not rookie friendly",
    Kick = true,
    Kicktime = 60,
    KickMessage = "You will be kicked in %s min",
}

Plugin.CheckConfig = true

local Enabled = true

Shine.Hook.SetupClassHook( "CommandStructure", "LoginPlayer", "CheckComLogin","Halt")

function Plugin:SetGameState( Gamerules, NewState, OldState )
    if NewState == kGameState.Started and self.Config.DisableAfterRoundtime > 0 then        
        self:CreateTimer("Disable",self.Config.DisableAfterRoundtime * 60 ,1,function() Enabled = false end)
    end
end

function Plugin:EndGame( Gamerules, WinningTeam )
    self:DestroyTimer("Disable")
    Enabled = true
end
    
function  Plugin:CheckComLogin( Chair, Player )
    local Players = Shared.GetEntitiesWithClassname( "Player" ):GetSize()
    if not Enabled or not self.Config.BlockCC or not Player or not Player.GetClient or Players < self.Config.MinPlayer then return end
    
    local steamid = Player:GetClient():GetUserId()
    if not steamid or steamid <= 0 then return end
    
    local pData = GetPlayerHiveData(steamid)
    if pData and pData.playTime < self.Config.MinPlaytime then
        self:Notify(Player, self.Config.BlockMessage)
        self:Kick(Player)
        return false 
    end
end

function Plugin:Notify( Player, Message )
    Shine:NotifyDualColour( Player, 100, 255, 100, "[No Rookies]", 255, 255, 255, Message)
end

function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )    
    local Players = Shared.GetEntitiesWithClassname( "Player" ):GetSize()
    if not Enabled or Players < self.Config.MinPlayer then return end
    
    local client = Player:GetClient()
    if ShineForce or not Shine:IsValidClient(client) or Shine:HasAccess(client, "sh_ignorestatus" ) then return end
    
    local steamid = client:GetUserId()
    if not steamid or steamid <= 0 then return end
    
    local pData = GetPlayerHiveData(steamid)
    local playtime = pData and pData.playTime or 0
    
    if self.Config.BlockTeams and playtime < self.Config.MinPlaytime then
        self:Notify(Player, self.Config.BlockMessage)
        self:Kick(Player)
        return false 
    end
    
end    

function Plugin:Kick(player)
    if not self.Config.Kick then return end
    
    local client = player:GetClient()
    if not Shine:IsValidClient(client) then return end
    
    local steamid = client:GetUserId() or 0
    if steamid<= 0 then return end
    
    self:DestroyTimer("Player_" .. tostring(steamid))
    self:Notify(player, StringFormat(self.Config.KickMessage, self.Config.Kicktime/60))
    Kicktimes[steamid] = self.Config.Kicktime
    self:CreateTimer("Player_" .. tostring(steamid),1, self.Config.Kicktime, function()        
        Kicktimes[steamid] = Kicktimes[steamid]-1
        if Kicktimes[steamid] == 10 then self:Notify(player, StringFormat(self.Config.KickMessage, Kicktimes[steamid])) end
        if Kicktimes[steamid] <= 5 then self:Notify(player, StringFormat(self.Config.KickMessage, Kicktimes[steamid])) end        
        if Kicktimes[steamid] <= 0 then
            Shine:Print( "Client %s[%s] was kicked by No Rookies. Kicking...", true, player:GetName(), steamid)
            client.DisconnectReason = "You didn't fit to the set min playtime"
            Server.DisconnectClient( client )
        end    
    end)    
end

function Plugin:ClientDisconnect(Client)
    local steamid = Client:GetUserId()
    if not steamid or steamid <= 0 then return end
    
    self:DestroyTimer("Player_" .. tostring(steamid))
end

Shine:RegisterExtension( "norookies", Plugin )