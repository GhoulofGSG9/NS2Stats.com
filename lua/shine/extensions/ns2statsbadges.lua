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
    self.Retries = {}
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
    Shared.SendHTTPRequest( StringFormat("%s/gamecards/4920", profileurl), "GET", function(response)
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
    
    --everyone is a member of the UN
    local nationality  = "UNO"
    self.Retries[ ClientId ] = 1

    local function SetBadges()
        if not self.Config.flags or not GiveBadge(ClientId,nationality) then return end
        -- send bagde to Clients        
        Server.SendNetworkMessage(Client, "Badge", BuildBadgeMessage(-1, kBadges[nationality]), true)
            
        -- give default badge (disabled)
        GiveBadge(ClientId,"disabled")
        Server.SendNetworkMessage(Client, "Badge", BuildBadgeMessage(-1, kBadges["disabled"]), true)  
    end
    
    local function GetBadges()
        if self.Retries[ ClientId ] >= 5 then
           SetBadges()
           return            
        end
        self.Retries[ ClientId ] = self.Retries[ ClientId ] + 1
        
        HTTPRequest( StringFormat("http://ns2stats.com/api/oneplayer?ns2_id=%s", ClientId), "GET", function(response)         
            --get players nationality from ns2stats.com
            local Data = JsonDecode(response)
            if Data and Data.country and Data.country ~= "null" and Data.country ~= "-" and Data.country ~= "" then                         
                nationality  = Data.country
                SetBadges()
            end
            
            if self.Config.steambadges and Data and Data.steam_url then
               SetSteamBagde(Client,ClientId,Data.steam_url)        
            end
                           
        end,GetBadges)
    end    
    GetBadges()
end

function Plugin:Cleanup()
    self.Enabled = false
end

Shine:RegisterExtension( "ns2statsbadges", Plugin )