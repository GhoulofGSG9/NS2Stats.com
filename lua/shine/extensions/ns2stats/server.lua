--[[
Shine ns2stats plugin. - Server
]]

local Shine = Shine
local Notify = Shared.Message

local Plugin = Plugin

local Floor = math.floor
local ToString = tostring
local StringFind = string.find
local StringFormat = string.format
local StringSub = string.UTF8Sub
local StringLen = string.len
local StringLower = string.UTF8Lower
local StringReverse = string.UTF8Reverse

local TableInsert = table.insert

local JsonEncode = json.encode
local JsonDecode = json.decode

local HTTPRequest = Shared.SendHTTPRequest

local SetupClassHook = Shine.Hook.SetupClassHook
local SetupGlobalHook = Shine.Hook.SetupGlobalHook
local Call = Shine.Hook.Call

Plugin.Version = "shine"

Plugin.HasConfig = true
Plugin.ConfigName = "Ns2Stats.json"
Plugin.DefaultConfig =
{
	SendMapData = false, --Send Mapdata, only set true if minimap is missing at website or is incorrect
	StatusReport = false, -- send Status to NS2Stats every min
	EnableHiveStats = true, -- should we enable UWE Hive Stats
	WebsiteUrl = "http://ns2stats.com", --this is the ns2stats URL
	Awards = true, --show Award
	ShowNumAwards = 4, --how many Awards should be shown at the end of the game?
	AwardMsgTime = 20, -- secs to show Awards
	AwardMsgColour = { 255, 215, 0 },
	LogChat = false, --log the chat?
	ServerKey = "", -- Serverkey given by ns2stats.com
	Tags = {}, --Tags added to log
	Competitive = false, -- tag rounds as Competitive
	Lastroundlink = "", --Link of last round
	DisableSponitor = false,
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:SetupHooks()
	SetupClassHook( "ConstructMixin", "SetConstructionComplete", "OnFinishedBuilt", "PassivePost" )
	SetupClassHook( "DamageMixin", "DoDamage", "OnDoDamage", function ( OldFunc, ...)
		Call( "PreDoDamage", ... )
		local a = OldFunc( ... )
		Call( "PastDoDamage", ... )
		return a
	end)
	SetupClassHook( "Flamethrower", "FirePrimary", "OnFirePrimary", function( OldFunc, ... )
		Call( "PreFirePrimary", ... )
		OldFunc( ... )
		Call( "PostFirePrimary", ... )
	end )
	SetupClassHook( "NS2Gamerules", "OnEntityDestroy", "OnEntityDestroy", "PassivePre" )
	SetupClassHook( "NS2Gamerules", "ResetGame", "OnGameReset", "PassivePre" )
	SetupClassHook( "Player", "OnJump", "OnPlayerJump", "PassivePost" )
	SetupClassHook( "PlayerBot", "UpdateNameAndGender","OnBotRenamed", "PassivePost" )
	SetupClassHook( "PlayerInfoEntity", "UpdateScore", "OnPlayerScoreChanged", "PassivePost" )
	SetupClassHook( "ResearchMixin", "OnResearchCancel", "AddUpgradeAbortedToLog", "PassivePost" )
	SetupClassHook( "ResearchMixin", "SetResearching", "OnTechStartResearch", "PassivePre" )
	SetupClassHook( "ResearchMixin", "TechResearched", "OnTechResearched", "PassivePost" )
	SetupClassHook( "ResourceTower", "CollectResources", "OnTeamGetResources", "PassivePost" )
	SetupClassHook( "UpgradableMixin", "RemoveUpgrade","AddUpgradeLostToLog", "PassivePost" )

	SetupGlobalHook( "CheckMeleeCapsule", "OnCheckMeleeCapsule", function( OldFunc, ... )
		local didHit, target, endPoint, direction, surface = OldFunc( ... )
		
		if not didHit then
			Call( "OnMeleeMiss", ... )
		end

		return didHit, target, endPoint, direction, surface

	end)

	SetupGlobalHook( "RadiusDamage", "OnRadiusDamage", function( OldFunc, ... )
		Call( "PreRadiusDamage", ... )
		
		OldFunc( ... )
		
		Call( "PostRadiusDamage", ... )
	end)
	
	if self.Config.DisableSponitor then
		SetupClassHook( "ServerSponitor", "OnStartMatch", "OnStartMatch", function() end )
	end
	
end

function Plugin:Initialise()
	self.Enabled = false
	
	self:Setup()
	
	local Clients = Shine.GetAllClients()	
	--check if there are already players at the server
	if #Clients > 0 then
		for i = 1, #Clients do
			local Client = Clients[ i ]
			self:ClientConfirmConnect( Client )
		end	
	end
	
	self:SetupHooks()
	
	return true
end

function Plugin:Setup()
	self.Enabled = true
	
	self.dt.WebsiteUrl = self.Config.WebsiteUrl
	self.dt.SendMapData = self.Config.SendMapData
	
	--create values
	self.StatsEnabled = true
	self.SuccessfulSends = 0
	self.ResendCount = 0
	self:OnGameReset()
	
	--create Commands
	self:CreateCommands()
	
	if self.Config.ServerKey == "" then
		self.StatsEnabled = false
		HTTPRequest( StringFormat( "%s/api/generateKey/?s=7g94389u3r89wujj3r892jhr9fwj", self.Config.WebsiteUrl ), "GET", function(Response) self:AcceptKey( Response ) end )
	else
		self.ServerId = self:GetServerId()
	end  
	
	--Timers
	
	--every 1 sec
	--to update Weapon data
	self:CreateTimer( "WeaponUpdate", 1, -1, function()
		self:UpdateWeaponTable()
	end )
	
	-- every 30 sec send Server Status + Devour   
	if self.Config.StatusReport then
		self:CreateTimer( "SendStatus" , 30, -1, function() self:SendServerStatus( self.CurrentGameState ) end) --Plugin:DevourSendStatus()
	end
end

-- Events

--Game Events

--Game reset
function Plugin:OnGameReset()
	--Resets all Stats
	self.Working = true
	self.Log = {}
	self.LogPartNumber = 1
	self.LogPartToSend  = 1
	self.GameStartTime = 0
	self.RoundFinished = 0
	self.NextAwardId = 0
	self.Awards = {}
	self.RoundStarted = false
	self.CurrentGameState = 0
	self.PlayersInfos = {}
	self.ItemInfos = {}
	self.BuildingsInfos = {}
	self.OldUpgrade = -1
	self.DoDamageHeathChange = {}
	self.HitCache = {}
	self.FireCache = {}
	self.DetonateCache = {}
	
	-- update stats all connected players
	for _, Client in ipairs( Shine.GetAllClients() ) do
		self:AddPlayerToTable( Client )
	end
	
	self:AddLog( { action = "game_reset" } )
end

--Gamestart
function Plugin:SetGameState( Gamerules, NewState, OldState )
	self.CurrentGameState = NewState
	if NewState == kGameState.Started then
		self.Working = false             
		self.RoundStarted = true
		self.GameStartTime = Shared.GetTime()
		self:AddLog( { action = "game_start" } )
	
		--add Playerlist to Log           
		self:AddPlayersToLog( 0 )
	end
end

--Gameend
function Plugin:EndGame( Gamerules, WinningTeam )         
	if self.Config.Awards then Plugin:SendAwardListToClients() end
	self:AddPlayersToLog( 1 )
	
	local Winner = WinningTeam and WinningTeam:GetTeamNumber() or 0
	
	local InitialHiveTechIdString = "None"
	if Gamerules.initialHiveTechId then
		InitialHiveTechIdString = EnumToString( kTechId, Gamerules.initialHiveTechId )
	end
	
	local Params =
		{
			version = ToString( Shared.GetBuildNumber() ),
			winner = Winner,
			length = StringFormat( "%.2f", Shared.GetTime() - Gamerules.gameStartTime ),
			map = Shared.GetMapName(),
			start_location1 = Gamerules.startingLocationNameTeam1,
			start_location2 = Gamerules.startingLocationNameTeam2,
			start_path_distance = Gamerules.startingLocationsPathDistance,
			start_hive_tech = InitialHiveTechIdString,
		}
	Plugin:AddServerInfos( Params )
	
	self.RoundFinished = 1
	self.RoundStarted = false
	if self.StatsEnabled then self:SendData() end        
end

--Player Events

--Player Connected
function Plugin:ClientConfirmConnect( Client )
	if not Client or Client:GetIsVirtual() then return end
	
	local Params =
	{
		action = "connect",
		steamId = Plugin:GetId( Client )
	}
	self:AddLog( Params )
	
	--Player disconnected and came back
	local PlayerInfo = self:GetPlayerByClient( Client )
	
	if not PlayerInfo then
		Plugin:AddPlayerToTable( Client )  
	else 
		PlayerInfo.dc = false 
	end
end

--Player Disconnect
function Plugin:ClientDisconnect( Client )
	if not Client then return end
	
	local PlayerInfo = self:GetPlayerByClient( Client )
	if not PlayerInfo then return end
	
	PlayerInfo.dc = true
	
	local Params = {
			action = "disconnect",
			steamId = PlayerInfo.steamId,
			score = PlayerInfo.score
	}
	self:AddLog( Params )
end

--score changed (temp for 263)
function Plugin:OnPlayerScoreChanged( PlayerInfoEntity )
	if self.RoundFinished == 1 then return end
	
	local Player = Shared.GetEntity( PlayerInfoEntity.playerId )  
	if not Player then return end
	
	local Client = Player:GetClient()
	if not Client then return end
	
	local PlayerInfo = self:GetPlayerByClient( Client )
	if not PlayerInfo then return end
	
	local Lifeform = Player:GetMapName()
	
	--check teamnumber
	local Teamnumber = Player:GetTeamNumber() or 0    
	if Teamnumber < 0 then return end
	
	if PlayerInfo.teamnumber == 3 and Teamnumber > 0 then return end   --filter spectator
	
	if Teamnumber >= 0 and PlayerInfo.teamnumber ~= Teamnumber then
		PlayerInfo.teamnumber = Teamnumber
	
		local Params =
		{
			action = "player_join_team",
			name = PlayerInfo.name,
			team = PlayerInfo.teamnumber,
			steamId = PlayerInfo.steamId,
			score = PlayerInfo.score
		}
		self:AddLog( Params ) 
	end
	
	--check if Lifeform changed    
	if not Player:GetIsAlive() and (Teamnumber == 1 or Teamnumber == 2) then Lifeform = "dead" end
	if PlayerInfo.lifeform ~= Lifeform then
		PlayerInfo.lifeform = Lifeform
		self:AddLog(
		{
			action = "lifeform_change",
			name = PlayerInfo.name, 
			lifeform = Lifeform, 
			steamId = PlayerInfo.steamId
		})      
	end
	
	self:UpdatePlayerInTable( Client, Player, PlayerInfo )
end

--Bots renamed
function Plugin:OnBotRenamed( Bot )
	local Player = Bot:GetPlayer()
	local Name = Player:GetName()
	if not Name or not StringFind( Name, "[BOT]", nil, true ) then return end
	
	local Client = Player:GetClient()
	if not Client then return end
		
	local PlayerInfo = Plugin:GetPlayerByClient( Client )
	if not PlayerInfo then
		self:AddPlayerToTable( Client )
		PlayerInfo = self:GetPlayerByClient( Client )
	else
		PlayerInfo.dc = false
		return
	end
	
	--Bot connects
	local Params = {
			action = "connect",
			steamId = PlayerInfo.steamId
	}
	
	self:AddLog( Params )        
end

local function GetAttacker( Mixin )
	if not Mixin then return end
	
	local Parent = Mixin:GetParent()
	local Owner = HasMixin( Mixin, "Owner" ) and Mixin:GetOwner()
	
	local Attacker 
	if Mixin:isa( "Player" ) then
		Attacker = Mixin
	elseif Parent and Parent:isa( "Player" ) then
		Attacker = Parent
	elseif Owner and Owner:isa( "Player" ) then
		Attacker = Owner
	end
	
	return Attacker
end

--For Flame-thrower tracking
function Plugin:PreFirePrimary( Weapon )
	self.FireCache[ Weapon:GetId() ] = true
end

function Plugin:PostFirePrimary( Weapon, Player )
	local Id = Weapon:GetId()

	if self.FireCache[ Id ] then
		self:AddMissToLog( Player, Weapon )
		self.FireCache[ Id ] = nil
	end
end

--Player shoots weapon
function Plugin:PreDoDamage( DamageMixin, Damage, Target, Point )
	if not self.RoundStarted then return end
	
	local Id = DamageMixin:GetId()
	if self.HitCache[ Id ] then return end
	self.HitCache[ Id ] = true
	
	if Target and Damage > 0 and HasMixin( Target, "Live" ) then
		self.DoDamageHeathChange[Target:GetId()] = Target:GetHealth() + Target:GetArmor() * 2
	else
		self:AddMissToLog( GetAttacker( DamageMixin ), DamageMixin )
	end
end

function Plugin:PastDoDamage( DamageMixin, Damage, Target, Point )
	if not self.RoundStarted then return end
	
	local TargetId = Target and Target:GetId()	
	local TargetPostHealth = TargetId and self.DoDamageHeathChange[ TargetId ]
	
	if TargetPostHealth then		
		local TargetHealth = Target:GetHealth() + Target:GetArmor() * 2
		local Damage = TargetPostHealth - TargetHealth
		local Attacker = GetAttacker( DamageMixin )
		
		self.DoDamageHeathChange[ TargetId ] = nil
		
		if Damage > 0 then
			self:AddHitToLog( Target, Attacker, DamageMixin, Damage )
		end
	end
	
	local Id = DamageMixin:GetId()
	
	self.HitCache[ Id ] = nil
	self.FireCache[ Id ] = nil
	self.DetonateCache[ Id ] = nil
end

--grenades
function Plugin:PreRadiusDamage( entities, centerOrigin, radius, fullDamage, doer, ignoreLOS, fallOffFunc )
	if not self.RoundStarted then return end
	
	self.DetonateCache[ doer:GetId() ] = true
end

function Plugin:PostRadiusDamage( entities, centerOrigin, radius, fullDamage, doer, ignoreLOS, fallOffFunc )
	local Id = doer:GetId()
	if not self.DetonateCache[ Id ] then return end
	
	self:AddMissToLog( GetAttacker( doer ) , doer )
	self.DetonateCache[ Id ] = nil
end

function Plugin:OnMeleeMiss( weapon, player )
	self:AddMissToLog( player, weapon )
end

--add Hit
function Plugin:AddHitToLog( Target, Attacker, Doer, Damage )
	if not Attacker then return end
	
	if Target:isa( "Player" ) then
		self:WeaponsAddHit( Attacker, StringLower( Doer:GetMapName() ), Damage )		
	else --Target is a structure
		self:WeaponsAddStructureHit( Attacker, StringLower( Doer:GetMapName() ), Damage )
	end
end

--Add miss
function Plugin:AddMissToLog( Attacker, Doer )
	local Client = Attacker and Attacker:GetClient()
	if not Client then return end

	local Player = Plugin:GetPlayerByClient( Client )
	if not Player then return end
	
	local WeaponName = StringLower( Doer and Doer:GetMapName() or Attacker:GetActiveWeaponName() or "none" )
	
	--gorge fix
	if WeaponName == "spitspray" then
		WeaponName = "spit"
	end
	
	self:WeaponsAddMiss( Client, WeaponName )
end

--weapon add miss
function Plugin:WeaponsAddMiss( Client, Weapon )
	local PlayerInfo = self:GetPlayerByClient( Client )
	if not PlayerInfo then return end
	
	local FoundId      
	for i=1, #PlayerInfo.weapons do
		if PlayerInfo.weapons[ i ].name == Weapon then
			FoundId = i
			break
		end
	end

	if FoundId then
		PlayerInfo.weapons[ FoundId ].miss = PlayerInfo.weapons[ FoundId ].miss + 1
	else --add new weapon
		TableInsert( PlayerInfo.weapons,
		{
			name = Weapon,
			time = 0,
			miss = 1,
			player_hit = 0,
			structure_hit = 0,
			player_damage = 0,
			structure_damage = 0
		})
	end        
end

--weapon addhit to Player
function Plugin:WeaponsAddHit( Player, Weapon, Damage )
	local Client = Player:GetClient()
	if not Client then return end
	
	local PlayerInfo = Plugin:GetPlayerByClient( Client )
	if not PlayerInfo then return end
	
	local FoundId
	
	for i=1, #PlayerInfo.weapons do
		if PlayerInfo.weapons[ i ].name == Weapon then
			FoundId = i
			break
		end
	end

	if FoundId then
		PlayerInfo.weapons[ FoundId ].player_hit = PlayerInfo.weapons[ FoundId ].player_hit + 1
		PlayerInfo.weapons[ FoundId ].player_damage = PlayerInfo.weapons[ FoundId ].player_damage + Damage
		
	else --add new weapon
		TableInsert( PlayerInfo.weapons,
		{
			name = Weapon,
			time = 0,
			miss = 0,
			player_hit = 1,
			structure_hit = 0,
			player_damage = Damage,
			structure_damage = 0
		})
	end        
end

--weapon addhit to Structure
function Plugin:WeaponsAddStructureHit( Player, Weapon, Damage)
	local Client = Player:GetClient()
	if not Client then return end
	
	local PlayerInfo = Plugin:GetPlayerByClient( Client )
	if not PlayerInfo then return end
	
	local FoundId
	
	for i = 1, #PlayerInfo.weapons do
		if PlayerInfo.weapons[ i ].name == Weapon then
			FoundId = i
			break
		end
	end

	if FoundId then
		PlayerInfo.weapons[ FoundId ].structure_hit = PlayerInfo.weapons[ FoundId ].structure_hit + 1
		PlayerInfo.weapons[ FoundId ].structure_damage = PlayerInfo.weapons[ FoundId ].structure_damage + Damage

	else --add new weapon
		TableInsert(PlayerInfo.weapons,
		{
			name = Weapon,
			time = 0,
			miss = 0,
			player_hit = 0,
			structure_hit = 1,
			player_damage = 0,
			structure_damage = Damage
		})
	end
		
end
--DoDamage end

--Player jumps
function Plugin:OnPlayerJump( Player )
	if not self.RoundStarted then return end
	
	local PlayerInfo = self:GetPlayerByName( Player.name )
	if not PlayerInfo then return end
	PlayerInfo.jumps = PlayerInfo.jumps + 1   
end

--Chatlogging
function Plugin:PlayerSay( Client, Message )
	if not Plugin.Config.LogChat then return end
	
	local Player = Client:GetControllingPlayer()
	if not Player then return end
	
	self:AddLog({
		action = "chat_message",
		team = Player:GetTeamNumber(),
		steamid = Plugin:GetId( Client ),
		name = Player:GetName(),
		message = Message.message,
		toteam = Message.teamOnly
	})
end

--Team Events

--Resource gathered
function Plugin:OnTeamGetResources( ResourceTower )    
	local Params =
	{
		team = ResourceTower:GetTeam():GetTeamNumber(),
		action = "resources_gathered",
		amount = kTeamResourcePerTick
	}
	self:AddLog( Params )
end

--Structure Events

--Building Dropped
function Plugin:OnConstructInit( Building )    
	if not self.RoundStarted then return end

	local TechId = Building:GetTechId()
	local name = EnumToString( kTechId, TechId )
	
	if name == "Hydra" or name == "GorgeTunnel"  or name == "BabblerEgg" then return end --Gorge Building Fix
	
	self.BuildingsInfos[ Building:GetId() ] = true
	
	local StructureOrigin = Building:GetOrigin()
	local Build =
	{
		action = "structure_dropped",
		id = Building:GetId(),
		steamId = self:GetTeamCommanderSteamid( Building:GetTeamNumber() ) or 0,       
		team = Building:GetTeamNumber(),        
		structure_cost = GetCostForTech( TechId ),
		structure_name = name,
		structure_x = StringFormat("%.4f", StructureOrigin.x ),
		structure_y = StringFormat("%.4f", StructureOrigin.y ),
		structure_z = StringFormat( "%.4f", StructureOrigin.z ),
	}
	Plugin:AddLog( Build )
	if Building.isGhostStructure then self:OnGhostCreated( Building ) end
end

--Building built
function Plugin:OnFinishedBuilt( ConstructMixin, Builder )
	if not self.RoundStarted then return end
	self.BuildingsInfos[ ConstructMixin:GetId() ] = true 

	local TechId = ConstructMixin:GetTechId()    
	local StructureOrigin = ConstructMixin:GetOrigin()
	
	if Builder and Builder.GetName then
		local PlayerInfo = Plugin:GetPlayerByName( Builder:GetName() )
	end
	
	local Teamnumber = ConstructMixin:GetTeamNumber()
	local SteamId = Plugin:GetTeamCommanderSteamid(teamnumber) or 0    
	local Buildername = ""
		
	if PlayerInfo then
		SteamId = PlayerInfo.steamId
		Buildername = PlayerInfo.name
		PlayerInfo.total_constructed = PlayerInfo.total_constructed + 1
	end
	
	local Params =
	{
		action = "structure_built",
		id = ConstructMixin:GetId(),
		builder_name = Buildername,
		steamId = SteamId,
		structure_cost = GetCostForTech( TechId ),
		team = Teamnumber,
		structure_name = EnumToString( kTechId, TechId ),
		structure_x = StringFormat( "%.4f", StructureOrigin.x ),
		structure_y = StringFormat( "%.4f", StructureOrigin.y ),
		structure_z = StringFormat( "%.4f", StructureOrigin.z ),
	}
	self:AddLog( Params )
end

--Ghost Buildings (Blueprints)
function Plugin:OnGhostCreated(GhostStructureMixin)
	if not self.RoundStarted then return end
	self:GhostStructureAction( "ghost_create", GhostStructureMixin )
end

function Plugin:OnGhostDestroyed(GhostStructureMixin)
self.BuildingsInfos[ GhostStructureMixin:GetId() ] = nil
self:GhostStructureAction( "ghost_destroy", GhostStructureMixin )
end

--addfunction
function Plugin:GhostStructureAction( Action, Structure )
	if not Structure then return end
	local TechId = Structure:GetTechId()
	local tOrigin = Structure:GetOrigin()

	local Params =
	{
		action = Action,
		structure_name = EnumToString( kTechId, TechId),
		team = Structure:GetTeamNumber(),
		id = Structure:GetId(),
		structure_x = StringFormat( "%.4f", tOrigin.x ),
		structure_y = StringFormat( "%.4f", tOrigin.y ),
		structure_z = StringFormat( "%.4f", tOrigin.z )
	}
	self:AddLog( Params )    
end

--Upgrade Stuff

--Upgrades Started
function Plugin:OnTechStartResearch( ResearchMixin, ResearchNode, Player )
	if Player:isa( "Commander" ) then
		local Client = Player:GetClient()  
		local SteamId = self:GetId( Client ) or 0
		local TechId = ResearchNode:GetTechId()

		local Params =
		{
			structure_id = ResearchMixin:GetId(),
			commander_steamid = SteamId,
			team = Player:GetTeamNumber(),
			cost = GetCostForTech( TechId ),
			upgrade_name = EnumToString( kTechId, TechId ),
			action = "upgrade_started"
		}

		self:AddLog( Params )
	end
end

--Upgradefinished
function Plugin:OnTechResearched( ResearchMixin, Structure, ResearchId)
	if not Structure then return end
	local ResearchNode = ResearchMixin:GetTeam():GetTechTree():GetTechNode( ResearchId )    
	if not ResearchNode then return end
	
	local TechId = ResearchNode:GetTechId()
	
	if TechId == self.OldUpgrade then return end
	self.OldUpgrade = TechId
	
	local Params =
	{
		structure_id = Structure:GetId(),
		team = Structure:GetTeamNumber(),
		commander_steamid = Plugin:GetTeamCommanderSteamid( Structure:GetTeamNumber() ),
		cost = GetCostForTech( TechId ),
		upgrade_name = EnumToString( kTechId, TechId ),
		action = "upgrade_finished"
	}
	self:AddLog( Params )
end

--Upgrade lost
function Plugin:AddUpgradeLostToLog( UpgradableMixin, TechId )
	local Params =
	{
		team = UpgradableMixin:GetTeamNumber(),
		cost = GetCostForTech( TechId ),
		upgrade_name = EnumToString( kTechId, TechId ), 
		action = "upgrade_lost"
	}
	self:AddLog( Params )

end

--Research canceled
function Plugin:AddUpgradeAbortedToLog( ResearchMixin, ResearchNode )
	local TechId = ResearchNode:GetTechId()
	local SteamId = self:GetTeamCommanderSteamid( ResearchMixin:GetTeamNumber() )

	local Params =
	{
		structure_id = ResearchMixin:GetId(),
		team = ResearchMixin:GetTeamNumber(),
		commander_steamid = SteamId,
		cost = GetCostForTech( TechId ),
		upgrade_name = EnumToString( kTechId, TechId ),
		action = "upgrade_aborted"
	}
	self:AddLog( Params )
end

--Building recyled
function Plugin:OnBuildingRecycled( Structure, ResearchID )
	local tOrigin = Structure:GetOrigin()
	local TechId = Structure:GetTechId()
	
	if not TechId then return end    
	--from RecyleMixin.lua
		local UpgradeLevel =  Structure.GetUpgradeLevel and Structure:GetUpgradeLevel() or 0        
		local Amount = GetRecycleAmount( TechId, UpgradeLevel ) or 0
		-- returns a scalar from 0-1 depending on health the Structure has (at the present moment)
		local Scalar = Structure:GetRecycleScalar() * kRecyclePaybackScalar
		
		-- We round it up to the nearest value thus not having weird
		-- fracts of costs being returned which is not suppose to be
		-- the case.
		local FinalRecycleAmount = math.round( Amount * Scalar )
	--end   

	local Params =
	{
		id = Structure:GetId(),
		team = Structure:GetTeamNumber(),
		givenback = FinalRecycleAmount,
		structure_name = EnumToString( kTechId, TechId ),
		action = "structure_recycled",
		structure_x = StringFormat( "%.4f", tOrigin.x ),
		structure_y = StringFormat( "%.4f", tOrigin.y ),
		structure_z = StringFormat( "%.4f", tOrigin.z )
	}
	self:AddLog( Params )
end

--Structure gets killed
function Plugin:OnStructureKilled( Structure, Attacker , Doer )
	if not self.BuildingsInfos[ Structure:GetId() ] then return end
	self.BuildingsInfos[ Structure:GetId() ] = nil
	
	local tOrigin = Structure:GetOrigin()
	local TechId = Structure:GetTechId()
	Attacker = GetAttacker( Attacker )
	Doer = Doer or "none"
	
	--Structure killed
	if Attacker then
	
		local Player = Attacker                 
		local Client = Player:GetClient()
		local SteamId = self:GetId( Client ) or -1
		
		local Weapon = Doer and Doer.GetMapName and Doer:GetMapName() or "self"

		local Params =
		{
			id = Structure:GetId(),
			killer_steamId = SteamId,
			killer_lifeform = Player:GetMapName() or "none",
			killer_team = Player:GetTeamNumber() or 0,
			structure_team = Structure:GetTeamNumber(),
			killerweapon = Weapon,
			structure_cost = GetCostForTech( TechId ),
			structure_name = EnumToString( kTechId, TechId ),
			action = "structure_killed",
			structure_x = StringFormat( "%.4f", tOrigin.x ),
			structure_y = StringFormat( "%.4f", tOrigin.y ),
			structure_z = StringFormat( "%.4f", tOrigin.z )
		}
		self:AddLog( Params )
			
	--Structure suicide
	else
		local Params =
		{
			id = Structure:GetId(),
			structure_team = Structure:GetTeamNumber(),
			structure_cost = GetCostForTech( TechId ),
			structure_name = EnumToString( kTechId, TechId ),
			action = "structure_suicide",
			structure_x = StringFormat( "%.4f", tOrigin.x ),
			structure_y = StringFormat( "%.4f", tOrigin.y ),
			structure_z = StringFormat( "%.4f", tOrigin.z )
		}
		self:AddLog( Params )
	end 
end

--Mixed Events 

--Entity Killed
function Plugin:OnEntityKilled(Gamerules, TargetEntity, Attacker, Inflictor)
	if not self.RoundStarted then return end
	
	if TargetEntity:isa( "Player" ) then
		self:AddDeathToLog( TargetEntity, Attacker, Inflictor )     
	elseif self.BuildingsInfos[ TargetEntity:GetId() ] and not TargetEntity.isGhostStructure then 
		self:OnStructureKilled( TargetEntity, Attacker, Inflictor )      
	end   
end

function Plugin:OnEntityDestroy( Entity )
	if not self.RoundStarted then return end
	if Entity.isGhostStructure and self.BuildingsInfos[ Entity:GetId() ] then 
		self:OnGhostDestroyed( Entity )
	end    
end

--add Player death to Log
function Plugin:AddDeathToLog( Target, Attacker, Doer )
	if Attacker and Doer and Target then
		local aOrigin = Attacker:GetOrigin()
		local tOrigin = Target:GetOrigin()        
		local TargetClient = Target:GetClient()
		if not TargetClient then return end

		local TargetWeapon = Target:GetActiveWeapon() and Target:GetActiveWeapon():GetMapName() or "None"

		if Attacker:isa( "Player" ) then            
			local AttackerClient = Attacker:GetClient()           
			if not AttackerClient then return end
			
			local Params =
			{                
				--general
				action = "death",	
				
				--Attacker
				attacker_steamId = Plugin:GetId( AttackerClient ) or 0,
				attacker_team = HasMixin( Attacker, "Team" ) and Attacker:GetTeamType() or kNeutralTeamType,
				attacker_weapon = StringLower( Doer:GetMapName() ),
				attacker_lifeform = StringLower( Attacker:GetMapName() ), 
				attacker_hp = Attacker:GetHealth(),
				attacker_armor = Attacker:GetArmorAmount(),
				attackerx = StringFormat( "%.4f", aOrigin.x ),
				attackery = StringFormat( "%.4f", aOrigin.y ),
				attackerz = StringFormat( "%.4f", aOrigin.z ),
				
				--Target
				target_steamId = Plugin:GetId(TargetClient) or 0,
				target_team = Target:GetTeamType(),
				target_weapon = StringLower(TargetWeapon),
				target_lifeform = StringLower(Target:GetMapName()), 
				target_hp = Target:GetHealth(),
				target_armor = Target:GetArmorAmount(),
				targetx = StringFormat("%.4f", tOrigin.x),
				targety = StringFormat("%.4f", tOrigin.y),
				targetz = StringFormat("%.4f", tOrigin.z),
				target_lifetime = StringFormat( "%.4f", Shared.GetTime() - Target:GetCreationTime() )
			}
			Plugin:AddLog(Params)
				
			if Attacker:GetTeamNumber() ~= Target:GetTeamNumber() then
				--addkill
				Plugin:AddKill( Plugin:GetId(AttackerClient) )
			end
		else
			--natural causes death
			local Params =
			{
				--general
				action = "death",
	
				--Attacker
				attacker_weapon	= "natural causes",
	
				--Target
				target_steamId = Plugin:GetId( TargetClient ),
				target_team = Target:GetTeamType(),
				target_weapon = TargetWeapon,
				target_lifeform = Target:GetMapName(),
				target_hp = Target:GetHealth(),
				target_armor = Target:GetArmorAmount(),
				targetx = StringFormat( "%.4f", tOrigin.x),
				targety = StringFormat( "%.4f", tOrigin.y),
				targetz = StringFormat( "%.4f", tOrigin.z),
				target_lifetime = StringFormat( "%.4f", Shared.GetTime() - Target:GetCreationTime() )	
			}
			self:AddLog( Params )       
		end
	elseif Target then --suicide
		local TargetClient = Target:GetClient()     
		local TargetWeapon = "none"
		local tOrigin = Target:GetOrigin()
		local AttackerClient = TargetClient --easy way out        
		local aOrigin = tOrigin
		local Attacker = Target
		local Params =
			{                
				--general
				action = "death",	
				
				--Attacker
				attacker_weapon = "self",
				attacker_lifeform = Attacker:GetMapName(),
				attacker_steamId = Plugin:GetId(AttackerClient),
				attacker_team = HasMixin( Attacker, "Team" ) and Attacker:GetTeamType() or kNeutralTeamType,
				attacker_hp = Attacker:GetHealth(),
				attacker_armor = Attacker:GetArmorAmount(),
				attackerx = StringFormat( "%.4f", aOrigin.x ),
				attackery = StringFormat( "%.4f", aOrigin.y ),
				attackerz = StringFormat( "%.4f", aOrigin.z ),
				
				--Target
				target_steamId = Plugin:GetId( TargetClient ),
				target_team = Target:GetTeamType(),
				target_weapon = TargetWeapon,
				target_lifeform = Target:GetMapName(),
				target_hp = Target:GetHealth(),
				target_armor = Target:GetArmorAmount(),
				targetx = StringFormat( "%.4f", tOrigin.x ),
				targety = StringFormat( "%.4f", tOrigin.y ),
				targetz = StringFormat( "%.4f", tOrigin.z ),
				target_lifetime = StringFormat( "%.4f", Shared.GetTime() - Target:GetCreationTime() )
			}            
		self:AddLog( Params )  
	end
end

--Check Killstreaks
function Plugin:AddKill( AttackerSteamId )
	for _,PlayerInfo in ipairs(self.PlayersInfos) do	
		if PlayerInfo.steamId == AttackerSteamId then	
			PlayerInfo.killstreak = PlayerInfo.killstreak + 1	
			if PlayerInfo.killstreak > PlayerInfo.highestKillstreak then
				PlayerInfo.highestKillstreak = PlayerInfo.killstreak
			end
			return    
		end            
	end
end

--Events end

--Log functions

--add to log
function Plugin:AddLog( Params )    
	if self.RoundFinished == 1 or not Params then return end
	
	if not self.Log then self.Log = {} end
	if not self.Log[ self.LogPartNumber ] then self.Log[ self.LogPartNumber ] = "" end

	if Shared.GetCheatsEnabled() and self.StatsEnabled then 
		self.StatsEnabled = false
		Shine:Notify( nil, "", "NS2Stats", "Cheats were enabled! NS2Stats will disable itself now!")
	end
	
	Params.time = Shared.GetGMTString(false)
	Params.gametime = Shared.GetTime() - self.GameStartTime
	Plugin.Log[Plugin.LogPartNumber] = StringFormat("%s%s\n",Plugin.Log[Plugin.LogPartNumber], JsonEncode(Params))	
	
	--avoid that log gets too long
	if StringLen( self.Log[ self.LogPartNumber ] ) > 160000 then
		self.LogPartNumber = self.LogPartNumber + 1    
		if self.StatsEnabled then self:SendData() end        
	end
end

--add playerlist to log
function Plugin:AddPlayersToLog( Type ) 
	local Temp = {}
	
	if Type == 0 then
		Temp.action = "player_list_start"
	else
		Temp.action = "player_list_end"
	end

	--reset codes
	for p = 1, #self.PlayersInfos do	
		local Player = self.PlayersInfos[ p ]	
		Player.code = 0
	end
	
	Temp.list = self.PlayersInfos    
	self:AddLog( Temp )
end

--Add server infos
function Plugin:AddServerInfos( Params )
	local Mods = {}
	local GetMod = Server.GetActiveModId
	for i = 1, Server.GetNumActiveMods() do
		local Mod = GetMod( i )
		for j = 1, Server.GetNumMods() do
			if Server.GetModId(j) == Mod then
				Mods[ i ] = Server.GetModTitle( j )
				break
			end
		end 
	end
	
	Params.action = "game_ended"
	Params.statsVersion = Plugin.Version
	Params.serverName = Server.GetName()
	Params.gamemode = Shine.GetGamemode()
	Params.successfulSends = self.SuccessfulSends 
	Params.resendCount = self.ResendCount
	Params.mods = mods
	Params.awards = self.Awards
	Params.tags = self.Config.Tags    
	Params.private = self.Config.Competitive
	Params.autoarrange = false --use Shine plugin settings later?
	local Ip = IPAddressToString( Server.GetIpAddress() ) 
	if not StringFind( Ip, ":" ) then Ip = StringFormat( "%s:%s", Ip, Server.GetPort() ) end
	Params.serverInfo =
	{
		password = "",
		IP = Ip,
		count = 30 --servertick?
	}    
	self:AddLog( Params )
end

--send Log to NS2Stats Server
function Plugin:SendData()
	if not self.StatsEnabled or self.Working or self.LogPartNumber <= self.LogPartToSend and self.RoundFinished ~= 1 then return end
	
	self.Working = true
	
	local Params =
	{
		key = self.Config.ServerKey,
		roundlog = self.Log[ Plugin.LogPartToSend ],
		part_number = self.LogPartToSend ,
		last_part = self.RoundFinished,
		map = Shared.GetMapName(),
	}
	
	Shine.TimedHTTPRequest( StringFormat( "%s/api/sendlog", self.Config.WebsiteUrl ), "POST", Params, function( Response ) Plugin:OnHTTPResponseFromSend( Response ) end, function()
		Plugin.working = false 
		Plugin.ResendCount = Plugin.ResendCount + 1 
		if Plugin.ResendCount > 5 then 
			self.StatsEnabled = false
			Notify( "Ns2Stats.com seems to be not avaible at the moment. Disabling stats sending" )
			return
		end
		Plugin:SendData()
	end, 30)
end

--Analyze the answer of server
function Plugin:OnHTTPResponseFromSend( Response )	
	local Message = JsonDecode( Response )
	
	if Message then        
		if Message.other then
			Notify( StringFormat( "[NSStats]: %s", Message.other ))
			return
		end
	
		if Message.error == "NOT_ENOUGH_PLAYERS" then
			Notify( "[NS2Stats]: Send failed because of too less players " )
			return
		end	

		if Message.link then
			local Link = StringFormat( "%s%s", self.Config.WebsiteUrl, Message.link)
			Shine:Notify( nil, "", "", StringFormat("Round has been saved to NS2Stats : %s" , Link))
			self.Config.Lastroundlink = Link
			self:SaveConfig()
			return
		end
	end
	
	if StringLen( Response ) > 1 and StringFind( Response, "LOG_RECEIVED_OK", nil, true ) then
		self.Log[ Plugin.LogPartToSend ] = nil
		self.LogPartToSend = Plugin.LogPartToSend  + 1
		self.SuccessfulSends  = self.SuccessfulSends  + 1
		self.Working = false
		Plugin:SendData()
	else --we couldn't reach the NS2Stats Servers
		self.Working = false
		self:SimpleTimer( 5, function() self:SendData() end)
	end    
end

--Log end 

--Player table functions
	
--add Player to table
function Plugin:AddPlayerToTable( Client )
	if not Client then return end
	local Entry = self:CreatePlayerEntry( Client )
	if not Entry then return end
	
	TableInsert( self.PlayersInfos, Entry )    
end

--create new entry
function Plugin:CreatePlayerEntry(Client)
	if not Client.GetControllingPlayer then
		Notify( "[NS2Stats Debug]: Tried to create nil Player" )
		return
	end
	local Player = Client:GetControllingPlayer()
	if not Player then return end
	local PlayerInfo = {}
	
	PlayerInfo.teamnumber = Player:GetTeamNumber() or 0
	PlayerInfo.Lifeform = Player:GetMapName()
	PlayerInfo.score = 0
	PlayerInfo.assists = 0
	PlayerInfo.deaths = 0
	PlayerInfo.kills = 0
	PlayerInfo.totalKills = Player.totalKills or 0
	PlayerInfo.totalAssists = Player.totalAssists or 0
	PlayerInfo.totalDeaths = Player.totalDeaths or 0
	PlayerInfo.playerSkill = Player.playerSkill or 0
	PlayerInfo.totalScore = Player.totalScore or 0
	PlayerInfo.totalPlayTime = Player.totalPlayTime or 0
	PlayerInfo.playerLevel = Player.playerLevel or 0   
	PlayerInfo.steamId = Plugin:GetId(Client) or 0
	PlayerInfo.name = Player:GetName() or ""
	PlayerInfo.ping = Client:GetPing() or 0
	PlayerInfo.isbot = Client:GetIsVirtual() or false
	PlayerInfo.isCommander = false
	PlayerInfo.dc = false
	PlayerInfo.total_constructed = 0
	PlayerInfo.weapons = {}
	PlayerInfo.killstreak = 0
	PlayerInfo.highestKillstreak = 0
	PlayerInfo.jumps = 0
			
	--for bots
	if PlayerInfo.isbot then
		PlayerInfo.ping = 0
		PlayerInfo.ipaddress = "127.0.0.1"
	else
		PlayerInfo.ping = Client:GetPing()
		PlayerInfo.ipaddress = IPAddressToString( Server.GetClientAddress( Client ))
	end
	
	return PlayerInfo
end

--Update Player Entry
function Plugin:UpdatePlayerInTable(Client, Player, PlayerInfo)
	if PlayerInfo.dc then return end
	
	PlayerInfo.name = Player:GetName()
	PlayerInfo.score = Player.score or 0
	PlayerInfo.assists = Player.assistkills or 0
	PlayerInfo.deaths = Player.deaths or 0
	PlayerInfo.kills = Player.kills or 0
	PlayerInfo.totalKills = Player.totalKills or 0
	PlayerInfo.totalAssists = Player.totalAssists or 0
	PlayerInfo.totalDeaths = Player.totalDeaths or 0
	PlayerInfo.playerSkill = Player.playerSkill or 0
	PlayerInfo.totalScore = Player.totalScore or 0
	PlayerInfo.totalPlayTime = Player.totalPlayTime or 0
	PlayerInfo.playerLevel = Player.playerLevel or 0
	PlayerInfo.isCommander = Player:GetIsCommander() or false
	--if Player is dead
	if not Player:GetIsAlive() then
		PlayerInfo.killstreak = 0
	end
	if not PlayerInfo.isbot then PlayerInfo.ping = Client:GetPing() end
end

--All search functions
function Plugin:GetTeamCommanderSteamid( TeamNumber )
	for _, PlayerInfo in ipairs( self.PlayersInfos ) do
		if PlayerInfo.isCommander and PlayerInfo.teamnumber == TeamNumber then
			return PlayerInfo.steamId
		end	
	end
	return 0
end

function Plugin:GetPlayerByName( Name )
	if not Name then return end
	for _, PlayerInfo in ipairs( self.PlayersInfos ) do        
		if PlayerInfo.name == Name then return PlayerInfo end	
	end
	return
end

function Plugin:GetPlayerByClient( Client )
	if not Client then return end
	
	if Client.GetUserId then
		local steamId = self:GetId( Client )
		for _, PlayerInfo in ipairs( self.PlayersInfos ) do	
			if PlayerInfo.steamId == steamId then return PlayerInfo end
		end
	elseif Client.GetControllingPlayer then
		local Player = Client:GetControllingPlayer()
		local name = Player:GetName()
		self:GetPlayerByName( Name )
	end
	
	return
end
--Player Table end

--GetIds
function Plugin:GetId( Client )
	if Client and Client.GetUserId then     
		if Client:GetIsVirtual() then return Plugin:GetIdbyName( Client:GetControllingPlayer():GetName() ) or 0
		else return Client:GetUserId() end
	end
	return
end

--For Bots
Plugin.FakeIds = {}
function Plugin:GetIdbyName( Name )    
	if not Name then return end
	
	--disable Onlinestats
	if self.StatsEnabled then
		Notify( "NS2Stats won't store game with bots. Disabling online stats now!" )
		self.StatsEnabled = false 
	end
	
	if self.FakeIds[ Name ] then return self.FakeIds[ Name ] end
	
	local NewId = ""
	local Letters = " ()[]+-*!_-%$1234567890aAbBcCdDeEfFgGhHiIjJkKlLmMnNoOpPqQrRsStTuUvVwWxXyYzZ"
	
	--to differ between e.g. name and name (2)   
	local Input = StringReverse( Name )
	
	for i = 1, 6 do
		local Num = 99
		if #Input >=i then
			local Char = StringSub( Input, i, i )
			Num = StringFind( Letters, Char, nil, true) or 99
			if Num < 10 then Num = 80 + Num end
		end
		NewId = StringFormat( "%s%s", NewId, Num )
	end
	
	
	--make a int
	NewId = tonumber( NewId )
	
	self.FakeIds[ Name ] = NewId    
	return NewId
end
--Ids end

--Timer functions

--Update Weapontable
function Plugin:UpdateWeaponTable() 
	if not self.RoundStarted then return end
	for _, Client in ipairs( Shine.GetAllClients() ) do
		Plugin:UpdateWeaponData( Client )
	end
end   

function Plugin:UpdateWeaponData( Client ) 
	if not Client then return end
	
	local PlayerInfo = self:GetPlayerByClient( Client )
	if not PlayerInfo then return end
	
	local Player = Client:GetControllingPlayer()
	if not Player then return end

	local Weapon = Player.GetActiveWeaponName and Player:GetActiveWeaponName() or "none"
	Weapon = StringLower( Weapon )
	
	local FoundId
	for i = 1, #PlayerInfo.weapons do
		if PlayerInfo.weapons[ i ].name == Weapon then FoundId = i end
	end
	
	if FoundId then
		PlayerInfo.weapons[ FoundId ].time = PlayerInfo.weapons[ FoundId ].time + 1
	else --add new weapon
		TableInsert( PlayerInfo.weapons,
		{
			name = Weapon,
			time = 1,
			miss = 0,
			player_hit = 0,
			structure_hit = 0,
			player_damage = 0,
			structure_damage = 0
		})
	end
end

--send Status report to NS2Stats
function Plugin:SendServerStatus( GameState )
	if self.RoundFinished == 1 then return end
	local stime = Shared.GetGMTString( false )
	local gameTime = Shared.GetTime() - self.GameStartTime
	local Params =
	{
		key = self.Config.ServerKey,
		players = JsonEncode( self.PlayersInfos ),
		state = GameState,
		time = stime,
		gametime = gameTime,
		map = Shared.GetMapName(),
	}
	HTTPRequest( StringFormat( "%s/api/sendstatus", self.Config.WebsiteUrl ), "POST", Params, function() end )	
end
--Timer end

-- Other ns2stats functions

--gets server key
function Plugin:AcceptKey( Response )
		if not Response or Response == "" then
			Notify( "NS2Stats: Unable to receive unique key from server, stats wont work yet. " )
			Notify( "NS2Stats: Server restart might help." )
		else
			local Decoded = JsonDecode( Response )
			if Decoded and Decoded.key then
				self.Config.ServerKey = Decoded.key
				Notify( StringFormat("NS2Stats: Key %s has been assigned to this server ", self.Config.ServerKey ))
				Notify( "NS2Stats: You may use admin command sh_verity to claim this server." )
				Notify( "NS2Stats setup complete." )
				self.StatsEnabled = true
				self:SaveConfig()                                              
			else
				Notify( "NS2Stats: Unable to receive unique key from server, stats wont work yet." )
				Notify( "NS2Stats: Server restart might help." )
				Notify( StringFormat( "NS2Stats: Server responded: %s", Response ))
			end
		end
end

function Plugin:GetServerId()
	if not self.ServerId then
		HTTPRequest(StringFormat("%s/api/server?key=%s", self.Config.WebsiteUrl,self.Config.ServerKey), "GET", function(Response)
			local Data = JsonDecode( Response )
			if not Data then return end
			if Data.error == "Invalid server key. Server not found." then
				self.StatsEnabled = false
				HTTPRequest( StringFormat( "%s/api/generateKey/?s=7g94389u3r89wujj3r892jhr9fwj", self.Config.WebsiteUrl), "GET", function( Response ) self:AcceptKey( Response ) end )
			else
				self.ServerId = Data.id or "" 
			end         
		end)
	end
	return self.ServerId
end

function Plugin:OnSuspend()
	self.StatsEnabled = false
	Shine:Notify( nil, "", "NS2Stats", "It's not possible to suspend NS2Stats, instead it will disable itself now!")
end

--Other Ns2Stat functions end

--Commands
function Plugin:CreateCommands()    
	local ShowPStats = self:BindCommand( "sh_showplayerstats", { "showplayerstats", "showstats" }, function( Client, Target )
		local target = Target or Client
		HTTPRequest( StringFormat("%s/api/oneplayer?ns2_id=%s", self.Config.WebsiteUrl, Plugin:GetId( target )), "GET", function( Response )
			local Data = JsonDecode( Response )
			local PlayerId = ""
			if Data then PlayerId = Data.id or "" end
			local URL = StringFormat( "%s/Player/Player/%s", self.Config.WebsiteUrl, PlayerId )
			Server.SendNetworkMessage( Client, "Shine_Web", { URL = URL, Title = "My Stats" }, true )
			end )
	end, true )
	ShowPStats:AddParam{ Type = "client", Optional = true, Default = false }
	ShowPStats:Help( "<optional player> Shows stats from the given player or yourself" )
	
	local ShowLastRound = self:BindCommand( "sh_showlastround", { "showlastround", "lastround" }, function(Client)
		if Plugin.Config.Lastroundlink == "" then Shine:Notify( Client, "", "", "[NS2Stats]: Last round was not saved at NS2Stats" )       
		else Server.SendNetworkMessage( Client, "Shine_Web", { URL = Plugin.Config.Lastroundlink, Title = "Last Rounds Stats" }, true )
		end
	end, true )   
	ShowLastRound:Help("Shows stats of last round played on this server")
	
	local ShowSStats = self:BindCommand( "sh_showserverstats", "showserverstats", function(Client)
		local URL = StringFormat( "%s/server/server/%s",self.Config.WebsiteUrl,Plugin:GetServerId() )
		Server.SendNetworkMessage( Client, "Shine_Web", { URL = URL, Title = "Server Stats" }, true )
	end, true )
	ShowSStats:Help("Shows server stats") 
	
	local ShowLStats = self:BindCommand( "sh_showlivestats", "showlivestats", function(Client)
		local URL = StringFormat( "%s/live/scoreboard/%s", self.Config.WebsiteUrl, Plugin:GetServerId() )
		Server.SendNetworkMessage( Client, "Shine_Web", { URL = URL, Title = "Scoreboard" }, true )
	end, true )
	ShowLStats:Help( "Shows server live stats" )
	
	local Verify = self:BindCommand( "sh_verify", {"verifystats","verify"},function(Client)
			HTTPRequest(StringFormat("%s/api/verifyServer/%s?s=479qeuehq2829&key=%s", self.Config.WebsiteUrl, Plugin:GetId(Client), self.Config.ServerKey), "GET",
			function( Response ) ServerAdminPrint( Client, Response ) end )
	end )
	Verify:Help( "Sets yourself as serveradmin at NS2Stats.com" )
	
	local Tag = self:BindCommand( "sh_addtag", "addtag", function(Client,tag)
		TableInsert(Plugin.Config.Tags, tag)
		Notify( StringFormat( "[NS2Stats]: %s  has been added as Tag to this roundlog", tag ))
	end )    
	Tag:AddParam{ Type = "string", TakeRestOfLine = true, Error = "Please specify a tag to be added.", MaxLength = 30 }
	Tag:Help( "Adds the given tag to the Stats" )
	
	local Debug = self:BindCommand( "sh_statsdebug", "statsdebug", function( Client )
		Shine:AdminPrint( Client, "NS2Stats Debug Report:" )
		Shine:AdminPrint( Client, StringFormat( "Ns2Stats is%s sending data to website", Plugin.StatsEnabled and "" or " not"))
		Shine:AdminPrint( Client, StringFormat( "Currently uploading log part: %s", Plugin.working and "Yes" or "No"))
		Shine:AdminPrint( Client, StringFormat( "%s Players in PlayerTable.", #Plugin.PlayersInfos ))
		Shine:AdminPrint( Client, StringFormat( "Current Logparts %s / %s . Length of ToSend: %s", Plugin.LogPartToSend, Plugin.LogPartNumber, StringLen( Plugin.Log[ Plugin.LogPartToSend ] )))
	end, true )
	Debug:Help( "Prints some ns2stats debug values into the console (only usefull for debugging)" )
end

--Awards
function Plugin:MakeAwardsList()
	self:AddAward( Plugin:AwardMostDamage() )
	self:AddAward( Plugin:AwardMostKillsAndAssists() )
	self:AddAward( Plugin:AwardMostConstructed() )
	self:AddAward( Plugin:AwardMostStructureDamage() )
	self:AddAward( Plugin:AwardMostPlayerDamage() )
	self:AddAward( Plugin:AwardBestAccuracy() )
	self:AddAward( Plugin:AwardMostJumps() )
	self:AddAward( Plugin:AwardHighestKillstreak() )
end

function Plugin:SendAwardListToClients()
	--reset and generates Awardlist
	self.NextAwardId = 0
	self.Awards = {}
	self:MakeAwardsList()
		
	--send Highest 10 Rating Awards
	table.sort(self.Awards, function( a, b )
		return a.rating > b.rating
	end)
	
	local AwardMessage = {}
	AwardMessage.Message = ""    
	AwardMessage.Duration = Plugin.Config.AwardMsgTime
	AwardMessage.ColourR = Plugin.Config.AwardMsgColour[1]
	AwardMessage.ColourG = Plugin.Config.AwardMsgColour[2]
	AwardMessage.ColourB = Plugin.Config.AwardMsgColour[3]
	
	for i = 1, self.Config.ShowNumAwards do
		if i > #self.Awards then break end
		if self.Awards[ i ].message then 
			AwardMessage.Message = StringFormat( "%s%s\n", AwardMessage.Message, self.Awards[ i ].message )
		end
	end 
	self:SendNetworkMessage( nil, "StatsAwards", AwardMessage, true )
end

function Plugin:AddAward(Award)
	self.NextAwardId = self.NextAwardId + 1
	Award.id = self.NextAwardId
	
	self.Awards[ #self.Awards + 1 ] = Award
end

function Plugin:AwardMostDamage()
	local HighestDamage = 0
	local HighestPlayer = "nobody"
	local HighestSteamId = ""
	local Rating = 0
	
	for _, PlayerInfo in ipairs( self.PlayersInfos ) do
		local TotalDamage = 0
		
		for i=1, #PlayerInfo.weapons do
			TotalDamage = TotalDamage + PlayerInfo.weapons[ i ].structure_damage
			TotalDamage = TotalDamage + PlayerInfo.weapons[ i ].player_damage
		end
		
		if Floor( TotalDamage ) > Floor( HighestDamage ) then
			HighestDamage = TotalDamage
			HighestPlayer = PlayerInfo.name
			HighestSteamId = PlayerInfo.steamId
		end
	end
	
	Rating = ( HighestDamage + 1 ) / 350
	
	return { steamId = HighestSteamId, rating = Rating, message = StringFormat("Most Damage done by %s with total Damage of %s !", HighestPlayer, Floor( HighestDamage )) }
end

function Plugin:AwardMostKillsAndAssists()
	local Rating = 0
	local HighestTotal = 0
	local HighestPlayer = "Nobody"
	local HighestSteamId = ""
	
	for _, PlayerInfo in ipairs( self.PlayersInfos ) do
		local Total = PlayerInfo.kills + PlayerInfo.assists
		if Total > HighestTotal then
			HighestTotal = Total
			HighestPlayer = PlayerInfo.name
			HighestSteamId = PlayerInfo.steamId
		end
	
	end
	
	Rating = HighestTotal
	
	return { steamId = HighestSteamId, rating = Rating, message = StringFormat( "%s is deathbringer with total of %s  kills and assists!", HighestPlayer, HighestTotal ) }
end

function Plugin:AwardMostConstructed()
	local HighestTotal = 0
	local Rating = 0
	local HighestPlayer = "was not present"
	local HighestSteamId = ""
	
	for _, PlayerInfo in ipairs( self.PlayersInfos ) do
		if PlayerInfo.total_constructed > HighestTotal then
			HighestTotal = PlayerInfo.total_constructed
			HighestPlayer = PlayerInfo.name
			HighestSteamId = PlayerInfo.steamId
		end
	end
	
	Rating = ( HighestTotal + 1 ) / 30
	
	return { steamId = HighestSteamId, rating = Rating, message = StringFormat( "Bob the builder: %s !", HighestPlayer ) }
end

function Plugin:AwardMostStructureDamage()
	local HighestTotal = 0
	local HighestPlayer = "nobody"
	local HighestSteamId = ""
	local Rating = 0
	
	for _, PlayerInfo in ipairs( self.PlayersInfos ) do
		local Total = 0
		
		for i=1, #PlayerInfo.weapons do
			Total = Total + PlayerInfo.weapons[ i ].structure_damage
		end
		
		if Floor( Total ) > Floor( HighestTotal ) then
			HighestTotal = Total
			HighestPlayer = PlayerInfo.name
			HighestSteamId = PlayerInfo.steamId
		end
	end
	
	Rating = ( HighestTotal + 1 ) / 150
	
	return {steamId = HighestSteamId, rating = Rating, message = StringFormat( "Demolition man: %s with %s  Structure Damage.", HighestPlayer, Floor(HighestTotal))}
end

function Plugin:AwardMostPlayerDamage()
	local HighestTotal = 0
	local HighestPlayer = "nobody"
	local HighestSteamId = ""
	local Rating = 0
	
	for _, PlayerInfo in ipairs( self.PlayersInfos ) do
		local Total = 0
		
		for i = 1, #PlayerInfo.weapons do
			Total = Total + PlayerInfo.weapons[ i ].player_damage
		end
		
		if Floor( Total ) > Floor( HighestTotal ) then
			HighestTotal = Total
			HighestPlayer = PlayerInfo.name
			HighestSteamId = PlayerInfo.steamId
		end
	end
	
	Rating = ( HighestTotal + 1 ) / 90
	
	return { steamId = HighestSteamId, rating = Rating, message = StringFormat( " %s was spilling blood worth of %s Damage.", HighestPlayer, Floor( HighestTotal )) }
end

function Plugin:AwardBestAccuracy()
	local HighestTotal = 0
	local HighestPlayer = "nobody"
	local HighestSteamId = ""
	local HighestTeam = 0
	local Rating = 0
	
	for _, PlayerInfo in ipairs( self.PlayersInfos ) do
		local Total = 0
		
		for i = 1, #PlayerInfo.weapons do
			if i == 1 then 
				Total = PlayerInfo.weapons[ i ].player_hit / ( PlayerInfo.weapons[ i ].miss + 1 )
			else    
				Total = 0.5 * ( Total + PlayerInfo.weapons[ i ].player_hit / ( PlayerInfo.weapons[ i ].miss + 1 ) )
			end    
		end
		
		if Total > HighestTotal then
			HighestTotal = Total
			HighestPlayer = PlayerInfo.name
			HighestTeam = PlayerInfo.teamnumber
			HighestSteamId = PlayerInfo.steamId
		end
	end
	
	Rating = HighestTotal * 100
	
	if HighestTeam == 2 then
		return {steamId = HighestSteamId, rating = Rating, message = StringFormat( "Versed: %s", HighestPlayer )}
	else --marine or ready room
		return { steamId = HighestSteamId, rating = Rating, message = StringFormat( "Weapon specialist: %s", HighestPlayer )}
	end
end

function Plugin:AwardMostJumps()
	local HighestTotal = 0
	local HighestPlayer = "nobody"
	local HighestSteamId = ""
	local Rating = 0
	
	for _, PlayerInfo in ipairs(self.PlayersInfos) do
	
		local Total = PlayerInfo.jumps or 0
	
		if Total > HighestTotal then
			HighestTotal = Total
			HighestPlayer = PlayerInfo.name
			HighestSteamId = PlayerInfo.steamId
		end
	end
	
	Rating = HighestTotal / 30
		
	return { steamId = HighestSteamId, rating = Rating, message = StringFormat( "%s is jump maniac with %s jumps!", HighestPlayer,  HighestTotal )}
	
end

function Plugin:AwardHighestKillstreak()
	local HighestTotal = 0
	local HighestPlayer = "nobody"
	local HighestSteamId = ""
	
	for _, PlayerInfo in ipairs( self.PlayersInfos ) do				
		local Total = PlayerInfo.highestKillstreak or 0
		
		if Total > HighestTotal then
			HighestTotal = Total
			HighestPlayer = PlayerInfo.name
			HighestSteamId = PlayerInfo.steamId
		end
	end
	
	local Rating = HighestTotal
		
	return { steamId = HighestSteamId, rating = Rating, message = StringFormat( "%s became unstoppable with streak of %s kills", HighestPlayer, HighestTotal )}
end

--Url Method
function Plugin:GetStatsURL()
	return self.Config.WebsiteUrl
end 

function Plugin:Cleanup()	
	self.StatsEnabled = nil
	self.SuccessfulSends = nil
	self.ResendCount = nil
	self.Working = nil
	self.Log = nil
	self.LogPartNumber = nil
	self.LogPartToSend  = nil
	self.GameStartTime = nil
	self.RoundFinished = nil
	self.NextAwardId = nil
	self.Awards = nil
	self.RoundStarted = nil
	self.CurrentGameState = nil
	self.PlayersInfos = nil
	self.ItemInfos = nil
	self.BuildingsInfos = nil
	self.OldUpgrade = nil
	self.FakeIds = nil
	self.DoDamageHeathChange = nil
	self.HitCache = nil
	self.FireCache = nil
	self.DetonateCache = nil
	
	self.BaseClass.Cleanup( self )

	self.Enabled = false
end