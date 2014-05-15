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
local StringLower = string.lower
local StringReverse = string.UTF8Reverse

local TableInsert = table.insert

local GetOwner = Server.GetOwner

local JsonEncode = json.encode
local JsonDecode = json.decode

local HTTPRequest = Shared.SendHTTPRequest

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
}
Plugin.CheckConfig = true

--All needed Hooks

Shine.Hook.SetupClassHook( "DamageMixin", "DoDamage", "OnDamageDealt", "PassivePre" )
Shine.Hook.SetupClassHook( "ResearchMixin", "TechResearched", "OnTechResearched", "PassivePost" )
Shine.Hook.SetupClassHook( "ResearchMixin", "SetResearching", "OnTechStartResearch", "PassivePre" )
Shine.Hook.SetupClassHook( "ConstructMixin", "SetConstructionComplete", "OnFinishedBuilt", "PassivePost" )
Shine.Hook.SetupClassHook( "ResearchMixin", "OnResearchCancel", "AddUpgradeAbortedToLog", "PassivePost" )
Shine.Hook.SetupClassHook( "UpgradableMixin", "RemoveUpgrade","AddUpgradeLostToLog", "PassivePost" )
Shine.Hook.SetupClassHook( "ResourceTower", "CollectResources", "OnTeamGetResources", "PassivePost" )
Shine.Hook.SetupClassHook( "DropPack", "OnUpdate", "OnPickableItemDropped", "PassivePre" )
Shine.Hook.SetupClassHook( "Player", "OnJump", "OnPlayerJump", "PassivePost" )
Shine.Hook.SetupClassHook( "PlayerInfoEntity", "UpdateScore", "OnPlayerScoreChanged", "PassivePost" )
Shine.Hook.SetupClassHook( "PlayerBot", "UpdateNameAndGender","OnBotRenamed", "PassivePost" )
Shine.Hook.SetupClassHook( "NS2Gamerules", "OnEntityDestroy", "OnEntityDestroy", "PassivePre" )
Shine.Hook.SetupClassHook( "NS2Gamerules", "ResetGame", "OnGameReset", "PassivePre" )
--NS2Ranking
Shine.Hook.SetupClassHook( "PlayerRanking", "GetTrackServer", "EnableNS2Ranking", "ActivePre" )

function Plugin:Initialise()
    self.Enabled = true
    
    --ceate values
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
    --to update Weapondatas
    self:CreateTimer( "WeaponUpdate", 1, -1, function()
       self:UpdateWeaponTable()
    end )
    
    -- every 30 sec send Server Status + Devour   
    if self.Config.StatusReport then
       self:CreateTimer( "SendStatus" , 30, -1, function() self:SendServerStatus( self.CurrentGameState ) end) --Plugin:DevourSendStatus()
    end
    
    /* every 0.25 sec create Devour datas
    self:CreateTimer( "Devour", 0.25, -1, function()
        if self.RoundStarted then
            Plugin:CreateDevourMovementFrame()
            if self.Devour.Frame % 20 == 0 then Plugin:CreateDevourEntityFrame() end
            self.Devour.Frame = self.Devour.Frame + 1
        end 
    end)
    */
    return true
end

