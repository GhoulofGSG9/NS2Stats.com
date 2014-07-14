Script.Load( "lua/shine/core/server/playerinfohub.lua" )

local Plugin = Plugin
local Shine = Shine
local GetAllPlayers = Shine.GetAllPlayers

local Gamerules
local Teams = {
	{
		Players = {},
		TeamNumber = 1,
		Wins = 0
	},
	{
		Players = {},
		TeamNumber = 2,
		Wins = 0
	}
}

local HiveData = {}

Plugin.Conflicts = {
    DisableThem = {
        "tournamentmode",
		"pregame",
		"readyroom",
    },
    --Which plugins should force us to be disabled if they're enabled and we are?
    DisableUs = {
    }
}

Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "CaptainMode.json"
Plugin.DefaultConfig = {
	MinPlayers = 12,
	MaxVoteTime = 4,
	MinVotesToPass = 0.8,
	MaxWaitForCaptains = 4,
	BlockGameStart = false,
	AllowPregameJoin = true,
	Cache = {}
}
Plugin.CheckConfig = true

function Plugin:Initialise()
	self.Enabled = true
	self:CreateCommands()
	self.Vote = {
		Votes = {},
		Voted = {}
	}
	self.Cache = false
	self:CheckStart()
	return true
end

function Plugin:ResetVote()
	self.Vote.Started = false
	self.Vote.Votes = {}
	self.Vote.Voted = {}
	self.Vote.Team = nil
end

function Plugin:CheckStart()	
	if self.Config.Cache.Teams then
		self.Cache = true
		Teams = self.Config.Cache.Teams
		self.Config.Cache = {}
		self:SaveConfig( true )
		self:CreateTimer( "CaptainWait", 1, self.Config.MaxWaitForCaptains, function() self:Reset() end )	
	elseif Shine.GetHumanPlayerCount() > self.Config.MinPlayers and self.dt.State == 0 and not self:TimerExists( "CaptainWait" ) then
		self:StartVote()
	end
end

function Plugin:Reset()
	self:Notify( nil, "The Teams have been reset, restarting Mode ..." )
	Teams = {
		{
			Players = {},
			TeamNumber = 1,
			Wins = 0
		},
		{
			Players = {},
			TeamNumber = 2,
			Wins = 0
		}
	}
	self.Config.Cache = {}
	self:SaveConfig( true )
	
	self.dt.State = 0
	self:CheckStart()
end

function Plugin:StartVote( Team )
	self:ResetVote()
	if self.dt.State == 0 then
		local Players = GetAllPlayers()
		if Gamerules then 
			for i = 1, #Players do
				local Player = Players[ i ]
				Gamerules:JoinTeam( Player, 0, nil, true )
				local Client = Player:GetClient()
			end	
			Gamerules:ResetGame()
		end
		self.dt.State = 1
	end
	self.Vote.Started = true
	
	if Team then
		self.Vote.Team = Team
	end
	
	self:SendNetworkMessage( nil, "VoteState", { team = Team or 0, start = true }, true )
	self:CreateTimer( "CaptainVote", self.Config.MaxVoteTime * 60, 1,  function() self:EndVote() end)
end

function Plugin:AddVote( ClientId, TargetId)
	
	local TargetClient = Shine.GetClientByNS2ID( TargetId )
	if not TargetClient then return end
	local Target = TargetClient:GetControllingPlayer()
	
	local PlayerCount = Shine.GetHumanPlayerCount()
	
	if self.Vote.Team then
		local TeamNumber = self.Vote.Team
		
		if not ( Teams[ TeamNumber ].Players[ ClientId ] and Teams[ TeamNumber ].Players[ TargetId ] ) then return end
		
		PlayerCount = #Shine.GetTeamClients( Teams[ TeamNumber ].TeamNumber )
	end
	
	local oldVote = self.Vote.Voted[ ClientId ]
	if oldVote then
		self.Vote.Votes[ oldVote ] = self.Vote.Votes[oldVote] - 1
	end
	
	self.Vote.Votes[ TargetId ] = self.Vote.Votes[ TargetId ] or 0 + 1
	self.Vote.Voted[ ClientId ] = TargetId
	
	self:SendPlayerData( nil, Target )
	
	if GetTableSize( self.Vote.Voted ) >= PlayerCount * self.Config.MinVotesToPass then
		self:EndVote()
	end
