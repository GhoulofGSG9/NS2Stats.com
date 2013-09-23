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

Plugin.Version = "0.42"

Plugin.HasConfig = true

Plugin.ConfigName = "Ns2Stats.json"
Plugin.DefaultConfig =
{
    Statsonline = true, -- Upload stats?
    SendMapData = false, --Send Mapdata, only set true if minimap is missing at website or is incorrect
    Statusreport = true, -- send Status to NS2Stats every min
    WebsiteUrl = "http://dev.ns2stats.com", --this is url which is shown in player private messages, so its for advertising
    WebsiteDataUrl = "http://dev.ns2stats.com/api/sendlog", --this is url where posted data is send and where it is parsed into database
    WebsiteStatusUrl="http://dev.ns2stats.com/api/sendstatus", --this is url where posted data is send on status sends
    WebsiteApiUrl = "http://dev.ns2stats.com/api",
    Awards = true, --show award
    ShowNumAwards = 4, --how many awards should be shown at the end of the game?
    AwardMsgTime = 20, -- secs to show awards
    LogChat = false, --log the chat?
    ServerKey = "",
    Tags = {}, --Tags added to log 
    Competitive = false, -- tag round as Competitive
    SendTime = 60, --Send after how many min?
    Lastroundlink = "", --Link of last round
    VanillaRanking = false,
}

Plugin.CheckConfig = true

--All needed Hooks

Shine.Hook.SetupClassHook( "DamageMixin", "DoDamage", "OnDamageDealt", "PassivePost" )
Shine.Hook.SetupClassHook("ResearchMixin","TechResearched","OnTechResearched","PassivePost")
Shine.Hook.SetupClassHook("ResearchMixin","SetResearching","OnTechStartResearch","PassivePre")
Shine.Hook.SetupClassHook("ConstructMixin","SetConstructionComplete","OnFinishedBuilt","PassivePost")
Shine.Hook.SetupClassHook("ResearchMixin","OnResearchCancel","addUpgradeAbortedToLog","PassivePost")
Shine.Hook.SetupClassHook("UpgradableMixin","RemoveUpgrade","addUpgradeLostToLog","PassivePost")
Shine.Hook.SetupClassHook("ResourceTower","CollectResources","OnTeamGetResources","PassivePost")  
Shine.Hook.SetupClassHook("DropPack","OnUpdate","OnPickableItemPicked","PassivePre")
Shine.Hook.SetupClassHook("Player","OnJump","OnPlayerJump","PassivePost")
Shine.Hook.SetupClassHook("Player","SetScoreboardChanged","OnPlayerScoreChanged","PassivePost")
--NS2Ranking
Shine.Hook.SetupClassHook("PlayerRanking","GetTrackServer","EnableNS2Ranking","ActivePre")
--Global hooks
Shine.Hook.SetupGlobalHook("RemoveAllObstacles","OnGameReset","PassivePost") 
Shine.Hook.SetupGlobalHook("DestroyEntity","OnEntityDestroyed","PassivePre")  
   
--Score datatable 
Plugin.Players = {}

--values needed by NS2Stats

Plugin.Log = {}
Plugin.LogPartNumber = 1
Plugin.LogPartToSend = 1
RBPSsuccessfulSends = 0
Gamestarted = 0
Plugin.gameFinished = 0
RBPSnextAwardId= 0
RBPSawards = {}
GameHasStarted = false
Currentgamestate = 0
Buildings = {}

--avoids overload at gameend
stoplogging = false

function Plugin:Initialise()
    self.Enabled = true
    
    --create Commands
    Plugin:CreateCommands()
    
    if self.Config.ServerKey == "" then
        Shared.SendHTTPRequest(StringFormat(Plugin.Config.WebsiteUrl, "/api/generateKey/?s=7g94389u3r89wujj3r892jhr9fwj"), "GET",
            function(response) Plugin:acceptKey(response) end)
    end   
    
    --getting server id
    local serverid = Plugin:GetServerId()
    
    --Timers   
    
    --every 1 sec
    --to update Weapondatas
    Shine.Timer.Create( "WeaponUpdate", 1, -1, function()
       Plugin:UpdateWeaponTable()
    end)
    
    -- every 1 min send Server Status    
     Shine.Timer.Create("SendStatus" , 30, -1, function() if Plugin.Config.Statusreport then Plugin:sendServerStatus(Currentgamestate) end end)

    --every x min (Sendtime at config)
    --send datas to NS2StatsServer
    Shine.Timer.Create( "SendStats", 60 * Plugin.Config.SendTime, -1, function()
        if not GameHasStarted then return end
        if Plugin.Config.Statsonline then Plugin:sendData(true) end
    end)
    
    return true 
end

-- NS2VanillaStats Bugging atm
function Plugin:EnableNS2Ranking()
    if Plugin.Config.VanillaRanking then return Plugin.Config.Statsonline end
    return false
end

-- Events

--Game Events

--Game reset
function Plugin:OnGameReset()
        stoplogging = false 
        --Resets all Stats
        Plugin.LogPartNumber = 1
        Plugin.LogPartToSend  = 1
        Gamestarted = 0
        Plugin.gameFinished = 0
        RBPSnextAwardId= 0
        RBPSawards = {}
        GameHasStarted = false
        Currentgamestate = 0
        Plugin.Log = {}
        Plugin.Players = {}
        Items = {}
        -- update stats all connected players       
        for _, client in ipairs(Shine.GetAllClients()) do            
            Plugin:addPlayerToTable(client)        
        end        
        Buildings = {}       
    
    Plugin:addLog({action="game_reset"})
end

--Gamestart
function Plugin:SetGameState( Gamerules, NewState, OldState )
    Currentgamestate = NewState    
    if NewState == kGameState.Started then        
        GameHasStarted = true             
        Gamestarted = Shared.GetTime()
        Plugin:addLog({action = "game_start"})      
       
         --send Playerlist            
         Plugin:addPlayersToLog(0)    
    end
end

