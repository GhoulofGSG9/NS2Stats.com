local Plugin = Plugin

local Shine = Shine
local GetAllPlayers = Shine.GetAllPlayers
local GetAllClients = Shine.GetAllClients
local StringFormat = string.format
local ToNumber = tonumber
local TableInsert = table.insert
local TableRemove = table.remove
local Random = math.random
local GetClientByNS2ID = Shine.GetClientByNS2ID
local SetupClassHook = Shine.Hook.SetupClassHook
local GetOwner = Server.GetOwner

if not Shine.PlayerInfoHub then 
	Script.Load( "lua/shine/core/server/playerinfohub.lua" )
end

--Vote Class
Script.Load( "lua/shine/extensions/captains/vote.lua" )

local PlayerInfoHub = Shine.PlayerInfoHub

local HiveData = {}
local Gamerules

Plugin.Conflicts = {
    DisableThem = {
        "tournamentmode",
		"pregame",
		"readyroom",
    },
    DisableUs = {}
}

Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "CaptainMode.json"
Plugin.DefaultConfig = {
	MinPlayers = 12,
	MaxVoteTime = 1,
	MinVotesToPass = 0.8,
	MaxWaitForCaptains = 4,
	BlockGameStart = false,
	AllowPregameJoin = true,
	StateMessageFirst = "Captain Mode enabled",
	StateMessages =
	{
		"Waiting for %s Players to join the Server before starting a Vote for Captains",
		"Vote for Captains is currently running",
		"Waiting for Captains to set up the teams.\nThe round will start once both teams are ready and have a Commander!",
		"Currently a round has been started.\nPlease wait for a Captain to pick you up."
	},
	StateMessageLast = "",
	VoteTimeMessage = "The current vote will end in %s minutes\nPress %s to access the Captain Mode Menu.\nOr type !captainmenu into the chat.",
	StateMessagePosX = 0.05,
	StateMessagePosY = 0.55,
	StateMessageColour = { 51, 153, 0 },
	VoteforCaptains = true,
	AllowSpectating = true,
	CountdownTime = 15	
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.CountdownTimer = "Countdown"
Plugin.FiveSecondTimer = "5SecondCount"

local function OnSucess( self, Winners )
	local Team = 0
	if self.Team > 0 then
		Team = self.Team == Plugin.Teams[ 1 ].TeamNumber and 1 or 2
	end
	
	for _, Winner in ipairs( Winners ) do
		local Client = GetClientByNS2ID( Winner.Name )
		if not Client then
			self:RemoveOption( Winner.Name )
			
			local Winners = self:GetWinners( self.WinnersNeeded )

			if Winners and #Winners == self.WinnersNeeded then
				self.Winners = Winners
				OnSucess( self, Winners )
			else
				OnFailure( self )
			end
			
			return
		end
	end
	
	Plugin:SendNetworkMessage( nil, "VoteState", { team = Team, start = false, timeleft = 0 }, true )
	
	if Team > 0 then
		Plugin:SetCaptain( Winners[ 1 ].Name, Team )
	else
		Plugin:SetCaptain( Winners[ 1 ].Name, 1 )
		Plugin:SetCaptain( Winners[ 2 ].Name, 2 )
	end
end

local function OnFailure( self )
	local Team = 0
	if self.Team > 0 then
		Team = self.Team == Plugin.Teams[ 1 ].TeamNumber and 1 or 2
	end
	
	Plugin:SendNetworkMessage( nil, "VoteState", { team = Team, start = false, timeleft = 0 }, true )
	Plugin:Notify( nil, "CaptainVote%s failed because not enough players voted or we did not got enough Captain candidates! Restarting Vote...", true, self.Team == 1 and " for Team 1" or self.Team == 2 and " for Team 2" or "")
	
	self:Start()
	Plugin:SendNetworkMessage( nil, "VoteState", { team = Team, start = true, timeleft = self:GetTimeLeft() }, true )
end

local function CreateVote( Team )
	local Vote = Vote()
	local WinnerNum = Team > 0 and 1 or 2
	local Name = StringFormat( "Vote%s", Team )
	Vote:Setup( Name, {}, Plugin.Config.MaxVoteTime * 60, OnSucess, OnFailure, WinnerNum, Team )
	return Vote
end

function Plugin:Initialise()
	self.Votes = { 
		[ 0 ] = CreateVote( 0 ),
		[ 1 ] = CreateVote( 1 ), 
		[ 2 ] = CreateVote( 2 ) 
	}
	
	self.Connected = {}
	self.dt.State = 0
	
	self:ResetTeams()
	
	self.Enabled = true
	
	self:CreateCommands()
	
	local Clients = GetAllClients()
	
	--check if there are already players at the server
	if #Clients > 0 then
		for i = 1, #Clients do
			local Client = Clients[ i ]
			local ClientId = Client:GetUserId()
			local HiveInfo = PlayerInfoHub:GetHiveData( ClientId )
			
			if HiveInfo then
				HiveData[ ClientId ] = HiveInfo
			end
			
			self:ClientConfirmConnect( Client )
		end
	else
		self:CheckModeStart()
	end
	
	SetupClassHook( "Player", "SetName", "OnPlayerRename", "PassivePost" )
	
	return true
end

function Plugin:CheckModeStart()
	if Shine.GetHumanPlayerCount() >= self.Config.MinPlayers and self.dt.State == 0 then
		local Players = GetAllPlayers()
		if Gamerules then 
			for i = 1, #Players do
				local Player = Players[ i ]
				if Player and Player:GetClient() then
					Gamerules:JoinTeam( Player, 0, nil, true )
				end
			end	
			Gamerules:ResetGame()
		end
		self.dt.State = 1
		self:StartVote()
	end
end

function Plugin:Think()
	for i = 0, 2 do
		self.Votes[ i ]:OnUpdate()
	end
end

function Plugin:ResetTeams()

	if self.Teams then
		self:RemoveCaptain( 1 )
		self:RemoveCaptain( 2 )
	end

	self.Teams = {
		{
			Name = "Team 1",
			Players = {},
			TeamNumber = 1,
			Wins = 0
		},
		{
			Name = "Team 2",
			Players = {},
			TeamNumber = 2,
			Wins = 0
		}
	}
	
	self:SendTeamInfo( 1 )
	self:SendTeamInfo( 2 )
end

function Plugin:SendTeamInfo( TeamNumber )
	local Team = self.Teams[ TeamNumber ]
	if not Team then return end
	
	local Info = {
		name = Team.Name,
		wins = Team.Wins,
		number = TeamNumber,
		teamnumber = Team.TeamNumber
	}
	self:SendNetworkMessage( nil, "TeamInfo", Info, true )
end

function Plugin:Reset()
	self:Notify( nil, "The Teams have been reset, restarting Captain Mode ..." )
	self:ResetTeams()
	
	self:DestroyAllTimers()
	for i = 0, 2 do
		if self.Votes[ i ] then
			self.Votes[ i ]:Reset()
		end
	end
	
	self.dt.State = 0
	self:CheckModeStart()
end

function Plugin:StartVote( Team )
	if not self.Config.VoteforCaptains then return end
	
	Team = Team or 0
	
	local Vote = self.Votes[ Team ]
	Vote:Start()
	self:SendNetworkMessage( nil, "VoteState", { team = Team, start = true, timeleft = Vote:GetTimeLeft() }, true )
end

local CaptainsNum = 0
function Plugin:SetCaptain( SteamId, TeamNumber )
	if not SteamId then return end
	
	self:RemoveCaptain( TeamNumber, true )
	self.Teams[ TeamNumber ].Captain = SteamId
	self.Teams[ TeamNumber ].Players[ SteamId ] = true
	
	local Client = GetClientByNS2ID( SteamId )
	
	if not Client then return end
	local Player = Client:GetControllingPlayer()
	
	self:Notify( nil, "%s is now the Captain of Team %s", true, Player:GetName(), TeamNumber )
	
	Gamerules:JoinTeam( Player, self.Teams[ TeamNumber ].TeamNumber, nil, true )
	self:SendNetworkMessage( nil, "SetCaptain", { steamid = SteamId, team = TeamNumber, add = true }, true )
	
	CaptainsNum = CaptainsNum + 1
	if CaptainsNum == 2 and self.dt.State < 2 then
		self.dt.State = 2
	end
end

function Plugin:RemoveCaptain( TeamNumber, SetCall )
	local SteamId = self.Teams[ TeamNumber ].Captain
	if not SteamId or CaptainsNum == 0 then return end

	self.Teams[ TeamNumber ].Players[ SteamId ] = false
	self.Teams[ TeamNumber ].Captain = nil	

	local Client = GetClientByNS2ID( SteamId )
	local Player = Client:GetControllingPlayer()
	
	self:Notify( nil, "%s is now not any longer the Captain of Team %s", true, Player:GetName(), TeamNumber )
	if self.Teams[ TeamNumber ].Ready then
		self.Teams[ TeamNumber ].Ready = false
		self:Notify( nil, "And Team %s is now not any more ready!", true, TeamNumber )
	end
	
	self:SendNetworkMessage( nil, "SetCaptain", { steamid = SteamId, team = TeamNumber, add = false }, true )
	
	if Player:GetTeamNumber() ~= 0 then
		Gamerules:JoinTeam( Player, 0, nil, true )
	end
	
	CaptainsNum = CaptainsNum - 1
	
	if not SetCall and self.dt.State ~= 1 then
		if table.Count( self.Teams[ TeamNumber ].Players ) > 0 then
			self:StartVote( TeamNumber )
		else
			self:Notify( nil, "Oh no, Team %s is empty! We have to restart the captain mode.", true, TeamNumber )
			self:Reset()
		end
	end	
end

function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )
	if ShineForce or self.dt.State ~= 1 and self.Config.AllowSpectating and NewTeam == kSpectatorIndex or 
	self.Config.AllowPregameJoin and self.dt.State == 0 or Player:GetTeamNumber() == kSpectatorIndex and NewTeam == kTeamReadyRoom then return end
	
	return false
