--[[
    Shine Ns2Stats Bagdes
]]

local Shine = Shine
local StringFormat = string.format
local JsonDecode = json.decode 

local Plugin = {}

Plugin.Version = "1.0"
Plugin.DefaultState = false

function Plugin:Initialise()    
    self.Enabled = true
    return true
end

function Plugin:ClientConnect(Client)   
    local ClientId = Client:GetUserId()
    if ClientId <= 0 then return end
    
    Shared.SendHTTPRequest( StringFormat("http://ns2stats.com/api/player?ns2_id=%s", ClientId), "GET",function(response)  
        local Data = JsonDecode(response)
        
        --get players nationality
        local nationality            
        if Data then nationality = Data[1].nationality end        
        if not nationality then return end        
        nationality = nationality:upper()
        
        --set bagde at server
        if not GiveBadge or not kBadges then return end
        local setbagde = GiveBadge(ClientId,nationality)
        if not setbagde then return end
        
        -- send bagde to Playerclient
        Server.SendNetworkMessage(Client, "Badge", {clientIndex = -1, badge = kBadges[nationality]}, true)                     
    end)    
end

function Plugin:Cleanup()
    self.Enabled = false
end

Shine:RegisterExtension( "ns2statsbagdes", Plugin )