--Gameend
function Plugin:EndGame( Gamerules, WinningTeam )     
        if Plugin.Config.Awards then Plugin:sendAwardListToClients() end               
        Buildings = {}
        Plugin:addPlayersToLog(1)
        stoplogging = true      
        local initialHiveTechIdString = "None"            
        if Gamerules.initialHiveTechId then
                initialHiveTechIdString = EnumToString(kTechId, Gamerules.initialHiveTechId)
        end           
        local params =
            {
                version = ToString(Shared.GetBuildNumber()),
                winner = WinningTeam:GetTeamNumber(),
                length = string.format("%.2f", Shared.GetTime() - Gamerules.gameStartTime),
                map = Shared.GetMapName(),
                start_location1 = Gamerules.startingLocationNameTeam1,
                start_location2 = Gamerules.startingLocationNameTeam2,
                start_path_distance = Gamerules.startingLocationsPathDistance,
                start_hive_tech = initialHiveTechIdString,
            }
        Plugin.gameFinished = 1       
        Plugin:AddServerInfos(params)        
        if Plugin.Config.Statsonline then Plugin:sendData(true)  end --senddata also clears log         
end

--Player Events

--PlayerConnected
function Plugin:ClientConfirmConnect( Client)
    
    if not Client then return end
    if Client:GetIsVirtual() then return end
    
    local connect=
    {
        action = "connect",
        steamId = Plugin:GetId(Client)
    }
    Plugin:addLog(connect)
    
    --player disconnected and came back
    local taulu = Plugin:getPlayerByClient(Client)
    
    if not taulu then Plugin:addPlayerToTable(Client)  
    else taulu.dc = false end
    
    self:SendNetworkMessage(Client,"StatsConfig",{WebsiteApiUrl = self.Config.WebsiteApiUrl,SendMapData = self.Config.SendMapData } ,true)
        
end

--PlayerDisconnect
function Plugin:ClientDisconnect(Client)
    if not Client then return end
    local Player = Client:GetPlayer()
    if not Player then return end 
    
    local taulu = Plugin:getPlayerByName(Player:GetName())
    
    if not taulu then return end
    
    taulu.dc = true
    
    local connect={
            action = "disconnect",
            steamId = taulu.steamId,
            score = taulu.score
    }
    Plugin:addLog(connect)
end

--Player changes Name
function Plugin:PlayerNameChange( Player, Name, OldName )

    if not Player or not Name then return end    
    local taulu = Plugin:getPlayerByName(OldName)  
    if not taulu then
        if StringFind(Name,"[BOT]",nill,true) and Player.GetClient then
            Plugin:addPlayerToTable(Player:GetClient())
        end    
        return 
    end    
    if taulu.isBot then return end    
    taulu.name = Name
end

--score changed
function Plugin:OnPlayerScoreChanged(Player,state)
    if not state then return end
 
    local name = Player:GetName()
    if not name then return end  
    
    local taulu = Plugin:getPlayerByName(name)
    if not taulu then
        local client = Player:GetClient()
        if client and not client:GetIsVirtual() then Plugin:ClientConfirmConnect(client) taulu=Plugin:getPlayerByName(name)
        else return end
    end
    
    --check teamchange  
    if taulu.teamnumber ~= Player:GetTeamNumber() then
        taulu.teamnumber = Player:GetTeamNumber()
        local playerJoin =
        {
            action="player_join_team",
            name = taulu.name,
            team = taulu.teamnumber,
            steamId = taulu.steamId,
            score = taulu.score
        }
        Plugin:addLog(playerJoin)
    end
    
    --check if lifeform changed
    if taulu.lifeform ~= Plugin:GetLifeform(Player) then
        taulu.lifeform = Plugin:GetLifeform(Player)
        Plugin:addLog({action = "lifeform_change", name = taulu.name, lifeform = taulu.lifeform, steamId = taulu.steamId})      
    end
    
    Plugin:UpdatePlayerInTable(Player)
end

function Plugin:GetLifeform(Player)
    if not Player then return end
    local Currentlifeform = Player:GetMapName()
    local teamnumber = Player:GetTeamNumber()
    if not teamnumber then teamnumber = 0 end
    if not Player:GetIsAlive() then Currentlifeform = "dead" end
    if teamnumber == 0 then Currentlifeform = "spectator" end
    if Player:GetIsCommander() then
        if teamnumber == 1 then
            Currentlifeform = "marine_commander"
        else Currentlifeform = "alien_commander" end
    end
    return Currentlifeform
end

--Player shoots weapon
function Plugin:OnDamageDealt(DamageMixin, damage, target, point, direction, surface, altMode, showtracer)
   
    local attacker = DamageMixin
    if DamageMixin:GetParent() and DamageMixin:GetParent():isa("Player") then
            attacker = DamageMixin:GetParent()
    elseif HasMixin(DamageMixin, "Owner") and DamageMixin:GetOwner() and DamageMixin:GetOwner():isa("Player") then
            attacker = DamageMixin:GetOwner()
    end
    
    if not attacker:isa("Player") then return end 
    
    if damage == 0 or not target then Plugin:addMissToLog(attacker) return end
    if target:isa("Ragdoll") then Plugin:addMissToLog(attacker) return end
    
    local damageType = kDamageType.Normal
    if DamageMixin.GetDamageType then
            damageType = DamageMixin:GetDamageType() end
            
    local doer = attacker:GetActiveWeapon() 
    if not doer then doer = attacker end    
    Plugin:addHitToLog(target, attacker, doer, damage, damageType)
end