end

local function spairs( t, order )
    -- collect the keys
    local keys = {}
    for k in pairs( t ) do keys[ #keys + 1 ] = k end

    -- if order function given, sort by it by passing the table and keys a, b,
    -- otherwise just sort the keys 
    if order then
        table.sort( keys, function(a,b) return order( t, a, b ) end )
    else
        table.sort( keys )
    end

    -- return the iterator function
    local i = 0
    return function()
        i = i + 1
        if keys[ i ] then
            return keys[ i ], t[ keys[ i ] ]
        end
    end
end

function Plugin:EndVote()
	self.Vote.Started = false
	self:DestroyTimer( "CaptainVote" )
	self:SendNetworkMessage( nil, "VoteState", { team = self.Vote.Team or 0, start = false }, true )
	
	local Winner = {}
	for k in spairs( self.Vote.Votes, function(t, a, b) return t[ b ] < t[ a ] end ) do
		Winner[ #Winner + 1 ] = k
	end
	
	if self.Vote.Team then 
		self:SetCaptain( Winner[ 1 ], self.Vote.Team )
	else
		self:SetCaptain( Winner[ 1 ], 1 )
		--self:SetCaptain( Winner[ 2 ], 2 )
	end
end

local CaptainsNum = 0
function Plugin:SetCaptain( SteamId, TeamNumber )
	--inform about new Captain
	--Todo not enought votes?
	if not SteamId then return end
	
	self:RemoveCaptain( TeamNumber )
	Teams[ TeamNumber ].Captain = SteamId
	Teams[ TeamNumber ].Players[ SteamId ] = true
	local Client = Shine.GetClientByNS2ID( SteamId )
	local Player = Client:GetControllingPlayer()
	Gamerules:JoinTeam( Player, Teams[ TeamNumber ].TeamNumber, nil, true )
	self:SendNetworkMessage( nil, "SetCaptain", { steamid = SteamId, team = TeamNumber, add = true }, true )
	CaptainsNum = CaptainsNum + 1
	if CaptainsNum == 2 and self.dt.State < 2 then
		self:DestroyTimer( "CaptainWait" )
		self.dt.State = 2
		local Clients = Shine.GetAllClients()
		for i = 1, #Clients do
			local Client = Clients[ i ]
			local SteamId = Client:GetUserId()
			local Team
			if Teams[ 1 ].Players[ SteamId ] then
				Team = 1
			elseif Teams[ 2 ].Players[ SteamId ] then
				Team = 2
			end
			
			if Team then
				local Player = Client:GetControllingPlayer()
				Gamerules:JoinTeam( Player, Teams[ Team ].TeamNumber, nil, true )
			end
		end
	end
end

function Plugin:RemoveCaptain( TeamNumber )
	local SteamId = Teams[TeamNumber].Captain
	if not SteamId then return end
	
	Teams[ TeamNumber ].Player[ SteamId ] = false
	Client = Shine.GetClientByNS2ID( SteamId )
	Player = Client:GetControllingPlayer()
	Gamerules:JoinTeam( Player, 0, nil, true )
	self:SendNetworkMessage( nil, "SetCaptain", { steamid = SteamId, team = TeamNumber, add = false }, true )
	CaptainsNum = CaptainsNum - 1
	
	if CaptainsNum == 0 then
		self:ResetVote()
		TeamNumber = nil
	end
	
	if self.dt.State > 0 and not self.Vote.Started then 
		self:StartVote( TeamNumber )
	end
end

function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )
	if ShineForce or self.Config.AllowPregameJoin and self.dt.State == 0 then return end
	
	return false
end

function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force, ShineForce )
	self:SendPlayerData( nil, Player )
	
	if self.dt.State > 0 then
		if OldTeam == 1 or OldTeam == 2 then
			self:Notify( nil, "%s left Team %s", true, Player:GetName(), Teams[ 1 ].TeamNumber == OldTeam and "1" or "2" )
		end
		if NewTeam == 1 or NewTeam == 2 then
			self:Notify( nil, "%s joined Team %s", true, Player:GetName(), Teams[ 1 ].TeamNumber == OldTeam and "1" or "2" )
		end
	end
