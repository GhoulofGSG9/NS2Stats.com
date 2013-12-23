--[[
Shine ns2stats plugin. - Server
]]

local Shine = Shine
local Notify = Shared.Message

local Plugin = Plugin

local tostring = tostring
local StringFind = string.find
local StringFormat = string.format
local StringSub = string.UTF8Sub
local StringLen = string.len
local StringLower = string.lower

local GetOwner = Server.GetOwner

local JsonEncode = json.encode
local JsonDecode = json.decode

Plugin.Version = "shine"

Plugin.HasConfig = true
Plugin.ConfigName = "Ns2Stats.json"
Plugin.DefaultConfig =
{
    SendMapData = false, --Send Mapdata, only set true if minimap is missing at website or is incorrect
    Statusreport = true, -- send Status to NS2Stats every min
    WebsiteUrl = "http://ns2stats.com", --this is the ns2stats url
    Awards = true, --show award
    ShowNumAwards = 4, --how many awards should be shown at the end of the game?
    AwardMsgTime = 20, -- secs to show awards
    AwardMsgColour = {255,215,0},
    LogChat = false, --log the chat?
    ServerKey = "", -- Serverkey given by ns2stats.com
    Tags = {}, --Tags added to log
    Competitive = false, -- tag rounds as Competitive
    Lastroundlink = "", --Link of last round
}
Plugin.CheckConfig = true

--All needed Hooks

Shine.Hook.SetupClassHook("DamageMixin", "DoDamage", "OnDamageDealt", "PassivePre" )
Shine.Hook.SetupClassHook("ResearchMixin","TechResearched","OnTechResearched","PassivePost")
Shine.Hook.SetupClassHook("ResearchMixin","SetResearching","OnTechStartResearch","PassivePre")
Shine.Hook.SetupClassHook("ConstructMixin","SetConstructionComplete","OnFinishedBuilt","PassivePost")
Shine.Hook.SetupClassHook("ResearchMixin","OnResearchCancel","addUpgradeAbortedToLog","PassivePost")
Shine.Hook.SetupClassHook("UpgradableMixin","RemoveUpgrade","addUpgradeLostToLog","PassivePost")
Shine.Hook.SetupClassHook("ResourceTower","CollectResources","OnTeamGetResources","PassivePost")
Shine.Hook.SetupClassHook("DropPack","OnUpdate","OnPickableItemDropped","PassivePre")
Shine.Hook.SetupClassHook("Player","OnJump","OnPlayerJump","PassivePost")
Shine.Hook.SetupClassHook("Player","SetScoreboardChanged","OnPlayerScoreChanged","PassivePost")
Shine.Hook.SetupClassHook("PlayerBot","UpdateNameAndGender","OnBotRenamed","PassivePost")
Shine.Hook.SetupClassHook("NS2Gamerules","OnEntityDestroy","OnEntityDestroy","PassivePre")
Shine.Hook.SetupClassHook("NS2Gamerules","ResetGame","OnGameReset","PassivePre")
--NS2Ranking
Shine.Hook.SetupClassHook("PlayerRanking","GetTrackServer","EnableNS2Ranking","ActivePre")

function Plugin:Initialise()
    self.Enabled = true
    
    --ceate values
    self:OnGameReset()
    
    --create Commands
    self:CreateCommands()
    
    if self.Config.ServerKey == "" then
        self.Enabled = false
        Shared.SendHTTPRequest(StringFormat("%s/api/generateKey/?s=7g94389u3r89wujj3r892jhr9fwj",self.Config.WebsiteUrl), "GET", function(response) self:acceptKey(response) end)
    end
    
    --get Serverid
    self:GetServerId()
    
    --Timers
    
    --every 1 sec
    --to update Weapondatas
    self:CreateTimer( "WeaponUpdate", 1, -1, function()
       self:UpdateWeaponTable()
    end)
    
    -- every 30 sec send Server Status + Devour   
    if self.Config.Statusreport then
       self:CreateTimer("SendStatus" , 30, -1, function() self:sendServerStatus(self.currentGameState) end) --Plugin:devourSendStatus()
    end
    
    -- every 0.25 sec create Devour datas
    -- self:CreateTimer("Devour",0.25,-1, function()
        --if self.roundStarted then
            --Plugin:createDevourMovementFrame()
            --if self.Devour.Frame % 20 == 0 then Plugin:createDevourEntityFrame() end
            --self.Devour.Frame = self.Devour.Frame + 1
        --end 
    --end)
    return true
end

-- NS2VanillaStats
function Plugin:EnableNS2Ranking()
    return self.Enabled and Shine.GetGamemode() == "ns2"
end

-- Events

--Game Events

--Game reset
function Plugin:OnGameReset()
    --Resets all Stats
    self.self.working = true
    self.Log = {}
    self.LogPartNumber = 1
    self.LogPartToSend  = 1
    self.GameStartTime = 0
    self.RoundFinished = 0
    self.nextAwardId= 0
    self.Awards = {}
    self.roundStarted = false
    self.currentGameState = 0
    self.PlayersInfos = {}
    self.ItemInfos = {}
    
    --Reset Devour
    self.Devour.Frame = 0
    self.Devour.Entities = {}
    self.Devour.MovementInfos = {}
    
    -- update stats all connected players
    for _, client in ipairs(Shine.GetAllClients()) do
        self:addPlayerToTable(client)
    end        
    self.BuildingsInfos = {}
    self:addLog({action="game_reset"})
end

--Gamestart
function Plugin:SetGameState( Gamerules, NewState, OldState )
    self.currentGameState = NewState
    if NewState == kGameState.Started then
        self.working= false             
        self.roundStarted = true
        self.GameStartTime = Shared.GetTime()
        self:addLog({action = "game_start"})
       
        --send Playerlist            
        self:addPlayersToLog(0)
    end
end

--Gameend
function Plugin:EndGame( Gamerules, WinningTeam )         
        if self.Config.Awards then Plugin:sendAwardListToClients() end               
        self:addPlayersToLog(1)
        
        local initialHiveTechIdString = "None"
        if Gamerules.initialHiveTechId then
        	initialHiveTechIdString = EnumToString(kTechId, Gamerules.initialHiveTechId)
        end
          
        local params =
            {
                version = tostring(Shared.GetBuildNumber()),
                winner = WinningTeam:GetTeamNumber(),
                length = StringFormat("%.2f", Shared.GetTime() - Gamerules.gameStartTime),
                map = Shared.GetMapName(),
                start_location1 = Gamerules.startingLocationNameTeam1,
                start_location2 = Gamerules.startingLocationNameTeam2,
                start_path_distance = Gamerules.startingLocationsPathDistance,
                start_hive_tech = initialHiveTechIdString,
            }
        Plugin:AddServerInfos(params)
        
        self.RoundFinished = 1
        
        if self.Enabled then Plugin:sendData() end
        self.roundStarted = false
end

--Player Events

--Player Connected
function Plugin:ClientConfirmConnect(Client)
    if not Client or Client:GetIsVirtual() then return end
    
    local connect=
    {
        action = "connect",
        steamId = Plugin:GetId(Client)
    }
    self:addLog(connect)
    
    --player disconnected and came back
    local taulu = self:getPlayerByClient(Client)
    
    if not taulu then Plugin:addPlayerToTable(Client)  
    else taulu.dc = false end
    
    self:SendNetworkMessage(Client,"StatsConfig",{WebsiteApiUrl = StringFormat("%s/api",self.Config.WebsiteUrl),SendMapData = self.Config.SendMapData } ,true)   
end

--Player Disconnect
function Plugin:ClientDisconnect(Client)
    if not Client then return end
    
    local taulu = self:getPlayerByClient(Client)    
    if not taulu then return end
    
    taulu.dc = true
    
    local connect={
            action = "disconnect",
            steamId = taulu.steamId,
            score = taulu.score
    }
    self:addLog(connect)
end