--add Hit
function Plugin:addHitToLog(target, attacker, doer, damage, damageType)
    if attacker:isa("Player") then
        if target:isa("Player") then
            local attacker_id = Plugin:GetId(attacker:GetClient())
            local target_id = Plugin:GetId(target:GetClient())
            if not attacker_id or not target_id then return end            
            local aOrigin = attacker:GetOrigin()
            local tOrigin = target:GetOrigin()
            local weapon = "none"
            if target:GetActiveWeapon() then
                weapon = target:GetActiveWeapon():GetMapName() end        
            local hitLog =
            {
                --general
                action = "hit_player",	
                
                --Attacker
                attacker_steamId = attacker_id,
                attacker_team = attacker:GetTeamNumber(),
                attacker_weapon = string.lower(doer:GetMapName()),
                attacker_lifeform =  string.lower(attacker:GetMapName()),
                attacker_hp = attacker:GetHealth(),
                attacker_armor = attacker:GetArmorAmount(),
                attackerx = string.format("%.4f", aOrigin.x),
                attackery = string.format("%.4f", aOrigin.y),
                attackerz = string.format("%.4f", aOrigin.z),
                
                --Target
                target_steamId = target_id,
                target_team = target:GetTeamNumber(),
                target_weapon = string.lower(weapon),
                target_lifeform = string.lower(target:GetMapName()),
                target_hp = target:GetHealth(),
                target_armor = target:GetArmorAmount(),
                targetx = string.format("%.4f", tOrigin.x),
                targety = string.format("%.4f", tOrigin.y),
                targetz = string.format("%.4f", tOrigin.z),
                
                damageType = damageType,
                damage = damage
                
            }

            Plugin:addLog(hitLog)
            Plugin:weaponsAddHit(attacker, string.lower(doer:GetMapName()), damage)                
            
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
                attacker_weapon = string.lower(doer:GetMapName()),
                attacker_lifeform = string.lower(attacker:GetMapName()),
                attacker_hp = attacker:GetHealth(),
                attacker_armor = attacker:GetArmorAmount(),
                attackerx = string.format("%.4f",  aOrigin.x),
                attackery = string.format("%.4f",  aOrigin.y),
                attackerz = string.format("%.4f",  aOrigin.z),
                            
                structure_id = target:GetId(),
                structure_name = string.lower(target:GetMapName()),	
                structure_x = string.format("%.4f", structureOrigin.x),
                structure_y = string.format("%.4f", structureOrigin.y),
                structure_z = string.format("%.4f", structureOrigin.z),	

                damageType = damageType,
                damage = damage
            }
            
            Plugin:addLog(hitLog)
            Plugin:weaponsAddStructureHit(attacker, string.lower(doer:GetMapName()), damage)
            
        end
    end         
end

--Add miss
function Plugin:addMissToLog(attacker)             
    if attacker and attacker:isa("Player") then
    
        local client = attacker:GetClient()
        if not client then return end
    
        local RBPSplayer = Plugin:getPlayerByClient(client)
        if not RBPSplayer then return end
   
        local weapon = attacker:GetActiveWeaponName() or "none"
        
        --local missLog =
        --{
            
        -- --general
        -- action = "miss",
            
        -- --Attacker
        -- attacker_steamId = RBPSplayer.steamId,
        -- attacker_team = ((HasMixin(attacker, "Team") and attacker:GetTeamType()) or kNeutralTeamType),
        -- attacker_weapon = attackerWeapon,
        -- attacker_lifeform = attacker:GetMapName(),
        -- attacker_hp = attacker:GetHealth(),
        -- attacker_armor = attacker:GetArmorAmount(),
        -- attackerx = RBPSplayer.x,
        -- attackery = RBPSplayer.y,
        -- attackerz = RBPSplayer.z
        --}
        
        ----Lisätään data json-muodossa logiin.
        --Plugin:addLog(missLog)
        --gorge fix
        if weapon == "spitspray" then
            weapon = "spit"
        end
        
        Plugin:weaponsAddMiss(attacker,string.lower(weapon))
    end
end

