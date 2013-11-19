--[[
    Shine Ns2Stats Badges
]]

local Shine = Shine
local Notify = Shared.Message
local StringFormat = string.format
local JsonDecode = json.decode
local HTTPRequest = Shared.SendHTTPRequest

local Plugin = {}

Plugin.Version = "1.5"
Plugin.DefaultState = false

Plugin.HasConfig = true

Plugin.ConfigName = "ns2statsbadges.json"
Plugin.DefaultConfig =
{
    flags = true,
    steambadges = false,
}

Plugin.CheckConfig = true

function Plugin:Initialise()    
    self.Enabled = true
    return true
end

local function FindCharactersBetween( Response, OpeningCharacters, ClosingCharacters )
        local Result

        local IndexOfOpeningCharacters = Response:find( OpeningCharacters )
        
        if IndexOfOpeningCharacters then
                local FoundCharacters = Response:sub( IndexOfOpeningCharacters + #OpeningCharacters )
                local IndexOfClosingCharacters = FoundCharacters:find( ClosingCharacters )
        
                if IndexOfClosingCharacters then
                        FoundCharacters = FoundCharacters:sub( 1, IndexOfClosingCharacters - 1 )
                        FoundCharacters = StringTrim( FoundCharacters )

                        Result = FoundCharacters
                end
        end
        
        return Result
end

local function GetSteamBadgeName( Response )
        return FindCharactersBetween( Response, "<div class=\"badge_info_title\">", "</div>" )
end

local function SetSteamBagde( Client,ClientId,profileurl )
    HTTPRequest( StringFormat("%s/gamecards/4920", profileurl), "GET", function(response)
        local badgename = GetSteamBadgeName( response )        
        if badgename then badgename = StringFormat("steam_%s",badgename)
        else return end
       
        local setbagde = GiveBadge(ClientId,badgename)
        if not setbagde then return end  
            
        -- send bagde to Clients        
        Server.SendNetworkMessage(Client, "Badge", BuildBadgeMessage(-1, kBadges[badgename]), true)
        
        -- give default badge (disabled)
        GiveBadge(ClientId,"disabled")
        Server.SendNetworkMessage(Client, "Badge", BuildBadgeMessage(-1, kBadges["disabled"]), true) 
    end)
end

function Plugin:ClientConnect(Client)
    if not GiveBadge or not kBadges or not Client then return end
 
    local ClientId = Client:GetUserId()
    if ClientId <= 0 then return end
    
    HTTPRequest( StringFormat("http://ns2stats.com/api/oneplayer?ns2_id=%s", ClientId), "GET", function(response)        
        --everyone is a member of the UN
        local nationality  = "UNO"        
        
        --get players nationality from ns2stats.com
        local Data = JsonDecode(response)
        if Data and Data.country and Data.country ~= "null" and Data.country ~= "-" and Data.country ~= "" then                         
            nationality  = Data.country
        end
        
        --set badge at server       
        local setbagde
        if self.Config.flags then setbagde = GiveBadge(ClientId,nationality) end
        if self.Config.steambadges and Data.steam_url then
           SetSteamBagde(Client,ClientId,Data.steam_url)        
        end
        
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