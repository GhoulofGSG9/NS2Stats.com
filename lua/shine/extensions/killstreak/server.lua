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
    return true
end

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
    local victimId = VictimClient:GetUserId() or 0
    if victimId == 0 then victimId = Plugin:GetIdbyName(Victim:GetName()) or 0 end
    if victimId>0 then
        local vname        
        if Killstreaks[victimId] and Killstreaks[victimId] > 3 then  vname = Victim:GetName() end
        Killstreaks[victimId] = nil 
        if vname then Shine:NotifyColour(nil,255,0,0,vname .. " has been stopped") end
    else return end
    
    local AttackerClient = Server.GetOwner( Attacker )
    if not AttackerClient then return end
    
    local steamId = AttackerClient:GetUserId() or 0
    local name = Attacker:GetName()
    if steamId == 0 then steamId = Plugin:GetIdbyName(name) end
    if not steamId or steamId<=0 then return end
    
    if not Killstreaks[steamId] then Killstreaks[steamId] = 1
    else Killstreaks[steamId] = Killstreaks[steamId] + 1 end    

    Plugin:checkForMultiKills(name,Killstreaks[steamId])      
end

Shine.Hook.SetupGlobalHook("RemoveAllObstacles","OnGameReset","PassivePost")

--Gamereset
function Plugin:OnGameReset()
    Killstreaks = {}
end

--For Bots
function Plugin:GetIdbyName(Name)

    if not Name then return -1 end
    
    local newId=""
    local letters = " (){}[]/.,+-=?!*1234567890aAbBcCdDeEfFgGhHiIjJkKlLmMnNoOpPqQrRsStTuUvVwWxXyYzZ"
    
    --cut the [Bot]
    local input = tostring(Name)
    input = input:sub(6,#input)
    
    --to differ between e.g. name and name (2)
    input = string.reverse(input)
    
    for i=1, #input do
        local char = input:sub(i,i)
        local num = string.find(letters,char,nil,true)
        newId = newId .. tostring(num)
    end
    
    --fill up the ns2id to 12 numbers
    while string.len(newId) < 12 do
        newId = newId .. "0"
    end
    newId = string.sub(newId, 1 , 12)
    
    --make a int
    newId = tonumber(newId)
    return newId
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
    