--score changed (will change with 263)
function Plugin:OnPlayerScoreChanged(Player,state)    
    if not Player or not state then return end
    
    local Client = Player:GetClient()
    if not Client then return end
    
    local taulu = Plugin:getPlayerByClient(Client)
    if not taulu then return end
    
    local lifeform = Player:GetMapName()
    
    --check team
    local team = Player:GetTeamNumber() or 0    
    if team < 0 then return end
    
    if taulu.teamnumber == 3 and team > 0 then return end   --filter spectator
    
    if team >= 0 and taulu.teamnumber ~= team then
        taulu.teamnumber = team
    
        local playerJoin =
        {
            action="player_join_team",
            name = taulu.name,
            team = taulu.teamnumber,
            steamId = taulu.steamId,
            score = taulu.score
        }
        self:addLog(playerJoin) 
    end
    
    --check if lifeform changed    
    if not Player:GetIsAlive() and (team == 1 or team == 2) then lifeform = "dead" end
    if taulu.lifeform ~= lifeform then
        taulu.lifeform = lifeform
        self:addLog({action = "lifeform_change", name = taulu.name, lifeform = taulu.lifeform, steamId = taulu.steamId})      
    end
    
    self:UpdatePlayerInTable(Client,Player,taulu)
end

--Bots renamed
function Plugin:OnBotRenamed(Bot)
    local player = Bot:GetPlayer()
    local name = player:GetName()
    if not name or not string.find(name, "[BOT]",nil,true) then return end
    
    local client = player:GetClient()
    if not client then return end
        
    local taulu = Plugin:getPlayerByClient(client)
    if not taulu then
        self:addPlayerToTable(client)
        taulu = self:getPlayerByClient(client)
    else
        taulu.dc = false
        return
    end
    
    --Bot connects
    local connect={
            action = "connect",
            steamId = taulu.steamId
    }
    
    self:addLog(connect)        
end

--Player shoots weapon (will change with 263)
function Plugin:OnDamageDealt(DamageMixin, damage, target, point, direction, surface, altMode, showtracer)    
    local attacker 
    if DamageMixin:isa("Player") then
        attacker = DamageMixin
    elseif DamageMixin:GetParent() and DamageMixin:GetParent():isa("Player") then
        attacker = DamageMixin:GetParent()
    elseif HasMixin(DamageMixin, "Owner") and DamageMixin:GetOwner() and DamageMixin:GetOwner():isa("Player") then
        attacker = DamageMixin:GetOwner()
    else return end
    
    local damageType = kDamageType.Normal
    if DamageMixin.GetDamageType then damageType = DamageMixin:GetDamageType()
    elseif HasMixin(DamageMixin, "Tech") then damageType = LookupTechData(DamageMixin:GetTechId(), kTechDataDamageType, kDamageType.Normal) end
            
    local doer = DamageMixin
    
    local hit = false
    if target and HasMixin(target, "Live") and damage > 0 then
    
        local armorUsed = 0
        local healthUsed = 0        
        damage, armorUsed, healthUsed = GetDamageByType(target, attacker, doer, damage, damageType, point)
        
        if damage > 0 and attacker:isa("Player")then
            Plugin:addHitToLog(target, attacker, doer, damage, damageType)
            hit = true
        end            
    end
    
    if not hit then self:addMissToLog(attacker) end 
end

--add Hit
function Plugin:addHitToLog(target, attacker, doer, damage, damageType)
    if target:isa("Player") then
        local attacker_id = Plugin:GetId(attacker:GetClient())
        local target_id = Plugin:GetId(target:GetClient())        
        if not attacker_id or not target_id then return end
        
        local aOrigin = attacker:GetOrigin()
        local tOrigin = target:GetOrigin()
        if not attacker:GetIsAlive() then aOrigin = tOrigin end
        
        local weapon = "none"
        if target:GetActiveWeapon() then
            weapon = StringLower(target:GetActiveWeapon():GetMapName()) end        
        local hitLog =
        {
            --general
            action = "hit_player",	
            
            --Attacker
            attacker_steamId = attacker_id,
            attacker_team = attacker:GetTeamNumber(),
            attacker_weapon = StringLower(doer:GetMapName()),
            attacker_lifeform =  StringLower(attacker:GetMapName()),
            attacker_hp = attacker:GetHealth(),
            attacker_armor = attacker:GetArmorAmount(),
            attackerx = StringFormat("%.4f", aOrigin.x),
            attackery = StringFormat("%.4f", aOrigin.y),
            attackerz = StringFormat("%.4f", aOrigin.z),
            
            --Target
            target_steamId = target_id,
            target_team = target:GetTeamNumber(),
            target_weapon = weapon,
            target_lifeform = StringLower(target:GetMapName()),
            target_hp = target:GetHealth(),
            target_armor = target:GetArmorAmount(),
            targetx = StringFormat("%.4f", tOrigin.x),
            targety = StringFormat("%.4f", tOrigin.y),
            targetz = StringFormat("%.4f", tOrigin.z),
            
            damageType = damageType,
            damage = damage            
        }
        self:addLog(hitLog)
        self:weaponsAddHit(attacker, StringLower(doer:GetMapName()), damage)                
        
    else --target is a structure
        local structureOrigin = target:GetOrigin()
        local aOrigin = attacker:GetOrigin()
        local hitLog =
        {
            
            --general
            action = "hit_structure",	
            
            --Attacker
            attacker_steamId =  attacker_id,
            attacker_team = attacker:GetTeamNumber(),
            attacker_weapon = StringLower(doer:GetMapName()),
            attacker_lifeform = StringLower(attacker:GetMapName()),
            attacker_hp = attacker:GetHealth(),
            attacker_armor = attacker:GetArmorAmount(),
            attackerx = StringFormat("%.4f",  aOrigin.x),
            attackery = StringFormat("%.4f",  aOrigin.y),
            attackerz = StringFormat("%.4f",  aOrigin.z),
                        
            structure_id = target:GetId(),
            structure_name = StringLower(target:GetMapName()),	
            structure_x = StringFormat("%.4f", structureOrigin.x),
            structure_y = StringFormat("%.4f", structureOrigin.y),
            structure_z = StringFormat("%.4f", structureOrigin.z),	

            damageType = damageType,
            damage = damage
        }        
        self:addLog(hitLog)
        self:weaponsAddStructureHit(attacker, StringLower(doer:GetMapName()), damage)        
    end
end

--Add miss
function Plugin:addMissToLog(attacker)                
    local client = attacker:GetClient()
    if not client then return end

    local player = Plugin:getPlayerByClient(client)
    if not player then return end

    local weapon = StringLower(attacker:GetActiveWeaponName()) or "none"
    
    --gorge fix
    if weapon == "spitspray" then
        weapon = "spit"
    end
    
    self:weaponsAddMiss(client,weapon)
end

--weapon add miss
function Plugin:weaponsAddMiss(client, weapon)    
    local player = self:getPlayerByClient(client)    
    if not player then return end
     
    local foundId = false      
    for i=1, #player.weapons do
        if player.weapons[i].name == weapon then
            foundId=i
            break
        end
    end

    if foundId then
        player.weapons[foundId].miss = player.weapons[foundId].miss + 1
    else --add new weapon
        table.insert(player.weapons,
        {
            name = weapon,
            time = 0,
            miss = 1,
            player_hit = 0,
            structure_hit = 0,
            player_damage = 0,
            structure_damage = 0
        })
    end        
end

--weapon addhit to player
function Plugin:weaponsAddHit(player, weapon, damage)
    local client = player:GetClient()
    if not client then return end
    
    local taulu = Plugin:getPlayerByClient(client)
    if not taulu then return end
    
    local foundId = false
      
    for i=1, #taulu.weapons do
        if taulu.weapons[i].name == weapon then
            foundId=i
            break
        end
    end

    if foundId then
        taulu.weapons[foundId].player_hit = taulu.weapons[foundId].player_hit + 1
        taulu.weapons[foundId].player_damage = taulu.weapons[foundId].player_damage + damage
        
    else --add new weapon
        table.insert(taulu.weapons,
        {
            name = weapon,
            time = 0,
            miss = 0,
            player_hit = 1,
            structure_hit = 0,
            player_damage = damage,
            structure_damage = 0
        })
    end        