--weapon add miss
function Plugin:weaponsAddMiss(player,weapon)
        
   local client = player:GetClient()
    if not client then return end
    
    local RBPSplayer = Plugin:getPlayerByClient(client)
            
    local foundId = false
      
    for i=1, #RBPSplayer.weapons do
        if RBPSplayer.weapons[i].name == weapon then
            foundId=i
            break
        end
    end

    if foundId then
        RBPSplayer.weapons[foundId].miss = RBPSplayer.weapons[foundId].miss + 1
    else --add new weapon
        table.insert(RBPSplayer.weapons,
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
    
    local RBPSplayer = Plugin:getPlayerByClient(client)
    if not RBPSplayer then return end
    
    local foundId = false
      
    for i=1, #RBPSplayer.weapons do
        if RBPSplayer.weapons[i].name == weapon then
            foundId=i
            break
        end
    end

    if foundId then
        RBPSplayer.weapons[foundId].player_hit = RBPSplayer.weapons[foundId].player_hit + 1
        RBPSplayer.weapons[foundId].player_damage = RBPSplayer.weapons[foundId].player_damage + damage
        
    else --add new weapon
        table.insert(RBPSplayer.weapons,
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
    
    local RBPSplayer = Plugin:getPlayerByClient(client)
    if not RBPSplayer then return end
    
    local foundId = false
      
    for i=1, #RBPSplayer.weapons do
        if RBPSplayer.weapons[i].name == weapon then
            foundId=i
            break
        end
    end

    if foundId then
        RBPSplayer.weapons[foundId].structure_hit = RBPSplayer.weapons[foundId].structure_hit + 1
        RBPSplayer.weapons[foundId].structure_damage = RBPSplayer.weapons[foundId].structure_damage + damage

    else --add new weapon
        table.insert(RBPSplayer.weapons,
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
    local taulu = Plugin:getPlayerByName(Player.name)
    if not taulu then return end
    taulu.jumps = taulu.jumps + 1   
end

--Chatlogging
function Plugin:PlayerSay( Client, Message )

    if not Plugin.Config.LogChat then return end
    
    Plugin:addLog({
        action = "chat_message",
        team = Client:GetPlayer():GetTeamNumber(),
        steamid = Plugin:GetId(Client),
        name = Client:GetPlayer():GetName(),
        message = Message.message,
        toteam = Message.teamOnly
    })
end

--Team Events

--Pickable Stuff
local Items = {}

--Item is dropped
function Plugin:OnPickableItemCreated(item, player)
    if not item then return end    
    local techId = item:GetTechId()
    local itemname = EnumToString(kTechId, techId)
    if not itemname or itemname == "None" then return end 
    local itemOrigin = item:GetOrigin()
    local steamid = Plugin:getTeamCommanderSteamid(item:GetTeamNumber()) or 0
    
    local ihit = false
    if player then ihit = true end
          
    local newItem =
    {
        commander_steamid = steamid,
        instanthit = ihit,
        id = item:GetId(),
        cost = GetCostForTech(techId),
        team = item:GetTeamNumber(),
        name = itemname,
        action = "pickable_item_dropped",
        x = string.format("%.4f", itemOrigin.x),
        y = string.format("%.4f", itemOrigin.y),
        z = string.format("%.4f", itemOrigin.z)
    }

    Plugin:addLog(newItem)
	
	--istanthit pick
    if ihit then     
        local client = player:GetClient()
        local steamId = 0

        if client then
            steamId = Plugin:GetId(client)
        end
        
        newItem.action = "pickable_item_picked"
        newItem.steamId = steamId
        newItem.commander_steamid = nil
        newItem.instanthit = nil
        
        Plugin:addLog(newItem)
    else Items[item:GetId()] = true end    
end

--Item is picked
function Plugin:OnPickableItemPicked(item,deltaTime)
    if not item then return end
     
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
    if deltaTime==0 then 
            if player then Plugin:OnPickableItemCreated(item, player)       
            else Plugin:OnPickableItemCreated(item, nil) end
            return            
    end
    
    if not player then return end
    
    if not Items[item:GetId()] then return end
    
    Items[item:GetId()] = nil
    
    local techId = item:GetTechId()
    
    local itemname = EnumToString(kTechId, techId)
    if not itemname or itemname == "None" then return end 
    
    local itemOrigin = item:GetOrigin()

    local client = player:GetClient()
    local steamId = 0

    if client then
        steamId = Plugin:GetId(client)
    end

    local newItem =
    {
        steamId = steamId,
        id = item:GetId(),
        cost = GetCostForTech(techId),
        team = player:GetTeamNumber(),
        name = itemname,
        action = "pickable_item_picked",
        x = string.format("%.4f", itemOrigin.x),
        y = string.format("%.4f", itemOrigin.y),
        z = string.format("%.4f", itemOrigin.z)
    }

    Plugin:addLog(newItem)	

end

--Item gets destroyed
function Plugin:OnPickableItemDestroyed(item)
    
    if not item then return end
    
    if not Items[item:GetId()] then return end  
    
    Items[item:GetId()] = nil
    
    local techId = item:GetTechId()
    local structureOrigin = item:GetOrigin()

    local newItem =
    {
        id = item:GetId(),
        cost = GetCostForTech(techId),
        team = item:GetTeamNumber(),
        name = EnumToString(kTechId, techId),
        action = "pickable_item_destroyed",
        x = string.format("%.4f", structureOrigin.x),
        y = string.format("%.4f", structureOrigin.y),
        z = string.format("%.4f", structureOrigin.z)
    }

    Plugin:addLog(newItem)	

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

    Plugin:addLog(newResourceGathered)
end

--Structure Events

--Building Dropped
function Plugin:OnConstructInit( Building )
    
    if not GameHasStarted then return end    
    local techId = Building:GetTechId()
    local name = EnumToString(kTechId, techId)
    
    if name == "Hydra" or name == "GorgeTunnel" then return end --Gorge Buildings
    
    Buildings[Building:GetId()] = true
    
    local strloc = Building:GetOrigin()
    local build=
    {
        action = "structure_dropped",
        id = Building:GetId(),
        steamId = Plugin:getTeamCommanderSteamid(Building:GetTeamNumber()) or 0,       
        team = Building:GetTeamNumber(),        
        structure_cost = GetCostForTech(techId),
        structure_name = name,
        structure_x = string.format("%.4f",strloc.x),
        structure_y = string.format("%.4f",strloc.y),
        structure_z = string.format("%.4f",strloc.z),
    }
    Plugin:addLog(build)
    if Building.isGhostStructure then Plugin:OnGhostCreated(Building) end
end

--Building built
function  Plugin:OnFinishedBuilt(ConstructMixin, builder)

    Buildings[ConstructMixin:GetId()] = true   
    local techId = ConstructMixin:GetTechId()    
    local strloc = ConstructMixin:GetOrigin()
    if builder then
        if builder:isa("Player") then
            local client = builder:GetClient()
        end
    end    
    local team = ConstructMixin:GetTeamNumber()
    local steamId = Plugin:getTeamCommanderSteamid(team) or 0
    local buildername = ""

    if client then               
        local taulu = Plugin:getPlayerByClient(client)        
        if taulu then
            steamId = taulu.steamId
            buildername = taulu.name
            taulu.total_constructed = taulu.total_constructed + 1 end               
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
        structure_x = string.format("%.4f",strloc.x),
        structure_y = string.format("%.4f",strloc.y),
        structure_z = string.format("%.4f",strloc.z),
    }
    Plugin:addLog(build)
end

--Ghost Buildings (Blueprints)

function Plugin:OnGhostCreated(GhostStructureMixin)
     Plugin:ghostStructureAction("ghost_create",GhostStructureMixin,nil)
end

function Plugin:OnGhostDestroyed(GhostStructureMixin)
    Buildings[GhostStructureMixin:GetId()] = nil
   Plugin:ghostStructureAction("ghost_destroy",GhostStructureMixin,nil)
end

--addfunction

function Plugin:ghostStructureAction(action,structure,doer)
        
    if not structure then return end
    local techId = structure:GetTechId()
    local structureOrigin = structure:GetOrigin()
    
    local log = nil
    
    log =
    {
        action = action,
        structure_name = EnumToString(kTechId, techId),
        team = structure:GetTeamNumber(),
        id = structure:GetId(),
        structure_x = string.format("%.4f", structureOrigin.x),
        structure_y = string.format("%.4f", structureOrigin.y),
        structure_z = string.format("%.4f", structureOrigin.z)
    }
    
    if action == "ghost_remove" then
        --something extra here? we can use doer here
    end
    Plugin:addLog(log)    
end

--Upgrade Stuff

--UpgradesStarted
function Plugin:OnTechStartResearch(ResearchMixin, researchNode, player)
    if player:isa("Commander") then
    	local client = player:GetClient()        
        if client then steamId = Plugin:GetId(client) end
        local techId = researchNode:GetTechId()

        local newUpgrade =
        {
        structure_id = ResearchMixin:GetId(),
        commander_steamid = steamId or 0,
        team = player:GetTeamNumber(),
        cost = GetCostForTech(techId),
        upgrade_name = EnumToString(kTechId, techId),
        action = "upgrade_started"
        }

        Plugin:addLog(newUpgrade)
    end
end

--temp to fix Uprades loged multiple times
OldUpgrade = -1

--Upgradefinished
function Plugin:OnTechResearched( ResearchMixin,structure,researchId)
    if not structure then return end
    local researchNode = ResearchMixin:GetTeam():GetTechTree():GetTechNode(researchId)
    local techId = researchNode:GetTechId()
    if  techId == OldUpgrade then return end
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

    Plugin:addLog(newUpgrade)
end

--Upgrade lost
function Plugin:addUpgradeLostToLog(UpgradableMixin, techId)

    local teamNumber = UpgradableMixin:GetTeamNumber()

    local newUpgrade =
    {
        team = teamNumber,
        cost = GetCostForTech(techId),
        upgrade_name = EnumToString(kTechId, techId), 
        action = "upgrade_lost"
    }

    Plugin:addLog(newUpgrade)

end

--Research canceled
function Plugin:addUpgradeAbortedToLog(ResearchMixin, researchNode)
    local techId = researchNode:GetTechId()
    local steamid = Plugin:getTeamCommanderSteamid(ResearchMixin:GetTeamNumber())

    local newUpgrade =
    {
        structure_id = ResearchMixin:GetId(),
        team = ResearchMixin:GetTeamNumber(),
        commander_steamid = steamid,
        cost = GetCostForTech(techId),
        upgrade_name = EnumToString(kTechId, techId),
        action = "upgrade_aborted"
    }

    Plugin:addLog(newUpgrade)

end

--Building recyled
function Plugin:OnBuildingRecycled( Building, ResearchID )
    local structure = Building
    local structureOrigin = structure:GetOrigin()
    local techId = structure:GetTechId()
    
    --from RecyleMixin.lua
        local upgradeLevel = 0
        if structure.GetUpgradeLevel then
            upgradeLevel = structure:GetUpgradeLevel()
        end        
        local amount = GetRecycleAmount(techId, upgradeLevel)
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
        structure_x = string.format("%.4f", structureOrigin.x),
        structure_y = string.format("%.4f", structureOrigin.y),
        structure_z = string.format("%.4f", structureOrigin.z)
    }

    Plugin:addLog(newUpgrade)
end

--Structure gets killed
function Plugin:OnStructureKilled(structure, attacker , doer)
    if not Buildings[structure:GetId()] then return end
    Buildings[structure:GetId()] = nil                
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
            
            local steamId = -1
            
            local player = attacker                 
            local client = Server.GetOwner(player)
            if client then steamId = Plugin:GetId(client) end
            
            local weapon = ""        

            if not doer then weapon = "self"
            else weapon = doer:GetMapName()
            end

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
                structure_x = string.format("%.4f", structureOrigin.x),
                structure_y = string.format("%.4f", structureOrigin.y),
                structure_z = string.format("%.4f", structureOrigin.z)
            }
            Plugin:addLog(newStructure)
                
        --Structure suicide
        else
            local newStructure =
            {
                id = structure:GetId(),
                structure_team = structure:GetTeamNumber(),
                structure_cost = GetCostForTech(techId),
                structure_name = EnumToString(kTechId, techId),
                action = "structure_suicide",
                structure_x = string.format("%.4f", structureOrigin.x),
                structure_y = string.format("%.4f", structureOrigin.y),
                structure_z = string.format("%.4f", structureOrigin.z)
            }
            Plugin:addLog(newStructure)
        end 
