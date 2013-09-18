--[[
Shine Killstreak Plugin - Client
]]

local Shine = Shine
local Notify = Shared.Message

local Plugin = Plugin

Plugin.Version = "1.0"

function Plugin:Initialise()
    self.Enabled = true
    
    if Shine.Config.PlayShineSounds == nil then
        Shine.Config.PlayShineSound = true
        Shine:SaveClientBaseConfig()
    end
    
    if Shine.Config.PlayShineSounds then
        --precache ShineSounds        
        ShineSoundTriplekill = PrecacheAsset("lua/shine/extensions/killstreaks/sound/killstreaks.fev/killstreaks/triplekill")
        ShineSoundMultikill = PrecacheAsset("lua/shine/extensions/killstreaks/sound/killstreaks.fev/killstreaks/multikill")
        ShineSoundRampage = PrecacheAsset("lua/shine/extensions/killstreaks/sound/killstreaks.fev/killstreaks/rampage")
        ShineSoundKillingspree = PrecacheAsset("lua/shine/extensions/killstreaks/sound/killstreaks.fev/killstreaks/killingspree")
        ShineSoundDominating = PrecacheAsset("lua/shine/extensions/killstreaks/sound/killstreaks.fev/killstreaks/dominating")
        ShineSoundUnstoppable = PrecacheAsset("lua/shine/extensions/killstreaks/sound/killstreaks.fev/killstreaks/unstoppable")
        ShineSoundMegakill = PrecacheAsset("lua/shine/extensions/killstreaks/sound/killstreaks.fev/killstreaks/megakill")
        ShineSoundUltrakill = PrecacheAsset("lua/shine/extensions/killstreaks/sound/killstreaks.fev/killstreaks/ultrakill")
        ShineSoundOwnage = PrecacheAsset("lua/shine/extensions/killstreaks/sound/killstreaks.fev/killstreaks/ownage")
        ShineSoundLudicrouskill = PrecacheAsset("lua/shine/extensions/killstreaks/sound/killstreaks.fev/killstreaks/ludicrouskill")
        ShineSoundHeadhunter = PrecacheAsset("lua/shine/extensions/killstreaks/sound/killstreaks.fev/killstreaks/headhunter")
        ShineSoundWhickedsick = PrecacheAsset("lua/shine/extensions/killstreaks/sound/killstreaks.fev/killstreaks/whickedsick")
        ShineSoundMonsterkill = PrecacheAsset("lua/shine/extensions/killstreaks/sound/killstreaks.fev/killstreaks/monsterkill")
        ShineSoundHolyshit = PrecacheAsset("lua/shine/extensions/killstreaks/sound/killstreaks.fev/killstreaks/holyshit")
        ShineSoundGodlike = PrecacheAsset("ShineSound/killstreaks.fev/killstreaks/godlike")        
    end
end

function Plugin:ReceivePlaySound(Message)
    if not Message.Name then return end
    if Shine.Config.PlayShineSounds then
        StartSoundEffect(Message.Name)
    end
end

local DisableSounds = Shine:RegisterClientCommand( "sh_disablesounds", function( Bool )
  Shine.Config.PlayShineSounds = Bool

  Notify( StringFormat( "[Shine] Playing Shine Sounds has been %s.", Bool and "disabled" or "enabled" ) )

  Shine:SaveClientBaseConfig() 
end)

function Plugin:Cleanup()
    self.Enabled = false
end    
    