end

--weapon addhit to structure
function Plugin:weaponsAddStructureHit(player,weapon, damage)
    local client = player:GetClient()
    if not client then return end
    
    local taulu = Plugin:getPlayerByClient(client)
    if not taulu then return end
    
    local foundId = false
      
    for i=1, #taulu.weapons do
        if taulu.weapons[i].name == weapon then
            foundId=i
            break
        end
    end

    if foundId then
        taulu.weapons[foundId].structure_hit = taulu.weapons[foundId].structure_hit + 1
        taulu.weapons[foundId].structure_damage = taulu.weapons[foundId].structure_damage + damage

    else --add new weapon
        table.insert(taulu.weapons,
        {
            name = weapon,
            time = 0,
            miss = 0,
            player_hit = 0,
            structure_hit = 1,
            player_damage = 0,
            structure_damage = damage
        })
    end
        
end
--OnDamagedealt end

--Player jumps
function Plugin:OnPlayerJump(Player)
    local taulu = self:getPlayerByName(Player.name)
    if not taulu then return end
    taulu.jumps = taulu.jumps + 1   
end

--Chatlogging
function Plugin:PlayerSay( Client, Message )
    if not Plugin.Config.LogChat then return end
    
    local player = Client:GetControllingPlayer()
    if not player then return end
    
    self:addLog({
        action = "chat_message",
        team = player:GetTeamNumber(),
        steamid = Plugin:GetId(Client),
        name = player:GetName(),
        message = Message.message,
        toteam = Message.teamOnly
    })
end

--Team Events

--Pickable Stuff
local self.ItemInfos = {}

--Item is dropped
function Plugin:OnPickableItemCreated(item, techId, player) 
    
    local itemname = EnumToString(kTechId, techId)
    if not itemname or itemname == "None" then return end 
    
    local itemOrigin = item:GetOrigin()
    
    local steamid = self:getTeamCommanderSteamid(item:GetTeamNumber()) or 0
          
    local newItem =
    {
        commander_steamid = steamid,
        instanthit = ihit,
        id = item:GetId(),
        cost = GetCostForTech(techId),
        team = item:GetTeamNumber(),
        name = itemname,
        action = "pickable_item_dropped",
        x = StringFormat("%.4f", itemOrigin.x),
        y = StringFormat("%.4f", itemOrigin.y),
        z = StringFormat("%.4f", itemOrigin.z)
    }

    Plugin:addLog(newItem)
	
	--istanthit pick
    if player then     
        local client = player:GetClient()
        local steamId = self:GetId(client) or 0
        
        newItem.action = "pickable_item_picked"
        newItem.steamId = steamId
        newItem.commander_steamid = nil
        newItem.instanthit = nil        
        self:addLog(newItem)
    else self.ItemInfos[item:GetId()] = true end    
end

--Item is picked
function Plugin:OnPickableItemPicked(item,player)
    if not item or not player then return end
    
    local techId = item:GetTechId()    
    if not techId or not self.ItemInfos[item:GetId()] then return end
    
    self.ItemInfos[item:GetId()] = nil
    
    local techId = item:GetTechId()
    
    local itemname = EnumToString(kTechId, techId)
    if not itemname or itemname == "None" then return end 
    
    local itemOrigin = item:GetOrigin()

    local client = player:GetClient()
    local steamId = self:GetId(client) or 0
    local newItem =
    {
        steamId = steamId,
        id = item:GetId(),
        cost = GetCostForTech(techId),
        team = player:GetTeamNumber(),
        name = itemname,
        action = "pickable_item_picked",
        x = StringFormat("%.4f", itemOrigin.x),
        y = StringFormat("%.4f", itemOrigin.y),
        z = StringFormat("%.4f", itemOrigin.z)
    }
    Plugin:addLog(newItem)	

end

function Plugin:OnPickableItemDropped(item,deltaTime)
    if not item then return end    
    
    local techId = item:GetTechId()
    if not techId or techId < 180 then return end
    
    --from dropack.lua
    local marinesNearby = GetEntitiesForTeamWithinRange("Marine", item:GetTeamNumber(), item:GetOrigin(), item.pickupRange)
    Shared.SortEntitiesByDistance(item:GetOrigin(), marinesNearby)
    
    local player
    for _, marine in ipairs(marinesNearby) do    
        if item:GetIsValidRecipient(marine) then
            player = marine
            break
        end
    end    
    
    --check if droppack is new
    if deltaTime == 0 then
        if player then self:OnPickableItemCreated(item, techId, player)       
        else self:OnPickableItemCreated(item, techId, nil) end
        return
    end
    
    if player then self:OnPickableItemPicked(item,player) end        
end

--Item gets destroyed
function Plugin:OnPickableItemDestroyed(item)  
    if item and item.GetId and item:GetId() and self.ItemInfos[item:GetId()] then    
        self.ItemInfos[item:GetId()] = nil
        
        local techId = item:GetTechId()
        
        local structureOrigin = item:GetOrigin()

        local newItem =
        {
            id = item:GetId(),
            cost = GetCostForTech(techId),
            team = item:GetTeamNumber(),
            name = EnumToString(kTechId, techId),
            action = "pickable_item_destroyed",
            x = StringFormat("%.4f", structureOrigin.x),
            y = StringFormat("%.4f", structureOrigin.y),
            z = StringFormat("%.4f", structureOrigin.z)
        }
        self:addLog(newItem)	
    end
end
--Pickable Stuff end

--Resource gathered
function Plugin:OnTeamGetResources(ResourceTower)    
    local newResourceGathered =
    {
        team = ResourceTower:GetTeam():GetTeamNumber(),
        action = "resources_gathered",
        amount = kTeamResourcePerTick
    }
    self:addLog(newResourceGathered)
end

--Structure Events

--Building Dropped
function Plugin:OnConstructInit( Building )
    
    if not self.roundStarted then return end    
    local techId = Building:GetTechId()
    local name = EnumToString(kTechId, techId)
    
    if name == "Hydra" or name == "GorgeTunnel"  or name == "BabblerEgg" then return end --Gorge Building Fix
    
    self.BuildingsInfos[Building:GetId()] = true
    
    local strloc = Building:GetOrigin()
    local build=
    {
        action = "structure_dropped",
        id = Building:GetId(),
        steamId = Plugin:getTeamCommanderSteamid(Building:GetTeamNumber()) or 0,       
        team = Building:GetTeamNumber(),        
        structure_cost = GetCostForTech(techId),
        structure_name = name,
        structure_x = StringFormat("%.4f",strloc.x),
        structure_y = StringFormat("%.4f",strloc.y),
        structure_z = StringFormat("%.4f",strloc.z),
    }
    Plugin:addLog(build)
    if Building.isGhostStructure then self:OnGhostCreated(Building) end
end

--Building built
function Plugin:OnFinishedBuilt(ConstructMixin, builder)
    self.BuildingsInfos[ConstructMixin:GetId()] = true 
  
    local techId = ConstructMixin:GetTechId()    
    local strloc = ConstructMixin:GetOrigin()
    
    if builder and builder.GetName then
        local taulu = Plugin:getPlayerByName(builder:GetName())
    end
    
    local team = ConstructMixin:GetTeamNumber()
    local steamId = Plugin:getTeamCommanderSteamid(team) or 0    
    local buildername = ""
        
    if taulu then
        steamId = taulu.steamId
        buildername = taulu.name
        taulu.total_constructed = taulu.total_constructed + 1           
    end
    
    local build=
    {
        action = "structure_built",
        id = ConstructMixin:GetId(),
        builder_name = buildername,
        steamId = steamId,
        structure_cost = GetCostForTech(techId),
        team = team,
        structure_name = EnumToString(kTechId, techId),
        structure_x = StringFormat("%.4f",strloc.x),
        structure_y = StringFormat("%.4f",strloc.y),
        structure_z = StringFormat("%.4f",strloc.z),
    }
    self:addLog(build)