end

--Mixed Events 

--Entity Killed
function Plugin:OnEntityKilled(Gamerules, TargetEntity, Attacker, Inflictor, Point, Direction)    
    
    if TargetEntity:isa("Player") then Plugin:addDeathToLog(TargetEntity, Attacker, Inflictor)     
    elseif Buildings[TargetEntity:GetId()] then if TargetEntity.isGhostStructure then Plugin:OnGhostDestroyed(TargetEntity) else Plugin:OnStructureKilled(TargetEntity, Attacker, Inflictor) end       
    end   
end

function Plugin:OnEntityDestroyed(entity)
    if entity:isa("DropPack") then  Plugin:OnPickableItemDestroyed(entity) end
    if Buildings[entity:GetId()] then if entity.isGhostStructure then Plugin:OnGhostDestroyed(entity) end end
end

--add Player death to Log
function Plugin:addDeathToLog(target, attacker, doer)
    if attacker  and doer and target then
        local attackerOrigin = attacker:GetOrigin()
        local targetWeapon = "none"
        local targetOrigin = target:GetOrigin()        
        local target_client = target:GetClient()
        if not target_client then return end        
        if target:GetActiveWeapon() then
                targetWeapon = target:GetActiveWeapon():GetMapName()
        end

        --Jos on quitannu servulta justiin ennen tjsp niin ei ole clienttiä ja erroria pukkaa. (uwelta kopsasin)
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
                attacker_weapon = string.lower(doer:GetMapName()),
                attacker_lifeform = string.lower(attacker:GetMapName()), 
                attacker_hp = attacker:GetHealth(),
                attacker_armor = attacker:GetArmorAmount(),
                attackerx = string.format("%.4f", attackerOrigin.x),
                attackery = string.format("%.4f", attackerOrigin.y),
                attackerz = string.format("%.4f", attackerOrigin.z),
                
                --Target
                target_steamId = Plugin:GetId(target_client) or 0,
                target_team = target:GetTeamType(),
                target_weapon = string.lower(targetWeapon),
                target_lifeform = string.lower(target:GetMapName()), 
                target_hp = target:GetHealth(),
                target_armor = target:GetArmorAmount(),
                targetx = string.format("%.4f", targetOrigin.x),
                targety = string.format("%.4f", targetOrigin.y),
                targetz = string.format("%.4f", targetOrigin.z),
                target_lifetime = string.format("%.4f", Shared.GetTime() - target:GetCreationTime())
            }
            
                --Lisätään data json-muodossa logiin.
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
                    targetx = string.format("%.4f", targetOrigin.x),
                    targety = string.format("%.4f", targetOrigin.y),
                    targetz = string.format("%.4f", targetOrigin.z),
                    target_lifetime = string.format("%.4f", Shared.GetTime() - target:GetCreationTime())	
                }
                Plugin:addLog(deathLog)       
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
                
                --Attacker (

                attacker_weapon = "self",
                attacker_lifeform = attacker:GetMapName(),
                attacker_steamId = Plugin:GetId(attacker_client),
                attacker_team = ((HasMixin(attacker, "Team") and attacker:GetTeamType()) or kNeutralTeamType),
                attacker_hp = attacker:GetHealth(),
                attacker_armor = attacker:GetArmorAmount(),
                attackerx = string.format("%.4f", attackerOrigin.x),
                attackery = string.format("%.4f", attackerOrigin.y),
                attackerz = string.format("%.4f", attackerOrigin.z),
                
                --Target
                target_steamId = Plugin:GetId(target_client),
                target_team = target:GetTeamType(),
                target_weapon = targetWeapon,
                target_lifeform = target:GetMapName(),
                target_hp = target:GetHealth(),
                target_armor = target:GetArmorAmount(),
                targetx = string.format("%.4f", targetOrigin.x),
                targety = string.format("%.4f", targetOrigin.y),
                targetz = string.format("%.4f", targetOrigin.z),
                target_lifetime = string.format("%.4f", Shared.GetTime() - target:GetCreationTime())
            }
            
            Plugin:addLog(deathLog)  
    end
