--[[
    Shine Ns2Stats Badges
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
   Plugin:SetFlagBadge(Client)    
end

function Plugin:SetFlagBadge(Client,trynr)    
    if not GiveBadge or not kBadges then return end
    
    local ClientId = Client:GetUserId()    
    if ClientId<=0 then return end
    
    if not trynr then trynr = 0 end
    if trynr > 5 then return end
    
    Shared.SendHTTPRequest( StringFormat("http://ns2stats.com/api/player?ns2_id=%s", ClientId), "GET", function(response) 

        local Data = JsonDecode(response)            
        if not Data then Shine.Timer.Simple(5,Plugin:SetFlagBadge(Client,trynr+1)) return end
        
        --get players nationality
        local nationality  = Data[1].nationality        
        if not nationality then return end        
        nationality = nationality:upper()
        
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