end

function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force, ShineForce )
	local Client = Player:GetClient()
	local SteamId = Client and Client:GetUserId()
	
	if self.dt.State > 0 then
		if OldTeam == 1 or OldTeam == 2 then
			local Team = self.Teams[ 1 ].TeamNumber == OldTeam and 1 or 2
			self.Teams[ Team ].Players[ SteamId ] = nil
			self:Notify( nil, "%s left %s", true, Player:GetName(), self:GetTeamName( OldTeam ) )
			if self.Teams[ Team ].Captain == SteamId then
				self:Notify( nil, "Also Team %s is now without a Captain. Starting a vote for a new Captain ...", true, Team )
				self:RemoveCaptain( Team )
			end
		end
		
		if NewTeam == 1 or NewTeam == 2 then
			local Team = self.Teams[ 1 ].TeamNumber == NewTeam and 1 or 2
			self.Teams[ Team ].Players[ SteamId ] = true
			self:Notify( nil, "%s joined %s", true, Player:GetName(), self:GetTeamName( NewTeam ))
		end
	end
	
	if self.Votes[ OldTeam ] then
		local Client = GetOwner( Player )
		local Vote = self.Votes[ OldTeam ]
		if Vote:GetIsStarted() then
			local OldVoteId = Vote:GetOptionName( Vote:GetVote( Client ) )
			if OldVoteId then
				Vote:RemoveVote( Client )
				local OldVoteClient = GetClientByNS2ID( OldVoteId )
				local OldVotePlayer = OldVoteClient:GetControllingPlayer()
				self:SendPlayerData( nil, OldVotePlayer )
			end
		end
		
		Vote:RemoveOption( SteamId ) 
	end
	
	if self.Votes[ NewTeam ] then
		local Vote = self.Votes[ NewTeam ]
		Vote:AddVoteOption( SteamId )
		
		if Vote:GetIsStarted() and self.Connected[ SteamId ] then
			self:SendNetworkMessage( Client, "VoteState", { team = NewTeam, start = true, timeleft = Vote:GetTimeLeft() }, true )
		end
	end
	
	self:SendPlayerData( nil, Player, NewTeam == 4 )