end

--Check Killstreaks
function Plugin:addKill(attacker_steamId,target_steamId)
    for key,taulu in pairs(Plugin.Players) do	
        if taulu.steamId == attacker_steamId then	
            taulu.killstreak = taulu.killstreak +1	
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
    
    if stoplogging and tbl.action ~= "game_ended" then return end      
    if not Plugin.Log then Plugin.Log = {} end
    if not Plugin.Log[Plugin.LogPartNumber] then Plugin.Log[Plugin.LogPartNumber] = "" end
    if not tbl then return end 
    tbl.time = Shared.GetGMTString(false)
    tbl.gametime = Shared.GetTime() - Gamestarted
    Plugin.Log[Plugin.LogPartNumber] = StringFormat("%s%s\n",Plugin.Log[Plugin.LogPartNumber] , json.encode(tbl))	
    
    --avoid that log gets too long also do resend by this way
    if StringLen(Plugin.Log[Plugin.LogPartNumber]) > 1000000 then    
        if Plugin.Config.Statsonline then Plugin:sendData() end
        Plugin.LogPartNumber = Plugin.LogPartNumber + 1
    end
    --local data = RBPSlibc:CompressHuffman(Plugin.Log)
    --Notify("compress size: " .. StringLen(data) .. "decompress size: " .. StringLen(RBPSlibc:Decompress(data)))        
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
    for p = 1, #Plugin.Players do	
        local player = Plugin.Players[p]	
        player.code = 0
    end
    
    tmp.list = Plugin.Players
    
    Plugin:addLog(tmp)
end

--Add server infos
function Plugin:AddServerInfos(params)
    local mods = {}
    local GetMod = Server.GetActiveModId
    for i = 1, Server.GetNumActiveMods() do
        local Mod = GetMod( i )
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
    params.successfulSends = RBPSsuccessfulSends
    params.resendCount = RBPSresendCount
    params.mods = mods
    params.awards = RBPSawards
    params.tags = self.Config.Tags    
    params.private = self.Config.Competitive
    params.autoarrange = false --use Shine plugin settings later?
    local ip = IPAddressToString(Server.GetIpAddress()) 
    if not StringFind(ip,":") then ip = StringFormat(ip, ":", Server.GetPort()) end
    params.serverInfo =
    {
        password = "",
        IP = ip,
        count = 30 --servertick?
    }
    Plugin:addLog(params)
end

local working = false

--send Log to NS2Stats Server
function Plugin:sendData(force)
    
    if not Plugin.Log[Plugin.LogPartToSend] then return end
    if StringLen(Plugin.Log[Plugin.LogPartToSend]) < 1000000 and not force and not Plugin.gameFinished == 1 then return end
    
    if working then return end
    working = true
    
    local params =
    {
        key = self.Config.ServerKey,
        roundlog = Plugin.Log[Plugin.LogPartToSend],
        part_number = Plugin.LogPartToSend ,
        last_part = Plugin.gameFinished,
        map = Shared.GetMapName(),
    }
    Shared.SendHTTPRequest(self.Config.WebsiteDataUrl, "POST", params, function(response,status) Plugin:onHTTPResponseFromSend(client,"send",response,status,params) end)
end

local resendtimes = 0

--Analyze the answer of server
function Plugin:onHTTPResponseFromSend(client,action,response,status,params)	
    local message = json.decode(response)        
    if message then        
        if StringLen(response)>0 then --if we got somedata, that means send was completed                
             if not StringFind(response,"Server log empty",nil, true) then
                 Plugin.Log[Plugin.LogPartToSend ] = nil 
                 Plugin.LogPartToSend = Plugin.LogPartToSend  + 1 
                 RBPSsuccessfulSends = RBPSsuccessfulSends +1
                 working = false
                 Plugin:sendData()                                      
            end
        end
    
        if message.other then
            Notify("[NSStats]: ".. message.other)
        end
    
        if message.error == "NOT_ENOUGH_PLAYERS" then
            Notify("[NS2Stats]: Send failed because of too less players ")
            return
        end	

        if message.link then
            local link = StringFormat("%s%s",Plugin.Config.WebsiteUrl, message.link)
            Shine:Notify( nil, "", "", StringFormat("Round has been saved to NS2Stats : %s" ,link))
            Plugin.Config.Lastroundlink = link
            self:SaveConfig()                
        end	
    elseif response then --if message = nil, json parse failed prob or timeout
        if StringLen(response)>0 then --if we got somedata, that means send was completed
            if not StringFind(response,"Server log empty",nil, true) then
                 Plugin.Log[Plugin.LogPartToSend] = nil 
                 Plugin.LogPartToSend = Plugin.LogPartToSend  + 1
                 RBPSsuccessfulSends = RBPSsuccessfulSends +1
                 working =  false
                 Plugin:sendData()          
            end
        end
        Notify(StringFormat("NS2Stats.org: ( %s )", response))
    elseif not response then --we couldn't reach the NS2Stats Servers
        if params then
            working = false                                
            Shine.Timer.Simple(5, function() Plugin:sendData() end)             
        end              
    end    
