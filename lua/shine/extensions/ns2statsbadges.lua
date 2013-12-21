--[[
    Shine Ns2Stats Badges
]]

local Shine = Shine
local Notify = Shared.Message
local StringFormat = string.format
local JsonDecode = json.decode
local HTTPRequest = Shine.TimedHTTPRequest

local Plugin = {}

Plugin.Version = "1.5"

Plugin.HasConfig = true

Plugin.ConfigName = "ns2statsbadges.json"
Plugin.DefaultConfig =
{
    flags = true,
    steambadges = false,
}

Plugin.CheckConfig = true

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

--fix for no badge showing up
local function AvoidEmptyBadge(Client, Badge)
    if getClientBadgeEnum(Client) == kBadges.None then
       setClientBadgeEnum(kBadges[Badge]) 
    end
end

local function SetSteamBagde( Client,ClientId,profileurl )

    --normal
    Shared.SendHTTPRequest( StringFormat("%s/gamecards/4920", profileurl), "GET", function(response)
        local badgename = GetSteamBadgeName( response )        
        if badgename then badgename = StringFormat("steam_%s",badgename)
        else return end
       
        local setbagde = GiveBadge(ClientId,badgename)
        if not setbagde then return end  
            
        -- send bagde to Clients        
        Server.SendNetworkMessage(Client, "Badge", BuildBadgeMessage(-1, kBadges[badgename]), true)
        AvoidEmptyBadge(Client, badgename)
        
        -- give default badge (disabled)
        GiveBadge(ClientId,"disabled")
        Server.SendNetworkMessage(Client, "Badge", BuildBadgeMessage(-1, kBadges["disabled"]), true) 
    end)
    
    --foil
    Shared.SendHTTPRequest( StringFormat("%s/gamecards/4920?border=1", profileurl), "GET", function(response)
        local badgename = GetSteamBadgeName( response )        
        if badgename then badgename = StringFormat("steam_%s",badgename)
        else return end
       
        local setbagde = GiveBadge(ClientId,badgename)
        if not setbagde then return end  
            
        -- send bagde to Clients        
        Server.SendNetworkMessage(Client, "Badge", BuildBadgeMessage(-1, kBadges[badgename]), true)
        AvoidEmptyBadge(Client, badgename)
        
        -- give default badge (disabled)
        GiveBadge(ClientId,"disabled")
        Server.SendNetworkMessage(Client, "Badge", BuildBadgeMessage(-1, kBadges["disabled"]), true) 
    end)
end

local Retries = {}

function Plugin:ClientConnect(Client)
    if not GiveBadge or not kBadges or not Client then return end
 
    local ClientId = Client:GetUserId()
    if ClientId <= 0 then return end
    
    --everyone is a member of the UN
    local nationality  = "UNO"
    Retries[ ClientId ] = 1

    local function SetBadges()
        if not self.Config.flags or not GiveBadge(ClientId,nationality) then return end
        -- send bagde to Client
        Server.SendNetworkMessage(Client, "Badge", BuildBadgeMessage(-1, kBadges[nationality]), true)
        AvoidEmptyBadge(Client, nationality)
            
        -- give default badge (disabled)
        GiveBadge(ClientId,"disabled")
        Server.SendNetworkMessage(Client, "Badge", BuildBadgeMessage(-1, kBadges["disabled"]), true)  
    end
    
    local function GetBadges()
        if Retries[ ClientId ] >= 3 then
           SetBadges()
           return            
        end
        Retries[ ClientId ] = Retries[ ClientId ] + 1
        
        HTTPRequest( StringFormat("http://ns2stats.com/api/oneplayer?ns2_id=%s", ClientId), "GET", function(response)
            --player still connected?
            if not Shine:IsValidClient(Client) then return end
            
             --get players nationality from ns2stats.com
            local Data = JsonDecode(response)
            if Data and Data.country and string.len(tostring(Data.country))>= 2 and Data.country ~= "null" then                        
                nationality  = Data.country                
            end
            
            SetBadges()
            
            if self.Config.steambadges and Data and Data.steam_url then
               SetSteamBagde(Client,ClientId,Data.steam_url)        
            end
                           
        end,function() GetBadges() end,10)
    end    
    GetBadges()
end

Shine:RegisterExtension( "ns2statsbadges", Plugin )