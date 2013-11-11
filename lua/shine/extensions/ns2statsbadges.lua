--[[
    Shine Ns2Stats Badges
]]

local Shine = Shine
local Notify = Shared.Message
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
    if not GiveBadge or not kBadges or not Client then return end
 
    local ClientId = Client:GetUserId()
    if ClientId <= 0 then return end
        
    Shared.SendHTTPRequest( StringFormat("http://ns2stats.com/api/oneplayer?ns2_id=%s", ClientId), "GET", function(response)        
        --everyone is a member of the UN
        local nationality  = "UNO"        
        
        --get players nationality from ns2stats.com
        local Data = JsonDecode(response)
        if Data and Data.country and Data.country ~= "null" and Data.country ~= "-" and Data.country ~= "" then                         
            nationality  = Data.country
        end
        
        --set badge at server       
        local setbagde = GiveBadge(ClientId,nationality)
        if not setbagde then return end  
        
        -- send bagde to Clients        
        Server.SendNetworkMessage(Client, "Badge", BuildBadgeMessage(-1, kBadges[nationality]), true)
        
        -- give default badge (disabled)
        GiveBadge(ClientId,"disabled")
        Server.SendNetworkMessage(Client, "Badge", BuildBadgeMessage(-1, kBadges["disabled"]), true)                             
    end)  
end

function Plugin:Cleanup()
    self.Enabled = false
end

Shine:RegisterExtension( "ns2statsbadges", Plugin )