end

--Log end 

--Player table functions

    
--add Player to table
function Plugin:addPlayerToTable(client)
    if not client then return end
    
    local entry = Plugin:createPlayerTable(client)
    if not entry then return end
    
    table.insert(Plugin.Players, entry )    
end

--create new entry
function Plugin:createPlayerTable(client)
    if not client.GetPlayer then
        Notify("[NS2Stats Debug]: Tried to create nil player")
        return
    end
    local player = client:GetPlayer()
    if not player then return end
    local taulu= {}
       
    taulu.teamnumber = player:GetTeamNumber() or 0
    taulu.lifeform = Plugin:GetLifeform(player)
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
function Plugin:UpdatePlayerInTable(player)   
    
    local taulu = Plugin:getPlayerByName(player.name)
    if not taulu then return end
    if taulu.dc then return end
    
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
    if player:GetIsAlive() == false then
        taulu.killstreak = 0        
    end
    if not taulu.isbot and player.GetClient and player:GetClient() then taulu.ping = player:GetClient():GetPing() or 0 end        
end


--All search functions
function Plugin:IsClientInTable(client)

    if not client then return false end
    local steamId = Plugin:GetId(client)
    if not steamId then return false end
    
    for p = 1, #Plugin.Players do	
        local player = Plugin.Players[p]	

        if player.steamId == steamId then
            return true
        end	
    end
        
    return false
end


function Plugin:getPlayerClientBySteamId(steamId)
    if not steamId then return end        
    for list, victim in ientitylist(Shared.GetEntitiesWithClassname("Player")) do            
        local client = victim:GetClient()
        if client and Plugin:GetId(client) then
            if Plugin:GetId(client) == tonumber(steamId) then	
                return client	
            end
        end                
     end            
    return nil                            
end

function Plugin:getPlayerByClientId(client)
    if not client  then return end
    local steamId = Plugin:GetId(client)
    if not steamId then return end

    for key,taulu in pairs(Plugin.Players) do        
            if taulu["steamId"] == steamId then return taulu end
    end
end

function Plugin:getTeamCommanderSteamid(teamNumber)
    for key,taulu in pairs(Plugin.Players) do	
        if taulu["isCommander"] and taulu["teamnumber"] == teamNumber then
            return taulu["steamId"]
        end	
    end

    return 0
end

function Plugin:getPlayerBySteamId(steamId)
   if not steamId then return end
   for key,taulu in pairs(Plugin.Players) do         
            if tostring(taulu.steamId) == tostring(steamId)  then return taulu end
   end
end

function Plugin:getPlayerByName(name)
    if not name then return end
    for key,taulu in pairs(Plugin.Players) do        
        if taulu["name"] == name then return taulu end	
    end
end

function Plugin:getPlayerByClient(client)
    if not client then return end
    local steamId = nil
    local name = nil
    if type(client["GetUserId"]) ~= "nil" then
        steamId = Plugin:GetId(client)
    else
        if type(client["GetPlayer"]) ~= "nil" then
                local player = client:GetPlayer()
                local name = player:GetName()
            else
                return
        end
    end

    for key,taulu in pairs(Plugin.Players) do	
        if steamId then
            if taulu["steamId"] == steamId then return taulu end
        end
            
        if name then
            if taulu["name"] == name then return taulu end
        end	
    end
    return nil
end

--Plyer Table end

--GetIds

function Plugin:GetId(client)
    if client and client.GetUserId then     
        if client:GetIsVirtual() then return Plugin:GetIdbyName(client:GetPlayer():GetName()) or 0
        else return client:GetUserId() end
    end 
end

--display warning only once
local a = true

--For Bots
function Plugin:GetIdbyName(Name)

    if not Name then return end
    
    --disable Onlinestats
    if a then Notify( "NS2Stats won't store game with bots. Disabling online stats now!") a=false 
    Plugin.Config.Statsonline = false end
    
    local newId=""
    local letters = " (){}[]/.,+-=?!*1234567890aAbBcCdDeEfFgGhHiIjJkKlLmMnNoOpPqQrRsStTuUvVwWxXyYzZ"
    
    --cut the [Bot]
    local input = tostring(Name)
    input = StringSub(input,6)
    
    --to differ between e.g. name and name (2)   
    input = string.UTF8Reverse(input)
    
    for i=1, #input do
        local char = StringSub(input,i,i)
        local num = StringFind(letters,char,nil,true)
        newId = StringFormat("%s%s",newId,num)        
    end
    
    --fill up the ns2id to 12 numbers
    while StringLen(newId) < 12 do
        newId = StringFormat("%s%s",newId, "0")
    end       
    newId = StringSub(newId, 1 , 12)
    
    --make a int
    newId = tonumber(newId)
    return newId
end

--Ids end

--Timer functions

--Update Weapontalble

function  Plugin:UpdateWeaponTable() 
        if not GameHasStarted then return end         
        for _, client in ipairs(Shine.GetAllClients()) do
            Plugin:updateWeaponData(client)                 
        end       
end   