end

--Ghost Buildings (Blueprints)
function Plugin:OnGhostCreated(GhostStructureMixin)
     self:ghostStructureAction("ghost_create",GhostStructureMixin,nil)
end

function Plugin:OnGhostDestroyed(GhostStructureMixin)
   self.BuildingsInfos[GhostStructureMixin:GetId()] = nil
   self:ghostStructureAction("ghost_destroy",GhostStructureMixin,nil)
end

--addfunction

function Plugin:ghostStructureAction(action,structure,doer)        
    if not structure then return end
    local techId = structure:GetTechId()
    local structureOrigin = structure:GetOrigin()
   
    local log =
    {
        action = action,
        structure_name = EnumToString(kTechId, techId),
        team = structure:GetTeamNumber(),
        id = structure:GetId(),
        structure_x = StringFormat("%.4f", structureOrigin.x),
        structure_y = StringFormat("%.4f", structureOrigin.y),
        structure_z = StringFormat("%.4f", structureOrigin.z)
    }
    self:addLog(log)    
end

--Upgrade Stuff

--UpgradesStarted
function Plugin:OnTechStartResearch(ResearchMixin, researchNode, player)
    if player:isa("Commander") then
    	local client = player:GetClient()        
        local steamId = self:GetId(client) or 0
        local techId = researchNode:GetTechId()

        local newUpgrade =
        {
	        structure_id = ResearchMixin:GetId(),
	        commander_steamid = steamId,
	        team = player:GetTeamNumber(),
	        cost = GetCostForTech(techId),
	        upgrade_name = EnumToString(kTechId, techId),
	        action = "upgrade_started"
        }

        self:addLog(newUpgrade)
    end
end

--temp to fix Uprades loged multiple times
OldUpgrade = -1

--Upgradefinished
function Plugin:OnTechResearched( ResearchMixin, structure, researchId)
    if not structure then return end
    local researchNode = ResearchMixin:GetTeam():GetTechTree():GetTechNode(researchId)
    local techId = researchNode:GetTechId()
    
    if techId == OldUpgrade then return end
    OldUpgrade = techId
    
    local newUpgrade =
    {
        structure_id = structure:GetId(),
        team = structure:GetTeamNumber(),
        commander_steamid = Plugin:getTeamCommanderSteamid(structure:GetTeamNumber()),
        cost = GetCostForTech(techId),
        upgrade_name = EnumToString(kTechId, techId),
        action = "upgrade_finished"
    }
    self:addLog(newUpgrade)
end

--Upgrade lost
function Plugin:addUpgradeLostToLog(UpgradableMixin, techId)
    local newUpgrade =
    {
        team = UpgradableMixin:GetTeamNumber(),
        cost = GetCostForTech(techId),
        upgrade_name = EnumToString(kTechId, techId), 
        action = "upgrade_lost"
    }
    self:addLog(newUpgrade)

end

--Research canceled
function Plugin:addUpgradeAbortedToLog(ResearchMixin, researchNode)
    local techId = researchNode:GetTechId()
    local steamid = self:getTeamCommanderSteamid(ResearchMixin:GetTeamNumber())

    local newUpgrade =
    {
        structure_id = ResearchMixin:GetId(),
        team = ResearchMixin:GetTeamNumber(),
        commander_steamid = steamid,
        cost = GetCostForTech(techId),
        upgrade_name = EnumToString(kTechId, techId),
        action = "upgrade_aborted"
    }
    self:addLog(newUpgrade)
end

--Building recyled
function Plugin:OnBuildingRecycled( structure, ResearchID )
    local structureOrigin = structure:GetOrigin()
    local techId = structure:GetTechId()
    
    --from RecyleMixin.lua
        local upgradeLevel = 0
        if structure.GetUpgradeLevel then
            upgradeLevel = structure:GetUpgradeLevel()
        end        
        local amount = GetRecycleAmount(techId, upgradeLevel) or 0
        -- returns a scalar from 0-1 depending on health the structure has (at the present moment)
        local scalar = structure:GetRecycleScalar() * kRecyclePaybackScalar
        
        -- We round it up to the nearest value thus not having weird
        -- fracts of costs being returned which is not suppose to be
        -- the case.
        local finalRecycleAmount = math.round(amount * scalar)
    --end   

    local newUpgrade =
    {
        id = structure:GetId(),
        team = structure:GetTeamNumber(),
        givenback = finalRecycleAmount,
        structure_name = EnumToString(kTechId, techId),
        action = "structure_recycled",
        structure_x = StringFormat("%.4f", structureOrigin.x),
        structure_y = StringFormat("%.4f", structureOrigin.y),
        structure_z = StringFormat("%.4f", structureOrigin.z)
    }
    structure:addLog(newUpgrade)
end

--Structure gets killed
function Plugin:OnStructureKilled(structure, attacker , doer)
    if not self.BuildingsInfos[structure:GetId()] then return end
    self.BuildingsInfos[structure:GetId()] = nil                
    local structureOrigin = structure:GetOrigin()
    local techId = structure:GetTechId()        
    if not doer then doer = "none" end
    --Structure killed
    if attacker then 
        if not attacker:isa("Player") then 
            local realKiller = (attacker.GetOwner and attacker:GetOwner()) or nil
            if realKiller and realKiller:isa("Player") then
                attacker = realKiller
            else return
            end
        end
        
        local player = attacker                 
        local client = player:GetClient()
        local steamId = self:GetId(client) or -1
        
        local weapon = doer and doer:GetMapName() or "self"      

        local newStructure =
        {
            id = structure:GetId(),
            killer_steamId = steamId,
            killer_lifeform = player:GetMapName() or "none",
            killer_team = player:GetTeamNumber() or 0,
            structure_team = structure:GetTeamNumber(),
            killerweapon = weapon,
            structure_cost = GetCostForTech(techId),
            structure_name = EnumToString(kTechId, techId),
            action = "structure_killed",
            structure_x = StringFormat("%.4f", structureOrigin.x),
            structure_y = StringFormat("%.4f", structureOrigin.y),
            structure_z = StringFormat("%.4f", structureOrigin.z)
        }
        self:addLog(newStructure)
            
    --Structure suicide
    else
        local newStructure =
        {
            id = structure:GetId(),
            structure_team = structure:GetTeamNumber(),
            structure_cost = GetCostForTech(techId),
            structure_name = EnumToString(kTechId, techId),
            action = "structure_suicide",
            structure_x = StringFormat("%.4f", structureOrigin.x),
            structure_y = StringFormat("%.4f", structureOrigin.y),
            structure_z = StringFormat("%.4f", structureOrigin.z)
        }
        self:addLog(newStructure)
    end 
end

--Mixed Events 

--Entity Killed
function Plugin:OnEntityKilled(Gamerules, TargetEntity, Attacker, Inflictor, Point, Direction)   
    if TargetEntity:isa("Player") then self:addDeathToLog(TargetEntity, Attacker, Inflictor)     
    elseif self.BuildingsInfos[TargetEntity:GetId()] and not TargetEntity.isGhostStructure then self:OnStructureKilled(TargetEntity, Attacker, Inflictor)      
    end   
end

function Plugin:OnEntityDestroy(entity)
    if entity:isa("DropPack") and entity:GetTechId() > 180 then  Plugin:OnPickableItemDestroyed(entity) end
    if self.BuildingsInfos[entity:GetId()] then if entity.isGhostStructure then self:OnGhostDestroyed(entity) end end
end

