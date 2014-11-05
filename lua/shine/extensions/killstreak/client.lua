--[[
Shine Killstreak Plugin - Client
]]

local Shine = Shine
local Notify = Shared.Message
local StringFormat = string.format

local Plugin = Plugin

Plugin.HasConfig = true
Plugin.ConfigName = "Killstreak.json"

Plugin.DefaultConfig = {
    PlaySounds = true,
    SoundVolume = 100
}
Plugin.CheckConfig = true
Plugin.SilentConfigSave = true

function Plugin:Initialise()
    self.Enabled = true
	
	--Sounds
	self.Sounds = {       
		[ "Triplekill" ] = "sound/killstreaks.fev/killstreaks/triplekill",
		[ "Multikill" ] =  "sound/killstreaks.fev/killstreaks/multikill",
		[ "Rampage" ] =  "sound/killstreaks.fev/killstreaks/rampage",
		[ "Killingspree" ] =  "sound/killstreaks.fev/killstreaks/killingspree",
		[ "Dominating" ] =  "sound/killstreaks.fev/killstreaks/dominating",
		[ "Unstoppable" ] =  "sound/killstreaks.fev/killstreaks/unstoppable",
		[ "Megakill" ] =  "sound/killstreaks.fev/killstreaks/megakill",
		[ "Ultrakill" ] =  "sound/killstreaks.fev/killstreaks/ultrakill",
		[ "Ownage" ] =  "sound/killstreaks.fev/killstreaks/ownage",
		[ "Ludicrouskill" ] =  "sound/killstreaks.fev/killstreaks/ludicrouskill",
		[ "Headhunter" ] =  "sound/killstreaks.fev/killstreaks/headhunter",
		[ "Whickedsick" ] =  "sound/killstreaks.fev/killstreaks/whickedsick",
		[ "Monsterkill" ] =  "sound/killstreaks.fev/killstreaks/monsterkill",
		[ "Holyshit" ] =  "sound/killstreaks.fev/killstreaks/holyshit",
		[ "Godlike" ] =  "sound/killstreaks.fev/killstreaks/godlike" 
	}
	
	for _, Sound in pairs( self.Sounds ) do
		Client.PrecacheLocalSound( Sound )
	end
	
	if Shine.AddStartupMessage then 
		Shine.AddStartupMessage( StringFormat( "Shine is set to %s killstreak sounds. You can change this with sh_sounds", self.Config.PlaySounds and "play" or "mute" ))
		
		if self.Config.SoundVolume < 0 or self.Config.SoundVolume > 200 or self.Config.SoundVolume % 1 ~= 0 then
		   Shine.AddStartupMessage( "Warning: The set Sound Volume was outside the limit of 0 to 200" )
		   self.Config.SoundVolume = 100
		end
		 
		if self.Config.PlaySounds then Shine.AddStartupMessage( StringFormat( "Shine is set to play killstreak sounds with a volume of %s . You can change this with sh_setsoundvolume.",self.Config.SoundVolume)) end
	end
	
    return true
end

function Plugin:ReceivePlaySound( Message )
    if not Message.Name then return end
	
    if self.Config.PlaySounds then    
        StartSoundEffect( self.Sounds[ Message.Name ], self.Config.SoundVolume / 100 )
    end
end

function Plugin:ReceiveCommand( Message )
	local Commands = {
		["Sounds"] = function( Value )
			if Value == 0 then 
				Value = not self.Config.PlaySounds
			else 
				Value = Value == 2
			end
			
			self.Config.PlaySounds = Bool
			self:SaveConfig()
			
			Notify( StringFormat( "[Shine] Playing Killstreak Sounds has been %s.", Bool and "enabled" or "disabled" )) 
		end,
		["SoundVolume"] = function( Volume )
			self.Config.SoundVolume = Volume    
			self:SaveConfig()
    
			Notify( StringFormat( "[Shine] Killstreak Sounds Volume has been set to %s.", Volume ))
		end		
	}
	
	if Commands[ Message.Name ] and Message.Value then
		Commands[ Message.Name ]( Message.Value )
	end	
end

function Plugin:Cleanup()
    self.BaseClass.Cleanup( self )
	
    self.Sounds = nil
	
    self.Enabled = false
end