end

function Plugin:OnReceiveHiveData( Client, HiveInfo )
	local SteamId = Client:GetUserId()
	local Player = Client:GetControllingPlayer()
	
	HiveData[ SteamId ] = HiveInfo
	self:SendPlayerData( nil, Player )
end

function Plugin:SendPlayerData( Client, Player, Disconnect )
	local client = GetOwner( Player )
	local steamId = client:GetUserId()

	local TeamNumber = self:GetTeamNumber( steamId )
	if Disconnect or Player:GetTeamNumber() == kSpectatorIndex then TeamNumber = 3 end
	
	local Vote = self.Votes[ Player:GetTeamNumber() ]
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
		votes = Vote and Vote:GetIsStarted() and Vote:GetVotes( Vote:OptionToId( steamId ) ) or 0,
		team = TeamNumber
	}
	
	local HiveInfo = HiveData[ steamId ]
	if HiveInfo then
		PlayerData.skill = ToNumber( HiveInfo.skill ) or 0
		PlayerData.kills = ToNumber( HiveInfo.kills ) or 0
		PlayerData.deaths = ToNumber( HiveInfo.deaths ) or 0
		PlayerData.playtime = ToNumber( HiveInfo.playTime ) or 0
		PlayerData.score = ToNumber( HiveInfo.score ) or 0
		PlayerData.wins = ToNumber( HiveInfo.wins ) or 0
		PlayerData.loses = ToNumber( HiveInfo.loses ) or 0
	end
	
	self:SendNetworkMessage( Client, "PlayerData", PlayerData, true )