--add Player death to Log
function Plugin:addDeathToLog(target, attacker, doer)
    if attacker and doer and target then
        local attackerOrigin = attacker:GetOrigin()
        local targetOrigin = target:GetOrigin()        
        local target_client = target:GetClient()
        if not target_client then return end

        local targetWeapon = target:GetActiveWeapon() and target:GetActiveWeapon():GetMapName() or "None"

        if attacker:isa("Player") then            
            local attacker_client = attacker:GetClient()                
            if not attacker_client then return end
            
            local deathLog =
            {                
            --general
            action = "death",	
            
            --Attacker
            attacker_steamId = Plugin:GetId(attacker_client) or 0,
            attacker_team = ((HasMixin(attacker, "Team") and attacker:GetTeamType()) or kNeutralTeamType),
            attacker_weapon = StringLower(doer:GetMapName()),
            attacker_lifeform = StringLower(attacker:GetMapName()), 
            attacker_hp = attacker:GetHealth(),
            attacker_armor = attacker:GetArmorAmount(),
            attackerx = StringFormat("%.4f", attackerOrigin.x),
            attackery = StringFormat("%.4f", attackerOrigin.y),
            attackerz = StringFormat("%.4f", attackerOrigin.z),
            
            --Target
            target_steamId = Plugin:GetId(target_client) or 0,
            target_team = target:GetTeamType(),
            target_weapon = StringLower(targetWeapon),
            target_lifeform = StringLower(target:GetMapName()), 
            target_hp = target:GetHealth(),
            target_armor = target:GetArmorAmount(),
            targetx = StringFormat("%.4f", targetOrigin.x),
            targety = StringFormat("%.4f", targetOrigin.y),
            targetz = StringFormat("%.4f", targetOrigin.z),
            target_lifetime = StringFormat("%.4f", Shared.GetTime() - target:GetCreationTime())
            }
            Plugin:addLog(deathLog)
                
            if attacker:GetTeamNumber() ~= target:GetTeamNumber() then                   
                --addkill
                Plugin:addKill(Plugin:GetId(attacker_client), Plugin:GetId(target_client))                  
            end            
	    else
	        --natural causes death
	        local deathLog =
	        {
	            --general
	            action = "death",
	
	            --Attacker
	            attacker_weapon	= "natural causes",
	
	            --Target
	            target_steamId = Plugin:GetId(target_client),
	            target_team = target:GetTeamType(),
	            target_weapon = targetWeapon,
	            target_lifeform = target:GetMapName(), --target:GetPlayerStatusDesc(),
	            target_hp = target:GetHealth(),
	            target_armor = target:GetArmorAmount(),
	            targetx = StringFormat("%.4f", targetOrigin.x),
	            targety = StringFormat("%.4f", targetOrigin.y),
	            targetz = StringFormat("%.4f", targetOrigin.z),
	            target_lifetime = StringFormat("%.4f", Shared.GetTime() - target:GetCreationTime())	
	        }
	        self:addLog(deathLog)       
	    end
    elseif target then --suicide
        local target_client = target:GetClient()       
        local targetWeapon = "none"
        local targetOrigin = target:GetOrigin()
        local attacker_client = target_client --easy way out        
        local attackerOrigin = targetOrigin
        local attacker = target
         local deathLog =
            {                
                --general
                action = "death",	
                
                --Attacker
                attacker_weapon = "self",
                attacker_lifeform = attacker:GetMapName(),
                attacker_steamId = Plugin:GetId(attacker_client),
                attacker_team = ((HasMixin(attacker, "Team") and attacker:GetTeamType()) or kNeutralTeamType),
                attacker_hp = attacker:GetHealth(),
                attacker_armor = attacker:GetArmorAmount(),
                attackerx = StringFormat("%.4f", attackerOrigin.x),
                attackery = StringFormat("%.4f", attackerOrigin.y),
                attackerz = StringFormat("%.4f", attackerOrigin.z),
                
                --Target
                target_steamId = Plugin:GetId(target_client),
                target_team = target:GetTeamType(),
                target_weapon = targetWeapon,
                target_lifeform = target:GetMapName(),
                target_hp = target:GetHealth(),
                target_armor = target:GetArmorAmount(),
                targetx = StringFormat("%.4f", targetOrigin.x),
                targety = StringFormat("%.4f", targetOrigin.y),
                targetz = StringFormat("%.4f", targetOrigin.z),
                target_lifetime = StringFormat("%.4f", Shared.GetTime() - target:GetCreationTime())
            }            
            self:addLog(deathLog)  
    end
end

--Check Killstreaks
function Plugin:addKill(attacker_steamId,target_steamId)
    for key,taulu in pairs(self.PlayersInfos) do	
        if taulu.steamId == attacker_steamId then	
            taulu.killstreak = taulu.killstreak + 1	
            if taulu.killstreak > taulu.highestKillstreak then
                taulu.highestKillstreak = taulu.killstreak
            end 
        end            
    end
end

--Events end

--Log functions

--add to log
function Plugin:addLog(tbl)    
    if self.RoundFinished == 1 or not tbl then return end
    
    if not Plugin.Log then Plugin.Log = {} end
    if not Plugin.Log[Plugin.LogPartNumber] then Plugin.Log[Plugin.LogPartNumber] = "" end
   
    if Shared.GetCheatsEnabled() and self.Enabled then 
        self.Enabled = false
        Shine:Notify( nil, "", "NS2Stats", "Cheats were enabled! NS2Stats will disable itself now!")
    end
    
    tbl.time = Shared.GetGMTString(false)
    tbl.gametime = Shared.GetTime() - self.GameStartTime
    Plugin.Log[Plugin.LogPartNumber] = StringFormat("%s%s\n",Plugin.Log[Plugin.LogPartNumber], JsonEncode(tbl))	
    
    --avoid that log gets too long
    if StringLen(Plugin.Log[Plugin.LogPartNumber]) > 250000 then
        Plugin.LogPartNumber = Plugin.LogPartNumber + 1    
        if self.Enabled then Plugin:sendData() end        
    end
end

--add playerlist to log
function Plugin:addPlayersToLog(type) 
    local tmp = {}
    
    if type == 0 then
        tmp.action = "player_list_start"
    else
        tmp.action = "player_list_end"
    end
  
    --reset codes
    for p = 1, #self.PlayersInfos do	
        local player = self.PlayersInfos[p]	
        player.code = 0
    end
    
    tmp.list = self.PlayersInfos    
    self:addLog(tmp)
end

--Add server infos
function Plugin:AddServerInfos(params)
    local mods = {}
    local getMod = Server.GetActiveModId
    for i = 1, Server.GetNumActiveMods() do
        local Mod = getMod( i )
        for j = 1, Server.GetNumMods() do
            if Server.GetModId(j) == Mod then
                mods[i] = Server.GetModTitle(j)
                break
            end
        end 
    end
    
    params.action = "game_ended"
    params.statsVersion = Plugin.Version
    params.serverName = Server.GetName()
    params.gamemode = Shine.GetGamemode()
    params.successfulSends = RBPSsuccessfulSends
    params.resendCount = RBPSresendCount
    params.mods = mods
    params.awards = self.Awards
    params.tags = self.Config.Tags    
    params.private = self.Config.Competitive
    params.autoarrange = false --use Shine plugin settings later?
    local ip = IPAddressToString(Server.GetIpAddress()) 
    if not StringFind(ip,":") then ip = StringFormat("%s:%s",ip,Server.GetPort()) end
    params.serverInfo =
    {
        password = "",
        IP = ip,
        count = 30 --servertick?
    }    
    self:addLog(params)
end

--send Log to NS2Stats Server
function Plugin:sendData()
    if self.LogPartNumber <= self.LogPartToSend and self.RoundFinished ~= 1 or self.working then return end
    
    self.working = true
    
    local params =
    {
        key = self.Config.ServerKey,
        roundlog = self.Log[Plugin.LogPartToSend],
        part_number = self.LogPartToSend ,
        last_part = self.RoundFinished,
        map = Shared.GetMapName(),
    }
    
    Shine.TimedHTTPRequest(StringFormat("%s/api/sendlog", self.Config.WebsiteUrl), "POST", params, function(response) Plugin:onHTTPResponseFromSend(response) end,function() self.working = false Plugin:sendData() end, 30)