end

function Plugin:OnReceiveHiveData( Client, HiveInfo )
	local SteamId = Client:GetUserId()
	local Player = Client:GetControllingPlayer()
	
	HiveData[ SteamId ] = HiveInfo
	self:SendPlayerData( nil, Player )
end

function Plugin:SendPlayerData( Client, Player, Disconnect )
	local steamId = Player:GetSteamId()

	
	local TeamNumber = 0
	for i = 1, 2 do
		if Teams[ i ].Players[ steamId ] then TeamNumber = i end
	end
	if Disconnect then TeamNumber = 3 end
	
	local PlayerData =
	{
		steamid = steamId,
		name = Player:GetName(),
		kills = 0,
		deaths = 0,
		playtime = 0,
		score = 0,
		skill = 0,
		win = 0,
		loses = 0,
		votes = self.Vote.Votes[ steamId ] or 0,
		team = TeamNumber
	}
	
	local HiveInfo = HiveData[ steamId ]
	if HiveInfo then
		PlayerData.skill = tonumber( HiveInfo.skill ) or 0
		PlayerData.kills = tonumber( HiveInfo.kills ) or 0
		PlayerData.deaths = tonumber( HiveInfo.deaths ) or 0
		PlayerData.playtime = tonumber( HiveInfo.playTime ) or 0
		PlayerData.score = tonumber( HiveInfo.score ) or 0
		PlayerData.wins = tonumber( HiveInfo.wins ) or 0
		PlayerData.loses = tonumber( HiveInfo.loses ) or 0
	end
	
	self:SendNetworkMessage( Client, "PlayerData", PlayerData, true )
end

function Plugin:ClientConfirmConnect( Client )
	if not Gamerules then 
		Gamerules = GetGamerules()
	end
	
	--inform about connect
	local Player = Client:GetControllingPlayer()
	local SteamId = Client:GetUserId()
	
	self:SendPlayerData( nil, Player )
	
	self:SimpleTimer( 1, function()
		local Players = GetAllPlayers()
		for i = 1, #Players do
			local Player = Players[ i ]
			if Player then self:SendPlayerData( Client, Player ) end
		end
	end)
	
	if self.Vote.Started then
		self:SendNetworkMessage( Client, "VoteState", { team = self.Vote.Team or 0, start = false }, true )
	end
	
	local CaptainTeam = self:GetCaptainTeamNumbers( SteamId )
	if CaptainTeam then
		self:SetCaptain( SteamId, CaptainTeam)
	elseif self.dt.State == 0 then
		self:CheckStart()
	elseif self.dt.State == 2 then 
		for i = 1, 2 do
			Teams[ i ].Players[ SteamId ] = nil
		end
	end
	
	if self.dt.State ~= 3 then return end
	
	-- check team balance
	local Marines = Gamerules:GetTeam1()
	local Aliens = Gamerules:GetTeam2()
	
	local MarinesNumPlayers = Marines:GetNumPlayers()
	local AliensNumPlayers = Aliens:GetNumPlayers()
	
	local PlayingTeamNumber
	local TeamNumber
	for i = 1, 2 do
		if Teams[ i ].Players[ SteamId ] then
			PlayingTeamNumber = Teams[ i ].TeamNumber
			TeamNumber = i
			break
		end
	end
	
	if MarinesNumPlayers == AliensNumPlayers then		
		if PlayingTeamNumber then
			Gamerules:JoinTeam( Player, PlayingTeamNumber, nil, true )
		else
			local Random = math.random( 1, 2 )
			
			Teams[ Random ].Players[ SteamId ] = true
		
			Gamerules:JoinTeam( Player, Teams[ Random ].TeamNumber, nil, true )
		end
	else
		if PlayingTeamNumber then
			Teams[ TeamNumber ].Players[ SteamId ] = nil
		end
		
		if MarinesNumPlayers < AliensNumPlayers then
			TeamNumber = Teams[ 1 ].TeamNumber == 1 and 1 or 2
		else
			TeamNumber = Teams[ 1 ].TeamNumber == 2 and 1 or 2
		end
		
		Teams[ TeamNumber ].Players[ SteamId ] = true
		Gamerules:JoinTeam( Player, Teams[ TeamNumber ].TeamNumber, nil, true )
	end