end

function Plugin:SendMessages( Client )
	for i = 1, 2 do
		local Info = {
			number = i,
			name = self.Teams[ i ].Name,
			wins = self.Teams[ i ].Wins,
			teamnumber = self.Teams[ i ].TeamNumber,
		}
		self:SendNetworkMessage( Client, "TeamInfo", Info, true )
	end
	
	local Config = {
		x = self.Config.StateMessagePosX,
		y = self.Config.StateMessagePosY,
		r = self.Config.StateMessageColour[ 1 ],
		g = self.Config.StateMessageColour[ 2 ],
		b = self.Config.StateMessageColour[ 3 ],
	}
	self:SendNetworkMessage( Client, "MessageConfig", Config, true )
	
	for i = 1 , 7 do 
		local Message = { id = i}
		if i == 1 then
			Message.text = self.Config.StateMessageFirst
		elseif i == 6 then
			Message.text = self.Config.StateMessageLast
		elseif i == 2 then
			Message.text = StringFormat( self.Config.StateMessages[ 1 ], self.Config.MinPlayers )
		elseif i == 7 then
			Message.text = self.Config.VoteTimeMessage
		else
			Message.text = self.Config.StateMessages[ i - 1 ] or ""
		end
		self:SendNetworkMessage( Client, "InfoMsgs", Message, true )
	end
end