end

--Analyze the answer of server
function Plugin:onHTTPResponseFromSend(response)	
    local message = JsonDecode(response)
    
    if message then        
        if message.other then
            Notify("[NSStats]: ".. message.other)
            return
        end
    
        if message.error == "NOT_ENOUGH_PLAYERS" then
            Notify("[NS2Stats]: Send failed because of too less players ")
            return
        end	

        if message.link then
            local link = StringFormat("%s%s",self.Config.WebsiteUrl, message.link)
            Shine:Notify( nil, "", "", StringFormat("Round has been saved to NS2Stats : %s" ,link))
            self.Config.Lastroundlink = link
            self:SaveConfig()
            return       
        end
    end
    
    if StringLen(response)>1 and StringFind(response,"LOG_RECEIVED_OK",nil, true) then
         self.Log[Plugin.LogPartToSend ] = nil
         self.LogPartToSend = Plugin.LogPartToSend  + 1
         RBPSsuccessfulSends = RBPSsuccessfulSends + 1
         self.working = false
         Plugin:sendData()
    else --we couldn't reach the NS2Stats Servers
        self.working = false                                
        self:SimpleTimer(5, function() self:sendData() end)             
    end    
end

--Log end 

--Player table functions
    
--add Player to table
function Plugin:addPlayerToTable(client)
    if not client then return end
    
    local entry = self:createPlayerTable(client)
    if not entry then return end
    
    table.insert(self.PlayersInfos, entry )    
end

--create new entry
function Plugin:createPlayerTable(client)
    if not client.GetControllingPlayer then
        Notify("[NS2Stats Debug]: Tried to create nil player")
        return
    end
    local player = client:GetControllingPlayer()
    if not player then return end
    local taulu= {}
       
    taulu.teamnumber = player:GetTeamNumber() or 0
    taulu.lifeform = player:GetMapName()
    taulu.score = 0
    taulu.assists = 0
    taulu.deaths = 0
    taulu.kills = 0
    taulu.totalKills = player.totalKills or 0
    taulu.totalAssists = player.totalAssists or 0
    taulu.totalDeaths = player.totalDeaths or 0
    taulu.playerSkill = player.playerSkill or 0
    taulu.totalScore = player.totalScore or 0
    taulu.totalPlayTime = player.totalPlayTime or 0
    taulu.playerLevel = player.playerLevel or 0   
    taulu.steamId = Plugin:GetId(client) or 0
    taulu.name = player:GetName() or ""
    taulu.ping = client:GetPing() or 0
    taulu.isbot = client:GetIsVirtual() or false	
    taulu.isCommander = false           
    taulu.dc = false
    taulu.total_constructed = 0        
    taulu.weapons = {}      
    taulu.killstreak =0
    taulu.highestKillstreak =0
    taulu.jumps = 0    
            
    --for bots
    if taulu.isbot then
        taulu.ping = 0
        taulu.ipaddress = "127.0.0.1"
    else
        taulu.ping = client:GetPing()
        taulu.ipaddress = IPAddressToString(Server.GetClientAddress(client))
    end
    
    return taulu
end

--Update Player Entry
function Plugin:UpdatePlayerInTable(client,player,taulu)

    if taulu.dc then return end
    
    taulu.name = player:GetName()
    taulu.score = player.score or 0
    taulu.assists = player.assistkills or 0
    taulu.deaths = player.deaths or 0
    taulu.kills = player.kills or 0
    taulu.totalKills = player.totalKills or 0
    taulu.totalAssists = player.totalAssists or 0
    taulu.totalDeaths = player.totalDeaths or 0
    taulu.playerSkill = player.playerSkill or 0
    taulu.totalScore = player.totalScore or 0
    taulu.totalPlayTime = player.totalPlayTime or 0
    taulu.playerLevel = player.playerLevel or 0
    taulu.isCommander = player:GetIsCommander() or false    
    --if player is dead
    if not player:GetIsAlive() then
        taulu.killstreak = 0        
    end
    if not taulu.isbot then taulu.ping = client:GetPing() end        
end

--All search functions
function Plugin:getTeamCommanderSteamid(teamNumber)
    for key,taulu in pairs(self.PlayersInfos) do	
        if taulu.isCommander and taulu.teamnumber == teamNumber then
            return taulu.steamId
        end	
    end

    return 0
end

function Plugin:getPlayerByName(name)
    if not name then return end
    for key,taulu in pairs(self.PlayersInfos) do        
        if taulu.name == name then return taulu end	
    end
    return end
end

function Plugin:getPlayerByClient(client)
    if not client then return end
    
    if client.GetUserId then
        local steamId = self:GetId(client)
        for key,taulu in pairs(self.PlayersInfos) do	
          if taulu.steamId == steamId then return taulu end
        end
    elseif client.GetControllingPlayer then
        local player = client:GetControllingPlayer()
        local name = player:GetName()
        self:getPlayerByName(name)
    end
end
--Player Table end

--GetIds
function Plugin:GetId(Client)
    if Client and Client.GetUserId then     
        if Client:GetIsVirtual() then return Plugin:GetIdbyName(Client:GetControllingPlayer():GetName()) or 0
        else return Client:GetUserId() end
    end 
end

--For Bots
local fakeids = {}

function Plugin:GetIdbyName(Name)    
    if not Name then return end
    
    --disable Onlinestats
    if self.Enabled then
        Notify( "NS2Stats won't store game with bots. Disabling online stats now!")
        self.Enabled = false 
    end
    
    if fakeids[Name] then return fakeids[Name] end
    
    local NewId=""
    local Letters = " []+-*/!_-%$1234567890aAbBcCdDeEfFgGhHiIjJkKlLmMnNoOpPqQrRsStTuUvVwWxXyYzZ"
    
    --to differ between e.g. name and name (2)   
    local Input = string.UTF8Reverse(Name)
    
    for i=1,6 do
        local Num = 99
        if #Input >=i then
            local Char = StringSub(Input,i,i)
            Num = StringFind(Letters,Char,nil,true) or 99
            if Num < 10 then Num = 80+Num end
        end
        NewId = StringFormat("%s%s",NewId,Num)        
    end
    
    
    --make a int
    NewId = tonumber(NewId)
    
    fakeids[Name] = NewId    
    return NewId
end
--Ids end

--Timer functions

--Update Weapontable
function Plugin:UpdateWeaponTable() 
        if not self.roundStarted then return end         
        for _, client in ipairs(Shine.GetAllClients()) do
            Plugin:updateWeaponData(client)                 
        end       
end   

