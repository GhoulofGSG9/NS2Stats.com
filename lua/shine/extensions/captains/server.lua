local Plugin = Plugin
local Vote = {}

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

if not Shine.PlayerInfoHub then 
	Script.Load( "lua/shine/core/server/playerinfohub.lua" )
end
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
	Cache = { temp },
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
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:Initialise()
	self.Enabled = true
	self.Votes = {}
	self:ResetTeams()
	self.Cache = false

	--update HiveData of players we allready received their HiveInfo
	for _, Client in ipairs( GetAllClients() ) do
		local ClientId = Client:GetUserId()
		local HiveInfo = PlayerInfoHub:GetHiveData( ClientId )
		if HiveInfo then
			HiveData[ ClientId ] = HiveInfo
		end
		self:ClientConfirmConnect( Client )
	end
	
	self.dt.State = 0

	self:CreateCommands()
	self:CheckStart()
	
	SetupClassHook( "Player", "SetName", "OnPlayerRename", "PassivePost" )
	return true
end

function Plugin:CheckStart()	
	if self.Config.Cache.Teams then
		self.Cache = true
		self.Teams = self.Config.Cache.Teams
		self.Config.Cache = {}
		self:SaveConfig( true )		
		self:CreateTimer( "CaptainWait", 1, self.Config.MaxWaitForCaptains, function() self:Reset() end )	
	elseif Shine.GetHumanPlayerCount() >= self.Config.MinPlayers and self.dt.State == 0 and not self:TimerExists( "CaptainWait" ) then
		local Players = GetAllPlayers()
		if Gamerules then 
			for i = 1, #Players do
				local Player = Players[ i ]
				Gamerules:JoinTeam( Player, 0, nil, true )
			end	
			Gamerules:ResetGame()
		end
		self.dt.State = 1
		self:StartVote()
	end
end

function Plugin:ResetTeams()
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
end

function Plugin:Reset()
	self:Notify( nil, "The Teams have been reset, restarting Captain Mode ..." )
	self:ResetTeams()
	self.Config.Cache = {}
	self:SaveConfig( true )
	
	self:DestroyAllTimers()
	for i = 0, 2 do
		if self.Votes[ i ] then
			self.Votes[ i ]:Reset()
		end
	end
	
	self.dt.State = 0
	self:CheckStart()
end

function Plugin:StartVote( Team )
	if not self.Config.VoteforCaptains then return end
	
	Team = Team or 0
	self.Votes[ Team ] = Vote:New( self.Votes[ Team ], Team )
	self.Votes[ Team ]:Start()
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
		self:DestroyTimer( "CaptainWait" )
		self.dt.State = 2
		local Clients = Shine.GetAllClients()
		for i = 1, #Clients do
			local Client = Clients[ i ]
			local SteamId = Client:GetUserId()
			local Team
			if self.Teams[ 1 ].Players[ SteamId ] then
				Team = 1
			elseif self.Teams[ 2 ].Players[ SteamId ] then
				Team = 2
			end
			
			if Team then
				local Player = Client:GetControllingPlayer()
				Gamerules:JoinTeam( Player, self.Teams[ Team ].TeamNumber, nil, true )
			end
		end
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
	Gamerules:JoinTeam( Player, 0, nil, true )
	CaptainsNum = CaptainsNum - 1
	
	if not SetCall and self.dt.State ~= 1 then
		self:StartVote( TeamNumber )
	end	
end

function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )
	if ShineForce or self.Config.AllowSpectating and NewTeam == kSpectatorIndex or 
	self.Config.AllowPregameJoin and self.dt.State == 0 then return end
	
	return false
end

function Plugin:OnPlayerRename( Player, Name )
	if Name == kDefaultPlayerName then return end
	
	self:SendPlayerData( nil, Player )
end

function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force, ShineForce )
	local SteamId = Player:GetSteamId()	
	if self.dt.State > 0 then
		if OldTeam == 1 or OldTeam == 2 then
			local Team = self.Teams[ 1 ].TeamNumber == OldTeam and 1 or 2
			self.Teams[ Team ].Players[ SteamId ] = nil
			self:Notify( nil, "%s left Team %s", true, Player:GetName(), Team)
		end
		if NewTeam == 1 or NewTeam == 2 then
			local Team = self.Teams[ 1 ].TeamNumber == NewTeam and 1 or 2
			self.Teams[ Team ].Players[ SteamId ] = true
			self:Notify( nil, "%s joined Team %s", true, Player:GetName(), Team )
		end
	end
	
	self:SendPlayerData( nil, Player )
