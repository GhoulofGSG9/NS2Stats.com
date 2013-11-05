--[[
    Shine Ns2Stats Badges -Server
]]

local Shine = Shine
local StringFormat = string.format
local JsonDecode = json.decode 

local Plugin = Plugin

function Plugin:Initialise()    
    self.Enabled = true
    return true
end

function Plugin:ClientConnect(Client)
    if not GiveBadge or not kBadges then return end
 
    local ClientId = Client:GetUserId()
    if ClientId <= 0 then return end
        
    Shared.SendHTTPRequest( StringFormat("http://ns2stats.com/api/player?ns2_id=%s", ClientId), "GET", function(response) 
        
        local Data = JsonDecode(response)            
        if not Data then return end
        
        --get players nationality
        local nationality  = Data[1].nationality        
        if not nationality then return end        
        nationality = nationality:upper()
        
        --set badge at server        
        local setbagde = GiveBadge(ClientId,nationality)
        if not setbagde then return end  
        
        -- send bagde to Clients
        setClientBadgeEnum(Client,kBadges[nationality])
        Server.SendNetworkMessage(Client, "Badge", BuildBadgeMessage(-1, kBadges[nationality]), true)
        Plugin:SendNetworkMessage(Client,"Ns2statsBagdes",{Name = nationality } ,true)                        
    end)  
end

function Plugin:Cleanup()
    self.Enabled = false
end