end

function Plugin:MapChange()
	self.Config.Cache.Teams = Teams
	self:SaveConfig( true )
end

function Plugin:ClientDisconnect( Client )
	local Player = Client:GetControllingPlayer()
	self:SendPlayerData( nil, Player, true )
	
	local SteamId = Client:GetUserId()
	local TeamNumber
	for i = 1, 2 do
		if Teams[ i ].Players[ SteamId ] then
			TeamNumber = i
		end
	end
	
	if TeamNumber then
		self:Notify( nil, "%s left Team %s", true, Player:GetName(), TeamNumber )
		if Teams[ TeamNumber ].Captain == SteamId then
			self:Notify( nil, "Also Team %s is now without a Captain. Starting a vote for a new Captain ...", true, TeamNumber, TeamNumber )
			self:StartVote( TeamNumber )
		end
	end

	if not self.Vote.Started then return end
	
	if self.Vote.Voted[ SteamId ] then
		self.Vote.Votes[ self.Vote.Voted ] = self.Vote.Votes[ self.Vote.Voted ] - 1
	end
	self.Vote.Votes[ SteamId ] = nil
end

function Plugin:CheckGameStart( Gamerules )
	local State = Gamerules:GetGameState()

	if self.dt.State ~= 3 then
		self:CheckRdy( Gamerules )
		return false	
	end
end

function Plugin:CheckRdy( Gamerules )
	if Teams[ 1 ].Ready and Teams[ 2 ].Ready then
		self:StartGame( Gamerules )
	end
end

function Plugin:StartGame( Gamerules )
	Teams[ 1 ].Ready = nil
	Teams[ 2 ].Ready = nil
	
	Gamerules:ResetGame()
	Gamerules:SetGameState( kGameState.Countdown )
	Gamerules.countdownTime = kCountDownLength
	Gamerules.lastCountdownPlayed = nil

	local Players, Count = Shine.GetAllPlayers()

	for i = 1, Count do
		local Player = Players[ i ]

		if Player.ResetScores then
			Player:ResetScores()
		end
	end
	
	self.dt.State = 3
end

function Plugin:GetCaptainTeamNumbers( SteamId )
	for i = 1, 2 do
		local Team = Teams[ i ]
		if Team.Captain == SteamId then
			return i, Team.TeamNumber
		end
	end
end

function Plugin:EndGame()
	local temp = Teams[ 1 ].TeamNumber
	Teams[ 1 ].TeamNumber = Teams[ 2 ].TeamNumber
	Teams[ 2 ].TeamNumber = temp
	
	local AllCaptains = true
	for i = 1, 2 do
		local Client = Shine.GetClientByNS2ID( Teams[ i ].Captain )
		if not Client then
			AllCaptains = false
			break
		end
	end
	
	if AllCaptains then
		self.dt.State = 2
	else
		self:Reset()
	end
end

function Plugin:ChangeState( OldValue, NewValue )
	--Notify?
end

function Plugin:Notify( Player, Message, Format, ... )
	Shine:NotifyDualColour( Player, 100, 255, 100, "[Captains Mode]" , 255, 255, 255, Message, Format, ... )
end