function Plugin:ClientConfirmConnect( Client )
	if not Gamerules then 
		Gamerules = GetGamerules()
	end
	
	--inform about connect
	local Player = Client:GetControllingPlayer()
	local SteamId = Client:GetUserId()
	
	self:SendMessages( Client )
	
	self:SendPlayerData( nil, Player )
	
	self.Connected[ SteamId ] = true
	
	self:SimpleTimer( 1, function()
		for _, Player in ipairs( GetAllPlayers() ) do
			self:SendPlayerData( Client, Player )
		end
	end)
	
	local Vote = self.Votes[ 0 ]
	Vote:AddVoteOption( SteamId )	
	if Vote:GetIsStarted() then
		self:SendNetworkMessage( Client, "VoteState", { team = 0, start = true, timeleft = Vote:GetTimeLeft() }, true )
	end
	
	if self.dt.State == 0 then
		self:CheckModeStart()
	end
	
	if self.dt.State ~= 3 then return end
	
	-- check team balance
	local Marines = Gamerules:GetTeam1()
	local Aliens = Gamerules:GetTeam2()
	
	local MarinesNumPlayers = Marines:GetNumPlayers()
	local AliensNumPlayers = Aliens:GetNumPlayers()
	
	if MarinesNumPlayers == AliensNumPlayers then
		local Random = Random( 1, 2 )
	
		Gamerules:JoinTeam( Player, self.Teams[ Random ].TeamNumber, nil, true )
	else		
		if MarinesNumPlayers < AliensNumPlayers then
			TeamNumber = self.Teams[ 1 ].TeamNumber == 1 and 1 or 2
		else
			TeamNumber = self.Teams[ 1 ].TeamNumber == 2 and 1 or 2
		end
		
		Gamerules:JoinTeam( Player, self.Teams[ TeamNumber ].TeamNumber, nil, true )
	end
end

function Plugin:ClientDisconnect( Client )
	local Player = Client:GetControllingPlayer()
	if Player then
		self:PostJoinTeam( nil, Player, Player:GetTeamNumber(), 4 )
	end	
end

function Plugin:OnPlayerRename( Player, Name )
	local SteamId = Player:GetClient() and Player:GetSteamId()
	if Name == kDefaultPlayerName or not self.Connected[ SteamId ] then return end
	
	self:SendPlayerData( nil, Player )
end

function Plugin:CheckGameStart( Gamerules )
	if self.dt.State == 2 then
		self:CheckCommanders( Gamerules )
		return false
	end
end

function Plugin:CheckStart()
	--Both teams are ready, start the countdown.
	if self.Teams[ 1 ].Ready and self.Teams[ 2 ].Ready then
		local CountdownTime = self.Config.CountdownTime
		local GameStartTime = string.TimeToString( CountdownTime )
		Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7, StringFormat( "Game starts in %s", GameStartTime ), 5, 255, 255, 255, 1, 3, 1 ) )
		
		--Game starts in 5 seconds!
		self:CreateTimer( self.FiveSecondTimer, CountdownTime - 5, 1, function()
			Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7, "Game starts in %s", 5, 255, 0, 0, 1, 3, 0 ) )
		end )
		
		--If we get this far, then we can start.
		self:CreateTimer( self.CountdownTimer, self.Config.CountdownTime, 1, function()
			self:StartGame( GetGamerules() )
		end )
		
		return
	end
	
	--One or both teams are not ready, halt the countdown.
	if self:TimerExists( self.CountdownTimer ) then
		self:DestroyTimer( self.FiveSecondTimer )
		self:DestroyTimer( self.CountdownTimer )
		
		--Remove the countdown text.
		Shine:RemoveText( nil, { ID = 2 } )
		
		self:Notify( nil, "Game start aborted." )
	end
end

function Plugin:GetTeamName( TeamNumber )
	local Team = self.Teams[ TeamNumber ]
	if not Team then return end
	return Team.Name or Shine:GetTeamName( Team.TeamNumber, true )
end