end

function Plugin:OnReceiveHiveData( Client, HiveInfo )
	local SteamId = Client:GetUserId()
	local Player = Client:GetControllingPlayer()
	
	HiveData[ SteamId ] = HiveInfo
	self:SendPlayerData( nil, Player )
end

function Plugin:SendPlayerData( Client, Player, Disconnect )
	local steamId = Player:GetSteamId()

	local TeamNumber = self:GetTeamNumber( steamId )
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
		votes = self.dt.State == 1 and self.Votes[ 0 ].Votes[ steamId ] and self.Votes[ 0 ].Votes[ steamId ].Count or self.Votes[ TeamNumber ] and self.Votes[ TeamNumber ].Votes[ steamId ] and self.Votes[ TeamNumber ].Votes[ steamId ].Count or 0,
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
	
	self:SimpleTimer( 1, function()
		for _, Player in ipairs( GetAllPlayers() ) do
			self:SendPlayerData( Client, Player )
		end
	end)
	
	local Timer = self.Timers[ "CaptainVote0" ]
	if Timer then
		self:SendNetworkMessage( Client, "VoteState", { team = 0, start = true, timeleft = math.Round( Timer:GetTimeUntilNextRun(), 0 ) }, true )
	end
	
	local CaptainTeam = self:GetCaptainTeamNumbers( SteamId )
	if CaptainTeam then
		self:SetCaptain( SteamId, CaptainTeam)
	elseif self.dt.State == 0 then
		self:CheckStart()
	elseif self.dt.State == 2 then 
		for i = 1, 2 do
			self.Teams[ i ].Players[ SteamId ] = nil
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
		if self.Teams[ i ].Players[ SteamId ] then
			PlayingTeamNumber = self.Teams[ i ].TeamNumber
			TeamNumber = i
			break
		end
	end
	
	if MarinesNumPlayers == AliensNumPlayers then		
		if PlayingTeamNumber then
			Gamerules:JoinTeam( Player, PlayingTeamNumber, nil, true )
		else
			local Random = Random( 1, 2 )
			
			self.Teams[ Random ].Players[ SteamId ] = true
		
			Gamerules:JoinTeam( Player, self.Teams[ Random ].TeamNumber, nil, true )
		end
	else
		if PlayingTeamNumber then
			self.Teams[ TeamNumber ].Players[ SteamId ] = nil
		end
		
		if MarinesNumPlayers < AliensNumPlayers then
			TeamNumber = self.Teams[ 1 ].TeamNumber == 1 and 1 or 2
		else
			TeamNumber = self.Teams[ 1 ].TeamNumber == 2 and 1 or 2
		end
		
		self.Teams[ TeamNumber ].Players[ SteamId ] = true
		Gamerules:JoinTeam( Player, self.Teams[ TeamNumber ].TeamNumber, nil, true )
	end
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

function Plugin:MapChange()
	self.Config.Cache.Teams = self.Teams
	self:SaveConfig( true )
end

function Plugin:ClientDisconnect( Client )
	local Player = Client:GetControllingPlayer()
	self:SendPlayerData( nil, Player, true )
	
	local SteamId = Client:GetUserId()
	local TeamNumber = self:GetTeamNumber( SteamId )
	
	if TeamNumber > 0 then
		self:Notify( nil, "%s left Team %s", true, Player:GetName(), TeamNumber )
		if self.Teams[ TeamNumber ].Captain == SteamId and not self:TimerExists( "CaptainWait" ) then
			self:Notify( nil, "Also Team %s is now without a Captain. Starting a vote for a new Captain ...", true, TeamNumber )
			self:RemoveCaptain( TeamNumber )
		end
		self.Teams[ TeamNumber ].Players[ SteamId ] = nil
	end
	
	for i = 0, 2 do
		if self.Votes[ i ] and self.Votes[ i ]:GetIsStarted() then
			self.Votes[ i ]:Remove( SteamId )
		end
	end
end

function Plugin:CheckGameStart()
	if self.dt.State ~= 3 then
		if self.Teams[ 1 ].Ready and self.Teams[ 2 ].Ready then 
			self.Teams[ 1 ].Ready = nil
			self.Teams[ 2 ].Ready = nil
			self.dt.State = 3
			return true
		else
			return false
		end
	end