function Plugin:CreateCommands()
	
	local function VoteCaptain( Client, Target )
		if not self.Vote.Started then return end
		
		local ClientId = Client:GetUserId()
		local TargetId = Target:GetUserId()
		local TargetPlayer = Target:GetControllingPlayer()
		
		if not TargetPlayer then return end
		
		self:AddVote( ClientId, TargetId )
	end
	local CommandVoteCaptain = self:BindCommand( "sh_votecaptain", "votecaptain", VoteCaptain, true )
	CommandVoteCaptain:AddParam{ Type = "client", NotSelf = false }
	
	-- addplayer
	local function AddPlayer( Client, Target )
		local SteamId = Client:GetUserId()
		
		local TeamNumber, CaptainTeam = self:GetCaptainTeamNumbers( SteamId )
		if not TeamNumber then return end
		
		local Team = CaptainTeam == 1 and Gamerules:GetTeam1() or Gamerules:GetTeam2()
		local OtherTeam = CaptainTeam == 2 and Gamerules:GetTeam1() or Gamerules:GetTeam2()
		
		if Team:GetNumPlayers() > OtherTeam:GetNumPlayers() then return end
		
		local TargetPlayer = Client:GetControllingPlayer()
		if not TargetPlayer then return end
		
		Teams[ TeamNumber ].Players[ Target:GetUserId() ] = true
		
		Gamerules:JoinTeam( Player, CaptainTeam, nil, true )
	end
	local CommandAddPlayer = self:BindCommand( "sh_captain_addplayer", "captainaddplayer", AddPlayer, true )
	CommandAddPlayer:AddParam{ Type = "client" }
	
	-- removeplayer
	local function RemovePlayer( Client, Target )
		local SteamId = Client:GetUserId()
		local TargetId = Target:GetUserId()
		
		local TeamNumber, CaptainTeam = self:GetCaptainTeamNumbers( SteamId )
		if not TeamNumber then return end
		
		Teams[ TeamNumber ].Players[ TargetId ] = nil
		local TargetPlayer = Client:GetControllingPlayer()
		if not TargetPlayer or TargetPlayer:GetTeamNumber() ~= CaptainTeam then return end
		
		Gamerules:JoinTeam( Player, 0, nil, true )
	end
	local CommandRemovePlayer = self:BindCommand( "sh_captain_removeplayer", "captainremoveplayer", RemovePlayer, true )
	CommandRemovePlayer:AddParam{ Type = "client", NotSelf = true }
	
	-- removecaptain
	local function RemoveCaptain( Client, TeamNumber )
		self:RemoveCaptain( TeamNumber )
	end
	local CommandRemoveCaptain = self:BindCommand( "sh_removecaptain", "removecaptain", RemoveCaptain )
	CommandRemoveCaptain:AddParam{ Type = "number", Min = 1, Max = 2, Round = true, Error = "The team number has to be either 1 or 2" }
	
	-- setcaptain
	local function SetCaptain( Client, Target, TeamNumber )		
		local TargetId = Target:GetUserId()
		self:SetCaptain( TargetId, TeamNumber)
	end
	local CommandSetCaptain = self:BindCommand( "sh_setcaptain", "setcaptain", RemoveCaptain )
	CommandSetCaptain:AddParam{ Type = "client" }
	CommandSetCaptain:AddParam{ Type = "number", Min = 1, Max = 2, Round = true, Error = "The team number has to be either 1 or 2" }
	
	-- reset
	
	-- rdy
	local function Ready( Client )
		if self.dt.State ~= 2 then return end 
		local SteamId = Client:GetUserId()
		local TeamNumber = self:GetCaptainTeamNumbers( SteamId )
		if not TeamNumber then return end
		Teams[ TeamNumber ].Ready = not Teams[ TeamNumber ].Ready
		--inform
	end
	local CommandReady = self:BindCommand("sh_ready", { "rdy", "ready" }, Ready, true )
	
	local function OpenMenu( Client )
		if self.dt.State == 0 then return end
		self:SendNetworkMessage( Client, "CaptainMenu", {}, true)
	end
	self:BindCommand("sh_captainmenu", "captainmenu", OpenMenu, true)
	
	local function ChangeState( Client, State )
		if State == 1 then
				self:StartVote()
		else
			self.dt.State = State
		end
	end
	local ChangeStateCommand = self:BindCommand("sh_captainstate", "captainstate", ChangeState)
	ChangeStateCommand:AddParam{ Type = "number", Min = 1, Max = 5 }
end