--[[
    Shine Ns2Stats Badges - Client
]]
local Shine = Shine

local StringFormat = string.format

local Plugin = Plugin

function Plugin:Initialise()
    self.Enabled = true
    return true
end

function Plugin:ReceiveNs2statsBagdes(Message)
    if not Message.Name then return end
    if Client.GetOptionString("Badge", "") ~= Message.Name then return end
    Shared.ConsoleCommand("badge nil")
    Shared.ConsoleCommand(StringFormat("badge %s", Message.Name))
end    

function Plugin:Cleanup()
    self.Enabled = false
end 