end

function Plugin:EndGame( Gamerules, WinningTeam )
	if WinningTeam then
		local Winner = WinningTeam:GetTeamNumber()
		for i = 1, 2 do
			local Team = self.Teams[ i ]
			if Team.TeamNumber == Winner then
				Team.Wins = Team.Wins + 1
				local Info = {
					number = i,
					name = Team.Name,
					wins = Team.Wins,
					teamnumber = Team.TeamNuber,
				}
				self:SendNetworkMessage( nil, "TeamInfo", Info, true )
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
	local AllPlayer = GetAllPlayers()
	for i = 1, 2 do
		local Captain = self.Teams[ i ].Captain
		self:SetCaptain( Captain, i )
	end
	
	for i = 1, #AllPlayer do
		local Player = AllPlayer[ i ]
		local SteamId = Player:GetSteamId()
		local Team = self:GetTeamNumber( SteamId )
		local TeamNumber = Team and self.Teams[ Team ].TeamNumber
		if Player:GetTeamNumber() == 0 then
			Gamerules:JoinTeam( Player, TeamNumber, nil, true )
		end
	end
	self.dt.State = 2
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
		local ClientId = Client:GetUserId()
		local TargetId = Target:GetUserId()
		local TeamNumber = self:GetTeamNumber( ClientId )
		
		local Vote = self.Votes[ TeamNumber ]
		if Vote and Vote:GetIsStarted() then
			Vote:Add( ClientId, TargetId )
		end
	end
	local CommandVoteCaptain = self:BindCommand( "sh_votecaptain", "votecaptain", VoteCaptain, true )
	CommandVoteCaptain:AddParam{ Type = "client", IgnoreCanTarget = true }
	CommandVoteCaptain:Help( "<player> Votes for the given player to become captain" )
	
	-- addplayer
	local function AddPlayer( Client, Target )
		local SteamId = Client:GetUserId()
		local TargetId = Target:GetUserId()
		
		if self:GetTeamNumber( TargetId ) ~= 0 then
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
		
		local TargetPlayer = Target:GetControllingPlayer()
		if not TargetPlayer then return end
		
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
		self.Teams[ TeamNumber ].Ready = not self.Teams[ TeamNumber ].Ready
		self:Notify( nil, "Team %s is now %s", true, TeamNumber, self.Teams[ TeamNumber ].Ready and "ready" or "not ready" )
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
		Team.Name = TeamName
		local Info = {
			name = TeamName,
			wins = Team.Wins,
			number = TeamNumber,
			teamnumber = Team.TeamNumber
		}
		self:SendNetworkMessage( nil, "TeamInfo", Info, true )
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

--Vote Class
function Vote:New( NewVote, Team )
	NewVote = NewVote or {}
	setmetatable( NewVote, self )
	self.__index = self
	
	NewVote.Team = Team or 0
	return NewVote
end

function Vote:Reset()	
	if self.Votes then
		for ClientId in pairs( self.Votes ) do
			local Client = GetClientByNS2ID( ClientId )
			local Player = Client and Client:GetControllingPlayer()
			self.Votes[ ClientId ] = nil
			if Player then
				Plugin:SendPlayerData( nil, Player )
			end
		end
	else
		self.Votes = {}
	end
	
	self.Count = 0
	self.Ranks = {}
	self.Voted = {}
end

function Vote:Start()
	self:Reset()
	self.Started = true

	local Vote = self
	local VoteTime = Plugin.Config.MaxVoteTime * 60
	Plugin:CreateTimer( StringFormat( "CaptainVote%s", self.Team ), VoteTime, 1, function()
		self:End()
	end)
	Plugin:SendNetworkMessage( nil, "VoteState", { team = self.Team, start = true, timeleft = VoteTime }, true )
end

function Vote:GetIsStarted()
	return self.Started
end