function Plugin:updateWeaponData(client) 
    if not client then return end
    
    local taulu = self:getPlayerByClient(client)
    if not taulu then return end
    
    local player = client:GetControllingPlayer()
    if not player then return end
   
    local weapon = player.GetActiveWeaponName and player:GetActiveWeaponName() or "none"
    weapon = StringLower(weapon)
    
    local foundId
    for i=1, #taulu.weapons do
        if taulu.weapons[i].name == weapon then foundId=i end
    end
    
    if foundId then
        taulu.weapons[foundId].time = taulu.weapons[foundId].time + 1
    else --add new weapon
        table.insert(taulu.weapons,
        {
            name = weapon,
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
function Plugin:sendServerStatus(gameState)
    local stime = Shared.GetGMTString(false)
    local gameTime = Shared.GetTime() - self.GameStartTime
    local params =
    {
        key = self.Config.ServerKey,
        players = JsonEncode(self.PlayersInfos),
        state = gameState,
        time = stime,
        gametime = gameTime,
        map = Shared.GetMapName(),
    }
    Shared.SendHTTPRequest(StringFormat("%s/api/sendstatus", self.Config.WebsiteUrl), "POST", params, function() end)	
end
--Timer end

-- Other ns2stats functions

--gets server key
function Plugin:acceptKey(response)
        if not response or response == "" then
            Notify("NS2Stats: Unable to receive unique key from server, stats wont work yet. ")
            Notify("NS2Stats: Server restart might help.")
        else
            local decoded = JsonDecode(response)
            if decoded and decoded.key then
                self.Config.ServerKey = decoded.key
                Notify(StringFormat("NS2Stats: Key %s has been assigned to this server ", self.Config.ServerKey))
                Notify("NS2Stats: You may use admin command sh_verity to claim this server.")
                Notify("NS2Stats setup complete.")
                self.Enabled = true
                self:SaveConfig()                                              
            else
                Notify("NS2Stats: Unable to receive unique key from server, stats wont work yet. ")
                Notify("NS2Stats: Server restart might help.")
                Notify(StringFormat("NS2Stats: Server responded: %s", response))
            end
        end
end

function Plugin:GetServerId()    
    if not self.serverid then
        self.serverid = ""
        Shared.SendHTTPRequest(StringFormat("%s/api/server?key=%s", self.Config.WebsiteUrl,self.Config.ServerKey), "GET", function(response)
            local Data = JsonDecode( response )
            if Data then self.serverid = Data.id or "" end            
        end)
    end
    return self.serverid    
end
--Other Ns2Stat functions end

--Commands
function Plugin:CreateCommands()    
     local ShowPStats = self:BindCommand( "sh_showplayerstats", {"showplayerstats","showstats" }, function(Client)
        Shared.SendHTTPRequest( StringFormat("%s/api/oneplayer?ns2_id=%s", self.Config.WebsiteUrl, Plugin:GetId(Client)), "GET",function(response)
            local Data = JsonDecode(response)
            local playerid = ""
            if Data then playerid = Data.id or "" end
            local url = StringFormat( "%s/player/player/%s", self.Config.WebsiteUrl, playerid)
            Server.SendNetworkMessage( Client, "Shine_Web", { URL = url, Title = "My Stats" }, true )
            end)
    end,true)
    ShowPStats:Help("Shows stats from yourself")
    
    local ShowLastRound = self:BindCommand( "sh_showlastround", {"showlastround","lastround" }, function(Client)
        if Plugin.Config.Lastroundlink == "" then Shine:Notify(Client, "", "", "[NS2Stats]: Last round was not saved at NS2Stats")       
        else Server.SendNetworkMessage( Client, "Shine_Web", { URL = Plugin.Config.Lastroundlink, Title = "Last Rounds Stats" }, true )
        end     
    end,true)   
    ShowLastRound:Help("Shows stats of last round played on this server")
    
    local ShowSStats = self:BindCommand( "sh_showserverstats", "showserverstats", function(Client)                     
        local url= StringFormat("%s/server/server/%s",self.Config.WebsiteUrl,Plugin:GetServerId())           
        Server.SendNetworkMessage( Client, "Shine_Web", { URL = url, Title = "Server Stats" }, true )       
    end,true)
    ShowSStats:Help("Shows server stats") 
    
    local ShowLStats = self:BindCommand( "sh_showlivestats", "showlivestats", function(Client)                    
        local url= StringFormat("%s/live/scoreboard/%s", self.Config.WebsiteUrl, Plugin:GetServerId())           
        Server.SendNetworkMessage( Client, "Shine_Web", { URL = url, Title = "Scoreboard" }, true )       
    end,true)
    ShowLStats:Help("Shows server live stats") 
    
    local Verify = self:BindCommand( "sh_verify", {"verifystats","verify"},function(Client)
            Shared.SendHTTPRequest(StringFormat("%s/api/verifyServer/%s?s=479qeuehq2829&key=%s", self.Config.WebsiteUrl, Plugin:GetId(Client), self.Config.ServerKey), "GET",
            function(response) ServerAdminPrint(Client,response) end)       
    end)
    Verify:Help ("Sets yourself as serveradmin at NS2Stats.com")
    
    local Tag = self:BindCommand( "sh_addtag","addtag",function(Client,tag)
        table.insert(Plugin.Config.Tags, tag)
        Notify( StringFormat("[NS2Stats]: %s  has been added as Tag to this roundlog", tag))       
    end)    
    Tag:AddParam{ Type = "string",TakeRestOfLine = true,Error = "Please specify a tag to be added.", MaxLength = 30}
    Tag:Help ("Adds the given tag to the Stats")
    
    local Debug = self:BindCommand( "sh_statsdebug","statsdebug",function(Client)
        Shine:AdminPrint( Client,"NS2Stats Debug Report:")
        Shine:AdminPrint( Client,StringFormat("%s Players in PlayerTable.",#self.PlayersInfos))
        Shine:AdminPrint( Client,StringFormat("Current Logparts %s / %s . Length of ToSend: %s",Plugin.LogPartToSend,Plugin.LogPartNumber ,StringLen(Plugin.Log[Plugin.LogPartToSend])))
    end,true)
end

--Awards
function Plugin:makeAwardsList()
    --DO NOT CHANGE ORDER HERE
    self:addAward(Plugin:awardMostDamage())
    self:addAward(Plugin:awardMostKillsAndAssists())
    self:addAward(Plugin:awardMostConstructed())
    self:addAward(Plugin:awardMostStructureDamage())
    self:addAward(Plugin:awardMostPlayerDamage())
    self:addAward(Plugin:awardBestAccuracy())
    self:addAward(Plugin:awardMostJumps())
    self:addAward(Plugin:awardHighestKillstreak())    
end

function Plugin:sendAwardListToClients()
    --reset and generates Awardlist
    self.nextAwardId = 0
    self.Awards = {}
    self:makeAwardsList()        
    --send highest 10 rating awards
    table.sort(self.Awards, function(a, b)
        return a.rating > b.rating
    end)
    
    local AwardMessage = {}
    AwardMessage.message = ""    
    AwardMessage.duration = Plugin.Config.AwardMsgTime
    AwardMessage.colourr = Plugin.Config.AwardMsgColour[1]
    AwardMessage.colourg = Plugin.Config.AwardMsgColour[2]
    AwardMessage.colourb = Plugin.Config.AwardMsgColour[3]
    
    for i=1,self.Config.ShowNumAwards do
        if i > #self.Awards then break end
        if self.Awards[i].message then 
            AwardMessage.message = StringFormat("%s%s\n", AwardMessage.message, self.Awards[i].message )
        end
    end 
    self:SendNetworkMessage(nil, "StatsAwards", AwardMessage, true )
 end

function Plugin:addAward(award)
    self.nextAwardId = self.nextAwardId +1
    award.id = self.nextAwardId
    
    self.Awards[#self.Awards +1] = award
end

function Plugin:awardMostDamage()
    local highestDamage = 0
    local highestPlayer = "nobody"
    local highestSteamId = ""
    local totalDamage = nil
    local rating = 0
    
    for key,taulu in pairs(self.PlayersInfos) do
        totalDamage = 0
        
        for i=1, #taulu.weapons do
            totalDamage = totalDamage + taulu.weapons[i].structure_damage
            totalDamage = totalDamage + taulu.weapons[i].player_damage
        end
        
        if math.floor(totalDamage) > math.floor(highestDamage) then
            highestDamage = totalDamage
            highestPlayer = taulu.name
            highestSteamId = taulu.steamId
        end
    end
    
    rating = (highestDamage+1)/350
    
    return {steamId = highestSteamId, rating = rating, message = StringFormat("Most damage done by %s with total damage of %s !", highestPlayer, math.floor(highestDamage))}
end

function Plugin:awardMostKillsAndAssists()
    local total = 0
    local rating = 0
    local highestTotal = 0
    local highestPlayer = "Nobody"
    local highestSteamId = ""
    
    for key,taulu in pairs(self.PlayersInfos) do
        total = taulu.kills + taulu.assists
        if total > highestTotal then
            highestTotal = total
            highestPlayer = taulu.name
            highestSteamId = taulu.steamId
        end
    
    end
    
    rating = highestTotal
    
    return {steamId = highestSteamId, rating = rating, message = StringFormat("%s is deathbringer with total of %s  kills and assists!", highestPlayer, highestTotal)}
end

function Plugin:awardMostConstructed()
    local highestTotal = 0
    local rating = 0
    local highestPlayer = "was not present"
    local highestSteamId = ""
    
    for key,taulu in pairs(self.PlayersInfos) do
        if taulu.total_constructed > highestTotal then
            highestTotal = taulu.total_constructed
            highestPlayer = taulu.name
            highestSteamId = taulu.steamId
        end
    end
    
    rating = (highestTotal+1)/30
    
    return {steamId = highestSteamId, rating = rating, message = StringFormat("Bob the builder: %s !", highestPlayer)}
end


function Plugin:awardMostStructureDamage()
    local highestTotal = 0
    local highestPlayer = "nobody"
    local highestSteamId = ""
    local total = 0
    local rating = 0
    
    for key,taulu in pairs(self.PlayersInfos) do
        total = 0
        
        for i=1, #taulu.weapons do
            total = total + taulu.weapons[i].structure_damage
        end
        
        if math.floor(total) > math.floor(highestTotal) then
            highestTotal = total
            highestPlayer = taulu.name
            highestSteamId = taulu.steamId
        end
    end
    
    rating = (highestTotal+1)/150
    
    return {steamId = highestSteamId, rating = rating, message = StringFormat("Demolition man: %s with %s  structure damage.", highestPlayer, math.floor(highestTotal))}
end


function Plugin:awardMostPlayerDamage()
    local highestTotal = 0
    local highestPlayer = "nobody"
    local highestSteamId = ""
    local total = 0
    local rating = 0
    
    for key,taulu in pairs(self.PlayersInfos) do
        total = 0
        
        for i=1, #taulu.weapons do
            total = total + taulu.weapons[i].player_damage
        end
        
        if math.floor(total) > math.floor(highestTotal) then
            highestTotal = total
            highestPlayer = taulu.name
            highestSteamId = taulu.steamId
        end
    end
    
    rating = (highestTotal+1)/90
    
    return {steamId = highestSteamId, rating = rating, message = StringFormat( " %s was spilling blood worth of %s damage.",highestPlayer, math.floor(highestTotal))}
end


function Plugin:awardBestAccuracy()
    local highestTotal = 0
    local highestPlayer = "nobody"
    local highestSteamId = ""
    local highestTeam = 0
    local total = 0
    local rating = 0
    
    for key,taulu in pairs(self.PlayersInfos) do
        total = 0
        
        for i=1, #taulu.weapons do
            total = total + taulu.weapons[i].player_hit/(taulu.weapons[i].miss+1)
        end
        
        if total > highestTotal then
            highestTotal = total
            highestPlayer = taulu.name
            highestTeam = taulu.teamnumber
            highestSteamId = taulu.steamId
        end
    end
    
    rating = highestTotal*10
    
    if highestTeam == 2 then
        return {steamId = highestSteamId, rating = rating, message = StringFormat("Versed: %s", highestPlayer)}
    else --marine or ready room
         return {steamId = highestSteamId, rating = rating, message = StringFormat("Weapon specialist: %s", highestPlayer)}
    end
end


function Plugin:awardMostJumps()
    local highestTotal = 0
    local highestPlayer = "nobody"
    local highestSteamId = ""
    local rating = 0
    
    for key,taulu in pairs(self.PlayersInfos) do
       
        total = taulu.jumps or 0
      
        if total > highestTotal then
            highestTotal = total
            highestPlayer = taulu.name
            highestSteamId = taulu.steamId
        end
    end
    
    rating = highestTotal/30
        
    return {steamId = highestSteamId, rating = rating, message = StringFormat("%s is jump maniac with %s jumps!", highestPlayer,  highestTotal)}
    
end


function Plugin:awardHighestKillstreak()
    local highestTotal = 0
    local highestPlayer = "nobody"
    local highestSteamId = ""
    
    for key,taulu in pairs(self.PlayersInfos) do
                  
        local total = taulu.highestKillstreak or 0
        
        if total > highestTotal then
            highestTotal = total
            highestPlayer = taulu.name
            highestSteamId = taulu.steamId
        end
    end
    
    local rating = highestTotal
        
    return {steamId = highestSteamId, rating = rating, message = StringFormat("%s became unstoppable with streak of %s kills", highestPlayer, highestTotal)}
end

--Url Method
function Plugin:GetStatsURL()
    return self.Config.WebsiteUrl
end 

--Devour System Methods (see also Timers)

function Plugin:devourClearBuffer()
    self.Devour.Entities = {}
    self.Devour.MovementInfos = {}
end

function Plugin:devourSendStatus()
    if not self.roundStarted then return end
    
    local stime = Shared.GetGMTString(false)
    
    local state = {
        time = stime,
        gametime = Shared.GetTime() - self.GameStartTime,
        map = Shared.GetMapName(),
    }
    
    local dataset = {
        Entity = self.Devour.Entities,
        Movement =  self.Devour.MovementInfos,
        state = state
    }

    local params =
    {
        key = self.Config.ServerKey,
        data = json.encode(dataset)
    }
        
    Shared.SendHTTPRequest(StringFormat("%s/api/sendstatusDevour",self.Config.WebsiteUrl), "POST", params, function(response,status) Plugin:onHTTPResponseFromSendStatus(client,"sendstatus",response,status) end)
    self:devourClearBuffer()    
end

function Plugin:createDevourMovementFrame()

    local data = {}
    
    for key,Client in pairs(Shine.GetAllClients()) do
        local Player = Client:GetControllingPlayer()
        local PlayerPos = Player:GetOrigin()
	    
	    if Player:GetTeamNumber()>0 then
            local movement =
            {
                id = Plugin:GetId(Client),
                x = Plugin:RoundNumber(PlayerPos.x),
                y = Plugin:RoundNumber(PlayerPos.y),
                z = Plugin:RoundNumber(PlayerPos.z),
                wrh = Plugin:RoundNumber(Plugin:GetViewAngle(Player)),
            }
            table.insert(data, movement)
        end	
    end
 
    self.Devour.MovementInfos[self.Devour.Frame] = data
end

function Plugin:createDevourEntityFrame()
    local devourPlayers = {}
    
    for key,Client in pairs(Shine.GetAllClients()) do	
        local Player = Client:GetControllingPlayer()        
        if not Player then return end
        
        local PlayerPos = Player:GetOrigin()
        
        local weapon = "none"
        if Player.GetActiveWeapon and Player:GetActiveWeapon() then
            weapon=Player:GetActiveWeapon():GetMapName() or "none"
        end
        
        if Player:GetTeamNumber()>0 then
            local devourPlayer =
            {
                id = self:GetId(Client),
                name = Player:GetName(),
                team = Player:GetTeamNumber(),
                x = self:RoundNumber(PlayerPos.x),
                y = self:RoundNumber(PlayerPos.y),
                z = self:RoundNumber(PlayerPos.z),
                wrh = self:RoundNumber(Plugin:GetViewAngle(Player)),
                weapon = weapon,
                health = aelf:RoundNumber(Player:GetHealth()),
                armor = self:RoundNumber(Player:GetArmor()),
                pdmg = 0,
                sdmg = 0,
                lifeform = Player:GetMapName(),
                score = Player:GetScore(),
                kills = Player.kills,
                deaths = Player.deaths or 0,
                assists = Player:GetAssistKills(),
                pres = self:RoundNumber(Player:GetResources()),
                ping = Client:GetPing() or 0,
                acc = 0,

            }
            table.insert(devourPlayers, devourPlayer)
        end	
    end
    
    self.Devour.Entities[self.Devour.Frame]= devourPlayers     
end

function Plugin:GetViewAngle(Player)
    
    local angle = Player:GetDirectionForMinimap()/math.pi * 180
    if angle < 0 then angle = 360 + angle end
    if angle > 360 then angle = angle%360 end
    return angle
end

function Plugin:RoundNumber(number)
    local temp = StringFormat("%.2f",number)
    return tonumber(temp)
end