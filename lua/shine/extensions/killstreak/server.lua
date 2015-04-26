--[[
Shine Killstreak Plugin - Server
]]

local Shine = Shine
local StringFormat = string.format

local Plugin = Plugin

Plugin.HasConfig = true
Plugin.ConfigName = "Killstreak.json"
Plugin.DefaultConfig =
{
    SendSounds = false,
    AlienColour = { 255, 125, 0 },
    MarineColour = { 0, 125, 255 },
    KillstreakMinValue = 3,
    StoppedValue = 5,
    StoppedMsg = "%s has been stopped by %s " -- first victim then killer
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:Initialise()
    self.Enabled = true
	
	--create Commands
	self:CreateCommands()
	
	self.Killstreaks = {}
	
    return true
end

function Plugin:OnEntityKilled( _, Victim, Attacker )
    if not Attacker or not Victim or not Victim:isa( "Player" ) then return end
    
    if not Attacker:isa( "Player" ) then 
         local RealKiller = Attacker.GetOwner and Attacker:GetOwner() or nil
         if RealKiller and RealKiller:isa( "Player" ) then
             --noinspection UnusedDef
             Attacker = RealKiller
         else return end
    end
    
    local VictimClient = Victim:GetClient()
    if not VictimClient then return end
      
    if self.Killstreaks[ VictimClient ] and self.Killstreaks[ VictimClient ] >= self.Config.StoppedValue then
        local Colour = { 255, 0, 0 }
        local team = Victim:GetTeamNumber()
        
        if team == 1 then --noinspection UnusedDef
        Colour = self.Config.MarineColour
        elseif team == 2 then Colour = self.Config.AlienColour end
        
        Shine:NotifyColour(nil, Colour[ 1 ], Colour[ 2 ], Colour[ 3 ], StringFormat( self.Config.StoppedMsg, Victim:GetName(), Attacker:GetName() ))
    end
    self.Killstreaks[ VictimClient ] = nil
    
    local AttackerClient = Attacker:GetClient()
    if not AttackerClient then return end
    
    if not self.Killstreaks[ AttackerClient ] then self.Killstreaks[ AttackerClient ] = 1
    else self.Killstreaks[ AttackerClient ] = self.Killstreaks[ AttackerClient ] + 1 end    

    self:CheckForMultiKills( Attacker:GetName(), self.Killstreaks[ AttackerClient ], Attacker:GetTeamNumber() )
end

Shine.Hook.SetupGlobalHook( "RemoveAllObstacles", "OnGameReset", "PassivePost" )

--Gamereset
function Plugin:OnGameReset()
    self.Killstreaks = {}
end

function Plugin:ClientDisconnect( Client )
    self.Killstreaks[ Client ] = nil
end

function Plugin:PostJoinTeam( _, Player )
    local Client = Player:GetClient()
    if not Client then return end
    
    self.Killstreaks[ Client ] = nil
end

local Streaks = {
    [ 3 ] = {
        Text = "%s is on a triple kill!",
        Sound = "Triplekill"
    },    
    [ 5 ] = {
        Text = "%s is on multikill!",
        Sound = "Multikill"
    },    
    [ 6 ] = {
        Text = "%s is on rampage!",
        Sound = "Rampage"
    },
    [ 7 ] = {
        Text = "%s is on a killing spree!",
        Sound = "Killingspree"
    },
    [ 9 ] = {
        Text = "%s is dominating!",
        Sound = "Dominating"
    },
    [ 11 ] = {
        Text = "%s is unstoppable!",
        Sound = "Unstoppable"
    },
    [ 13 ] = {
        Text = "%s made a mega kill!",
        Sound = "Megakill"
    },
    [ 15 ] = {
        Text = "%s made an ultra kill!",
        Sound = "Ultrakill"
    },
    [ 17 ] = {
        Text = "%s owns!",
        Sound = "Ownage"
    },
    [ 18 ] = {
        Text = "%s made a ludicrouskill!",
        Sound = "Ludicrouskill"
    },
    [ 19 ] = {
        Text = "%s is a head hunter!",
        Sound = "Headhunter"
    },
    [ 20 ] = {
        Text = "%s is whicked sick!",
        Sound = "Whickedsick"
    },
    [ 21 ] = {
        Text = "%s made a monster kill!",
        Sound = "Monsterkill"
    },
    [ 23 ] = {
        Text = "Holy Shit! %s got another one!",
        Sound = "Holyshit"
    },
    [ 25 ] = {
        Text = "%s is G o d L i k e !!!",
        Sound = "Godlike"
    }
}

Streaks[ 27 ] = Streaks[ 25 ]
Streaks[ 30 ] = Streaks[ 25 ]
Streaks[ 34 ] = Streaks[ 25 ]
Streaks[ 40 ]  = Streaks[25]
Streaks[ 48 ] = Streaks[ 25 ]
Streaks[ 58 ] = Streaks[ 25 ]
Streaks[ 70 ] = Streaks[ 25 ]
Streaks[ 80 ] = Streaks[ 25 ]
Streaks[ 100 ] = Streaks[ 25 ]
        
function Plugin:CheckForMultiKills( Name, Streak, Teamnumber )
    if Streak < self.Config.KillstreakMinValue then return end
    
    local StreakData = Streaks[ Streak ]

    if not StreakData then return end
    
    local Colour = { 250, 0, 0 }
    
    if Teamnumber then
        if Teamnumber == 1 then --noinspection UnusedDef
        Colour = self.Config.MarineColour
        else Colour = self.Config.AlienColour end
    end
    Shine:NotifyColour( nil, Colour[ 1 ], Colour[ 2 ], Colour[ 3 ], StringFormat( StreakData.Text, Name ) )
    self:PlaySoundForEveryPlayer( StreakData.Sound )
end

function Plugin:PlaySoundForEveryPlayer( SoundName )
    if self.Config.SendSounds then
        self:SendNetworkMessage( nil, "PlaySound",{ Name = SoundName } , true)
    end
end

function Plugin:CreateCommands()
	local CSound = self:BindCommand( "sh_sounds", {"quake", "sounds"} , function( Client, Value)
	
		-- 0 = nil, 1 = false, 2 = true
		if Value == nil then
			Value = 0
		elseif Value then
            --noinspection UnusedDef
            Value = 2
		else
			Value = 1
		end
		
		self:SendNetworkMessage( Client, "Command",{ Name = "Sounds", Value = Value } , true)
	end, true, true )
	CSound:AddParam{ Type = "boolean", Optional = true }
	CSound:Help( "<boolean> Allows you to set if killstreak sounds should be played for you or not." )
	
	local CVolume = self:BindCommand( "sh_soundvolume", {"quakevolume", "soundvolume"}, function( Client, Value)
		self:SendNetworkMessage( Client, "SoundVolume",{ Name = "Sounds", Value = Value } , true)
	end, true, true)
	CVolume:AddParam{ Type = "number", Min = 0, Max = 200, Round= true, Error = "Please set a value between 0 and 200. Any value outside this limit is not allowed" }
	CVolume:Help( "<volume in percent> Set the killstreak's sound volume to whatever you like between 0 and 200%" )
end

function Plugin:Cleanup()
    self.Killstreaks = nil

    self.BaseClass.Cleanup( self )

    self.Enabled = false
end