function Vote:Remove( ClientId )
	local VoteId = self.Voted[ ClientId ]
	if not VoteId then return end

	local Count = self.Votes[ VoteId ].Count
	TableRemove( self.Ranks[ Count ], self.Votes[ VoteId ].RankId )

	Count = Count - 1
	self.Votes[ VoteId ].Count = Count

	if Count > 0 then
		self.Ranks[ Count ] =  self.Ranks[ Count ] or {}
		TableInsert( self.Ranks[ Count ], VoteId )
		self.Votes[ VoteId ].RankId = #self.Ranks[ Count ]
	else
		self.Votes[ VoteId ] = nil
	end
	
	self.Count = self.Count - 1
	local VoteClient = GetClientByNS2ID( VoteId )
	local Player = VoteClient and VoteClient:GetControllingPlayer()
	if not Player then return end
	
	Plugin:SendPlayerData( nil, Player )
end

function Vote:Add( ClientId, TargetId )
	
	self:Remove( ClientId )
	
	local Vote = self.Votes[ TargetId ] or { Count = 0, RankId = 0 }
	if Vote.Count > 0 then 
		TableRemove( self.Ranks[ Vote.Count ], Vote.RankId )
	end

	Vote.Count = Vote.Count + 1
	self.Ranks[ Vote.Count ] = self.Ranks[ Vote.Count ] or {}
	TableInsert( self.Ranks[ Vote.Count ], TargetId )
	Vote.RankId = #self.Ranks[ Vote.Count ]

	self.Votes[ TargetId ] = Vote
	self.Voted[ ClientId ] = TargetId
	
	self.Count = self.Count + 1
	
	local TargetClient = GetClientByNS2ID( TargetId )
	local TargetPlayer = TargetClient and TargetClient:GetControllingPlayer()
	
	if not TargetPlayer then return end	
	Plugin:SendPlayerData( nil, TargetPlayer )
	
	local PlayerCount = Shine.GetHumanPlayerCount()
	
	if self.Team ~= 0 then
		local TeamNumber = self.Team
		
		if not ( Plugin.Teams[ TeamNumber ].Players[ ClientId ] and Plugin.Teams[ TeamNumber ].Players[ TargetId ] ) then
			return 
		end
		
		PlayerCount = #Shine.GetTeamClients( Plugin.Teams[ TeamNumber ].TeamNumber )
	end
	
	if self.Count >= PlayerCount * Plugin.Config.MinVotesToPass then
		self:End()
	end
end

function Vote:End()
	self.Started = false
	
	local Winners = {}
	local HighestRank = #self.Ranks
	local HighestRankSize = self.Ranks[ HighestRank ] and #self.Ranks[ HighestRank ] or 0
	
	local WinnersNeeded = self.Team > 0 and 1 or 2
	if WinnersNeeded > HighestRank and WinnersNeeded > HighestRankSize then
		Plugin:Notify( nil, "CaptainVote%s failed because not enough players voted or we did not got enough Captain candidates! Restarting Vote...", true, self.Team == 1 and " for Team 1" or self.Team == 2 and " for Team 2" or "")
		self:Start()
		return
	end
	
	Plugin:DestroyTimer( StringFormat( "CaptainVote%s", self.Team ) )
	Plugin:SendNetworkMessage( nil, "VoteState", { team = self.Team, start = false, timeleft = 0 }, true )
	
	if HighestRankSize > WinnersNeeded then
		--Notify?
		for i = 1, WinnersNeeded do
			local j = Random( 1, HighestRankSize )
			Winners[ i ] = self.Ranks[ HighestRank ][ j ]
			TableRemove( self.Ranks[ HighestRank ], j )
			HighestRankSize = HighestRankSize - 1
		end
	elseif HighestRankSize == WinnersNeeded then
		for i = 1, WinnersNeeded do
			Winners[ i ] = self.Ranks[ HighestRank ][ i ]
		end
	else
		Winners[ 1 ] = self.Ranks[ HighestRank ][ 1 ]
		--get next rank
		local NextRank
		for i = HighestRank - 1, 1, -1 do
			if self.Ranks[ i ] and #self.Ranks[ i ] > 0 then
				NextRank = i
				break
			end
		end
		
		if not NextRank then
			Shine:DebugPrint("Captains Vote had a issue while picking a winner.\n Class table:\n%s", true, table.ToString( self ) )
			return
		end
		
		local j = Random( 1, #self.Ranks[ NextRank ] )
		Winners[ 2 ] = self.Ranks[ j ]
	end
	
	if self.Team > 0 then 
		Plugin:SetCaptain( Winners[ 1 ], self.Team )
	else
		Plugin:SetCaptain( Winners[ 1 ], 1 )
		Plugin:SetCaptain( Winners[ 2 ], 2 )
	end
end