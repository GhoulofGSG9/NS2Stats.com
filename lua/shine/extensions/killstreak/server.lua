--[[
Shine Killstreak Plugin - Server
]]

local Shine = Shine
local Notify = Shared.Message

local Plugin = Plugin

Plugin.Version = "1.0"

Plugin.HasConfig = true

Plugin.ConfigName = "Killstreak.json"
Plugin.DefaultConfig =
{
    SendSounds = false
}

Plugin.CheckConfig = true

local Killstreaks = {}
function Plugin:Initialise()
    self.Enabled = true
end

function 
function Plugin:OnEntityKilled( Gamerules, Victim, Attacker, Inflictor, Point, Dir )
    if not Attacker or not Victim then return end
    if not Victim:isa("Player") then return end
    
    if not Attacker:isa("Player") then 
         local realKiller = (Attacker.GetOwner and Attacker:GetOwner()) or nil
         if realKiller and realKiller:isa("Player") then
            Attacker = realKiller
         else return
         end
    end
    
    local VictimClient = Server.GetOwner( Victim )
    Killstreaks[VictimClient:GetUserId()] = nil
    
    local AttackerClient = Server.GetOwner( Attacker )
    if not AttackerClient then return end
    
    local steamId = AttackerClient:GetUserId()
    if not steamId or steamId<=0 then return end
    
    if not Killstreaks[steamId] then Killstreaks[steamId] = 1
    else Killstreaks[steamId] = Killstreaks[steamId] + 1 end
    
    local name = Attacker:GetName()
    Plugin:checkForMultiKills(name,Killstreaks[steamId])      
end

function Plugin:checkForMultiKills(name,streak)
        
    local text = ""
    
    if streak == 3 then
        text = name .. " is on triple kill!"
        Plugin:playSoundForEveryPlayer(ShineSoundTriplekill)
    elseif streak == 5 then
        text = name .. " is on multikill!"
        Plugin:playSoundForEveryPlayer(ShineSoundMultikill)
    elseif streak == 6 then
        text = name .. " is on rampage!"
        Plugin:playSoundForEveryPlayer(ShineSoundRampage)
    elseif streak == 7 then
        text = name .. " is on a killing spree!"
        Plugin:playSoundForEveryPlayer(ShineSoundKillingspree)
    elseif streak == 9 then
        text = name .. " is dominating!"
        Plugin:playSoundForEveryPlayer(ShineSoundDominating)
    elseif streak == 11 then
        text = name .. " is unstoppable!"
        Plugin:playSoundForEveryPlayer(ShineSoundUnstoppable)
    elseif streak == 13 then
        text = name .. " made a mega kill!"
        Plugin:playSoundForEveryPlayer(ShineSoundMegakill)
    elseif streak == 15 then
        text = name .. " made an ultra kill!"
        Plugin:playSoundForEveryPlayer(ShineSoundUltrakill)
    elseif streak == 17 then
        text = name .. " owns!"
        Plugin:playSoundForEveryPlayer(ShineSoundOwnage)
    elseif streak == 18 then
        text = name .. " made a ludicrouskill!"
        Plugin:playSoundForEveryPlayer(ShineSoundLudicrouskill)
    elseif streak == 19 then
        text = name .. " is a head hunter!"
        Plugin:playSoundForEveryPlayer(ShineSoundHeadhunter)
    elseif streak == 20 then
        text = name .. " is whicked sick!"
        Plugin:playSoundForEveryPlayer(ShineSoundWhickedsick)
    elseif streak == 21 then
        text = name .. " made a monster kill!"
        Plugin:playSoundForEveryPlayer(ShineSoundMonsterkill)
    elseif streak == 23 then
        text = "Holy Shit! " .. name .. " got another one!"
        Plugin:playSoundForEveryPlayer(ShineSoundHolyshit)
    elseif streak == 25 then
        text = name .. " is G o d L i k e !!!"
        Plugin:playSoundForEveryPlayer(ShineSoundGodlike)
    elseif streak == 27 then
        text = name .. " is G o d L i k e !!!"
        Plugin:playSoundForEveryPlayer(ShineSoundGodlike)
    elseif streak == 30 then
        text = name .. " is G o d L i k e !!!"
        Plugin:playSoundForEveryPlayer(ShineSoundGodlike)
    elseif streak == 34 then
        text = name .. " is G o d L i k e !!!"
        Plugin:playSoundForEveryPlayer(ShineSoundGodlike)
    elseif streak == 40 then
        text = name .. " is G o d L i k e !!!"
        Plugin:playSoundForEveryPlayer(ShineSoundGodlike)
    elseif streak == 48 then
        text = name .. " is G o d L i k e !!!"
        Plugin:playSoundForEveryPlayer(ShineSoundGodlike)
    elseif streak == 58 then
        text = name .. " is G o d L i k e !!!"
        Plugin:playSoundForEveryPlayer(ShineSoundGodlike)
    elseif streak == 70 then
        text = name .. " is G o d L i k e !!!"
        Plugin:playSoundForEveryPlayer(ShineSoundGodlike)
    elseif streak == 80 then
        text = name .. " is G o d L i k e !!!"
        Plugin:playSoundForEveryPlayer(ShineSoundGodlike)
    elseif streak == 100 then
        text = name .. " is G o d L i k e !!!"
        Plugin:playSoundForEveryPlayer(ShineSoundGodlike)
    end
    Shine:NotifyColour(nil,255,0,0,text)
end

function Plugin:playSoundForEveryPlayer(name)
    if self.Config.SendSounds then
        self:SendNetworkMessage(nil,"PlaySound",{Neme = name } ,true)
    end
end

function Plugin:Cleanup()
    self.Enabled = false
end    
    