--[[
    Shine No Rookies - Server
]]
local Shine = Shine
local InfoHub = Shine.PlayerInfoHub
local Plugin = Plugin

local Notify = Shared.Message
local StringFormat = string.format

Plugin.Version = "1.5"
Plugin.HasConfig = true

Plugin.ConfigName = "norookies.json"
Plugin.DefaultConfig =
{
    UseSteamTime = true,
    ForceSteamTime = false,
    MinPlayer = 0,
    DisableAfterRoundtime = 0,
    MinPlaytime = 8,
    MinComPlaytime = 8,
    ShowInform = true,
    InformMessage = "This server is not rookie friendly",
    BlockTeams = true,
    ShowSwitchAtBlock = false,
    BlockCC = true,
    AllowSpectating = false,
    BlockMessage = "This server is not rookie friendly",
    Kick = true,
    Kicktime = 20,
    KickMessage = "You will be kicked in %s seconds",
    WaitMessage = "Please wait while your data is retrieved",
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.Name = "No Rookies"
Plugin.DisconnectReason = "You didn't fit to the required playtime"
local Enabled = true

function Plugin:Initialise()
	self.Enabled = true
	return true
end

function Plugin:SetGameState( _, NewState )
    if NewState == kGameState.Started and self.Config.DisableAfterRoundtime and self.Config.DisableAfterRoundtime > 0 then        
        self:CreateTimer( "Disable", self.Config.DisableAfterRoundtime * 60 , 1, function() Enabled = false end )
    end
end

function Plugin:EndGame()
    self:DestroyTimer( "Disable" )
    Enabled = true
end

function Plugin:OnReceiveSteamData( Client )
	local SteamId = Client:GetUserId()
	if not InfoHub:GetIsRequestFinished( SteamId ) then return end
	
	local Player = Client:GetControllingPlayer()
	self:Check( Player )
end

function Plugin:OnReceiveHiveData( Client )
	local SteamId = Client:GetUserId()
	if not InfoHub:GetIsRequestFinished( SteamId ) then return end
	
	local Player = Client:GetControllingPlayer()
	self:Check( Player )
end

function Plugin:OnReceiveNs2StatsData( Client )
	local SteamId = Client:GetUserId()
	if not InfoHub:GetIsRequestFinished( SteamId ) then return end
	
	local Player = Client:GetControllingPlayer()
	self:Check( Player )
end

--noinspection UnusedDef
function Plugin:CheckCommLogin( CommandStation, Player )
    if not self.Config.BlockCC or not Player or not Player.GetClient or Shine.GetHumanPlayerCount() < self.Config.MinPlayer then return end

    return self:Check( Player, true )
end

function Plugin:Check( Player, ComCheck )
	if not ComCheck and not self.Config.BlockTeams or not Enabled then return end
	
    local Client = Player:GetClient()
    if not Shine:IsValidClient( Client ) or Shine:HasAccess( Client, "sh_ignorestatus" ) then return end
    
    local SteamId = Client:GetUserId()
    if not SteamId or SteamId <= 0 then return end
    
    if not InfoHub:GetIsRequestFinished( SteamId ) then self:Notify( Player, self.Config.WaitMessage ) return false end
    
    local PlayTime
    
    local SteamData = InfoHub:GetSteamData( SteamId )    
    if self.Config.UseSteamTime or self.Config.ForceSteamTime then
        PlayTime = SteamData.PlayTime
    end
    
    if not self.Config.ForceSteamTime then
		local HiveData = InfoHub:GetHiveData( SteamId )    
		if type( HiveData ) == "table" and HiveData.playTime and ( not PlayTime or HiveData.playTime > PlayTime ) then
			PlayTime = tonumber( HiveData.playTime )
		end

		local Ns2StatsData = InfoHub:GetNs2StatsData( SteamId )
		if type( Ns2StatsData ) == "table" and Ns2StatsData.time_played and ( not PlayTime or tonumber( Ns2StatsData.time_played ) > PlayTime ) then
			PlayTime = tonumber( Ns2StatsData.time_played )
		end
    end
    
    if not PlayTime or PlayTime < 0 then return end
    
    local CheckTime = self.Config.MinPlaytime
    
    if ComCheck then CheckTime = self.Config.MinComPlaytime end
    
    if PlayTime < CheckTime * 3600 then
        self:Notify( Player, self.Config.BlockMessage )
		Notify( StringFormat("[No Rookies]: %s failed the check with %s hours", Shine.GetClientInfo( Client ), PlayTime / 3600 ))
        if self.Config.ShowSwitchAtBlock then
           self:SendNetworkMessage( Client, "ShowSwitch", {}, true )
        end
        self:Kick( Player )
        return false
    end
end