-- NS2VanillaStats
function Plugin:EnableNS2Ranking()
    return self.Config.EnableHiveStats and self.StatsEnabled and Shine.GetGamemode() == "ns2"
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
    
    --Reset Devour
    self.Devour = {}
    self.Devour.Frame = 0
    self.Devour.Entities = {}
    self.Devour.MovementInfos = {}
    
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
        
        local InitialHiveTechIdString = "None"
        if Gamerules.initialHiveTechId then
        	InitialHiveTechIdString = EnumToString( kTechId, Gamerules.initialHiveTechId )
        end
          
        local Params =
            {
                version = ToString( Shared.GetBuildNumber() ),
                winner = WinningTeam:GetTeamNumber(),
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
    
    if not PlayerInfo then Plugin:AddPlayerToTable( Client )  
    else PlayerInfo.dc = false end
    
    self:SendNetworkMessage( Client, "StatsConfig", { WebsiteApiUrl = StringFormat( "%s/api", self.Config.WebsiteUrl ), SendMapData = self.Config.SendMapData } , true )
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

--Player shoots weapon
function Plugin:OnDamageDealt( DamageMixin, Damage, Target, Point )
	if not self.RoundStarted then return end
	
    local Attacker 
    if DamageMixin:isa("Player") then
        Attacker = DamageMixin
    elseif DamageMixin:GetParent() and DamageMixin:GetParent():isa( "Player" ) then
        Attacker = DamageMixin:GetParent()
    elseif HasMixin( DamageMixin, "Owner" ) and DamageMixin:GetOwner() and DamageMixin:GetOwner():isa( "Player" ) then
        Attacker = DamageMixin:GetOwner()
    else return end
    
    local DamageType = kDamageType.Normal
    if DamageMixin.GetDamageType then DamageType = DamageMixin:GetDamageType()
    elseif HasMixin( DamageMixin, "Tech" ) then DamageType = LookupTechData( DamageMixin:GetTechId(), kTechDataDamageType, kDamageType.Normal) end
            
    local Doer = DamageMixin
    
    local Hit = false
    if Target and HasMixin( Target, "Live" ) and Damage > 0 then
    
        local armorUsed = 0
        local healthUsed = 0        
        Damage, armorUsed, healthUsed = GetDamageByType( Target, Attacker, Doer, Damage, DamageType, Point )
        
        if Damage > 0 and Attacker:isa( "Player" )then
            Plugin:AddHitToLog( Target, Attacker, Doer, Damage, DamageType )
            Hit = true
        end            
    end
    
    if not Hit then self:AddMissToLog( Attacker ) end 
end

--add Hit
function Plugin:AddHitToLog( Target, Attacker, Doer, Damage, DamageType )
    if Target:isa( "Player" ) then
        local AttackerId = Plugin:GetId( Attacker:GetClient() )
        local TargetId = Plugin:GetId( Target:GetClient() )        
        if not AttackerId or not TargetId then return end
        
        local aOrigin = Attacker:GetOrigin()
        local tOrigin = Target:GetOrigin()
        if not Attacker:GetIsAlive() then aOrigin = tOrigin end
        
        local Weapon = "none"
        if Target:GetActiveWeapon() then
            Weapon = StringLower( Target:GetActiveWeapon():GetMapName() ) end
       
        local Params =
        {
            --general
            action = "hit_player",	
            
            --Attacker
            attacker_steamId = AttackerId,
            attacker_team = Attacker:GetTeamNumber(),
            attacker_weapon = StringLower( Doer:GetMapName() ),
            attacker_lifeform =  StringLower( Attacker:GetMapName() ),
            attacker_hp = Attacker:GetHealth(),
            attacker_armor = Attacker:GetArmorAmount(),
            attackerx = StringFormat( "%.4f", aOrigin.x ),
            attackery = StringFormat( "%.4f", aOrigin.y ),
            attackerz = StringFormat( "%.4f", aOrigin.z ),
            
            --Target
            target_steamId = TargetId,
            target_team = Target:GetTeamNumber(),
            target_weapon = Weapon,
            target_lifeform = StringLower( Target:GetMapName() ),
            target_hp = Target:GetHealth(),
            target_armor = Target:GetArmorAmount(),
            targetx = StringFormat( "%.4f", tOrigin.x ),
            targety = StringFormat( "%.4f", tOrigin.y ),
            targetz = StringFormat( "%.4f", tOrigin.z ),
            
            damageType = DamageType,
            damage = Damage            
        }
        self:AddLog( Params )
        self:WeaponsAddHit( Attacker, StringLower( Doer:GetMapName()), Damage )
        
    else --Target is a Structure
        local tOrigin = Target:GetOrigin()
        local aOrigin = Attacker:GetOrigin()
        
        local Params =
        {
            
            --general
            action = "hit_structure",	
            
            --Attacker
            attacker_steamId =  AttackerId,
            attacker_team = Attacker:GetTeamNumber(),
            attacker_weapon = StringLower( Doer:GetMapName() ),
            attacker_lifeform = StringLower( Attacker:GetMapName() ),
            attacker_hp = Attacker:GetHealth(),
            attacker_armor = Attacker:GetArmorAmount(),
            attackerx = StringFormat( "%.4f",  aOrigin.x ),
            attackery = StringFormat( "%.4f",  aOrigin.y ),
            attackerz = StringFormat( "%.4f",  aOrigin.z ),
                        
            structure_id = Target:GetId(),
            structure_name = StringLower( Target:GetMapName() ),
            structure_x = StringFormat( "%.4f", tOrigin.x ),
            structure_y = StringFormat( "%.4f", tOrigin.y ),
            structure_z = StringFormat( "%.4f", tOrigin.z ),	

            damageType = DamageType,
            damage = Damage
        }        
        self:AddLog( Params )
        self:WeaponsAddStructureHit( Attacker, StringLower( Doer:GetMapName() ), Damage )
    end
end

--Add miss
function Plugin:AddMissToLog( Attacker )
    local Client = Attacker:GetClient()
    if not Client then return end

    local Player = Plugin:GetPlayerByClient( Client )
    if not Player then return end

    local Weapon = StringLower( Attacker:GetActiveWeaponName() ) or "none"
    
    --gorge fix
    if Weapon == "spitspray" then
        Weapon = "spit"
    end
    
    self:WeaponsAddMiss( Client, Weapon )
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
--OnDamagedealt end

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

--Item is dropped
function Plugin:OnPickableItemCreated( Item, TechId, Player ) 
    
    local Itemname = EnumToString( kTechId, TechId )
    if not Itemname or Itemname == "None" then return end 
    
    local ItemOrigin = Item:GetOrigin()
    
    local SteamId = self:GetTeamCommanderSteamid( Item:GetTeamNumber() ) or 0
          
    local Params =
    {
        commander_steamid = SteamId,
        instanthit = Player ~= nil,
        id = Item:GetId(),
        cost = GetCostForTech( TechId ),
        team = Item:GetTeamNumber(),
        name = Itemname,
        action = "pickable_item_dropped",
        x = StringFormat( "%.4f", ItemOrigin.x ),
        y = StringFormat( "%.4f", ItemOrigin.y ),
        z = StringFormat( "%.4f", ItemOrigin.z )
    }

    Plugin:AddLog( Params )
	
	--istanthit pick
    if Player then     
        local Client = Player:GetClient()
        SteamId = self:GetId( Client )
        
        Params.action = "pickable_item_picked"
        Params.steamId = SteamId
        Params.commander_steamid = nil
        Params.instanthit = nil        
        self:AddLog( Params )
    else self.ItemInfos[ Item:GetId() ] = true end    
end

--Item is picked
function Plugin:OnPickableItemPicked( Item, Player )
    if not Item or not Player then return end
    
    local TechId = Item:GetTechId()    
    if not TechId or not self.ItemInfos[ Item:GetId() ] then return end
    
    self.ItemInfos[ Item:GetId() ] = nil
    
    local TechId = Item:GetTechId()
    
    local Itemname = EnumToString( kTechId, TechId )
    if not Itemname or Itemname == "None" then return end 
    
    local ItemOrigin = Item:GetOrigin()

    local Client = Player:GetClient()
    local SteamId = self:GetId(Client) or 0
    
    local Params =
    {
        steamId = SteamId,
        id = Item:GetId(),
        cost = GetCostForTech(TechId),
        team = Player:GetTeamNumber(),
        name = Itemname,
        action = "pickable_item_picked",
        x = StringFormat("%.4f", ItemOrigin.x),
        y = StringFormat("%.4f", ItemOrigin.y),
        z = StringFormat("%.4f", ItemOrigin.z)
    }
    Plugin:AddLog( Params )	

end

function Plugin:OnPickableItemDropped( Item, DeltaTime )
	if not ( self.RoundStarted or Item ) then return end

    local TechId = Item:GetTechId()
    if not TechId or TechId < 180 then return end
    
    --from dropack.lua
    local MarinesNearby = GetEntitiesForTeamWithinRange( "Marine", Item:GetTeamNumber(), Item:GetOrigin(), Item.pickupRange)
    
    if #MarinesNearby > 0 then
        Shared.SortEntitiesByDistance( Item:GetOrigin(), MarinesNearby )
    end    
    
    local Player
    for _, Marine in ipairs( MarinesNearby ) do    
        if Item:GetIsValidRecipient( Marine ) then
            Player = Marine
            break
        end
    end    
    
    --check if droppack is new
    if DeltaTime == 0 then
        self:OnPickableItemCreated( Item, TechId, Player )
        return
    end
    
    if Player then self:OnPickableItemPicked( Item, Player ) end        
end

--Item gets destroyed
function Plugin:OnPickableItemDestroyed( Item )  
    if Item and Item.GetId and Item:GetId() and self.ItemInfos[ Item:GetId() ] then    
        self.ItemInfos[ Item:GetId() ] = nil
        
        local TechId = Item:GetTechId()
        
        local tOrigin = Item:GetOrigin()

        local Params =
        {
            id = Item:GetId(),
            cost = GetCostForTech( TechId ),
            team = Item:GetTeamNumber(),
            name = EnumToString( kTechId, TechId ),
            action = "pickable_item_destroyed",
            x = StringFormat( "%.4f", tOrigin.x ),
            y = StringFormat( "%.4f", tOrigin.y ),
            z = StringFormat( "%.4f", tOrigin.z )
        }
        self:AddLog( Params )	
    end
end
--Pickable Stuff end

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
    if not Doer then Doer = "None" end
    --Structure killed
    if Attacker then 
        if not Attacker:isa( "Player" ) then 
            local RealKiller = Attacker.GetOwner and Attacker:GetOwner()
            if RealKiller and RealKiller:isa( "Player" ) then
                Attacker = RealKiller
            else 
                return
            end
        end
        
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
    elseif Entity:isa( "DropPack" ) and Entity:GetTechId() > 180 then
        self:OnPickableItemDestroyed( Entity )
    end    
end

--add Player death to Log
function Plugin:AddDeathToLog(Target, Attacker, Doer)
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
    for _,PlayerInfo in pairs(self.PlayersInfos) do	
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
    
    if not Plugin.Log then Plugin.Log = {} end
    if not Plugin.Log[ Plugin.LogPartNumber ] then Plugin.Log[ Plugin.LogPartNumber ] = "" end
   
    if Shared.GetCheatsEnabled() and self.StatsEnabled then 
        self.StatsEnabled = false
        Shine:Notify( nil, "", "NS2Stats", "Cheats were enabled! NS2Stats will disable itself now!")
    end
    
    Params.time = Shared.GetGMTString(false)
    Params.gametime = Shared.GetTime() - self.GameStartTime
    Plugin.Log[Plugin.LogPartNumber] = StringFormat("%s%s\n",Plugin.Log[Plugin.LogPartNumber], JsonEncode(Params))	
    
    --avoid that log gets too long
    if StringLen(self.Log[self.LogPartNumber]) > 160000 then
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
    local PlayerInfo= {}
       
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
    for _, PlayerInfo in pairs( self.PlayersInfos ) do
        if PlayerInfo.isCommander and PlayerInfo.teamnumber == TeamNumber then
            return PlayerInfo.steamId
        end	
    end
    return 0
end

function Plugin:GetPlayerByName( Name )
    if not Name then return end
    for _,PlayerInfo in pairs( self.PlayersInfos ) do        
        if PlayerInfo.name == Name then return PlayerInfo end	
    end
    return
end

function Plugin:GetPlayerByClient(Client)
    if not Client then return end
    
    if Client.GetUserId then
        local steamId = self:GetId( Client )
        for _,PlayerInfo in pairs( self.PlayersInfos ) do	
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
function Plugin:GetId(Client)
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
    
    for i=1,6 do
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
     local ShowPStats = self:BindCommand( "sh_showplayerstats", { "showplayerstats", "showstats" }, function( Client )
        HTTPRequest( StringFormat("%s/api/oneplayer?ns2_id=%s", self.Config.WebsiteUrl, Plugin:GetId(Client)), "GET", function(Response)
            local Data = JsonDecode( Response )
            local PlayerId = ""
            if Data then PlayerId = Data.id or "" end
            local URL = StringFormat( "%s/Player/Player/%s", self.Config.WebsiteUrl, PlayerId )
            Server.SendNetworkMessage( Client, "Shine_Web", { URL = URL, Title = "My Stats" }, true )
            end )
    end, true )
    ShowPStats:Help( "Shows stats from yourself" )
    
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
    
    for _, PlayerInfo in pairs( self.PlayersInfos ) do
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
    
    for _, PlayerInfo in pairs( self.PlayersInfos ) do
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
    
    for _, PlayerInfo in pairs( self.PlayersInfos ) do
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
    
    for _, PlayerInfo in pairs( self.PlayersInfos ) do
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
    
    for _, PlayerInfo in pairs( self.PlayersInfos ) do
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
    
    for _, PlayerInfo in pairs( self.PlayersInfos ) do
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
    
    for _, PlayerInfo in pairs(self.PlayersInfos) do
       
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
    
    for _, PlayerInfo in pairs( self.PlayersInfos ) do
                  
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

--Devour System Methods (see also Timers)

function Plugin:DevourClearBuffer()
    self.Devour.Entities = {}
    self.Devour.MovementInfos = {}
end

function Plugin:DevourSendStatus()
    if not self.RoundStarted then return end
    
    local stime = Shared.GetGMTString( false )
    
    local State = {
        time = stime,
        gametime = Shared.GetTime() - self.GameStartTime,
        map = Shared.GetMapName(),
    }
    
    local Dataset = {
        Entity = self.Devour.Entities,
        Movement =  self.Devour.MovementInfos,
        State = State
    }

    local Params =
    {
        key = self.Config.ServerKey,
        data = JsonEncode( Dataset )
    }
        
    HTTPRequest( StringFormat( "%s/api/sendstatusDevour", self.Config.WebsiteUrl ), "POST", Params, function() end )
    self:DevourClearBuffer()    
end

function Plugin:CreateDevourMovementFrame()

    local data = {}
    
    for _, Client in pairs( Shine.GetAllClients() ) do
        local Player = Client:GetControllingPlayer()
        local PlayerPos = Player:GetOrigin()
	    
	    if Player:GetTeamNumber() > 0 then
            local movement =
            {
                id = Plugin:GetId( Client ),
                x = Plugin:RoundNumber( PlayerPos.x ),
                y = Plugin:RoundNumber( PlayerPos.y ),
                z = Plugin:RoundNumber( PlayerPos.z ),
                wrh = Plugin:RoundNumber( Plugin:GetViewAngle( Player ) ),
            }
            TableInsert( data, movement )
        end	
    end
 
    self.Devour.MovementInfos[ self.Devour.Frame ] = data
end

function Plugin:CreateDevourEntityFrame()
    local DevourPlayers = {}
    
    for _, Client in pairs( Shine.GetAllClients() ) do	
        local Player = Client:GetControllingPlayer()        
        if not Player then return end
        
        local PlayerPos = Player:GetOrigin()
        
        local weapon = "none"
        if Player.GetActiveWeapon and Player:GetActiveWeapon() then
            weapon=Player:GetActiveWeapon():GetMapName() or "none"
        end
        
        if Player:GetTeamNumber()>0 then
            local DevourPlayer =
            {
                id = self:GetId( Client ),
                name = Player:GetName(),
                team = Player:GetTeamNumber(),
                x = self:RoundNumber( PlayerPos.x ),
                y = self:RoundNumber( PlayerPos.y ),
                z = self:RoundNumber( PlayerPos.z ),
                wrh = self:RoundNumber( Plugin:GetViewAngle( Player ) ),
                weapon = weapon,
                health = aelf:RoundNumber( Player:GetHealth() ),
                armor = self:RoundNumber( Player:GetArmor() ),
                pdmg = 0,
                sdmg = 0,
                lifeform = Player:GetMapName(),
                score = Player:GetScore(),
                kills = Player.kills,
                deaths = Player.deaths or 0,
                assists = Player:GetAssistKills(),
                pres = self:RoundNumber( Player:GetResources() ),
                ping = Client:GetPing() or 0,
                acc = 0,

            }
            TableInsert( DevourPlayers, DevourPlayer )
        end	
    end
    
    self.Devour.Entities[ self.Devour.Frame ] = DevourPlayers
end

function Plugin:GetViewAngle( Player )
    
    local Angle = Player:GetDirectionForMinimap() / math.pi * 180
    if Angle < 0 then Angle = 360 + Angle end
    if Angle > 360 then Angle = Angle % 360 end
    return Angle
end

function Plugin:RoundNumber( Number )
    local Temp = StringFormat( "%.2f", Number )
    return tonumber( Temp )
end

function Plugin:CleanUp()
    self.BaseClass.Cleanup( self )
    
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
    self.Devour = nil
    
    self.Enabled = false
end