function Plugin:updateWeaponData(client) 
    if not client then return end
    
    local RBPSplayer = Plugin:getPlayerByClient(client)
    local foundId = false
    if not RBPSplayer then return end    
    local weapon = client:GetPlayer():GetActiveWeaponName() or "none"
    if weapon == "" then weapon = "none" end
    weapon = string.lower(weapon)
    
    for i=1, #RBPSplayer.weapons do
        if RBPSplayer.weapons[i].name == weapon then foundId=i end
    end
    
    if foundId then
        RBPSplayer.weapons[foundId].time = RBPSplayer.weapons[foundId].time + 1
    else --add new weapon
        table.insert(RBPSplayer.weapons,
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

--Timer end

-- Other ns2stats functions

--generates server key
function Plugin:acceptKey(response)
        if not response or response == "" then
            Notify("NS2Stats: Unable to receive unique key from server, stats wont work yet. ")
            Notify("NS2Stats: Server restart might help.")
        else
            local decoded = json.decode(response)
            if decoded and decoded.key then
                self.Config.ServerKey = decoded.key
                Notify(StringFormat("NS2Stats: Key %s has been assigned to this server ", self.Config.ServerKey))
                Notify("NS2Stats: You may use admin command sh_verity to claim this server.")
                Notify("NS2Stats setup complete.")
                self:SaveConfig()
                                
            else
                Notify("NS2Stats: Unable to receive unique key from server, stats wont work yet. ")
                Notify("NS2Stats: Server restart might help.")
                Notify(StringFormat("NS2Stats: Server responded: %s", response))
            end
        end
end

--send Status report to NS2Stats
function Plugin:sendServerStatus(gameState)
    local stime = Shared.GetGMTString(false)
    local gameTime = Shared.GetTime() - Gamestarted
        local params =
        {
            key = self.Config.ServerKey,
            players = json.encode(Plugin.Players),
            state = gameState,
            time = stime,
            gametime = gameTime,
            map = Shared.GetMapName(),
        }

    Shared.SendHTTPRequest(self.Config.WebsiteStatusUrl, "POST", params, function(response,status) Plugin:onHTTPResponseFromSendStatus(client,"sendstatus",response,status) end)	
end

function Plugin:onHTTPResponseFromSendStatus(client,action,response,status)
    --Maybe add Log notice
end

--Other Ns2Stat functions end
local serverid = ""

function Plugin:GetServerId()    
    if serverid == "" then 
        Shared.SendHTTPRequest( StringFormat("%s/server?key=%s",self.Config.WebsiteApiUrl,self.Config.ServerKey),"GET",function(response)
            local Data = json.decode( response )
            if Data then serverid = Data.id or "" end            
        end)
     end
    return serverid    
end

--Commands
function Plugin:CreateCommands()
    
    local ShowPStats = self:BindCommand( "sh_showplayerstats", {"showplayerstats","showstats" }, function(Client)
        Shared.SendHTTPRequest( StringFormat("%s/player?ns2_id=%s", self.Config.WebsiteApiUrl, Plugin:GetId(Client)), "GET",function(response)   
            local Data = json.decode(response)
            local playerid = ""
            if Data then playerid = Data[1].player_page_id or "" end
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
            Shared.SendHTTPRequest(StringFormat("%s/api/verifyServer/%s", self.Config.WebsiteUrl, Plugin:GetId(Client), "?s=479qeuehq2829&key=", self.Config.ServerKey), "GET",
            function(response) ServerAdminPrint(Client,response) end)       
    end)
    Verify:Help ("Sets yourself as serveradmin at NS2Stats.com")
    
    local Tag = self:BindCommand( "sh_addtag","addtag",function(Client,tag)
        table.insert(Plugin.Config.Tags, tag)
        Notify( StringFormat("[NS2Stats]: %S  has been added as Tag to this roundlog", tag))       
    end)    
    Tag:AddParam{ Type = "string",TakeRestOfLine = true,Error = "Please specify a tag to be added.", MaxLength = 30}
    Tag:Help ("Adds the given tag to the Stats")
end

--Awards

function Plugin:makeAwardsList()

    --DO NOT CHANGE ORDER HERE
    Plugin:addAward(Plugin:awardMostDamage())
    Plugin:addAward(Plugin:awardMostKillsAndAssists())
    Plugin:addAward(Plugin:awardMostConstructed())
    Plugin:addAward(Plugin:awardMostStructureDamage())
    Plugin:addAward(Plugin:awardMostPlayerDamage())
    Plugin:addAward(Plugin:awardBestAccuracy())
    Plugin:addAward(Plugin:awardMostJumps())
    Plugin:addAward(Plugin:awardHighestKillstreak())
    
end

function Plugin:sendAwardListToClients()

    --reset and generates Awardlist
    RBPSnextAwardId = 0
    RBPSawards = {}
    Plugin:makeAwardsList()        
    --send highest 10 rating awards
    table.sort(RBPSawards, function (a, b)
          return a.rating > b.rating
        end)
    local AwardMessage = {}
    AwardMessage.message = ""    
    AwardMessage.duration = Plugin.Config.AwardMsgTime
    
    for i=1,Plugin.Config.ShowNumAwards do
        if i > #RBPSawards then break end
        if RBPSawards[i].message then 
            AwardMessage.message = StringFormat("%s%s\n", AwardMessage.message, RBPSawards[i].message )
        end
    end 
    self:SendNetworkMessage(nil, "StatsAwards", AwardMessage, true )
 end

function Plugin:addAward(award)
    RBPSnextAwardId = RBPSnextAwardId +1
    award.id = RBPSnextAwardId
    
    RBPSawards[#RBPSawards +1] = award
end

function Plugin:awardMostDamage()
    local highestDamage = 0
    local highestPlayer = "nobody"
    local highestSteamId = ""
    local totalDamage = nil
    local rating = 0
    
    for key,taulu in pairs(Plugin.Players) do
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
    
    for key,taulu in pairs(Plugin.Players) do
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
    
    for key,taulu in pairs(Plugin.Players) do
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
    
    for key,taulu in pairs(Plugin.Players) do
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
    
    for key,taulu in pairs(Plugin.Players) do
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
    
    for key,taulu in pairs(Plugin.Players) do
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
    local total = 0
    local rating = 0
    
    for key,taulu in pairs(Plugin.Players) do
        total = 0
        
        
        total = taulu.jumps
        
        
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
    local total = 0
    local rating = 0
    
    for key,taulu in pairs(Plugin.Players) do
                  
        total = taulu.highestKillstreak
        
        if total > highestTotal then
            highestTotal = total
            highestPlayer = taulu.name
            highestSteamId = taulu.steamId
        end
    end
    
    rating = highestTotal
        
    return {steamId = highestSteamId, rating = rating, message = StringFormat("%s became unstoppable with streak of %s kills", highestPlayer, highestTotal)}
end

--Url Method
function Plugin:GetStatsURL()
    return Plugin.Config.WebsiteUrl
end 

--Cleanup
function Plugin:Cleanup()
    self.Enabled = false
    Shine.Timer.Destroy("WeaponUpdate")
    Shine.Timer.Destroy("SendStats")
    Shine.Timer.Destroy("SendStatus")
end