function Plugin:CheckCommanders( Gamerules )
	local Team1 = Gamerules:GetTeam( self.Teams[ 1 ].TeamNumber )
	local Team2 = Gamerules:GetTeam( self.Teams[ 1 ].TeamNumber )
	
	local Team1Com = Team1 and Team1:GetCommander()
	local Team2Com = Team2 and Team2:GetCommander()
	
	local Team1Ready = self.Teams[ 1 ].Ready
	local Team2Ready = self.Teams[ 2 ].Ready
	
	if Team1Ready and not Team1Com then
		Team1Ready = false
		self:Notify( nil, "%s is no longer ready.", true, self:GetTeamName( 1 ) )
	end
	if Team2Ready and not Team2Com then
		Team2Ready = false
		self:Notify(nil, "%s is no longer ready.", true, self:GetTeamName( 2 ) )
	end
	
	self:CheckStart()
end

function Plugin:StartGame( Gamerules )
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
	
	self.Teams[ 1 ].Ready = false
	self.Teams[ 2 ].Ready = false
	self.dt.State = 3
end

function Plugin:EndGame( Gamerules, WinningTeam )
	if WinningTeam then
		local Winner = WinningTeam:GetTeamNumber()
		for i = 1, 2 do
			local Team = self.Teams[ i ]
			if Team.TeamNumber == Winner then
				Team.Wins = Team.Wins + 1
				self:SendTeamInfo( i )
				break
			end
		end
	end
	
	self.Teams[ 1 ].TeamNumber, self.Teams[ 2 ].TeamNumber = self.Teams[ 2 ].TeamNumber, self.Teams[ 1 ].TeamNumber
	
	local AllCaptains = true
	for i = 1, 2 do
		local Client = GetClientByNS2ID( self.Teams[ i ].Captain )
		if not Client then
			AllCaptains = false
			break
		end
	end
	
	if AllCaptains then
		self:RestoreTeams()
	else
		self:Reset()
	end
end

function Plugin:RestoreTeams()
	-- first put captains into teams
	local AllClients = GetAllClients()
	for i = 1, 2 do
		local Captain = self.Teams[ i ].Captain
		self:SetCaptain( Captain, i )
	end
	
	for i = 1, #AllClients do
		local Client = AllClients[ i ]
		local Player = Client:GetControllingPlayer()
		local SteamId = Client:GetUserId()
		local Team = self:GetTeamNumber( SteamId )
		local TeamNumber = Team and self.Teams[ Team ] and self.Teams[ Team ].TeamNumber or 0
		if Player then
			Gamerules:JoinTeam( Player, TeamNumber, nil, true )
		end
	end
	self.dt.State = 2
end

function Plugin:ReceiveOnResolutionChanged( Client )
	self:SendMessages( Client )
	
	for _, Player in ipairs( GetAllPlayers() ) do
		self:SendPlayerData( Client, Player )
	end
	
	local Timer = self.Timers[ "CaptainVote0" ]
	if Timer then
		self:SendNetworkMessage( Client, "VoteState", { team = 0, start = true, timeleft = math.Round( Timer:GetTimeUntilNextRun(), 0 ) }, true )
	end
	
	local SteamId = Client:GetUserId()
	local TeamNumber = self.GetCaptainTeamNumbers( SteamId )
	if self.GetCaptainTeamNumbers( SteamId ) then
		self:SendNetworkMessage( nil, "SetCaptain", { steamid = SteamId, team = TeamNumber, add = true }, true )
	end
end

function Plugin:ChangeState( OldValue, NewValue )
	--Notify?
end

function Plugin:Notify( Player, Message, Format, ... )
	Shine:NotifyDualColour( Player, 100, 255, 100, "[Captains Mode]" , 255, 255, 255, Message, Format, ... )
end

function Plugin:GetTeamNumber( ClientId )
	for i = 1, 2 do 
		if self.Teams[ i ].Players[ ClientId ] then
			return i
		end
	end
	return 0
end

function Plugin:GetCaptainTeamNumbers( SteamId )
	for i = 1, 2 do
		local Team = self.Teams[ i ]
		if Team.Captain == SteamId then
			return i, Team.TeamNumber
		end
	end
end

function Plugin:CreateCommands()
	
	local function VoteCaptain( Client, Target )
		local TargetId = Target:GetUserId()
		local TeamNumber = Client:GetControllingPlayer():GetTeamNumber()
		
		local Vote = self.Votes[ TeamNumber ]
		if Vote and Vote:GetIsStarted() then
			local OldVoteId = Vote:GetOptionName( Vote:GetVote( Client ) )
			local OldVoteClient = OldVoteId and GetClientByNS2ID( OldVoteId )
			if OldVoteId == TargetId then return end --revote
			
			Vote:AddVote( Client, Vote:OptionToId( TargetId ))
			
			if OldVoteClient then
				self:SendPlayerData( nil, OldVoteClient:GetControllingPlayer() )
			end
			
			self:SendPlayerData( nil, Target:GetControllingPlayer() )
		end
	end
	local CommandVoteCaptain = self:BindCommand( "sh_votecaptain", "votecaptain", VoteCaptain, true )
	CommandVoteCaptain:AddParam{ Type = "client", IgnoreCanTarget = true }
	CommandVoteCaptain:Help( "<player> Votes for the given player to become captain" )
	
	-- addplayer
	local function AddPlayer( Client, Target )
		local SteamId = Client:GetUserId()
		
		local TargetPlayer = Target:GetControllingPlayer()
		if not TargetPlayer then return end
		
		if TargetPlayer:GetTeamNumber() ~= 0 then
			self:Notify( Client:GetControllingPlayer(), "Please pick a player from the Ready Room" )
			return
		end
		
		local TeamNumber, CaptainTeam = self:GetCaptainTeamNumbers( SteamId )
		if not TeamNumber then return end
		
		local Team = CaptainTeam == 1 and Gamerules:GetTeam1() or Gamerules:GetTeam2()
		local OtherTeam = CaptainTeam == 2 and Gamerules:GetTeam1() or Gamerules:GetTeam2()
		
		if Team:GetNumPlayers() > OtherTeam:GetNumPlayers() then
			self:Notify( Client:GetControllingPlayer(), "Please wait until the other Captain has also picked the next player!")
			return 
		end
		
		Gamerules:JoinTeam( TargetPlayer, CaptainTeam, nil, true )
	end
	local CommandAddPlayer = self:BindCommand( "sh_captain_addplayer", "captainaddplayer", AddPlayer, true )
	CommandAddPlayer:AddParam{ Type = "client", NotSelf = true, IgnoreCanTarget = true }
	CommandAddPlayer:Help( "<player> Picks the given player for your team [this command is only available for captains]" )
	
	-- removeplayer
	local function RemovePlayer( Client, Target )
		local SteamId = Client:GetUserId()
		local TargetId = Target:GetUserId()
		
		local TeamNumber, CaptainTeam = self:GetCaptainTeamNumbers( SteamId )
		if not TeamNumber then return end
		
		local TargetPlayer = Client:GetControllingPlayer()
		if not TargetPlayer or TargetPlayer:GetTeamNumber() ~= CaptainTeam then
			self:Notify( Client:GetControllingPlayer(), "You can only remove Players from your own team" )
			return 
		end

		Gamerules:JoinTeam( TargetPlayer, 0, nil, true )
	end
	local CommandRemovePlayer = self:BindCommand( "sh_captain_removeplayer", "captainremoveplayer", RemovePlayer, true )
	CommandRemovePlayer:AddParam{ Type = "client", NotSelf = true, IgnoreCanTarget = true }
	CommandRemovePlayer:Help( "<player> Removes the given player from your team [this command is only available for captains]" )
	
	-- removecaptain
	local function RemoveCaptain( Client, TeamNumber1, TeamNumber2 )
		local TeamNumber = TeamNumber2
		if math.InRange( 1, TeamNumber1, 2 ) then
			TeamNumber = TeamNumber1
		end
		self:RemoveCaptain( TeamNumber )
	end
	
	local CommandRemoveCaptain = self:BindCommand( "sh_removecaptain", "removecaptain", RemoveCaptain )
	CommandRemoveCaptain:AddParam{ Type = "number", Round = true, IgnoreCanTarget = true }
	CommandRemoveCaptain:AddParam{ Type = "number", Min = 1, Max = 2, Round = true, Error = "The team number has to be either 1 or 2", Optimal = true, Default = 1 }
	CommandRemoveCaptain:Help( "<teamnumber> Removes the player of the given team" )
	
	-- setcaptain
	local function SetCaptain( Client, Target, TeamNumber )		
		local TargetId = Target:GetUserId()
		self:SetCaptain( TargetId, TeamNumber)
	end
	local CommandSetCaptain = self:BindCommand( "sh_setcaptain", "setcaptain", SetCaptain )
	CommandSetCaptain:AddParam{ Type = "client" }
	CommandSetCaptain:AddParam{ Type = "number", Min = 1, Max = 2, Round = true, Error = "The team number has to be either 1 or 2" }
	CommandSetCaptain:Help( "<player> <teamnumber> Makes the given player the captain of the given team." )
	
	-- reset
	local function ResetCaptain( Client )		
		self:Reset()
	end
	local CommandReset = self:BindCommand( "sh_resetcaptainmode", "resetcaptainmode",  ResetCaptain )
	CommandReset:Help( "Resets the Captain Mode. This will reset all teams." )
	
	-- rdy
	local function Ready( Client )
		if self.dt.State ~= 2 then return end 
		local SteamId = Client:GetUserId()
		local TeamNumber = self:GetCaptainTeamNumbers( SteamId )
		if not TeamNumber then return end
		
		local Commander = GetGamerules():GetTeam( TeamNumber ):GetCommander()
		local Ready = self.Teams[ TeamNumber ].Ready
		if not Commander and not Ready then
			self:Notify( Client:GetControllingPlayer(), "Your team needs to have a Commander before you can set it ready !")
			return
		end
		
		Ready = not Ready
		
		self:Notify( nil, "%s is now %s", true, self:GetTeamName( TeamNumber ), Ready and "ready" or "not ready" )
	end
	local CommandReady = self:BindCommand("sh_ready", { "rdy", "ready" }, Ready, true )
	CommandReady:Help( "Sets your team to be ready [this command is only available for captains]" )
	
	local function OpenMenu( Client )
		if self.dt.State == 0 or not self.Enabled then return end
		self:SendNetworkMessage( Client, "CaptainMenu", {}, true)
	end
	local CommandMenu = self:BindCommand("sh_captainmenu", "captainmenu", OpenMenu, true)
	CommandMenu:Help( "Opens the Capatain Mode Menu" )
	
	--teamnames
	local function SetTeamName( Client, TeamNumber, TeamName )
		if not Shine:HasAccess( Client, "sh_setteamname" ) and not self:GetCaptainTeamNumbers( Client:GetUserId() ) then
			return
		end

		local Team = self.Teams[ TeamNumber ]
		
		if Team then
			Team.Name = TeamName
			self:SendTeamInfo( TeamNumber )
		end
	end
	local CommandSetTeamName = self:BindCommand( "sh_setteamname", "setteamname", SetTeamName, true )
	CommandSetTeamName:AddParam{ Type = "number", Min = 1, Max = 2, Round = true, Error = "TeamNumber must be either 1 or 2 " }
	CommandSetTeamName:AddParam{ Type = "string", TakeRestOfLine = true  }
	CommandSetTeamName:Help( "<teamnumber> <name> Sets the given name as team name for the given team." )
	
	--debug
	local function ChangeState( Client, State )
		if State == 1 then
			self:StartVote()
		end
		self.dt.State = State
	end
	local ChangeStateCommand = self:BindCommand("sh_captainstate", "captainstate", ChangeState)
	ChangeStateCommand:AddParam{ Type = "number", Min = 0, Max = 5 }
end